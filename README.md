# tracker-autovisit — surcouche Malinois

> **Ceci est un fork.** Le script `autovisit.py` et toute la mécanique de visite sont l'œuvre de [**lol-powa/tracker-autovisit**](https://github.com/lol-powa/tracker-autovisit), lui-même fork divergent de [**Gusdezup/Autovisit**](https://github.com/Gusdezup/Autovisit) (l'auteur original). Je n'ai **pas** écrit l'outil de base : mes contributions se limitent à la couche **Malinois** décrite ci-dessous. Voir la section [Crédits & attribution](#crédits--attribution).

L'outil de base passe quotidiennement sur des sites privés pour éviter la désactivation pour inactivité, collecte les statistiques (ratio, upload, download, bonus…) et prévient en cas de message privé ou de site KO.

## Ce que ce fork ajoute (couche Malinois)

Mes contributions sont une surcouche d'exploitation autour de l'outil, sans modifier sa logique de fond :

- un **tableau de bord web** qui affiche les stats de tous les sites ;
- un **inspecteur** : on choisit un tracker dans une liste, le formulaire se remplit tout seul (plateforme, mode d'authentification, regex de stats, 2FA…), il ne reste qu'à coller ses identifiants ou ses cookies. La récupération du HTML ne se déclenche qu'au clic sur **« Lancer l'inspection »** (pas de visite automatique à l'ouverture) ;
- une **base de trackers pré-configurés** : chaque fiche connaît le mode d'authentification réel qui fonctionne et les regex de stats correctes ;
- une **authentification** du dashboard (connexion par mot de passe avec jauge de robustesse, **2FA TOTP** optionnel) ;
- le **HTTPS gérable depuis l'interface** (certificat auto-signé, import, ou Let's Encrypt) sans toucher à Nginx à la main ;
- la **planification des visites** depuis l'interface (heure, fréquence) et un **visualiseur de logs** (cron, TLS, Let's Encrypt) ;
- des **alertes multi-canaux** (e-mail/SMTP, Telegram, ntfy) déclenchées par des conditions configurables (échec, rétablissement, stats revenues en N/A, récapitulatif), avec un **modèle de message unique et personnalisable** (entête / corps / pied de page, émojis, variables `{site}`/`{statut}`/`{stats}`… cliquables) ;
- une **détection des challenges Cloudflare** : un site qui renvoie une page de défi au lieu de ses stats est marqué **EN ÉCHEC** avec la raison explicite, plutôt qu'un faux « OK » aux stats vides ;
- un **dashboard auto-rafraîchi** (toutes les 30 s et au retour sur l'onglet) et un bouton **« Vider »** par fichier de log ;
- un script de déploiement unique `deploy-addsite.sh` qui installe et met à jour l'ensemble dans un conteneur LXC sur Proxmox.

> **Note** : ce dépôt est à usage personnel. Les fichiers de configuration contenant identifiants, secrets et cookies ne sont **jamais** commités (voir `.gitignore`). À la réinstallation, ces données sont ressaisies via l'inspecteur.

---

<!-- IMAGE : capture du dashboard (vue d'ensemble des trackers et de leurs stats) -->
<!-- ![Dashboard Malinois](docs/img/dashboard.png) -->

<!-- IMAGE : capture de l'inspecteur, formulaire pré-rempli après sélection d'un tracker -->
<!-- ![Inspecteur Malinois](docs/img/inspecteur.png) -->

---

## Architecture

```
Proxmox (hôte, root@<IP_PROXMOX>)
└── Conteneur LXC 100 (<IP_CONTENEUR>)
    ├── /opt/tracker-autovisit/        <- l'outil de base + la couche Malinois
    │   ├── autovisit.py               <- script du repo lol-powa (patché par le deploy)
    │   ├── web-api.py                 <- backend Malinois (inspecteur + édition des sites)
    │   └── data/
    │       ├── sites.d/<slug>.json    <- une config par site (NON commité)
    │       ├── cookies/<slug>.json    <- cookies de session (NON commité)
    │       ├── status.json            <- généré par autovisit --json-output
    │       ├── auth.json              <- auth du dashboard (généré au 1er accès)
    │       └── logs/cron.log
    └── /var/www/autovisit/            <- dashboard web
        ├── index.html                 <- le tableau de bord
        ├── addsite.js                 <- l'overlay inspecteur (base TRACKERS incluse)
        └── .logos/                    <- logos des trackers
```

Le service systemd `autovisit-web` (dans le conteneur) sert le backend `web-api.py`. Le challenge Cloudflare est résolu par **Byparr / FlareSolverr** sur `127.0.0.1:8191`.

---

## Prérequis

### 1. L'hôte Proxmox

Le déploiement se fait depuis l'hôte Proxmox via `pct push` / `pct exec` vers le conteneur. Tu dois donc avoir :

- un hôte Proxmox accessible en SSH (ici `root@<IP_PROXMOX>`) ;
- un conteneur LXC Debian (ici **CTID 100**, IP `<IP_CONTENEUR>`) démarré et avec accès Internet.

> Le numéro de conteneur est défini en haut de `deploy-addsite.sh` par la variable `CT=100`. Adapte-la si ton conteneur a un autre ID.

### 2. Dépendances Python (dans le conteneur)

Le `deploy-addsite.sh` installe `pillow` et `pyotp` automatiquement, mais le **socle** de l'outil de base doit être présent. Dans le conteneur :

```bash
apt install python3 python3-pip
pip install requests pyotp curl_cffi playwright pillow --break-system-packages
playwright install firefox
```

Détail de ce que chaque paquet couvre :

- `requests` + `pyotp` : login form classique, API JSON, 2FA TOTP (le minimum).
- `curl_cffi` : sites Cloudflare / anti-bot (imite l'empreinte TLS de Firefox).
- `playwright` + `firefox` : sites à captcha invisible (login par clé privée façon Nostradamus).
- `pillow` : génération des favicons côté dashboard.

### 3. Byparr / FlareSolverr (dans le conteneur)

Pour les sites avec un vrai challenge Cloudflare (G3MINI, The Old School, Nexum…), un solveur doit tourner en permanence sur `127.0.0.1:8191`.

> **⚠️ FlareSolverr n'est plus activement maintenu.** L'équipe a annoncé l'arrêt du développement, et l'outil devient progressivement moins efficace face aux évolutions de Cloudflare (certains forks ont été archivés fin 2025). Pour un nouveau déploiement, privilégie **[Byparr](https://github.com/ThePhaseless/Byparr)**, une alternative maintenue exposant la même API sur le port `8191` — le code de Malinois fonctionne avec l'un comme l'autre (mutuellement exclusifs sur ce port).

**Installation sans docker (intégrée au script).** Le déploiement peut installer FlareSolverr automatiquement — **sans docker** — via son binaire Linux x64 auto-contenu (qui embarque Chromium + Python), géré en service systemd. C'est **optionnel, au choix de l'utilisateur** lors de l'installation. En terminal interactif (`ssh -t` ou exécution locale) **le script pose directement la question** `[o/N]`. En non-interactif, on force le choix via la variable :

```bash
# Interactif : le déploiement demande s'il faut installer FlareSolverr
ssh -t root@<HOTE_PROXMOX> 'CT_IP=<IP_CONTENEUR> LAN_CIDR=<CIDR_LAN> bash /root/deploy-addsite.sh'

# Non-interactif : réponse forcée
ssh root@<HOTE_PROXMOX> 'CT_IP=<IP_CONTENEUR> LAN_CIDR=<CIDR_LAN> INSTALL_FLARESOLVERR=1 bash /root/deploy-addsite.sh'
```

Sans réponse « oui » (ou `INSTALL_FLARESOLVERR=0`, le défaut), **aucun solveur n'est installé** : le script suppose alors qu'un Byparr/FlareSolverr externe tourne déjà sur `127.0.0.1:8191` si un challenge Cloudflare est nécessaire. Le service installé écoute sur `127.0.0.1:8191` (`systemctl status flaresolverr` pour l'état, `libseccomp2` est installé automatiquement).

Alternative manuelle via docker (héritage) :

```bash
docker run -d --name flaresolverr --restart unless-stopped \
  -p 127.0.0.1:8191:8191 ghcr.io/flaresolverr/flaresolverr:latest
```

> **Important** : le cookie `cf_clearance` est lié à l'**IP** et au **User-Agent**. Le solveur doit sortir sur Internet par la même IP publique que celle utilisée pour récupérer les cookies dans le navigateur.

---

## Installation from scratch

### Étape 1 — Cloner le dépôt dans le conteneur

```bash
git clone https://github.com/TheWorms/tracker-autovisit.git /opt/tracker-autovisit
cd /opt/tracker-autovisit
mkdir -p data/{sites.d,cookies,logs}
```

### Étape 2 — Configuration globale (optionnel)

Pour les notifications mail / ntfy, créer `data/config.json` :

```json
{
    "mail": { "enabled": true, "to": "autovisit@example.org" },
    "ntfy": {
        "enabled": true,
        "url": "https://ntfy.example.org",
        "topic": "autovisit",
        "auth_user": "autovisit",
        "auth_pass": "CHANGE_ME",
        "priority": 4,
        "tags": "warning"
    }
}
```

Sans ce fichier, le script tourne en mode silencieux (logs seulement).

### Étape 3 — Déployer le dashboard et patcher l'outil

Depuis l'hôte Proxmox (pas depuis le conteneur), lancer le script de déploiement. Il faut lui indiquer l'IP du conteneur et la plage réseau autorisée à accéder au dashboard, soit en éditant les variables en haut du script (`CT_IP`, `LAN_CIDR`, `CT`), soit en les passant à l'appel :

```bash
CT_IP=<IP_CONTENEUR> LAN_CIDR=<CIDR_RESEAU_LOCAL> ./deploy-addsite.sh
```

> Le numéro de conteneur (`CT=100`) est défini en haut du script ; adapte-le si besoin. Ces valeurs sont propres à ton infra : ne commite pas tes vraies IP.

Le script effectue 8 étapes (il **patche** `autovisit.py`, il ne le remplace pas) :

| Étape | Action |
|-------|--------|
| 1 | Installe `pillow` + `pyotp` dans le conteneur |
| 2 | Crée les dossiers (`data/logs`, `data/cookies`, `/var/www/autovisit/.logos`…) |
| 3 | Installe les logos des trackers |
| 3b | Récupère les favicons manquants |
| 4 | Déploie le backend `web-api.py` |
| 4b | Patche `autovisit.py` (patches backend Malinois + regex de stats) |
| 5 | Installe et démarre le service systemd `autovisit-web` |
| 6 | Déploie l'overlay inspecteur `addsite.js` (avec la base TRACKERS) |
| 7 | Déploie la page `index.html` du dashboard |

> Le script retire volontairement `set -e` : si une étape intermédiaire échoue (patch, push…), elle ne doit pas empêcher la mise à jour du reste. Chaque commande critique est vérifiée en fin d'exécution.

### Étape 4 — Exposer le dashboard (Nginx)

Rien à écrire à la main : le script de déploiement génère la configuration Nginx tout seul, via le backend (`web-api.py --write-nginx`), à partir de l'état stocké dans `data/tls.json`. Par défaut le site est exposé en **HTTP** sur le port 80, restreint au réseau local (`allow <CIDR_RESEAU_LOCAL>; deny all;`) sur toutes les routes, y compris les fichiers statiques. Le `status.json` reste dans `data/` (hors racine web) et est servi via un proxy interne protégé par l'authentification.

Le passage en **HTTPS** se fait ensuite depuis l'interface, sans toucher à Nginx (voir la section [HTTPS (TLS)](#https-tls)). Le backend est la **source unique** de la configuration Nginx : chaque changement est validé par `nginx -t` avec restauration automatique de la config précédente si le test échoue.

### Étape 5 — Planifier la visite quotidienne (crontab)

> 💡 Le plus simple : depuis le dashboard, onglet **Réglages → Planification**, choisis l'heure et la fréquence (tous les N jours / tous les jours / jours de la semaine). Le backend écrit la ligne crontab pour toi et affiche le crontab actif. La méthode manuelle ci-dessous reste valable pour un premier amorçage ou un réglage hors interface.

Dans le conteneur, une visite par jour suffit :

```cron
0 6 * * * /opt/tracker-autovisit/autovisit.py --json-output >> /opt/tracker-autovisit/data/logs/cron.log 2>&1
```

`--json-output` génère le `status.json` qui alimente le dashboard.

---

## Configurer les trackers via l'inspecteur

C'est ici que Malinois fait gagner du temps. Plutôt que d'écrire à la main chaque `data/sites.d/<slug>.json`, on passe par l'inspecteur du dashboard.

<!-- IMAGE : capture de la liste déroulante de sélection d'un tracker dans l'inspecteur -->
<!-- ![Sélection d'un tracker](docs/img/inspecteur-selection.png) -->

### Principe

1. Ouvrir le dashboard, cliquer sur **« Ajouter un site »**.
2. Choisir le tracker dans la liste.
3. Le formulaire **se pré-remplit automatiquement** : nom, domaine, plateforme, chemin de login, regex de stats, 2FA, Cloudflare, Playwright… selon la fiche du tracker.
4. Compléter ce qui est propre à toi : identifiants, secret TOTP, ou cookies de session + User-Agent.
5. Tester via une revisite, puis sauvegarder.

### Modes d'authentification

Chaque fiche demande exactement ce qu'il faut selon le mode réel du tracker :

| Mode | Le formulaire demande | Exemples |
|------|----------------------|----------|
| Identifiant / mot de passe | identifiant + mot de passe (+ 2FA si requis) | ABNormal, KaraGarga, WiHD, Torr9 |
| Identifiant + 2FA | identifiant + mot de passe + secret TOTP | C411, HD-Forever, Phoenix Project |
| Cookies de session | cookies (une ligne par cookie : nom + valeur) + User-Agent | G3MINI, The Old School, PrivateHD, TR4KER |
| Cookies + pseudo | cookies + User-Agent + pseudo (pour l'URL de stats) | Nexum |
| Clé privée (Playwright) | clé privée | Nostradamus |

> Pour les sites en **cookies de session** : se connecter manuellement au site dans un navigateur (en cochant « Se souvenir de moi » **avant**), ouvrir les DevTools (F12) → **Stockage → Cookies**, puis reporter chaque cookie dans le formulaire **sur sa propre ligne (nom + valeur)** — au minimum le cookie de session et le cookie « se souvenir » (souvent `remember_*` / `remember_web_*`), plus `cf_clearance` si le site est derrière Cloudflare. Relever les valeurs depuis l'onglet **Stockage** (pas l'onglet *Réseau*) évite la troncature « … » ; le formulaire refuse d'ailleurs une valeur tronquée. Les cookies expirent (de ~30 min pour `cf_clearance` à plusieurs mois pour le cookie persistant) ; quand un site repasse en N/A ou EN ÉCHEC, c'est le signal pour réinjecter des cookies frais.

### Cas particulier : Nexum (cookies + pseudo)

Nexum lit ses statistiques principales (upload, bonus, downloads, ratio, classe) depuis une page profil dont l'URL contient le pseudo. En mode cookie, le formulaire affiche donc **en plus** un champ « Pseudo sur le tracker » à renseigner. L'URL de stats est construite automatiquement avec ce pseudo. Si le pseudo est oublié, le test affiche un avertissement explicite plutôt que d'échouer silencieusement.

<!-- IMAGE : capture du formulaire Nexum, avec le champ pseudo visible en mode cookie -->
<!-- ![Formulaire Nexum](docs/img/inspecteur-nexum.png) -->

---

## Alertes

Malinois peut **notifier** quand l'état d'un tracker change, via **e-mail (SMTP)**, **Telegram** et **ntfy** (webhook). Dans l'onglet *Réglages → Alertes* :

- on active et configure chaque canal indépendamment, avec un bouton **« Tester »** par canal ;
- on choisit les **conditions** de déclenchement : un site passe **en échec**, un site se **rétablit**, des **stats reviennent en N/A** (cookie probablement expiré), ou un **récapitulatif à chaque exécution** ;
- un **modèle de message unique** (commun à tous les canaux) se compose tout en bas de l'onglet : **entête / corps / pied de page**, avec une barre d'**émojis** et des **variables cliquables** (`{site}`, `{statut}`, `{stats}`, `{date}`, `{heure}`, `{nb_echec}`, `{sites}`…) insérées au curseur, plus un **aperçu en direct**. Laisser le modèle vide = message par défaut selon l'événement.

---

## Trackers pré-configurés

La base TRACKERS (incluse dans `addsite.js`) contient les fiches suivantes, alignées sur le mode d'authentification réel qui fonctionne :

| Tracker | Plateforme | Authentification | 2FA |
|---------|-----------|------------------|-----|
| ABNormal | ASP.NET | identifiant / mot de passe | non |
| C411 | API JSON | identifiant / mot de passe | oui |
| G3MINI | UNIT3D | cookies de session | non |
| HD-Forever | Gazelle | identifiant / mot de passe | oui |
| KaraGarga | form | identifiant / mot de passe | non |
| Nexum | UNIT3D | cookies + pseudo | non |
| Nostradamus | form | clé privée (Playwright) | non |
| Phoenix Project | Gazelle | identifiant / mot de passe | oui |
| PrivateHD | UNIT3D | cookies de session | non |
| The Old School | UNIT3D | cookies de session | non |
| Torr9 | API JSON | identifiant / mot de passe | non |
| TR4KER | API JSON | cookies de session | non |
| WiHD | form | identifiant / mot de passe | non |

---

## Mises à jour

Pour mettre à jour le dashboard, l'inspecteur ou les patches backend : modifier `deploy-addsite.sh` (incrément de version en commentaire d'en-tête) puis le relancer depuis l'hôte. Le script est idempotent : les patches backend vérifient leur propre présence avant de s'appliquer, et le dashboard est simplement réécrit.

### Commande de déploiement / mise à jour

Le déploiement se fait depuis un poste ayant accès à l'hôte Proxmox : on copie le script sur l'hôte, puis on l'exécute en ciblant le conteneur via les variables `CT_IP` et `LAN_CIDR`.

```bash
# 1. Copier le script sur l'hôte Proxmox
scp ~/Téléchargements/deploy-addsite.sh root@<HOTE_PROXMOX>:/root/deploy-addsite.sh

# 2. Déployer (-t = terminal interactif : le script demande s'il faut installer FlareSolverr)
ssh -t root@<HOTE_PROXMOX> 'CT_IP=<IP_CONTENEUR> LAN_CIDR=<CIDR_LAN> bash /root/deploy-addsite.sh'

# Pour répondre sans question (automatisation) : forcer via la variable (1=oui, 0=non)
ssh root@<HOTE_PROXMOX> 'CT_IP=<IP_CONTENEUR> LAN_CIDR=<CIDR_LAN> INSTALL_FLARESOLVERR=1 bash /root/deploy-addsite.sh'
```

> ⚠️ **Branche privée uniquement.** Les valeurs réelles (IP de l'hôte/conteneur, CIDR) ne doivent figurer **que** sur la branche privée — jamais sur un dépôt public.

**Autres commandes utiles** (dans le conteneur) :

```bash
grep -o 'MALINOIS_VER="[0-9]*"' /var/www/autovisit/addsite.js   # version déployée
journalctl -u autovisit-web -f                                  # logs backend
systemctl restart autovisit-web                                 # redémarrer le backend
systemctl status flaresolverr                                   # état du solveur (si installé)
python3 /opt/tracker-autovisit/autovisit.py --json-output       # visite manuelle de tous les trackers
```

Les fichiers `data/sites.d/*.json` du conteneur sont la **source de vérité** : ils ne sont jamais écrasés par le déploiement. Le patcher de regex est volontairement neutre (il ne réécrit aucune config existante).

### Garde-fou authentification

Si le dashboard se verrouille (auth perdue), dans le conteneur :

```bash
rm /opt/tracker-autovisit/data/auth.json
systemctl restart autovisit-web
```

---

## Utilisation de l'outil de base

```bash
autovisit                       # visite par défaut (pas de notif si tout va bien)
autovisit --site MonSite        # un seul site
autovisit --json-output         # exporte status.json (utilisé par le dashboard)
autovisit --verbose             # récap détaillé
autovisit --list                # liste tous les sites configurés
```

Pour la documentation complète des champs de configuration (`stats`, `stats_json`, `extra_url`, `cf_solver`, `use_playwright`, `session_cookies_file`…), voir le [README du repo d'origine](https://github.com/lol-powa/tracker-autovisit).

---

## Sécurité

- `data/config.json`, `data/sites.d/*.json` et `data/cookies/*.json` contiennent des mots de passe, secrets TOTP et cookies en clair. **Tous sont dans `.gitignore`** et ne doivent jamais être commités.
- Dans le conteneur, restreindre leurs permissions : `chmod 600 data/config.json data/sites.d/*.json data/cookies/*.json`.
- Le `status.json` exposé via Nginx ne contient que des stats agrégées, pas de secrets.

---

## HTTPS (TLS)

Le dashboard se gère en HTTP par défaut, et peut être chiffré en HTTPS **entièrement depuis l'interface** (menu **Sécurité**), sans éditer Nginx à la main. Le backend reste la source unique de la configuration Nginx et chaque bascule est validée par `nginx -t` avec rollback automatique en cas d'échec.

### Activer le HTTPS

Dans **⚙️ → Sécurité → section HTTPS** :

1. Obtenir un certificat, au choix :
   - **Générer un certificat local (auto-signé)** — un clic. Le certificat couvre l'IP du conteneur (SAN). C'est l'option immédiate pour un accès LAN par IP ; le navigateur affichera un avertissement « non sécurisé » tant que tu n'auras pas importé le certificat dans ton navigateur/OS.
   - **Importer un certificat** — colle ton certificat (PEM, *fullchain*) et ta clé privée (PEM). Le backend valide les deux formats **et** vérifie que la clé correspond au certificat avant de l'installer. Idéal si tu as déjà un certificat pour un vrai nom de domaine.
2. Activer le **toggle HTTPS**. La page bascule sur `https://` (port 80 → redirection 301 vers 443). Le cookie de session passe en `Secure`.

Pour revenir en HTTP : désactiver le toggle.

### Filet de sécurité (anti-verrouillage)

Comme l'application reconfigure son propre Nginx, garde cette commande sous la main : elle force le retour en HTTP (supprime l'état TLS, régénère la conf, recharge Nginx) si jamais tu te retrouves bloqué.

```bash
ssh root@<IP_PROXMOX> 'pct exec 100 -- bash -c "rm -f /opt/tracker-autovisit/data/tls.json && \
  env MAL_CT_IP=<IP_CONTENEUR> MAL_LAN_CIDR=<CIDR_RESEAU_LOCAL> MAL_WEBROOT=/var/www/autovisit \
  python3 /opt/tracker-autovisit/web-api.py --write-nginx && nginx -t && systemctl reload nginx"'
```

### Notes

- Les certificats sont stockés dans `data/tls/` (clé privée en `0600`) et l'état dans `data/tls.json` — tous deux hors `git` et hors racine web.
- Au redéploiement, l'état HTTPS est conservé : le script régénère la conf Nginx selon `data/tls.json`.
- **Let's Encrypt / Certbot** (certificat reconnu, renouvellement automatique) nécessite un vrai nom de domaine pointant vers le conteneur ; non couvert par les deux modes ci-dessus (prévu séparément).

---

Avant une réinstallation, sauvegarder les configs et cookies qui fonctionnent (depuis l'hôte) :

```bash
ssh root@<IP_PROXMOX> 'pct exec 100 -- tar czf /tmp/backup-sites.tgz \
  -C /opt/tracker-autovisit/data sites.d cookies'
```

À la réinstallation from scratch, la base TRACKERS donne la **structure** correcte (plateforme, regex, mode d'auth) dès le départ ; il reste à ressaisir les secrets et à réinjecter des cookies frais via l'inspecteur.

---

## Organisation Git

Dépôt à **une seule branche `main`**, poussée sur deux distants :
- **Forgejo auto-hébergé** (privé) — ce `README` avec les vraies commandes de déploiement, notes d'infra.
- **GitHub** (public) — fork de `tracker-autovisit`.

**Aucun identifiant ni cookie** n'y est commité — voir `.gitignore` et la section *Sécurité* (`data/sites.d/*.json`, `data/cookies/*.json`, `data/auth.json`… sont ignorés).

La variante conteneurisée n'a **pas de branche dédiée** : le squelette Docker (`Dockerfile`, `docker-compose.yml`…) vit dans le dossier `docker/` sur `main`, à adapter et construire au besoin.

---

## Crédits & attribution

Ce projet est un **fork** et ne serait rien sans le travail des auteurs en amont. La généalogie :

1. **[Gusdezup/Autovisit](https://github.com/Gusdezup/Autovisit)** — l'auteur original. C'est lui qui a créé le script Python de visite automatique, la détection CSRF, le support TOTP, les notifications, et la structure de configuration par site.

2. **[lol-powa/tracker-autovisit](https://github.com/lol-powa/tracker-autovisit)** — fork divergent de Gusdezup, qui a notamment ajouté le support FlareSolverr (Cloudflare), Playwright (captcha invisible), les cookies de session, davantage de types de sites (XenForo, Symfony, SPA, Phoenix LiveView…), une première interface web, et les `extra_url` / `extra_stats`. **C'est de ce dépôt que je suis directement parti** : tout le code de `autovisit.py` lui revient.

3. **Ce dépôt ([TheWorms/tracker-autovisit](https://github.com/TheWorms/tracker-autovisit))** — mes contributions se limitent à la **couche Malinois** : le dashboard web (`index.html`), l'inspecteur (`addsite.js` + sa base de trackers), le backend `web-api.py`, et le script de déploiement `deploy-addsite.sh` pour conteneur LXC sur Proxmox. Je n'ai **pas** réécrit l'outil de base ; mes patches l'enrichissent sans en modifier la logique de fond.

En clair : le moteur est l'œuvre de Gusdezup puis de lol-powa. Je n'ai fait qu'ajouter une surcouche d'exploitation par-dessus. Tout le mérite de l'outil leur revient — un grand merci à eux.

> La licence et les conditions d'usage sont celles du dépôt d'origine. Ce fork est partagé dans le même esprit.
