# Triagem de Execuções Fiscais

Sistema de triagem automatizada de execuções fiscais para procuradorias.
Lê os PDFs dos processos, extrai os dados e entrega ao procurador uma fila de
trabalho já ordenada.

Desenvolvido pela **HERA Tecnologia** para a **Procuradoria-Geral do Estado de
Mato Grosso do Sul (PGMS)**.

> Este repositório é a **página de distribuição**: notas de cada versão,
> documentação e o download do pacote Docker. O código-fonte não fica aqui.

---

## ⬇️ Baixar a versão atual

**[→ Releases](../../releases)** · versão estável: **[v1.0.0](../../releases/latest)**

O pacote é a **imagem Docker exportada** (`procuradorias-1.0.tar.gz`). Instala com
`docker load`, sem construir nada, sem clonar repositório e **sem acesso à
internet no servidor**.

```bash
docker load < procuradorias-1.0.tar.gz
```

O passo a passo completo está em **[docs/instalacao.md](docs/instalacao.md)**.

---

## O que o sistema faz

O trabalho é dividido em dois agentes, e o que os separa é importante: **um lê o
processo, o outro organiza a fila.** Nenhum dos dois decide nada.

### Agente 1 — extração

Lê cada PDF, aplica OCR nas páginas digitalizadas e extrai os dados do processo:

| | |
| --- | --- |
| **Identificação** | número do processo (CNJ), vara, se é execução fiscal (com grau de confiança e a classe/assunto do PJe) |
| **Partes** | nome e CPF/CNPJ do executado, exequente |
| **Dívida** | número da CDA, tipo de tributo, exercício, data de inscrição em dívida ativa, valor original, valor atualizado |
| **Andamento** | status e datas de citação (ordem, tentativa, citação efetiva), resultado da penhora, sinais de extinção, parcelamento ou suspensão pelo art. 40 da LEF |
| **Auditoria** | quais páginas exigiram OCR, confiança média do reconhecimento, indicador de sucesso da extração |

Sai em **Excel** (para revisão humana) e em **JSON** (para integração) — os dois
com exatamente os mesmos campos. Campo não encontrado vem como `null`, nunca
omitido: a estrutura é sempre a mesma.

### Agente 2 — priorização

Lê a extração do Agente 1 e organiza a fila do procurador. Para cada processo:

- **prioridade** — ALTA, MEDIA ou BAIXA;
- **ação recomendada** — ex.: "nova tentativa de citação", "penhora online via SISBAJUD/RENAJUD", "suspenso pelo art. 40 da LEF — controlar prescrição intercorrente";
- **justificativa** da prioridade atribuída;
- **alerta de prescrição**, com base no art. 174 do CTN;
- **observações** — ex.: CPF/CNPJ não identificado, CDA não extraída.

Como a prioridade é atribuída:

| Prioridade | Critério |
| --- | --- |
| **ALTA** | dívida ≥ R$ 5.000 · **ou** risco de prescrição · **ou** 5 anos ou mais sem movimentação |
| **MEDIA** | dívida entre R$ 1.000 e R$ 5.000 |
| **BAIXA** | dívida abaixo de R$ 1.000 |

> Os valores R$ 5.000 e R$ 1.000 são uma **definição provisória**, feita apenas
> para ordenar o trabalho. **Não derivam de norma e não são critério de
> ajuizamento.** BAIXA nunca significa "não cobrar". Trocá-los é mudança de
> configuração — não exige nova versão do sistema.

### Duas portas de entrada

| | |
| --- | --- |
| **Painel do procurador** | Página web protegida por senha. Envia os PDFs, acompanha o processamento com log ao vivo e baixa os relatórios. |
| **API v1** | Para o SIAP e outros sistemas. Autenticação por token, processamento assíncrono, documentação interativa em `/api/docs`. Ver **[docs/api.md](docs/api.md)**. |

As duas usam a mesma fila.

---

## O que o sistema **não** faz

Isto é tão relevante quanto o que ele faz:

- **Não usa inteligência artificial.** A extração é regex + OCR; a priorização é
  um conjunto de regras. O mesmo processo produz sempre o mesmo resultado, e cada
  resultado é auditável linha a linha.
- **Não faz chamada para fora.** Nenhum serviço de terceiros, nenhuma API de IA,
  nenhum dado sai do servidor. O container funciona em rede fechada.
- **Não emite juízo sobre o processo.** Não existe classificação APTO / NÃO APTO.
  O Agente 1 relata o que está no PDF; o Agente 2 sugere uma ordem de atendimento.
  **A decisão é do procurador.**

Ver **[docs/seguranca-e-privacidade.md](docs/seguranca-e-privacidade.md)**.

---

## Histórico de versões

| Versão | Data | O que mudou | Pacote |
| --- | --- | --- | --- |
| **[v1.0.0](releases/v1.0.0.md)** | 27/08/2026 | **Primeira entrega instalável.** Isolamento entre consumidores, pico de memória de 1.648 MB → 243 MB, retenção automática em disco, 118 testes | ✅ Docker |
| [v0.6.0](releases/v0.6.0.md) | 23/08/2026 | Estabilização da consulta por processo e dos códigos de erro | — |
| [v0.5.0](releases/v0.5.0.md) | 11/08/2026 | Agente 1 v8.0 — extração 100% determinística, fim do APTO / NÃO APTO | — |
| [v0.4.0](releases/v0.4.0.md) | 04/08/2026 | Consulta de um processo pelo número CNJ | — |
| [v0.3.0](releases/v0.3.0.md) | 30/07/2026 | Swagger, download por artefato, lote de 500 MB, log ao vivo | — |
| [v0.2.0](releases/v0.2.0.md) | 29/07/2026 | Painel do procurador e API v1 autenticada | — |
| [v0.1.0](releases/v0.1.0.md) | 28/07/2026 | Os dois agentes, empacotados em Docker | — |

As versões `v0.x` são marcos de desenvolvimento — o empacotamento para instalação
começa na **v1.0.0**. Ver o **[CHANGELOG](CHANGELOG.md)** para a lista corrida.

---

## Requisitos do ambiente

| Item | Valor |
| --- | --- |
| Docker | qualquer versão recente |
| Memória do container | **2 GB, mínimo** — é o OCR que consome |
| Porta publicada | 3000 (configurável) |
| Volumes persistentes | 3 pastas (JSON, resultados, dados) |
| Disco | dimensionar pelo volume de PDFs — há limpeza automática configurável |
| Acesso à internet | **nenhum** |

⚠️ **Um passo não pode ser pulado:** aumentar o limite de tamanho de requisição
no proxy de entrada (Traefik / Nginx / balanceador). O padrão da maioria dos
proxies é bem menor que 100 MB, e é ele quem recusa o arquivo **antes** de a
requisição chegar ao sistema. É a causa mais comum de falha de implantação.

---

## Documentação

| | |
| --- | --- |
| **[Instalação](docs/instalacao.md)** | Do `docker load` ao primeiro lote processado |
| **[API v1](docs/api.md)** | Rotas, autenticação, ciclo de vida do lote, exemplos |
| **[Segurança e privacidade](docs/seguranca-e-privacidade.md)** | Autenticação, isolamento entre consumidores, retenção de dados |

---

## Suporte

Dúvida, problema na instalação ou pedido de ajuste: **[abra uma issue](../../issues)**.

⚠️ **Não anexe PDF de processo, planilha de resultado nem credencial em issue** —
este repositório é público. Descreva o sintoma; se for preciso enviar arquivo, ele
vai por canal privado.
