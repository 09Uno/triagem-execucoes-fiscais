# Instalação

Do arquivo baixado ao primeiro lote processado.

**Pré-requisito único:** Docker instalado no servidor.
**Não é preciso** acesso à internet no servidor, nem clonar repositório, nem
construir imagem.

---

## 1. Carregar a imagem

Baixe `procuradorias-1.0.tar.gz` na [página de releases](../../../releases) e
carregue:

```bash
docker load < procuradorias-1.0.tar.gz
docker images | grep procuradorias      # confirma que entrou
```

## 2. Gerar as credenciais

**Sem elas o serviço sobe recusando tudo.** É proposital — ver
[Segurança e privacidade](seguranca-e-privacidade.md). Rode uma vez, em qualquer
máquina com Python:

```bash
python gerar_credencial.py api pgms      # token para o sistema que vai integrar
python gerar_credencial.py painel        # senha do painel do procurador
```

O gerador mostra duas coisas:

- o **segredo** — aparece uma única vez e não fica gravado em lugar nenhum.
  Guarde-o com cuidado; se for perdido, emite-se outro, não há recuperação;
- o **hash** — é o que vai para o ambiente do serviço, no passo seguinte.

> O script `gerar_credencial.py` acompanha o pacote. Se não o tiver em mãos,
> peça — ele não depende do sistema instalado e roda em qualquer Python.

## 3. Subir

```bash
docker run -d --name procuradorias \
  --restart unless-stopped \
  -p 3000:3000 \
  --memory 2g \
  -e API_TOKENS='pgms:sha256:<hash>' \
  -e SENHA_PAINEL_HASH='<hash scrypt>' \
  -e COOKIE_SEGURO=0 \
  -e TZ=America/Campo_Grande \
  -v /opt/procuradorias/JSON:/app/JSON \
  -v /opt/procuradorias/resultados:/app/resultados \
  -v /opt/procuradorias/dados:/app/dados \
  procuradorias:1.0
```

Ajuste os caminhos **à esquerda** dos `-v` para onde os dados devem ficar no
servidor.

> ⚠️ **Os três volumes são obrigatórios.** Sem eles, recriar o container apaga o
> histórico acumulado e todos os lotes já processados.

`COOKIE_SEGURO=1` apenas se o serviço for publicado por HTTPS. Em `1` sem HTTPS,
o painel não consegue abrir sessão.

