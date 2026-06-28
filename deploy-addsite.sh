#!/usr/bin/env bash
# deploy-addsite.sh v123 — auth (login + 2FA optionnel), HTTPS gerable depuis l'UI (auto-signe / import),
# v83 : menu Securite > HTTPS (toggle, cert auto-signe ou importe), nginx genere par le backend
# (--write-nginx, rollback nginx -t), cookie Secure, restriction LAN des fichiers statiques + en-tetes securite.
# v84 : fix routage nginx des routes /tls/ (location ~ ^/tls/ dediee, deux segments).
# v85 : formulaire d'infos du certificat auto-signe (CN, SAN, organisation, pays, validite) avant generation.
# v86 : mode Let's Encrypt/Certbot (HTTP-01 webroot, renouvellement auto via hook), location ACME ouverte.
# v87 : durcissements auth (mdp min 8, throttle login 5/300s -> 429, rotation server_secret au changement, plafond corps 8 Mo).
# v88 : mot de passe confirme (2e champ) + jauge de robustesse live, avec controle cote backend.
# v89 : durcissements P3 (favicon plafonne 2 Mo + limite pixels anti-bombe ; nom de site interdit de commencer par -).
# v90 : durcissement systemd sur (ProtectKernel*, ProtectControlGroups, ProtectClock, RestrictRealtime, LockPersonality).
# v91 : logs cert (data/logs/tls.log) ; inspection a la demande (bouton "Lancer l'inspection", plus de visite auto a l'ouverture) ; gestion crontab dans l'admin (heure/minute + tous les N jours / tous les jours / jours choisis, apercu + crontab actif).
# v92 : HOTFIX init JS (bindCron appele apres creation de l'overlay reglages ; corrige le dashboard vide en v91).
# v93 : cron dans un onglet dedie Planification ; route logs liste toujours cron.log + tls.log (visibles meme vides).
# v94 : bouton 2FA a la couleur d'accent (orange) au lieu du cyan (la classe etait reappliquee par le JS).
# v95 : bac a sable systemd durci en root (ProtectSystem=full + ReadWritePaths /etc/nginx -/etc/letsencrypt + PrivateTmp) : /usr et /etc en lecture seule.
# v96 : sandbox systemd RETIREE entierement (cassait le service) + nettoyage de tout override residuel ; ajout de letsencrypt.log (journal certbot) dans l'onglet Logs.
# v97 : cookie Secure base sur le protocole reel (X-Forwarded-Proto transmis par nginx) au lieu de l'etat TLS global -> corrige dashboard vide / login en boucle en HTTP.
# v98 : version de l'app affichee sous le menu (haut-droite) uniquement ; logs des inspections (data/logs/inspect.log) dans l'onglet Logs ; nouvel onglet Alertes (email SMTP / Telegram / webhook-ntfy) avec test d'envoi et alerte automatique sur echec de visite.
# v99 : version d'affichage decouplee (APP_VERSION="0.97", centree sous le menu, padding haut 10px) du build interne ; onglet Alertes : choix des types d'alerte envoyes (echec / retablissement / resume a chaque visite).
# v100 : onglet Alertes : bouton de test PAR canal (email / Telegram / webhook) testant chaque config separement (ignore le flag actif), en plus du test global ; envoi factorise en _send_email/_send_telegram/_send_webhook.
# v101 : onglet Alertes : bouton Enregistrer PAR canal (plus de save global, mise a jour ciblee sans ecraser les autres) ; conditions enregistrees automatiquement ; notifications navigateur (Notification API, alerte a l'ecran sur nouvel echec) ; logs d'envoi des alertes (data/logs/alerts.log) dans l'onglet Logs.
# v102 : version affichee derivee du build (build/100, ex. 1.02) ; messages de succes en VERT (nouvelle var --good) au lieu de l'orange d'accent ; meilleur contraste des bandeaux resultat (ok/ko, themes clair+sombre) ; le bandeau resultat est efface au changement d'onglet (plus d'erreur 2FA persistante sur un autre onglet).
# v103 : echecs d'enregistrement au vrai rouge --ko (var --bad inexistante remplacee, correct en theme clair) ; hover des boutons tools (theme/+/reglages/deconnexion) a la couleur d'accent comme les actions ; placeholder "min. 8 caracteres" ajoute au champ de confirmation du mot de passe.
# v104 : hover repense -> FOND d'accent (au lieu de colorer l'icone) sur les boutons tools (icone blanche) et FOND teinte sur les actions des lignes (la couleur d'icone ed/de/on/off ecrasait le hover par specificite egale) ; override de hover dedie au theme clair pour les actions.
# v105 : possibilite de supprimer le logo personnalise (bouton "Supprimer le logo" dans Apparence, visible seulement si un logo existe ; backend delete_favicon + route /favicon {delete:true} -> retire favicon.png/.ico/apple-touch-icon et remet favicon=false).
# v106 : hover des actions des lignes -> fond plein accent + icone blanche (comme tools, .av-actions .av-act:hover pour battre les couleurs d'icone ed/de) ; hover visible (fond accent) sur le bouton "Retour au dashboard" (etait un ghost a peine perceptible) ; closeSettings rendu infaillible (try/catch -> fermeture garantie meme si une etape echoue).
# v107 : en-tete "Actions" ajoute au-dessus de la colonne des boutons d'action (coherence avec les autres colonnes ; aligne a droite comme les boutons, non triable).
# v108 : hover accent (fond teinte) sur les onglets de configuration, via :not(.active) pour que l'onglet selectionne garde son fond plein accent (sombre + clair).
# v109 : hover des onglets passe en fond plein accent + texte BLANC (au lieu du fond teinte/texte orange trop attenue), coherent avec tools et l'onglet actif.
# v110 : hover des elements DEJA orange (boutons Enregistrer/save/go, onglet actif, + accent, bouton login) -> on fonce l'accent (color-mix 85% + noir) au lieu de l'eclaircir (brightness washait l'orange) ; bouton "Parcourir..." de l'input fichier stylise (bordure + hover orange plein/texte blanc, sombre + clair).
# v111 : harmonisation des boutons d'action -> ghost/test/go/save passent en style NEUTRE (contour, "non selectionne") avec hover orange plein + texte blanc (sombre + clair) ; les Enregistrer ne sont plus orange par defaut (gras conserve pour rester l'action principale) ; concerne Generer/Obtenir un certificat, Supprimer le logo, Tester (e-mail/Telegram/webhook/notif/regex), Inspecter/Lancer l'inspection, Restaurer, Recharger, Reactualiser. Restent orange : onglet actif, bouton +, login (etats reellement actifs) ; fail/danger restent rouges.
# v112 : clic sur le logo (actualisation) -> affiche "Actualise : <date + heure>" du MOMENT de l'actualisation (heure locale du navigateur, jj/mm/aaaa hh:mm) au lieu de "Mis a jour : <heure de mise a jour serveur des donnees>".
# v113 : onglets config -> FIX texte de l'onglet actif en theme clair (etait gris-brun car html:not(.av-dark) .cfg-tab ecrasait le color:#fff par specificite) : regle dediee html:not(.av-dark) .cfg-tab.active = blanc + gras. Hover des onglets non-actifs repense : fond clair (teinte accent 12%) + bordure orange + texte orange (au lieu du remplissage orange plein), pour distinguer nettement du selectionne. Bordure transparente ajoutee a la base (.cfg-tab border:1px solid transparent) pour eviter tout decalage au survol.
# v114 : bouton "Se deconnecter" (id av-logout) -> hover ROUGE (var(--ko) : corail en sombre, rouge franc en clair) au lieu de l'orange generique des av-tbtn, pour signaler clairement la sortie. ID = priorite sur les hovers orange des deux themes.
# v115 : couleur d'accent appliquee en !important (l'inline bat toute regle :root, meme un CSS perso residuel) ; FIX toggles/cases qui ne suivaient PAS l'accent (accent-color #e3a857 code en dur + bordure de focus #e3a857 -> var(--ok)) ; les .av-check deviennent des CARRES toggle (appearance:none, remplissage accent + coche blanche au coche, hover/focus accent) au lieu des checkbox natives ; label "Couleur d'accent" renomme "Couleur bouton".
# v116 : FIX CACHE du dashboard -> la racine "location = /" n'avait PAS d'en-tete no-store (seul /index.html exact l'avait), donc le navigateur servait une vieille version en cache (la couleur ne semblait pas prise en compte). Ajout de no-store sur / ; le ?v= d'addsite.js suit desormais le build (116) et est horodate a chaque deploiement (anti-cache garanti). Apres deploiement : un rafraichissement force (Ctrl+Maj+R) une fois suffit a purger l'ancien cache.
# v117 : section Apparence repensee -> "Couleur bouton" renomme "Colorisation" ; le selecteur de couleur devient un petit rectangle compact (48x30) ; "Theme sombre par defaut" passe en vrai toggle bascule (.av-switch, piste accent au coche) ; les deux controles + leurs libelles sont desormais sur UNE seule ligne (.av-coltheme, flex).
# v118 : ajout du tracker TeamOS (teamos.xyz, plateforme XenForo) a la base : login /login/ -> POST /login/login, champs login/password, CSRF _xfToken, remember, verif /account/. Entree login-only (selecteurs de stats a affiner via l'inspecteur si besoin).
# v119 : TeamOS -> ajout des selecteurs de stats (download torrentUserDownloaded, upload torrentUserUploaded, ratio torrentUserRatio, bonus torrentUserSeedbonus, class userBanner) extraits du HTML du profil XenForo. Stats sur la page de profil membre : pointer la page de verif/stats du site sur /members/<slug>.<id>/.
# v120 : TeamOS reconfigure sur le modele Nexum (stats sur page profil) -> mode cookie + URL de stats parametree par {{username}} (xf.u = /members/{{username}}/). Le champ "Pseudo sur le tracker (pour l'URL de stats)" s'affiche : y mettre le slug complet du profil (ex. monpseudo.123456). Login par formulaire retire (incompatible : le slug XenForo != identifiant de login).
# v121 : option INSTALL_FLARESOLVERR=1 -> installe FlareSolverr SANS docker (binaire x64 auto-contenu + service systemd sur 127.0.0.1:8191, libseccomp2 auto). Defaut 0 = non installe (solveur externe attendu). README enrichi : commandes de deploiement/mise a jour, doc de l'option FlareSolverr, section Organisation Git (branche main privee + branche docker + propagation via merge ou action Forgejo). Squelette docker/ + .forgejo/workflows/sync-docker.yml ajoutes.
# v122 : l'option FlareSolverr est desormais INTERACTIVE -> en terminal (ssh -t ou local) le script DEMANDE "Installer FlareSolverr ? [o/N]" ; la variable INSTALL_FLARESOLVERR reste prioritaire pour l'automatisation (non-interactif => defaut non). README + commandes mis a jour (ssh -t).
# v123 : nouvelle alerte "Statistiques non recuperees" -> si un site est OK (connecte) mais que son upload revient N/A (vide ou "N/A"), envoi d'une alerte signalant des stats non recuperees (cause probable : cookie expire/renouvellement echoue). Nouvelle case dans l'onglet Alertes (on_stats_na), anti-spam via _last_stats_na, ne concerne que les sites exposant un champ upload.
# auth par cle (Nostradamus), rendu propre, logos, configs git fideles.
# GARDE-FOU : pour desactiver l'auth si verrouille -> 'rm /opt/tracker-autovisit/data/auth.json' puis 'systemctl restart autovisit-web' (dans le conteneur).
# set -e RETIRE volontairement : une etape intermediaire qui echoue (patcher,
# daemon-reload, push…) ne doit JAMAIS empecher la mise a jour d'addsite.js / index.html
# / web-api.py ni le redemarrage du service. Chaque commande critique est verifiee en fin.
set +e
CT=100
# === À configurer pour ton infra (ne PAS committer tes vraies valeurs) ===
# IP du conteneur (server_name Nginx) et plage réseau autorisée à accéder au dashboard.
# Surcharge possible à l'appel : CT_IP=10.0.0.5 LAN_CIDR=10.0.0.0/24 ./deploy-addsite.sh
CT_IP="${CT_IP:-CHANGE_ME_IP_CONTENEUR}"
LAN_CIDR="${LAN_CIDR:-CHANGE_ME_CIDR_LAN}"
# Option : installer FlareSolverr (solveur Cloudflare). Au choix de l'utilisateur :
#   - demandé interactivement si le terminal le permet (lancer avec ssh -t, ou en local) ;
#   - sinon piloté par la variable INSTALL_FLARESOLVERR (1=oui, 0=non ; défaut : non).
if [ -z "${INSTALL_FLARESOLVERR:-}" ]; then
  if [ -t 0 ]; then
    printf "  → Installer FlareSolverr (solveur Cloudflare, sans docker, sur 127.0.0.1:8191) ? [o/N] "
    read -r _fs_ans
    case "$_fs_ans" in [oOyY]*) INSTALL_FLARESOLVERR=1 ;; *) INSTALL_FLARESOLVERR=0 ;; esac
  else
    INSTALL_FLARESOLVERR=0
  fi
fi
echo "[1/8] Pillow + pyotp (favicon + 2FA) + openssl/certbot (HTTPS)…"
pct exec $CT -- bash -c "pip install pillow pyotp --break-system-packages >/dev/null 2>&1 || true"
pct exec $CT -- bash -c "command -v openssl >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y openssl >/dev/null 2>&1) || true"
pct exec $CT -- bash -c "command -v certbot >/dev/null 2>&1 || (apt-get install -y certbot >/dev/null 2>&1) || true"

# --- Option FlareSolverr (SANS docker : binaire x64 auto-contenu + service systemd, 127.0.0.1:8191) ---
case "$INSTALL_FLARESOLVERR" in
  1|yes|true|on|oui)
    echo "[opt] FlareSolverr (binaire x64, systemd, 127.0.0.1:8191)…"
    pct exec $CT -- bash -c '
      apt-get update >/dev/null 2>&1; apt-get install -y libseccomp2 ca-certificates curl tar >/dev/null 2>&1
      if ! curl -fsSL "https://github.com/FlareSolverr/FlareSolverr/releases/latest/download/flaresolverr_linux_x64.tar.gz" -o /tmp/flaresolverr.tgz; then echo "  ECHEC telechargement (verifie la connexion du conteneur)"; exit 0; fi
      mkdir -p /opt; tar -xzf /tmp/flaresolverr.tgz -C /opt 2>/dev/null; rm -f /tmp/flaresolverr.tgz
      BIN=$(find /opt -maxdepth 3 -type f -name flaresolverr 2>/dev/null | head -1)
      if [ -z "$BIN" ]; then echo "  ECHEC : binaire flaresolverr introuvable apres extraction"; exit 0; fi
      chmod +x "$BIN" 2>/dev/null
      cat > /etc/systemd/system/flaresolverr.service <<UNIT
[Unit]
Description=FlareSolverr (solveur Cloudflare)
After=network.target

[Service]
Type=simple
Environment=HOST=127.0.0.1
Environment=PORT=8191
Environment=LOG_LEVEL=info
ExecStart=$BIN
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
      systemctl daemon-reload
      systemctl enable --now flaresolverr >/dev/null 2>&1 || systemctl restart flaresolverr
      sleep 2
      curl -s http://127.0.0.1:8191/ >/dev/null 2>&1 && echo "  FlareSolverr OK (127.0.0.1:8191)" || echo "  FlareSolverr installe ; demarrage en cours (systemctl status flaresolverr)"
    '
    ;;
  *)
    echo "[opt] FlareSolverr non installe (INSTALL_FLARESOLVERR=1 pour l'installer ; solveur externe attendu sur 8191 sinon)."
    ;;
esac

echo "[2/8] Dossiers…"
pct exec $CT -- mkdir -p /opt/tracker-autovisit/data/logs /opt/tracker-autovisit/data/.sitebak /opt/tracker-autovisit/data/cookies /var/www/autovisit/icones /var/www/autovisit/.logos

echo "[3/8] Logos trackers…"
cat > /tmp/logos-manifest.json << 'MANEOF'
{"abnormal": "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", "bitporn": "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", "c411": "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", "crazyspirits": "iVBORw0KGgoAAAANSUhEUgAAAD4AAABACAYAAABC6cT1AAARRUlEQVR4nO1beXRV1bn/fXufc+6Y3MwkJAQMiAULoqAMgkUrrqedtLXY0oq+Cvq01Q6vfVRbrbXVtq6OYm11qXVYWhxQW6lDbSvDK2OAMkUMEMKFkJCQ+d5zh3P2/t4fNwlJSC6B3PjW6vJbKytr5eyzz++3v29/094BPpQP5UP5UDIg4TD7Dr77rjfdmOrqag8z0weBR4z0B0gI7H3w7oubH7rtdqspXJRurHpz5Uerfnr/tVxZaY40rhElzszGtm/d+tVjb/3lycSxuimjL158PN14k41Ex5b1S7Y8/PNvM7McSWwjRrxz5cqiTV/6zG87N294iFkEsyomP01lwk73zvivf7tWaUe44f0PbF5y/X0HDx5MuzWGIyNCvO7RRwt2PPWb38YPh282WAsrN7+2/Jov7ARzejCGEbFGl2xihps4UPU/R+/+77sP/iG9XzhTyTjxyuk3mwdefuph1dZ+LYjgCpmwiopfD553XlozBwBWCsGys9YmlNsplDYS4drbWrY+fwPJzFt9RomTlLAr6u5xYvYVLAyAAcVOMjSufDsR6aHM4S/Jj5J2HBcEYs5p27j6wW2333RFJnECGSa+5bYvXaGO1N4khczVzCAwzKLSvdmfvG7HUOfwz7y8xhw1Ji4IYCKYvmD28TV/+/2GO+8YlUmsGSNeddddJZ27dn3XNKySbtVqreHNCf21eOrUhqHOUzhpUouZnbVdd/kDlwSMYOgstWfn9+uY/ZnCmxniUqIjvOcqVrjEoe4pGTAs+EeXH2I9JCtPARIiYXh8lazcnnkIQLK5+Yb9V14yNyN4kSHiu3//YJ4btW80wJLR5bk1wwj44Rk3Ye/pzMXMED7L6b1YLASY4ZfB4I3HXnwxmAnMGSGe2HdwvmptmaJwItskZpBp1SE/WH268xm+UCcZJzw5M0MYpnQaGz5Zv/rtjGg9I8Sd8MFFpNwQUy/iYJDAe60Nq1tOG1Qg2MHCRO+4zwAkc1bs2KHbMoF52MQP/vnljyTbO8o1etcWBLCGgGN6j5acdtHBRAriZGiaCIm2jorqpx8/fziYgQwQ79i4cZaKxS9g6jdVt7LOPfkdMi0ws+cYc5CZ/cxsQJwwbZIY0BsyCDrpTO5cv3rBcHEbw3mZmeXmGxaexW5Skhg4u2oqTJHg1tacnQ/8YHp0354yGQxMrLzx8+WuYm8NsRbMkfWfW7AbUtTlXvqZ91R9bQG0ZqCPGaXMHUzxluaLmTmLiDrPFPuwiEdqagrcWPRSgwTcPk8YIAKRkaxonli+YeEnblj3xavOZcjZbEcLRGurZQqBVJIDaAAJpTQZZrzpT8/Xs6sMMBNogF1CBLetZe6Oe2+/EMA/BsLFzL5d93z3P7xt9hsTly9PZJx43avPnO22Nk0c6Jk2TNhNrR878OufbiNhhKhHfwTFgKt6WTMziISAUn5EOsYDhAFJo8vfOY7HrW/KH/g5+9fNGf+kZ+J5DVOeeuU1LF8+4Dyn3OPHdu8ODlYeJuuOZGvHsXpid38hWEKYIYCgiaBB0MDJo4nASGneBUGlwcNEIAgDwjOZmfso7vjx49lrr5z9ayNJ14lAaD9JOWg5eEqNH7h32ZVKicMANvZ5IASUQ+daltefjMcHfX/oOdvQhAEYzJ5kR8fs9nA4C0ArADCzueHq+fehM7I0KQ2gLnwIevAyOL3GpYFYZeXM+LZNFScBUEo6ycRkA/Aw+pklM6A1TlV/n1K0BmsNVqrfnxV0LJLT8e4bqdydCJuWfuE/461tt7HhhXQTaNu2tnUA2+qRtMRbmpyQMWHMVP8FU6cN0AT0udFotuskT96PnDJoZg2dTIJdZ8hcAYBdF+wkAVYwggF4ior7PNfM4GTCb+/bb4EIu++7a27iSN1dBoSpwVBCKgR87iDTAziFqdd89VMlWtFU144Xrp4//x4APTbd3r7LhOP4WHFf4swInX8RQlPOQ7zpGOz9exE/egRuxE6NGyAx6UNaKUivhaxJH0XO+TMQHD8RDEL1L38Ct+U4IA1oZljSKLbtlmzW2th0/Wdv0Z0dJZAGhFbQocL60NmT2rB31ZkRj+z7V5Y2s4pULCbzLl9wGdaseaP7WWxPvQmV9DJrgGQPadYaOTPnYtx1X4KK2XDbW9HxfhUa/vomWjeuhXYdkDFAE5UZ7DrwnzUBpZ9diII5H4OnaBSElHBjNqyiYiQbGyCkCQ0CK10Ymn7J49W//HG7HT40SwhpaQCSGTIQPOqfcWkn/ngmxIngmzZvovN+FbkQedGtW+/g+vo1VFISBYDkoWZDaeUdaBeRYUAYEiIrC2ZWFnxl5cg5bwYOv/Qsjr78PNyEg/7tJFYKwQnnoOLWb6Bgdt86hF0Fsjwpn0EACHAcF27dkRmx6j2Ak4Q2rdS3AUAaHb4LLhgwfnfL4HZHBBnMLgEJMJFwIp0f3/aD73yt+1BAqIiAUvIkB6Y13LZ+dQkzjOxsjF28FMWf/jyIqMsPdJN2YebmYuwNN6Ng9ly4kQiS7e09zpE1gxNxEInumA92kjj2zzVoqakBelsQMwRYF3sK0waUtMThqMJecVdGavYtbVv18mJICY/fp6i/1yQCa4XYgaoTTxho3rIBNU88DLezA2O+sBjZH50K7Tg9QEECeTPnoHDefKh4HIdeeAY1TzwCp7MDAKCi7YjtrwJ1aRVE0EqlFli5fX0MERTIstvCaTuUgxJn15WuHek5+SAi4kRyfPv2Lcu23rL4m7GEyhsoWhEJ2OEw7MPhFOiYjfrXVqDuhWcR2VcN36hiFFxyGYRppPY1MwyvB0VXfALCshCt2YeG11eidfP6HuJte3bBbW8F5KlrKiYClJvdvHVr2rb0oDOtXr2adDKR1R2jGamykB2nom3ntl/W/uHRrW7EnuH2K07INGHX1uDYG68BABLHG2EfOQLtaqguLefOmAUrrxCsFcAMMycf2RPOAQDY4Rokj4ZBQkJaHri2jUPPPAERyBlSXqBJwG1rLW9e81pOunGDOrf5ADY4SW+K8glTYiIQSeh43MPAyTGcCDAt1K16Dd4x4+AdUw4VT8BTOAqewpQB+UrLIE1KJTlCQgSzIL0+AIBrx8DCgLe0HInWZoR/9xDsmv0gY2hlhSYBo/N4gd1wJOuMiK8G4DGtBPpnZb0WYDAhIeG0NGHfr36CrElTkGxrRWjyufCXjQEAmP4ApHDBWoOEhLCsngWUHgtCEhw7gr0P3odI1W6QHPoZIgHQJOEdN96Do+8POm5wjc+fz5uffjTi9tP4kAEYFlTMRtuW9SDDRKK9A0deexGB0aWw8gqgkgoQApTaPki2NKGlch/adv0LsPzo3LkNUCoV89Mscn9J1ewa7MbSvpTOfrTwBxqHc1hN0gBk6hPR6r2I7KyEdmIQZgDCH4QwLbBSYCeJ9h3bUXXfMrDSkIFskJDAIM2NtN8Eg03Tidt2NN24QZ0bCcmW13xfaY7Taaz4oPMZBkRWLoy8Uohgdp/UlV0XMC2Y+SWQ/mF0j4kAJwnOG71uwu0/rk03dPD4wBptuzdWKZWQaYqc0xPmPolLz5+dJBiA8HrB6swLWckamoQrLeu5iiVLGtONTRsYfeMnNxihnBrS6VoDwxMiQDsJgASkP9AVshgnTlKGMAcIUmtopdjIDq2Y++SKlUSUVl1piV/4yHOHhOl9jsEYrrkz84BxmJl6ylZhWQBrEAkYwayu0jQNfmZ4lAvhJsAeq84qG/PwuJvu+AHl5bWfCk9a4kSkAhdevEIlIgeM09F6N8muH06moiKZ1slECGCVajgIK+XsZFY2yq9fgrzZc6HjNjiZPGnhmDWMQBByXMVDIr9gSfbk6QvnrFh159hrr60ZCsRTq1EIbP/W0mva1r77qOHxFbrCSIFIQ5qgUt0TBogdhC6ah4LLrkTjqpVo37UDTCJVZHURNX1ejPvGnWh6889o3bwe0u9H7uxLMPpT1yBaexCNf3sT9p5NgPCADV8qDCYT8JSNfXf2i6s+RUJGB/Id6eTU6ZDWOP/nj7269etfoc4Nqx8gM3COAEEbJlJdFqCnjOk6Ex+/7Iew8gq6SPmgOjtwfN1qRGoOQFhehC6cjXhdGNHqKshAdtdGV5Aeqyd/b3rnL3CajmLid3+E7ImTAAHEGxux/xcPwI3ZMAVgZfkPALBPl/TQiKcYYfpvnnjlvZ/9bE/T6j99Ga6+Tne0nS1IwhICrpTQJLq6pYSjLz0PT14+gmMmIHfePOz79U9h1x6ADIYghIC3uBjli25E7WO/QMv6tZDecqikC2EYqfwdIlV6Kg2nsxN771sGEQgBYKhkAoIZCGQ3W6Vj3yAhzijmnFZffdKyZe+TZd29cfE1zzo7GoqDk6aXUiBQZB8OL0J720W66xgpsncPOuwoOotKEZw2BcGKCYgfrQMZBlgpHF35PBL1RzDhm99HXfnzaPzb29DRKEikNA8CtJuElRUAuy50zEa8oR4kJMjyQAoCBfwHcidO3HKmDc3TPlDgZBIzH3+hGkA1KsMAEd77yV07j73zzjMymShTIAiPF8Lrg5uIoWPHduTPX4COPbvgRCKpRMb04PjadxGrrUHFHd+Gb+wESK8PQnBPxSYMD7xl4xGrOwylNITHBxBBAHCJ4ln5Ra+XfXlpE66/+YyID+/QkDWgFQLzpmz05Bf+lblXo5kZWrlo2bgOhs+PnOkzU+M51ZyU/iDsI2G8f//3QEIgb/qMVDgDA0pBBgMITp2G6N6d4FisJ18nZgi/zw6MKV1HRGnbSyNHvEvK5yyM5Uy54Hfk9VZRr5sMwpCwD4fRUrkJeXMvhXd0KXpf8RC+ANxoHIcefwSHVzyLREs7hOkFKwXf6DJY2TmIHNjXN4oQYAWz3y78+Ge2DQdzxi7/fOR79273ji55VLNye7ROAiCB42vegbI7UXrNQhg+34k+OzPIMKHiMdSvehWtO3dCeP2AG0fh/MsRr6+DXXuwp6dGzNDCSPqnXfjHwrlzz/ikFMggcSJSFz31yiNmbt4L5CZ7Mj2SEm5nJ+pe/iM8xaUYc/0SmKEc6GgkVZwgVcAQCahYFDoWQe6FsxCaOg3N/1wDNxo9MZdW2pOf9/r599z/+nDxZvaCH5FbevX1PyK/f4tOJrlnXxomYofDqH3qMXgKilBx6zeRO3MWZDAInUhARTqgXQdmTi5GLbgSpV/8CprWrUXb9i2pspYIAgxYnvrg5MnLT+cW1aBYhz3DAFL5nVsv7azc/LR03DE9PTkG2HVg5eejaMFVyLloDjgWQ6KhDjpmQwaz4SkphbAsNP79bTT9/S2oZCJVlxPBStpQeTnL/7Fq/Td+OMRbkulkZC7FE2H9LTcsilftXG4w57m9Chx2HZBpwZuTA++YsciaPgvSH4Db3obo7m2wDx1EoqU1FQG6Fk2wBnmt/y389NU3Tb79rtO+RTUgxExMMpAwM228adGtseq9PxPEQd37jgxzzwkoCdFzQsI69ZvkifRCEMGNReOesgkL572yath7u1uGdSMinRARM/NjGxd/zhc/VHO30Dqku7suRH27pl2xvf/9ISIC2x3wjhr1q7mvvpEx0sAIarxbmFluuXnR1yL7q++VjsrRQgypoUMAtOskvMWjXpqz8p1biSiSSVwj/z8pROqiJ1/6TWjqtP+ioK8SWmvJ6Tu3EgBrDU9x6SvBj11+Z6ZJI+3XR0BqfvXAzIZNG25xmhquUrHYKCFN6H6dHZG6SRE1S0rXeM45/44Z999/YCSwfKDEASC8/q28lpf/tCB+9NDieEvbRygarWCd6rELMLTlaQyOH78i97LLHxi/aOmxkcLxgRMHAAiB+jefCrRWN85JHqyelWhuLWatLcPvaw+MO3tN9uIlfy8tLU37jzv/FsLMxMzW/zeOD+XfWf4PCkz45qqMQ74AAAAASUVORK5CYII=", "empornium": "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", "g3mini": "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", "generationfree": "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", "happyfappy": "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", "hdforever": "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", "hdonly": "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", "kufirc": "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", "lacale": "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", "mam": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAC4ElEQVR4nO2XS0gUcRzHP7M7a5vuWvZakLAQH4mkPYiKiB4YdqpDkYF1KIgoSE8WRpdAlC5CRUTlobqUlYc6iNJLiTy0kVGKEmVIZrnr+sh0d+f17zBlLetYPmoP+YW5/P7/md9n/r/XjORr9AhiKFssnc8A/H8A3X49dgCXbo/wvFWNHcCd+yGS3NHu/hlAnAM6P8UwBMuWylTXBWMHcPygi5a3Gk0vlYkDDA0L/P3GlAA8820UFSZQfOYLw8Gf3V8abxYoquBYxRdqn4RRVMHKLAflRW5WZTki9rW/13j3Qedzr05PwEDTITtNJidDJj1FHt0XVgTr9wXYvCaOypLE3wOcOj/E5TsjEbbkhXYeVs3D329w4eYIDd4wPQHr0/nhbLHHDpjVcLRskJrKJDaujrMOQWe3zpWakSh7t1+n5kGI5naV6rrguM4BGrwKmw4EaHxuxn5XnpPsNJmLt8xnWwJ4W1SExdm44iUcsjSu4181NCw4WjZIYMBAkuDEQRePnoXp7NatAbp80TULkLFEZvc2J0+blTHXreTvNyg9OwTA8nQZw4Cr94LWAO746DdckengXGkiHV1mGCaq+qYwugHuBNPt3UchZKvN+RtmkbzQTBxJgqxUmSXJdl60qewtGSAUnviHVDAkaOvQUFTz3rAixgZ49lqluT1ycLxoU3n1RuWxV7HMjT9RR5dGg9cMnyteigZofatRUNIf0SymU+0dGjdqzZa8Y4szsg/4+gzyD/eRlmJn69pZVFR9ndRRjyfZDpoODhmeXFvwMwlDYcH+0gE++nSKChM4sieenAzLFJm0tO/FVVmSSOpiO3y4v0hUnZ4j1uXECUAAInOpLAq2zxaSxKhtOq+Th1zC1+gRvkaPkPbkO8Wt+omX1GS0IMlGRbGbnVucozZp3hyb6Buc2qT7E+3Kc1Je7CYpMbL1SNfL54qe3r8HINkgN0MmN9Mx9vrMr9kMQKwBvgFnYzyycJTAhwAAAABJRU5ErkJggg==", "milkie": "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAGWElEQVR4nO2a3W4byRGFv9PNmSH14w0Yy4ITIUGuFggMBEiu93XyGoJfI6+T61wEEBbYYIFgF8waspzByqIkzk935WKGQ9KkTMuOl9LuHGCGgqZOT9Xpn2lUNfTo0aNHjx49evT4ZULzP+z01JHnCSfDlOBT7NAtzKYw/Yk9O+huAFyV/7VDDkvG44I8r/TyZVw2t9NTx3ickOfZFVfpYfprdfQpoKuIDyWTWcl43PEHXQt5njAeHTF1v8X0nLQc4j2EAAGC/9wRr8KX7a31YRSTooq350meT8jzc6BYIeR5AhxX9e3JyCXHUGaUo/bhLdxohvwrxqP/kOcXc/5CgJOTtLq8/I2T/dmc/Wkg+wIZWIQopBXBPz+iAxdBDmQ43FvnOavqW5Lx+EfeFWA8zqr69iTx/i/ReEHUE+Y+R1HLLhX1zxgGlpycXLImwM1NIs+RIn/E+ArjaLl9+6zRbkHz8jfRDJkmFMU3azZFkcjpOJq9AH0F9hRT14CMC0Elz/fc3Hw7py0EKEsvzz7iCPgdWXaA9+A8+BpvrQTqbps93abUh/IlGAyaywesKvcF38i5fYpyfUJmmVddHGAcG/YHhsMho2xZoH2wZzL2SdOOvxDg4ABup679X8rAN/PPrLmwZjg6tcNy3fdmurTTxmh5bTDifnzUvH/gG1sjRRqAHGm6rmBZCu8SU9z3fjBkOIThsG1b+Ol0L9ZxL0Dqy7LjLwSYTsETMatwKqhDSjSo6+YC8Ab49ndDBNEgBghxSbi5ALoffxkxglQgqzAiZfl/m5ELAdLUrJoFeVeCzaiqQ7yHqmq+BGYQHLiwCGjF/zbgGJtrZTi3t/vwpYWAIQDMMJWYBdJ0XYA0NeqiElyHup752WyIWrNZQQjhRnDjUbnMH6w04pxhGCIuhn3jaIgxEmMFFEKlyVackEmGpUAGJHLOLXey3ZPvvXfNu7sp2Kgqbe79ogjmbCqnc6F/M5s97Z7NZgAXoNcmXVOWYbMA70IOnM17rMLsXNIE41zvfoYgk3RsZidIx5IyfLvWhIDdk4+U4VzjA4GtyLLK6ttzJ3cWDUBPuhGAMHGJ8bUFLjjYq7YLILULVrsZqutC0iSa/UPiDNPbVXt7YsYLJ2Fmv8L7jGSp+RDux3cuaxbADdNlE/K8SMbjSVXfIqeJc5Zh7WbWGQPTDGevvAs/MJmU2wWAbhPSjQBxLtxZbfXfs+DfLJsWPj4daACyE9CXmn/GAOpwb37TAY67P5nvYDyuGI/Pkzz/8Yqrfx3yRKTtyClT2CtWtsIfKEB7a3ogYHZtxuvs9eg7/e3lzbKp/fX0un5WfinsGhQWAfDx/A/p+bmrzd6+YH1qvRduq0XnhBkQwWqeU67ZPacEq1sbW3G+Wczux1959+fDdgG6xVoCHNElTKfZmt10mhFd0rQpsbzIm92fv/Luz4ftAnQwgbwUU5JkuPY4SYZSTJtV0xYBdEF8BP8nwPvXgDWYkIQ2CCc5hN7v/Kfy39PyJ+cDHjs+OR/w2PHJ+YDHjk/OBzx2VJXXKN0He2bY78myPYZp88wMimKEOJLZPmW5IR/w2JGmbaKBAWZtPqMNb1ADpDTxOg4WydZ7fAYfOMqyyaTIKqSCOixyGc1WvMCsAiLTRYr75zQCDLOAqQRmVNU+vu3fqgJshlNpIQbS4R35gMcOybot9/ImrPmNGIZzK9vLn88U+Ej0AuzagV2jF2DXDuwavQC7dmDX6AXYtQO7Ri/Arh3YNVYFiFFNXg7X5eW7/Lzm2d67c3Zmc8ID5NPkHGNc4S8EKEvJOU+0FDQkSVi5YIgsRfIs1deX+UgeWQo8QL6GREvl3Ap//YCElGDW1OUGSwkFswyU3HlAYZ6QMB4uX2rqDhsTIk2SIAI1UFIHCHVz1QE0r9zY5gMK84QEVqMHyIeyje2OhEiaBovVtaJdIL6nKI660lRRIPQG7LXFeE2SrNerkyRYjNfyei30HUXx9CHxgQuMC3O6Jk02nA/Y26vs8vLCxNcmEtAXy/V14K2TzoLiOdmwq6522FKf3zV/+/mAyaRMxqMfiE6YXuFsuFxfj8QiBDtPBqMJeb5egd1Sn981f/v5gPG4Is8vOBleEvy3WOqW6+u37soOXXtUFdZ7YEt9ftf8u84H9OjRo0ePHj169Pil4n/d4ME3QzoA3QAAAABJRU5ErkJggg==", "nexum": "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", "orpheus": "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", "redacted": "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", "seedpool": "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", "speedapp": "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAJCAYAAACCPip6AAAEYklEQVR4nMWVW2wUZRTHf9/M7Ox2t5ft9kKhbaq1AlKIhYAtNSUKIirWaCIPSmJICIk8SELAxChEaqhReJKY1KgoxQexhChSRB6gBLGKXLIWbAiFXoQWSu9l2+525+LD2brBBzFi4kkmM/nOd87/f66jUrye5lCaPU9pYHrAduSx4tA3LN8+LxTk8r+JAsbGYXwScjLBdUEpGBqFgRHISofMDDn/p/5icazeIU+9KsrDPbYL0jNh33eQF4LHKuHqVahaDwEfNGyHR+aB7oJpgOOCZYPjiLcUUwg5LkRjd4J5DNAUuMjbdiBuiZ1pJO/pGsTi4tNjyIMQxXbh+k3YuAv2vi14mML31R1waAdULQKfEoy/8jB0KS7ApCXcR8dg2QblGroGBTngDck7Owg502BsWC6uXgFPPgGMQVsXnPoVivKgbBaEMsC1Yc9hGLoNwVRY8wxoHiRiBc1h6OmXBMXiUJgrZKMROHpakqEpIbSiHKYXwMVWONUiFX18Acx+CC53QUYqhIJg+iSY2UUwsxCWl4PXhD2NMDgKGQFYsxJ0D6DB5XZo/FFslpTBwvkwfBtGItoNw2NA3dfSWqufBysCO+sgxStViVtw/XdJzgMFEInCsTNwcxBefg7Oh2F/E2QFYVYBKB1wEgnQofR+KJ4Bygvb6uDhEqgql7GqKAVXwfgEvPIOLFsoJN+og8PN8v3Tx+LvxgB8sBFsCw43wcolkJspgXozIByGhuPC48F8UBpgSwLqj0BHj8RTOU+659tTcGvI+NKwHZhbLDM0NgiBAFTMhZGIzH3/CLz/Gfh8UP0oVJXB/FIgDljwSyt8sRWyChKA42DboJvQ1gkX20HTJCfd/bBtLTAJJ87BcASUAZ3XoWwmFN4H1zrh7CUpQPkcWFQKROHpCvD4oe+WdBMOFE2DddXC4+ffYM9bkFuU4DYhwffcgMIcqN2c4OdAbxfsPqSikLJXFefjtu0DLRt2fggl+fDCi9B2Hr46Bls2Sft3dghw0fTEFgFiUVi6AXyJHQCQE4T6rWCmw+1+6B0UnetKC+fkCYnubohOJue0MFds3HHo7hObYBoEgomOUjKWtiPt7vUnzoF4DJa+JnM+tYu2r4PKSmg4CLX1ys7LYnJqLDt71PDla56tENttjEcVDcddAgFZQL2DcKgR2rugtRO+PyoZNnQBa+2Q1s3MhyMnoPkCd0hFKTSFwbWk8rr25zrAdcG6lFxMSiV1V7sFX6kklpP4I6HBrQGorYfIBPh9ULMWnloMoRlw9KTsjCkJpsGcYrAmYO8RRcsV7+qWK+bZZOn8I3CzD0AZhne9ZcUWJJV/J8r0+1h1oNb1NYXh04NaeHDUOXd3u/9alMdnsurAu27KDxfgk2+0loER50xCN+el5e7iNdXw3udq4mSL8dGWLW9urqmpce4dVinSAp7T2UG9HcxNMCvtnp3+Sx6pAb05O6h3gO91KEmf0vn9/menhfQhwzAaIXXJ3Xz9AXtplDriNFVhAAAAAElFTkSuQmCC", "teamflix": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAADHUlEQVR4nMWXTWhUVxTHf/e+F2Ni/UJUpM6YSMCFQqEuJEsj+AGF6kZoC6Wl1K5qUtCN1pYEFCUQUPAjMS6iRRSzED8ogtW6EBQqKAFTdTqZ997MGE3SVqNJZiZzj4tk8jGOMaPzxv/uHM6598c9l3PuhQ8sle0IBoPLReytI5Y+53mhf4oG8PGyZWu16EtAOYCIpFDqsKVMveM4//sBoCcZRjcB5Ruq57OlZgG2pUsU1BlRDwOBih8Aq9AAk04gEKxIgbIfnP+UGSWKzq5BGpo9bnX0jwQI94w2P8Uc57pPAJUC0HV59aSgP24/o6HFw+1OjHCIXNLK1LquG35fAP32EFi3Zi5Xm1fyy7alfFSmUUp9ZkR3Lg1UHqyqqprjOwBAia349vPFXG1eyRcbF2JpPUMptg8l0n8HgxXb8llroqZVglzqeDRAfYvLnfsvARDkjkbXum74ZlEAAETg95v/se9ElNjTZMbVbmvZGYlEHN8BMhpMGFran3CsvZuhpAEYQGgUSR2IRqODU+W+U92yVVaqqf1qCdeOr2JLzQKUohzFr0rbDwOBiq/J0XEzKsgJZOt2Rz8NLVHuhwcyrhtpZerijnO3KAAAaSOcvdJL06k4fc+GAdIIR0pLrZ2hUCiRiStICXLJ0oovNy3k2vFVfLd5EbalLBQ/JhLDeyfG+QaQ0ZxZFj9/H+DM/hUjDqW+KSrA6xKZaNl+b/f8ZZpDp+O0XewZ3Z+2ogC86RLOnl2+y3eAWx39NDR7dHaN9aAbRkttLBK5lx1bUIDHvSka22Kcv943WmmJIuz2vMgpQHLlFAQg04qPnusmkRpvxVrLfsd1hqbKfS+AsWHUGiXWMz6M0rba8TgcdqezxjsD5BjHf2l0nZfnOM4b4ElfkoOnuzl7pRcjgkBcI/WeG2kFTL7rTRsgNSz8dvkpTSfjvBgyiEgS1LGZpdaeUCj0PN+N8wLw81GaDZAGrGRKpn6Wu349ywOVd1F8sr56HrPKLC78+S9pI4D0IOzxvEjrKGTBNAkgGFxeI8hFivg1e+PnVCkjIna735/TD65XWsWVJp5DyAgAAAAASUVORK5CYII=", "theoldschool": "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", "tigersdl": "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAFD0lEQVR4nO2b3W4bRRiGH/8nDUkRTXFt0qSiQAsltCdw2KvhhrgI7qIHSAghQCCgVREHSGlpCeHnJInTxo69HLzfaNem692tZ9YR7CtZk+zOzrwz883fO99AOrrAx8A94BlwBHwK3E3EuQN8AjwFopJ/Ty3vOwk+d43jkXG+Z2XophWyPqcCHKLE3y3gQuL/NaCdMx3fqFvea4lnFxBHh4gMNDPeT4CxhXXLoAvs2LMesA407P8RMLRfZuYFUUMFbqNCNizvHnDV+HWNY32GeyrmVUBkCZxZ2AY2gfdQQSfAu8AVIzQC/gR+s/C0cBHnowNcBvoWtizvXStH3bhtosoZJrinNkaWBYwTCa2i2v4QeMMS7QLbRm6I+uV3wEPUD31iHRUwAi5antuoId5EFtI3jg3jPLQypCKPBYwsbKACbwC3LE4LWDEyJ8A+8APwOfB3sfJl4pJx6QFvob6/hVp8ZHHaqKEaM9xf2gKS/aiGCtpJiTsGjoEDYA9ViE8cAe9YHmNk8qv2exFyjQFFZ4GseK7Whzm/KYIhOVr0BZzmwvf0VUfdIs1KFkHH0vbKOU9itZxp1VDfa6NxwTdWLO1GQU5zkTUG1C3DOjKnIfCceNBxg6BbDDUT8X3DcXFTXh4+mVzmVYBrUbfoGKP5fQ/43eJcAa5ZmIybt4WKIAifLAtwiTQtw33ga+BHe/8B8QKlmcgwFLzzeRkLuA98lohzk3idsAwLWIhPkTHgDBigWn9k7/ft2YSw/T8Yn6KzwIjpBc4J8QA0GzcUvPJZxjb2XGFRPaDw/tsDvPIpqgesoc3Ijr3v2bPc++8F4Z1Pkd1gG00vu8Q1u2vP3P676Fq9CILwyaMHjJjWAz5C+3DQgiO5/3YZhoJ3PkX1gMtImLhpcdzSM/f+ewEE4eNTD5gQS1AhxgHH5awAn6XoAW6D4hvPiSWuc6sHOGXYtyCKpenEWG8IoQe00AjtG0k5/FzoARHT++8GmoNfR/PyXzlJ5sWmpb1GfA6R5FOjZD0gQqPwNpKjW0g1ft++PyxUvGxsWNpdy2uIziAeG68aJesBEXDDwkuo5rfsuy3CHIx0Le0OavlHwJfAz6iQpeoBETqA3EEts24EX0XydaijMSeOHiIL+B74yt6XrgdcRXq90+nnzcu+Mba8XTeAJegBx8jUQ26A0jCxvI8Tzyo9oCgW1QNeQSa/LP+AjnFwKFUPiND0N+sfcEpY/wA3CDr/gD6aimuUrAe4abBv70boYPSJhSGnwa7l2UcuMquoAkrVA5ILoQ4q8BPgW+AB4RZCoKm2gyyxBrxNvBAqTQ+YXQoPUMs/QP4BIZbCIAu4gfp+H3iNfy+Fl+YfMAD+QOsE3/4BA1TwAfG6Y4X0g9jKPyBPvMo/IEecyj+Ayj+g8g+o/AOo/AMq/wCo/AP+e6j8AzLeV/4BVP4BlX9A5R9A5R+QC5V/AJV/wP/DP+AZseSVvDTVQEJlF21JQ1ya6loe7hzilGk9wF2aCqYHHAC/oANJd23uGlJq22gKum3fHBUqXjbW0bW5nuXlZPg94+WuzV230Jse0GZ6//0NuhrnLk7W0XS0iu4T1tC8HPLiZBtZ4mPkH/CT8bhNfLu1SSyhpSKPBbht5Rhp/Q+BL4invevIBDeM4EV7Fvrq7CFSgu4j/wAnyN4iXic47t70gBNkbm7/vc3y/QP2gV/t2YFxLE0PGKABcVn+AUPj4FBYD/gHdAl/i7V4o0YAAAAASUVORK5CYII=", "torr9": "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAADnElEQVR4nO2bu0oDQRSG/9lsEkQL0ygGxMJKJD5AwEtjY6NgnkA7H8BesDSkEyvF0ktlowgWAS/gSwQkYGNnYUx0x2pks5nZ3bPO7iRxPxDZnZmzZ/6dM+dkogwAxz/GMu2AaVIBTDtgmlQA0w6YJhXAtAOmSQUw7YBpUgFMO2AamzqgUqlgZWUFjuOAcw7OORhjAIDHx0ecnZ0BALLZLHZ3dzExMdE1njEGxtjvWDfeaxlirMzm/f09zs/PqVMCp/wcHh5yFaenp7/9RkZGeLPZVPaNg5OTE9JcAHByCLTbbWVbq9Xquv74+KCa/xN+vqkgC8BDLFOBCI1+Zqg2QcrLEZAFGIS3SkFrCLjFETtzv0NOg36T8orjJ9bt7S1eXl5C2xKUy2XMz88HeBkesgBhCYrHWq2Gm5sbst1qtapVgFizgB/5fD7SuEwmo2yL4pt0Bdi2DcuyugyKCsyy9CQO27aRzWZJYzjnsG31onXbFKEq5sA5x9fXV+8YmaFqtYrV1VWpopOTkySnVdRqNezt7QX2c+85juOgWCwq+25ubqJcLneNE3Oo1+vY2dnpGSMVYGZmBnNzc4HO+RGUBaanp/9kX0ahUEChUJC2NRoN6X3pepYtlUFHVSYPVSUYBakAg1DAUFHNKV0BspvU9CQjKGUlTS6Xk96Xeri/v4/j4+OeNOg4Dra3t7G+vi415l5mn5+f2NrawtjYGAB0nRyJa/fvMGEnnr+xsSFtv76+xtHRUc+JE2MMr6+v0jFSAZ6fn5VOLC0tKdu8Ofvu7k7ZNyrLy8vKtkajgaurK5I98h7gFx66ymQ//CrRKCGnNUjdAliWhYWFBeRyOTiO07PExbXskFMVLt/f35iamtLpMl2AsG85n8/j8vISs7OzPROKShwrLJFtWlddEWQnynNirQOS2BPc9J0ASZPIoWjSb5VCIgJQHEi6EoxyWKP1UNSbuprNJjKZDPnNyPp7DzhkvL29kZ4DxJgFWq0W1tbWpHmegqxUVtmLco6hVQDv6nh/f9dpPha07gGdTkenuUTQugIWFxdxcHAg3SeCvlBxh4q3r6o0Fn1F+9PTEy4uLkg+axWgVCqhVCrpNElifHycLMBQfTnad38fMAgMVSkchaESIJEPQ1G/1EyCKIe55Czw8PCA0dHR2PaCsIek3lTIGEO9Xic/jyH9n6H/TSqAaQdMkwpg2gHTpAKYdsA0qQCmHTBNKoBpB0zzA6ui8VImwqpiAAAAAElFTkSuQmCC", "tr4ker": "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAEBklEQVR4nOXbW4ydUxQH8N+Zi7bjWjRFNZR4oISINPEgHiQiRCIIIjwhcUlECIlEvCBpRDw0BBFpxCXiyS0hEpd68ETELUXQMi0e2upUR6fT6RkPy6RjfHq+c7r3fPvoP/k/nOSc/X3/vddea+219uEgR6vL7w/iaNyNqzCMnfgG02lfrSsM4cy/3wd+xUN4O/WDjsDtmBSCS+Y7dQQNdCF+IVaImR3u8N0SMJZ6wLPwoeZXtg5/xsqU4o/DI2gXIK4TJ3EDRlKJH8Y12FGAuDpcg+NTiR/CSfZ5+dL5FZakEk+EvFcLEFaHf+BcCR30UtyCPQWI68Q2HsAC3ec2lViIi/BbAeLq8E0sTyF8Bqfi3QKE1eEmYfrJMIjH9UfI24NLsSiV+ENxtXAoTYurw6dwlIT7fiW+K0BYHX4u4v1gCvEtnCxmtGlhdTiGi1MIn8Ei3IqpAsR1Yhv3CYtNhkvEGbppcXX4mshOk2EF1hUgrA4n/bPwccAYwM24INWAmTGOrSL8JcOY5le2LvfiHIk8P+H9N2FZqgHnAV/jXqwXFtEL2pjAeAvX41ocKU1CsQhniKQqF3aII3qvEzCNjXg41QvNxgCu0B9RZU03RdG6aOM9PJ1h7NSYyDn4dZpf4f3xWyzPYQFwDM7ONHYKbBfNndEcgw+IYsovml/lKk6JtH8ol/hj8VEBQv+Lj0pcOJ2NxVgtEpamhVZxHU6UafUXi0PVzgKEVnFU5CdZ2nqDWCXq8k0LreJO0c3OhmV4tgChVWzjfglbZXNxCO7C7gLEVnGtxCXz2ViI8/FFAUKr+KWwzmSnx9kYFDP7fAFCq7gFp8vk8eEE3INdBYidywnRIs8mfkR41e8LEFvF1SIhy4ZV+LgAoVV8XdQ5s2BAXJR6QZmts41iaybpFFXhMNyG3wsQO5djOE+E5WxYig0FiJ3LPbhDD/cDuvWS0zLF1APEM+Imy+5uf9jtXhnBlbhJ+IK6+FOY6BZsE5Z0OQ7v8vlVeF/cZPmxlx93OwEtUfVdoPcYO2O2p+ElnNLjOLAZF+InUejoG7RElrZW7/t+XFyOSNoknU8sEabbi/i9eFCCTC9XUbQOpoRv6AUv4gkJzL7JCegVn4iOzvYUg/XbBGwVidhmkYkeMLKdljJgEneK5uiuVIP2ywRM40m8nHrgftkCb4gj7v8Ki3GZziFvvfizRpYUvEkLGNc5Fd4h0u4fROxPjiZ9wAL7X9UpUW3+TEKnNxdNWkCnyX8Or8jcwy81CnwgmpjZVn4GJUaBUXETdMN8PKzJCZj272xuAjfa12PMjqYPQ9tnfW6L62+f6qGy048YEhXct4TZPyb+pDWvi5KtfFwTQ6J31xIxf1uzr3MQ4i+KnvVKBc/xFAAAAABJRU5ErkJggg==", "yggreborn": "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"}
MANEOF
pct push $CT /tmp/logos-manifest.json /tmp/logos-manifest.json; rm /tmp/logos-manifest.json
pct exec $CT -- python3 -c 'import json,base64,os
man=json.load(open("/tmp/logos-manifest.json"))
os.makedirs("/var/www/autovisit/.logos",exist_ok=True)
n=0
for k,b in man.items():
    open("/var/www/autovisit/.logos/%s.png"%k,"wb").write(base64.b64decode(b)); n+=1
print("  logos installes:",n)
'

# Favicons des trackers absents du depot (le conteneur a Internet, contrairement au build)
cat > /tmp/favicon-targets.json << 'FAVEOF'
[{"id": "brokenstones", "d": "brokenstones.is"}, {"id": "exoticaz", "d": "exoticaz.to"}, {"id": "iptorrents", "d": "www.iptorrents.com"}, {"id": "nostradamus", "d": "nostradamus.foo"}, {"id": "phoenixproject", "d": "phoenixproject.app"}, {"id": "sextorrent", "d": "sextorrent.myds.me"}, {"id": "torrentleech", "d": "www.torrentleech.org"}, {"id": "karagarga", "d": "karagarga.in"}, {"id": "privatehd", "d": "privatehd.to"}]
FAVEOF
pct push $CT /tmp/favicon-targets.json /tmp/favicon-targets.json >/dev/null; rm /tmp/favicon-targets.json
cat > /tmp/fetch_favicons.py << 'FAVPY'
#!/usr/bin/env python3
# MALINOIS : recupere le favicon des trackers absents du depot (le conteneur a Internet).
# Sauvegarde en /var/www/autovisit/.logos/<id>.png (64px). Best-effort, jamais bloquant.
import sys, io, os, re, json
try:
    import requests
except Exception:
    print("  requests indisponible, favicons ignores"); sys.exit(0)
try:
    from PIL import Image
except Exception:
    print("  PIL indisponible, favicons ignores"); sys.exit(0)

OUT = "/var/www/autovisit/.logos"
os.makedirs(OUT, exist_ok=True)
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
targets = json.load(open(sys.argv[1]))

def save_png(data, dest):
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    im.thumbnail((64, 64))
    im.save(dest, "PNG")

ok = 0
for t in targets:
    i = t["id"]; d = t["d"]; dest = os.path.join(OUT, i + ".png")
    if os.path.exists(dest):
        continue
    got = False
    for url in ("https://%s/favicon.ico" % d, "https://%s/favicon.png" % d, "http://%s/favicon.ico" % d):
        try:
            r = requests.get(url, timeout=12, headers={"User-Agent": UA}, allow_redirects=True)
            if r.ok and r.content and len(r.content) >= 70 and b"<html" not in r.content[:200].lower():
                save_png(r.content, dest); got = True; break
        except Exception:
            pass
    if not got:
        try:
            r = requests.get("https://%s/" % d, timeout=12, headers={"User-Agent": UA})
            m = re.search(r'<link[^>]+rel=["\'][^"\']*icon[^"\']*["\'][^>]*>', r.text, re.I)
            if m:
                h = re.search(r'href=["\']([^"\']+)["\']', m.group(0))
                if h:
                    href = h.group(1)
                    if href.startswith("//"):
                        href = "https:" + href
                    elif href.startswith("/"):
                        href = "https://%s%s" % (d, href)
                    elif not href.lower().startswith("http"):
                        href = "https://%s/%s" % (d, href)
                    rr = requests.get(href, timeout=12, headers={"User-Agent": UA})
                    if rr.ok and rr.content and len(rr.content) >= 70:
                        save_png(rr.content, dest); got = True
        except Exception:
            pass
    print(("  favicon OK: " if got else "  favicon introuvable: ") + i)
    if got:
        ok += 1
print("  favicons recuperes: %d / %d" % (ok, len(targets)))
FAVPY
pct push $CT /tmp/fetch_favicons.py /tmp/fetch_favicons.py >/dev/null; rm /tmp/fetch_favicons.py
pct exec $CT -- python3 /tmp/fetch_favicons.py /tmp/favicon-targets.json || true
pct exec $CT -- rm -f /tmp/fetch_favicons.py /tmp/favicon-targets.json
echo "[4/8] Service web-api.py…"
cat > /tmp/web-api.py << 'PYEOF'
#!/usr/bin/env python3
"""
web-api.py v5 — service d'aide pour tracker-autovisit (127.0.0.1:8099, exposé via Nginx, LAN).
Flux "tester puis confirmer" : un test écrit le fichier (avec sauvegarde) mais ne l'affiche pas ;
seul /confirm le valide (régénère status.json). /cancel nettoie (rien enregistré).

  GET  /sites              liste détaillée
  GET  /site?slug=xxx      un site (mot de passe masqué)
  GET  /settings           réglages dashboard (nom, url, accent, dark, cron, favicon)
  POST /test    {site, original_slug?}          -> écrit (backup si existant), teste
  POST /confirm {slug, original_slug?}          -> valide (renomme si besoin) + régénère
  POST /cancel  {slug, original_slug?, created} -> supprime (si créé) ou restaure le backup
  POST /delete  {slug}                          -> supprime + régénère
  POST /toggle  {slug}                          -> bascule enabled + régénère
  POST /settings {name,url,accent,dark,cron_hours} -> écrit settings.json (+ maj cron)
  POST /favicon  {data}                         -> écrit favicon.png (+ .ico si Pillow)
"""
import base64, json, os, re, shutil, subprocess, sys, threading, glob, io
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = "/opt/tracker-autovisit"
SITES_DIR = os.path.join(BASE, "data", "sites.d")
BAK_DIR = os.path.join(BASE, "data", ".sitebak")
STATUS = os.path.join(BASE, "data", "status.json")
SCRIPT = os.path.join(BASE, "autovisit.py")
HOST, PORT = "127.0.0.1", 8099
REQUIRED = ("name", "url", "post_url", "username")

WEBROOT = os.environ.get("MAL_WEBROOT", "/var/www/autovisit")
ICONDIR = os.path.join(WEBROOT, "icones")
LOGODIR = os.path.join(WEBROOT, ".logos")
SETTINGS = os.path.join(BASE, "data", "settings.json")
ALERTS_FILE = os.path.join(BASE, "data", "alerts.json")
LOGFILE = os.path.join(BASE, "data", "logs", "cron.log")
DEFAULTS = {"name": "MALINOIS", "url": "", "accent": "#e0892b",
            "dark": False, "cron_hours": 24, "favicon": False, "css": "", "cron": {}}

# --- HTTPS / TLS ---
CT_IP    = os.environ.get("MAL_CT_IP", "127.0.0.1")
LAN_CIDR = os.environ.get("MAL_LAN_CIDR", "127.0.0.0/8")
NGINX_SITE = "/etc/nginx/sites-available/autovisit"
TLS_DIR   = os.path.join(BASE, "data", "tls")
TLS_CERT  = os.path.join(TLS_DIR, "cert.pem")
TLS_KEY   = os.path.join(TLS_DIR, "key.pem")
TLS_STATE = os.path.join(BASE, "data", "tls.json")

AUTH = os.path.join(BASE, "data", "auth.json")
COOKIE = "av_session"
TTL_REMEMBER = 30 * 24 * 3600   # « se souvenir » : 30 jours
TTL_SESSION = 12 * 3600         # sinon : 12 h (et cookie de session)
PENDING_2FA = {}   # token -> secret en cours d'activation


def load_auth():
    try:
        return json.load(open(AUTH, encoding="utf-8"))
    except Exception:
        return {}


def save_auth(a):
    fd = os.open(AUTH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(a, f)


def is_configured():
    return bool(load_auth().get("pwd_hash"))


def _hash(pw, salt):
    import hashlib
    return hashlib.pbkdf2_hmac("sha256", (pw or "").encode(), bytes.fromhex(salt), 120000).hex()


def set_password(new):
    import secrets
    a = load_auth()
    salt = secrets.token_hex(16)
    a["pwd_salt"] = salt
    a["pwd_hash"] = _hash(new, salt)
    a["server_secret"] = secrets.token_hex(32)   # rotation -> invalide toutes les sessions existantes
    save_auth(a)


# --- Anti-bruteforce : throttle global du login ---
LOGIN_MAX_FAILS = 5
LOGIN_WINDOW = 300
_login_fails = []
_login_lock = threading.Lock()

def login_blocked():
    import time
    now = time.time()
    with _login_lock:
        _login_fails[:] = [t for t in _login_fails if now - t < LOGIN_WINDOW]
        return len(_login_fails) >= LOGIN_MAX_FAILS

def login_record_fail():
    import time
    with _login_lock:
        _login_fails.append(time.time())

def login_reset():
    with _login_lock:
        _login_fails.clear()


def check_password(pw):
    import hmac
    a = load_auth()
    if not a.get("pwd_hash"):
        return False
    return hmac.compare_digest(_hash(pw, a.get("pwd_salt", "")), a["pwd_hash"])


def check_totp(code):
    a = load_auth()
    sec = a.get("totp_secret")
    if not (a.get("twofa") and sec):
        return True  # 2FA non activé -> rien à vérifier
    try:
        import pyotp
        return pyotp.TOTP(sec).verify((code or "").strip(), valid_window=1)
    except Exception:
        return False


def _server_secret():
    import secrets
    a = load_auth()
    s = a.get("server_secret")
    if not s:
        s = secrets.token_hex(32)
        a["server_secret"] = s
        save_auth(a)
    return s


def new_session(ttl=TTL_REMEMBER):
    """Jeton signé sans état (survit à un redémarrage du service)."""
    import hmac, hashlib, time
    exp = int(time.time()) + int(ttl)
    sig = hmac.new(_server_secret().encode(), str(exp).encode(), hashlib.sha256).hexdigest()
    return "%d.%s" % (exp, sig)


def valid_session(tok):
    import hmac, hashlib, time
    if not tok or "." not in tok:
        return False
    exp_s, _, sig = tok.partition(".")
    try:
        exp = int(exp_s)
    except ValueError:
        return False
    if exp < time.time():
        return False
    good = hmac.new(_server_secret().encode(), exp_s.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(good, sig)


def cookie_token(handler):
    raw = handler.headers.get("Cookie", "") or ""
    for part in raw.split(";"):
        if "=" in part:
            k, v = part.strip().split("=", 1)
            if k == COOKIE:
                return v
    return ""


def read_settings():
    s = dict(DEFAULTS)
    try:
        s.update(json.load(open(SETTINGS, encoding="utf-8")))
    except Exception:
        pass
    return s


def write_settings(s):
    cur = read_settings()
    for k in DEFAULTS:
        if k in s and s[k] is not None:
            cur[k] = s[k]
    fd = os.open(SETTINGS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cur, f, ensure_ascii=False, indent=2)
    return cur


def _write_cron(line):
    """Remplace la ligne autovisit du crontab (sans toucher au reste). line='' => supprime."""
    try:
        cur = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        existing = cur.stdout if cur.returncode == 0 else ""
    except Exception:
        existing = ""
    kept = [l for l in existing.splitlines()
            if l.strip() and "autovisit.py" not in l]
    if line:
        kept.append(line)
    payload = ("\n".join(kept) + "\n").encode("utf-8")
    try:
        p = subprocess.run(["crontab", "-"], input=payload, capture_output=True)
        return p.returncode == 0
    except Exception:
        return False


def update_cron(hours):
    """Planifie autovisit tous les N jours (N = hours/24) à 6h, sans toucher au reste du crontab."""
    n = max(1, int(hours) // 24)
    return _write_cron("0 6 */%d * * %s --json-output >> %s 2>&1" % (n, SCRIPT, LOGFILE))


def cron_schedule(opts):
    """Construit les 5 champs cron à partir d'options structurées (heure/minute + mode)."""
    mn = max(0, min(59, int(opts.get("minute", 0) or 0)))
    hr = max(0, min(23, int(opts.get("hour", 6) or 0)))
    mode = opts.get("mode", "interval")
    if mode == "weekdays":
        wd = [str(d) for d in (opts.get("weekdays") or []) if str(d) in ("0", "1", "2", "3", "4", "5", "6")]
        dow = ",".join(wd) if wd else "*"
        return "%d %d * * %s" % (mn, hr, dow)
    if mode == "daily":
        return "%d %d * * *" % (mn, hr)
    n = max(1, min(60, int(opts.get("interval_days", 1) or 1)))
    return "%d %d */%d * *" % (mn, hr, n)


def set_cron(opts):
    """Écrit la ligne autovisit selon une planification structurée."""
    line = "%s %s --json-output >> %s 2>&1" % (cron_schedule(opts), SCRIPT, LOGFILE)
    return _write_cron(line)


def current_cron():
    """Retourne la ligne cron autovisit active (ou '')."""
    try:
        cur = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        for l in (cur.stdout or "").splitlines():
            s = l.strip()
            if s and not s.startswith("#") and "autovisit.py" in s:
                return s
    except Exception:
        pass
    return ""


def save_favicon(data_url):
    """Accepte un dataURL base64 (image), écrit favicon.png (+ .ico si Pillow dispo)."""
    raw = data_url.split(",", 1)[1] if "," in data_url else data_url
    img = base64.b64decode(raw)
    if len(img) > 2 * 1024 * 1024:
        raise ValueError("Image trop volumineuse (max 2 Mo)")
    os.makedirs(WEBROOT, exist_ok=True)
    png = os.path.join(WEBROOT, "favicon.png")
    with open(png, "wb") as f:
        f.write(img)
    os.chmod(png, 0o644)
    try:
        from PIL import Image
        Image.MAX_IMAGE_PIXELS = 16 * 1024 * 1024   # ~16 Mpx : rejette les bombes de decompression
        import io
        im = Image.open(io.BytesIO(img)).convert("RGBA")
        im.save(os.path.join(WEBROOT, "favicon.ico"),
                sizes=[(16, 16), (32, 32), (48, 48)])
        im.resize((180, 180)).save(os.path.join(WEBROOT, "apple-touch-icon.png"))
    except Exception:
        pass
    return True


def delete_favicon():
    """Supprime le logo personnalise (favicon.png/.ico + apple-touch-icon)."""
    for fn in ("favicon.png", "favicon.ico", "apple-touch-icon.png"):
        try:
            os.remove(os.path.join(WEBROOT, fn))
        except Exception:
            pass
    return True


_UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"


def fetch_favicon(domain, dest):
    """Recupere le favicon d'un domaine -> PNG 64px dans dest. Best-effort, le conteneur a Internet."""
    try:
        import requests
        from PIL import Image
    except Exception:
        return False
    dom = (domain or "").strip().lower()
    if not dom:
        return False

    def _save(b):
        im = Image.open(io.BytesIO(b)).convert("RGBA")
        im.thumbnail((64, 64))
        im.save(dest, "PNG")
        return True

    for url in ("https://%s/favicon.ico" % dom, "https://%s/favicon.png" % dom,
                "http://%s/favicon.ico" % dom):
        try:
            r = requests.get(url, timeout=12, headers={"User-Agent": _UA}, allow_redirects=True)
            if r.ok and r.content and len(r.content) >= 70 and b"<html" not in r.content[:200].lower():
                return _save(r.content)
        except Exception:
            pass
    # secours : lien <link rel=icon> de la page d'accueil
    try:
        r = requests.get("https://%s/" % dom, timeout=12, headers={"User-Agent": _UA})
        m = re.search(r'<link[^>]+rel=["\'][^"\']*icon[^"\']*["\'][^>]*>', r.text, re.I)
        if m:
            h = re.search(r'href=["\']([^"\']+)["\']', m.group(0))
            if h:
                href = h.group(1)
                if href.startswith("//"):
                    href = "https:" + href
                elif href.startswith("/"):
                    href = "https://%s%s" % (dom, href)
                elif not href.lower().startswith("http"):
                    href = "https://%s/%s" % (dom, href)
                rr = requests.get(href, timeout=12, headers={"User-Agent": _UA})
                if rr.ok and rr.content and len(rr.content) >= 70:
                    return _save(rr.content)
    except Exception:
        pass
    return False


# Etat de la reactualisation globale des stats (run en arriere-plan)
_refreshing = {"on": False}

# Revisites individuelles en cours (par slug) : permet de rendre /revisit non
# bloquant (le subprocess de reconnexion peut durer ~180 s) tout en laissant le
# navigateur interroger l'avancement via /revisitstate, sans garder de connexion
# HTTP ouverte (ce qui saturerait son pool de connexions).
_revisiting = set()
_revisiting_lock = threading.Lock()


def _bg_revisit(slug, name):
    try:
        regenerate_one(name)
    finally:
        with _revisiting_lock:
            _revisiting.discard(slug)


def _bg_refresh():
    try:
        regenerate_status()
        check_and_alert()
    finally:
        _refreshing["on"] = False


def slugify(name):
    return re.sub(r"[^a-z0-9_-]", "", (name or "").strip().lower().replace(" ", "-"))


def site_path(slug):
    p = os.path.join(SITES_DIR, slug + ".json")
    if os.path.dirname(os.path.realpath(p)) != os.path.realpath(SITES_DIR):
        raise ValueError("Chemin invalide")
    return p


def _abs_url(site, u):
    """Resout une URL de page de stats : absolue telle quelle, sinon collee sur
    la racine (scheme+host) du site."""
    u = (u or "").strip()
    if not u:
        return ""
    if u.startswith("http://") or u.startswith("https://"):
        return u
    base = site.get("url") or site.get("verify_url") or site.get("login_url") or ""
    m = re.match(r"^(https?://[^/]+)", base or "")
    root = m.group(1) if m else ""
    if not u.startswith("/"):
        u = "/" + u
    return root + u


def bak_path(slug):
    return os.path.join(BAK_DIR, slug + ".json")


def write_site(site):
    slug = slugify(site.get("name", ""))
    if not slug:
        raise ValueError("Nom de site invalide")
    # Auth par cookies de session : on écrit les cookies dans un fichier dédié
    cookie_auth = ("session_cookies" in site) or site.get("session_cookies_file") or site.get("cf_solver")
    sc = site.pop("session_cookies", None)
    if sc is not None:
        cdir = os.path.join(BASE, "data", "cookies")
        os.makedirs(cdir, exist_ok=True)
        cf = os.path.join(cdir, slug + ".json")
        with open(cf, "w", encoding="utf-8") as f:
            json.dump(sc, f, ensure_ascii=False)
        try:
            os.chmod(cf, 0o600)
        except Exception:
            pass
        site["session_cookies_file"] = cf
    if not site.get("name") or not site.get("url"):
        raise ValueError("Champ manquant : name/url")
    if site["name"].lstrip().startswith("-"):
        raise ValueError("Le nom ne peut pas commencer par « - ».")
    if cookie_auth:
        if not (site.get("session_cookies_file") or site.get("cf_solver")):
            raise ValueError("Cookies de session manquants")
    else:
        if not site.get("post_url"):
            raise ValueError("Champ manquant : post_url")
        if site.get("username_field") and not site.get("username"):
            raise ValueError("Champ manquant : username")
        if not site.get("password"):
            raise ValueError("Mot de passe manquant")
    os.makedirs(SITES_DIR, exist_ok=True)
    p = site_path(slug)
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(site, f, ensure_ascii=False, indent=2)
    return slug, p


def read_site(slug):
    return json.load(open(site_path(slug), encoding="utf-8"))


def test_site(name):
    # Une seule connexion : on teste ET on met a jour le tableau, pour eviter une
    # deuxieme connexion a l'enregistrement (qui reutiliserait le meme code 2FA).
    try:
        out = regenerate_one(name)
    except Exception as e:
        return False, "Erreur : %s" % e
    if not out:
        return False, "Aucune sortie du test."
    resume = out.split("=== Resume")[-1] if "=== Resume" in out else out
    fail = ("ECHEC" in resume) or ("echec(s)" in resume)
    win = ("reussie" in resume.lower()) or ("succes" in resume.lower())
    ok = win and not fail
    lines = [l for l in out.splitlines() if l.strip()]
    return ok, "\n".join(lines[-14:])


def regenerate_status():
    try:
        p = subprocess.run([sys.executable, SCRIPT, "--json-output"],
                           cwd=BASE, capture_output=True, text=True, timeout=120)
        out = (p.stdout or "") + (p.stderr or "")
        if "Aucun site" in out:
            open(STATUS, "w", encoding="utf-8").write("{}")
    except Exception:
        pass


def regenerate_one(name):
    """Visite UNIQUEMENT ce site puis fusionne son resultat dans status.json,
    sans revisiter tous les autres. Retourne la sortie du run."""
    if not name:
        regenerate_status()
        return ""
    full = _load_status()
    if not isinstance(full, dict):
        full = {}
    full_sites = full.get("sites", []) or []
    out = ""
    try:
        p = subprocess.run([sys.executable, SCRIPT, "--site", name, "--json-output"],
                           cwd=BASE, capture_output=True, text=True, timeout=180)
        out = (p.stdout or "") + (p.stderr or "")
    except Exception as e:
        out = "ECHEC subprocess : %s" % e
    one = _load_status()
    one_sites = one.get("sites", []) if isinstance(one, dict) else []
    nl = (name or "").lower()
    fresh = [s for s in one_sites if (s.get("name") or "").lower() == nl]
    merged = [s for s in full_sites if (s.get("name") or "").lower() != nl] + fresh
    full["sites"] = merged
    if isinstance(one, dict) and one.get("updated"):
        full["updated"] = one["updated"]
    _save_status(full)
    return out


def list_sites():
    res = []
    try:
        files = sorted(f for f in os.listdir(SITES_DIR) if f.endswith(".json"))
    except FileNotFoundError:
        files = []
    for f in files:
        try:
            d = json.load(open(os.path.join(SITES_DIR, f), encoding="utf-8"))
        except Exception:
            continue
        res.append({"slug": f[:-5], "name": d.get("name", f[:-5]),
                    "url": d.get("url", ""), "enabled": d.get("enabled", True)})
    return res


def clear_bak(slug):
    b = bak_path(slug)
    if os.path.exists(b):
        os.remove(b)


def _safe_key(n):
    n = (n or "").strip().lower().replace("/", "").replace("\\", "").replace("..", "")
    return n


def assign_logo(key, logo):
    """Copie .logos/<logo>.png -> icones/<key>.png (idempotent, n'écrase pas un icône existant)."""
    key = _safe_key(key); logo = _safe_key(logo)
    if not key or not logo:
        return False
    src = os.path.join(LOGODIR, logo + ".png")
    if not os.path.exists(src):
        return False
    os.makedirs(ICONDIR, exist_ok=True)
    dst = os.path.join(ICONDIR, key + ".png")
    if os.path.exists(dst):
        return True
    shutil.copy2(src, dst)
    try:
        os.chmod(dst, 0o644)
    except Exception:
        pass
    return True


def _load_status():
    try:
        return json.load(open(STATUS, encoding="utf-8"))
    except Exception:
        return {}


def _save_status(d):
    fd = os.open(STATUS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False)


def prune_status(name):
    d = _load_status()
    if isinstance(d.get("sites"), list):
        low = (name or "").lower()
        d["sites"] = [s for s in d["sites"] if s.get("name", "").lower() != low]
        _save_status(d)


def set_status_disabled(name, disabled):
    d = _load_status()
    low = (name or "").lower()
    for s in d.get("sites", []) or []:
        if s.get("name", "").lower() == low:
            s["disabled"] = bool(disabled)
    _save_status(d)


# ===================== HTTPS / TLS =====================
def _tls_run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)

def read_tls_state():
    s = {"enabled": False, "mode": "none"}
    try:
        s.update(json.load(open(TLS_STATE, encoding="utf-8")))
    except Exception:
        pass
    return s

def write_tls_state(s):
    fd = os.open(TLS_STATE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(s, f, ensure_ascii=False, indent=2)

def _log_line(fname, msg):
    """Ecrit une ligne horodatee dans data/logs/<fname> (visible dans l'onglet Logs)."""
    try:
        import time
        ld = os.path.join(BASE, "data", "logs")
        os.makedirs(ld, exist_ok=True)
        with open(os.path.join(ld, fname), "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S  ") + str(msg).strip() + "\n")
    except Exception:
        pass


def _tls_log(msg):
    """Journalise les operations TLS/cert dans data/logs/tls.log (visible dans l'onglet Logs)."""
    _log_line("tls.log", msg)


def _inspect_log(msg):
    """Journalise les inspections dans data/logs/inspect.log (visible dans l'onglet Logs)."""
    _log_line("inspect.log", msg)


def _alert_log(msg):
    """Journalise les envois d'alertes dans data/logs/alerts.log (visible dans l'onglet Logs)."""
    _log_line("alerts.log", msg)


# ===== Alertes / notifications (email SMTP, Telegram, webhook/ntfy) =====
def read_alerts():
    base = {"email": {}, "telegram": {}, "webhook": {}, "browser": {"enabled": False},
            "on_failure": False, "on_recovery": False, "on_each_run": False, "on_stats_na": False}
    try:
        d = json.load(open(ALERTS_FILE, encoding="utf-8"))
        if isinstance(d, dict):
            base.update(d)
    except Exception:
        pass
    return base


def write_alerts(cfg):
    fd = os.open(ALERTS_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return cfg


def _alerts_masked():
    """Config pour le frontend : secrets remplaces par un booleen <champ>_set."""
    c = read_alerts()
    out = json.loads(json.dumps(c))
    for ch, key in (("email", "password"), ("telegram", "token"), ("webhook", "auth")):
        d = out.get(ch) or {}
        d[key + "_set"] = bool((c.get(ch) or {}).get(key))
        d.pop(key, None)
        out[ch] = d
    out.pop("_last_failed", None)
    return out


def _update_alerts(incoming):
    """Mise a jour CIBLEE : ne touche que ce qui est fourni (un canal, les conditions, ou le navigateur),
    sans ecraser les autres reglages. Preserve les secrets si le champ est vide."""
    cur = read_alerts()
    ch = incoming.get("channel")
    secrets = {"email": "password", "telegram": "token", "webhook": "auth"}
    if ch in secrets:
        key = secrets[ch]
        new = dict(incoming.get(ch) or {})
        new.pop(key + "_set", None)
        if not new.get(key):
            old = (cur.get(ch) or {}).get(key)
            if old:
                new[key] = old
            else:
                new.pop(key, None)
        cur[ch] = new
    if incoming.get("types"):
        cur["on_failure"] = bool(incoming.get("on_failure"))
        cur["on_recovery"] = bool(incoming.get("on_recovery"))
        cur["on_each_run"] = bool(incoming.get("on_each_run"))
        cur["on_stats_na"] = bool(incoming.get("on_stats_na"))
    if "browser" in incoming:
        cur["browser"] = {"enabled": bool((incoming.get("browser") or {}).get("enabled"))}
    write_alerts(cur)
    return cur


def _send_email(em, subject, body):
    if not (em.get("host") and em.get("to")):
        return (False, "serveur ou destinataire manquant")
    try:
        import smtplib, ssl
        from email.mime.text import MIMEText
        msg = MIMEText(body, "plain", "utf-8")
        msg["Subject"] = subject
        sender = em.get("from") or em.get("user") or "malinois@localhost"
        msg["From"] = sender; msg["To"] = em["to"]
        port = int(em.get("port") or 587)
        sec = (em.get("security") or "starttls").lower()
        if sec == "ssl":
            srv = smtplib.SMTP_SSL(em["host"], port, timeout=15)
        else:
            srv = smtplib.SMTP(em["host"], port, timeout=15)
            if sec == "starttls":
                srv.starttls(context=ssl.create_default_context())
        if em.get("user"):
            srv.login(em["user"], em.get("password", ""))
        rcpts = [a.strip() for a in str(em["to"]).replace(";", ",").split(",") if a.strip()]
        srv.sendmail(sender, rcpts, msg.as_string()); srv.quit()
        return (True, "")
    except Exception as e:
        return (False, str(e))


def _send_telegram(tg, subject, body):
    if not (tg.get("token") and tg.get("chat_id")):
        return (False, "token ou chat_id manquant")
    try:
        import urllib.request, urllib.parse
        url = "https://api.telegram.org/bot%s/sendMessage" % tg["token"]
        payload = urllib.parse.urlencode({"chat_id": tg["chat_id"],
                                          "text": subject + "\n\n" + body}).encode("utf-8")
        urllib.request.urlopen(urllib.request.Request(url, data=payload), timeout=15).read()
        return (True, "")
    except Exception as e:
        return (False, str(e))


def _send_webhook(wh, subject, body):
    if not wh.get("url"):
        return (False, "URL manquante")
    try:
        import urllib.request
        req = urllib.request.Request(wh["url"], data=(subject + "\n\n" + body).encode("utf-8"), method="POST")
        req.add_header("Title", subject)
        req.add_header("Content-Type", "text/plain; charset=utf-8")
        if wh.get("auth"):
            req.add_header("Authorization", wh["auth"])
        urllib.request.urlopen(req, timeout=15).read()
        return (True, "")
    except Exception as e:
        return (False, str(e))


_SENDERS = {"email": _send_email, "telegram": _send_telegram, "webhook": _send_webhook}


def send_alert(subject, body):
    """Envoie via tous les canaux actives. Retourne [(canal, ok, erreur)]."""
    cfg = read_alerts()
    res = []
    for ch in ("email", "telegram", "webhook"):
        c = cfg.get(ch) or {}
        if c.get("enabled"):
            ok, err = _SENDERS[ch](c, subject, body)
            res.append((ch, ok, err))
            _alert_log("envoi %s [%s] : %s" % (ch, subject, "OK" if ok else ("ECHEC — " + err)))
    return res


def test_channel(channel):
    """Teste un seul canal depuis la config sauvegardee (ignore le flag 'enabled')."""
    fn = _SENDERS.get(channel)
    if not fn:
        return (False, "canal inconnu")
    cfg = read_alerts()
    ok, err = fn(cfg.get(channel) or {}, "Malinois : test de notification",
                 "Ceci est un message de test (canal %s) envoye depuis le dashboard Malinois." % channel)
    _alert_log("test %s : %s" % (channel, "OK" if ok else ("ECHEC — " + err)))
    return (ok, err)


def check_and_alert():
    """Apres un refresh : envoie les alertes selon les types actives (anti-spam memorise)."""
    try:
        cfg = read_alerts()
        if not (cfg.get("on_failure") or cfg.get("on_recovery") or cfg.get("on_each_run") or cfg.get("on_stats_na")):
            return
        st = _load_status()
        sites = st.get("sites") or [] if isinstance(st, dict) else []
        failed = sorted(s.get("name", s.get("slug", "?")) for s in sites if not s.get("ok", True))
        total = len(sites)
        prev = cfg.get("_last_failed") or []
        new_fail = [f for f in failed if f not in prev]
        recovered = [f for f in prev if f not in failed]
        msgs = []
        if cfg.get("on_each_run"):
            resume = "Resume visite : %d site(s), %d en echec." % (total, len(failed))
            if failed:
                resume += " En echec : " + ", ".join(failed) + "."
            msgs.append(resume)
        if cfg.get("on_failure") and new_fail:
            m = "Nouveaux sites en echec : " + ", ".join(new_fail) + "."
            if len(failed) > len(new_fail):
                m += " (total en echec : " + ", ".join(failed) + ")"
            msgs.append(m)
        if cfg.get("on_recovery") and recovered:
            msgs.append("Sites retablis (de nouveau OK) : " + ", ".join(recovered) + ".")
        na_sites = []
        if cfg.get("on_stats_na"):
            def _na(v):
                return v is None or (isinstance(v, str) and (v.strip() == "" or v.strip().upper() == "N/A"))
            for s in sites:
                if not s.get("ok", True):
                    continue  # echec de visite : deja couvert par on_failure
                stats = s.get("stats") or s.get("stats_json") or s.get("extra_stats") or {}
                if isinstance(stats, dict) and "upload" in stats and _na(stats.get("upload")):
                    na_sites.append(s.get("name", s.get("slug", "?")))
            na_sites = sorted(na_sites)
            new_na = [n for n in na_sites if n not in (cfg.get("_last_stats_na") or [])]
            if new_na:
                msgs.append("Statistiques non recuperees (upload = N/A) sur : " + ", ".join(new_na)
                            + ". Probablement une erreur de recuperation/renouvellement de cookie -- verifie ou reimporte les cookies de session.")
        for m in msgs:
            send_alert("Malinois : alerte visite", m)
        changed = False
        if failed != prev:
            cfg["_last_failed"] = failed; changed = True
        if cfg.get("on_stats_na") and na_sites != (cfg.get("_last_stats_na") or []):
            cfg["_last_stats_na"] = na_sites; changed = True
        if changed:
            write_alerts(cfg)
    except Exception:
        pass

def _active_paths():
    """Chemins cert/cle actifs selon le mode (certbot -> /etc/letsencrypt, sinon data/tls)."""
    st = read_tls_state()
    if st.get("mode") == "certbot" and st.get("domain"):
        dom = re.sub(r"[^a-zA-Z0-9.-]", "", st["domain"])
        d = "/etc/letsencrypt/live/" + dom
        return os.path.join(d, "fullchain.pem"), os.path.join(d, "privkey.pem")
    return TLS_CERT, TLS_KEY

def https_on():
    c, k = _active_paths()
    return bool(read_tls_state().get("enabled")) and os.path.exists(c) and os.path.exists(k)

def tls_cert_info(path=None):
    import ssl
    if path is None:
        path = _active_paths()[0]
    try:
        d = ssl._ssl._test_decode_cert(path)
    except Exception:
        return None
    subj = dict(x[0] for x in d.get("subject", []))
    iss = dict(x[0] for x in d.get("issuer", []))
    san = [v for (k, v) in d.get("subjectAltName", [])]
    return {"cn": subj.get("commonName", ""), "issuer": iss.get("commonName", ""),
            "san": san, "not_after": d.get("notAfter", ""), "self_signed": (subj == iss)}

def _pubkey_cert(p):
    r = _tls_run(["openssl", "x509", "-in", p, "-noout", "-pubkey"]); return r.stdout if r.returncode == 0 else ""

def _pubkey_key(p):
    r = _tls_run(["openssl", "pkey", "-in", p, "-pubout"]); return r.stdout if r.returncode == 0 else ""

def validate_pair(cert_pem, key_pem):
    import tempfile, shutil
    td = tempfile.mkdtemp()
    cp, kp = os.path.join(td, "c.pem"), os.path.join(td, "k.pem")
    try:
        open(cp, "w").write(cert_pem); open(kp, "w").write(key_pem)
        if _tls_run(["openssl", "x509", "-in", cp, "-noout"]).returncode != 0:
            return False, "Certificat invalide (PEM attendu)"
        if _tls_run(["openssl", "pkey", "-in", kp, "-noout"]).returncode != 0:
            return False, "Cle privee invalide (PEM attendu)"
        cpub, kpub = _pubkey_cert(cp), _pubkey_key(kp)
        if not cpub or cpub != kpub:
            return False, "La cle privee ne correspond pas au certificat"
        return True, "ok"
    finally:
        shutil.rmtree(td, ignore_errors=True)

def install_pair(cert_pem, key_pem):
    ok, msg = validate_pair(cert_pem, key_pem)
    if not ok:
        return False, msg
    os.makedirs(TLS_DIR, exist_ok=True)
    open(TLS_CERT, "w").write(cert_pem)
    fd = os.open(TLS_KEY, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, key_pem.encode()); os.close(fd)
    os.chmod(TLS_CERT, 0o644)
    return True, "ok"

def gen_selfsigned(opts):
    import tempfile, shutil
    opts = opts or {}
    def _clean(s):
        return re.sub(r"[\r\n\[\]=]", "", str(s or "")).strip()
    cn = _clean(opts.get("cn"))
    san = opts.get("san") or []
    if isinstance(san, str):
        san = san.replace(",", " ").split()
    san = [_clean(s) for s in san]
    san = [s for s in san if s]
    if cn and cn not in san:
        san = [cn] + san
    if not san:
        san = [CT_IP]
    if not cn:
        cn = san[0]
    ips = [h for h in san if h.replace(".", "").isdigit()]
    dns = [h for h in san if h not in ips]
    alt = "".join("IP.%d=%s\n" % (i + 1, v) for i, v in enumerate(ips)) + \
          "".join("DNS.%d=%s\n" % (i + 1, v) for i, v in enumerate(dns))
    dn = "CN=%s\n" % cn
    org = _clean(opts.get("org"))
    if org:
        dn += "O=%s\n" % org
    ou = _clean(opts.get("ou"))
    if ou:
        dn += "OU=%s\n" % ou
    country = re.sub(r"[^A-Za-z]", "", str(opts.get("country") or ""))[:2].upper()
    if len(country) == 2:
        dn += "C=%s\n" % country
    try:
        days = int(opts.get("days") or 825)
    except Exception:
        days = 825
    days = max(1, min(days, 3650))
    cnf = ("[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\n%s"
           "[v3]\nsubjectAltName=@alt\nbasicConstraints=CA:FALSE\n"
           "keyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n[alt]\n%s" % (dn, alt))
    os.makedirs(TLS_DIR, exist_ok=True)
    td = tempfile.mkdtemp(); cfgp = os.path.join(td, "san.cnf")
    try:
        open(cfgp, "w").write(cnf)
        r = _tls_run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                      "-keyout", TLS_KEY, "-out", TLS_CERT, "-days", str(days), "-config", cfgp])
        if r.returncode != 0:
            return False, "openssl a echoue : " + (r.stderr or "")[:200]
        os.chmod(TLS_KEY, 0o600); os.chmod(TLS_CERT, 0o644)
        return True, "ok"
    finally:
        shutil.rmtree(td, ignore_errors=True)

def _nginx_locations():
    api = ("test|confirm|cancel|delete|toggle|sites|site|settings|favicon|logosync|inspect|"
           "logs|favsync|refreshall|refreshstate|revisit|revisitstate|sitestats|siterestore|cron")
    return (
        "    add_header X-Frame-Options DENY;\n"
        "    add_header X-Content-Type-Options nosniff;\n"
        "    location = /addsite.js { allow %s; deny all; add_header Cache-Control \"no-store\"; }\n"
        "    location = /index.html { allow %s; deny all; add_header Cache-Control \"no-store\"; }\n"
        "    location = / { allow %s; deny all; add_header Cache-Control \"no-store\"; }\n"
        "    location = /status.json { allow %s; deny all; proxy_pass http://127.0.0.1:8099/status; proxy_set_header Host $host; proxy_set_header Cookie $http_cookie; proxy_set_header X-Forwarded-Proto $scheme; add_header Cache-Control \"no-store, no-cache, must-revalidate\"; }\n"
        "    location ~ ^/auth/ { allow %s; deny all; proxy_pass http://127.0.0.1:8099; proxy_set_header Host $host; proxy_set_header Cookie $http_cookie; proxy_set_header X-Forwarded-Proto $scheme; }\n"
        "    location ~ ^/tls/ { allow %s; deny all; proxy_pass http://127.0.0.1:8099; proxy_set_header Host $host; proxy_set_header Cookie $http_cookie; proxy_set_header X-Forwarded-Proto $scheme; client_max_body_size 4m; proxy_read_timeout 150s; }\n"
        "    location ~ ^/alerts { allow %s; deny all; proxy_pass http://127.0.0.1:8099; proxy_set_header Host $host; proxy_set_header Cookie $http_cookie; proxy_set_header X-Forwarded-Proto $scheme; proxy_read_timeout 40s; }\n"
        "    location ~ ^/(%s)$ { allow %s; deny all; proxy_pass http://127.0.0.1:8099; proxy_set_header Host $host; proxy_set_header Cookie $http_cookie; proxy_set_header X-Forwarded-Proto $scheme; client_max_body_size 4m; proxy_connect_timeout 20s; proxy_send_timeout 200s; proxy_read_timeout 200s; }\n"
        % (LAN_CIDR, LAN_CIDR, LAN_CIDR, LAN_CIDR, LAN_CIDR, LAN_CIDR, LAN_CIDR, api, LAN_CIDR))

def _acme_loc():
    return ("    location ^~ /.well-known/acme-challenge/ { allow all; default_type \"text/plain\"; root %s; }\n" % WEBROOT)

def nginx_config(https):
    loc = _nginx_locations()
    st = read_tls_state()
    name = st["domain"] if (st.get("mode") == "certbot" and st.get("domain")) else CT_IP
    cert, key = _active_paths()
    acme = _acme_loc()
    if not https:
        return ("server {\n    listen 80;\n    server_name %s;\n    root %s;\n    index index.html;\n%s%s}\n"
                % (name, WEBROOT, acme, loc))
    return ("server {\n    listen 80;\n    server_name %s;\n%s    location / { return 301 https://$host$request_uri; }\n}\n"
            "server {\n    listen 443 ssl;\n    server_name %s;\n"
            "    ssl_certificate %s;\n    ssl_certificate_key %s;\n"
            "    ssl_protocols TLSv1.2 TLSv1.3;\n"
            "    root %s;\n    index index.html;\n%s%s}\n"
            % (name, acme, name, cert, key, WEBROOT, acme, loc))

def write_nginx_from_state():
    """Ecrit la conf nginx selon tls.json (sans recharger). Utilise au deploiement."""
    c, k = _active_paths()
    https = read_tls_state().get("enabled") and os.path.exists(c) and os.path.exists(k)
    open(NGINX_SITE, "w", encoding="utf-8").write(nginx_config(bool(https)))
    return bool(https)

def apply_nginx(https):
    """Ecrit la conf voulue, teste (nginx -t), recharge. Rollback si echec."""
    try:
        prev = open(NGINX_SITE, encoding="utf-8").read()
    except Exception:
        prev = None
    open(NGINX_SITE, "w", encoding="utf-8").write(nginx_config(https))
    t = _tls_run(["nginx", "-t"])
    if t.returncode != 0:
        if prev is not None:
            open(NGINX_SITE, "w", encoding="utf-8").write(prev)
            _tls_run(["nginx", "-s", "reload"])
        return False, "nginx -t a echoue (config restauree) : " + (t.stderr or "")[-300:]
    r = _tls_run(["nginx", "-s", "reload"])
    if r.returncode != 0:
        return False, "reload nginx a echoue : " + (r.stderr or "")[:200]
    return True, "ok"


def _ensure_certbot():
    import shutil as _sh
    if _sh.which("certbot"):
        return True
    _tls_run(["apt-get", "update"], timeout=120)
    _tls_run(["apt-get", "install", "-y", "certbot"], timeout=180)
    return _sh.which("certbot") is not None

def run_certbot(domain, email, staging):
    """Obtient un cert Let's Encrypt via HTTP-01 (webroot) et installe le hook de renouvellement."""
    domain = re.sub(r"[^a-zA-Z0-9.-]", "", (domain or "").strip())
    email = re.sub(r"[^a-zA-Z0-9.@_+-]", "", (email or "").strip())
    if not domain or "." not in domain:
        return False, "Domaine invalide (un vrai nom de domaine public est requis)."
    if not email or "@" not in email:
        return False, "Email invalide."
    if not _ensure_certbot():
        return False, "certbot indisponible (echec d'installation)."
    # nginx doit deja servir /.well-known/acme-challenge/ en clair (genere dans la conf)
    try:
        os.makedirs(os.path.join(WEBROOT, ".well-known", "acme-challenge"), exist_ok=True)
    except Exception:
        pass
    args = ["certbot", "certonly", "--webroot", "-w", WEBROOT, "-d", domain,
            "--email", email, "--agree-tos", "--non-interactive", "--keep-until-expiring"]
    if staging:
        args.append("--staging")
    _tls_log("certbot : demande pour %s (staging=%s)" % (domain, bool(staging)))
    r = _tls_run(args, timeout=140)
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "")[-700:]
        _tls_log("certbot ECHEC (%s) :\n%s" % (domain, err))
        return False, "certbot a echoue : " + err[-400:]
    _tls_log("certbot OK : certificat obtenu pour %s" % domain)
    # hook de deploiement : recharge nginx apres chaque renouvellement automatique (certbot.timer)
    try:
        hookdir = "/etc/letsencrypt/renewal-hooks/deploy"
        os.makedirs(hookdir, exist_ok=True)
        hp = os.path.join(hookdir, "reload-nginx.sh")
        open(hp, "w").write("#!/bin/sh\nnginx -t && systemctl reload nginx\n")
        os.chmod(hp, 0o755)
    except Exception:
        pass
    return True, "ok"


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj, cookie=None):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if cookie is not None:
            # Secure UNIQUEMENT si la requete arrive reellement en HTTPS (X-Forwarded-Proto
            # transmis par nginx). Sinon, en HTTP, le navigateur rejette le cookie Secure
            # -> pas de session -> dashboard vide / login en boucle.
            proto = (self.headers.get("X-Forwarded-Proto", "") or "").lower()
            if proto == "https" and "Secure" not in cookie:
                cookie = cookie + "; Secure"
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if n > 8 * 1024 * 1024:
            raise ValueError("corps de requete trop volumineux")
        return json.loads((self.rfile.read(n) if n else b"{}").decode("utf-8"))

    def _authed(self):
        return valid_session(cookie_token(self))

    def _gate(self):
        """True si l'accès est refusé (auth configurée et session invalide)."""
        return is_configured() and not self._authed()

    def log_message(self, *a):
        pass

    def do_GET(self):
        u = urlparse(self.path); route = u.path.rstrip("/")
        if route == "/auth/status":
            return self._send(200, {"ok": True, "configured": is_configured(),
                                    "twofa": bool(load_auth().get("twofa")),
                                    "accent": read_settings().get("accent", ""),
                                    "authed": self._authed()})
        if self._gate():
            return self._send(401, {"ok": False, "error": "auth"})
        if route == "/status":
            d = _load_status()
            return self._send(200, d if d else {})
        if route == "/sites":
            return self._send(200, {"ok": True, "sites": list_sites()})
        if route == "/site":
            slug = slugify((parse_qs(u.query).get("slug") or [""])[0])
            try:
                d = read_site(slug)
            except Exception:
                return self._send(404, {"ok": False, "error": "site introuvable"})
            d["password"] = ""
            return self._send(200, {"ok": True, "site": d})
        if route == "/settings":
            return self._send(200, {"ok": True, "settings": read_settings()})
        if route == "/cron":
            return self._send(200, {"ok": True, "line": current_cron(),
                                    "cron": read_settings().get("cron") or {}})
        if route == "/alerts":
            return self._send(200, {"ok": True, "alerts": _alerts_masked()})
        if route == "/logs":
            logsdir = os.path.join(BASE, "data", "logs")
            LE_LOG = "/var/log/letsencrypt/letsencrypt.log"
            files = []
            try:
                files = [os.path.basename(f) for f in glob.glob(os.path.join(logsdir, "*"))
                         if os.path.isfile(f)]
            except Exception:
                files = []
            # Toujours proposer les journaux connus, même s'ils n'existent pas encore
            # (letsencrypt.log = journal systeme de certbot, hors data/logs)
            for known in ("cron.log", "tls.log", "letsencrypt.log", "inspect.log", "alerts.log"):
                if known not in files:
                    files.append(known)
            files = sorted(files)
            want = (parse_qs(u.query).get("file") or [""])[0]
            want = os.path.basename(want) if want else "cron.log"
            if want == "letsencrypt.log":
                path = LE_LOG
                allowed = True
            else:
                path = os.path.join(logsdir, want)
                allowed = (os.path.realpath(os.path.dirname(path)) == os.path.realpath(logsdir))
            txt = ""
            if allowed and os.path.isfile(path):
                try:
                    # Lecture de la FIN du fichier uniquement (128 Ko), 400 dernières
                    # lignes : evite de charger un journal qui grossit toute la journee
                    # et allege le rendu live cote navigateur.
                    with io.open(path, "rb") as f:
                        f.seek(0, 2)
                        size = f.tell()
                        f.seek(max(0, size - 131072))
                        chunk = f.read().decode("utf-8", "replace")
                    txt = "\n".join(chunk.splitlines()[-400:])
                except Exception:
                    txt = ""
            return self._send(200, {"ok": True, "log": txt, "files": files, "file": want})
        if route == "/refreshstate":
            return self._send(200, {"ok": True, "running": bool(_refreshing["on"])})
        if route == "/revisitstate":
            slug = slugify((parse_qs(u.query).get("slug") or [""])[0])
            with _revisiting_lock:
                running = slug in _revisiting
            return self._send(200, {"ok": True, "running": running})
        if route == "/tls/status":
            st = read_tls_state()
            cpath = _active_paths()[0]
            info = tls_cert_info() if os.path.exists(cpath) else None
            import shutil as _sh
            return self._send(200, {"ok": True, "enabled": https_on(), "mode": st.get("mode", "none"),
                                    "domain": st.get("domain", ""), "has_cert": bool(info), "cert": info,
                                    "ct_ip": CT_IP, "certbot": bool(_sh.which("certbot"))})
        return self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        route = urlparse(self.path).path.rstrip("/")
        try:
            data = self._body()
        except Exception as e:
            return self._send(400, {"ok": False, "error": "JSON invalide: %s" % e})

        # --- routes d'authentification (non protégées) ---
        if route == "/auth/login":
            if not is_configured():
                return self._send(400, {"ok": False, "error": "aucun mot de passe défini"})
            if login_blocked():
                return self._send(429, {"ok": False, "error": "Trop de tentatives. Réessaie dans quelques minutes."})
            if not check_password(data.get("password", "")):
                login_record_fail()
                return self._send(401, {"ok": False, "error": "Mot de passe incorrect"})
            if load_auth().get("twofa"):
                if not data.get("code"):
                    return self._send(200, {"ok": False, "need_2fa": True})
                if not check_totp(data.get("code", "")):
                    login_record_fail()
                    return self._send(401, {"ok": False, "need_2fa": True, "error": "Code 2FA invalide"})
            login_reset()
            tok = new_session(TTL_REMEMBER if data.get("remember") else TTL_SESSION)
            if data.get("remember"):
                ck = "%s=%s; Path=/; HttpOnly; SameSite=Lax; Max-Age=%d" % (COOKIE, tok, TTL_REMEMBER)
            else:
                ck = "%s=%s; Path=/; HttpOnly; SameSite=Lax" % (COOKIE, tok)  # cookie de session
            return self._send(200, {"ok": True}, cookie=ck)

        if route == "/auth/logout":
            ck = "%s=; Path=/; HttpOnly; Max-Age=0" % COOKIE
            return self._send(200, {"ok": True}, cookie=ck)

        if route == "/auth/password":
            # 1er réglage autorisé sans session ; changement = session requise + mot de passe actuel
            if is_configured():
                if not self._authed():
                    return self._send(401, {"ok": False, "error": "auth"})
                if not check_password(data.get("current", "")):
                    return self._send(401, {"ok": False, "error": "Mot de passe actuel incorrect"})
            new = (data.get("new") or "").strip()
            if len(new) < 8:
                return self._send(400, {"ok": False, "error": "Mot de passe trop court (min 8 caractères)"})
            classes = sum(bool(re.search(p, new)) for p in (r"[a-z]", r"[A-Z]", r"\d", r"[^A-Za-z0-9]"))
            if len(new) < 12 and classes < 2:
                return self._send(400, {"ok": False, "error": "Mot de passe trop faible (ajoute majuscules/chiffres/symboles, ou allonge-le à 12+)"})
            set_password(new)
            tok = new_session(TTL_REMEMBER)
            ck = "%s=%s; Path=/; HttpOnly; SameSite=Lax; Max-Age=%d" % (COOKIE, tok, TTL_REMEMBER)
            return self._send(200, {"ok": True}, cookie=ck)

        if route == "/auth/2fa/init":
            if self._gate():
                return self._send(401, {"ok": False, "error": "auth"})
            try:
                import pyotp
            except Exception:
                return self._send(400, {"ok": False, "error": "pyotp non installé sur le serveur"})
            sec = pyotp.random_base32()
            PENDING_2FA[cookie_token(self)] = sec
            name = read_settings().get("name", "Autovisit")
            uri = pyotp.totp.TOTP(sec).provisioning_uri(name=name, issuer_name="Autovisit")
            return self._send(200, {"ok": True, "secret": sec, "uri": uri})

        if route == "/auth/2fa/enable":
            if self._gate():
                return self._send(401, {"ok": False, "error": "auth"})
            sec = PENDING_2FA.get(cookie_token(self))
            if not sec:
                return self._send(400, {"ok": False, "error": "Lance d'abord la configuration 2FA"})
            try:
                import pyotp
                ok = pyotp.TOTP(sec).verify((data.get("code") or "").strip(), valid_window=1)
            except Exception:
                ok = False
            if not ok:
                return self._send(401, {"ok": False, "error": "Code invalide"})
            a = load_auth(); a["totp_secret"] = sec; a["twofa"] = True; save_auth(a)
            PENDING_2FA.pop(cookie_token(self), None)
            return self._send(200, {"ok": True})

        if route == "/auth/2fa/disable":
            if self._gate():
                return self._send(401, {"ok": False, "error": "auth"})
            a = load_auth(); a["twofa"] = False; a.pop("totp_secret", None); save_auth(a)
            return self._send(200, {"ok": True})

        # --- toutes les autres routes POST sont protégées ---
        if self._gate():
            return self._send(401, {"ok": False, "error": "auth"})

        if route == "/test":
            try:
                site = data.get("site") or {}
                orig = slugify(data.get("original_slug", "") or "")
                site.setdefault("enabled", True)
                if not site.get("password"):
                    src = orig or slugify(site.get("name", ""))
                    try:
                        site["password"] = read_site(src).get("password", "")
                    except Exception:
                        pass
                slug = slugify(site.get("name", ""))
                created = not os.path.exists(site_path(slug)) if slug else True
                if not created and not os.path.exists(bak_path(slug)):
                    os.makedirs(BAK_DIR, exist_ok=True)
                    shutil.copy2(site_path(slug), bak_path(slug))
                write_site(site)
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            ok, log = test_site(site["name"])
            return self._send(200, {"ok": True, "slug": slug, "created": created,
                                    "login_ok": ok, "log": log})

        if route == "/confirm":
            try:
                slug = slugify(data.get("slug", ""))
                orig = slugify(data.get("original_slug", "") or "")
                if orig and orig != slug and os.path.exists(site_path(orig)):
                    try:
                        oldname = read_site(orig).get("name", "")
                    except Exception:
                        oldname = ""
                    os.remove(site_path(orig))
                    clear_bak(orig)
                    if oldname:
                        prune_status(oldname)
                clear_bak(slug)
                if data.get("logo"):
                    assign_logo(data.get("icon_key") or slug, data.get("logo"))
                # Pas de seconde connexion ici : le test a deja mis a jour le tableau
                # (evite de reutiliser le meme code 2FA -> faux echec).
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "slug": slug})

        if route == "/cancel":
            try:
                slug = slugify(data.get("slug", ""))
                orig = slugify(data.get("original_slug", "") or "")
                created = bool(data.get("created"))
                if slug:
                    if created and os.path.exists(site_path(slug)):
                        os.remove(site_path(slug))
                    elif os.path.exists(bak_path(slug)):
                        shutil.copy2(bak_path(slug), site_path(slug))
                    clear_bak(slug)
                if orig and orig != slug:
                    clear_bak(orig)
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True})

        if route == "/delete":
            try:
                slug = slugify(data.get("slug", ""))
                if not slug:
                    raise ValueError("slug manquant")
                name = ""
                try:
                    name = read_site(slug).get("name", "")
                except Exception:
                    pass
                if os.path.exists(site_path(slug)):
                    os.remove(site_path(slug))
                clear_bak(slug)
                if name:
                    prune_status(name)
                else:
                    regenerate_status()
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "slug": slug})

        if route == "/toggle":
            try:
                slug = slugify(data.get("slug", ""))
                d = read_site(slug)
                d["enabled"] = not d.get("enabled", True)
                fd = os.open(site_path(slug), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(d, f, ensure_ascii=False, indent=2)
                set_status_disabled(d.get("name", ""), not d["enabled"])
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "slug": slug, "enabled": d["enabled"]})

        if route == "/inspect":
            # Capture ce que le bot recoit reellement sur la page de stats (HTML ou JSON),
            # via la variable d'env AUTOVISIT_INSPECT lue par autovisit patche.
            try:
                slug = slugify(data.get("slug", ""))
                name = ""
                try:
                    name = read_site(slug).get("name", "")
                except Exception:
                    name = ""
                if not name:
                    return self._send(404, {"ok": False, "error": "site introuvable"})
                dump = os.path.join(BASE, "data", ".inspect_" + slug + ".txt")
                try:
                    os.remove(dump)
                except Exception:
                    pass
                # On sauvegarde le fichier site entier, on le modifie temporairement pour
                # forcer la capture de la bonne page, puis on restaure tout a la fin.
                sp = site_path(slug)
                orig_text = None
                try:
                    orig_text = io.open(sp, encoding="utf-8").read()
                except Exception:
                    orig_text = None
                try:
                    raw = json.loads(orig_text) if orig_text else read_site(slug)
                    # URL de la page de stats : override de la requete si present, sinon stockee.
                    if "extra_url" in data:
                        eu = _abs_url(raw, data.get("extra_url"))
                    else:
                        eu = (raw.get("extra_url") or "").strip()
                    if eu:
                        # Page de stats separee : on vide stats (sinon extract_stats se
                        # declenche d'abord sur l'accueil) et on met la sonde dans
                        # extra_stats -> le hook capture bien la page extra_url.
                        raw["extra_url"] = eu
                        raw["extra_format"] = "html"
                        raw["extra_stats"] = {"_malinois_probe": "(?!)"}
                        raw["stats"] = {}
                        raw.pop("stats_json", None)
                        json.dump(raw, open(sp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
                    elif not raw.get("stats") and not raw.get("stats_json"):
                        # Sonde sur l'accueil (aucune regex configuree).
                        if raw.get("api_json"):
                            raw["stats_json"] = {"_malinois_probe": "x"}
                        else:
                            raw["stats"] = {"_malinois_probe": "(?!)"}
                        json.dump(raw, open(sp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
                except Exception:
                    pass
                env = dict(os.environ); env["AUTOVISIT_INSPECT"] = dump
                _inspect_log("Inspection lancee : %s" % name)
                proc_err = ""
                try:
                    p = subprocess.run([sys.executable, SCRIPT, "--site", name],
                                       cwd=BASE, capture_output=True, text=True, timeout=180, env=env)
                    proc_err = (p.stderr or p.stdout or "")[-600:]
                except Exception as _e:
                    proc_err = str(_e)
                # Restauration integrale du fichier site.
                if orig_text is not None:
                    try:
                        io.open(sp, "w", encoding="utf-8").write(orig_text)
                    except Exception:
                        pass
                content = ""
                try:
                    import io as _io
                    content = _io.open(dump, encoding="utf-8", errors="replace").read()
                except Exception:
                    content = ""
                try:
                    os.remove(dump)
                except Exception:
                    pass
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            if not content:
                _inspect_log("Inspection %s : rien capture (login en echec / 2FA / anti-bot ?)%s"
                             % (name, ("\n" + proc_err) if proc_err else ""))
                return self._send(200, {"ok": False, "content": "",
                    "error": "Rien capture : le bot n'a pas atteint la page apres connexion. Cause probable : login en echec (identifiants, 2FA, ou protection anti-bot type Cloudflare). Voir l'onglet Logs pour le detail."})
            truncated = len(content) > 200000
            _inspect_log("Inspection %s : OK (%d octets captures)" % (name, len(content)))
            return self._send(200, {"ok": True, "content": content[:200000], "truncated": truncated})

        if route == "/logosync":
            try:
                done = 0
                for pair in (data.get("pairs") or []):
                    if assign_logo(pair.get("key", ""), pair.get("logo", "")):
                        done += 1
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "assigned": done})

        if route == "/favsync":
            # Recupere le favicon des sites depuis leur domaine (le conteneur a Internet)
            # et l'ecrit dans icones/<slug>.png. targets = [{slug, domain}], force = bool.
            try:
                force = bool(data.get("force"))
                os.makedirs(ICONDIR, exist_ok=True)
                results = []
                for t in (data.get("targets") or []):
                    slug = _safe_key(t.get("slug", ""))
                    dom = (t.get("domain") or "").strip().lower()
                    if not slug or not dom:
                        continue
                    dest = os.path.join(ICONDIR, slug + ".png")
                    if not force and os.path.exists(dest):
                        results.append({"slug": slug, "ok": True, "skipped": True})
                        continue
                    ok = fetch_favicon(dom, dest)
                    if ok:
                        try:
                            os.chmod(dest, 0o644)
                        except Exception:
                            pass
                    results.append({"slug": slug, "ok": bool(ok)})
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "results": results})

        if route == "/refreshall":
            # Reactualise toutes les stats en arriere-plan (revisite chaque site).
            if _refreshing["on"]:
                return self._send(200, {"ok": True, "already": True})
            _refreshing["on"] = True
            threading.Thread(target=_bg_refresh, daemon=True).start()
            return self._send(200, {"ok": True, "started": True})

        if route == "/revisit":
            # Re-visite UN site existant (rafraichit ses stats) sans modifier sa config.
            try:
                slug = slugify(data.get("slug", ""))
                name = ""
                try:
                    name = read_site(slug).get("name", "")
                except Exception:
                    name = ""
                if not name:
                    return self._send(404, {"ok": False, "error": "site introuvable"})
                # Revisite en arriere-plan : on rend la main tout de suite. Garder la
                # connexion ouverte pendant ~180 s saturerait le pool du navigateur et
                # bloquerait les requetes suivantes (ex. /sitestats).
                with _revisiting_lock:
                    already = slug in _revisiting
                    if not already:
                        _revisiting.add(slug)
                if not already:
                    threading.Thread(target=_bg_revisit, args=(slug, name), daemon=True).start()
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "started": True})

        if route == "/sitestats":
            # Edition manuelle des regex de stats d'un site (depuis l'inspection).
            try:
                slug = slugify(data.get("slug", ""))
                d = read_site(slug)
                es = data.get("extra_stats")
                if "extra_url" in data:
                    eu = _abs_url(d, data.get("extra_url"))
                    if eu:
                        # Stats sur une page separee : regex dans extra_stats, accueil vide.
                        d["extra_url"] = eu
                        d["extra_format"] = "html"
                        if isinstance(es, dict):
                            d["extra_stats"] = es
                        d["stats"] = {}
                        d.pop("stats_json", None)
                    else:
                        # URL videe -> retour aux stats de l'accueil.
                        d.pop("extra_url", None)
                        d.pop("extra_stats", None)
                        d.pop("extra_format", None)
                elif isinstance(es, dict):
                    d["extra_stats"] = es
                st = data.get("stats")
                if st is not None:
                    if not isinstance(st, dict):
                        return self._send(400, {"ok": False, "error": "stats: objet JSON attendu"})
                    d["stats"] = st
                sj = data.get("stats_json")
                if sj is not None and isinstance(sj, dict):
                    d["stats_json"] = sj
                # Sauvegarde de securite : archive la config PRECEDENTE (telle que
                # sur disque) avant ecrasement -> data/.statsbak/<slug>.json.
                # Restauration manuelle possible depuis l'hote si besoin.
                try:
                    bakdir = os.path.join(BASE, "data", ".statsbak"); os.makedirs(bakdir, exist_ok=True)
                    shutil.copy2(site_path(slug), os.path.join(bakdir, slug + ".json"))
                except Exception:
                    pass
                # Ecriture STATS-ONLY : on reecrit le MEME fichier que celui lu
                # (site_path(slug)), SANS passer par write_site -> pas de
                # re-validation auth (post_url/password/cookies) qui pourrait lever
                # une erreur et bloquer l'enregistrement de simples regex, et aucun
                # risque de re-slugification ecrivant dans un autre fichier.
                p = site_path(slug)
                fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(d, f, ensure_ascii=False, indent=2)
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "slug": slug, "keys": sorted((d.get("stats") or {}).keys())})

        if route == "/siterestore":
            # Restaure la config de stats depuis la derniere sauvegarde
            # (data/.statsbak/<slug>.json), ecrite avant le dernier enregistrement.
            try:
                slug = slugify(data.get("slug", ""))
                bakf = os.path.join(BASE, "data", ".statsbak", slug + ".json")
                if not os.path.exists(bakf):
                    return self._send(404, {"ok": False, "error": "Aucune sauvegarde pour ce site (enregistre au moins une fois avant)."})
                bak = json.load(open(bakf, encoding="utf-8"))
                d = read_site(slug)
                # On ne restaure QUE les champs de stats (pas l'auth / mdp).
                for k in ("stats", "stats_json", "extra_stats", "extra_url", "extra_format"):
                    d.pop(k, None)
                for k in ("stats", "stats_json", "extra_stats", "extra_url", "extra_format"):
                    if k in bak:
                        d[k] = bak[k]
                p = site_path(slug)
                fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(d, f, ensure_ascii=False, indent=2)
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "slug": slug, "keys": sorted((d.get("stats") or {}).keys())})

        if route == "/settings":
            try:
                s = write_settings(data)
                # Ne touche au cron via cron_hours QUE si aucune planification structurée n'existe
                if "cron_hours" in data and data["cron_hours"] and not read_settings().get("cron"):
                    update_cron(data["cron_hours"])
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "settings": s})

        if route == "/cron":
            try:
                opts = {
                    "minute": data.get("minute", 0),
                    "hour": data.get("hour", 6),
                    "mode": data.get("mode", "interval"),
                    "interval_days": data.get("interval_days", 1),
                    "weekdays": data.get("weekdays", []),
                }
                ok = set_cron(opts)
                if not ok:
                    return self._send(400, {"ok": False, "error": "Écriture du crontab impossible."})
                write_settings({"cron": opts})
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "line": current_cron(), "cron": opts})

        if route == "/alerts":
            try:
                _update_alerts(data)
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True, "alerts": _alerts_masked()})

        if route == "/alerts/test":
            try:
                if data.get("save"):
                    _update_alerts(data)
                ch = data.get("channel")
                if ch:
                    ok, err = test_channel(ch)
                    label = {"email": "E-mail", "telegram": "Telegram", "webhook": "Webhook"}.get(ch, ch)
                    return self._send(200, {"ok": ok,
                        "detail": "%s : %s" % (label, "OK" if ok else ("échec — " + err))})
                results = send_alert("Malinois : test de notification",
                                     "Ceci est un message de test envoye depuis le dashboard Malinois.")
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            if not results:
                return self._send(200, {"ok": False, "error": "Aucun canal actif/complet a tester."})
            ok = all(r[1] for r in results)
            detail = "; ".join("%s : %s" % (r[0], "OK" if r[1] else ("échec — " + r[2])) for r in results)
            return self._send(200, {"ok": ok, "detail": detail})

        if route == "/favicon":
            try:
                if data.get("delete"):
                    delete_favicon()
                    write_settings({"favicon": False})
                    return self._send(200, {"ok": True, "deleted": True})
                if not data.get("data"):
                    raise ValueError("image manquante")
                save_favicon(data["data"])
                write_settings({"favicon": True})
            except Exception as e:
                return self._send(400, {"ok": False, "error": str(e)})
            return self._send(200, {"ok": True})

        if route == "/tls/selfsigned":
            ok, msg = gen_selfsigned({
                "cn": data.get("cn") or "",
                "san": data.get("san") or data.get("hosts") or [CT_IP],
                "org": data.get("org") or "",
                "ou": data.get("ou") or "",
                "country": data.get("country") or "",
                "days": data.get("days") or 825,
            })
            if not ok:
                _tls_log("Cert auto-signe ECHEC : " + str(msg))
                return self._send(400, {"ok": False, "error": msg})
            st = read_tls_state(); st["mode"] = "selfsigned"; st.pop("domain", None); write_tls_state(st)
            _tls_log("Cert auto-signe genere (CN=%s)" % (data.get("cn") or CT_IP))
            return self._send(200, {"ok": True, "cert": tls_cert_info()})

        if route == "/tls/import":
            ok, msg = install_pair(data.get("cert", "") or "", data.get("key", "") or "")
            if not ok:
                _tls_log("Import de cert ECHEC : " + str(msg))
                return self._send(400, {"ok": False, "error": msg})
            st = read_tls_state(); st["mode"] = "import"; st.pop("domain", None); write_tls_state(st)
            _tls_log("Cert importe avec succes")
            return self._send(200, {"ok": True, "cert": tls_cert_info()})

        if route == "/tls/certbot":
            dom = re.sub(r"[^a-zA-Z0-9.-]", "", (data.get("domain") or "").strip())
            ok, msg = run_certbot(dom, data.get("email", ""), bool(data.get("staging")))
            if not ok:
                return self._send(400, {"ok": False, "error": msg})
            st = read_tls_state(); st["mode"] = "certbot"; st["domain"] = dom; write_tls_state(st)
            ok2, msg2 = apply_nginx(True)
            if not ok2:
                return self._send(400, {"ok": False, "error": "Certificat obtenu, mais nginx : " + msg2})
            st = read_tls_state(); st["enabled"] = True; write_tls_state(st)
            return self._send(200, {"ok": True, "cert": tls_cert_info(), "domain": dom})

        if route == "/tls/enable":
            if not (os.path.exists(TLS_CERT) and os.path.exists(TLS_KEY)):
                return self._send(400, {"ok": False, "error": "Aucun certificat : genere ou importe d'abord."})
            ok, msg = apply_nginx(True)
            if not ok:
                _tls_log("Activation HTTPS ECHEC (nginx) : " + str(msg))
                return self._send(400, {"ok": False, "error": msg})
            st = read_tls_state(); st["enabled"] = True; write_tls_state(st)
            _tls_log("HTTPS active")
            return self._send(200, {"ok": True})

        if route == "/tls/disable":
            ok, msg = apply_nginx(False)
            if not ok:
                _tls_log("Desactivation HTTPS ECHEC (nginx) : " + str(msg))
                return self._send(400, {"ok": False, "error": msg})
            st = read_tls_state(); st["enabled"] = False; write_tls_state(st)
            _tls_log("HTTPS desactive")
            return self._send(200, {"ok": True})

        return self._send(404, {"ok": False, "error": "not found"})


if __name__ == "__main__":
    if "--write-nginx" in sys.argv:
        https = write_nginx_from_state()
        print("nginx config ecrite (%s) -> %s" % ("HTTPS" if https else "HTTP", NGINX_SITE), flush=True)
        sys.exit(0)
    print("web-api v5 sur http://%s:%d" % (HOST, PORT), flush=True)
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()
PYEOF
pct push $CT /tmp/web-api.py /opt/tracker-autovisit/web-api.py --perms 700; rm /tmp/web-api.py

echo "[4b/8] Patches autovisit.py (2FA session + inspection)…"
cat > /tmp/malinois_patch_2fa.py << 'P2FAEOF'
#!/usr/bin/env python3
# MALINOIS : patches additifs pour autovisit.py
#   1) 2FA a etape separee dans le login hybride du mode session/Cloudflare
#   2) "inspect" : extract_stats / extract_stats_json deversent ce qu'ils recoivent
#      dans le fichier pointe par $AUTOVISIT_INSPECT (pour le bouton Inspecter).
# Idempotent (un marqueur par patch), sauvegarde unique, restauration si la
# compilation echoue.
import io, os, sys, py_compile

P = sys.argv[1] if len(sys.argv) > 1 else "/opt/tracker-autovisit/autovisit.py"
try:
    src = io.open(P, encoding="utf-8").read()
except Exception as e:
    print("MALINOIS patch : lecture impossible (%s) -- ignore" % e); sys.exit(0)

orig = src
applied = []

# ---- Patch 1 : 2FA session/Cloudflare ----
if "MALINOIS-2FA-SESSION" not in src:
    anchor = '            log.info("[" + name + "] Login effectue (HTTP " + str(r_post.status_code) + ")")'
    if anchor in src:
        block = "\n".join([
            "",
            "            # MALINOIS-2FA-SESSION : etape 2FA separee derriere Cloudflare/cookies",
            '            _t_url = site.get("totp_url"); _t_sec = site.get("totp_secret")',
            "            if _t_url and _t_sec:",
            '                _u = (getattr(r_post, "url", "") or "").lower()',
            '                _need = ("2fa" in _u) or ("two-factor" in _u) or ("two_factor" in _u) or ("/otp" in _u)',
            "                if not _need:",
            "                    try:",
            '                        _need = (\'name="\' + site.get("totp_field", "code") + \'"\') in r_post.text',
            "                    except Exception:",
            "                        _need = False",
            "                if _need:",
            "                    try:",
            "                        import pyotp as _po",
            "                        from urllib.parse import urljoin as _uj",
            "                        _code = _po.TOTP(_t_sec).now()",
            '                        _tf = site.get("totp_field", "code")',
            '                        _turl = _t_url if _t_url.startswith("http") else _uj(login_url, _t_url)',
            "                        _tp = {_tf: _code}",
            '                        _cf2 = site.get("csrf_field")',
            "                        _ct = extract_csrf(r_post.text, _cf2)",
            "                        if _ct:",
            '                            _tp[_cf2 if _cf2 else "_token"] = _ct',
            "                        time.sleep(random.uniform(0.4, 1.0))",
            "                        r_post = session.post(_turl, data=_tp, timeout=timeout, allow_redirects=True)",
            '                        log.info("[" + name + "] 2FA session : code envoye " + _code)',
            "                    except Exception as _e:",
            '                        log.error("[" + name + "] erreur 2FA session : " + str(_e))',
        ])
        src = src.replace(anchor, anchor + block, 1)
        applied.append("2FA-session")
    else:
        print("MALINOIS patch : ancre 2FA introuvable -- 2FA session ignore")

# ---- Patch 2a : inspect HTML (extract_stats) ----
if "MALINOIS-INSPECT-HTML" not in src:
    a = "def extract_stats(html, patterns):"
    if a in src:
        block = "\n".join([
            "",
            "    # MALINOIS-INSPECT-HTML",
            "    import os as _os",
            '    _insf = _os.environ.get("AUTOVISIT_INSPECT")',
            "    if _insf and not _os.path.exists(_insf):",
            "        try:",
            '            open(_insf, "w", encoding="utf-8").write(html if isinstance(html, str) else str(html))',
            "        except Exception:",
            "            pass",
        ])
        src = src.replace(a, a + block, 1)
        applied.append("inspect-html")
    else:
        print("MALINOIS patch : ancre extract_stats introuvable -- inspect HTML ignore")

# ---- Patch 2b : inspect JSON (extract_stats_json) ----
if "MALINOIS-INSPECT-JSON" not in src:
    a = "def extract_stats_json(data, fields):"
    if a in src:
        block = "\n".join([
            "",
            "    # MALINOIS-INSPECT-JSON",
            "    import os as _os, json as _json",
            '    _insf = _os.environ.get("AUTOVISIT_INSPECT")',
            "    if _insf and not _os.path.exists(_insf):",
            "        try:",
            '            open(_insf, "w", encoding="utf-8").write(_json.dumps(data, ensure_ascii=False, indent=2) if not isinstance(data, str) else data)',
            "        except Exception:",
            "            pass",
        ])
        src = src.replace(a, a + block, 1)
        applied.append("inspect-json")
    else:
        print("MALINOIS patch : ancre extract_stats_json introuvable -- inspect JSON ignore")


# === Patches backend MALINOIS v78 (additifs, idempotents, best-effort) ===
# Note : sur un conteneur deja patche a chaud (session v77->v78), le contenu est
# deja present ; l'ancre "avant patch" ne matchera pas et le patch sera ignore
# proprement (le code fonctionnel reste en place). Sur un autovisit.py vierge,
# l'ancre matche et le patch s'applique.

# ---- Patch 3 : apijson dans visit_site_session (TR4KER) ----
if "Stats JSON (api_json) -- lit /api/auth/me" not in src:
    a = ('        # Stats\n'
         '        site_stats = site.get("stats", {})\n'
         '        stats = {}\n'
         '        if site_stats:\n'
         '            stats = extract_stats(rv.text, site_stats)')
    b = ('        # Stats\n'
         '        site_stats = site.get("stats", {})\n'
         '        stats = {}\n'
         '        # MALINOIS-APIJSON-SESSION : Stats JSON (api_json) -- lit /api/auth/me etc.\n'
         '        if site.get("api_json") and site.get("stats_json"):\n'
         '            try:\n'
         '                stats = extract_stats_json(rv.json(), site["stats_json"])\n'
         '            except Exception as _je:\n'
         '                log.error("[" + name + "] JSON stats KO : " + str(_je))\n'
         '        elif site_stats:\n'
         '            stats = extract_stats(rv.text, site_stats)')
    if a in src:
        src = src.replace(a, b, 1); applied.append("apijson-session")
    else:
        print("MALINOIS patch : ancre apijson-session introuvable (deja applique ?) -- ignore")

# ---- Patch 4 : priorite cookies fichier > FlareSolverr (Nexum) ----
if "_cf_filtered" not in src:
    a = "        cookies_data = list(cookies_data) + list(cf_cookies)"
    b = ('        # MALINOIS-CF-COOKIE-PRIORITY : le fichier prime sur FlareSolverr\n'
         '        _file_names = {c.get("name") for c in cookies_data}\n'
         '        _cf_filtered = [c for c in cf_cookies if c.get("name") not in _file_names]\n'
         '        cookies_data = list(cookies_data) + list(_cf_filtered)')
    if a in src:
        src = src.replace(a, b, 1); applied.append("cf-cookie-priority")
    else:
        print("MALINOIS patch : ancre cf-cookie-priority introuvable (deja applique ?) -- ignore")

# ---- Patch 5 : flux MFA -> stats JSON (C411) ----
# Remplace le bloc complet : condition + GET + stats_json + verif finale tolerante.
if 'Connexion reussie apres MFA JSON (stats lues)' not in src:
    a = ('                            if custom_keywords and verify_url:\n'
         '                                rv = session.get(verify_url, timeout=timeout, headers={"Accept-Encoding": "identity"} if use_curl else {})\n'
         '                                matched = next((kw for kw in custom_keywords if kw.lower() in rv.text.lower()), None)\n'
         '                                if matched:\n'
         '                                    msg = "OK [" + name + "] Connexion reussie apres MFA JSON (mot-cle : " + matched + ")"\n'
         '                                    log.info(msg)\n'
         '                                    return True, msg, None\n'
         '                                else:\n'
         '                                    msg = "ECHEC [" + name + "] MFA JSON ok mais mot-cle introuvable sur " + verify_url\n'
         '                                    log.warning(msg)\n'
         '                                    return False, msg, None')
    if a in src:
        b = ('                            # MALINOIS-MFA-STATSJSON : lit stats_json dans le flux MFA\n'
             '                            if verify_url and (custom_keywords or site.get("stats_json") or site.get("extra_stats")):\n'
             '                                _vh = {"Accept": "application/json"}\n'
             '                                if use_curl: _vh["Accept-Encoding"] = "identity"\n'
             '                                rv = session.get(verify_url, timeout=timeout, headers=_vh)\n'
             '                                site_stats = site.get("stats", {})\n'
             '                                stats = {}\n'
             '                                stats_json = site.get("stats_json", {})\n'
             '                                if stats_json:\n'
             '                                    try:\n'
             '                                        stats = extract_stats_json(rv.json(), stats_json)\n'
             '                                    except Exception as _je:\n'
             '                                        log.warning("[" + name + "] Erreur parsing stats JSON (MFA) : " + str(_je))\n'
             '                                if site_stats:\n'
             '                                    stats.update(extract_stats(rv.text, site_stats))\n'
             '                                extra_url = site.get("extra_url")\n'
             '                                extra_fields = site.get("extra_stats")\n'
             '                                if extra_url and extra_fields:\n'
             '                                    extra = fetch_extra_stats(session, extra_url, extra_fields, name, timeout, site.get("extra_format", "json"))\n'
             '                                    if extra:\n'
             '                                        stats.update(extra)\n'
             '                                if stats:\n'
             '                                    log.info("[" + name + "] Stats -- " + format_stats(stats, site))\n'
             '                                if custom_keywords:\n'
             '                                    matched = next((kw for kw in custom_keywords if kw.lower() in rv.text.lower()), None)\n'
             '                                    if matched:\n'
             '                                        msg = "OK [" + name + "] Connexion reussie apres MFA JSON (mot-cle : " + matched + ")"\n'
             '                                        log.info(msg)\n'
             '                                        return True, msg, None\n'
             '                                    else:\n'
             '                                        msg = "ECHEC [" + name + "] MFA JSON ok mais mot-cle introuvable sur " + verify_url\n'
             '                                        log.warning(msg)\n'
             '                                        return False, msg, None\n'
             '                                msg = "OK [" + name + "] Connexion reussie apres MFA JSON (stats lues)"\n'
             '                                log.info(msg)\n'
             '                                return True, msg, None')
        src = src.replace(a, b, 1); applied.append("mfa-statsjson")
    else:
        print("MALINOIS patch : ancre mfa-statsjson introuvable (deja applique ?) -- ignore")

# ---- Patch 6 : mode cookie Playwright + User-Agent (Nostradamus / Anubis + LiveView) ----
if "malinois-cookie-playwright" not in src:
    anchor_np = '            page = browser.new_page()\n'
    if anchor_np in src:
        repl6 = (
            '            # malinois-cookie-playwright : contexte avec UA + reutilisation de session (cookies)\n'
            '            _ua = site.get("user_agent")\n'
            '            _ctx = browser.new_context(user_agent=_ua) if _ua else browser.new_context()\n'
            '            page = _ctx.new_page()\n'
            '            _scf = site.get("playwright_cookies_file")\n'
            '            _cookie_mode = bool(_scf)\n'
            '            if _cookie_mode:\n'
            '                try:\n'
            '                    import json as _json\n'
            '                    try:\n'
            '                        from urllib.parse import urlparse as _urlparse\n'
            '                        _host = _urlparse(site["url"]).hostname\n'
            '                    except Exception:\n'
            '                        _host = site["url"].split("/")[2]\n'
            '                    _raw = _json.load(open(_scf, encoding="utf-8"))\n'
            '                    _cks = []\n'
            '                    for _c in _raw:\n'
            '                        if not _c.get("name"):\n'
            '                            continue\n'
            '                        _ck = {"name": _c["name"], "value": _c.get("value", ""),\n'
            '                               "domain": _c.get("domain") or _host, "path": _c.get("path") or "/"}\n'
            '                        if _c.get("secure") is not None:\n'
            '                            _ck["secure"] = bool(_c["secure"])\n'
            '                        if _c.get("httpOnly") is not None:\n'
            '                            _ck["httpOnly"] = bool(_c["httpOnly"])\n'
            '                        _cks.append(_ck)\n'
            '                    _ctx.add_cookies(_cks)\n'
            '                    log.info("[" + name + "] " + str(len(_cks)) + " cookie(s) injecte(s) (session + Anubis) -- login saute (mode cookie)")\n'
            '                except Exception as _e:\n'
            '                    log.error("[" + name + "] echec injection cookies : " + str(_e))\n'
            '                    _cookie_mode = False\n'
        )
        src = src.replace(anchor_np, repl6, 1)
        _sa6 = '            log.info("[" + name + "] Chargement de la page de login (Playwright) : " + site["url"])'
        _ea6 = '            log.info("[" + name + "] URL apres 2FA : " + page.url)'
        _i6 = src.find(_sa6); _j6 = src.find(_ea6)
        if _i6 != -1 and _j6 != -1:
            _j6 += len(_ea6)
            _blk6 = src[_i6:_j6]
            _wrp6 = '            if not _cookie_mode:\n' + "\n".join(
                (("    " + ln) if ln.strip() else ln) for ln in _blk6.split("\n"))
            src = src[:_i6] + _wrp6 + src[_j6:]
            applied.append("cookie-playwright")
        else:
            print("MALINOIS patch : ancres login/2FA introuvables -- cookie-playwright ignore")
    else:
        print("MALINOIS patch : ancre new_page introuvable -- cookie-playwright ignore")

if not applied:
    print("MALINOIS patch : rien a faire (deja applique)."); sys.exit(0)

bak = P + ".malinois.bak"
if not os.path.exists(bak):
    io.open(bak, "w", encoding="utf-8").write(orig)

io.open(P, "w", encoding="utf-8").write(src)
try:
    py_compile.compile(P, doraise=True)
    print("MALINOIS patch : applique -> " + ", ".join(applied))
except Exception as e:
    io.open(P, "w", encoding="utf-8").write(orig)
    print("MALINOIS patch : ECHEC compilation, restaure (%s)." % e); sys.exit(1)
P2FAEOF
pct push $CT /tmp/malinois_patch_2fa.py /tmp/malinois_patch_2fa.py >/dev/null; rm /tmp/malinois_patch_2fa.py
pct exec $CT -- python3 /tmp/malinois_patch_2fa.py /opt/tracker-autovisit/autovisit.py || true
pct exec $CT -- rm -f /tmp/malinois_patch_2fa.py

echo "[4b/8] Correction des regex de stats (sites existants)…"
cat > /tmp/malinois_patch_stats.py << 'STATEOF'
# MALINOIS : corrige les regex de stats des sites deja deployes (sites.d),
# d'apres les pages reellement recues par le bot. Fusionne sans toucher au reste (mdp, etc.).
import json, os, glob
SITES = "/opt/tracker-autovisit/data/sites.d"
PATCH = {}
# PATCH vide en v78.1 : abn.lol, gemini, theoldschool, karagarga, wihd,
# phoenixproject, nostradamus ont tous des sites.d valides et PERSISTANTS
# dans le conteneur. Les regex codees ici risquaient d'ecraser tes versions
# validees (ex: GEMINI {0,400} -> {0,260}, ABN sans "invitations"...).
# Le patcher ne reecrit donc plus AUCUNE regex. Tes configs font foi.
# Sites refondus dont les stats sont sur une page profil (via extra_url) :
# EXTRA vide en v78 : nexum/tr4ker/c411 ont des configs sites.d validees et
# PERSISTANTES dans le conteneur (apijson, cookie+FlareSolverr, login vide...).
# Les reimposer ici les ECRASERAIT (tr4ker _force /mon-compte/stats ; c411
# /user/profile qui ecrase le JSON par des N/A ; nexum {u} vide -> 404).
# On les laisse donc intacts. Cf. session v77->v78.
EXTRA = {}
# Sites UNIT3D dont les stats se lisent sur l'ACCUEIL (barre de ratio top-nav).
# On ecrit dans "stats" et on PURGE toute config de page profil (extra_url).
HOMEPAGE = {}
# HOMEPAGE vide en v78.1 : idem, gemini/theoldschool conservent leurs sites.d.
changed = 0
for f in glob.glob(os.path.join(SITES, "*.json")):
    try:
        d = json.load(open(f, encoding="utf-8"))
    except Exception:
        continue
    hay = ((d.get("url") or "") + " " + (d.get("verify_url") or "") + " " + (d.get("login_url") or "") + " " + (d.get("extra_url") or "")).lower()
    for dom, keys in PATCH.items():
        if dom in hay:
            st = d.get("stats")
            if not isinstance(st, dict):
                st = {}
            for k, v in keys.items():
                if v is None:
                    st.pop(k, None)        # None = supprimer la regex devenue obsolete
                else:
                    st[k] = v
            d["stats"] = st
            json.dump(d, open(f, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
            changed += 1
            print("  stats corrigees : %s (%s)" % (os.path.basename(f), dom))
            break
    for dom, keys in EXTRA.items():
        if dom in hay:
            keys = dict(keys); url_tpl = keys.pop("_url", None); force = keys.pop("_force", False)
            d["extra_stats"] = dict(keys)          # remplace entierement (purge l'ancien)
            d["extra_format"] = "html"
            if url_tpl and (force or not d.get("extra_url")):
                d["extra_url"] = url_tpl.replace("{u}", d.get("username") or "")
            d["stats"] = {}
            json.dump(d, open(f, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
            changed += 1
            print("  extra_stats corrigees : %s (%s)" % (os.path.basename(f), dom))
            break
    for dom, keys in HOMEPAGE.items():
        if dom in hay:
            d["stats"] = dict(keys)                # stats lues sur l'accueil (barre de ratio)
            d.pop("extra_url", None)               # purge la page profil (404)
            d.pop("extra_stats", None)
            d.pop("extra_format", None)
            d.pop("stats_json", None)
            json.dump(d, open(f, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
            changed += 1
            print("  stats accueil (barre de ratio) : %s (%s)" % (os.path.basename(f), dom))
            break
print("  fichiers sites mis a jour : %d" % changed)
STATEOF
pct push $CT /tmp/malinois_patch_stats.py /tmp/malinois_patch_stats.py >/dev/null; rm /tmp/malinois_patch_stats.py
pct exec $CT -- python3 /tmp/malinois_patch_stats.py || true
pct exec $CT -- rm -f /tmp/malinois_patch_stats.py

echo "[5/8] Unite systemd…"
cat > /tmp/autovisit-web.service << UNITEOF
[Unit]
Description=tracker-autovisit web API (gestion des sites + parametres + auth)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/tracker-autovisit/web-api.py
Environment=MAL_CT_IP=${CT_IP}
Environment=MAL_LAN_CIDR=${LAN_CIDR}
Environment=MAL_WEBROOT=/var/www/autovisit
Restart=always
User=root

[Install]
WantedBy=multi-user.target
UNITEOF
pct push $CT /tmp/autovisit-web.service /etc/systemd/system/autovisit-web.service; rm /tmp/autovisit-web.service
# Nettoie tout override de sandbox residuel (drop-in de la trappe de secours) qui pourrait persister
pct exec $CT -- rm -rf /etc/systemd/system/autovisit-web.service.d
pct exec $CT -- systemctl daemon-reload
pct exec $CT -- systemctl enable autovisit-web >/dev/null 2>&1 || true
pct exec $CT -- systemctl restart autovisit-web

echo "[6/8] Overlay addsite.js…"
cat > /tmp/addsite.js << 'JSEOF'
/* addsite.js v5 — tracker-autovisit dashboard.
   Toolbar : Actualiser / Thème clair-sombre / Paramètres. FAB + (ajouter).
   Paramètres : nom, URL, favicon (upload->auto), couleur d'accent, thème, cron 24/48/72h.
   Modale d'ajout : auto-complétion intuitive depuis la base de 32 trackers ; sinon saisie manuelle.
   Actions par ligne (activer/désactiver, éditer, supprimer) + flux Tester -> Ajouter/Échec. */
(function () {
  "use strict";

  var TRACKERS = /*TRACKERS_DB*/[{"id": "abnormal", "n": "ABNormal", "d": "abn.lol", "p": "aspnet", "lp": "/Home/Login", "vp": "/", "to": false, "uf": "Username", "pf": "Password", "csrf": "__RequestVerificationToken", "hid": 1, "ef": {"RememberMe": "false"}, "lg": 1, "s": {"upload": "Seeds\\\">Up\\s*:\\s*<span[^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": "Seeds\\\">Down\\s*:\\s*<span[^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "ratio": ">Ratio\\s*:\\s*<span[^>]*>\\s*([\\d.,]+)", "bonus": "ChocosShop[\\s\\S]{0,80}?<span[^>]*>\\s*([\\d\\s.,]+)", "invitations": "Invitations[\\s\\S]{0,80}?(\\d[\\d\\s.,]*\\d|\\d)", "class": "class=\\\"userclass_([A-Za-z0-9]+)"}}, {"id": "bitporn", "n": "BitPorn", "d": "bitporn.eu", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "au": "cookie", "lg": 1, "s": {"upload": "ratio-bar__uploaded[\\s\\S]{0,260}?(\\d[\\d.,]*(?:&nbsp;|&#160;|&#xa0;|[\\s\\u00a0])*[KMGTPE]i?B)", "download": "ratio-bar__downloaded[\\s\\S]{0,260}?(\\d[\\d.,]*(?:&nbsp;|&#160;|&#xa0;|[\\s\\u00a0])*[KMGTPE]i?B)", "bufferBytes": "ratio-bar__buffer[\\s\\S]{0,260}?(\\d[\\d.,]*(?:&nbsp;|&#160;|&#xa0;|[\\s\\u00a0])*[KMGTPE]i?B)"}}, {"id": "brokenstones", "n": "BrokenStones", "d": "brokenstones.is", "p": "gazelle", "lp": "/login.php", "vp": "/", "to": false, "hid": 1, "ef": {"keeplogged": "1"}, "s": {"upload": "stats_seeding[\\s\\S]{0,200}?<span[^>]*>\\s*([\\d.]+ (?:TB|GB|MB|KB))\\s*</span>", "download": "stats_leeching[\\s\\S]{0,200}?<span[^>]*>\\s*([\\d.]+ (?:TB|GB|MB|KB))\\s*</span>", "ratio": "stats_ratio[\\s\\S]{0,200}?<span[^>]*>\\s*([\\d.]+)\\s*</span>", "tokens": "fl_tokens[\\s\\S]{0,200}?<a[^>]*>\\s*(\\d+)\\s*</a>"}, "lg": 1}, {"id": "c411", "n": "C411", "d": "c411.org", "p": "apijson", "lp": "/login", "vp": "/api/auth/me", "to": true, "pp": "/api/auth/login", "pv": ["/api/settings/public"], "mu": "/api/auth/mfa/totp", "tf": "code", "sf": "authenticated", "mp": {"u": "/api/messages/unread-count", "f": "total"}, "lg": 1, "sj": {"download": "user.downloaded", "upload": "user.uploaded", "ratio": "user.ratio", "class": "user.badge.label"}}, {"id": "crazyspirits", "n": "CrazySpirits", "d": "crazyspirits.com", "p": "form", "lp": "/account-login.php", "vp": "/", "to": false, "br": 1, "au": "cookie", "lg": 1, "s": {"download": "/dl\\.png\"[\\s\\S]{0,160}?<font[^>]*>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "upload": "/up\\.png\"[\\s\\S]{0,160}?<font[^>]*>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "bonus": "Crazy Bonus\\s*<a[^>]*>\\s*([\\d\\s.,]+)"}}, {"id": "empornium", "n": "Empornium", "d": "www.empornium.sx", "p": "gazelle", "lp": "/login", "vp": "/", "to": false, "hid": 1, "ef": {"keeploggedin": "1"}, "lg": 1, "s": {"bonus": ">Credits</a>:\\s*</td>[\\s\\S]{0,140}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+)", "upload": ">Up</a>:\\s*</td>[\\s\\S]{0,160}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": ">Down</a>:\\s*</td>[\\s\\S]{0,160}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "ratio": ">Ratio</a>:\\s*</td>[\\s\\S]{0,220}?<span[^>]*class=['\"]r\\d+['\"][^>]*>\\s*(\\d[\\d\\s.,]*)"}}, {"id": "exoticaz", "n": "ExoticaZ", "d": "exoticaz.to", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "ef": {"remember": "on"}, "br": 1, "au": "cookie", "s": {"upload": "fa-arrow-up[\\s\\S]{0,40}?</i>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "download": "fa-arrow-down[\\s\\S]{0,40}?</i>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "ratio": "fa-signal[\\s\\S]{0,40}?</i>\\s*([\\d.,]+)", "bufferBytes": "fa-database[\\s\\S]{0,40}?</i>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "seeding": "Seeding:</a>\\s*(\\d+)", "bonus": "Bonus:</a>\\s*([\\d.,]+)"}, "lg": 1}, {"id": "g3mini", "n": "G3MINI", "d": "gemini-tracker.org", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "csrf": "_token", "hid": 1, "lg": 1, "s": {"upload": "ratio-bar__uploaded[\\s\\S]{0,400}?(\\d[\\d.,]*(?:&nbsp;|[\\s\\u00a0])*[KMGTPE]i?B)", "download": "ratio-bar__downloaded[\\s\\S]{0,400}?(\\d[\\d.,]*(?:&nbsp;|[\\s\\u00a0])*[KMGTPE]i?B)", "ratio": "ratio-bar__ratio[\\s\\S]{0,400}?</i>\\s*([\\d.,]+)", "seeding": "ratio-bar__seeding[\\s\\S]{0,400}?</i>\\s*(\\d+)", "bonus": "ratio-bar__points[\\s\\S]{0,400}?</i>\\s*([\\d\\s.,\\u00a0]+?)\\s*</a>", "bufferBytes": "ratio-bar__buffer[\\s\\S]{0,400}?(\\d[\\d.,]*(?:&nbsp;|[\\s\\u00a0])*[KMGTPE]i?B)"}, "au": "cookie", "pp": "/api/auth/login"}, {"id": "generationfree", "n": "Generation-Free", "d": "generation-free.org", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "csrf": "_token", "hid": 1, "lg": 1}, {"id": "happyfappy", "n": "HappyFappy", "d": "www.happyfappy.net", "p": "gazelle", "lp": "/login", "vp": "/", "to": false, "hid": 1, "ef": {"keeploggedin": "1"}, "lg": 1, "s": {"bonus": ">Credits</a>:\\s*</td>[\\s\\S]{0,140}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+)", "upload": ">Up</a>:\\s*</td>[\\s\\S]{0,160}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": ">Down</a>:\\s*</td>[\\s\\S]{0,160}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "ratio": ">Ratio</a>:\\s*</td>[\\s\\S]{0,220}?<span[^>]*class=['\"]r\\d+['\"][^>]*>\\s*(\\d[\\d\\s.,]*)"}}, {"id": "hdforever", "n": "HD-Forever", "d": "hdf.world", "p": "gazelle", "lp": "/login.php", "vp": "/", "to": true, "hid": 1, "ef": {"login": "Se connecter", "keeplogged": "1"}, "mu": "/login.php?act=otp", "tf": "otp_code", "lg": 1, "s": {"upload": "class=\\\"stat tooltip up\\\" title=\\\"([^\\\"]+)\\\"", "download": "class=\\\"stat tooltip dl\\\" title=\\\"([^\\\"]+)\\\"", "ratio": "stats_ratio[^>]*>Ratio[^<]*<[^>]*><span class=\\\"tooltip r\\d+\\\" title=\\\"([^\\\"]+)\\\"", "bonus": "action=rate[^>]+>([\\d,]+)<", "jetons FL": ">Jetons FL</a>[\\s\\S]{0,200}?>\\s*(\\d[\\d\\s.,]*\\d|\\d)\\s*</a>", "unreadMessages": "data-notification-type=['\\\"]Inbox['\\\"][^>]*>[^<]*?(\\d+|\\bun) nouveau", "class": "class=\\\"userclass\\\">\\(?([^)<]+)"}}, {"id": "hdonly", "n": "HD-Only", "d": "hd-only.org", "p": "gazelle", "lp": "/login.php", "vp": "/", "to": false, "hid": 1, "ef": {"keeplogged": "1", "login": "Se connecter"}, "lg": 1, "s": {"upload": "Envoy[\\s\\S]{0,160}?([\\d\\s.,]+\\s*[KMGTPE]?i?B)", "download": "Re[\\s\\S]{0,160}?([\\d\\s.,]+\\s*[KMGTPE]?i?B)", "unreadMessages": "data-notification-type=['\"]Inbox['\"][^>]*>[^<]*?(\\d+|\\bun) nouveau", "class": "id=\"pseudo\"[\\s\\S]*?\\(?:([^)]+)\\)"}}, {"id": "iptorrents", "n": "IPTorrents", "d": "www.iptorrents.com", "p": "form", "lp": "/do-login.php", "vp": "/", "to": false, "br": 1, "s": {"upload": ">Uploaded</div>\\s*<i[^>]*></i>\\s*([\\d.,]+\\s*(?:[KMGTPE]i?B|B))", "download": ">Downloaded</div>\\s*<i[^>]*></i>\\s*([\\d.,]+\\s*(?:[KMGTPE]i?B|B))", "ratio": "c_ratio[\\s\\S]{0,120}?</i>\\s*([\\d.,]+)", "bonus": ">Bonus Points</div>\\s*<i[^>]*></i>\\s*([\\d.,]+)"}, "lg": 1}, {"id": "kufirc", "n": "KuFirc", "d": "kufirc.com", "p": "gazelle", "lp": "/login", "vp": "/", "to": false, "hid": 1, "ef": {"keeploggedin": "1"}, "lg": 1, "s": {"bonus": ">Credits</a>:\\s*</td>[\\s\\S]{0,140}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+)", "upload": ">Up</a>:\\s*</td>[\\s\\S]{0,160}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": ">Down</a>:\\s*</td>[\\s\\S]{0,160}?<span[^>]*class=['\"]stat['\"][^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "ratio": ">Ratio</a>:\\s*</td>[\\s\\S]{0,220}?<span[^>]*class=['\"]r\\d+['\"][^>]*>\\s*(\\d[\\d\\s.,]*)"}}, {"id": "lacale", "n": "La Cale", "d": "la-cale.space", "p": "form", "lp": "/login", "vp": "/profile", "to": false, "uf": "email", "br": 1, "lg": 1, "s": {"upload": "\\\\?\"uploaded\\\\?\"\\s*:\\s*(\\d+)", "download": "\\\\?\"downloaded\\\\?\"\\s*:\\s*(\\d+)", "bonus": "\\\\?\"bonusPoints\\\\?\"\\s*:\\s*(\\d+)"}}, {"id": "mam", "n": "MAM", "d": "www.myanonamouse.net", "p": "form", "lp": "/login.php?returnto=%2Fu%2F", "vp": "/u/", "to": false, "ef": {"rememberMe": "yes", "returnto": "/u/"}, "br": 1, "au": "cookie", "lg": 1, "s": {"upload": "Uploaded[\\s\\S]{0,160}?([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": "Downloaded[\\s\\S]{0,160}?([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "ratio": "Share ratio[\\s\\S]{0,160}?(\\d[\\d\\s.,]*)", "bonus": "Bonus[\\s\\S]{0,160}?([\\d\\s.,]+)"}}, {"id": "milkie", "n": "Milkie", "d": "milkie.cc", "p": "form", "lp": "/auth/signin", "vp": "/browse", "to": false, "uf": "email", "br": 1, "lg": 1, "s": {"upload": "keyboard_arrow_up[\\s\\S]{0,140}?([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": "keyboard_arrow_down[\\s\\S]{0,140}?([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))"}}, {"id": "nexum", "n": "Nexum", "d": "nexum-core.com", "p": "unit3d", "lp": "/login", "vp": "/activity", "uf": "email", "csrf": "_token", "hid": 1, "mu": "/login/2fa", "tf": "code", "xf": {"u": "https://nexum-core.com/user/{{username}}", "fmt": "html", "s": {"upload": "<span class=\"val[^\"]*\"[^>]*>\\s*([\\d.,]+\\s*(?:[KMGTPE]i?o|[KMGTPE]i?B|o|B))\\s*</span>\\s*<span class=\"lbl\">\\s*Uploadé", "bonus": "<span class=\"val[^\"]*\"[^>]*>\\s*([\\d\\s.,]+)\\s*</span>\\s*<span class=\"lbl\">\\s*Points bonus", "downloads": "<span class=\"val[^\"]*\"[^>]*>\\s*(\\d+)\\s*</span>\\s*<span class=\"lbl\">\\s*Téléchargements", "ratio": "title=\"Ratio de ([\\d.,]+)", "class": "title=\"Grade\\s*:\\s*([A-Za-zÀ-ÿ][\\wÀ-ÿ ]*?)\\s*(?:—|<)"}}, "lg": 1, "s": {"unreadMessages": "id=['\\\"]pm-badge['\\\"][^>]*>(\\d+)"}, "cf": 1, "au": "cookie"}, {"id": "nostradamus", "n": "Nostradamus", "d": "nostradamus.foo", "p": "form", "lp": "/sign-in", "vp": "/activity", "to": false, "br": 1, "au": "key", "pks": "#private-key-input", "s": {"upload": ">\\s*Upload total\\s*</div>\\s*<div class=\\\"mt-1[^\\\"]*\\\">\\s*([\\d.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": ">\\s*Download total\\s*</div>\\s*<div class=\\\"mt-1[^\\\"]*\\\">\\s*([\\d.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "snatches": ">\\s*Snatches uniques\\s*</div>\\s*<div class=\\\"mt-1[^\\\"]*\\\">\\s*(\\d+)", "anciennete": ">\\s*Anciennet[^<]*</div>\\s*<div class=\\\"mt-1[^\\\"]*\\\">\\s*([^<]+?)\\s*</div>"}, "lg": 1}, {"id": "orpheus", "n": "Orpheus", "d": "orpheus.network", "p": "gazelle", "lp": "/login.php", "vp": "/", "to": false, "hid": 1, "lg": 1, "s": {"download": "id=\"stats_leeching\"[\\s\\S]*?title=\"([^\"]+)\"", "upload": "id=\"stats_seeding\"[\\s\\S]*?title=\"([^\"]+)\"", "ratio": "id=\"stats_ratio\"[\\s\\S]*?title=\"([^\"]+)\"", "bonus": "Bonus \\(?:([^)]+)\\)", "unreadMessages": "data-noty-type=['\"]Inbox['\"][^>]*>[^<]*?(\\d+|\\ba) new message"}}, {"id": "phoenixproject", "n": "Phoenix Project", "d": "phoenixproject.app", "p": "gazelle", "lp": "/login.php", "vp": "/", "to": true, "hid": 1, "ef": {"login": "Log in", "keeplogged": "1"}, "s": {"upload": "id=\"stats_seeding\"[\\s\\S]{0,200}?title=\"([^\"]+)\"", "download": "id=\"stats_leeching\"[\\s\\S]{0,200}?title=\"([^\"]+)\"", "ratio": "id=\"stats_ratio\"[\\s\\S]{0,200}?title=\"([^\"]+)\"", "bonus": "Bonus \\(([\\d.,]+)\\)", "unreadMessages": "data-noty-type=['\"]Inbox['\"][^>]*>[^<]*?(\\d+|\\ba) new message", "class": "userclass\">([^<]+)"}, "tf": "twofa", "lg": 1}, {"id": "redacted", "n": "Redacted", "d": "redacted.sh", "p": "gazelle", "lp": "/login.php", "vp": "/", "to": false, "hid": 1, "lg": 1, "s": {"requiredRatio": "id=\"stats_required\"[^>]*title=\"Required Ratio: ([^\"]+)\"", "unreadMessages": "data-noty-type=['\"]Inbox['\"][^>]*>[^<]*?(\\d+)"}}, {"id": "seedpool", "n": "Seedpool", "d": "seedpool.org", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "br": 1, "au": "cookie", "lg": 1}, {"id": "sextorrent", "n": "SexTorrent", "d": "sextorrent.myds.me", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "csrf": "_token", "hid": 1, "lg": 1}, {"id": "speedapp", "n": "SpeedApp", "d": "speedapp.io", "p": "form", "lp": "/fr/connexion?locale=fr", "vp": "/profile", "to": false, "ef": {"_remember_me": "on"}, "lg": 1, "s": {"upload": "Uploaded[\\s\\S]{0,120}?<dd[^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))\\s*</dd>", "download": "Downloaded[\\s\\S]{0,120}?<dd[^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))\\s*</dd>", "seedTimeDays": "Seed time[\\s\\S]{0,120}?<dd[^>]*>\\s*(\\d[\\d\\s.,]*)\\s*days"}}, {"id": "teamflix", "n": "TeamFlix", "d": "tracker.teamflix.cc", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "csrf": "_token", "hid": 1, "lg": 1}, {"id": "teamos", "n": "TeamOS", "d": "www.teamos.xyz", "p": "xenforo", "lp": "/login/", "vp": "/account/", "to": false, "au": "cookie", "xf": {"u": "https://www.teamos.xyz/members/{{username}}/", "fmt": "html", "s": {"download": "torrentUserDownloaded[\\s\\S]{0,40}?([\\d.,]+\\s*(?:[KMGTPE]i?B|B))", "upload": "torrentUserUploaded[\\s\\S]{0,40}?([\\d.,]+\\s*(?:[KMGTPE]i?B|B))", "ratio": "torrentUserRatio[\\s\\S]{0,40}?([\\d.,]+)", "bonus": "torrentUserSeedbonus[\\s\\S]{0,40}?([\\d.,]+)", "class": "userBanner[\\s\\S]{0,120}?<strong>\\s*([^<]+?)\\s*</strong>"}}, "lg": 1}, {"id": "theoldschool", "n": "The Old School", "d": "theoldschool.cc", "p": "unit3d", "lp": "/login", "vp": "/", "to": false, "csrf": "_token", "hid": 1, "lg": 1, "s": {"upload": "ratio-bar__uploaded[\\s\\S]{0,260}?(\\d[\\d.,]*(?:&nbsp;|&#160;|&#xa0;|[\\s\\u00a0])*[KMGTPE]i?B)", "download": "ratio-bar__downloaded[\\s\\S]{0,260}?(\\d[\\d.,]*(?:&nbsp;|&#160;|&#xa0;|[\\s\\u00a0])*[KMGTPE]i?B)", "ratio": "ratio-bar__ratio[\\s\\S]{0,200}?</i>\\s*([\\d.,]+)", "seeding": "ratio-bar__seeding[\\s\\S]{0,200}?</i>\\s*(\\d+)", "bonus": "ratio-bar__(?:points|seedbonus|bonus)[\\s\\S]{0,200}?</i>\\s*(\\d[\\d\\s.,]*?)\\s*</a>", "bufferBytes": "ratio-bar__buffer[\\s\\S]{0,260}?(\\d[\\d.,]*(?:&nbsp;|&#160;|&#xa0;|[\\s\\u00a0])*[KMGTPE]i?B)"}, "au": "cookie", "pp": "/api/auth/login"}, {"id": "tigersdl", "n": "Tigers-DL", "d": "www.tigers-dl.net", "p": "form", "lp": "/account-login.php", "vp": "/mybonus.php", "to": false, "br": 1, "lg": 1, "s": {"upload": "title=['\"]Partager['\"][\\s\\S]{0,180}?<font[^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))\\s*</font>", "download": "title=['\"][^'\"]*charg[^'\"]*['\"][\\s\\S]{0,180}?<font[^>]*>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))\\s*</font>", "bonus": "Votre solde[\\s\\S]{0,180}?score-points[^>]*>\\s*([\\d\\s.,]+)", "seeding": "(?:Nombres de Torrents que vous avez en seed\\s*:\\s*|title=['\"]Seeding['\"][\\s\\S]{0,120}?<b>\\s*)(\\d+)"}}, {"id": "torr9", "n": "Torr9", "d": "torr9.net", "p": "apijson", "lp": "https://torr9.net/login", "vp": "https://api.torr9.net/api/v1/users/me", "to": false, "pp": "https://api.torr9.net/api/v1/auth/login", "sf": "token", "mp": {"u": "https://api.torr9.net/api/v1/chat/unread-counts", "f": "total_dms"}, "lg": 1, "sj": {"download": "total_downloaded_bytes", "upload": "total_uploaded_bytes", "bonus": "jeton_balance", "class": "role"}}, {"id": "torrentleech", "n": "TorrentLeech", "d": "www.torrentleech.org", "p": "form", "lp": "/user/account/login/", "vp": "/", "to": false, "s": {"upload": "title=\"Uploaded \\(?:Seeding\\)\"[\\s\\S]*?<span[^>]*>([\\d\\s.,]+\\s*(?:[KMGTPE](?:B|io|o)|B))</span>", "download": "title=\"Downloaded \\(?:Leeching\\)\"[\\s\\S]*?<span[^>]*>([\\d\\s.,]+\\s*(?:[KMGTPE](?:B|io|o)|B))</span>", "ratio": "title=\"Ratio\"[\\s\\S]*?<i[^>]*></i>\\s*([\\d\\s.,]+)", "bonus": "TL Points:[^<]*<span class=\"total-TL-points\">([^<]+)</span>"}, "lg": 1}, {"id": "tr4ker", "n": "TR4KER", "d": "tr4ker.net", "p": "apijson", "lp": "/login", "vp": "/api/me", "to": false, "au": "cookie", "lg": 1, "pp": "/api/auth/login", "sf": "id", "sj": {"upload": "uploaded", "download": "downloaded", "bonus": "money"}}, {"id": "yggreborn", "n": "YGGReborn", "d": "www.yggreborn.org", "p": "form", "lp": "/login?next=/account/", "vp": "/account/", "to": false, "br": 1, "au": "cookie", "s": {"upload": "(\\d[\\d\\s.,]*\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))\\s*</div>[\\s\\S]{0,180}?>Upload<", "download": "(\\d[\\d\\s.,]*\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))\\s*</div>[\\s\\S]{0,180}?>Download<", "class": ">R[oô]le</span>[\\s\\S]*?uppercase\"[\\s\\S]*?>([^<]+)</span>"}, "lg": 1}, {"id": "karagarga", "n": "KaraGarga", "d": "karagarga.in", "p": "form", "lp": "/login.php", "pp": "/takelogin.php", "vp": "/", "to": false, "uf": "username", "pf": "password", "hid": 1, "lg": 1, "s": {"upload": "Ratio:[\\s\\S]{0,120}?&#8593;<font[^>]*>\\s*([\\d.,]+\\s*[KMGTPE]i?B)\\s*</font>", "download": "Ratio:[\\s\\S]{0,160}?w/\\s*([\\d.,]+\\s*[KMGTPE]i?B)", "ratio": "Ratio:\\s*<font[^>]*>\\s*([\\d.,]+)\\s*</font>", "class": "<font color=blue>\\s*([^<]+?)\\s*</font>"}}, {"id": "privatehd", "n": "PrivateHD", "d": "privatehd.to", "p": "unit3d", "lp": "/auth/login", "vp": "/", "to": false, "ef": {"remember": "on"}, "au": "cookie", "s": {"upload": "fa-arrow-up[\\s\\S]{0,40}?</i>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "download": "fa-arrow-down[\\s\\S]{0,40}?</i>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "ratio": "fa-signal[\\s\\S]{0,40}?</i>\\s*([\\d.,]+)", "bufferBytes": "fa-database[\\s\\S]{0,40}?</i>\\s*([\\d.,]+\\s*[KMGTPE]?i?B)", "seeding": "Seeding:</a>\\s*(\\d+)", "bonus": "Bonus:</a>\\s*([\\d.,]+)"}, "lg": 1}, {"id": "wihd", "n": "WiHD", "d": "world-in-hd.net", "p": "form", "lp": "/login", "pp": "/login_check", "vp": "/", "to": false, "uf": "_username", "pf": "_password", "csrf": "_csrf_token", "hid": 1, "ef": {"_remember_me": "on", "_submit": "Connexion"}, "lg": 1, "s": {"upload": "upload-stats\"[\\s\\S]{0,80}?</strong>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "download": "download-stats\"[\\s\\S]{0,80}?</strong>\\s*([\\d\\s.,]+\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))", "ratio": "class=\"ratio\"[\\s\\S]{0,80}?Ratio</strong>\\s*([\\d.,]+)", "theias": "class=\"theias\"[\\s\\S]{0,80}?Theias</strong>\\s*([\\d.,]+\\s*[KMGT]?)", "seeding": "upload-stats\"[\\s\\S]{0,40}?<strong>(\\d+)</strong>", "class": "<span class=\"class\"[^>]*>\\s*([^<]+?)\\s*</span>"}}];

  var ICON = {
    power: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 4v8"/><path d="M7.5 7a7 7 0 1 0 9 0"/></svg>',
    edit: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M14 6l4 4"/></svg>',
    trash: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6.5 7l1 13h9l1-13"/></svg>',
    inspect: '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>',
    refresh: '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 11a8 8 0 1 0-2 5.3"/><path d="M20 4v5h-5"/></svg>',
    sun: '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19"/></svg>',
    moon: '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>',
    gear: '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.5l1.4 2.6 2.9-.6.6 2.9 2.6 1.4-1.4 2.6 1.4 2.6-2.6 1.4-.6 2.9-2.9-.6L12 21.5l-1.4-2.6-2.9.6-.6-2.9L4.5 15l1.4-2.6L4.5 9.8l2.6-1.4.6-2.9 2.9.6z"/></svg>',
    logout: '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 4h3a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-3"/><path d="M10 17l-5-5 5-5"/><path d="M5 12h12"/></svg>'
  };

  var PRESET = {
    form:    {path:"/login",         vmode:"auto", verify:"",         curl:false},
    unit3d:  {path:"/login",         vmode:"auto", verify:"",         curl:true},
    gazelle: {path:"/login.php",     vmode:"auto", verify:"",         curl:false},
    aspnet:  {path:"/login",         vmode:"auto", verify:"",         curl:false},
    xenforo: {path:"/login",         vmode:"auto", verify:"",         curl:false},
    symfony: {path:"/login",         vmode:"auto", verify:"",         curl:false},
    apijson: {path:"/api/auth/login",vmode:"url",  verify:"",         curl:false}
  };

  var css = `
  .av-topbar{position:fixed;left:0;right:0;top:0;height:48px;z-index:9997;display:flex;align-items:center;
    justify-content:space-between;padding:0 16px;pointer-events:none}
  .av-tools{display:flex;gap:8px;pointer-events:auto}
  .av-tbtn{width:38px;height:38px;border-radius:10px;border:1px solid rgba(127,127,127,.35);
    background:rgba(127,127,127,.12);color:#888;cursor:pointer;display:flex;align-items:center;justify-content:center;transition:.13s}
  html.av-dark .av-tbtn{color:#c2c8d2;border-color:#39414e;background:#1c222e}
  .av-tbtn:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  html.av-dark .av-tbtn:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  .av-tbtn:focus-visible{outline:2px solid #74d0d6;outline-offset:2px}
  .av-asst-grid{display:grid;grid-template-columns:auto minmax(70px,auto) 1fr auto;gap:8px 10px;align-items:center}
  .av-asst-grid label{font-size:13px;color:var(--text);font-weight:600;white-space:nowrap}
  .av-asst-val{font-size:12px;font-variant-numeric:tabular-nums;white-space:nowrap;padding:2px 7px;border-radius:6px;background:rgba(127,127,127,.12);color:var(--dim)}
  .av-asst-val.has{background:color-mix(in srgb,var(--ok,#2d7a4f) 18%,transparent);color:var(--ok,#2d7a4f);font-weight:600}
  .av-asst-grid input{width:100%;box-sizing:border-box;padding:7px 9px;border:1px solid var(--border);border-radius:7px;background:rgba(130,130,130,.08);color:inherit;font-size:13px}
  .av-asst-grid .av-btn{padding:6px 12px;font-size:12.5px}
  .av-tbtn.accent{background:var(--ok,#2d7a4f);color:#fff;border-color:transparent}
  html:not(.av-dark) .av-tbtn.accent,html.av-dark .av-tbtn.accent{background:var(--ok,#2d7a4f);color:#fff;border-color:transparent}
  html:not(.av-dark) .av-tbtn.accent:hover,html.av-dark .av-tbtn.accent:hover{color:#fff;border-color:transparent;filter:brightness(1.08)}
  .av-spin{display:inline-block;width:13px;height:13px;border:2px solid rgba(127,127,127,.3);border-top-color:currentColor;border-radius:50%;animation:av-spin .6s linear infinite;vertical-align:-2px;margin-right:4px}
  @keyframes av-spin{to{transform:rotate(360deg)}}
  .brand.refreshing #dash-logo{animation:av-spin .9s linear infinite}
  /* schémas de couleurs des logs */
  #lg-out.lt-amber{background:#1a1206;color:#e8c98a}
  #lg-out.lt-amber .lg-ts{color:#8a6a38} #lg-out.lt-amber .lg-info{color:#d8a24a} #lg-out.lt-amber .lg-ok{color:#cBd14a} #lg-out.lt-amber .lg-site{color:#f0c060}
  #lg-out.lt-green{background:#03140a;color:#7fe0a0}
  #lg-out.lt-green .lg-ts{color:#3a7a52} #lg-out.lt-green .lg-info{color:#5fd0b0} #lg-out.lt-green .lg-ok{color:#74e08a} #lg-out.lt-green .lg-site{color:#9ef0b8}
  #lg-out.lt-blue{background:#070d1a;color:#a8c4e6}
  #lg-out.lt-blue .lg-ts{color:#4a5e84} #lg-out.lt-blue .lg-info{color:#6aa8e0} #lg-out.lt-blue .lg-ok{color:#74c98a} #lg-out.lt-blue .lg-site{color:#7fb0f0}
  #lg-out.lt-light{background:#f6f4ee;color:#33312c;border-color:#e0dacd}
  #lg-out.lt-light .lg-ts{color:#9a948a} #lg-out.lt-light .lg-info{color:#2a6fb0} #lg-out.lt-light .lg-ok{color:#2d7a4f} #lg-out.lt-light .lg-err{color:#c0392b} #lg-out.lt-light .lg-warn{color:#b07d2a} #lg-out.lt-light .lg-site{color:#9a5a16} #lg-out.lt-light .lg-dim{color:#8b857a}
  .av-siteicon{pointer-events:auto;display:none;align-items:center;justify-content:center}
  .av-siteicon img{width:44px;height:44px;border-radius:11px;object-fit:cover;cursor:pointer;
    border:1px solid rgba(127,127,127,.3);background:rgba(127,127,127,.08)}
  .av-fab{display:none}
  .av-overlay{position:fixed;inset:0;z-index:9999;background:rgba(8,10,14,.66);backdrop-filter:blur(3px);
    display:none;align-items:flex-start;justify-content:center;padding:42px 16px;overflow:auto}
  .av-overlay.open{display:flex}
  .av-modal{width:100%;max-width:720px;background:#171c26;color:#d8dde6;border:1px solid #2a3140;
    border-radius:16px;font-family:Inter,system-ui,sans-serif;box-shadow:0 24px 60px -20px #000}
  .av-modal.small{max-width:460px}
  .av-head{display:flex;align-items:center;justify-content:space-between;padding:18px 20px;border-bottom:1px solid #232a36}
  .av-head h2{margin:0;font:600 18px/1.2 'Space Grotesk',system-ui,sans-serif;color:#f0c485}
  .av-x{background:none;border:0;color:#8b93a3;font-size:22px;cursor:pointer;line-height:1}
  .av-x:hover{color:#d8dde6}
  .av-body{padding:18px 20px}
  .av-field{margin:0 0 13px;position:relative}
  .av-field label{display:block;font-size:12.5px;color:#8b93a3;margin:0 0 5px;font-weight:500}
  .av-field input,.av-field select,.av-field textarea{width:100%;background:#1c222e;border:1px solid #2a3140;
    border-radius:9px;color:#e6eaf1;font:14px/1.4 'JetBrains Mono',monospace;padding:9px 11px}
  .av-field input[type=color]{height:42px;padding:4px;cursor:pointer}
  .av-field textarea{min-height:74px;resize:vertical}
  .av-field input:focus,.av-field select:focus,.av-field textarea:focus{outline:none;border-color:var(--ok,#e0892b)}
  .av-hint{font-size:11px;color:#6b7383;margin:4px 0 0}
  .av-row{display:flex;gap:11px}.av-row .av-field{flex:1}
  .av-ac{position:absolute;left:0;right:0;top:100%;z-index:5;background:#1c222e;border:1px solid #2a3140;
    border-radius:0 0 10px 10px;max-height:230px;overflow:auto;display:none;box-shadow:0 14px 30px -12px #000}
  .av-ac.show{display:block}
  .av-ac-item{padding:9px 12px;cursor:pointer;font-size:13.5px;display:flex;justify-content:space-between;gap:10px}
  .av-ac-item:hover,.av-ac-item.hl{background:#243040}
  .av-ac-item b{color:#e6eaf1;font-weight:600}
  .av-ac-item span{color:#6b7383;font-size:12px;font-family:'JetBrains Mono',monospace}
  .av-ac-tag{color:#74d0d6;font-size:11px;align-self:center}
  .av-summary{display:flex;align-items:center;gap:11px;background:rgba(127,207,159,.08);border:1px solid #2d7a4f;
    border-radius:10px;padding:10px 13px;margin:0 0 13px}
  .av-summary img{width:30px;height:30px;border-radius:7px;object-fit:cover;background:#1c222e}
  .av-summary b{color:#bfe6cd;font-size:14px}.av-summary span{color:#7fae8f;font-size:12px}
  .av-summary .av-chg{margin-left:auto;color:#74d0d6;font-size:12px;cursor:pointer;text-decoration:underline}
  .av-adv{margin:6px 0 2px;border-top:1px solid #232a36;padding-top:12px}
  .av-adv>summary{cursor:pointer;color:#74d0d6;font-size:13px;list-style:none;user-select:none}
  .av-adv>summary::-webkit-details-marker{display:none}
  .av-adv>summary::before{content:"▸ ";color:#6b7383}.av-adv[open]>summary::before{content:"▾ "}
  .av-checks{display:flex;flex-direction:column;gap:8px;margin:10px 0 2px}
  .av-check{display:flex;gap:9px;align-items:flex-start;font-size:13px;color:#d8dde6;cursor:pointer}
  .av-check input[type=checkbox]{-webkit-appearance:none;appearance:none;margin:1px 0 0;width:18px;height:18px;flex:0 0 18px;
    border:1.5px solid var(--border,#2a3140);border-radius:5px;background:transparent;cursor:pointer;position:relative;
    transition:background .15s,border-color .15s}
  .av-check input[type=checkbox]:hover{border-color:var(--ok,#e0892b)}
  .av-check input[type=checkbox]:checked{background:var(--ok,#e0892b);border-color:var(--ok,#e0892b)}
  .av-check input[type=checkbox]:checked::after{content:"";position:absolute;left:5px;top:1px;width:5px;height:9px;
    border:solid #fff;border-width:0 2px 2px 0;transform:rotate(45deg)}
  .av-check input[type=checkbox]:focus-visible{outline:2px solid var(--ok,#e0892b);outline-offset:2px}
  .av-check small{display:block;color:#6b7383;font-size:11.5px}
  .av-foot{display:flex;gap:10px;justify-content:flex-end;padding:16px 20px;border-top:1px solid #232a36}
  .av-btn{font:500 14px/1 Inter,system-ui,sans-serif;border-radius:9px;padding:10px 18px;cursor:pointer;border:1px solid transparent}
  .av-btn.ghost{background:none;border-color:#2a3140;color:#8b93a3}
  .av-btn.test{background:none;border-color:#2a3140;color:#8b93a3;font-weight:600}
  .av-btn.go{background:none;border-color:#2a3140;color:#8b93a3;font-weight:600}
  .av-btn.fail{background:#e0796f;color:#0f1218;font-weight:600}
  .av-btn.danger{background:#e0796f;color:#0f1218;font-weight:600}
  .av-btn.save{background:none;border-color:#2a3140;color:#8b93a3;font-weight:600}
  .av-btn:hover{filter:brightness(1.07)}.av-btn:disabled{opacity:.55;cursor:wait;filter:none}
  /* Hover unifie des boutons neutres (ghost/save/go) : remplissage accent + texte blanc */
  .av-btn.ghost:hover,.av-btn.save:hover,.av-btn.go:hover,.av-btn.test:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b);filter:none}
  /* Hover des elements ENCORE orange (onglet actif, bouton login, + accent) : on fonce l'accent */
  .cfg-tab.active:hover,.lg-btn:hover{background:color-mix(in srgb,var(--ok,#e0892b) 85%,#000);filter:none}
  .av-tbtn.accent:hover{background:color-mix(in srgb,var(--ok,#e0892b) 85%,#000);color:#fff;border-color:transparent;filter:none}
  /* Bouton "Se deconnecter" : hover ROUGE pour signaler la sortie (id = priorite sur les hovers orange) */
  #av-logout:hover{background:var(--ko,#e0796f);color:#fff;border-color:var(--ko,#e0796f);filter:none}
  /* Bouton "Parcourir..." de l'input fichier (favicon) */
  input[type=file]::file-selector-button{font:500 13px Inter,system-ui,sans-serif;padding:7px 14px;margin-right:12px;border:1px solid var(--border,#3a4252);border-radius:8px;background:transparent;color:var(--text);cursor:pointer;transition:background .12s,color .12s,border-color .12s}
  input[type=file]::-webkit-file-upload-button{font:500 13px Inter,system-ui,sans-serif;padding:7px 14px;margin-right:12px;border:1px solid var(--border,#3a4252);border-radius:8px;background:transparent;color:var(--text);cursor:pointer;transition:background .12s,color .12s,border-color .12s}
  input[type=file]::file-selector-button:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  input[type=file]::-webkit-file-upload-button:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  .av-msg{margin:0 20px;font-size:13.5px;color:#cfd5df}
  .av-result{margin:14px 20px 0;border-radius:10px;padding:12px 14px;font-size:13px;display:none}
  .av-result.show{display:block}
  .av-result.ok{background:rgba(74,222,128,.13);border:1px solid #4ade80;color:#9af2bb}
  .av-result.ko{background:rgba(224,121,111,.16);border:1px solid #e0796f;color:#ff9d92}
  .av-result pre{margin:8px 0 0;font:12px/1.5 'JetBrains Mono',monospace;color:#cfd5df;white-space:pre-wrap;max-height:240px;overflow:auto}
  .av-fav{display:flex;align-items:center;gap:12px}
  .av-fav img{width:40px;height:40px;border-radius:9px;border:1px solid #2a3140;object-fit:cover;background:#1c222e}
  .av-actions{display:inline-flex;gap:6px;vertical-align:middle;white-space:nowrap}
  .av-act{display:inline-flex;align-items:center;justify-content:center;width:30px;height:30px;border-radius:8px;
    border:1px solid #2a3140;background:#1c222e;color:#8b93a3;cursor:pointer;padding:0;transition:.12s}
  .av-actions .av-act:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}.av-act.on{color:var(--ok,#e0892b)}.av-act.off{color:#6b7383}
  .av-act.ed{color:#74d0d6}.av-act.de{color:#e0796f}
  @media(max-width:520px){.av-row{flex-direction:column;gap:0}}
  `;
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

  // thème sombre : surcharge des variables CSS du dashboard + correctifs hover
  var ds = document.createElement("style");
  ds.textContent = `
  html.av-dark{--bg:#14171c;--border:#2a2f37;--text:#e6eaf1;--dim:#8b93a3;--ko:#e0796f;--good:#4ade80;--alert:#d6a86a;--row-ko-bg:#2a1d1d;}
  html.av-dark tbody tr:hover td{background:var(--row-hover,#283142) !important;}
  html.av-dark tr.row-ko:hover td{background:#321f1f !important;}
  html.av-dark tr.row-disabled:hover td{background:var(--row-hover,#283142) !important;}
  html.av-dark td.na{color:#555 !important;}`;
  document.head.appendChild(ds);

  // lignes d'échec / désactivées en gris (au lieu de rouge)
  var ng = document.createElement("style");
  ng.textContent = `
  tr.row-ko td{ background:rgba(130,130,130,.06) !important; color:var(--dim) !important; }
  tr.row-ko td a{ color:var(--dim) !important; }
  tr.row-ko:hover td{ background:rgba(130,130,130,.11) !important; }
  .dot-ko{ background:#9aa0a6 !important; }
  html.av-dark tr.row-ko:hover td{ background:rgba(170,170,170,.10) !important; }`;
  document.head.appendChild(ng);

  // pastille « en ligne » verte pulsante, triangle d'alerte clignotant, en-têtes triables
  var stylInd = document.createElement("style");
  stylInd.textContent = `
  .dot-live{ background:#19b562 !important; animation:av-ok-ping 1.7s ease-out infinite; }
  @keyframes av-ok-ping{
    0%{ box-shadow:0 0 0 0 rgba(25,181,98,.55); }
    70%{ box-shadow:0 0 0 5px rgba(25,181,98,0); }
    100%{ box-shadow:0 0 0 0 rgba(25,181,98,0); } }
  .dot-pulse{ animation:av-soft-blink 1.6s ease-in-out infinite; }
  @keyframes av-soft-blink{ 0%,100%{opacity:1;} 50%{opacity:.42;} }
  .dot-wait{ background:#c9c3bb !important; animation:av-soft-blink 2s ease-in-out infinite; }
  .warn-tri{ display:inline-flex; width:14px; height:14px; flex-shrink:0; line-height:0; animation:av-warn-blink 1.05s ease-in-out infinite; }
  @keyframes av-warn-blink{ 0%,100%{opacity:1;} 50%{opacity:.22;} }
  thead th.av-sortable{ cursor:pointer; user-select:none; transition:color .12s; }
  thead th.av-sortable:hover{ color:var(--text); }
  thead th.sorted{ color:var(--text); }
  thead th .sort-arrow{ font-size:10px; }`;
  document.head.appendChild(stylInd);

  // modale & contrôles en thème CLAIR quand le dashboard est clair
  var lm = document.createElement("style");
  lm.textContent = `
  html:not(.av-dark) .av-modal{background:#fdfcfa;color:#1a1a1a;border-color:#e2ddd6;box-shadow:0 24px 60px -20px rgba(0,0,0,.22)}
  html:not(.av-dark) .av-head{border-bottom-color:#ece7df}
  html:not(.av-dark) .av-head h2{color:#b07d2a}
  html:not(.av-dark) .av-foot,html:not(.av-dark) .av-adv,html:not(.av-dark) .av-adv>summary{border-color:#ece7df}
  html:not(.av-dark) .av-field label,html:not(.av-dark) .av-hint,html:not(.av-dark) .av-check small,html:not(.av-dark) .av-x{color:#6b6560}
  html:not(.av-dark) .av-field input,html:not(.av-dark) .av-field select,html:not(.av-dark) .av-field textarea{background:#f4f1ea;border-color:#e2ddd6;color:#1a1a1a}
  html:not(.av-dark) .av-check span,html:not(.av-dark) .av-ac-item b{color:#1a1a1a}
  html:not(.av-dark) .av-btn.ghost,html:not(.av-dark) .av-btn.save,html:not(.av-dark) .av-btn.go,html:not(.av-dark) .av-btn.test{border-color:#ddd6cb;color:#6b6560}
  html:not(.av-dark) .av-btn.ghost:hover,html:not(.av-dark) .av-btn.save:hover,html:not(.av-dark) .av-btn.go:hover,html:not(.av-dark) .av-btn.test:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  html:not(.av-dark) .av-ac{background:#fff;border-color:#e2ddd6}
  html:not(.av-dark) .av-ac-item:hover,html:not(.av-dark) .av-ac-item.hl{background:#f0ece4}
  html:not(.av-dark) .av-act{background:#f4f1ea;border-color:#e2ddd6}
  html:not(.av-dark) .av-actions .av-act:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  html:not(.av-dark) .av-tbtn{color:#6b6560;border-color:#d8d2c8;background:#efece6}
  html:not(.av-dark) .av-tbtn:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  html:not(.av-dark) .av-summary{background:rgba(45,122,79,.08)}
  html:not(.av-dark) .av-result.ok{background:rgba(21,128,61,.10);border-color:#15803d;color:#136a33}
  html:not(.av-dark) .av-result.ko{background:rgba(192,57,43,.09);border-color:#c0392b;color:#a83124}
  html:not(.av-dark) .av-result pre{color:#3a3a3a}`;
  document.head.appendChild(lm);

  var cfgStyle = document.createElement("style");
  cfgStyle.textContent = `
  .av-switch{display:inline-flex;align-items:center;cursor:pointer;height:38px}
  .av-switch input{position:absolute;opacity:0;width:0;height:0}
  .av-sw-track{position:relative;width:50px;height:28px;border-radius:16px;background:#cdc8bb;transition:background .2s;display:inline-flex;align-items:center;border:1px solid rgba(0,0,0,.10)}
  html.av-dark .av-sw-track{background:#39414e;border-color:#2a3140}
  .av-sw-thumb{position:absolute;top:2px;left:2px;width:22px;height:22px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.35);transition:transform .2s;z-index:1}
  .av-switch input:checked + .av-sw-track .av-sw-thumb{transform:translateX(22px)}
  .av-switch input:checked + .av-sw-track{background:var(--ok,#2d7a4f)}
  .av-sw-ic{position:absolute;top:0;bottom:0;display:flex;align-items:center;color:#fff;opacity:.8}
  .av-sw-ic svg{width:13px;height:13px}
  .av-sw-ic.sun{left:6px}.av-sw-ic.moon{right:6px}
  html:not(.av-dark) .av-sw-ic.sun{color:#8a6d2f}
  html:not(.av-dark) .av-sw-ic.moon{color:#a59f93}

  .av-coltheme{display:flex;align-items:center;gap:26px;flex-wrap:wrap;margin:6px 0 4px}
  .av-ct-item{display:flex;align-items:center;gap:11px}
  .av-ct-item>label{margin:0;font-size:13px;color:#d8dde6;cursor:pointer;white-space:nowrap}
  html:not(.av-dark) .av-ct-item>label{color:#1a1a1a}
  .av-ct-color{-webkit-appearance:none;-moz-appearance:none;appearance:none;width:48px;height:30px;padding:2px;
    border:1px solid var(--border,#2a3140);border-radius:7px;background:transparent;cursor:pointer;flex:0 0 auto}
  .av-ct-color:hover{border-color:var(--ok,#e0892b)}
  .av-ct-color::-webkit-color-swatch-wrapper{padding:0}
  .av-ct-color::-webkit-color-swatch{border:none;border-radius:4px}
  .av-ct-color::-moz-color-swatch{border:none;border-radius:4px}

  .cfg-page{position:fixed;inset:0;z-index:9990;display:none;overflow:auto;background:#14171d;color:#e6e9ef;font-family:inherit}
  html:not(.av-dark) .cfg-page{background:#f3f0e9;color:#23211d}
  .cfg-page.open{display:block}
  .cfg-shell{display:flex;min-height:100vh;width:100%;align-items:stretch}
  .cfg-side{width:248px;flex:0 0 248px;display:flex;flex-direction:column;gap:4px;padding:26px 18px;border-right:1px solid #262d38}
  html:not(.av-dark) .cfg-side{border-right-color:#e0dacd}
  .cfg-brand{display:flex;align-items:center;gap:12px;font-weight:700;letter-spacing:.16em;font-size:13px;color:#f0c485;margin-bottom:18px;text-transform:uppercase}
  html:not(.av-dark) .cfg-brand{color:#b07d2a}
  .cfg-brand img{width:52px;height:52px;object-fit:contain;background:transparent;border:0}
  .cfg-nav{display:flex;flex-direction:column;gap:3px;flex:1}
  .cfg-tab{text-align:left;padding:10px 13px;border-radius:9px;border:1px solid transparent;background:transparent;color:#aeb6c2;cursor:pointer;font-size:14px;font-family:inherit}
  .cfg-tab:not(.active):hover{background:color-mix(in srgb,var(--ok,#e0892b) 12%,transparent);border-color:var(--ok,#e0892b);color:var(--ok,#e0892b)}
  .cfg-tab.active{background:var(--ok,#2d7a4f);color:#fff;font-weight:600}
  html:not(.av-dark) .cfg-tab{color:#6b6560}
  html:not(.av-dark) .cfg-tab.active{color:#fff;font-weight:600}
  html:not(.av-dark) .cfg-tab:not(.active):hover{background:color-mix(in srgb,var(--ok,#e0892b) 12%,transparent);border-color:var(--ok,#e0892b);color:var(--ok,#e0892b)}
  .cfg-back{margin-top:10px;width:100%}
  .av-btn.cfg-back:hover{background:var(--ok,#e0892b);color:#fff;border-color:var(--ok,#e0892b)}
  .cfg-main{flex:1;min-width:0;padding:28px 34px 60px}
  .cfg-sec{display:none}.cfg-sec.active{display:block}
  .al-block{border:1px solid var(--border,#2a3140);border-radius:10px;padding:13px 14px;margin:0 0 14px}
  .al-set{font-size:11px;opacity:.7;font-weight:400}
  .al-set.on{color:var(--good,#22c55e);opacity:.95}
  .cfg-sec h2{margin:0 0 18px;font-size:19px}
  .cfg-pre{background:#0e1014;color:#cdd3dc;border:1px solid #2a3140;border-radius:10px;padding:12px 14px;font:12px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace;white-space:pre-wrap;word-break:break-word;max-height:62vh;overflow:auto;margin:0}
  html:not(.av-dark) .cfg-pre{background:#fbfaf6;color:#33312c;border-color:#e0dacd}
  #lg-out{background:#0a0d12;color:#c6ccd6;border:1px solid #1b2230;max-height:none;height:calc(100vh - 248px);min-height:340px;border-radius:10px;font:12.5px/1.55 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;user-select:text;-webkit-user-select:text}
  html:not(.av-dark) #lg-out{background:#0a0d12;color:#c6ccd6;border-color:#1b2230}
  #lg-out .lg-ts{color:#5b6472}
  #lg-out .lg-info{color:#56b6d6}
  #lg-out .lg-ok{color:#74c98a}
  #lg-out .lg-err{color:#e0796f}
  #lg-out .lg-warn{color:#e3b341}
  #lg-out .lg-site{color:#e0a253;font-weight:600}
  #lg-out .lg-dim{color:#7d8694}
  .cfg-toolrow{display:flex;gap:8px;margin-bottom:10px;align-items:center}
  .cfg-toolrow select{padding:7px 10px;border-radius:8px;background:#1a202b;color:#e6e9ef;border:1px solid #2a3140}
  html:not(.av-dark) .cfg-toolrow select{background:#fff;color:#23211d;border-color:#d8d2c8}
  .cfg-actions{margin-top:16px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
  .cfg-list{display:flex;flex-direction:column;gap:8px;margin-top:16px}
  .cfg-row{display:flex;align-items:center;gap:10px;padding:9px 12px;border:1px solid #262d38;border-radius:10px;background:#1a202b}
  html:not(.av-dark) .cfg-row{background:#fbfaf6;border-color:#e6e0d3}
  .cfg-row .nm{flex:1;font-weight:600;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  #se-css{width:100%;box-sizing:border-box;background:#0e1014;color:#cdd3dc;border:1px solid #2a3140;border-radius:9px;padding:10px 12px;font:12.5px/1.5 ui-monospace,monospace;resize:vertical}
  html:not(.av-dark) #se-css{background:#fbfaf6;color:#33312c;border-color:#e0dacd}
  .av-switch-row{display:flex;align-items:center;gap:10px;cursor:pointer}
  .cfg-main .av-result{position:static;margin:0 0 16px}
  @media(max-width:720px){.cfg-shell{flex-direction:column}.cfg-side{width:auto;flex:none;border-right:0;border-bottom:1px solid #262d38;flex-direction:row;flex-wrap:wrap}.cfg-nav{flex-direction:row;flex-wrap:wrap}.cfg-back{width:auto}.cfg-main{padding:22px 18px 50px}}`;
  document.head.appendChild(cfgStyle);

  var MALINOIS_VER="123";          // numéro de build interne (incrémenté à chaque livraison)
  var APP_VERSION=(parseInt(MALINOIS_VER,10)/100).toFixed(2);  // version affichée = build/100 (ex. 102 -> 1.02)
  var alertsCfg=null;             // dernière config alertes connue (pour notifs navigateur)
  var _brPrevFailed=null;         // mémoire des sites en échec (notifs navigateur, anti-spam côté client)
  try{ console.log("MALINOIS addsite v"+MALINOIS_VER+" (app "+APP_VERSION+")"); }catch(e){}
  function el(html){var d=document.createElement("div");d.innerHTML=html.trim();return d.firstChild;}
  function post(url,obj,timeoutMs){
    var ctrl = (typeof AbortController!=="undefined") ? new AbortController() : null;
    var to = (ctrl && timeoutMs) ? setTimeout(function(){ try{ctrl.abort();}catch(e){} }, timeoutMs) : null;
    return fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(obj||{}),signal:ctrl?ctrl.signal:undefined}).then(function(r){ if(to) clearTimeout(to); return r.text().then(function(t){try{return JSON.parse(t);}catch(e){return {ok:false,error:"Réponse invalide du service (HTTP "+r.status+", "+(t?"non-JSON":"vide")+")."};}}); }).catch(function(e){ if(to) clearTimeout(to); if(e&&e.name==="AbortError"){ return {ok:false,error:"Délai dépassé — le serveur n'a pas répondu (recharge la page : Ctrl+Maj+R)."}; } throw e; });
  }
  function esc(t){return (t||"").replace(/[&<>]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;"}[c];});}
  // /inspect peut renvoyer un 502/réponse non-JSON transitoire quand le service
  // vient d'être redémarré (déploiement) ou est surchargé. On réessaie alors
  // automatiquement quelques fois. `alive()` permet d'abandonner si la modale a
  // été fermée / un autre site ouvert entre-temps.
  function inspectPost(payload, tries, alive){
    tries = (tries==null) ? 3 : tries;
    function transient(j){ return j && j.ok===false && /HTTP\s*50\d|non-?JSON|\bvide\b|injoignable|Délai/i.test(j.error||""); }
    function wait(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }
    return post("/inspect", payload).then(function(j){
      if(alive && !alive()) return j;
      if(transient(j) && tries>1){ return wait(1800).then(function(){ return (alive&&!alive())?j:inspectPost(payload, tries-1, alive); }); }
      return j;
    }).catch(function(e){
      if(tries>1 && (!alive || alive())){ return wait(1800).then(function(){ return inspectPost(payload, tries-1, alive); }); }
      throw e;
    });
  }

  /* ---------- TOOLBAR (boutons dans l'en-tête) ---------- */
  var tools = document.getElementById("tools-slot") || el('<div class="av-tools"></div>');
  if(!tools.parentNode) document.body.appendChild(tools);
  var themeSwitch = el('<label class="av-switch" title="Thème clair / sombre"><input type="checkbox" id="av-theme-cb"><span class="av-sw-track"><span class="av-sw-ic sun">'+ICON.sun+'</span><span class="av-sw-ic moon">'+ICON.moon+'</span><span class="av-sw-thumb"></span></span></label>');
  var bAdd = el('<button class="av-tbtn accent" type="button" title="Ajouter un site"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></button>');
  var bSettings = el('<button class="av-tbtn" type="button" title="Configuration">'+ICON.gear+'</button>');
  tools.appendChild(themeSwitch); tools.appendChild(bAdd); tools.appendChild(bSettings);
  var bLogout = el('<button class="av-tbtn" id="av-logout" type="button" title="Se déconnecter" style="display:none">'+ICON.logout+'</button>');
  tools.appendChild(bLogout);
  bLogout.addEventListener("click", function(){ post("/auth/logout",{}).then(function(){ location.reload(); }); });
  (function(){ var av=document.getElementById("app-ver"); if(av) av.textContent="Version : "+APP_VERSION; })();

  var dashLogo = document.getElementById("dash-logo");
  var dashTitle = document.getElementById("dash-title");
  var brand = document.getElementById("brand");
  if(brand) brand.addEventListener("click", function(){ refresh(); });

  var settings = {name:"",url:"",accent:"#e0892b",dark:false,cron_hours:24,favicon:false};

  function applySettings(s){
    settings = s || settings;
    if (dashTitle && settings.name){ dashTitle.textContent = settings.name; document.title = settings.name; }
    if (settings.accent) document.documentElement.style.setProperty("--ok", settings.accent, "important");
    document.documentElement.classList.toggle("av-dark", !!settings.dark);
    var _cb=document.getElementById("av-theme-cb"); if(_cb) _cb.checked = !!settings.dark;
    var _uc=document.getElementById("av-usercss");
    if(!_uc){ _uc=document.createElement("style"); _uc.id="av-usercss"; document.head.appendChild(_uc); }
    _uc.textContent = settings.css || "";
    if (settings.favicon) {
      var link = document.querySelector("link[rel~='icon']") || document.createElement("link");
      link.rel = "icon"; link.href = "/favicon.png?v=" + Date.now();
      if (!link.parentNode) document.head.appendChild(link);
      if (dashLogo){
        dashLogo.src = "/favicon.png?v=" + Date.now();
        dashLogo.style.display = "block";
        dashLogo.onerror = function(){ dashLogo.style.display = "none"; };
      }
    } else if (dashLogo){ dashLogo.style.display = "none"; }
  }
  function loadSettings(){
    return fetch("/settings").then(function(r){return r.json();}).then(function(j){
      if (j && j.ok) applySettings(j.settings);
    }).catch(function(){});
  }

  // --- Planification (cron) ---
  function cronOpts(){
    var dows=[]; SQ("#cr-dows").querySelectorAll(".cr-dow").forEach(function(c){ if(c.checked) dows.push(parseInt(c.value,10)); });
    return { hour:parseInt(SQ("#cr-hour").value,10)||0, minute:parseInt(SQ("#cr-min").value,10)||0,
             mode:SQ("#cr-mode").value, interval_days:parseInt(SQ("#cr-intv").value,10)||1, weekdays:dows };
  }
  function cronExpr(o){
    var mn=Math.max(0,Math.min(59,o.minute)), hr=Math.max(0,Math.min(23,o.hour));
    if(o.mode==="weekdays"){ var d=(o.weekdays&&o.weekdays.length)?o.weekdays.slice().sort().join(","):"*"; return mn+" "+hr+" * * "+d; }
    if(o.mode==="daily") return mn+" "+hr+" * * *";
    return mn+" "+hr+" */"+Math.max(1,o.interval_days)+" * *";
  }
  function cronPreview(){
    var o=cronOpts();
    SQ("#cr-intvwrap").style.display=(o.mode==="interval")?"inline":"none";
    SQ("#cr-dows").style.display=(o.mode==="weekdays")?"flex":"none";
    SQ("#cr-preview").textContent=cronExpr(o);
  }
  function fillCron(c){
    c=c||{};
    if(c.hour!=null) SQ("#cr-hour").value=c.hour;
    if(c.minute!=null) SQ("#cr-min").value=c.minute;
    SQ("#cr-mode").value=c.mode||"interval";
    if(c.interval_days) SQ("#cr-intv").value=c.interval_days;
    var set={}; (c.weekdays||[]).forEach(function(d){ set[d]=1; });
    SQ("#cr-dows").querySelectorAll(".cr-dow").forEach(function(cb){ cb.checked=!!set[parseInt(cb.value,10)]; });
    cronPreview();
  }
  function loadCron(){
    SQ("#cr-current").textContent="…"; SQ("#cr-msg").textContent="";
    fetch("/cron").then(function(r){return r.json();}).then(function(j){
      if(j&&j.ok){ fillCron(j.cron); SQ("#cr-current").textContent=j.line||"(aucune tâche planifiée)"; }
      else { cronPreview(); SQ("#cr-current").textContent="(indisponible)"; }
    }).catch(function(){ cronPreview(); SQ("#cr-current").textContent="(service injoignable)"; });
  }
  function bindCron(){
    ["#cr-hour","#cr-min","#cr-mode","#cr-intv"].forEach(function(s){ SQ(s).addEventListener("input",cronPreview); SQ(s).addEventListener("change",cronPreview); });
    SQ("#cr-dows").querySelectorAll(".cr-dow").forEach(function(c){ c.addEventListener("change",cronPreview); });
    SQ("#cr-save").addEventListener("click", function(){
      var btn=this, o=cronOpts();
      if(o.mode==="weekdays" && !o.weekdays.length){ SQ("#cr-msg").style.color="var(--ko,#e0796f)"; SQ("#cr-msg").textContent="Choisis au moins un jour."; return; }
      btn.disabled=true; SQ("#cr-msg").textContent="";
      post("/cron", o).then(function(j){
        btn.disabled=false;
        if(j&&j.ok){ SQ("#cr-current").textContent=j.line||"(aucune)"; SQ("#cr-msg").style.color="var(--good,#22c55e)"; SQ("#cr-msg").textContent="Planification enregistrée."; }
        else { SQ("#cr-msg").style.color="var(--ko,#e0796f)"; SQ("#cr-msg").textContent="Erreur : "+((j&&j.error)||""); }
      }).catch(function(){ btn.disabled=false; SQ("#cr-msg").style.color="var(--ko,#e0796f)"; SQ("#cr-msg").textContent="Service injoignable."; });
    });
  }

  function alSet(sel, on){ var e=SQ(sel); if(!e) return; e.textContent=on?"✓ déjà défini":""; e.className="al-set"+(on?" on":""); }
  function fillAlerts(a){
    a=a||{}; alertsCfg=a;
    var em=a.email||{}, tg=a.telegram||{}, wh=a.webhook||{}, br=a.browser||{};
    SQ("#al-em-on").checked=!!em.enabled;
    SQ("#al-em-host").value=em.host||""; SQ("#al-em-port").value=em.port||"";
    SQ("#al-em-sec").value=em.security||"starttls";
    SQ("#al-em-user").value=em.user||""; SQ("#al-em-from").value=em.from||""; SQ("#al-em-to").value=em.to||"";
    SQ("#al-em-pass").value=""; alSet("#al-em-pwset", em.password_set);
    SQ("#al-tg-on").checked=!!tg.enabled;
    SQ("#al-tg-chat").value=tg.chat_id||""; SQ("#al-tg-token").value=""; alSet("#al-tg-tokset", tg.token_set);
    SQ("#al-wh-on").checked=!!wh.enabled;
    SQ("#al-wh-url").value=wh.url||""; SQ("#al-wh-auth").value=""; alSet("#al-wh-authset", wh.auth_set);
    if(SQ("#al-br-on")){ SQ("#al-br-on").checked=!!br.enabled; brUpdateMsg(); }
    SQ("#al-onfail").checked=!!a.on_failure;
    SQ("#al-onrecover").checked=!!a.on_recovery;
    SQ("#al-oneach").checked=!!a.on_each_run;
    if(SQ("#al-onstatsna")) SQ("#al-onstatsna").checked=!!a.on_stats_na;
  }
  function chPayload(ch){
    if(ch==="email") return {channel:"email", email:{ enabled:SQ("#al-em-on").checked, host:SQ("#al-em-host").value.trim(),
        port:SQ("#al-em-port").value.trim(), security:SQ("#al-em-sec").value, user:SQ("#al-em-user").value.trim(),
        password:SQ("#al-em-pass").value, from:SQ("#al-em-from").value.trim(), to:SQ("#al-em-to").value.trim() }};
    if(ch==="telegram") return {channel:"telegram", telegram:{ enabled:SQ("#al-tg-on").checked,
        token:SQ("#al-tg-token").value.trim(), chat_id:SQ("#al-tg-chat").value.trim() }};
    if(ch==="webhook") return {channel:"webhook", webhook:{ enabled:SQ("#al-wh-on").checked,
        url:SQ("#al-wh-url").value.trim(), auth:SQ("#al-wh-auth").value }};
    return {};
  }
  function chMsg(sel, txt, ok){ var m=SQ(sel); if(!m) return; m.style.color=(ok===true)?"var(--good,#22c55e)":((ok===false)?"var(--ko,#e0796f)":""); m.textContent=txt; }
  function saveChannel(ch, msgSel, btn){
    btn.disabled=true; chMsg(msgSel, "Enregistrement…", null);
    post("/alerts", chPayload(ch)).then(function(j){
      btn.disabled=false;
      if(j&&j.ok){ if(j.alerts) fillAlerts(j.alerts); chMsg(msgSel, "✓ enregistré", true); }
      else { chMsg(msgSel, "✗ "+((j&&j.error)||"erreur"), false); }
    }).catch(function(){ btn.disabled=false; chMsg(msgSel, "Service injoignable.", false); });
  }
  function testChannel(ch, msgSel, btn){
    var p=chPayload(ch); p.save=true;
    btn.disabled=true; chMsg(msgSel, "Test en cours…", null);
    post("/alerts/test", p).then(function(j){
      btn.disabled=false;
      if(j&&j.ok){ chMsg(msgSel, "✓ "+(j.detail||"OK"), true); loadAlerts(); }
      else { chMsg(msgSel, "✗ "+((j&&(j.detail||j.error))||"échec"), false); }
    }).catch(function(){ btn.disabled=false; chMsg(msgSel, "Service injoignable.", false); });
  }
  function saveTypes(){
    post("/alerts", {types:true, on_failure:SQ("#al-onfail").checked,
      on_recovery:SQ("#al-onrecover").checked, on_each_run:SQ("#al-oneach").checked,
      on_stats_na:(SQ("#al-onstatsna")?SQ("#al-onstatsna").checked:false)})
      .then(function(j){ if(j&&j.ok&&j.alerts) alertsCfg=j.alerts; }).catch(function(){});
  }
  /* --- notifications navigateur (côté client) --- */
  function brSupported(){ return ("Notification" in window); }
  function brUpdateMsg(){
    var m=SQ("#al-br-msg"); if(!m) return;
    if(!brSupported()){ m.style.color="var(--ko,#e0796f)"; m.textContent="Non supporté par ce navigateur."; return; }
    if(Notification.permission==="granted"){ m.style.color="var(--good,#22c55e)"; m.textContent="Autorisé sur ce navigateur."; }
    else if(Notification.permission==="denied"){ m.style.color="var(--ko,#e0796f)"; m.textContent="Bloqué — à réautoriser dans les réglages du navigateur."; }
    else { m.style.color=""; m.textContent="Autorisation pas encore accordée (sera demandée à l'activation)."; }
  }
  function brSave(enabled){ post("/alerts", {browser:{enabled:enabled}}).then(function(j){ if(j&&j.ok&&j.alerts) alertsCfg=j.alerts; }).catch(function(){}); }
  function brTest(){
    var m=SQ("#al-br-msg");
    if(!brSupported()){ brUpdateMsg(); return; }
    function fire(){ try{ new Notification("Malinois", {body:"Notification de test ✓"}); if(m){ m.style.color="var(--good,#22c55e)"; m.textContent="✓ notification envoyée"; } }catch(e){ if(m){ m.style.color="var(--ko,#e0796f)"; m.textContent="Erreur : "+e; } } }
    if(Notification.permission==="granted"){ fire(); }
    else { Notification.requestPermission().then(function(p){ brUpdateMsg(); if(p==="granted") fire(); }); }
  }
  function alMsg(txt, ok){ var m=SQ("#al-msg"); m.style.color=ok?"var(--good,#22c55e)":"var(--ko,#e0796f)"; m.textContent=txt; }
  function loadAlerts(){
    fetch("/alerts").then(function(r){return r.json();}).then(function(j){
      if(j&&j.ok) fillAlerts(j.alerts);
    }).catch(function(){});
  }
  function bindAlerts(){
    SQ("#al-em-save").addEventListener("click", function(){ saveChannel("email", "#al-em-msg", this); });
    SQ("#al-tg-save").addEventListener("click", function(){ saveChannel("telegram", "#al-tg-msg", this); });
    SQ("#al-wh-save").addEventListener("click", function(){ saveChannel("webhook", "#al-wh-msg", this); });
    SQ("#al-em-test").addEventListener("click", function(){ testChannel("email", "#al-em-msg", this); });
    SQ("#al-tg-test").addEventListener("click", function(){ testChannel("telegram", "#al-tg-msg", this); });
    SQ("#al-wh-test").addEventListener("click", function(){ testChannel("webhook", "#al-wh-msg", this); });
    ["#al-onfail","#al-onrecover","#al-oneach","#al-onstatsna"].forEach(function(s){ if(SQ(s)) SQ(s).addEventListener("change", saveTypes); });
    SQ("#al-br-on").addEventListener("change", function(){
      var on=this.checked, self=this;
      if(on && brSupported() && Notification.permission!=="granted"){
        Notification.requestPermission().then(function(p){ brUpdateMsg();
          if(p==="granted"){ brSave(true); } else { self.checked=false; brSave(false); } });
      } else { brUpdateMsg(); brSave(on); }
    });
    SQ("#al-br-test").addEventListener("click", brTest);
    SQ("#al-test").addEventListener("click", function(){
      var btn=this; btn.disabled=true; alMsg("Envoi du test…", true);
      post("/alerts/test", {}).then(function(j){
        btn.disabled=false;
        if(j&&j.ok){ alMsg("Test envoyé ✓  ("+(j.detail||"")+")", true); }
        else { alMsg("Échec : "+((j&&(j.detail||j.error))||"inconnue"), false); }
      }).catch(function(){ btn.disabled=false; alMsg("Service injoignable.", false); });
    });
  }
  function browserNotifyCheck(status){
    try{
      if(!alertsCfg || !alertsCfg.browser || !alertsCfg.browser.enabled) return;
      if(!brSupported() || Notification.permission!=="granted") return;
      var sites=(status&&status.sites)||[];
      var failed=sites.filter(function(s){return !s.ok;}).map(function(s){return s.name||s.slug||"?";});
      if(_brPrevFailed===null){ _brPrevFailed=failed; return; }
      var nw=failed.filter(function(f){return _brPrevFailed.indexOf(f)<0;});
      if(nw.length){ try{ new Notification("Malinois — site en échec", {body:nw.join(", ")}); }catch(e){} }
      _brPrevFailed=failed;
    }catch(e){}
  }

  themeSwitch.querySelector("#av-theme-cb").addEventListener("change", function(){
    settings.dark = this.checked; applySettings(settings);
    post("/settings", {dark: settings.dark});
  });

  /* ---------- AUTHENTIFICATION ---------- */
  var authState = {configured:false, twofa:false, authed:false};
  var lgStyle = document.createElement("style");
  lgStyle.textContent = `
  #lg-page{position:fixed;inset:0;z-index:9998;display:none;align-items:center;justify-content:center;padding:20px;
    background:radial-gradient(1100px 560px at 50% -12%, rgba(176,125,42,.20), transparent), #14171d;font-family:inherit}
  #lg-page.open{display:flex}
  .lg-card{width:100%;max-width:380px;background:#1b2029;border:1px solid #2a3140;border-radius:18px;
    padding:34px 30px 30px;box-shadow:0 30px 80px -24px rgba(0,0,0,.6)}
  .lg-brand{display:flex;flex-direction:column;align-items:center;gap:8px;margin-bottom:24px}
  .lg-logo{width:56px;height:56px;border-radius:14px;object-fit:contain;background:transparent}
  .lg-name{font-size:21px;font-weight:700;letter-spacing:.22em;color:#f0c485}
  .lg-sub{font-size:12.5px;color:#8b93a3}
  .lg-field{margin-bottom:14px}
  .lg-field label{display:block;font-size:12px;color:#8b93a3;margin-bottom:6px}
  .lg-field input{width:100%;box-sizing:border-box;padding:11px 13px;border-radius:10px;border:1px solid #2a3140;background:#11151c;color:#e6eaf1;font-size:15px;outline:none}
  .lg-field input:focus{border-color:var(--ok,#e0892b)}
  .lg-remember{display:flex;align-items:center;gap:8px;font-size:13px;color:#cdd3dd;margin:2px 0 18px;cursor:pointer;user-select:none}
  .lg-remember input{width:15px;height:15px;accent-color:var(--ok,#e0892b)}
  .lg-btn{width:100%;padding:12px;border:none;border-radius:10px;background:var(--ok,#e0892b);color:#fff;font-size:15px;font-weight:600;cursor:pointer}
  .lg-btn:disabled{opacity:.6;cursor:default}
  .lg-msg{margin-top:12px;font-size:13px;text-align:center;min-height:16px;color:#8b93a3}
  .lg-msg.ko{color:#e0796f}
  html:not(.av-dark) #lg-page{background:radial-gradient(1100px 560px at 50% -12%, rgba(176,125,42,.14), transparent), #f3f1ec}
  html:not(.av-dark) .lg-card{background:#fff;border-color:#e6e0d7;box-shadow:0 30px 80px -28px rgba(0,0,0,.25)}
  html:not(.av-dark) .lg-name{color:#b07d2a}
  html:not(.av-dark) .lg-sub,html:not(.av-dark) .lg-field label{color:#6b6560}
  html:not(.av-dark) .lg-field input{background:#f6f4ef;border-color:#e2ddd6;color:#1a1a1a}
  html:not(.av-dark) .lg-remember{color:#3a3a3a}`;
  document.head.appendChild(lgStyle);
  var loginOv = el(`
  <div id="lg-page">
    <div class="lg-card" role="dialog" aria-modal="true" aria-label="Connexion">
      <div class="lg-brand">
        <img class="lg-logo" id="lg-logo" alt="" style="display:none">
        <div class="lg-name" id="lg-name">MALINOIS</div>
        <div class="lg-sub">Accès au tableau de bord</div>
      </div>
      <div class="lg-field"><label>Mot de passe</label><input id="lg-pass" type="password" autocomplete="current-password"></div>
      <div class="lg-field" id="lg-codefield" style="display:none"><label>Code 2FA</label><input id="lg-code" inputmode="numeric" autocomplete="one-time-code" placeholder="123456"></div>
      <label class="lg-remember"><input type="checkbox" id="lg-remember" checked> Se souvenir de moi</label>
      <button class="lg-btn" id="lg-go" type="button">Se connecter</button>
      <div class="lg-msg" id="lg-result"></div>
    </div>
  </div>`);
  document.body.appendChild(loginOv);
  function LQ(s){ return loginOv.querySelector(s); }
  function showLogin(){
    var ic=document.querySelector('link[rel*="icon"]'); var lo=LQ("#lg-logo");
    if(ic&&ic.href){ lo.src=ic.href; lo.style.display="block"; }
    var t=(document.title||"").split("—")[0].trim(); if(t) LQ("#lg-name").textContent=t;
    loginOv.classList.add("open"); setTimeout(function(){ LQ("#lg-pass").focus(); }, 50);
  }
  function updateAuthBtn(){ bLogout.style.display = (authState.configured && authState.authed) ? "flex" : "none"; }
  function doLogin(){
    var btn=LQ("#lg-go"); btn.disabled=true; btn.textContent="…";
    post("/auth/login",{password:LQ("#lg-pass").value, code:LQ("#lg-code").value, remember:LQ("#lg-remember").checked}).then(function(j){
      btn.disabled=false; btn.textContent="Se connecter";
      if(j.ok){ loginOv.classList.remove("open"); authState.authed=true; updateAuthBtn(); init2(); }
      else if(j.need_2fa){ LQ("#lg-codefield").style.display="block"; LQ("#lg-code").focus();
        LQ("#lg-result").className="lg-msg"+(j.error?" ko":""); LQ("#lg-result").textContent=j.error||"Entre le code de ton application 2FA."; }
      else { LQ("#lg-result").className="lg-msg ko"; LQ("#lg-result").textContent=j.error||"Échec de connexion."; }
    }).catch(function(){ btn.disabled=false; btn.textContent="Se connecter"; LQ("#lg-result").className="lg-msg ko"; LQ("#lg-result").textContent="Service injoignable."; });
  }
  LQ("#lg-go").addEventListener("click", doLogin);
  loginOv.addEventListener("keydown", function(e){ if(e.key==="Enter"){ e.preventDefault(); doLogin(); } });

  /* ---------- MODALE PARAMÈTRES ---------- */
  var sov = el(`
  <div class="cfg-page" role="dialog" aria-modal="true">
    <div class="cfg-shell">
      <aside class="cfg-side">
        <div class="cfg-brand"><img id="cfg-logo" alt="" src="/favicon.png?v=0" onerror="this.style.display='none'"><span>Configuration</span></div>
        <nav class="cfg-nav">
          <button class="cfg-tab active" type="button" data-tab="apparence">Apparence</button>
          <button class="cfg-tab" type="button" data-tab="cron">Planification</button>
          <button class="cfg-tab" type="button" data-tab="logs">Logs</button>
          <button class="cfg-tab" type="button" data-tab="icones">Icônes</button>
          <button class="cfg-tab" type="button" data-tab="stats">Statistiques</button>
          <button class="cfg-tab" type="button" data-tab="securite">Sécurité</button>
          <button class="cfg-tab" type="button" data-tab="alertes">Alertes</button>
        </nav>
        <button class="av-btn ghost cfg-back" type="button" id="cfg-back">← Retour au dashboard</button>
      </aside>
      <main class="cfg-main">
        <div class="av-result" id="se-result"></div>

        <section class="cfg-sec active" data-sec="apparence">
          <h2>Apparence & général</h2>
          <div class="av-field"><label>Nom du dashboard</label><input id="se-name" type="text" placeholder="MALINOIS"></div>
          <div class="av-field"><label>URL du site (lien du titre, optionnel)</label><input id="se-url" type="text" placeholder="https://…"></div>
          <div class="av-field"><label>Logo / favicon (favicon généré automatiquement)</label>
            <div class="av-fav"><img id="se-favimg" alt="" src="/favicon.png?v=0" onerror="this.style.visibility='hidden'"><input id="se-favfile" type="file" accept="image/*"></div>
            <button class="av-btn ghost" type="button" id="se-favdel" style="margin-top:8px;display:none">Supprimer le logo</button></div>
          <div class="av-coltheme">
            <div class="av-ct-item"><label for="se-accent">Colorisation</label><input id="se-accent" type="color" value="#2d7a4f" class="av-ct-color"></div>
            <div class="av-ct-item"><label for="se-dark">Thème sombre par défaut</label><label class="av-switch"><input type="checkbox" id="se-dark"><span class="av-sw-track"><span class="av-sw-thumb"></span></span></label></div>
          </div>
          <div class="av-field" style="margin-top:16px"><label>CSS personnalisé (avancé)</label>
            <textarea id="se-css" rows="7" spellcheck="false" placeholder=":root{ --ok:#e0892b; }"></textarea>
            <p class="av-hint">Injecté en direct dans la page. Laisse vide pour le style par défaut.</p></div>
          <div class="cfg-actions"><button class="av-btn save" type="button" id="se-save">Enregistrer</button></div>
        </section>

        <section class="cfg-sec" data-sec="cron">
          <h2>Planification des visites (cron)</h2>
          <p class="av-hint" style="margin:-8px 0 16px">Définis quand le bot effectue ses visites automatiques. La tâche est inscrite dans le crontab du conteneur.</p>
          <div class="av-field">
            <label>Horaire & fréquence</label>
            <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:6px">
              <span class="av-hint">À</span>
              <input id="cr-hour" type="number" min="0" max="23" value="6" style="width:64px;background:rgba(130,130,130,.08);border:1px solid var(--border);border-radius:8px;padding:7px 8px;color:inherit;font:13px ui-monospace,monospace">
              <span class="av-hint">h</span>
              <input id="cr-min" type="number" min="0" max="59" value="0" style="width:64px;background:rgba(130,130,130,.08);border:1px solid var(--border);border-radius:8px;padding:7px 8px;color:inherit;font:13px ui-monospace,monospace">
              <select id="cr-mode" style="background:rgba(130,130,130,.08);border:1px solid var(--border);border-radius:8px;padding:7px 8px;color:inherit">
                <option value="interval">tous les N jours</option>
                <option value="daily">tous les jours</option>
                <option value="weekdays">jours choisis</option>
              </select>
              <span id="cr-intvwrap" class="av-hint">tous les <input id="cr-intv" type="number" min="1" max="60" value="1" style="width:56px;background:rgba(130,130,130,.08);border:1px solid var(--border);border-radius:8px;padding:7px 8px;color:inherit;font:13px ui-monospace,monospace"> jour(s)</span>
            </div>
            <div id="cr-dows" style="display:none;gap:8px;flex-wrap:wrap;margin-top:8px">
              <label class="av-check" style="margin:0"><input type="checkbox" class="cr-dow" value="1"><span>Lun</span></label>
              <label class="av-check" style="margin:0"><input type="checkbox" class="cr-dow" value="2"><span>Mar</span></label>
              <label class="av-check" style="margin:0"><input type="checkbox" class="cr-dow" value="3"><span>Mer</span></label>
              <label class="av-check" style="margin:0"><input type="checkbox" class="cr-dow" value="4"><span>Jeu</span></label>
              <label class="av-check" style="margin:0"><input type="checkbox" class="cr-dow" value="5"><span>Ven</span></label>
              <label class="av-check" style="margin:0"><input type="checkbox" class="cr-dow" value="6"><span>Sam</span></label>
              <label class="av-check" style="margin:0"><input type="checkbox" class="cr-dow" value="0"><span>Dim</span></label>
            </div>
            <p class="av-hint" style="margin:14px 0 0">Aperçu : <code id="cr-preview" style="background:rgba(130,130,130,.12);padding:2px 6px;border-radius:5px">—</code></p>
            <p class="av-hint" style="margin:4px 0 0">Crontab actif : <code id="cr-current" style="background:rgba(130,130,130,.12);padding:2px 6px;border-radius:5px">—</code></p>
          </div>
          <div class="cfg-actions"><button class="av-btn save" type="button" id="cr-save">Enregistrer la planification</button><span id="cr-msg" class="av-hint" style="margin-left:8px"></span></div>
        </section>

        <section class="cfg-sec" data-sec="logs">
          <h2>Logs</h2>
          <div class="cfg-toolrow"><select id="lg-file"></select><button class="av-btn ghost" type="button" id="lg-reload">Recharger</button><select id="lg-theme" title="Couleur du terminal"><option value="">Sombre (défaut)</option><option value="lt-green">Vert terminal</option><option value="lt-amber">Ambre</option><option value="lt-blue">Bleu nuit</option><option value="lt-light">Clair</option></select><label class="av-switch-row" style="margin:0 0 0 6px"><span class="av-switch"><input type="checkbox" id="lg-live"><span class="av-sw-track"><span class="av-sw-thumb"></span></span></span><span>Live</span></label></div>
          <pre class="cfg-pre" id="lg-out">…</pre>
        </section>

        <section class="cfg-sec" data-sec="icones">
          <h2>Icônes des trackers</h2>
          <p class="av-hint">Récupère le favicon manquant de chaque site depuis son domaine (le bot a accès à Internet). Les icônes déjà présentes sont conservées, sauf si tu forces la mise à jour.</p>
          <label class="av-check"><input type="checkbox" id="ic-force"><span>Forcer (re-télécharger même celles déjà présentes)</span></label>
          <div class="cfg-actions"><button class="av-btn save" type="button" id="ic-run">Mettre à jour les icônes</button></div>
          <pre class="cfg-pre" id="ic-out" style="display:none"></pre>
        </section>

        <section class="cfg-sec" data-sec="stats">
          <h2>Statistiques</h2>
          <p class="av-hint">Réactualise les stats en cas d'échec (N/A). « Réactualiser » revisite le site ; « Inspecter » montre ce que le bot reçoit réellement.</p>
          <div class="cfg-actions"><button class="av-btn save" type="button" id="st-all">Tout réactualiser</button><span class="av-hint" id="st-allnote"></span></div>
          <div class="cfg-list" id="st-list"></div>
        </section>

        <section class="cfg-sec" data-sec="securite">
          <h2>Sécurité (connexion + 2FA)</h2>
          <div id="se-pwblock">
            <div class="av-field" id="se-curblock" style="display:none"><label>Mot de passe actuel</label><input id="se-cur" type="password" autocomplete="current-password"></div>
            <div class="av-field"><label id="se-newlabel">Définir un mot de passe</label><input id="se-new" type="password" autocomplete="new-password" placeholder="min. 8 caractères"></div>
            <div id="se-pwmeter" style="margin:-4px 0 12px;display:none">
              <div style="height:6px;border-radius:4px;background:rgba(130,130,130,.18);overflow:hidden"><div id="se-pwbar" style="height:100%;width:0;border-radius:4px;transition:width .2s ease,background .2s ease"></div></div>
              <p class="av-hint" id="se-pwlabel" style="margin:5px 0 0"></p>
            </div>
            <div class="av-field"><label>Confirmer le mot de passe</label><input id="se-new2" type="password" autocomplete="new-password" placeholder="min. 8 caractères"></div>
            <p class="av-hint" id="se-pwmatch" style="margin:-6px 0 10px"></p>
            <button class="av-btn save" type="button" id="se-pwbtn">Enregistrer le mot de passe</button>
          </div>
          <div id="se-2fablock" style="margin-top:18px;display:none">
            <p class="av-hint" id="se-2fastate" style="margin:0 0 8px"></p>
            <div id="se-2fasetup" style="display:none">
              <p class="av-hint" style="margin:0 0 6px">Scanne ce code dans ton app (ou saisis le secret), puis entre le code à 6 chiffres :</p>
              <div class="av-field"><label>Secret</label><input id="se-2fasecret" type="text" readonly></div>
              <div class="av-field"><label>Code de vérification</label><input id="se-2facode" inputmode="numeric" placeholder="123456"></div>
            </div>
            <button class="av-btn save" type="button" id="se-2fabtn">Activer le 2FA</button>
          </div>
          <div id="se-tlsblock" style="margin-top:22px;border-top:1px solid var(--border,#2a3140);padding-top:16px">
            <label class="av-switch-row" style="margin-bottom:2px"><span class="av-switch"><input type="checkbox" id="se-tls-on"><span class="av-sw-track"><span class="av-sw-thumb"></span></span></span><span>HTTPS — chiffrer l'accès au dashboard</span></label>
            <p class="av-hint" id="se-tls-state" style="margin:4px 0 8px">…</p>
            <div class="av-hint" id="se-tls-cert" style="margin:0 0 10px"></div>
            <div style="display:flex;gap:8px;flex-wrap:wrap">
              <button class="av-btn ghost" type="button" id="se-tls-gen">Générer un certificat local (auto-signé)</button>
              <button class="av-btn ghost" type="button" id="se-tls-import">Importer un certificat…</button>
              <button class="av-btn ghost" type="button" id="se-tls-certbot">Let's Encrypt (domaine public)…</button>
            </div>
            <div id="se-tls-certbotbox" style="display:none;margin-top:10px;border:1px solid var(--border,#2a3140);border-radius:8px;padding:12px">
              <p class="av-hint" style="margin:0 0 10px">Nécessite un <b>vrai nom de domaine public</b> pointant vers ce conteneur, avec le <b>port 80 joignable depuis Internet</b> (validation HTTP-01). Le renouvellement est ensuite automatique.</p>
              <div class="av-field"><label>Domaine</label><input id="se-tls-domain" type="text" spellcheck="false" placeholder="ex. malinois.mondomaine.fr"></div>
              <div class="av-field"><label>Email (avis d'expiration Let's Encrypt)</label><input id="se-tls-email" type="email" spellcheck="false" placeholder="toi@exemple.fr"></div>
              <label class="av-check" style="margin:2px 0 10px"><input type="checkbox" id="se-tls-staging"><span>Mode test (staging) — certificat non reconnu, pour vérifier sans consommer le quota</span></label>
              <button class="av-btn save" type="button" id="se-tls-certbot-go">Obtenir le certificat</button>
            </div>
            <div id="se-tls-genbox" style="display:none;margin-top:10px;border:1px solid var(--border,#2a3140);border-radius:8px;padding:12px">
              <p class="av-hint" style="margin:0 0 10px">Renseigne les informations du certificat auto-signé.</p>
              <div class="av-field"><label>Nom commun (CN) — hôte principal</label><input id="se-tls-cn" type="text" spellcheck="false" placeholder="ex. malinois.lan ou l'IP"></div>
              <div class="av-field"><label>Noms alternatifs (SAN) — IP/domaines séparés par des virgules</label><input id="se-tls-san" type="text" spellcheck="false" placeholder="ex. 192.168.0.10, malinois.lan"></div>
              <div class="av-field"><label>Organisation (O) — optionnel</label><input id="se-tls-org" type="text" spellcheck="false" placeholder="ex. Homelab"></div>
              <div class="av-field"><label>Pays (C) — code 2 lettres, optionnel</label><input id="se-tls-country" type="text" spellcheck="false" maxlength="2" placeholder="FR" style="max-width:90px"></div>
              <div class="av-field"><label>Validité (jours)</label><input id="se-tls-days" type="number" min="1" max="3650" value="825" style="max-width:120px"></div>
              <button class="av-btn save" type="button" id="se-tls-gen-go">Générer le certificat</button>
            </div>
            <div id="se-tls-importbox" style="display:none;margin-top:10px;border:1px solid var(--border,#2a3140);border-radius:8px;padding:12px">
              <div class="av-field"><label>Certificat (PEM — fullchain)</label><textarea id="se-tls-cert-in" rows="4" spellcheck="false" placeholder="-----BEGIN CERTIFICATE-----&#10;…"></textarea></div>
              <div class="av-field"><label>Clé privée (PEM)</label><textarea id="se-tls-key-in" rows="4" spellcheck="false" placeholder="-----BEGIN PRIVATE KEY-----&#10;…"></textarea></div>
              <button class="av-btn save" type="button" id="se-tls-import-save">Valider et installer</button>
            </div>
            <p class="av-hint" id="se-tls-msg" style="margin:8px 0 0"></p>
          </div>
        </section>
        <section class="cfg-sec" data-sec="alertes">
          <h2>Alertes &amp; notifications</h2>
          <p class="av-hint" style="margin:-4px 0 14px">Reçois une notification quand une visite échoue. Active un ou plusieurs canaux, puis teste l'envoi.</p>

          <div class="al-block">
            <label class="av-switch-row"><span class="av-switch"><input type="checkbox" id="al-em-on"><span class="av-sw-track"><span class="av-sw-thumb"></span></span></span><span>E-mail (SMTP)</span></label>
            <div style="margin-top:10px">
              <div class="av-field"><label>Serveur SMTP</label><input id="al-em-host" type="text" spellcheck="false" placeholder="ex. smtp.gmail.com"></div>
              <div style="display:flex;gap:10px;flex-wrap:wrap">
                <div class="av-field" style="flex:1;min-width:90px"><label>Port</label><input id="al-em-port" type="number" min="1" max="65535" placeholder="587"></div>
                <div class="av-field" style="flex:2;min-width:150px"><label>Sécurité</label><select id="al-em-sec"><option value="starttls">STARTTLS (587)</option><option value="ssl">SSL/TLS (465)</option><option value="none">Aucune</option></select></div>
              </div>
              <div class="av-field"><label>Utilisateur</label><input id="al-em-user" type="text" spellcheck="false" autocomplete="off" placeholder="souvent ton adresse e-mail"></div>
              <div class="av-field"><label>Mot de passe <span class="al-set" id="al-em-pwset"></span></label><input id="al-em-pass" type="password" autocomplete="new-password" placeholder="laisser vide pour conserver"></div>
              <div class="av-field"><label>Expéditeur (From)</label><input id="al-em-from" type="text" spellcheck="false" placeholder="malinois@mondomaine.fr"></div>
              <div class="av-field"><label>Destinataire(s) — séparés par des virgules</label><input id="al-em-to" type="text" spellcheck="false" placeholder="moi@exemple.fr"></div>
              <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-top:4px"><button class="av-btn save" type="button" id="al-em-save">Enregistrer</button><button class="av-btn ghost" type="button" id="al-em-test">Tester l'e-mail</button><span class="av-hint" id="al-em-msg"></span></div>
            </div>
          </div>

          <div class="al-block">
            <label class="av-switch-row"><span class="av-switch"><input type="checkbox" id="al-tg-on"><span class="av-sw-track"><span class="av-sw-thumb"></span></span></span><span>Telegram</span></label>
            <div style="margin-top:10px">
              <p class="av-hint" style="margin:0 0 8px">Crée un bot via @BotFather pour le token, puis récupère ton chat_id (via @userinfobot).</p>
              <div class="av-field"><label>Token du bot <span class="al-set" id="al-tg-tokset"></span></label><input id="al-tg-token" type="password" autocomplete="off" spellcheck="false" placeholder="laisser vide pour conserver"></div>
              <div class="av-field"><label>Chat ID</label><input id="al-tg-chat" type="text" spellcheck="false" placeholder="ex. 123456789"></div>
              <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-top:4px"><button class="av-btn save" type="button" id="al-tg-save">Enregistrer</button><button class="av-btn ghost" type="button" id="al-tg-test">Tester Telegram</button><span class="av-hint" id="al-tg-msg"></span></div>
            </div>
          </div>

          <div class="al-block">
            <label class="av-switch-row"><span class="av-switch"><input type="checkbox" id="al-wh-on"><span class="av-sw-track"><span class="av-sw-thumb"></span></span></span><span>Webhook / ntfy (ou passerelle SMS)</span></label>
            <div style="margin-top:10px">
              <p class="av-hint" style="margin:0 0 8px">POST du message (titre dans l'en-tête <code>Title</code>). Compatible ntfy et toute passerelle SMS acceptant un POST HTTP.</p>
              <div class="av-field"><label>URL</label><input id="al-wh-url" type="text" spellcheck="false" placeholder="https://ntfy.sh/mon-topic"></div>
              <div class="av-field"><label>En-tête Authorization <span class="al-set" id="al-wh-authset"></span> — optionnel</label><input id="al-wh-auth" type="password" autocomplete="off" spellcheck="false" placeholder="ex. Bearer xxx (laisser vide pour conserver)"></div>
              <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-top:4px"><button class="av-btn save" type="button" id="al-wh-save">Enregistrer</button><button class="av-btn ghost" type="button" id="al-wh-test">Tester le webhook</button><span class="av-hint" id="al-wh-msg"></span></div>
            </div>
          </div>

          <div class="al-block">
            <label class="av-switch-row"><span class="av-switch"><input type="checkbox" id="al-br-on"><span class="av-sw-track"><span class="av-sw-thumb"></span></span></span><span>Notifications navigateur</span></label>
            <div style="margin-top:10px">
              <p class="av-hint" style="margin:0 0 8px">Affiche une notification système quand le dashboard est ouvert dans ce navigateur et qu'un site passe en échec. L'autorisation est demandée par navigateur/appareil.</p>
              <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-top:4px"><button class="av-btn ghost" type="button" id="al-br-test">Tester la notification</button><span class="av-hint" id="al-br-msg"></span></div>
            </div>
          </div>

          <div style="margin:4px 0 14px">
            <p class="av-hint" style="margin:0 0 9px">Quelles alertes envoyer (à chaque visite planifiée ou rafraîchissement) — enregistré automatiquement :</p>
            <label class="av-check" style="margin:0 0 7px"><input type="checkbox" id="al-onfail"><span>Un site passe en échec</span></label>
            <label class="av-check" style="margin:0 0 7px"><input type="checkbox" id="al-onrecover"><span>Un site se rétablit (de nouveau OK)</span></label>
            <label class="av-check" style="margin:0"><input type="checkbox" id="al-oneach"><span>Résumé après chaque visite (même sans changement)</span></label>
            <label class="av-check" style="margin:7px 0 0"><input type="checkbox" id="al-onstatsna"><span>Statistiques non récupérées (upload = N/A — probable cookie expiré)</span></label>
          </div>

          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="av-btn ghost" type="button" id="al-test">Tester tous les canaux actifs</button>
          </div>
          <p class="av-hint" id="al-msg" style="margin:10px 0 0"></p>
        </section>
      </main>
    </div>
  </div>`);
  document.body.appendChild(sov);
  function SQ(s){return sov.querySelector(s);}
  bindCron();
  bindAlerts();

  function setTab(tab){
    sov.querySelectorAll(".cfg-tab").forEach(function(x){ x.classList.toggle("active", x.getAttribute("data-tab")===tab); });
    sov.querySelectorAll(".cfg-sec").forEach(function(s){ s.classList.toggle("active", s.getAttribute("data-sec")===tab); });
    var rr=SQ("#se-result"); if(rr){ rr.className="av-result"; rr.textContent=""; }
    if(tab!=="logs"){ stopLive(); var lv=SQ("#lg-live"); if(lv) lv.checked=false; }
    if(tab==="logs") loadLogs();
    if(tab==="stats") buildStatsList();
  }
  function openSettings(){
    fetch("/settings").then(function(r){return r.json();}).then(function(j){
      var s = (j&&j.ok)?j.settings:settings;
      SQ("#se-name").value = s.name||""; SQ("#se-url").value = s.url||"";
      SQ("#se-accent").value = s.accent||"#e0892b";
      SQ("#se-dark").checked = !!s.dark; SQ("#se-css").value = s.css||"";
      var img=SQ("#se-favimg"); img.style.visibility = s.favicon?"visible":"hidden";
      var clogo=SQ("#cfg-logo"); if(s.favicon){ clogo.style.display="block"; clogo.src="/favicon.png?v="+Date.now(); } else clogo.style.display="none";
      if (s.favicon) img.src = "/favicon.png?v="+Date.now();
      var favdel=SQ("#se-favdel"); if(favdel) favdel.style.display = s.favicon?"inline-flex":"none";
      SQ("#se-result").className="av-result"; SQ("#se-favfile").value="";
      refreshSecurityUI();
      loadCron();
      loadAlerts();
      setTab("apparence");
      sov.classList.add("open"); document.body.style.overflow="hidden";
    }).catch(function(){ sov.classList.add("open"); });
  }
  function closeSettings(){ sov.classList.remove("open"); document.body.style.overflow=""; try{ stopLive(); var lv=SQ("#lg-live"); if(lv) lv.checked=false; applySettings(settings); }catch(e){} }
  function readFile(file){ return new Promise(function(res,rej){var r=new FileReader();r.onload=function(){res(r.result);};r.onerror=rej;r.readAsDataURL(file);}); }

  SQ("#se-favfile").addEventListener("change", function(){
    var f=this.files&&this.files[0]; if(!f) return;
    readFile(f).then(function(d){ var img=SQ("#se-favimg"); img.src=d; img.style.visibility="visible"; });
  });
  bSettings.addEventListener("click", openSettings);
  SQ("#cfg-back").addEventListener("click", closeSettings);
  SQ("#se-accent").addEventListener("input", function(){ document.documentElement.style.setProperty("--ok", this.value, "important"); });
  sov.querySelectorAll(".cfg-tab").forEach(function(b){
    b.addEventListener("click", function(){ setTab(b.getAttribute("data-tab")); });
  });
  SQ("#se-save").addEventListener("click", function(){
    var btn=this; btn.disabled=true; btn.textContent="…";
    var payload={name:SQ("#se-name").value.trim(),url:SQ("#se-url").value.trim(),
      accent:SQ("#se-accent").value,dark:SQ("#se-dark").checked,
      css:SQ("#se-css").value};
    var f=SQ("#se-favfile").files&&SQ("#se-favfile").files[0];
    var chain = f ? readFile(f).then(function(d){return post("/favicon",{data:d});}) : Promise.resolve({ok:true});
    chain.then(function(){ return post("/settings", payload); }).then(function(j){
      btn.disabled=false; btn.textContent="Enregistrer";
      if (j&&j.ok){ applySettings(j.settings); if(f){ settings.favicon=true; var cl=SQ("#cfg-logo"); cl.style.display="block"; cl.src="/favicon.png?v="+Date.now(); var fd=SQ("#se-favdel"); if(fd) fd.style.display="inline-flex"; var fi=SQ("#se-favimg"); fi.style.visibility="visible"; fi.src="/favicon.png?v="+Date.now(); }
        SQ("#se-result").className="av-result show ok"; SQ("#se-result").textContent="Enregistré."; }
      else { SQ("#se-result").className="av-result show ko"; SQ("#se-result").textContent="Erreur : "+((j&&j.error)||"inconnue"); }
    }).catch(function(){ btn.disabled=false; btn.textContent="Enregistrer";
      SQ("#se-result").className="av-result show ko"; SQ("#se-result").textContent="Service injoignable."; });
  });
  SQ("#se-favdel").addEventListener("click", function(){
    var btn=this; btn.disabled=true;
    post("/favicon", {delete:true}).then(function(j){
      btn.disabled=false;
      if(j&&j.ok){
        settings.favicon=false; applySettings(settings);
        var im=SQ("#se-favimg"); im.style.visibility="hidden"; im.removeAttribute("src");
        var cl=SQ("#cfg-logo"); if(cl) cl.style.display="none";
        SQ("#se-favfile").value=""; btn.style.display="none";
        SQ("#se-result").className="av-result show ok"; SQ("#se-result").textContent="Logo supprimé.";
      } else { SQ("#se-result").className="av-result show ko"; SQ("#se-result").textContent="Erreur : "+((j&&j.error)||"inconnue"); }
    }).catch(function(){ btn.disabled=false; SQ("#se-result").className="av-result show ko"; SQ("#se-result").textContent="Service injoignable."; });
  });

  /* ---------- SECTIONS DE CONFIG (logs / icônes / stats) ---------- */
  function colorizeLog(text){
    return (text||"").split("\n").map(function(ln){
      var m=ln.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(\S+)\s+([\s\S]*)$/);
      if(!m){ return '<span class="lg-dim">'+esc(ln)+'</span>'; }
      var ts=m[1], lvl=m[2], msg=m[3];
      var lvlCls="lg-info";
      if(/ECHEC|ERROR|ERREUR|KO|FAIL/i.test(lvl)) lvlCls="lg-err";
      else if(/WARN|ATTEN/i.test(lvl)) lvlCls="lg-warn";
      else if(/^OK$/i.test(lvl)) lvlCls="lg-ok";
      var msgCls="";
      if(/(echec|échec|erreur|error|invalide|introuvable|fail|refus|\bKO\b|N\/A)/i.test(msg)) msgCls="lg-err";
      else if(/(\bOK\b|reussie|réussie|succes|succès)/i.test(msg)) msgCls="lg-ok";
      var emsg=esc(msg).replace(/\[([^\]]+)\]/g,'<span class="lg-site">[$1]</span>');
      if(msgCls) emsg='<span class="'+msgCls+'">'+emsg+'</span>';
      return '<span class="lg-ts">'+esc(ts)+'</span> <span class="'+lvlCls+'">'+esc(lvl)+'</span> '+emsg;
    }).join("\n");
  }
  var lgBusy=false;
  function loadLogs(file){
    var out=SQ("#lg-out"); if(!out.innerHTML) out.textContent="Chargement…";
    // Ne pas réécrire le contenu pendant que l'utilisateur sélectionne du texte :
    // sinon le rafraîchissement (live) efface la sélection en cours.
    try{ var sel=window.getSelection(); if(sel && !sel.isCollapsed && sel.rangeCount && out.contains(sel.getRangeAt(0).commonAncestorContainer)){ return; } }catch(e){}
    if(lgBusy) return;   // évite d'empiler des requêtes /logs (sature les connexions)
    lgBusy=true;
    fetch("/logs"+(file?("?file="+encodeURIComponent(file)):"")).then(function(r){return r.json();}).then(function(j){
      lgBusy=false;
      if(!j||!j.ok){ out.textContent="(indisponible)"; return; }
      var sel=SQ("#lg-file");
      if(sel && !sel.dataset.filled && j.files && j.files.length){
        sel.innerHTML=j.files.map(function(f){return '<option'+(f===j.file?' selected':'')+'>'+esc(f)+'</option>';}).join("");
        sel.dataset.filled="1";
      }
      var atBottom = (out.scrollHeight - out.scrollTop - out.clientHeight) < 40;
      out.innerHTML = (j.log && j.log.trim()) ? colorizeLog(j.log) : '<span class="lg-dim">(journal vide)</span>';
      if(atBottom) out.scrollTop = out.scrollHeight;
    }).catch(function(){ lgBusy=false; out.textContent="(service injoignable)"; });
  }
  SQ("#lg-reload").addEventListener("click", function(){ loadLogs(SQ("#lg-file").value); });
  SQ("#lg-file").addEventListener("change", function(){ loadLogs(this.value); });
  var lgTimer=null;
  function stopLive(){ if(lgTimer){ clearInterval(lgTimer); lgTimer=null; } }
  function startLive(){ stopLive(); loadLogs(SQ("#lg-file").value); lgTimer=setInterval(function(){ loadLogs(SQ("#lg-file").value); }, 3000); }
  SQ("#lg-live").addEventListener("change", function(){ if(this.checked) startLive(); else stopLive(); });
  (function(){ var sel=SQ("#lg-theme"), out=SQ("#lg-out"); if(!sel||!out) return;
    function applyLogTheme(v){ out.className=out.className.replace(/\blt-\S+/g,"").replace(/\s+/g," ").trim(); if(v) out.classList.add(v); }
    var saved=""; try{ saved=localStorage.getItem("malinois_log_theme")||""; }catch(e){}
    sel.value=saved; applyLogTheme(saved);
    sel.addEventListener("change", function(){ try{ localStorage.setItem("malinois_log_theme", this.value); }catch(e){} applyLogTheme(this.value); });
  })();

  function siteDomain(s){
    var url=(s.url||"").toLowerCase(), best=null;
    TRACKERS.forEach(function(t){ if(t.d&&url.indexOf(t.d.toLowerCase())>=0){ if(!best||t.d.length>best.d.length) best=t; }});
    if(best) return best.d;
    try{ return new URL(/^https?:/.test(s.url)?s.url:("https://"+s.url)).hostname; }catch(e){ return ""; }
  }
  SQ("#ic-run").addEventListener("click", function(){
    var btn=this, out=SQ("#ic-out"); btn.disabled=true; var old=btn.textContent; btn.textContent="Récupération…";
    var targets=[];
    (lastSites||[]).forEach(function(s){ var d=siteDomain(s); if(d) targets.push({slug:(s.name||"").toLowerCase(), domain:d}); });
    post("/favsync",{targets:targets, force:SQ("#ic-force").checked}).then(function(j){
      btn.disabled=false; btn.textContent=old; out.style.display="block";
      if(!j||!j.ok){ out.textContent="Erreur : "+((j&&j.error)||"inconnue"); return; }
      var got=j.results.filter(function(r){return r.ok&&!r.skipped;}).length;
      var sk=j.results.filter(function(r){return r.skipped;}).length;
      var ko=j.results.filter(function(r){return !r.ok;});
      out.textContent="Récupérées : "+got+"   ·   déjà présentes : "+sk+(ko.length?("   ·   échecs : "+ko.map(function(r){return r.slug;}).join(", ")):"");
      iconBust=Date.now(); refresh();
    }).catch(function(){ btn.disabled=false; btn.textContent=old; out.style.display="block"; out.textContent="Service injoignable."; });
  });

  function buildStatsList(){
    var box=SQ("#st-list"); box.innerHTML="";
    (lastSites||[]).slice().sort(function(a,b){return (a.name||"").localeCompare(b.name||"");}).forEach(function(s){
      var nm=(s.name||""), slug=nm.toLowerCase();
      var row=el('<div class="cfg-row"><span class="nm">'+esc(nm)+'</span></div>');
      var bR=el('<button class="av-btn ghost" type="button">Réactualiser</button>');
      var bI=el('<button class="av-btn ghost" type="button">Inspecter</button>');
      var bRes=el('<button class="av-btn ghost" type="button" title="Restaurer la config de stats d\'avant ta dernière modification">↩ Restaurer</button>');
      var note=el('<span class="av-hint" style="margin-left:8px"></span>');
      bR.addEventListener("click", function(){
        bR.disabled=true; var o=bR.textContent; bR.innerHTML='<span class="av-spin"></span>Réactualisation…';
        post("/revisit",{slug:slug}).then(function(){ bR.disabled=false; bR.textContent=o; refresh(); })
          .catch(function(){ bR.disabled=false; bR.textContent=o; });
      });
      bI.addEventListener("click", function(){ openInspect(slug, nm); });
      bRes.addEventListener("click", function(){
        if(!window.confirm("Restaurer la sauvegarde (config d'avant ta dernière modification) de « "+nm+" » ?")) return;
        bRes.disabled=true; var o=bRes.textContent; bRes.innerHTML='<span class="av-spin"></span>'; note.style.color=""; note.textContent="";
        post("/siterestore",{slug:slug},12000).then(function(j){
          bRes.disabled=false; bRes.textContent=o;
          if(!j||!j.ok){ note.style.color="var(--ko,#e0796f)"; note.textContent=(j&&j.error)||"Erreur"; return; }
          note.style.color="var(--good,#22c55e)"; note.textContent="✓ restauré ["+((j.keys&&j.keys.length)?j.keys.join(", "):"")+"]";
          post("/revisit",{slug:slug}).catch(function(){});
          refresh(); setTimeout(refresh,6000); setTimeout(refresh,15000);
        }).catch(function(){ bRes.disabled=false; bRes.textContent=o; note.style.color="var(--ko,#e0796f)"; note.textContent="Service injoignable."; });
      });
      row.appendChild(bR); row.appendChild(bI); row.appendChild(bRes); row.appendChild(note); box.appendChild(row);
    });
    if(!(lastSites||[]).length) box.innerHTML='<p class="av-hint">Aucun site pour l\'instant.</p>';
  }
  SQ("#st-all").addEventListener("click", function(){
    var btn=this; btn.disabled=true; var o=btn.textContent; btn.innerHTML='<span class="av-spin"></span>En cours…';
    SQ("#st-allnote").textContent="Réactualisation de tous les sites… (peut prendre plusieurs minutes)";
    post("/refreshall",{}).then(function(){
      var poll=setInterval(function(){
        fetch("/refreshstate").then(function(r){return r.json();}).then(function(st){
          if(st && !st.running){ clearInterval(poll); btn.disabled=false; btn.textContent=o; SQ("#st-allnote").textContent="Terminé."; refresh(); }
        }).catch(function(){});
      }, 4000);
    }).catch(function(){ btn.disabled=false; btn.textContent=o; SQ("#st-allnote").textContent="Service injoignable."; });
  });

  function refreshSecurityUI(){
    var configured=authState.configured, twofa=authState.twofa;
    SQ("#se-curblock").style.display = configured ? "block" : "none";
    SQ("#se-newlabel").textContent = configured ? "Nouveau mot de passe" : "Définir un mot de passe";
    SQ("#se-cur").value=""; SQ("#se-new").value=""; SQ("#se-new2").value="";
    SQ("#se-pwmeter").style.display="none"; SQ("#se-pwmatch").textContent="";
    SQ("#se-2fablock").style.display = configured ? "block" : "none";
    SQ("#se-2fasetup").style.display="none"; SQ("#se-2facode").value="";
    SQ("#se-2fastate").textContent = twofa ? "2FA activé." : "2FA désactivé.";
    SQ("#se-2fabtn").textContent = twofa ? "Désactiver le 2FA" : "Activer le 2FA";
    SQ("#se-2fabtn").className = "av-btn "+(twofa?"ghost":"save"); SQ("#se-2fabtn").style.padding="8px 14px";
    loadTLS();
  }
  var tlsState=null;
  function loadTLS(){
    fetch("/tls/status").then(function(r){return r.json();}).then(function(j){
      if(!j||!j.ok) return;
      tlsState=j;
      SQ("#se-tls-on").checked = !!j.enabled;
      SQ("#se-tls-on").disabled = !j.has_cert;
      SQ("#se-tls-state").textContent = j.enabled
        ? "HTTPS actif."
        : (j.has_cert ? "Certificat prêt — active le toggle pour passer en HTTPS."
                      : "Aucun certificat. Génère-en un en local, ou importe le tien.");
      if(j.cert){
        var c=j.cert;
        SQ("#se-tls-cert").innerHTML = "Certificat : <b>"+esc(c.cn||"?")+"</b>"
          + (c.self_signed?" (auto-signé)":" — émis par "+esc(c.issuer||"?"))
          + "<br>Noms couverts : "+esc((c.san||[]).join(", ")||"—")
          + "<br>Expire : "+esc(c.not_after||"?");
      } else { SQ("#se-tls-cert").innerHTML=""; }
    }).catch(function(){});
  }
  function tlsMsg(txt,ok){ var m=SQ("#se-tls-msg"); m.style.color=ok?"var(--good,#22c55e)":"var(--ko,#e0796f)"; m.textContent=txt; }
  SQ("#se-tls-on").addEventListener("change", function(){
    var on=this.checked, self=this; self.disabled=true; tlsMsg(on?"Activation HTTPS…":"Désactivation…", true);
    post(on?"/tls/enable":"/tls/disable",{}).then(function(j){
      self.disabled=false;
      if(j&&j.ok){
        if(on){ tlsMsg("HTTPS activé. Bascule vers https:// (certificat auto-signé : ton navigateur affichera un avertissement à accepter une fois).", true);
          setTimeout(function(){ location.href=location.href.replace(/^http:/,"https:"); }, 1600); }
        else { tlsMsg("HTTPS désactivé — retour en HTTP.", true);
          setTimeout(function(){ location.href=location.href.replace(/^https:/,"http:"); }, 1200); }
        loadTLS();
      } else { self.checked=!on; tlsMsg("Échec : "+((j&&j.error)||"inconnue"), false); }
    }).catch(function(){ self.disabled=false; self.checked=!on; tlsMsg("Service injoignable.", false); });
  });
  SQ("#se-tls-gen").addEventListener("click", function(){
    var bx=SQ("#se-tls-genbox"); var open=(bx.style.display==="none");
    bx.style.display = open ? "block" : "none";
    if(open){
      SQ("#se-tls-importbox").style.display="none"; SQ("#se-tls-certbotbox").style.display="none";
      var ip=(tlsState&&tlsState.ct_ip)||location.hostname;
      if(!SQ("#se-tls-cn").value) SQ("#se-tls-cn").value=ip;
      if(!SQ("#se-tls-san").value) SQ("#se-tls-san").value=ip;
    }
  });
  SQ("#se-tls-gen-go").addEventListener("click", function(){
    var b=this, o=b.textContent; b.disabled=true; b.textContent="Génération…";
    post("/tls/selfsigned",{
      cn: SQ("#se-tls-cn").value.trim(),
      san: SQ("#se-tls-san").value.trim(),
      org: SQ("#se-tls-org").value.trim(),
      country: SQ("#se-tls-country").value.trim(),
      days: parseInt(SQ("#se-tls-days").value,10)||825
    }).then(function(j){
      b.disabled=false; b.textContent=o;
      if(j&&j.ok){ tlsMsg("Certificat auto-signé généré. Active le toggle HTTPS.", true);
        SQ("#se-tls-genbox").style.display="none"; loadTLS(); }
      else tlsMsg("Échec : "+((j&&j.error)||"inconnue"), false);
    }).catch(function(){ b.disabled=false; b.textContent=o; tlsMsg("Service injoignable.", false); });
  });
  SQ("#se-tls-import").addEventListener("click", function(){
    var bx=SQ("#se-tls-importbox"); var open=(bx.style.display==="none");
    bx.style.display = open ? "block" : "none";
    if(open){ SQ("#se-tls-genbox").style.display="none"; SQ("#se-tls-certbotbox").style.display="none"; }
  });
  SQ("#se-tls-import-save").addEventListener("click", function(){
    var b=this, o=b.textContent; b.disabled=true; b.textContent="Vérification…";
    post("/tls/import",{cert:SQ("#se-tls-cert-in").value, key:SQ("#se-tls-key-in").value}).then(function(j){
      b.disabled=false; b.textContent=o;
      if(j&&j.ok){ tlsMsg("Certificat importé et validé. Active le toggle HTTPS.", true);
        SQ("#se-tls-importbox").style.display="none"; SQ("#se-tls-cert-in").value=""; SQ("#se-tls-key-in").value=""; loadTLS(); }
      else tlsMsg("Échec : "+((j&&j.error)||"inconnue"), false);
    }).catch(function(){ b.disabled=false; b.textContent=o; tlsMsg("Service injoignable.", false); });
  });
  SQ("#se-tls-certbot").addEventListener("click", function(){
    var bx=SQ("#se-tls-certbotbox"); var open=(bx.style.display==="none");
    bx.style.display = open ? "block" : "none";
    if(open){ SQ("#se-tls-genbox").style.display="none"; SQ("#se-tls-importbox").style.display="none"; }
  });
  SQ("#se-tls-certbot-go").addEventListener("click", function(){
    var b=this, o=b.textContent; b.disabled=true; b.textContent="Demande en cours… (peut prendre ~30 s)";
    tlsMsg("Demande Let's Encrypt en cours…", true);
    post("/tls/certbot",{domain:SQ("#se-tls-domain").value.trim(), email:SQ("#se-tls-email").value.trim(), staging:SQ("#se-tls-staging").checked}).then(function(j){
      b.disabled=false; b.textContent=o;
      if(j&&j.ok){
        tlsMsg("Certificat Let's Encrypt obtenu et HTTPS activé pour "+(j.domain||"")+". Renouvellement automatique en place. Bascule vers https://…", true);
        SQ("#se-tls-certbotbox").style.display="none"; loadTLS();
        if(j.domain){ setTimeout(function(){ location.href="https://"+j.domain+"/"; }, 1800); }
      } else tlsMsg("Échec : "+((j&&j.error)||"inconnue"), false);
    }).catch(function(){ b.disabled=false; b.textContent=o; tlsMsg("Service injoignable (ou délai dépassé).", false); });
  });
  function pwStrength(p){
    var s=0;
    if(p.length>=8) s++;
    if(p.length>=12) s++;
    if(/[a-z]/.test(p) && /[A-Z]/.test(p)) s++;
    if(/[0-9]/.test(p)) s++;
    if(/[^A-Za-z0-9]/.test(p)) s++;
    var L=[{l:"Très faible",c:"#e0796f",p:15},{l:"Très faible",c:"#e0796f",p:22},
           {l:"Faible",c:"#e0a13f",p:42},{l:"Moyen",c:"#d8c23a",p:66},
           {l:"Bon",c:"#7bc46c",p:85},{l:"Fort",c:"#2d9d4f",p:100}][Math.min(s,5)];
    return {score:s,label:L.l,color:L.c,pct:L.p};
  }
  function updatePwMeter(){
    var p=SQ("#se-new").value, m=SQ("#se-pwmeter");
    if(!p){ m.style.display="none"; updatePwMatch(); return; }
    m.style.display="block";
    var st=pwStrength(p);
    SQ("#se-pwbar").style.width=st.pct+"%"; SQ("#se-pwbar").style.background=st.color;
    SQ("#se-pwlabel").textContent="Robustesse : "+st.label+(p.length<8?" — min. 8 caractères":"");
    SQ("#se-pwlabel").style.color=st.color;
    updatePwMatch();
  }
  function updatePwMatch(){
    var p=SQ("#se-new").value, c=SQ("#se-new2").value, el=SQ("#se-pwmatch");
    if(!c){ el.textContent=""; return; }
    if(p===c){ el.textContent="✓ Les mots de passe correspondent"; el.style.color="var(--good,#22c55e)"; }
    else { el.textContent="✗ Les mots de passe ne correspondent pas"; el.style.color="var(--ko,#e0796f)"; }
  }
  SQ("#se-new").addEventListener("input", updatePwMeter);
  SQ("#se-new2").addEventListener("input", updatePwMatch);
  SQ("#se-pwbtn").addEventListener("click", function(){
    var btn=this, np=SQ("#se-new").value, cp=SQ("#se-new2").value;
    function ko(t){ SQ("#se-result").className="av-result show ko"; SQ("#se-result").textContent=t; }
    if(np.length<8){ ko("Mot de passe trop court (min. 8 caractères)."); return; }
    if(pwStrength(np).score<3){ ko("Mot de passe trop faible — mélange majuscules, minuscules, chiffres et symboles, ou allonge-le."); return; }
    if(np!==cp){ ko("Les deux mots de passe ne correspondent pas."); return; }
    btn.disabled=true;
    post("/auth/password",{current:SQ("#se-cur").value,new:np}).then(function(j){
      btn.disabled=false;
      if(j.ok){ authState.configured=true; updateAuthBtn(); refreshSecurityUI();
        SQ("#se-result").className="av-result show ok"; SQ("#se-result").textContent="Mot de passe enregistré."; }
      else ko("Erreur : "+(j.error||""));
    }).catch(function(){ btn.disabled=false; ko("Service injoignable."); });
  });
  SQ("#se-2fabtn").addEventListener("click", function(){
    var btn=this;
    if(authState.twofa){ // désactiver
      btn.disabled=true;
      post("/auth/2fa/disable",{}).then(function(j){ btn.disabled=false; if(j.ok){ authState.twofa=false; refreshSecurityUI(); } });
      return;
    }
    if(SQ("#se-2fasetup").style.display==="none"){ // lancer la config
      btn.disabled=true;
      post("/auth/2fa/init",{}).then(function(j){ btn.disabled=false;
        if(j.ok){ SQ("#se-2fasecret").value=j.secret; SQ("#se-2fasetup").style.display="block"; btn.textContent="Confirmer le code"; SQ("#se-2facode").focus(); }
        else { SQ("#se-result").className="av-result show ko"; SQ("#se-result").textContent="Erreur : "+(j.error||""); }
      }).catch(function(){ btn.disabled=false; });
    } else { // confirmer le code
      btn.disabled=true;
      post("/auth/2fa/enable",{code:SQ("#se-2facode").value}).then(function(j){ btn.disabled=false;
        if(j.ok){ authState.twofa=true; refreshSecurityUI(); SQ("#se-result").className="av-result show ok"; SQ("#se-result").textContent="2FA activé."; }
        else { SQ("#se-result").className="av-result show ko"; SQ("#se-result").textContent="Erreur : "+(j.error||""); }
      }).catch(function(){ btn.disabled=false; });
    }
  });

  /* ---------- MODALE AJOUT / ÉDITION ---------- */
  var ov = el(`
  <div class="av-overlay"><div class="av-modal" role="dialog" aria-modal="true">
    <div class="av-head"><h2 id="av-title">Ajouter un site</h2><button class="av-x" type="button" aria-label="Fermer">×</button></div>
    <div class="av-body">
      <div class="av-field"><label id="av-namelabel">Tracker <span style="color:#6b7383">— tape le nom (ex. The Old School)</span></label>
        <input id="av-name" type="text" placeholder="The Old School…" autocomplete="off">
        <div class="av-ac" id="av-ac"></div></div>
      <p class="av-hint" id="av-manualrow" style="margin:-6px 0 4px">Pas dans la liste ? <a id="av-manual" href="#" style="color:#74d0d6">Configuration manuelle →</a></p>

      <div id="av-config" style="display:none">
        <div id="av-summary" class="av-summary" style="display:none"></div>
        <div class="av-row">
          <div class="av-field" id="av-userfield"><label id="av-userlabel">Identifiant</label><input id="av-user" type="text" autocomplete="off"></div>
          <div class="av-field"><label id="av-passlabel">Mot de passe</label><input id="av-pass" type="password" autocomplete="new-password"></div>
        </div>
        <p class="av-hint" id="av-authswitch" style="margin:-4px 0 10px"><a href="#" id="av-tocookie" style="color:#74d0d6">🍪 Le tracker bloque (captcha, Cloudflare…) ? Se connecter par cookies de session →</a></p>
        <div id="av-cookieblock" style="display:none">
          <div class="av-field"><label>Cookies de session</label><textarea id="av-cookies" rows="4" placeholder='Colle le JSON exporté ([{"name":"…","value":"…"}]) OU la chaîne brute « nom=valeur; nom2=valeur2 »'></textarea>
          <p class="av-hint" style="margin:6px 0 0">Connecte-toi au tracker en cochant <b>« Se souvenir de moi »</b> <i>avant</i> d'exporter, puis récupère <b>tous</b> les cookies du domaine — en particulier le cookie persistant (souvent <code>remember_*</code> ou <code>remember_web_*</code>). Sans lui, la session expire au bout de quelques heures et les stats repassent en N/A.</p></div>
          <div class="av-field"><label>User-Agent (celui du navigateur d'où viennent les cookies)</label><input id="av-ua" type="text" autocomplete="off" placeholder="Mozilla/5.0 ..."></div>
        </div>
        <div class="av-field" id="av-2farow" style="display:none"><label>Secret 2FA (base32)</label><input id="av-totp" type="text" placeholder="SECRET_BASE32 de ton app d'authentification" autocomplete="off"><p class="av-hint">Ce tracker demande un code 2FA. Colle ici le <b>secret</b> (la clé base32 affichée à l'activation du 2FA, ex. <code>JBSWY3DP…</code>) — pas un code à 6 chiffres : le bot tournant en continu, il génère lui-même le code à chaque visite.</p></div>
        <details class="av-adv" id="av-adv"><summary id="av-advsum">Configuration du tracker (modifier)</summary>
          <div class="av-field"><label>Domaine (sans https://)</label><input id="av-domain" type="text" placeholder="theoldschool.cc" autocomplete="off"></div>
          <div class="av-row">
            <div class="av-field"><label>Plateforme</label>
              <select id="av-platform">
                <option value="form">Form classique (POST)</option>
                <option value="unit3d">UNIT3D / Laravel</option>
                <option value="gazelle">Gazelle</option>
                <option value="aspnet">ASP.NET</option>
                <option value="xenforo">XenForo</option>
                <option value="symfony">Symfony</option>
                <option value="apijson">API JSON</option>
              </select></div>
            <div class="av-field"><label>Vérifier la connexion via</label>
              <select id="av-vmode"><option value="auto">Détection automatique</option><option value="kw">Mot-clé dans la page (HTML)</option><option value="url">Texte dans l'URL après login</option></select></div>
          </div>
          <div class="av-field"><label id="av-verifylabel">Mot-clé de succès</label><input id="av-verify" type="text" placeholder="(défaut : ton pseudo)" autocomplete="off"><p class="av-hint" id="av-verifyhint"></p></div>
          <div class="av-field"><label>Chemin de login</label><input id="av-path" type="text" placeholder="/login"></div>
          <div class="av-field"><label>Stats (JSON de regex appliquées au HTML connecté)</label><textarea id="av-stats" placeholder='{ "ratio": "Ratio:\\\\s*([\\\\d.]+)" }'></textarea><p class="av-hint" id="av-statshint">Laisse vide si tu ne veux pas de stats. Pré-rempli pour un tracker connu.</p></div>
          <div class="av-checks">
            <label class="av-check"><input type="checkbox" id="av-curl"><span>Cloudflare léger (curl_cffi)<small>empreinte TLS Firefox</small></span></label>
            <label class="av-check"><input type="checkbox" id="av-pw"><span>Captcha invisible (Playwright)<small>Firefox headless</small></span></label>
            <label class="av-check"><input type="checkbox" id="av-cf"><span>Challenge Cloudflare (Byparr)<small>conteneur Byparr requis</small></span></label>
          </div>
        </details>
      </div>
    </div>
    <div class="av-result" id="av-result"></div>
    <div class="av-foot"><button class="av-btn ghost" type="button" id="av-cancel">Annuler</button><button class="av-btn test" type="button" id="av-primary">Tester</button></div>
  </div></div>`);
  document.body.appendChild(ov);

  var cf = el(`
  <div class="av-overlay"><div class="av-modal small" role="dialog" aria-modal="true">
    <div class="av-head"><h2 id="av-cf-title">Confirmer</h2><button class="av-x" type="button" aria-label="Fermer">×</button></div>
    <div class="av-body"><p class="av-msg" id="av-cf-msg" style="margin:4px 0"></p></div>
    <div class="av-foot"><button class="av-btn ghost" type="button" id="av-cf-no">Annuler</button><button class="av-btn danger" type="button" id="av-cf-yes">Confirmer</button></div>
  </div></div>`);
  document.body.appendChild(cf);

  // modale d'inspection : montre le contenu brut (HTML/JSON) que le bot reçoit
  var iov = el(`
  <div class="av-overlay"><div class="av-modal" role="dialog" aria-modal="true" style="max-width:900px;width:92%">
    <div class="av-head"><h2 id="av-iov-title">Inspecter</h2><button class="av-x" type="button" aria-label="Fermer">×</button></div>
    <div class="av-body">
      <p class="av-hint" id="av-iov-info" style="margin:0 0 8px">Ceci est exactement ce que le bot reçoit de la page de stats.</p>
      <div style="margin:0 0 10px"><button class="av-btn go" type="button" id="av-iov-run">▶ Lancer l'inspection</button></div>
      <pre id="av-iov-pre" style="max-height:42vh;overflow:auto;white-space:pre-wrap;word-break:break-word;background:rgba(130,130,130,.08);border:1px solid var(--border);border-radius:8px;padding:10px;font-size:12px;margin:0">…</pre>
      <div style="margin-top:12px;display:flex;gap:8px;align-items:flex-end;flex-wrap:wrap">
        <div style="flex:1;min-width:240px">
          <label class="av-hint" style="display:block;margin-bottom:4px">Inspecter une autre page <span style="opacity:.7">(aide aux regex — les stats sont toujours lues sur l'accueil)</span></label>
          <input id="av-iov-extra" type="text" spellcheck="false" placeholder="/mystats.php  ou  https://site.tld/stats" style="width:100%;box-sizing:border-box;background:rgba(130,130,130,.08);border:1px solid var(--border);border-radius:8px;padding:9px 10px;font:13px ui-monospace,SFMono-Regular,Menlo,monospace;color:inherit">
        </div>
        <button class="av-btn ghost" type="button" id="av-iov-reinspect">Inspecter cette page</button>
      </div>
      <div style="margin-top:14px">
        <button class="av-btn ghost" type="button" id="av-iov-asst-toggle">🧩 Assistant regex — générer depuis la page</button>
        <div id="av-iov-asst" style="display:none;margin-top:10px;border:1px solid var(--border);border-radius:8px;padding:12px">
          <p class="av-hint" style="margin:0 0 10px">Pour chaque info, indique le <b>texte qui précède la valeur</b> dans le HTML ci-dessus (ex. « Ratio », « Up : », « Bonus », « Class »). Clique <b>Générer</b> : la regex est créée et ajoutée au JSON. Tu peux ensuite Enregistrer &amp; réactualiser pour tester.</p>
          <div class="av-asst-grid"></div>
        </div>
      </div>
      <div style="margin-top:16px">
        <label class="av-hint" style="display:block;margin-bottom:6px">Regex de stats (modifiable) — édite, enregistre, et le site est revisité avec tes nouvelles regex :</label>
        <textarea id="av-iov-json" spellcheck="false" style="width:100%;box-sizing:border-box;min-height:150px;background:rgba(130,130,130,.08);border:1px solid var(--border);border-radius:8px;padding:10px;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;color:inherit;resize:vertical"></textarea>
        <div id="av-iov-msg" class="av-hint" style="margin-top:6px"></div>
      </div>
    </div>
    <div class="av-foot"><button class="av-btn ghost" type="button" id="av-iov-default">↩ Regex par défaut</button><button class="av-btn ghost" type="button" id="av-iov-restore">↩ Restaurer la sauvegarde</button><button class="av-btn ghost" type="button" id="av-iov-copy">Copier le HTML</button><button class="av-btn ghost" type="button" id="av-iov-cancel">Annuler</button><button class="av-btn save" type="button" id="av-iov-save">Enregistrer &amp; fermer</button><button class="av-btn go" type="button" id="av-iov-close">Fermer</button></div>
  </div></div>`);
  document.body.appendChild(iov);
  // Helpers de l'inspecteur — au NIVEAU MODULE pour être accessibles à la fois par
  // l'assistant (dans l'IIFE) et par le bouton « Enregistrer » (hors IIFE).
  function iovExtra(){ return (iov.querySelector("#av-iov-extra").value||"").trim(); }
  function iovStatsPayload(slug, obj){
    // L'« URL de la page des stats » ne sert qu'à INSPECTER (dumper une page pour
    // bâtir les regex). À l'enregistrement, on lit TOUJOURS les stats sur l'accueil
    // et on purge toute config de page séparée (extra_url) : évite les 404 en visite.
    var k=iov.dataset.statskind||"stats"; if(k==="extra_stats") k="stats";
    var p={slug:slug, extra_url:""}; p[k]=obj; return p;
  }
  var asstFill=null, asstRetest=null;
  (function(){
    var FIELDS=[["upload","Upload","size"],["download","Download","size"],["ratio","Ratio","ratio"],
                ["bonus","Bonus / Points","num"],["rang","Rang / Classe","text"],["seeding","En seed","num"],
                ["autres","Autres","text"]];
    var grid=iov.querySelector(".av-asst-grid"); var valEls={};
    FIELDS.forEach(function(f){
      var lab=document.createElement("label"); lab.textContent=f[1];
      var val=document.createElement("span"); val.className="av-asst-val"; val.textContent="—"; valEls[f[0]]=val;
      var inp=document.createElement("input"); inp.type="text"; inp.placeholder="texte avant la valeur"; inp.dataset.fld=f[0]; inp.dataset.kind=f[2];
      var b=document.createElement("button"); b.type="button"; b.className="av-btn go"; b.textContent="Générer";
      b.addEventListener("click", function(){ genInto(f[0], f[2], inp.value.trim(), b); });
      grid.appendChild(lab); grid.appendChild(val); grid.appendChild(inp); grid.appendChild(b);
    });
    function setBadge(k, v, tested){
      var el=valEls[k]; if(!el) return;
      if(v===undefined){ el.textContent="…"; el.classList.remove("has"); el.title="Inspecte d'abord la page (le HTML doit être affiché ci-dessus)"; return; }
      if(v!=null && (""+v).trim()!=="" && v!=="N/A"){ el.textContent=(""+v).trim(); el.classList.add("has"); el.title=tested?"Valeur extraite par cette regex sur la page inspectée":"Valeur déjà extraite par le bot"; }
      else { el.textContent=tested?"N/A":"—"; el.classList.remove("has"); el.title=tested?"Cette regex n'a rien trouvé sur la page inspectée":"Aucune valeur — utilise l'assistant"; }
    }
    asstFill=function(vals){
      Object.keys(valEls).forEach(function(k){ setBadge(k, vals?vals[k]:null, false); });
    };
    function dumpReady(){ var t=(iov.querySelector("#av-iov-pre").textContent||""); return t.length>50 && !/^Visite en cours/.test(t) && !/^Erreur/.test(t); }
    function testRx(rxStr){
      if(!dumpReady()) return undefined;                 // dump pas encore chargé
      var html=iov.querySelector("#av-iov-pre").textContent||"";
      try{ var m=new RegExp(rxStr).exec(html); if(!m) return null; var v=(m[1]!=null?m[1]:m[0]); return (""+v).replace(/\s+/g," ").trim(); }
      catch(e){ return null; }
    }
    // Recalcule les badges en appliquant les regex du JSON à la page dumpée.
    asstRetest=function(){
      if(!dumpReady()) return;
      var cur; try{ cur=JSON.parse(iov.querySelector("#av-iov-json").value||"{}"); }catch(e){ return; }
      if(typeof cur!=="object"||Array.isArray(cur)) return;
      ["upload","download","ratio","bonus","seeding"].forEach(function(k){ if(cur[k]!=null) setBadge(k, testRx(cur[k]), true); });
      var rk=(cur.rang!=null)?cur.rang:cur["class"]; if(rk!=null) setBadge("rang", testRx(rk), true);
    };
    iov.querySelector("#av-iov-asst-toggle").addEventListener("click", function(){
      var p=iov.querySelector("#av-iov-asst"); p.style.display = p.style.display==="none" ? "block" : "none";
    });
    // Bouton « Inspecter cette page » : recapture le dump sur l'URL saisie.
    function runInspect(b, payload){
      var slug=iov.dataset.slug||"", myGen=++iovGen;
      b.disabled=true; var o=b.innerHTML; b.innerHTML='<span class="av-spin"></span>';
      iov.querySelector("#av-iov-pre").textContent = "Visite en cours… (connexion + page de stats, ~10-30 s)";
      payload.slug=slug;
      inspectPost(payload, 3, function(){ return myGen===iovGen; }).then(function(j){
        b.disabled=false; b.innerHTML=o;
        if(myGen!==iovGen) return;   // modale fermée ou relancée -> réponse périmée
        if(j && j.ok){ iov.querySelector("#av-iov-pre").textContent = j.content + (j.truncated?"\n\n… (tronqué à 200 000 caractères)":""); if(asstRetest) asstRetest(); }
        else { iov.querySelector("#av-iov-pre").textContent = (j && j.error) ? j.error : "Aucun contenu capturé."; }
      }).catch(function(){ b.disabled=false; b.innerHTML=o; if(myGen!==iovGen) return; iov.querySelector("#av-iov-pre").textContent="Erreur réseau pendant l'inspection."; });
    }
    iov.querySelector("#av-iov-run").addEventListener("click", function(){ runInspect(this, {}); });
    iov.querySelector("#av-iov-reinspect").addEventListener("click", function(){ runInspect(this, {extra_url:iovExtra()}); });
    function genRegex(kind, anchor){
      var a=anchor.replace(/[.*+?^${}()|[\]\\]/g,"\\$&").replace(/\s+/g,"\\s*");
      if(kind==="size")  return a+"[\\s\\S]{0,80}?(\\d[\\d\\s.,]*\\s*(?:[KMGTPE](?:i?B|io|o)|B|o))";
      if(kind==="ratio") return a+"[\\s\\S]{0,80}?(\\d[\\d.,]*)";
      if(kind==="num")   return a+"[\\s\\S]{0,80}?(\\d[\\d\\s.,]*\\d|\\d)";
      if(kind==="text")  return a+"[\\s\\S]{0,80}?>\\s*([^<]+?)\\s*<";
      return a+"[\\s\\S]{0,80}?(\\S+)";
    }
    function genInto(fld, kind, anchor, btn){
      if(iov.dataset.ready!=="1"){ btn.textContent="⏳ patiente"; setTimeout(function(){btn.textContent="Générer";},1300); return; }
      if(!anchor){ btn.textContent="↑ texte ?"; setTimeout(function(){btn.textContent="Générer";},1200); return; }
      var ta=iov.querySelector("#av-iov-json"), cur={};
      try{ cur=JSON.parse(ta.value||"{}"); if(typeof cur!=="object"||Array.isArray(cur)) cur={}; }catch(e){ cur={}; }
      cur[fld]=genRegex(kind, anchor);
      ta.value=JSON.stringify(cur,null,2);
      // Teste la regex sur le HTML dumpé et affiche la valeur (ou N/A) dans le badge.
      var res=testRx(cur[fld]); setBadge(fld, res, true);
      // L'insertion est LOCALE ; clique « Enregistrer & fermer » pour l'appliquer au bot.
      var msg=iov.querySelector("#av-iov-msg");
      if(msg){
        if(res===undefined){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="⚠ Inspecte d'abord la page (le HTML doit s'afficher ci-dessus) pour vérifier la regex."; }
        else if(res===null){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="Regex « "+fld+" » ajoutée, mais elle ne trouve RIEN sur la page (N/A). Ajuste le texte avant la valeur."; }
        else { msg.style.color="var(--good,#22c55e)"; msg.textContent="✓ « "+fld+" » = "+res+" — clique « Enregistrer & fermer » pour l'appliquer."; }
      }
      btn.textContent="✓"; setTimeout(function(){ btn.textContent="Générer"; },1200);
    }
  })();
  var iovGen=0;
  function closeInspect(){ iovGen++; iov.classList.remove("open"); }
  iov.querySelector(".av-x").addEventListener("click", closeInspect);
  iov.querySelector("#av-iov-close").addEventListener("click", closeInspect);
  iov.querySelector("#av-iov-cancel").addEventListener("click", closeInspect);
  iov.addEventListener("click", function(e){ if(e.target===iov) closeInspect(); });
  function copyText(txt, btn, okLabel, baseLabel){
    function done(ok){ btn.textContent = ok?okLabel:"Échec copie"; setTimeout(function(){ btn.textContent=baseLabel; }, 1500); }
    if(navigator.clipboard && window.isSecureContext){
      navigator.clipboard.writeText(txt).then(function(){done(true);},function(){fallback();});
    } else { fallback(); }
    function fallback(){
      try{ var ta=document.createElement("textarea"); ta.value=txt;
        ta.style.position="fixed"; ta.style.top="-1000px"; ta.setAttribute("readonly","");
        document.body.appendChild(ta); ta.select(); ta.setSelectionRange(0, txt.length);
        var ok=document.execCommand("copy"); document.body.removeChild(ta); done(ok);
      }catch(e){ done(false); }
    }
  }
  iov.querySelector("#av-iov-copy").addEventListener("click", function(){
    copyText(iov.querySelector("#av-iov-pre").textContent||"", this, "Copié ✓", "Copier le HTML");
  });
  // « Regex par défaut » : recharge les regex d'usine du tracker (base intégrée),
  // pour revenir à une config par défaut si on a cassé les regex. À enregistrer ensuite.
  iov.querySelector("#av-iov-default").addEventListener("click", function(){
    var msg=iov.querySelector("#av-iov-msg");
    if(iov.dataset.ready!=="1"){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="Patiente : la config du site n'est pas encore chargée."; return; }
    var hay=iov.dataset.dom||"", t=null, best=-1;
    for(var i=0;i<TRACKERS.length;i++){ var d=(TRACKERS[i].d||"").toLowerCase(); if(d && hay.indexOf(d)>=0 && d.length>best){ t=TRACKERS[i]; best=d.length; } }
    if(!t){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="Aucun tracker par défaut reconnu pour ce site (ajouté manuellement ?)."; return; }
    var def=null, kind="stats";
    if(t.s && Object.keys(t.s).length){ def=t.s; kind="stats"; }
    else if(t.sj && Object.keys(t.sj).length){ def=t.sj; kind="stats_json"; }
    else if(t.xf && t.xf.s && Object.keys(t.xf.s).length){ def=t.xf.s; kind="stats"; }
    if(!def){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="« "+(t.n||t.d)+" » n'a pas de regex par défaut intégrées."; return; }
    if(!window.confirm("Remplacer les regex actuelles par celles par défaut de « "+(t.n||t.d)+" » ?\n(rien n'est appliqué tant que tu n'as pas cliqué « Enregistrer & fermer »)")) return;
    iov.querySelector("#av-iov-json").value = JSON.stringify(def, null, 2);
    iov.dataset.statskind=kind;
    if(asstRetest) asstRetest();
    msg.style.color="var(--good,#22c55e)"; msg.textContent="↩ Regex par défaut de « "+(t.n||t.d)+" » chargées — clique « Enregistrer & fermer » pour appliquer.";
  });
  // « Restaurer la sauvegarde » : remet la config de stats d'avant le dernier
  // enregistrement (data/.statsbak), via le backend, puis revisite.
  iov.querySelector("#av-iov-restore").addEventListener("click", function(){
    var btn=this, slug=iov.dataset.slug||"", msg=iov.querySelector("#av-iov-msg");
    if(!slug) return;
    if(!window.confirm("Restaurer la sauvegarde (config d'avant ta dernière modification) pour ce site ?")) return;
    var o=btn.textContent; btn.disabled=true; btn.innerHTML='<span class="av-spin"></span>';
    function restore(){ btn.disabled=false; btn.textContent=o; }
    post("/siterestore",{slug:slug},12000).then(function(j){
      restore();
      if(!j||!j.ok){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="Erreur : "+((j&&j.error)||"inconnue"); return; }
      // recharge le JSON restauré dans la zone d'édition + badges
      fetch("/site?slug="+encodeURIComponent(slug)).then(function(r){return r.json();}).then(function(s){
        if(s&&s.ok){ var st=s.site||{}; var cur=(st.stats&&Object.keys(st.stats).length)?st.stats:(st.stats_json||st.extra_stats||{}); iov.querySelector("#av-iov-json").value=JSON.stringify(cur,null,2); iov.dataset.ready="1"; if(asstRetest) asstRetest(); }
      }).catch(function(){});
      msg.style.color="var(--good,#22c55e)"; msg.textContent="↩ Sauvegarde restaurée ["+((j.keys&&j.keys.length)?j.keys.join(", "):"")+"] — réactualisation en cours…";
      refresh();
      post("/revisit",{slug:slug},12000).catch(function(){});
      setTimeout(refresh,6000); setTimeout(refresh,15000); setTimeout(refresh,30000);
    }).catch(function(){ restore(); msg.style.color="var(--ko,#e0796f)"; msg.textContent="Service injoignable."; });
  });
  iov.querySelector("#av-iov-save").addEventListener("click", function(){
    var btn=this, slug=iov.dataset.slug||"", kind=iov.dataset.statskind||"stats";
    var msg=iov.querySelector("#av-iov-msg"); var raw=iov.querySelector("#av-iov-json").value.trim();
    if(iov.dataset.ready!=="1"){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="Patiente : les regex du site ne sont pas encore chargées."; return; }
    var obj;
    try { obj = raw ? JSON.parse(raw) : {}; if(typeof obj!=="object"||Array.isArray(obj)) throw new Error("objet attendu"); }
    catch(e){ msg.style.color="var(--ko,#e0796f)"; msg.textContent="JSON invalide : "+e.message; return; }
    btn.disabled=true; var o=btn.dataset.label||btn.textContent; btn.dataset.label=o;
    btn.innerHTML='<span class="av-spin"></span> Enregistrement…'; msg.style.color=""; msg.textContent="Enregistrement…";
    function restore(){ btn.disabled=false; btn.textContent=o; }
    var payload=iovStatsPayload(slug, obj);
    post("/sitestats", payload, 12000).then(function(j){
      if(!j||!j.ok){ restore(); msg.style.color="var(--ko,#e0796f)"; msg.textContent="Erreur : "+((j&&j.error)||"inconnue"); return; }
      // Modif ENREGISTRÉE : on affiche la confirmation un court instant, puis on ferme
      // (la revisite tourne en arrière-plan et le tableau se met à jour ensuite).
      restore(); msg.style.color="var(--good,#22c55e)";
      msg.textContent="✓ Enregistré ["+((j.keys&&j.keys.length)?j.keys.join(", "):"aucune clé")+"] — réactualisation en cours…";
      refresh();
      post("/revisit",{slug:slug}, 12000).catch(function(){});
      setTimeout(refresh, 6000); setTimeout(refresh, 15000); setTimeout(refresh, 30000);
      setTimeout(closeInspect, 1100);
    }).catch(function(){ restore(); msg.style.color="var(--ko,#e0796f)"; msg.textContent="Service injoignable."; });
  });
  function openInspect(slug, name){
    var myGen=++iovGen;
    iov.dataset.slug=slug; iov.dataset.statskind="stats"; iov.dataset.name=name||"";
    iov.querySelector("#av-iov-title").textContent = "Inspecter — "+name;
    iov.querySelector("#av-iov-pre").textContent = "Inspection non lancée.\n\nClique sur « ▶ Lancer l'inspection » pour récupérer le HTML de la page. Cela déclenche une visite réelle du tracker (~10-30 s).";
    iov.querySelector("#av-iov-info").textContent = "Ceci est exactement ce que le bot reçoit de la page de stats.";
    iov.querySelector("#av-iov-msg").textContent = "";
    iov.querySelector("#av-iov-json").value = "Chargement des regex…";
    iov.querySelector("#av-iov-extra").value = "";
    iov.dataset.ready="0";
    // Réinitialise l'assistant pour CE site : sinon les saisies « texte avant la
    // valeur » du site précédent persistent (le DOM de l'inspecteur est réutilisé).
    var _ai=iov.querySelectorAll(".av-asst-grid input"); for(var _k=0;_k<_ai.length;_k++){ _ai[_k].value=""; }
    var _ap=iov.querySelector("#av-iov-asst"); if(_ap) _ap.style.display="none";
    if(asstFill){
      var stx=((lastStatus&&lastStatus.sites)||[]).filter(function(x){return (x.name||"").toLowerCase()===(name||"").toLowerCase();})[0];
      var rs=(stx&&stx.ok)?rowStats(stx):null;
      asstFill(rs?{upload:rs.up,download:rs.dl,ratio:rs.ra,bonus:rs.bo,rang:rs.rang,seeding:rs.se,autres:(rs.oth&&rs.oth.length?rs.oth.join(" | "):"")}:{});
    }
    iov.classList.add("open");
    fetch("/site?slug="+encodeURIComponent(slug)).then(function(r){return r.json();}).then(function(j){
      if(myGen!==iovGen) return;
      var s=(j&&j.ok)?j.site:{};
      var cur, kind="stats";
      // Le champ « Inspecter une autre page » reste VIDE par défaut : il ne sert qu'à
      // inspecter ponctuellement une autre page. Les stats se lisent sur l'accueil.
      if(s.stats && Object.keys(s.stats).length){ cur=s.stats; kind="stats"; }
      else if(s.stats_json && Object.keys(s.stats_json).length){ cur=s.stats_json; kind="stats_json"; }
      else if(s.extra_stats && Object.keys(s.extra_stats).length){ cur=s.extra_stats; kind="stats"; }
      else { cur={}; }
      iov.dataset.statskind=kind;
      iov.dataset.dom = ((s.url||"")+" "+(s.login_url||"")+" "+(s.verify_url||"")+" "+(s.post_url||"")).toLowerCase();
      iov.querySelector("#av-iov-json").value = JSON.stringify(cur, null, 2);
      iov.dataset.ready="1";
      if(asstRetest) asstRetest();
    }).catch(function(){ iov.querySelector("#av-iov-json").value = "{}"; iov.dataset.ready="1"; });
    // Plus de récupération automatique du HTML : l'inspection ne se lance qu'au clic
    // sur « ▶ Lancer l'inspection » (évite une visite réelle à chaque ouverture).
  }

  var Q = function (s) { return ov.querySelector(s); };
  var result = Q("#av-result"), primary = Q("#av-primary"), acBox = Q("#av-ac");
  var editOrig = null, staged = null, mode = "test", buildErr = "", picked = null, origSite = null, cookieMode = false;

  function cleanDomain(d){return d.trim().replace(/^https?:\/\//i,"").replace(/\/.*$/,"");}

  function updateVerifyLabel(){
    var m = Q("#av-vmode").value, url = m==="url", auto = m==="auto";
    Q("#av-verify").disabled = auto;
    Q("#av-verify").style.opacity = auto ? ".5" : "1";
    Q("#av-verifylabel").textContent = url ? "Texte attendu dans l'URL" : "Mot-clé de succès";
    Q("#av-verify").placeholder = auto ? "(non requis en détection auto)" : (url ? "ex. index.php" : "(défaut : ton pseudo)");
    Q("#av-verifyhint").textContent = auto ? "autovisit détecte la connexion via les marqueurs de la page (déconnexion / logout / mon compte…). Choisis « mot-clé » ou « URL » seulement si l'auto échoue."
      : url ? "Login validé si l'URL après connexion contient ce texte."
      : "Texte présent uniquement une fois connecté (souvent : logout, /logout, ton pseudo).";
  }
  function applyPreset(p){
    var pr = PRESET[p] || PRESET.form;
    Q("#av-path").value = pr.path; Q("#av-vmode").value = pr.vmode;
    Q("#av-verify").value = pr.verify; Q("#av-curl").checked = pr.curl; updateVerifyLabel();
  }
  function detectPlatform(s){
    if(s.api_json) return "apijson";
    if(s.csrf_field==="_xfToken") return "xenforo";
    if(s.csrf_field==="__RequestVerificationToken") return "aspnet";
    if(s.csrf_field==="_csrf_token") return "symfony";
    if(s.csrf_field==="_token"||s.extract_hidden_fields) return "unit3d";
    if((s.url||"").indexOf("login.php")>=0) return "gazelle";
    return "form";
  }
  function setMode(m){
    mode = m;
    primary.className = "av-btn " + (m==="add"?"go":m==="fail"?"fail":"test");
    primary.textContent = m==="add" ? (editOrig?"Enregistrer":"Ajouter") : m==="fail" ? "Échec — retester" : "Tester";
    primary.disabled = false;
  }
  function updateAuthSwitch(){
    var link=Q("#av-authswitch");
    if((picked && (picked.au==="cookie"||picked.au==="key"))){ link.style.display="none"; return; }
    link.style.display="block";
    Q("#av-tocookie").textContent = cookieMode ? "← Revenir à la connexion par identifiants" : "🍪 Le tracker bloque (captcha, Cloudflare…) ? Se connecter par cookies de session →";
  }
  function setAuthMode(mode){ // "key" -> clé privée ; "cookie" -> cookies de session ; sinon identifiant/mot de passe
    var isKey=mode==="key", isCookie=mode==="cookie";
    // needPseudo : un site en mode cookie peut quand même demander le pseudo (URL de stats paramétrée par {{username}})
    var needPseudo = isCookie && picked && picked.xf && /\{\{username\}\}/.test(picked.xf.u||"");
    Q("#av-userfield").style.display=((isKey||isCookie) && !needPseudo)?"none":"";
    Q("#av-pass").parentNode.style.display=isCookie?"none":"";
    Q("#av-cookieblock").style.display=isCookie?"block":"none";
    if(needPseudo){
      Q("#av-userlabel").textContent="Pseudo sur le tracker (pour l'URL de stats)";
      Q("#av-user").placeholder="ton pseudo exact (ex. MonPseudo)";
    } else {
      Q("#av-userlabel").textContent="Identifiant";
      Q("#av-user").placeholder="";
    }
    if(isKey){
      Q("#av-passlabel").textContent="Clé privée";
      Q("#av-pass").type="password"; Q("#av-pass").placeholder="ta clé privée";
    } else if(!isCookie){
      Q("#av-passlabel").textContent=editOrig?"Mot de passe (vide = inchangé)":"Mot de passe";
      Q("#av-pass").type="password"; Q("#av-pass").placeholder="";
    }
    if((isKey||isCookie) && !needPseudo) Q("#av-user").value="";
    updateAuthSwitch();
  }
  function showConfig(open){
    Q("#av-config").style.display = "block";
    Q("#av-adv").open = !!open;
  }
  function setSummary(t){
    var sum = Q("#av-summary");
    if(!t){ sum.style.display="none"; sum.innerHTML=""; return; }
    var logo = t.lg ? '<img src="/.logos/'+t.id+'.png" onerror="this.style.display=\'none\'">' : '';
    sum.innerHTML = logo + '<span style="display:flex;flex-direction:column"><b>'+esc(t.n)+'</b><span>'+esc(t.d)+' · '+esc(t.p)+(t.s||t.sj?' · stats incluses':'')+'</span></span><span class="av-chg">changer</span>';
    sum.style.display="flex";
    var chg = sum.querySelector(".av-chg");
    if(chg) chg.addEventListener("click", function(){ goManual(true); });
  }
  function show2FA(on){ Q("#av-2farow").style.display = on ? "block" : "none"; }
  function knownByDomain(dom){
    dom=(dom||"").replace(/^www\./,"");
    if(!dom) return null;
    return TRACKERS.filter(function(t){ var d=(t.d||"").replace(/^www\./,""); return d && (dom===d || dom.indexOf(d)>=0 || d.indexOf(dom)>=0); })[0] || null;
  }
  function reset(){
    ["av-name","av-domain","av-user","av-pass","av-verify","av-path","av-totp","av-stats","av-cookies","av-ua"].forEach(function(id){Q("#"+id).value="";});
    ["av-curl","av-pw","av-cf"].forEach(function(id){Q("#"+id).checked=false;});
    Q("#av-platform").value="form"; applyPreset("form"); picked=null; origSite=null; cookieMode=false; hideAc(); show2FA(false);
    Q("#av-config").style.display="none"; Q("#av-adv").open=false; setSummary(null);
    Q("#av-manualrow").style.display="block"; setAuthMode("user");
    Q("#av-namelabel").innerHTML='Tracker <span style="color:#6b7383">— tape le nom (ex. The Old School)</span>';
    Q("#av-name").placeholder="The Old School…";
    Q("#av-totp").placeholder="SECRET_BASE32";
    result.className="av-result"; result.innerHTML=""; staged=null; setMode("test");
  }
  function goManual(keepName){
    picked=null; cookieMode=false; setSummary(null); setAuthMode("user");
    Q("#av-namelabel").innerHTML='Nom du site';
    Q("#av-manualrow").style.display="none";
    show2FA(true); // config manuelle : on ne peut pas deviner, on laisse le champ 2FA disponible
    if(!keepName){ /* garde ce qui est tapé */ }
    showConfig(true); hideAc();
    setTimeout(function(){ Q("#av-domain").focus(); }, 0);
  }

  /* ----- auto-complétion trackers ----- */
  var acItems = [], acIdx = -1;
  function hideAc(){ acBox.classList.remove("show"); acBox.innerHTML=""; acItems=[]; acIdx=-1; }
  function fillFromTracker(t){
    picked = t; cookieMode=false;
    Q("#av-name").value = t.n; Q("#av-domain").value = t.d;
    Q("#av-platform").value = t.p; applyPreset(t.p);
    Q("#av-path").value = (t.lp && t.lp.charAt(0)==="/") ? t.lp : "/login";
    if (t.s) { try { Q("#av-stats").value = JSON.stringify(t.s, null, 2); } catch(e){} }
    else { Q("#av-stats").value = ""; }
    Q("#av-statshint").textContent = (t.au==="cookie")
      ? ((t.xf && /\{\{username\}\}/.test(t.xf.u||""))
         ? "Auth par cookies de session : colle les cookies exportés + le User-Agent, et renseigne ton pseudo (pour l'URL de stats)."
         : "Auth par cookies de session : colle les cookies exportés de ton navigateur + le User-Agent correspondant.")
      : (t.p==="apijson")
      ? "Tracker API JSON : login et stats via l'API, repris automatiquement du dashboard."
      : (t.br ? "Stats via rendu Playwright (Firefox) : elles fonctionnent, mais le test et la visite sont plus lents (~20-30 s)."
      : (t.sj ? "Stats JSON récupérées automatiquement."
      : (t.s ? "Regex pré-remplies depuis « "+t.n+" »." : "Pas de stats définies pour ce tracker dans le dashboard.")));
    if(t.br && t.au!=="cookie") Q("#av-pw").checked = true;
    if(t.cf){ Q("#av-cf").checked = true;
      Q("#av-statshint").textContent = "Tracker derrière Cloudflare : challenge résolu automatiquement via Byparr (conteneur requis sur 127.0.0.1:8191)."; }
    show2FA(!!t.to);
    Q("#av-totp").placeholder = t.to ? "SECRET_BASE32 (2FA requis pour ce tracker)" : "SECRET_BASE32";
    Q("#av-manualrow").style.display="none";
    setAuthMode(t.au||"user");
    setSummary(t); showConfig(false); hideAc();
    setTimeout(function(){ (t.au==="cookie"?Q("#av-cookies"):t.au==="key"?Q("#av-pass"):Q("#av-user")).focus(); }, 0);
    if (mode!=="test") setMode("test");
  }
  function renderAc(q){
    var ql = q.trim().toLowerCase();
    if (ql.length < 1) { hideAc(); return; }
    var m = TRACKERS.filter(function(t){ return t.n.toLowerCase().indexOf(ql)>=0 || (t.d||"").toLowerCase().indexOf(ql)>=0; }).slice(0,8);
    if (!m.length) { hideAc(); return; }
    acItems = m; acIdx = -1;
    acBox.innerHTML = m.map(function(t,i){
      return '<div class="av-ac-item" data-i="'+i+'"><span style="display:flex;flex-direction:column"><b>'+esc(t.n)+'</b><span>'+esc(t.d)+'</span></span><span class="av-ac-tag">'+esc(t.p)+'</span></div>';
    }).join("");
    Array.prototype.forEach.call(acBox.querySelectorAll(".av-ac-item"), function(it){
      it.addEventListener("mousedown", function(e){ e.preventDefault(); fillFromTracker(acItems[+it.dataset.i]); });
    });
    acBox.classList.add("show");
  }
  Q("#av-name").addEventListener("input", function(){ picked=null; renderAc(this.value); });
  Q("#av-name").addEventListener("keydown", function(e){
    if (!acBox.classList.contains("show")) return;
    if (e.key==="ArrowDown"){ e.preventDefault(); acIdx=Math.min(acIdx+1,acItems.length-1); hl(); }
    else if (e.key==="ArrowUp"){ e.preventDefault(); acIdx=Math.max(acIdx-1,0); hl(); }
    else if (e.key==="Enter" && acIdx>=0){ e.preventDefault(); fillFromTracker(acItems[acIdx]); }
    else if (e.key==="Escape"){ hideAc(); }
  });
  function hl(){ Array.prototype.forEach.call(acBox.children, function(c,i){ c.classList.toggle("hl", i===acIdx); }); }
  Q("#av-name").addEventListener("blur", function(){ setTimeout(hideAc, 150); });
  Q("#av-manual").addEventListener("click", function(e){ e.preventDefault(); goManual(false); });
  Q("#av-tocookie").addEventListener("click", function(e){ e.preventDefault();
    if(picked && (picked.au==="cookie"||picked.au==="key")) return;
    cookieMode=!cookieMode; setAuthMode(cookieMode?"cookie":"user");
    if(cookieMode) Q("#av-cookies").focus();
  });

  function openAdd(){ editOrig=null; reset(); Q("#av-title").textContent="Ajouter un site"; Q("#av-passlabel").textContent="Mot de passe"; ov.classList.add("open"); Q("#av-name").focus(); }
  function openEdit(slug){
    fetch("/site?slug="+encodeURIComponent(slug)).then(function(r){return r.json();}).then(function(j){
      if(!j.ok){alert("Site introuvable");return;}
      var s=j.site; editOrig=slug; reset(); origSite=s;
      Q("#av-title").textContent="Modifier « "+(s.name||slug)+" »";
      Q("#av-namelabel").innerHTML="Nom du site"; Q("#av-manualrow").style.display="none";
      Q("#av-passlabel").textContent="Mot de passe (vide = inchangé)";
      var u=(s.url||"").replace(/^https?:\/\//i,""), sl=u.indexOf("/");
      var dom = sl>=0?u.slice(0,sl):u;
      Q("#av-name").value=s.name||""; Q("#av-domain").value=dom;
      Q("#av-path").value=sl>=0?u.slice(sl):"/login"; Q("#av-user").value=s.username||"";
      Q("#av-platform").value=detectPlatform(s);
      Q("#av-curl").checked=!!s.use_curl_cffi; Q("#av-pw").checked=!!s.use_playwright; Q("#av-cf").checked=!!s.cf_solver;
      Q("#av-totp").value=s.totp_secret||"";
      // reconnaissance du tracker -> base picked (réinjecte totp_url, csrf, api, etc. à l'enregistrement)
      var known=knownByDomain(dom);
      if(known) picked=Object.assign({}, known);
      if(s.success_url_contains){ Q("#av-vmode").value="url"; Q("#av-verify").value=s.success_url_contains; }
      else if(s.success_keywords && s.success_keywords.length){ Q("#av-vmode").value="kw"; var kw=s.success_keywords[0]||""; Q("#av-verify").value=(kw===s.username)?"":kw; }
      else { Q("#av-vmode").value="auto"; Q("#av-verify").value=""; }
      updateVerifyLabel();
      if(s.stats){ try{ Q("#av-stats").value=JSON.stringify(s.stats,null,2); }catch(e){} }
      else if(s.stats_json){ picked=Object.assign(picked||{},{sj:s.stats_json}); }
      if(s.username_field && s.username_field!=="username") picked=Object.assign(picked||{},{uf:s.username_field});
      if(s.password_field && s.password_field!=="password") picked=Object.assign(picked||{},{pf:s.password_field});
      if(s.session_cookies_file){ picked=Object.assign(picked||{},{au:"cookie"}); setAuthMode("cookie"); if(s.user_agent) Q("#av-ua").value=s.user_agent; }
      else if(s.playwright_password_selector){ picked=Object.assign(picked||{},{au:"key",pks:s.playwright_password_selector}); setAuthMode("key"); }
      else setAuthMode("user");
      show2FA(!!(s.totp_url || s.totp_secret || (known && known.to)));
      showConfig(true);
      ov.classList.add("open");
    }).catch(function(){alert("Service injoignable.");});
  }

  function absURL(u, base){ if(!u) return null; return (/^https?:/i).test(u) ? u : (base + (u.charAt(0)==="/"?u:"/"+u)); }

  function buildSite(){
    buildErr="";
    var name=Q("#av-name").value.trim(), domain=cleanDomain(Q("#av-domain").value);
    var user=Q("#av-user").value.trim(), pass=Q("#av-pass").value;
    var keyauth = picked && picked.au==="key";
    var cookieauth = (picked && picked.au==="cookie") || cookieMode;
    if(!name||!domain) return null;
    if(!editOrig){
      if(cookieauth){ if(!Q("#av-cookies").value.trim()) return null; }
      else { if(!keyauth && !user) return null; if(!pass) return null; }
    }
    var platform=Q("#av-platform").value;
    var pathRaw=Q("#av-path").value.trim()||(PRESET[platform]||PRESET.form).path;
    if(!/^https?:/i.test(pathRaw) && pathRaw[0]!=="/") pathRaw="/"+pathRaw;
    var base="https://"+domain;
    var urlFromPath = /^https?:/i.test(pathRaw)?pathRaw:(base+pathRaw);

    // helper cookies : accepte le JSON exporté OU une chaîne brute « nom=valeur; … »
    function parseCookies(){
      var t=Q("#av-cookies").value.trim(); if(!t) return null;
      var dom=cleanDomain(Q("#av-domain").value);
      if(t.charAt(0)==="[" || t.charAt(0)==="{"){
        try{ var c=JSON.parse(t);
          if(Array.isArray(c)) return c;
          if(c && Array.isArray(c.cookies)) return c.cookies;
          buildErr="Cookies : tableau JSON attendu."; return false;
        }catch(e){ buildErr="Cookies : JSON invalide ("+e.message+")."; return false; }
      }
      // format brut copié depuis le navigateur : nom=valeur; nom2=valeur2
      var arr=[];
      t.split(/;\s*/).forEach(function(p){
        var i=p.indexOf("="); if(i<1) return;
        var n=p.slice(0,i).trim(), v=p.slice(i+1).trim();
        if(n) arr.push({name:n, value:v, domain:"."+dom, path:"/"});
      });
      if(!arr.length){ buildErr="Cookies : format non reconnu (colle le JSON exporté, ou « nom=valeur; … »)."; return false; }
      return arr;
    }

    // ===== ÉDITION : repartir de la config réelle, n'écraser que ce qui change =====
    if(editOrig && origSite){
      var s=JSON.parse(JSON.stringify(origSite));
      s.name=name;
      s.url=urlFromPath;
      if(!origSite.post_url || origSite.post_url===origSite.url) s.post_url=urlFromPath;
      if(!keyauth) s.username=user;
      if(pass) s.password=pass;
      var vmodeE=Q("#av-vmode").value, vv=Q("#av-verify").value.trim();
      if(vmodeE==="auto"){ delete s.success_keywords; delete s.success_url_contains; }
      else if(vv){ if(vmodeE==="url"){ s.success_url_contains=vv; delete s.success_keywords; }
              else { s.success_keywords=[vv]; delete s.success_url_contains; } }
      var rawE=Q("#av-stats").value.trim();
      if(rawE){ try{ var st2=JSON.parse(rawE); if(st2&&typeof st2==="object"){ s.stats=st2; delete s.stats_json; } else {buildErr="Stats : objet JSON attendu.";return null;} }catch(e){ buildErr="Stats : JSON invalide ("+e.message+")."; return null; } }
      var totpE=Q("#av-totp").value.trim().replace(/\s+/g,"").toUpperCase();
      if(totpE){ if(/^\d{6,8}$/.test(totpE)){ buildErr="Champ 2FA : entre le SECRET (clé base32), pas un code à 6 chiffres."; return null; } s.totp_secret=totpE; }
      // tracker reconnu : on (ré)injecte la config fidèle manquante (répare les anciens enregistrements)
      if(picked){
        if(picked.mu) s.totp_url=absURL(picked.mu,base);
        if(picked.tf) s.totp_field=picked.tf;
        if(picked.pp && !origSite.post_url) s.post_url=absURL(picked.pp,base);
        if(picked.csrf && !s.csrf_field && s.api_json!==true) s.csrf_field=picked.csrf;
        if(picked.pv && !s.pre_visit_urls) s.pre_visit_urls=picked.pv.map(function(x){return absURL(x,base);});
        if(picked.mp && !s.mp_url){ s.mp_url=absURL(picked.mp.u,base); s.mp_json_field=picked.mp.f; }
        if(s.api_json && picked.sf && !s.success_json_field) s.success_json_field=picked.sf;
      }
      if(Q("#av-curl").checked) s.use_curl_cffi=true; else delete s.use_curl_cffi;
      if(Q("#av-pw").checked) s.use_playwright=true; else if(!s.playwright_password_selector) delete s.use_playwright;
      if(Q("#av-cf").checked) s.cf_solver="http://127.0.0.1:8191/v1"; else delete s.cf_solver;
      // mise à jour éventuelle des cookies de session
      if(origSite.session_cookies_file){
        var ck=parseCookies(); if(ck===false) return null;
        if(ck) s.session_cookies=ck;                                  // nouveaux cookies collés
        else s.session_cookies_file=origSite.session_cookies_file;    // sinon : on conserve l'existant (auth cookies préservée)
        var uae=Q("#av-ua").value.trim(); if(uae) s.user_agent=uae;
      }
      return s;
    }

    // ===== AJOUT par cookies de session (tracker cookieOnly ou bascule manuelle) =====
    if(cookieauth){
      var ck2=parseCookies(); if(!ck2){ if(buildErr) return null; buildErr="Colle les cookies de session."; return null; }
      var vpath = (picked&&picked.vp) ? absURL(picked.vp,base) : urlFromPath;
      var cs={name:name, url:base+"/", verify_url:vpath,
              enabled:true, alert_keywords:["new_message"], session_cookies:ck2};
      var ua2=Q("#av-ua").value.trim(); if(ua2) cs.user_agent=ua2;
      var rawC=Q("#av-stats").value.trim();
      if(rawC){ try{ var stc=JSON.parse(rawC); if(stc&&typeof stc==="object") cs.stats=stc; }catch(e){} }
      else if(picked&&picked.s) cs.stats=picked.s;
      if(picked&&picked.sj) cs.stats_json=picked.sj;
      if(picked&&picked.mp){ cs.mp_url=absURL(picked.mp.u,base); cs.mp_json_field=picked.mp.f; }
      if(picked&&picked.xf){
        // Si l'URL de stats est parametree par le pseudo, on EXIGE le pseudo (sinon extra_url cassee)
        if(/\{\{username\}\}/.test(picked.xf.u||"") && !user){ buildErr="Renseigne ton pseudo sur le tracker (necessaire pour l'URL de stats)."; return null; }
        cs.extra_url=absURL(picked.xf.u.replace(/\{\{username\}\}/g,encodeURIComponent(user||"")),base);
        cs.extra_format=picked.xf.fmt||"html";
        if(picked.xf.s && typeof picked.xf.s==="object"){ cs.extra_stats=Object.assign({},picked.xf.s); }
        else { cs.extra_stats={}; cs.extra_stats[picked.xf.f]=picked.xf.fmt==="json"?picked.xf.pa:picked.xf.rx; } }
      if(Q("#av-cf").checked) cs.cf_solver="http://127.0.0.1:8191/v1";
      return cs;
    }

    // ===== AJOUT : formulaire + config exacte du tracker =====
    var s={name:name,url:urlFromPath,post_url:urlFromPath,
      username_field:(picked&&picked.uf)||"username",password_field:(picked&&picked.pf)||"password",
      username:user,password:pass,alert_keywords:["new_message"],verify_url:base+"/",enabled:true};
    var vmode=Q("#av-vmode").value, vval=Q("#av-verify").value.trim();
    if(vmode==="auto"){ /* autovisit détecte via les marqueurs de page (logout/déconnexion…) */ }
    else if(vmode==="url"){ s.success_url_contains = vval || (PRESET[platform]||{}).verify || "index.php"; }
    else { s.success_keywords = [vval || user]; }
    if(platform==="unit3d"){ s.csrf_field="_token"; s.extract_hidden_fields=true; }
    else if(platform==="aspnet"){ s.csrf_field="__RequestVerificationToken"; s.extract_hidden_fields=true; }
    else if(platform==="xenforo"){ s.csrf_field="_xfToken"; s.extract_hidden_fields=true; }
    else if(platform==="symfony"){ s.csrf_field="_csrf_token"; }
    else if(platform==="apijson"){ s.api_json=true; s.success_json_field="success"; }
    if(Q("#av-curl").checked) s.use_curl_cffi=true;
    if(Q("#av-pw").checked) s.use_playwright=true;
    if(Q("#av-cf").checked) s.cf_solver="http://127.0.0.1:8191/v1";
    if(picked && picked.mu){ s.totp_url=absURL(picked.mu,base); }
    if(picked && picked.tf){ s.totp_field=picked.tf; }
    var totp=Q("#av-totp").value.trim().replace(/\s+/g,"").toUpperCase();
    if(totp){
      if(/^\d{6,8}$/.test(totp)){ buildErr="Champ 2FA : entre le SECRET (clé base32, ex. JBSWY3DP…), pas un code à 6 chiffres."; return null; }
      s.totp_secret=totp; if(!s.totp_field) s.totp_field=(platform==="xenforo")?"code":"mfa";
      if(!s.totp_url && platform==="xenforo") s.totp_url=base+"/login/two-step"; }
    var raw=Q("#av-stats").value.trim();
    if(raw){ try{ var stt=JSON.parse(raw); if(stt&&typeof stt==="object") s.stats=stt; else {buildErr="Stats : objet JSON attendu.";return null;} }catch(e){ buildErr="Stats : JSON invalide ("+e.message+")."; return null; } }
    if(picked && picked.sj && !raw){ s.stats_json = picked.sj; }
    // surcharges fidèles au tracker connu (config exacte du dashboard git)
    if(picked){
      if(picked.lp) s.url = absURL(picked.lp, base);
      s.post_url = picked.pp ? absURL(picked.pp, base) : s.url;
      if(picked.vp) s.verify_url = absURL(picked.vp, base);
      if(picked.csrf) s.csrf_field = picked.csrf;
      if(picked.hid) s.extract_hidden_fields = true;
      if(picked.ef) s.extra_fields = picked.ef;
      if(picked.pv && picked.pv.length) s.pre_visit_urls = picked.pv.map(function(u){return absURL(u,base);});
      if(picked.mp){ s.mp_url=absURL(picked.mp.u,base); s.mp_json_field=picked.mp.f; }
      if(picked.xf){
        s.extra_url=absURL(picked.xf.u.replace(/\{\{username\}\}/g,encodeURIComponent(user||"")),base);
        s.extra_format=picked.xf.fmt||"html";
        s.extra_stats={}; s.extra_stats[picked.xf.f]= picked.xf.fmt==="json" ? picked.xf.pa : picked.xf.rx;
      }
      if(picked.br && picked.au!=="key"){
        s.use_playwright=true; s.playwright_fetch_verify=true;
        if(picked.vp) s.verify_url=absURL(picked.vp,base);
        s.playwright_post_verify_wait=4;
        delete s.success_keywords; delete s.success_url_contains; // succès = page rendue
      }
      if(platform==="apijson"){ s.api_json=true; delete s.success_keywords; delete s.success_url_contains; s.success_json_field=picked.sf||"success"; }
      if(picked.au==="key"){
        s.username=""; delete s.username_field;
        s.use_playwright=true; s.playwright_password_selector=picked.pks||"#private-key-input";
        s.playwright_wait_url_change=30; s.playwright_post_login_wait=5; s.playwright_fetch_verify=true;
        if(picked.vp) s.verify_url=absURL(picked.vp,base);
        delete s.success_keywords; delete s.success_url_contains;
        s.success_url_contains=(picked.vp||"/activity").replace(/^https?:\/\/[^/]+/,"").replace(/^\//,"")||"activity";
      }
    }
    return s;
  }
  function showResult(ok,html){result.className="av-result show "+(ok?"ok":"ko");result.innerHTML=html;}

  function runTest(){
    if(Q("#av-config").style.display==="none"){ goManual(false); return; }
    var site=buildSite();
    if(!site){ showResult(false, buildErr || ("Remplis le nom, le domaine, l'identifiant"+(editOrig?"":" et le mot de passe")+".")); return; }
    primary.disabled=true; primary.textContent="Test en cours…"; result.className="av-result";
    var prev=staged;
    post("/test",{site:site,original_slug:editOrig}).then(function(j){
      if(!j.ok){setMode("fail");showResult(false,"<b>Erreur :</b> "+(j.error||"")); return;}
      if(prev && prev.created && prev.slug!==j.slug){ post("/cancel",{slug:prev.slug,created:true}); }
      staged={slug:j.slug,created:j.created};
      if(j.login_ok){ setMode("add"); showResult(true,"<b>✓ Connexion réussie.</b> Clique sur « "+(editOrig?"Enregistrer":"Ajouter")+" » pour valider.<pre>"+esc(j.log)+"</pre>"); }
      else { setMode("fail"); showResult(false,"<b>Login en échec.</b> Ajuste plateforme / vérification / options puis reteste. Rien n'est enregistré tant que ce n'est pas validé.<pre>"+esc(j.log)+"</pre>"); }
    }).catch(function(e){setMode("fail");showResult(false,"<b>Service injoignable.</b> ("+e+")");});
  }
  function doConfirm(){
    if(!staged) return; primary.disabled=true; primary.textContent="…";
    var payload={slug:staged.slug,original_slug:editOrig};
    if(picked && picked.lg && picked.id){ payload.logo=picked.id; payload.icon_key=(Q("#av-name").value||"").trim().toLowerCase(); }
    post("/confirm",payload).then(function(j){
      if(j.ok){ staged=null; ov.classList.remove("open"); refresh(); }
      else { setMode("add"); showResult(false,"<b>Erreur :</b> "+(j.error||"")); }
    }).catch(function(){setMode("add");showResult(false,"Service injoignable.");});
  }
  function closeAdd(doCleanup){
    if(doCleanup && staged){ post("/cancel",{slug:staged.slug,original_slug:editOrig,created:staged.created}); }
    staged=null; ov.classList.remove("open");
  }

  primary.addEventListener("click", function(){ if(mode==="add") doConfirm(); else runTest(); });
  Q("#av-cancel").addEventListener("click", function(){ closeAdd(true); });
  Q(".av-x").addEventListener("click", function(){ closeAdd(true); });
  ov.addEventListener("click", function(e){ if(e.target===ov) closeAdd(true); });
  Q("#av-platform").addEventListener("change", function(){ applyPreset(this.value); if(mode!=="test") setMode("test"); });
  Q("#av-vmode").addEventListener("change", function(){ updateVerifyLabel(); if(mode!=="test") setMode("test"); });
  ov.querySelectorAll("input,textarea").forEach(function(inp){ if(inp.id==="av-name") return; inp.addEventListener("input", function(){ if(mode!=="test") setMode("test"); }); });

  /* ---------- CONFIRM générique ---------- */
  var cfYes=null;
  function askConfirm(msg, danger, onYes){
    cf.querySelector("#av-cf-msg").textContent=msg;
    var yes=cf.querySelector("#av-cf-yes"); yes.className="av-btn "+(danger?"danger":"go"); yes.textContent=danger?"Confirmer":"Oui";
    cfYes=onYes; cf.classList.add("open");
  }
  function closeConfirm(){cf.classList.remove("open");cfYes=null;}
  cf.querySelector("#av-cf-yes").addEventListener("click", function(){ var f=cfYes; closeConfirm(); if(f) f(); });
  cf.querySelector("#av-cf-no").addEventListener("click", closeConfirm);
  cf.querySelector(".av-x").addEventListener("click", closeConfirm);
  cf.addEventListener("click", function(e){ if(e.target===cf) closeConfirm(); });

  /* ---------- RENDU DU TABLEAU (liste réelle + stats fusionnées) ---------- */
  var tbody = document.getElementById("tbody");
  var updatedEl = document.getElementById("updated");

  var COL_UPLOAD=["upload"], COL_DOWN=["download"], COL_RATIO=["ratio"],
      COL_BONUS=["bonus","points","theias","credits","bonus_upload","gift_lvl","chocos","gold"],
      COL_SEED=["seed","seeds","seeding"],
      COL_RANG=["class","classe","rang","rank","role"];
  function deEnt(v){ return typeof v==="string" ? v.replace(/&nbsp;|&#160;|&#xa0;/gi," ").replace(/\u00a0/g," ").replace(/\s+/g," ").trim() : v; }
  function parseStats(str){ if(!str) return {};
    if(typeof str==="object"){ var o={}; Object.keys(str).forEach(function(k){o[k]=deEnt(str[k]);}); return o; }
    var r={};
    String(str).split("|").forEach(function(p){var i=p.indexOf(":"); if(i<0) return; r[p.slice(0,i).trim().toLowerCase()]=deEnt(p.slice(i+1).trim());}); return r; }
  function matchCol(k,cols){ return cols.some(function(c){ return k===c||k.indexOf(c)>=0; }); }

  function toNum(raw){ if(raw==null) return null;
    var s=String(raw).replace(/[\s\u00a0]/g,"").trim();
    if(!s||s==="—"||s==="-"||/^n\/?a$/i.test(s)) return null;
    if(s==="∞") return Infinity;
    if(s.indexOf(".")>=0 && s.indexOf(",")>=0){ s=s.replace(/,/g,""); }
    else if(s.indexOf(",")>=0){ var pa=s.split(","); s=(pa.length===2&&pa[1].length<=2)?(pa[0]+"."+pa[1]):s.replace(/,/g,""); }
    s=s.replace(/[^0-9.\-]/g,""); var n=parseFloat(s); return isNaN(n)?null:n; }
  function toBytes(raw){ if(raw==null) return null;
    var s=String(raw).replace(/\u00a0/g," ").trim();
    if(!s||s==="—"||s==="-"||/^n\/?a$/i.test(s)) return null;
    if(s==="∞") return Infinity;
    var m=s.match(/([\d.,\s]+)\s*([kmgtpe])?\s*i?\s*(?:b|o)\b/i);
    if(!m) return toNum(s);
    var num=toNum(m[1]); if(num==null) return null;
    var mult={"":1,k:1e3,m:1e6,g:1e9,t:1e12,p:1e15,e:1e18}[(m[2]||"").toLowerCase()]||1;
    return num*mult; }

  function rowStats(st){
    var stats=parseStats(st.stats); var up=null,dl=null,ra=null,bo=null,se=null,rang=null,oth=[];
    Object.keys(stats).forEach(function(k){ var v=stats[k];
      if(matchCol(k,COL_UPLOAD)&&!up) up=v;
      else if(matchCol(k,COL_DOWN)&&!dl) dl=v;
      else if(matchCol(k,COL_RATIO)&&!ra) ra=v;
      else if(matchCol(k,COL_BONUS)&&!bo) bo=v;
      else if(matchCol(k,COL_SEED)&&!se) se=v;
      else if(matchCol(k,COL_RANG)&&!rang){ if(v&&v!=="N/A") rang=v; }
      else if(v&&v!=="N/A") oth.push(k+": "+v);
    });
    return {up:up,dl:dl,ra:ra,bo:bo,se:se,rang:rang,oth:oth};
  }

  var WARN_TRI = '<span class="warn-tri" title="Hors ligne / échec de connexion">'+
    '<svg width="14" height="14" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'+
    '<path d="M12 3 L22.5 21 H1.5 Z" fill="#e8543a" stroke="#b23a23" stroke-width="1.4" stroke-linejoin="round"/>'+
    '<rect x="11" y="9" width="2" height="6" rx="1" fill="#fff"/>'+
    '<circle cx="12" cy="17.7" r="1.15" fill="#fff"/></svg></span>';
  function statusIndicator(kind){
    if(kind==="ko") return WARN_TRI;
    var c = kind==="ok" ? "dot dot-live"
          : kind==="alert" ? "dot dot-alert dot-pulse"
          : kind==="wait" ? "dot dot-wait"
          : "dot dot-off";
    return '<span class="'+c+'"></span>';
  }

  // ---- tri des colonnes ----
  var sortState = { col:null, dir:1 };
  function colVal(site, byName, col){
    if(col==="name") return {t:"s", v:(site.name||"").toLowerCase(), empty:false};
    var st=byName[(site.name||"").toLowerCase()];
    if(col==="date"){ var iso=st&&st.last_ok; var d=iso?Date.parse(iso):NaN; return {t:"n", v:isNaN(d)?null:d, empty:isNaN(d)}; }
    var strCol=(col==="rang"||col==="autres");
    if(site.enabled===false) return {t:(strCol?"s":"n"), v:(strCol?"":null), empty:true};
    if(!st || !st.ok) return {t:(strCol?"s":"n"), v:(strCol?"":null), empty:true};
    var rs=rowStats(st);
    if(col==="rang"){ var r=rs.rang; return {t:"s", v:(r||"").toLowerCase(), empty:!r}; }
    if(col==="autres"){ var o=(rs.oth&&rs.oth.length)?rs.oth.join(" | "):""; return {t:"s", v:o.toLowerCase(), empty:!o}; }
    var raw = col==="upload"?rs.up : col==="download"?rs.dl : col==="ratio"?rs.ra : col==="bonus"?rs.bo : col==="seed"?rs.se : null;
    var n=(col==="upload"||col==="download")?toBytes(raw):toNum(raw);
    return {t:"n", v:n, empty:(n==null)};
  }
  function applySort(sites, byName){
    if(!sortState.col) return sites;
    var arr=sites.slice(), col=sortState.col, dir=sortState.dir;
    arr.sort(function(a,b){
      var va=colVal(a,byName,col), vb=colVal(b,byName,col);
      if(va.empty&&vb.empty) return 0;     // valeurs absentes toujours en bas
      if(va.empty) return 1;
      if(vb.empty) return -1;
      if(va.t==="s"){ var c=va.v.localeCompare(vb.v); return c<0?-dir : c>0?dir : 0; }
      var na=va.v, nb=vb.v;
      return na<nb?-dir : na>nb?dir : 0;
    });
    return arr;
  }
  function normNum(raw){ if(raw==null) return raw; var s=String(raw).trim();
    if(s===""||s==="—"||s==="-"||s==="N/A"||s==="∞") return s; return s; }
  function fmtDate(iso){ if(!iso) return null; var m=String(iso).match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/); return m?(m[3]+"/"+m[2]+"/"+m[1]+" "+m[4]+":"+m[5]):iso; }
  function placeholder(name){ var l=(name||"?").charAt(0).toUpperCase();
    var svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect width="16" height="16" rx="3" fill="#6b6560"/><text x="8" y="12" font-family="sans-serif" font-size="10" font-weight="700" fill="white" text-anchor="middle">'+l+'</text></svg>';
    return "data:image/svg+xml;base64,"+btoa(unescape(encodeURIComponent(svg))); }
  function cell(val,sec){ var cls=sec?"col-secondary ":""; return val?'<td class="'+cls+'">'+esc(normNum(val))+'</td>':'<td class="'+cls+'na">—</td>'; }

  function actionsCell(info){
    var td=document.createElement("td"); td.style.textAlign="right"; td.style.whiteSpace="nowrap";
    var wrap=document.createElement("span"); wrap.className="av-actions";
    var t=document.createElement("button"); t.type="button"; t.className="av-act "+(info.enabled?"on":"off");
    t.innerHTML=ICON.power; t.title=info.enabled?"Désactiver":"Activer";
    t.addEventListener("click",function(ev){ev.stopPropagation();
      askConfirm((info.enabled?"Désactiver":"Activer")+" « "+info.name+" » ?", false, function(){ post("/toggle",{slug:info.slug}).then(refresh); });});
    var e=document.createElement("button"); e.type="button"; e.className="av-act ed"; e.innerHTML=ICON.edit; e.title="Éditer";
    e.addEventListener("click",function(ev){ev.stopPropagation(); openEdit(info.slug);});
    var ins=document.createElement("button"); ins.type="button"; ins.className="av-act"; ins.innerHTML=ICON.inspect; ins.title="Inspecter (voir ce que le bot reçoit)";
    ins.addEventListener("click",function(ev){ev.stopPropagation(); openInspect(info.slug, info.name);});
    var d=document.createElement("button"); d.type="button"; d.className="av-act de"; d.innerHTML=ICON.trash; d.title="Supprimer";
    d.addEventListener("click",function(ev){ev.stopPropagation();
      askConfirm("Supprimer « "+info.name+" » ? Cette action est définitive.", true, function(){ post("/delete",{slug:info.slug}).then(refresh); });});
    wrap.appendChild(t); wrap.appendChild(e); wrap.appendChild(ins); wrap.appendChild(d); td.appendChild(wrap); return td;
  }
  function nameCell(name, url, kind, alert){
    var slug=(name||"").toLowerCase();
    var bust=iconBust?("?v="+iconBust):"";
    var proto=/^https?:/.test(url||"")?url:("https://"+(url||""));
    var mp=alert?'<span class="mp-flag" title="'+esc(alert)+'">MP</span>':'';
    return '<td class="left"><div class="site-name">'+statusIndicator(kind)+
      '<img class="favicon" src="icones/'+encodeURIComponent(slug)+'.png'+bust+'" '+
      'onerror="this.onerror=null;this.src=\'icones/'+encodeURIComponent(slug)+'.ico'+bust+'\';this.onerror=function(){this.src=\''+placeholder(name)+'\';};">'+
      '<a href="'+esc(proto)+'" target="_blank" rel="noopener">'+esc(name)+'</a>'+mp+'</div></td>';
  }

  function renderRows(sites, status){
    var byName={}; ((status&&status.sites)||[]).forEach(function(s){ byName[(s.name||"").toLowerCase()]=s; });
    sites = applySort(sites, byName);
    tbody.innerHTML="";
    if(!sites.length){ tbody.innerHTML='<tr><td class="left" colspan="10" style="color:var(--dim);font-style:italic">Aucun site. Clique sur + pour en ajouter un.</td></tr>'; return; }
    sites.forEach(function(site){
      var st=byName[(site.name||"").toLowerCase()] || null;
      var info={slug:site.slug,name:site.name,enabled:site.enabled!==false};
      var tr=document.createElement("tr");
      var disabled = site.enabled===false;
      var kind = disabled?"off":(!st?"wait":(!st.ok?"ko":(st.alert?"alert":"ok")));
      var html = nameCell(site.name, (st&&st.url)||site.url, kind, (st&&!disabled)?st.alert:null);
      if(disabled){ tr.className="row-disabled"; html+='<td class="left off-info" colspan="8">Désactivé</td>'; }
      else if(!st){ tr.className="row-ko"; html+='<td class="left off-info" colspan="8" style="font-style:italic">En attente de la première visite…</td>'; }
      else if(!st.ok){ tr.className="row-ko"; var last=fmtDate(st.last_ok);
        html+='<td class="left ko-info" colspan="7">'+(last?("Échec — dernière connexion le "+last):"Échec — aucune connexion réussie")+'</td>'
            + cell(fmtDate(st.last_ok),true); }
      else {
        var rs=rowStats(st);
        html+=cell(rs.up,false)+cell(rs.dl,true)+cell(rs.ra,false)+cell(rs.bo,true)+cell(rs.se,true)
            + cell(rs.rang,false)+cell(rs.oth.length?rs.oth.join(" | "):null,true)+cell(fmtDate(st.last_ok),true);
      }
      tr.innerHTML=html;
      tr.appendChild(actionsCell(info));
      tbody.appendChild(tr);
    });
  }

  // câblage du tri sur les en-têtes
  var lastSites=[], lastStatus={};
  var iconBust=0;
  function rerender(){ renderRows(lastSites, lastStatus); }
  function updateSortArrows(){
    document.querySelectorAll("thead th[data-col]").forEach(function(th){
      var a=th.querySelector(".sort-arrow"); th.classList.remove("sorted");
      if(th.getAttribute("data-col")===sortState.col){ th.classList.add("sorted"); if(a) a.textContent=sortState.dir>0?" ▲":" ▼"; }
      else if(a){ a.textContent=""; }
    });
  }
  function wireSort(){
    document.querySelectorAll("thead th[data-col]").forEach(function(th){
      th.classList.add("av-sortable");
      if(!th.querySelector(".sort-arrow")){ var a=document.createElement("span"); a.className="sort-arrow"; th.appendChild(a); }
      th.addEventListener("click", function(){
        var col=th.getAttribute("data-col");
        if(sortState.col===col){ sortState.dir=-sortState.dir; }
        else { sortState.col=col; sortState.dir=(col==="name")?1:-1; }
        updateSortArrows(); rerender();
      });
    });
  }

  function syncLogos(sites){
    var pairs=[];
    (sites||[]).forEach(function(s){
      var url=(s.url||"").toLowerCase(), best=null;
      TRACKERS.forEach(function(t){ if(t.lg&&t.d&&url.indexOf(t.d.toLowerCase())>=0){ if(!best||t.d.length>best.d.length) best=t; }});
      if(best) pairs.push({key:(s.name||"").toLowerCase(), logo:best.id});
    });
    if(pairs.length) post("/logosync",{pairs:pairs}).catch(function(){});
  }

  var refreshing=false;
  function refresh(){
    if(refreshing) return; refreshing=true;
    var _t0=Date.now();
    if(brand) brand.classList.add("refreshing");
    if(updatedEl) updatedEl.innerHTML='<span class="av-spin"></span>Actualisation…';
    Promise.all([
      fetch("/sites").then(function(r){return r.json();}).catch(function(){return null;}),
      fetch("status.json?_="+Date.now()).then(function(r){return r.ok?r.json():null;}).catch(function(){return null;})
    ]).then(function(res){
      var sites=((res[0]&&res[0].sites)||[]);
      var status=res[1]||{};
      lastSites=sites; lastStatus=status;
      renderRows(sites, status);
      browserNotifyCheck(status);
      syncLogos(sites);
    }).catch(function(){}).then(function(){
      function _done(){
        refreshing=false;
        if(brand) brand.classList.remove("refreshing");
        if(updatedEl){
          var u=new Date().toLocaleString("fr-FR",{day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit"});
          updatedEl.textContent="Actualisé : "+u;
        }
      }
      var _dt=Date.now()-_t0;
      if(_dt<600){ setTimeout(_done, 600-_dt); } else { _done(); }
    });
  }

  bAdd.addEventListener("click", openAdd);
  wireSort();
  document.addEventListener("keydown", function(e){ if(e.key==="Escape"){
    if(iov.classList.contains("open")) closeInspect();
    else if(cf.classList.contains("open")) closeConfirm();
    else if(sov.classList.contains("open")) closeSettings();
    else if(ov.classList.contains("open")) closeAdd(true); }});

  function init2(){ loadSettings(); loadAlerts(); refresh(); }
  function init(){
    fetch("/auth/status").then(function(r){return r.json();}).then(function(j){
      if(j&&j.ok){ authState={configured:j.configured,twofa:j.twofa,authed:j.authed}; }
      if(j&&j.accent){ document.documentElement.style.setProperty("--ok", j.accent, "important"); }
      updateAuthBtn();
      if(authState.configured && !authState.authed){ showLogin(); return; }
      init2();
    }).catch(function(){ init2(); });
  }
  if(document.readyState!=="loading") init(); else document.addEventListener("DOMContentLoaded", init);
})();
JSEOF
pct push $CT /tmp/addsite.js /var/www/autovisit/addsite.js --perms 644; rm /tmp/addsite.js

echo "[7/8] Page index.html…"
pct exec $CT -- bash -c "[ -f /var/www/autovisit/index.html.orig ] || cp /var/www/autovisit/index.html /var/www/autovisit/index.html.orig 2>/dev/null || true"
cat > /tmp/index.html << 'IDXEOF'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>MALINOIS</title>
<link rel="icon" href="/favicon.png">
<style>
:root {
    --bg:     #f8f6f1;
    --border: #e2ddd6;
    --text:   #1a1a1a;
    --dim:    #6b6560;
    --ok:     #e0892b;
    --ko:     #c0392b;
    --good:   #15803d;
    --alert:  #b07d2a;
    --row-ko-bg: #fbeeec;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    font-size: 16px;
    line-height: 1.5;
    padding: 24px clamp(16px, 4vw, 48px);
  }

  header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 8px;
    margin-bottom: 20px;
    padding-bottom: 14px;
    border-bottom: 2px solid var(--text);
  }

  header h1 {
    font-size: 15px;
    font-weight: 700;
    letter-spacing: 0.22em;
    text-transform: uppercase;
  }

  table {
    width: 100%;
    border-collapse: separate;
    border-spacing: 0;
  }

  /* Largeurs adaptatives : la colonne Site prend ce qu'il faut, les
     colonnes numeriques s'ajustent a leur contenu (white-space:nowrap). */
  th {
    text-align: right;
    color: var(--dim);
    font-weight: 600;
    font-size: 12px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    padding: 0 0 10px 18px;
    border-bottom: 1px solid var(--border);
    white-space: nowrap;
  }

  th.left { text-align: left; padding-left: 0; }

  td {
    padding: 10px 0 10px 18px;
    background: var(--row, transparent);
    background-clip: padding-box;
    border-bottom: 1px solid var(--border);
    vertical-align: middle;
    text-align: right;
    white-space: nowrap;
    color: var(--dim);
    font-size: 15px;
    font-variant-numeric: tabular-nums;
  }

  td.left { text-align: left; padding-left: 0; }
  td.na   { color: #c9c3bb; }

  tr:last-child td { border-bottom: none; }
  tbody tr:hover td { background: var(--row-hover, #e6dcc8); }
  td:first-child, th:first-child { border-left: 5px solid transparent; }
  td:last-child,  th:last-child  { border-right: 5px solid transparent; }
  tbody tr:hover td:first-child { border-top-left-radius: 9px; border-bottom-left-radius: 9px; }
  tbody tr:hover td:last-child  { border-top-right-radius: 9px; border-bottom-right-radius: 9px; }

  /* Ligne en echec */
  tr.row-ko td { background: var(--row-ko-bg); color: var(--ko); }
  tr.row-ko:hover td { background: #f3d9d3; }

  /* Ligne desactivee (site enabled:false) */
  tr.row-disabled td { color: #b3ada4; }
  tr.row-disabled:hover td { background: var(--row-hover, #e6dcc8); }
  tr.row-disabled a { color: #b3ada4; }
  .dot-off { background: #c9c3bb; }
  .off-info { font-size: 13px; font-weight: 500; font-style: italic; }

  .site-name {
    display: flex;
    align-items: center;
    gap: 9px;
  }

  .favicon {
    width: 18px;
    height: 18px;
    flex-shrink: 0;
    object-fit: contain;
    border-radius: 3px;
  }

  .dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }
  .dot-ok    { background: var(--ok); }
  .dot-ko    { background: var(--ko); }
  .dot-alert { background: var(--alert); }

  a { color: var(--text); text-decoration: none; font-weight: 500; }
  a:hover { text-decoration: underline; }
  tr.row-ko a { color: var(--ko); }

  /* Icone MP juste apres le nom, clignotante */
  .mp-flag {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    background: var(--alert);
    color: #fff;
    font-size: 11px;
    font-weight: 700;
    padding: 2px 7px;
    border-radius: 3px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    flex-shrink: 0;
    animation: mp-blink 1.1s ease-in-out infinite;
  }
  @keyframes mp-blink {
    0%, 100% { opacity: 1; }
    50%      { opacity: 0.35; }
  }
  @media (prefers-reduced-motion: reduce) {
    .mp-flag { animation: none; }
  }

  .ko-info {
    font-size: 13px;
    font-weight: 500;
    font-style: italic;
  }

  #error {
    color: var(--ko);
    padding: 40px 0;
    text-align: center;
    font-size: 15px;
  }

  /* Responsive : sous 640px on masque les colonnes secondaires
     (Download, Bonus, En Seed, Autres) — on garde Site / Upload / Ratio / MP */
  @media (max-width: 640px) {
    body { padding: 16px 10px; font-size: 14px; }
    th.col-secondary, td.col-secondary { display: none; }
    th, td { padding-left: 8px; font-size: 13px; }
    th { font-size: 11px; letter-spacing: 0.06em; }
    .favicon { width: 16px; height: 16px; }
    .site-name { gap: 6px; }
    .mp-flag { font-size: 10px; padding: 1px 5px; }
    /* La colonne Site ne doit pas pousser Ratio hors cadre */
    td.left, th.left { white-space: normal; }
  }

  /* --- En-tete personnalise (logo + nom) --- */
  header { align-items: flex-start; }
  .brand { display:flex; flex-direction:column; align-items:flex-start; gap:7px; cursor:pointer; }
  #dash-logo { width:78px; height:78px; object-fit:contain; background:transparent; border:0; display:block; }
  .brand-name { font-size:16px; font-weight:700; letter-spacing:0.22em; text-transform:uppercase; color:var(--text); }
  .brand-updated { font-size:11px; font-weight:400; letter-spacing:normal; text-transform:none; color:var(--dim); min-height:14px; margin-top:1px; }
  .head-right { display:flex; flex-direction:column; align-items:flex-end; gap:10px; }
  .head-ver { font-size:11px; letter-spacing:.04em; opacity:.55; font-variant-numeric:tabular-nums; align-self:center; text-align:center; padding-top:10px; }
  .av-tools { display:flex; gap:8px; }
  @media (max-width:600px){ .brand-name{font-size:14px;letter-spacing:.16em;} #dash-logo{width:60px;height:60px;} }

</style>
</head>
<body>
<header>
  <div class="brand" id="brand" title="Actualiser">
    <img id="dash-logo" alt="" style="display:none">
    <span class="brand-name" id="dash-title">MALINOIS</span>
    <span class="brand-updated" id="updated"></span>
  </div>
  <div class="head-right">
    <div class="av-tools" id="tools-slot"></div>
    <span class="head-ver" id="app-ver"></span>
  </div>
</header>
<div id="content">
<table>
  <thead>
    <tr>
      <th class="left" data-col="name">Site</th>
      <th data-col="upload">Upload</th>
      <th class="col-secondary" data-col="download">Download</th>
      <th data-col="ratio">Ratio</th>
      <th class="col-secondary" data-col="bonus">Bonus / Points</th>
      <th class="col-secondary" data-col="seed">En Seed</th>
      <th data-col="rang">Rang</th>
      <th class="col-secondary" data-col="autres">Autres</th>
      <th class="col-secondary" data-col="date">Dernière connexion</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody id="tbody"></tbody>
</table>
</div>
<script src="/addsite.js?v=116"></script>
</body>
</html>
IDXEOF
sed -i "s/addsite\.js?v=[0-9]*/addsite.js?v=$(date +%s)/" /tmp/index.html
pct push $CT /tmp/index.html /var/www/autovisit/index.html --perms 644; rm /tmp/index.html
pct exec $CT -- bash -c "chown -R www-data:www-data /var/www/autovisit 2>/dev/null || true"

echo "[8/8] Nginx (conf generee par le backend selon data/tls.json)…"
pct exec $CT -- env MAL_CT_IP="$CT_IP" MAL_LAN_CIDR="$LAN_CIDR" MAL_WEBROOT=/var/www/autovisit python3 /opt/tracker-autovisit/web-api.py --write-nginx
pct exec $CT -- ln -sf /etc/nginx/sites-available/autovisit /etc/nginx/sites-enabled/autovisit
pct exec $CT -- bash -c 'nginx -t && systemctl reload nginx'

# --- Verification finale GARANTIE (s'execute quoi qu'il arrive en amont) ---
echo "[final] Redemarrage service + controle version…"
pct exec $CT -- systemctl restart autovisit-web
pct exec $CT -- bash -c 'sleep 1; curl -s http://127.0.0.1:8099/auth/status >/dev/null && echo "  service OK" || echo "  service KO"'
echo -n "  addsite.js servi : version "
pct exec $CT -- bash -c "grep -o 'MALINOIS_VER=\"[0-9]*\"' /var/www/autovisit/addsite.js | head -1 || echo '(marqueur absent — fichier non a jour !)'"
echo -n "  web-api.py installe : "
pct exec $CT -- bash -c "grep -q '_bg_revisit' /opt/tracker-autovisit/web-api.py && echo 'a jour (async revisit)' || echo 'ANCIEN (pas de _bg_revisit)'"
echo; echo "=== Termine. Recharge http://${CT_IP}/ (Ctrl+Maj+R). ==="
echo "  - Securite : Parametres > Securite pour definir un mot de passe (et activer le 2FA). Tant qu aucun mot de passe n est defini, l acces reste libre."
echo "  - Verrouille ? Dans le conteneur : rm /opt/tracker-autovisit/data/auth.json && systemctl restart autovisit-web"
