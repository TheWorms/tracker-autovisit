/* login.js v138 — portail d'authentification Malinois (public, filtré IP).
   Affiche UNIQUEMENT l'écran de connexion. Une fois authentifié — ou si le
   dashboard n'est pas encore configuré (setup initial) — charge /addsite.js,
   qui contient toute la logique métier + la base TRACKERS et qui est GATÉ par
   session côté serveur (auth_request nginx -> /auth/check). Un visiteur non
   connecté ne reçoit donc que ce fichier : une simple boîte de mot de passe. */
(function () {
  var APP_SRC = "/addsite.js?v=" + (window.__MAL_BUILD || Date.now());
  function el(html){var d=document.createElement("div");d.innerHTML=html.trim();return d.firstChild;}
  function post(url,obj){
    return fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},
      credentials:"same-origin",body:JSON.stringify(obj||{})}).then(function(r){return r.json();});
  }
  var _appLoaded=false;
  function loadApp(){
    if(_appLoaded) return; _appLoaded=true;
    try{ if(ov&&ov.parentNode) ov.parentNode.removeChild(ov); }catch(e){}
    var s=document.createElement("script"); s.src=APP_SRC; document.body.appendChild(s);
  }
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
  var ov = el(`
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
  document.body.appendChild(ov);
  function LQ(s){ return ov.querySelector(s); }
  function showLogin(){
    var ic=document.querySelector('link[rel*="icon"]'); var lo=LQ("#lg-logo");
    if(ic&&ic.href){ lo.src=ic.href; lo.style.display="block"; }
    var t=(document.title||"").split("—")[0].trim(); if(t) LQ("#lg-name").textContent=t;
    ov.classList.add("open"); setTimeout(function(){ LQ("#lg-pass").focus(); }, 50);
  }
  function doLogin(){
    var btn=LQ("#lg-go"); btn.disabled=true; btn.textContent="…";
    post("/auth/login",{password:LQ("#lg-pass").value, code:LQ("#lg-code").value, remember:LQ("#lg-remember").checked}).then(function(j){
      btn.disabled=false; btn.textContent="Se connecter";
      if(j.ok){ ov.classList.remove("open"); loadApp(); }
      else if(j.need_2fa){ LQ("#lg-codefield").style.display="block"; LQ("#lg-code").focus();
        LQ("#lg-result").className="lg-msg"+(j.error?" ko":""); LQ("#lg-result").textContent=j.error||"Entre le code de ton application 2FA."; }
      else { LQ("#lg-result").className="lg-msg ko"; LQ("#lg-result").textContent=j.error||"Échec de connexion."; }
    }).catch(function(){ btn.disabled=false; btn.textContent="Se connecter"; LQ("#lg-result").className="lg-msg ko"; LQ("#lg-result").textContent="Service injoignable."; });
  }
  LQ("#lg-go").addEventListener("click", doLogin);
  ov.addEventListener("keydown", function(e){ if(e.key==="Enter"){ e.preventDefault(); doLogin(); } });
  function boot(){
    fetch("/auth/status",{credentials:"same-origin"}).then(function(r){return r.json();}).then(function(j){
      if(j&&j.accent){ document.documentElement.style.setProperty("--ok", j.accent, "important"); }
      if(j&&j.ok&&j.configured&&!j.authed){ showLogin(); return; }
      loadApp();
    }).catch(function(){ loadApp(); });
  }
  if(document.readyState!=="loading") boot(); else document.addEventListener("DOMContentLoaded", boot);
})();