Os demais ajustes (OCR, prioridade, retenção, timeout) têm padrão embutido e só
precisam ser informados para mudar o comportamento — ver
[Ajustes de ambiente](#ajustes-de-ambiente).

## 4. Conferir que subiu do jeito certo

```bash
docker logs procuradorias | head -20
curl -s http://localhost:3000/health
```

Duas verificações:

**No log deve aparecer:**

```text
[entrypoint] Pastas prontas. Iniciando como 'hera' (sem privilégio).
```

Se em vez dela aparecer um destes avisos:

| Linha no log | O que significa |
| --- | --- |
| `AVISO: gosu não encontrado` | O serviço está rodando **como root**. Funciona, mas sem o isolamento |
| `AVISO: não consegui ajustar o dono` | O volume recusou o ajuste de dono. Pode funcionar mesmo assim; se o upload falhar por permissão, a causa é esta |

Os dois casos degradam com aviso em vez de derrubar o container — de propósito,
para que um detalhe de volume não impeça a subida. Mas nenhum é o comportamento
pretendido, e ambos passam despercebidos por quem não lê o log.

**O `/health` deve responder:**

```json
{"status":"ok","api_ativa":true}
```

Se `api_ativa` vier `false`, o `API_TOKENS` não foi aceito — confira se colou o
**hash**, e não o segredo.

## 5. Se houver proxy à frente — passo obrigatório

> ⚠️ **Este é o passo que mais causa falha de implantação.**

O sistema aceita lotes de até 500 MB, mas quem recebe a requisição **primeiro** é
o proxy (Nginx, Apache, Traefik ou o balanceador). O padrão deles é bem menor que
100 MB, e o upload de um PDF grande é recusado com `413` **antes de chegar ao
sistema** — com o sistema funcionando perfeitamente.

Em Nginx:

```nginx
client_max_body_size 500m;
```

E acrescente `-e COOKIE_SEGURO=1` ao `docker run` se o proxy servir HTTPS.

## 6. Primeiro uso

O painel fica em `http://SERVIDOR:3000` e a documentação da API em
`http://SERVIDOR:3000/api/docs`.

Faça o percurso completo antes de liberar para uso: enviar um PDF pelo painel,
acompanhar até `concluido`, baixar a planilha.

**Envie um PDF digitalizado neste teste** e abra a coluna **Confiança OCR (%)**
da planilha do Agente 1. Se vier `0,0%` numa página que visivelmente tem texto, o
OCR não rodou — e o sintoma, sem essa conferência, seria um lote concluindo com
texto vazio, sem erro aparente.

---

## Ajustes de ambiente

Todos opcionais — têm padrão embutido.

| Variável | Padrão | Para quê |
| --- | --- | --- |
| `TZ` | `America/Bahia` | Fuso dos relatórios e nomes de arquivo |
| `PORT` | `3000` | Porta da interface web |
| `COOKIE_SEGURO` | `0` | `1` em produção com HTTPS — marca a sessão como Secure |
| `HORAS_SESSAO` | `12` | Validade da sessão do painel |
| `MAX_MB_LOTE` | `500` | Tamanho máximo de um lote, em MB |
| `TIMEOUT_AGENTE_S` | `3600` | Tempo máximo por etapa. Estourou, o lote vira `erro` em vez de travar a fila |
| `OCR_DPI` | `200` | Resolução do OCR. Afeta a **qualidade** do reconhecimento |
| `OCR_MAX_LOTE` | `10` | Páginas convertidas por vez |
| `OCR_MAX_WORKERS` | `2` | Processos paralelos de OCR |
| `LIMIAR_PRIORIDADE_ALTA` | `5000` | Corte da prioridade ALTA, em R$ |
| `LIMIAR_PRIORIDADE_MEDIA` | `1000` | Corte da prioridade MEDIA, em R$ |
| `RETENCAO_PDF_DIAS` | `7` | Apaga os PDFs recebidos de lotes concluídos há mais dias que isto. `0` desliga |
| `RETENCAO_LOTE_DIAS` | `90` | Remove o lote inteiro — pasta e registro. `0` desliga |

### Se o container morrer por falta de memória

O log mostra **`código -9`**. Reduza `OCR_MAX_LOTE` e `OCR_MAX_WORKERS`
**antes** de mexer no `OCR_DPI` — é o DPI que determina se o texto digitalizado
será reconhecido. Custo por página: 300 dpi ≈ 1,27 s · 200 dpi ≈ 0,73 s ·
150 dpi ≈ 0,52 s.

### Retenção em disco

Os PDFs recebidos são o que pesa: 100 MB cada. Com 50 GB de volume, o disco
enche em cerca de **500 lotes** — e, cheio, o serviço recusa envios sem deixar
claro o motivo.

| Prazo | O que acontece |
| --- | --- |
| `RETENCAO_PDF_DIAS` (7) | Os **PDFs enviados** de lotes concluídos são apagados. A planilha e o JSON gerados **permanecem** |
| `RETENCAO_LOTE_DIAS` (90) | O lote inteiro sai — pasta e registro |

O PDF original continua com quem o enviou, então apagá-lo cedo não perde nada.
Para guardar tudo indefinidamente, defina as duas como `0` — mas então acompanhe
o espaço em disco.

---

## Atualizar para uma versão nova

```bash
docker load < procuradorias-1.1.tar.gz
docker stop procuradorias && docker rm procuradorias
# repita o docker run do passo 3, trocando a tag para 1.1
```

Os dados ficam nos volumes, fora do container — **trocar de versão não perde
nada**.

---

## Problemas comuns

| Sintoma | Causa provável |
| --- | --- |
| Upload de PDF grande falha com `413` | Limite de corpo do proxy. Ver o passo 5 |
| `/health` responde `api_ativa: false` | `API_TOKENS` não foi aceito — foi colado o segredo em vez do hash |
| O painel não abre sessão | `COOKIE_SEGURO=1` sem HTTPS |
| Container morre com **código -9** | Falta de memória. Suba para 2 GB ou reduza `OCR_MAX_LOTE` / `OCR_MAX_WORKERS` |
| Primeiro upload falha por permissão | O ajuste de dono do volume não passou — procure o `AVISO` no log, passo 4 |
| Lote `concluido` mas sem dados | Confira `avisos` na resposta. PDF ilegível ou OCR sem resultado |
| Histórico sumiu ao recriar o container | Os volumes não estavam montados como persistentes |
