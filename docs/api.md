# API v1

Para integração com o SIAP e outros sistemas.

A referência viva fica no próprio serviço, gerada a partir do código — **ela não
envelhece à parte da implementação**:

| Rota | Uso |
| --- | --- |
| `GET /api/docs` | Swagger. Clique em **Authorize**, cole o token e teste as rotas pelo navegador |
| `GET /api/redoc` | A mesma documentação em leitura corrida — é o que se manda para quem vai integrar |
| `GET /api/openapi.json` | OpenAPI cru, para gerar cliente com `openapi-generator` |

As três são públicas: mostram o **formato** da API, nunca dado de processo.

---

## Autenticação

Token Bearer em todas as rotas, exceto `/health`:

```http
Authorization: Bearer <token>
```

O token é emitido com `gerar_credencial.py api <rótulo>` — ver
[Instalação](instalacao.md#2-gerar-as-credenciais). O rótulo identifica o
consumidor no log e **isola os lotes dele**.

### Isolamento entre consumidores

Cada consumidor só enxerga os próprios lotes. O token de um recebe `404` no lote
de outro, e o Excel acumulado do Agente 2 é recortado para conter **apenas** os
processos dos lotes daquele token. Vale para todas as rotas de download.

---

## O processamento é assíncrono

Não é uma escolha de arquitetura — é uma restrição. O OCR leva minutos por lote e
**nenhum proxy mantém uma conexão HTTP aberta tanto tempo**. O envio responde na
hora com um `lote_id`; o consumidor acompanha por polling.

Os lotes rodam em **fila serial** — um por vez, porque o OCR já satura a CPU.
Acionamentos simultâneos entram na fila e são atendidos em sequência, sem risco
de concorrência.

### Ciclo de vida

```
na_fila → processando → concluido | erro
```

---

## Rotas

| Rota | Uso |
| --- | --- |
| `POST /api/v1/lotes` | Envia PDFs (multipart, campo `arquivos`). Responde `202` com o `lote_id` |
| `GET /api/v1/lotes` | Lista os lotes deste consumidor |
| `GET /api/v1/lotes/{id}` | Estado do lote, com log |
| `GET /api/v1/lotes/{id}/resultado` | Priorização completa (`409` enquanto não concluir) |
| `GET /api/v1/lotes/{id}/arquivos` | Lista o que dá para baixar, com tamanho e URL |
| `GET /api/v1/lotes/{id}/arquivos/{tipo}` | Baixa um artefato — ver a tabela abaixo |
| `GET /api/v1/lotes/{id}/planilha/agente1` | Atalho para `arquivos/agente1_planilha` |
| `GET /api/v1/lotes/{id}/planilha/agente2` | Atalho para `arquivos/agente2_planilha` |
| `GET /api/v1/lotes/{id}/processo` | **Lotes de 1 PDF:** o relatório estruturado do processo, direto |
| `GET /api/v1/processos?numero=...` | Consulta um processo pelo número CNJ |
| `GET /health` | Healthcheck, sem autenticação. Não devolve dado de processo |

### Envio unitário — um processo por chamada

Desde a [v1.1.0](../releases/v1.1.0.md), quem manda **um PDF por vez** não
precisa mais de três passos:

```http
1. POST /api/v1/lotes                    (1 PDF)  → 202 {"lote_id": "..."}
2. GET  /api/v1/lotes/{lote_id}/processo          → o processo, estruturado
```

Antes era preciso ler o payload agregado de `/resultado` para descobrir o número
extraído e então perguntar de novo em `/api/v1/processos`.

| Código | Quando |
| --- | --- |
| `200` | O relatório do processo |
| `409` | Lote ainda não concluído — continue o polling |
| `422` | O lote **não tem exatamente 1 PDF**, ou dele saiu mais de um processo |
| `404` | Lote de outro consumidor, inexistente, ou nenhum número pôde ser extraído |

O `422` é deliberado: a rota não adivinha qual processo você quer num lote com
vários. Nesse caso, use `/resultado`.

### Artefatos de um lote

| `tipo` | Formato | Conteúdo |
| --- | --- | --- |
| `agente1_planilha` | xlsx | Revisão do Agente 1 — só deste lote |
| `agente1_json` | json | A mesma extração em JSON — **os mesmos campos da planilha**, só deste lote |
| `agente2_json` | json | Priorização do Agente 2 — só deste lote |
| `agente2_planilha` | xlsx | Priorização — **acumulado**: todos os processos dos seus lotes |

`agente1_json` é a rota para quem quer os dados da planilha do Agente 1 de forma
estruturada, sem ler Excel.

---

## Exemplo completo

```bash
# 1. Enviar
curl -X POST https://SEU-DOMINIO/api/v1/lotes \
     -H "Authorization: Bearer $TOKEN" \
     -F "arquivos=@processo1.pdf" -F "arquivos=@processo2.pdf"
# → 202 {"lote_id":"20260729-143000-a1b2c3","status":"na_fila", ...}

# 2. Acompanhar até sair de na_fila/processando
curl https://SEU-DOMINIO/api/v1/lotes/20260729-143000-a1b2c3 \
     -H "Authorization: Bearer $TOKEN"

# 3. Buscar a priorização
curl https://SEU-DOMINIO/api/v1/lotes/20260729-143000-a1b2c3/resultado \
     -H "Authorization: Bearer $TOKEN"
```

**Um lote pode ter um único PDF — não há mínimo.** Um lote de um processo só é um
caso normal de uso.

---

## ⚠️ Sempre confira `avisos`

O Agente 1 trata OCR quebrado e PDF ilegível internamente e **encerra com código
de sucesso**. Um lote pode chegar a `concluido` sem ter extraído nada. Por isso a
resposta traz `resumo` e `avisos`:

```json
{
  "status": "concluido",
  "resumo": "3 de 12 processo(s) extraídos com sucesso",
  "avisos": [
    "9 processo(s) não puderam ser lidos — PDF ilegível ou OCR sem resultado"
  ]
}
```

> `status: "concluido"` com `avisos` **não vazio** significa que o lote rodou até
> o fim mas algo deu errado no caminho. **Trate como falha.**

Um PDF ilegível **não** gera prioridade: o erro aparece no JSON, na planilha e
nos avisos, em vez de virar um resultado aparentemente válido.

---

## Estrutura do JSON do Agente 1

Por processo:

| Grupo | Campos |
| --- | --- |
| Identificação | número do processo, `e_execucao_fiscal` (com grau de confiança e a classe/assunto do PJe), vara |
| Partes | nome e CPF/CNPJ do executado, exequente |
| Dívida | número da CDA, tipo de tributo, exercício, data de inscrição em dívida ativa, valor original, valor atualizado |
| Andamento | status e datas de citação (ordem, tentativa, citação efetiva), resultado da penhora, sinais de extinção / parcelamento / suspensão pelo art. 40 da LEF |
| Auditoria | quais páginas exigiram OCR, confiança média do reconhecimento, indicador de sucesso da extração |

> **Campos não encontrados vêm como `null` — nunca omitidos.** A estrutura é
> sempre a mesma, então o consumidor pode contar com ela.

## Estrutura do JSON do Agente 2

Por processo: `prioridade` (ALTA / MEDIA / BAIXA), `acao_recomendada`,
`justificativa`, `alerta_prescricao` (art. 174 do CTN) e `observacoes`.

A prioridade é **operacional** — ordena a fila do procurador. **Não é critério de
ajuizamento**, e BAIXA nunca significa "não cobrar".

---

## Limites e cuidados

| | |
| --- | --- |
| Tamanho do lote | 500 MB por padrão (`MAX_MB_LOTE`) |
| Proxy | ⚠️ o limite de corpo do proxy recusa **antes** — ver [Instalação, passo 5](instalacao.md#5-se-houver-proxy-à-frente--passo-obrigatório) |
| Fila | serial, um lote por vez |
| Tempo | dominado pelo OCR (≈0,73 s/página a 200 dpi). Um processo de 105 MB e 415 páginas concluiu em 61 s |
| Retenção | os PDFs enviados são apagados após 7 dias; o lote inteiro após 90. Configurável |
