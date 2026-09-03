# Histórico de versões

Lista corrida. Cada versão tem uma nota própria, com o raciocínio por trás das
mudanças — os links levam até ela.

O versionamento segue [SemVer](https://semver.org/lang/pt-BR/). As versões `v0.x`
são marcos de desenvolvimento; o empacotamento para instalação começa na
**v1.0.0**.

---

## [v1.0.0](releases/v1.0.0.md) — 27/08/2026 · ✅ pacote Docker

Primeira entrega instalável. Auditoria antes do empacotamento, com teste de
regressão para cada problema encontrado.

**Segurança**
- Isolamento entre consumidores: a consulta por processo entregava dado de
  qualquer consumidor a qualquer token válido, e a planilha acumulada do Agente 2
  era um arquivo global. Ambos recortados por consumidor
- Injeção de argumento em `/api/v1/processos`: `numero=-h` devolvia `200` com o
  help do programa e `--pasta=X` redirecionava a busca. O `500` deixou de vazar
  stderr e caminho interno do servidor

**Desempenho**
- Pico de memória do Agente 1: **1.648 MB → 243 MB**. O leitor não liberava as
  páginas lidas e o OCR carregava dezenas de imagens de uma vez
- Parâmetros de OCR ajustáveis por ambiente, sem reconstruir a imagem

**Correção**
- PDF ilegível concluía "com sucesso" e gerava prioridade fabricada. O erro
  aparece agora no JSON, na planilha e nos `avisos` do lote
- Excel do Agente 2 duplicava linha a cada reprocessamento — a deduplicação
  existia e nunca era chamada. Escrita passou a ser atômica
- Espanhol removido do log, das chaves de JSON e do marcador que ia parar no
  Excel (as chaves antigas continuam aceitas na entrada)

**Implantação**
- `docker-compose.yml` exigia `OPENAI_API_KEY`, que nenhum código usa desde a
  v0.5.0, e apontava para `promptV7.1.py`, que não existe mais — **os dois
  impediam subir**
- Container larga o privilégio antes de atender a primeira requisição
- Retenção automática em disco: PDFs após 7 dias, lote inteiro após 90
- Teto de tempo por etapa (`TIMEOUT_AGENTE_S`), para um agente travado não
  segurar a fila
- Cabeçalhos `X-Forwarded-*` tratados, para o freio de senha não trancar o painel
  para todos

**Testes**
- Suíte de **118 testes** cobrindo as rotas da API v1 e do painel

---

## [v0.6.0](releases/v0.6.0.md) — 23/08/2026

Estabilização. Nenhuma funcionalidade nova.

- Processo não encontrado devolvia `200` com corpo vazio — agora `404`
- Saída da consulta reescrita; histórico completo, em ordem
- Erros passaram a nomear a causa. O **código -9** (morte por falta de memória)
  deixou de ser um número opaco
- Espanhol removido da saída

---

## [v0.5.0](releases/v0.5.0.md) — 11/08/2026

Mudança conceitual. Agente 1 v8.0.

- **Fim do APTO / NÃO APTO.** Aptidão para ajuizar é análise jurídica, não saída
  de programa. Além disso, um processo marcado NÃO APTO saía da esteira — um erro
  de OCR bastava para um processo válido sumir da fila
- **Extração 100% determinística.** Sem modelo de linguagem. O mesmo PDF produz
  sempre o mesmo resultado
- **Nenhum dado sai do servidor.** Sem chamada externa, sem chave de API, roda em
  rede fechada

---

## [v0.4.0](releases/v0.4.0.md) — 04/08/2026

- Consulta de um processo pelo número CNJ, com o histórico de passagens pelo
  sistema

---

## [v0.3.0](releases/v0.3.0.md) — 30/07/2026

- Documentação interativa da API (`/api/docs`, `/api/redoc`, `/api/openapi.json`),
  gerada do próprio código
- Download por artefato — `agente1_planilha`, `agente1_json`, `agente2_json`,
  `agente2_planilha`
- Acompanhamento do lote com log ao vivo no painel
- Limite do lote de 200 → **500 MB** (os PDFs reais chegam a 100 MB cada)

---

## [v0.2.0](releases/v0.2.0.md) — 29/07/2026

- **Painel do procurador**, protegido por senha
- **API v1** com token Bearer e processamento assíncrono
- **O serviço falha fechado** — configuração incompleta deixa o serviço
  inacessível, nunca aberto
- **O ambiente guarda hashes, nunca segredos.** SHA-256 para os tokens, scrypt
  para a senha do painel. Rotação sem parar a integração

---

## [v0.1.0](releases/v0.1.0.md) — 28/07/2026

- **Agente 1** — extração determinística dos dados do processo, com OCR nas
  páginas digitalizadas. Saída em Excel e JSON
- **Agente 2** — priorização, ação recomendada, justificativa e alerta de
  prescrição (art. 174 do CTN)
- Empacotamento em **Docker**, com Tesseract (`por`) e Poppler dentro da imagem
