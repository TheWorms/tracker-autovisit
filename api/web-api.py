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
