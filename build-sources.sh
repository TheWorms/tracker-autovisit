#!/usr/bin/env bash
#
# build-sources.sh — reconstruit l'arbre de sources « éclaté » à partir de
# deploy-addsite.sh, qui reste la SOURCE UNIQUE de vérité.
#
# deploy-addsite.sh embarque tout le dashboard sous forme de heredocs ; ce script
# les en extrait vers api/ web/ patchers/ tools/ systemd/ data/, et décode les
# logos (base64 du manifest) vers web/icones/. Utile pour le build Docker ou pour
# lire/éditer les sources, sans jamais dupliquer le code à la main.
#
# Usage :  ./build-sources.sh [chemin/vers/deploy-addsite.sh]
#
set -euo pipefail

SRC="${1:-deploy-addsite.sh}"
[ -f "$SRC" ] || { echo "Introuvable : $SRC" >&2; exit 1; }

# Extrait le contenu d'un heredoc « cat > /tmp/x << 'MARQUEUR' ... MARQUEUR »
# vers un fichier. Gère les marqueurs quotés ('EOF') et non quotés (EOF).
extract() {
  local eof="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  awk -v eof="$eof" '
    function tail(s){ sub(/^.*<< */,"",s); gsub(/[\042\047]/,"",s); gsub(/[ \t]+$/,"",s); return s }
    !f && /cat >/ && index($0,"<<") { if (tail($0)==eof){ f=1; next } }
    f && $0==eof { f=0; next }
    f { print }
  ' "$SRC" > "$out"
  if [ -s "$out" ]; then
    printf '  ok   %-38s (%s lignes)\n' "$out" "$(wc -l < "$out")"
  else
    printf '  KO   %-38s (vide)\n' "$out"; rm -f "$out"; return 1
  fi
}

echo "Extraction des heredocs depuis $SRC :"
extract PYEOF    api/web-api.py
extract JSEOF    web/addsite.js
extract IDXEOF   web/index.html
extract P2FAEOF  patchers/malinois_patch_2fa.py
extract STATEOF  patchers/malinois_patch_stats.py
extract UNITEOF  systemd/autovisit-web.service
extract FAVPY    tools/fetch_favicons.py
extract MANEOF   data/logos-manifest.json
extract FAVEOF   data/favicon-targets.json

echo "Terminé. Sources éclatées régénérées à partir de $SRC."
echo "(Les logos/favicons sont produits séparément : render_logos.py + fetch_favicons.py au build.)"
