#!/usr/bin/env bash
#
# Publica esta vitrine no GitHub: cria o repositorio publico, sobe os arquivos
# e cria uma release para cada arquivo em releases/.
#
# Pre-requisito: gh instalado e autenticado.
#   gh auth login
#
# Uso:
#   ./publicar.sh                       # cria/atualiza tudo
#   ./publicar.sh --dry-run             # so mostra o que faria
#
# Idempotente: rodar de novo atualiza o que mudou, sem duplicar nada.

set -euo pipefail

# ── Configuracao ────────────────────────────────────────────────────
REPO_NOME="triagem-execucoes-fiscais"
REPO_DESC="Triagem automatizada de execucoes fiscais — pacote Docker, notas de versao e documentacao"

# Onde procurar os arquivos para anexar na release v1.0.0.
PASTA_PACOTES="${PASTA_PACOTES:-../Procuradorias}"

# Arquivos a anexar em v1.0.0. Os que nao existirem sao ignorados com aviso.
ASSETS_V1=(
  "$PASTA_PACOTES/procuradorias-1.0.tar.gz"
  "$PASTA_PACOTES/Guia de Instalacao - Triagem de Execucoes Fiscais.pdf"
  "$PASTA_PACOTES/Guia de Instalacao - Triagem de Execucoes Fiscais.docx"
  "$PASTA_PACOTES/Manual - Triagem de Execucoes Fiscais.docx"
)

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

cd "$(dirname "$0")"

# gh pode nao estar no PATH do shell atual logo apos a instalacao
export PATH="$PATH:/c/Program Files/GitHub CLI"

diz()  { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
aviso(){ printf '  \033[33m!\033[0m %s\n' "$*"; }
rodar(){ if (( DRY_RUN )); then printf '  \033[90m[dry-run] %s\033[0m\n' "$*"; else eval "$@"; fi; }

# ── 1. Conferir o gh ────────────────────────────────────────────────
diz "Conferindo o GitHub CLI"
command -v gh >/dev/null || { echo "gh nao encontrado. Instale com: winget install GitHub.cli"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh nao autenticado. Rode: gh auth login"; exit 1; }
DONO="$(gh api user --jq .login)"
ok "autenticado como $DONO"
REPO="$DONO/$REPO_NOME"

# ── 2. Criar o repositorio, se ainda nao existir ────────────────────
diz "Repositorio $REPO"
if gh repo view "$REPO" >/dev/null 2>&1; then
  ok "ja existe"
else
  rodar "gh repo create '$REPO' --public --description '$REPO_DESC'"
  ok "criado (publico)"
fi

# ── 3. Subir os arquivos ────────────────────────────────────────────
diz "Enviando os arquivos"
if [[ ! -d .git ]]; then
  rodar "git init -b main"
fi
rodar "git add -A"
if (( DRY_RUN )) || [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  rodar "git commit -m 'Vitrine publica: notas de versao e documentacao'"
  ok "commit feito"
else
  ok "nada mudou desde o ultimo envio"
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  rodar "git remote add origin 'https://github.com/$REPO.git'"
fi
rodar "git push -u origin main"
ok "arquivos no ar"

# ── 4. Criar uma release por arquivo em releases/ ───────────────────
# Ordem crescente: a ultima criada e a que o GitHub marca como 'Latest'.
diz "Criando as releases"
for arquivo in $(ls releases/v*.md | sort -V); do
  tag="$(basename "$arquivo" .md)"
  titulo="$(head -1 "$arquivo" | sed 's/^# *//')"

  # Pre-release para tudo abaixo de 1.0.0
  extra=""
  [[ "$tag" == v0.* ]] && extra="--prerelease"

  if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    rodar "gh release edit '$tag' --repo '$REPO' --title '$titulo' --notes-file '$arquivo'"
    ok "$tag atualizada"
  else
    rodar "gh release create '$tag' --repo '$REPO' --title '$titulo' --notes-file '$arquivo' --target main $extra"
    ok "$tag criada"
  fi
done

# ── 5. Anexar os pacotes na v1.0.0 ──────────────────────────────────
diz "Anexando os pacotes em v1.0.0"
encontrou=0
for asset in "${ASSETS_V1[@]}"; do
  if [[ -f "$asset" ]]; then
    rodar "gh release upload v1.0.0 --repo '$REPO' '$asset' --clobber"
    ok "$(basename "$asset")"
    encontrou=1
  else
    aviso "nao encontrado: $(basename "$asset")"
  fi
done
(( encontrou )) || aviso "Nenhum pacote anexado. Coloque os arquivos em '$PASTA_PACOTES' ou defina PASTA_PACOTES=<caminho> e rode de novo."

diz "Pronto"
echo "  https://github.com/$REPO"
echo "  https://github.com/$REPO/releases"
