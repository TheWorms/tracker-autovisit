#!/usr/bin/env python3
# Malinois : patches additifs pour autovisit.py
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
    print("Malinois patch : lecture impossible (%s) -- ignore" % e); sys.exit(0)

orig = src
applied = []

# ---- Patch 1 : 2FA session/Cloudflare ----
if "Malinois-2FA-SESSION" not in src:
    anchor = '            log.info("[" + name + "] Login effectue (HTTP " + str(r_post.status_code) + ")")'
    if anchor in src:
        block = "\n".join([
            "",
            "            # Malinois-2FA-SESSION : etape 2FA separee derriere Cloudflare/cookies",
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
        print("Malinois patch : ancre 2FA introuvable -- 2FA session ignore")

# ---- Patch 2a : inspect HTML (extract_stats) ----
if "Malinois-INSPECT-HTML" not in src:
    a = "def extract_stats(html, patterns):"
    if a in src:
        block = "\n".join([
            "",
            "    # Malinois-INSPECT-HTML",
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
        print("Malinois patch : ancre extract_stats introuvable -- inspect HTML ignore")

# ---- Patch 2b : inspect JSON (extract_stats_json) ----
if "Malinois-INSPECT-JSON" not in src:
    a = "def extract_stats_json(data, fields):"
    if a in src:
        block = "\n".join([
            "",
            "    # Malinois-INSPECT-JSON",
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
        print("Malinois patch : ancre extract_stats_json introuvable -- inspect JSON ignore")


# === Patches backend Malinois v78 (additifs, idempotents, best-effort) ===
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
         '        # Malinois-APIJSON-SESSION : Stats JSON (api_json) -- lit /api/auth/me etc.\n'
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
        print("Malinois patch : ancre apijson-session introuvable (deja applique ?) -- ignore")

# ---- Patch 4 : priorite cookies fichier > FlareSolverr (Nexum) ----
if "_cf_filtered" not in src:
    a = "        cookies_data = list(cookies_data) + list(cf_cookies)"
    b = ('        # Malinois-CF-COOKIE-PRIORITY : le fichier prime sur FlareSolverr\n'
         '        _file_names = {c.get("name") for c in cookies_data}\n'
         '        _cf_filtered = [c for c in cf_cookies if c.get("name") not in _file_names]\n'
         '        cookies_data = list(cookies_data) + list(_cf_filtered)')
    if a in src:
        src = src.replace(a, b, 1); applied.append("cf-cookie-priority")
    else:
        print("Malinois patch : ancre cf-cookie-priority introuvable (deja applique ?) -- ignore")

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
        b = ('                            # Malinois-MFA-STATSJSON : lit stats_json dans le flux MFA\n'
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
        print("Malinois patch : ancre mfa-statsjson introuvable (deja applique ?) -- ignore")

if not applied:
    print("Malinois patch : rien a faire (deja applique)."); sys.exit(0)

bak = P + ".malinois.bak"
if not os.path.exists(bak):
    io.open(bak, "w", encoding="utf-8").write(orig)

io.open(P, "w", encoding="utf-8").write(src)
try:
    py_compile.compile(P, doraise=True)
    print("Malinois patch : applique -> " + ", ".join(applied))
except Exception as e:
    io.open(P, "w", encoding="utf-8").write(orig)
    print("Malinois patch : ECHEC compilation, restaure (%s)." % e); sys.exit(1)
