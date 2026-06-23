#!/usr/bin/env python3
# Malinois : décode les logos (base64) du manifeste vers <WEBROOT>/.logos/<id>.png.
# Build-time : les données du manifeste sont embarquées dans l'image.
import sys, os, json, base64

MANIFEST = sys.argv[1] if len(sys.argv) > 1 else "data/logos-manifest.json"
WEBROOT = os.environ.get("WEBROOT", "/var/www/autovisit")
OUT = os.path.join(WEBROOT, ".logos")
os.makedirs(OUT, exist_ok=True)

try:
    man = json.load(open(MANIFEST, encoding="utf-8"))
except Exception as e:
    print("  manifeste illisible (%s), logos ignorés" % e)
    sys.exit(0)

n = 0
for k, b in man.items():
    try:
        open(os.path.join(OUT, "%s.png" % k), "wb").write(base64.b64decode(b))
        n += 1
    except Exception:
        pass
print("  logos installés : %d" % n)
