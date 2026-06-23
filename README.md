# MALINOIS

> Tableau de bord web pour l'outil [`tracker-autovisit`](https://github.com/lol-powa/tracker-autovisit) :
> un cron visite chaque tracker privé, extrait les stats par **regex**, et MALINOIS les
> affiche dans un tableau triable avec un **inspecteur** pour éditer les regex en direct.
>
> Fork : Gusdezup → lol-powa → MALINOIS. Toute la couche dashboard est ajoutée par-dessus l'outil amont.

---

## Aperçu

Le tableau de bord regroupe les stats de tous tes trackers privés sur une seule page :
upload, download, ratio, bonus/points, en seed, rang et dernière connexion. Chaque colonne
est triable et chaque ligne propose des actions rapides (revisite, édition, inspecteur, suppression).

![Tableau de bord MALINOIS](docs/img/dashboard.png)

---

## Fonctionnalités

- Agrégation des stats de trackers privés (UNIT3D, Gazelle, formulaires classiques…).
- Trois modes de connexion anti-Cloudflare par site : empreinte TLS Firefox (`curl_cffi`),
  captcha invisible (Playwright headless), challenge complet (Byparr).
- Inspecteur de regex en direct sur un dump du HTML reçu, avec sauvegarde/restauration.
- Authentification (login + 2FA optionnel), thème clair/sombre, icônes par tracker.
- Collecte planifiée par cron, journaux consultables et mode **Live**.

---

## Installation avec Docker (recommandé)

L'image est **générique** : elle s'installe partout où tourne Docker (VM, NAS, bare-metal…),
sans dépendre d'un conteneur LXC. Tous les chemins internes sont fournis par l'image ; seules
les **données** vivent dans un volume monté (`./data`).

> ⚠️ Construis l'image depuis la **racine de ton fork `tracker-autovisit`** : c'est là que vit
> `autovisit.py` (l'outil de collecte), que le `Dockerfile` embarque avec la couche MALINOIS.

```bash
# Depuis la racine de ton fork tracker-autovisit (qui contient autovisit.py)
cp .env.example .env          # ajuste le port, la TZ, le planning cron si besoin
docker compose up -d --build
```

Le dashboard est ensuite accessible sur `http://localhost:8080` (port configurable via `MALINOIS_PORT`).

Deux conteneurs sont lancés :

- **`malinois`** : nginx + l'API web + le cron de collecte, dans une seule image.
- **`byparr`** : le solveur Cloudflare. Il partage la pile réseau de `malinois`, donc il reste
  joignable sur `127.0.0.1:8191` — exactement comme l'attendent les configs de site existantes
  (`cf_solver`), sans aucune modification à faire.

### Premier lancement

1. Ouvre le dashboard, puis **Configuration → Sécurité** pour poser un mot de passe
   (et activer la 2FA si tu veux) — fais-le tout de suite si le service est exposé au-delà de `localhost`.
2. Ajoute tes trackers (voir ci-dessous) ou restaure ton dossier `data/` existant dans le volume.

### Ajouter un site

Le bouton **+** ouvre la recherche de trackers : tape le nom, MALINOIS propose les trackers
connus de sa base avec leur plateforme détectée.

![Ajouter un site](docs/img/add_site.png)

### Configurer un tracker

La fiche d'édition règle la connexion (domaine, plateforme, chemin de login, texte attendu dans
l'URL) et surtout le bloc **Stats** : les regex appliquées au HTML de la page d'accueil connectée
pour en extraire les chiffres. C'est ici qu'on choisit le mode anti-Cloudflare du site.

![Édition d'un tracker](docs/img/preconfig.png)

### Réactualiser et inspecter

Dans **Configuration → Statistiques**, chaque tracker se réactualise individuellement, s'inspecte
(ajustement des regex en direct sur un dump du HTML) ou se restaure à sa dernière sauvegarde.
**Tout réactualiser** relance la collecte sur l'ensemble des sites.

![Configuration des statistiques](docs/img/stats.png)

### Logs en direct

L'onglet **Configuration → Logs** affiche `cron.log` (et les autres journaux) dans une console
colorée, avec un mode **Live** pour suivre une collecte en temps réel.

![Logs](docs/img/logs.png)

---

## Configuration (variables d'environnement)

Définies dans `.env` (copié depuis `.env.example`) :

| Variable | Défaut | Rôle |
|---|---|---|
| `MALINOIS_PORT` | `8080` | Port HTTP publié sur l'hôte |
| `TZ` | `Europe/Paris` | Fuseau horaire (cron + Byparr) |
| `CRON_SCHEDULE` | `0 6 * * *` | Planning par défaut de la collecte (modifiable dans l'UI) |
| `BYPARR_IMAGE` | `ghcr.io/thephaseless/byparr:latest` | Image du solveur (FlareSolverr possible) |

---

## Données & sauvegarde

Tout l'état persistant est dans `./data` (monté en volume) :

```
data/
├── sites.d/        # configs des sites (domaines, regex, secrets) — sensible
├── cookies/        # cookies de session
├── logs/           # cron.log, visit_YYYY-MM.log
├── .sitebak/       # sauvegardes auto des configs
├── .statsbak/      # sauvegardes auto des regex (bouton "Restaurer")
├── _webicones/     # icônes custom uploadées via l'UI
├── auth.json       # identifiants du dashboard (auth)
├── status.json     # dernières valeurs extraites
└── settings.json   # réglages du dashboard
```

Pour **sauvegarder**, archive simplement le dossier `data/`. Pour **désactiver l'auth** si tu te
verrouilles dehors :

```bash
docker compose exec malinois rm -f /opt/tracker-autovisit/data/auth.json
docker compose restart malinois
```

> Le `.gitignore` exclut `data/` et `.env` : tes secrets ne partent jamais dans le dépôt.

---

## Installation classique (sans Docker)

L'installeur `deploy-addsite.sh` reste disponible pour une install directe :

```bash
# Sur la machine qui héberge tracker-autovisit (VM, bare-metal, LXC où tu as un shell)
MODE=local CT_IP=192.168.0.50 LAN_CIDR=192.168.0.0/24 ./deploy-addsite.sh

# Ou poussé depuis un hôte Proxmox vers un conteneur LXC
MODE=lxc CT=100 CT_IP=192.168.0.50 LAN_CIDR=192.168.0.0/24 ./deploy-addsite.sh
```

Dans ce mode, nginx/systemd/cron sont configurés directement sur la cible (le filtrage IP par
`LAN_CIDR` y est appliqué). La version Docker, elle, s'appuie sur l'auth applicative + ton pare-feu.

---

## Structure du dépôt

```
.
├── Dockerfile                 # image autonome (overlay + outil)
├── docker-compose.yml         # malinois + byparr
├── .env.example
├── docker/
│   ├── entrypoint.sh          # prépare le volume, planifie le cron, lance supervisord
│   ├── supervisord.conf       # nginx + web-api + cron
│   ├── nginx.conf             # reverse proxy générique
│   └── requirements.txt       # deps overlay + runtime
├── deploy-addsite.sh          # installeur classique (MODE=local|lxc)
├── api/web-api.py             # backend (gestion sites, réglages, auth, inspecteur)
├── web/{index.html,addsite.js}# dashboard
├── patchers/                  # patches additifs pour autovisit.py
├── tools/                     # render_logos.py, fetch_favicons.py
├── systemd/, nginx/           # unités pour l'install classique
├── data/                      # manifeste logos + cibles favicons (le reste est runtime, ignoré par git)
└── docs/img/                  # captures du README
```
