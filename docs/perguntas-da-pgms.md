# Perguntas levantadas pela PGMS

Os sete pontos levantados na avaliação da solução, com a resposta técnica de cada
um. Onde houve correção, ela está aplicada e a versão em que entrou está
indicada.

---

## 1. O JSON do Agente 1 traz as informações da planilha?

**Traz — e sempre trouxe.** Os dois artefatos saem da mesma passagem pelo PDF,
campo a campo. O problema era outro: **o download do JSON falhava**, por um erro
no nome do arquivo procurado. Na prática, esse JSON nunca chegava às mãos de
quem o pedia — daí a impressão de que era mais pobre que a planilha.

Corrigido. O arquivo é obtido em:

```http
GET /api/v1/lotes/{lote_id}/arquivos/agente1_json
```

E `GET /api/v1/lotes/{lote_id}/arquivos` lista tudo que o lote deixou
disponível, com tamanho e link de cada item.

**Estrutura por processo:** número do processo, indicador de execução fiscal,
classe/assunto do PJe, status e datas de citação, resultado da penhora, indícios
de extinção / parcelamento / aplicação do art. 40 da LEF, CPF/CNPJ, executado e
exequente, tributo, exercício, número da CDA, data de inscrição, valor original,
valor atualizado, vara e os metadados de OCR.

**Consistência:** campos não localizados retornam como `null`, **nunca
omitidos** — a estrutura é sempre a mesma, e o consumidor pode contar com ela.

## 2. Qual é o papel do Agente 2?

**Organiza a fila de trabalho do procurador.** Atua estritamente sobre os dados
já estruturados pelo Agente 1, por regras de negócio fixas — **não lê PDF e não
usa IA**. A previsibilidade é total: o mesmo processo produz sempre o mesmo
resultado.

**Entrega, por processo:** nível de prioridade, ação recomendada, fundamentação,
alerta de prescrição (art. 174 do CTN) e observações.

| Prioridade | Critério |
| --- | --- |
| **ALTA** | valor ≥ R$ 5.000 · **ou** risco iminente de prescrição · **ou** 5 anos ou mais sem movimentação |
| **MÉDIA** | valor entre R$ 1.000 e R$ 5.000 |
| **BAIXA** | valor inferior a R$ 1.000 |

> ⚠️ **BAIXA é critério de triagem operacional e não configura desistência da
> cobrança.** As faixas de corte são **provisórias**: a definição dos valores
> oficiais cabe à PGMS, e a alteração é puramente de configuração — sem novo
> deploy da aplicação.

**Exportação:** JSON por lote e planilha Excel consolidada, já ordenados por
prioridade e por valor.

## 3. Pacote Docker e implantação

Pacote entregue: **imagem Docker exportada** e **Guia de Instalação**. A
instalação é por `docker load`, **sem compilação e sem acesso ao repositório de
código**.

A partir da [v1.1.0](../releases/v1.1.0.md), o pacote também é baixável
diretamente na [página de releases](../../../releases).

Requisitos do ambiente e o passo obrigatório do limite de upload no proxy estão
em **[Instalação](instalacao.md)**.

## 4. A classificação APTO / NÃO APTO

**Removida do pipeline de processamento** na
[v0.5.0](../releases/v0.5.0.md). O Agente 1 limita-se à extração fidedigna dos
dados, e a totalidade dos processos segue para o Agente 2. Nenhum processo é
reprovado.

O raciocínio completo por trás dessa decisão está na nota da
[v0.5.0](../releases/v0.5.0.md) — resumidamente: aptidão para ajuizar é análise
jurídica, e um processo marcado NÃO APTO saía da esteira, de modo que um erro de
OCR bastava para um processo válido desaparecer da fila.

> **Pendência:** ainda restam menções ao rótulo em textos da tela de consulta e
> da documentação do Swagger. São texto antigo, **sem efeito sobre o resultado**.
> Em limpeza.

