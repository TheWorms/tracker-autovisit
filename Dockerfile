# Malinois — image autonome (overlay dashboard + outil tracker-autovisit).
# Se construit depuis la RACINE de ton fork tracker-autovisit (là où vit autovisit.py).
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    TZ=Europe/Paris

# 1) Paquets système : nginx, cron, tzdata + utilitaires
#    NB : supervisor n'est PAS installé ici via apt (cf. docker/requirements.txt) — sinon le
#    symlink python3->3.12 ci-dessous casse supervisord (metadata apt sous 3.11).
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx cron tzdata ca-certificates curl procps \
 && rm -f /etc/nginx/sites-enabled/default

# 2) python3 dans /usr/bin pour le shebang appelé par cron (#!/usr/bin/env python3)
RUN ln -sf /usr/local/bin/python3 /usr/bin/python3

# 3) Dépendances Python de la couche Malinois + runtime de collecte
COPY docker/requirements.txt /tmp/req-malinois.txt
RUN pip install -r /tmp/req-malinois.txt

# 4) Navigateur Playwright (Firefox headless) pour les sites à captcha invisible
RUN python3 -m playwright install --with-deps firefox \
 && rm -rf /var/lib/apt/lists/*

# 5) Le code : tout le fork (autovisit.py + overlay) dans /opt/tracker-autovisit
WORKDIR /opt/tracker-autovisit
COPY . /opt/tracker-autovisit

# 5b) Dépendances propres au fork amont, si un requirements.txt est présent à la racine
RUN if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

# 6) Mise en place de l'overlay aux emplacements attendus (identiques à l'install LXC)
RUN set -eux; \
    cp api/web-api.py /opt/tracker-autovisit/web-api.py; \
    chmod 700 /opt/tracker-autovisit/web-api.py; \
    if [ -f autovisit.py ]; then chmod +x autovisit.py; fi; \
    mkdir -p /var/www/autovisit/icones /var/www/autovisit/.logos; \
    cp web/index.html /var/www/autovisit/index.html; \
    cp web/addsite.js /var/www/autovisit/addsite.js; \
    WEBROOT=/var/www/autovisit python3 tools/render_logos.py data/logos-manifest.json || true; \
    if [ -f tools/fetch_favicons.py ] && [ -f data/favicon-targets.json ]; then \
        python3 tools/fetch_favicons.py data/favicon-targets.json || true; \
    fi; \
    chown -R www-data:www-data /var/www/autovisit || true

# 7) Patch build-time de autovisit.py (2FA/session + inspection). Idempotent.
RUN if [ -f autovisit.py ] && [ -f patchers/malinois_patch_2fa.py ]; then \
        python3 patchers/malinois_patch_2fa.py /opt/tracker-autovisit/autovisit.py || true; \
    fi

# 8) Confs runtime + entrypoint
RUN cp docker/nginx.conf /etc/nginx/sites-available/autovisit \
 && ln -sf /etc/nginx/sites-available/autovisit /etc/nginx/sites-enabled/autovisit \
 && cp docker/supervisord.conf /etc/supervisor/supervisord.conf \
 && cp docker/entrypoint.sh /usr/local/bin/entrypoint.sh \
 && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
