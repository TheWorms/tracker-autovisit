#!/usr/bin/env bash
# Malinois – entrypoint conteneur : prépare les données persistantes, planifie la
# collecte, puis passe la main à supervisord (nginx + web-api + cron).
set -e

BASE=/opt/tracker-autovisit
DATA="$BASE/data"
WEBROOT=/var/www/autovisit

# 1) Fuseau horaire (le cron "à 6h" suit cette TZ)
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

# 2) Arborescence des données (le volume peut être vide au 1er lancement)
mkdir -p "$DATA/sites.d" "$DATA/cookies" "$DATA/logs" "$DATA/.sitebak" "$DATA/.statsbak"
touch "$DATA/logs/cron.log"
mkdir -p "$WEBROOT/icones"
chown -R www-data:www-data "$WEBROOT" 2>/dev/null || true

# 2.5) Config globale : semer data/config.json depuis le gabarit si absent (volume vide
#      au 1er lancement). autovisit.py exige ce fichier ; on évite ainsi un exit(1).
if [ ! -f "$DATA/config.json" ] && [ -f "$BASE/config.example.json" ]; then
  cp "$BASE/config.example.json" "$DATA/config.json"
  echo "[entrypoint] data/config.json créé depuis config.example.json (édite-le pour activer mail/ntfy)."
fi

# 3) Patch runtime des regex sites.d (no-op en v78.1, idempotent, future-safe)
if [ -f "$BASE/patchers/malinois_patch_stats.py" ]; then
  python3 "$BASE/patchers/malinois_patch_stats.py" 2>/dev/null || true
fi

# 4) Crontab par défaut si aucune collecte planifiée (modifiable ensuite via l'UI,
#    ou ici via CRON_SCHEDULE). La ligne PATH garantit que python3 est trouvé par cron.
if ! crontab -l 2>/dev/null | grep -q "autovisit.py"; then
  {
    echo "PATH=/usr/local/bin:/usr/bin:/bin"
    printf '%s %s --json-output >> %s 2>&1\n' \
      "${CRON_SCHEDULE:-0 6 * * *}" "$BASE/autovisit.py" "$DATA/logs/cron.log"
  } | crontab -
  echo "[entrypoint] crontab par défaut posé : ${CRON_SCHEDULE:-0 6 * * *}"
fi

echo "[entrypoint] Malinois prêt — démarrage des services."
exec "$@"