## 5. Padronização do idioma

Planilhas, JSONs e o log em tempo real do Agente 2 estão **em português**. Os
pontos residuais identificados — chaves específicas do JSON e o marcador de
exceção que ia parar no Excel — foram corrigidos na
[v1.0.0](../releases/v1.0.0.md).

Caso apareça qualquer outro termo em idioma diverso em algo que vocês recebam, é
só apontar que ajustamos.

## 6. Retirar a "última movimentação" do processamento

**Viável**, e concordamos que o dado do MNI é mais consistente que o extraído do
PDF.

O campo impacta **unicamente** a regra de priorização dos 5 anos sem
movimentação. **O cálculo de prescrição permanece inalterado** — ele se baseia no
exercício fiscal e no marco de citação.

| Opção | O que acontece |
| --- | --- |
| **(a) Remover** | A regra dos 5 anos deixa de existir. A priorização passa a ser por valor + prescrição |
| **(b) Receber do MNI** *(recomendada)* | O SIAP envia a data junto com o processo e a regra continua valendo, com dado mais confiável |

> **Depende de definição da PGMS.** Se a escolha for (b), precisamos apenas do
> formato da data e de a partir de quando.

## 7. Processamento unitário e integração com o SIAP

A arquitetura suporta lotes de **1 a N arquivos** de forma nativa. **Não há
quantidade mínima** — um lote de um único processo é caso normal de uso. A fila é
serial, o que garante ordem e ausência de conflito de concorrência.

**O que já está entregue na [v1.1.0](../releases/v1.1.0.md):**

- **Consulta direta do processo de um lote.** Para quem manda um PDF por vez, o
  fluxo caiu de três passos para dois — não é mais preciso ler o número extraído
  no payload agregado e consultar de novo:

  ```http
  1. POST /api/v1/lotes                    (1 PDF)  → 202 {"lote_id": "..."}
  2. GET  /api/v1/lotes/{lote_id}/processo          → o processo, estruturado
  ```

- **Cache de extrações de OCR.** Páginas já reconhecidas não são reprocessadas em
  reenvios nem em novas análises. A chave é o hash do conteúdo do PDF, então
  renomear não engana o cache e um documento alterado é corretamente
  reprocessado. É o ganho mais direto no fluxo unitário do SIAP, onde o custo do
  OCR não se dilui num lote grande.

**O que ainda não está entregue:**

- **Resposta síncrona na mesma requisição.** A rota nova encurta o fluxo, mas
  ainda são duas chamadas. Uma resposta direta no próprio `POST` é possível e
  exige tratar o processo muito longo: nele o OCR pode ultrapassar o tempo que
  uma requisição HTTP consegue ficar aberta, e a chamada precisa cair
  automaticamente no modelo assíncrono **sem quebrar a integração do lado do
  SIAP**. É esse fallback que responde pelo prazo, não a rota em si.

- **`GET /api/v1/processos` em JSON.** A consulta por número ainda devolve texto
  formatado, pensado para leitura humana. A rota nova de lote unitário já entrega
  JSON estruturado.

**Dimensionamento:** o custo é dominado pelo OCR das páginas digitalizadas
(≈0,73 s por página a 200 dpi). O maior processo recebido — **105 MB e 415
páginas** — foi concluído em **61 segundos**. Um processo comum, de poucas dezenas
de páginas, sai em segundos.

---

## Pontos que dependem de definição da PGMS

Nenhum dos dois bloqueia a instalação ou os testes, e ambos são ajuste de
configuração — não exigem nova versão do sistema:

| # | Ponto | O que precisamos |
| --- | --- | --- |
| **2** | Faixas de corte da priorização | Os valores oficiais, no lugar dos provisórios R$ 5.000 / R$ 1.000 |
| **6** | Última movimentação | Remover a regra dos 5 anos, ou passar a receber a data pelo MNI |
