# Segurança e privacidade

Os relatórios do sistema carregam **nome, CPF/CNPJ e valor de dívida**. As
decisões abaixo partem daí.

---

## Nenhum dado sai do servidor

O sistema **não faz chamada para fora**. Não usa serviço de IA de terceiros, não
consulta API externa, não envia dado algum para a internet.

Isso não é uma configuração que se possa desligar por engano — é consequência de
uma decisão de arquitetura tomada na [v0.5.0](../releases/v0.5.0.md): a extração
deixou de usar modelo de linguagem e passou a ser **regras determinísticas +
OCR**, executadas inteiramente dentro do container.

Consequências práticas:

- o servidor pode ficar em **rede fechada**, sem saída para a internet;
- não há chave de API de terceiro para configurar, renovar ou vazar;
- não há custo por uso nem dependência da disponibilidade de um serviço externo;
- o mesmo processo produz **sempre** o mesmo resultado, e cada campo extraído é
  rastreável até o trecho que o originou.

---

## O serviço falha fechado

Sem `API_TOKENS`, a API recusa tudo com `503`. Sem senha, o painel não abre.

Uma configuração incompleta deixa o serviço **inacessível, nunca aberto**. É
deliberado: o modo de falha de um sistema que guarda CPF não pode ser "liberar".

---

## O ambiente guarda hashes, nunca segredos

**Variável de ambiente não é cofre.** O valor aparece na interface do painel de
hospedagem, em `docker inspect`, em `/proc/<pid>/environ` e em qualquer dump de
erro.

Por isso o serviço não guarda o token nem a senha — guarda o **hash**. Quem ler
qualquer um desses caminhos **não consegue autenticar**.

```bash
python gerar_credencial.py api pgms      # token de um consumidor da API
python gerar_credencial.py painel        # senha do painel do procurador
```

O gerador mostra o **segredo** uma única vez, sem gravá-lo em lugar nenhum, e o
**hash**, que vai para o ambiente. Perdeu o token, emite-se outro — não há
recuperação, e é assim que deve ser.

### Dois algoritmos, por dois motivos diferentes

| Credencial | Algoritmo | Por quê |
| --- | --- | --- |
| Token da API | SHA-256 direto | São 256 bits aleatórios. Não há força bruta viável — o hash rápido basta |
| Senha do painel | **scrypt** | É escolhida por gente, com entropia baixa e atacável por dicionário. Lento de propósito |

### Rotação sem parar a integração

Dois hashes com o mesmo rótulo valem ao mesmo tempo:

```ini
API_TOKENS=siap:sha256:<novo>,siap:sha256:<antigo>
```

Adicione o novo, avise o consumidor, espere a troca, remova o antigo.

---

## Isolamento entre consumidores

Cada consumidor da API **só enxerga os próprios lotes**:

- o token de um recebe `404` no lote de outro;
- o Excel acumulado do Agente 2 é recortado para conter **apenas** os processos
  dos lotes daquele token;
- vale para **todas** as rotas de download, inclusive o relatório acumulado.

> Este comportamento nasceu de uma correção. Antes da
> [v1.0.0](../releases/v1.0.0.md), a consulta por processo entregava dado de
> qualquer consumidor a qualquer token válido, e a planilha acumulada era um
> arquivo global. Ambos os furos estão fechados, com teste de regressão.

---

## O container não roda como root

O serviço roda como usuário **`hera`, uid 10001**. O container inicia como root
apenas para ajustar o dono das pastas montadas e **larga o privilégio antes de
atender a primeira requisição**.

A confirmação está no log:

```text
[entrypoint] Pastas prontas. Iniciando como 'hera' (sem privilégio).
```

Ver [Instalação, passo 4](instalacao.md#4-conferir-que-subiu-do-jeito-certo).

---

## Freio de tentativas de senha

O painel bloqueia após tentativas repetidas de senha errada, por IP.

Atrás de um proxy reverso, o container lê os cabeçalhos `X-Forwarded-*`. Isso é
necessário: sem eles, **toda** requisição chega com o IP do proxy, e o freio
enxergaria um único IP para o mundo inteiro — dez erros de senha de qualquer
pessoa trancariam o painel para todos, o procurador incluído.

Confiar no cabeçalho é seguro aqui porque o container **nunca** é exposto
diretamente: só o proxy alcança a porta. Se algum dia for publicado sem proxy à
frente, essa opção precisa sair.

---

## Retenção de dados

Os dados não ficam para sempre. Limpeza automática, em duas etapas:

| Prazo padrão | O que acontece |
| --- | --- |
| 7 dias (`RETENCAO_PDF_DIAS`) | Os **PDFs enviados** de lotes concluídos são apagados. A planilha e o JSON gerados permanecem |
| 90 dias (`RETENCAO_LOTE_DIAS`) | O lote inteiro sai — pasta e registro |

O raciocínio: o PDF original continua com quem o enviou, então apagá-lo cedo não
perde nada — e é ele que carrega o processo inteiro. O que o sistema produziu
sobrevive aos 7 dias.

Os dois prazos são configuráveis, e `0` desliga a limpeza. Mas desligar significa
guardar PDFs de processo indefinidamente — decisão que deve ser consciente, não
padrão.

---

## O sistema não decide nada

Não existe classificação APTO / NÃO APTO. O Agente 1 relata o que está no PDF; o
Agente 2 sugere uma **ordem de atendimento**. Nenhum processo é excluído da fila.

A prioridade ALTA / MEDIA / BAIXA é **operacional** e não deriva de norma. BAIXA
nunca significa "não cobrar".

**A decisão é do procurador.** Ver [v0.5.0](../releases/v0.5.0.md) para o
raciocínio completo por trás dessa escolha.

---

## Reportando um problema de segurança

**Não abra issue pública** para falha de segurança, e **nunca anexe PDF de
processo, planilha de resultado ou credencial** neste repositório — ele é
público.

Comunique por canal privado à HERA Tecnologia.
