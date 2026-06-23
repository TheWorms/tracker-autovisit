# Malinois : corrige les regex de stats des sites deja deployes (sites.d),
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
