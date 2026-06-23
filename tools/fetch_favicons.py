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
