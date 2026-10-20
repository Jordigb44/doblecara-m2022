#!/bin/bash
# Calcula la próxima versión siguiendo SemVer a partir de los commits desde el
# último tag, y actualiza app/Info.plist.
#
# Tipos de bump deducidos de los mensajes de commit (Conventional Commits):
#   - «BREAKING CHANGE» o «!:»  -> major
#   - «feat:»                   -> minor
#   - «fix:» / «perf:»          -> patch
#
# Uso:
#   scripts/bump-version.sh               # deducir bump y actualizar Info.plist
#   scripts/bump-version.sh --dry-run     # solo imprime la versión, sin tocar nada
#   scripts/bump-version.sh --minor --push # forzar minor y publicar (commit+tag+push)
#
# Opciones:
#   --major | --minor | --patch   fuerza el tipo de bump
#   --push                        commitea, crea el tag y hace push (tag + rama)
#   --dry-run                     no modifica nada
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PLIST="$ROOT/app/Info.plist"

FORCED=""
PUSH=0
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --major) FORCED="major" ;;
    --minor) FORCED="minor" ;;
    --patch) FORCED="patch" ;;
    --push)  PUSH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

git_describe() { git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"; }

LAST_TAG="$(git_describe)"
CURRENT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "0.0.0")"

if [ -n "$FORCED" ]; then
  BUMP="$FORCED"
else
  LOG="$(git -C "$ROOT" log --pretty=format:'%s' "$LAST_TAG"..HEAD 2>/dev/null || true)"
  if echo "$LOG" | grep -qE 'BREAKING CHANGE|!:'; then
    BUMP=major
  elif echo "$LOG" | grep -qE '^feat(\(.*\))?:'; then
    BUMP=minor
  elif echo "$LOG" | grep -qE '^(fix|perf)(\(.*\))?:'; then
    BUMP="patch"
  else
    echo "Sin commits feat/fix/breaking desde $LAST_TAG; se mantiene $CURRENT" >&2
    exit 0
  fi
fi

# Cálculo SemVer (descarta sufijos como -build.42)
BASE="${CURRENT%%-*}"
IFS=. read -r MAJ MIN PAT <<< "$BASE"
case "$BUMP" in
  major) MAJ=$((MAJ + 1)); MIN=0; PAT=0 ;;
  minor) MIN=$((MIN + 1)); PAT=0 ;;
  patch) PAT=$((PAT + 1)) ;;
esac
NEW="$MAJ.$MIN.$PAT"

if [ "$DRY_RUN" = 1 ]; then
  echo "$NEW"
  exit 0
fi

echo "Versión: $CURRENT → $NEW (bump $BUMP)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW" "$PLIST"

if [ "$PUSH" = 1 ]; then
  git -C "$ROOT" add "$PLIST"
  git -C "$ROOT" commit -m "chore: bump versión a $NEW" || true
  git -C "$ROOT" tag "v$NEW"
  git -C "$ROOT" push origin "v$NEW"
  git -C "$ROOT" push origin HEAD
fi
