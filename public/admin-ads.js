/* CVxMaker admin — Campagnes publicitaires + Utilisateurs en direct
 * Chargé après le script principal de admin.html (utilise ses helpers : $, esc, nf, rpc, toast, ask, openModal, closeAll, lineChart, bars, donut…)
 */
(function () {
  'use strict';
  var STATUS_FR = { draft: 'Brouillon', active: 'Active', paused: 'En pause', ended: 'Terminée' };
  var STATUS_CLS = { draft: '', active: 'b-ok', paused: 'b-warn', ended: 'b-bad' };
  var FORMATS = [
    ['popup', '🪟', 'Pop-up', 'Carte centrée, fond assombri'],
    ['fullscreen', '📱', 'Plein écran', 'Impact maximal, vidéo verticale'],
    ['sheet', '⬆️', 'Volet bas', 'Remonte depuis le bas'],
    ['banner', '📰', 'Bannière', 'Discrète, en bas de l\'écran'],
    ['corner', '💬', 'Coin', 'Petite carte flottante']
  ];
  var PLACEMENTS = [['app_open', 'À l\'ouverture de l\'appli'], ['my_cvs', 'À l\'ouverture de « Mes CV »'], ['after_export', 'Après un téléchargement de CV'], ['editor', 'Pendant l\'édition (réservé)']];
  var FREQ = [['once', 'Une seule fois par utilisateur'], ['once_per_session', 'Une fois par session'], ['once_per_day', 'Une fois par jour'], ['every_n_days', 'Tous les N jours'], ['always', 'À chaque déclenchement']];
  var PLANS = ['free', 'starter', 'premium', 'pro'];
  var COLORS = [['#4f46e5', '#ffffff'], ['#0ea5e9', '#ffffff'], ['#10b981', '#ffffff'], ['#f59e0b', '#111827'], ['#ef4444', '#ffffff'], ['#111827', '#ffffff'], ['#ec4899', '#ffffff']];
  var AD = null, AD_FILTER = 'all', PV = null;

  function blank() {
    return { id: null, name: '', status: 'draft', priority: 5, format: 'popup', media_type: 'image', media_url: '', poster_url: '', title: '', body: '', cta_label: 'En savoir plus', link_url: '', link_new_tab: true, sponsor_label: 'Sponsorisé',
      close_delay_s: 5, allow_close: true, auto_close_s: null, video_autoplay: true, video_muted: true, video_loop: false,
      theme: { bg: '#ffffff', text: '', accent: '#4f46e5', overlay: 62, radius: 18, animation: 'zoom', align: 'left', sponsor: true },
      audience: { plans: [], countries: [], devices: [], min_account_days: '', max_account_days: '', has_exported: 'any', include_admins: false },
      placement: 'app_open', trigger_delay_s: 3, frequency: 'once_per_day', frequency_days: 3, max_impressions: null, max_per_user: null, daily_cap: null, max_clicks: null, starts_at: null, ends_at: null };
  }
  function ctr(c) { return c.impressions ? (Math.round(c.clicks / c.impressions * 1000) / 10) + ' %' : '—'; }
  function pct(a, b) { return b ? Math.min(100, Math.round(a / b * 100)) : 0; }
  function liveState(c) {
    var now = Date.now();
    if (c.status === 'active' && c.starts_at && new Date(c.starts_at) > now) return ['Programmée', 'b-info'];
    if (c.status === 'active' && c.ends_at && new Date(c.ends_at) <= now) return ['Terminée', 'b-bad'];
    return [STATUS_FR[c.status] || c.status, STATUS_CLS[c.status] || ''];
  }
  function toLocal(iso) { if (!iso) return ''; var d = new Date(iso); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); }
  function fromLocal(v) { return v ? new Date(v).toISOString() : null; }
  function intOrNull(v) { v = String(v == null ? '' : v).trim(); if (v === '') return null; var n = parseInt(v, 10); return isNaN(n) ? null : n; }
  function slug(s) { return (s || 'campagne').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'campagne'; }

  /* ═════════════ LISTE ═════════════ */
  PAGEFN.ads = async function pageAds(arg) {
    if (arg) return editor(arg);
    $('mainArea').innerHTML = pageHead('Campagnes publicitaires', 'Annonces image ou vidéo affichées aux utilisateurs connectés',
      '<button class="btn" onclick="AdsAdmin.reload()">↻ Actualiser</button>' + (can(3) ? '<button class="btn pri" onclick="goPage(\'ads\',\'new\')">＋ Nouvelle campagne</button>' : '')) +
      '<div id="adsBody">' + loading() + '</div>';
    loadList();
  };
  async function loadList() {
    try {
      var r = await Promise.all([rpc('admin_ads_overview', { p_days: 14 }), sb.from('ad_campaigns').select('*').order('created_at', { ascending: false }).limit(200)]);
      var o = r[0], q = r[1]; if (q.error) throw q.error; var list = q.data || [];
      var shown = list.filter(function (c) { return AD_FILTER === 'all' || (AD_FILTER === 'live' ? (c.status === 'active') : c.status === AD_FILTER); });
      var tabs = [['all', 'Toutes'], ['active', 'Actives'], ['draft', 'Brouillons'], ['paused', 'En pause'], ['ended', 'Terminées']];
      var oc = o.impressions ? Math.round(o.clicks / o.impressions * 1000) / 10 + ' %' : '—';
      $('adsBody').innerHTML =
        '<div class="grid g-kpi" style="margin-bottom:14px">' +
        '<div class="kpi"><div class="l">Campagnes actives</div><div class="v">' + nf(o.active) + '</div><div class="d flat">' + nf(o.scheduled) + ' programmée(s) · ' + nf(o.drafts) + ' brouillon(s)</div></div>' +
        '<div class="kpi"><div class="l">Vues (14 j)</div><div class="v">' + nf(o.impressions) + '</div><div class="d flat">' + nf(o.viewers) + ' utilisateur(s) unique(s)</div></div>' +
        '<div class="kpi"><div class="l">Clics (14 j)</div><div class="v">' + nf(o.clicks) + '</div><div class="d flat">CTR ' + oc + '</div></div>' +
        '<div class="kpi"><div class="l">Fermetures (14 j)</div><div class="v">' + nf(o.closes) + '</div><div class="d flat">' + (o.impressions ? Math.round(o.closes / o.impressions * 100) : 0) + ' % des vues</div></div></div>' +
        '<div class="card" style="margin-bottom:14px"><h3>Vues et clics par jour</h3>' + lineChart(o.imp_series, { color: PAL[0] }) + '<div class="muted small" style="margin-top:6px">Clics : ' + (o.clk_series || []).map(function (s) { return s.v; }).join(' · ') + '</div></div>' +
        '<div class="chips" style="margin-bottom:12px">' + tabs.map(function (t) { return '<span class="chip ' + (t[0] === AD_FILTER ? 'on' : '') + '" onclick="AdsAdmin.filter(\'' + t[0] + '\')">' + t[1] + ' <b>' + (t[0] === 'all' ? list.length : list.filter(function (c) { return c.status === t[0]; }).length) + '</b></span>'; }).join('') + '</div>' +
        (shown.length ? '<div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:14px">' + shown.map(card).join('') + '</div>'
          : '<div class="stub">' + (list.length ? 'Aucune campagne dans ce filtre.' : '<b>Aucune campagne pour le moment.</b><br>Créez votre première annonce : image ou vidéo, lien, durée avant la croix, ciblage et plafonds de vues.') + (can(3) ? '<br><br><button class="btn pri" onclick="goPage(\'ads\',\'new\')">＋ Créer une campagne</button>' : '') + '</div>');
    } catch (e) { $('adsBody').innerHTML = errBox(e); }
  }
  function card(c) {
    var st = liveState(c), cap = c.max_impressions;
    var thumb = c.media_url ? (c.media_type === 'video' ? '<video src="' + esc(c.media_url) + '#t=0.5" muted preload="metadata" style="width:100%;height:100%;object-fit:cover"></video>' : '<img src="' + esc(c.media_url) + '" alt="" style="width:100%;height:100%;object-fit:cover" loading="lazy">') : '<div style="display:flex;align-items:center;justify-content:center;height:100%;font-size:30px;opacity:.4">📢</div>';
    var fmt = FORMATS.filter(function (f) { return f[0] === c.format; })[0] || FORMATS[0];
    var sched = (c.starts_at ? 'dès le ' + fdt(c.starts_at) : '') + (c.ends_at ? ' jusqu\'au ' + fdt(c.ends_at) : '');
    return '<div class="card" style="padding:0;overflow:hidden"><div style="height:130px;background:#0b1020;position:relative">' + thumb +
      '<span class="badge ' + st[1] + '" style="position:absolute;left:10px;top:10px">' + esc(st[0]) + '</span>' +
      (c.media_type === 'video' ? '<span class="badge" style="position:absolute;right:10px;top:10px">▶ vidéo</span>' : '') + '</div>' +
      '<div style="padding:14px"><div style="font-weight:800;font-size:15px;margin-bottom:2px">' + esc(c.name) + '</div>' +
      '<div class="muted small" style="margin-bottom:10px">' + fmt[1] + ' ' + fmt[2] + ' · ' + esc((PLACEMENTS.filter(function (p) { return p[0] === c.placement; })[0] || [0, c.placement])[1]) + ' · priorité ' + c.priority + (sched ? '<br>' + esc(sched) : '') + '</div>' +
      '<div class="grid" style="grid-template-columns:repeat(4,1fr);gap:6px;text-align:center;margin-bottom:10px">' +
      [['Vues', nf(c.impressions)], ['Uniques', nf(c.unique_viewers)], ['Clics', nf(c.clicks)], ['CTR', ctr(c)]].map(function (x) { return '<div><div style="font-weight:800">' + x[1] + '</div><div class="muted" style="font-size:11px">' + x[0] + '</div></div>'; }).join('') + '</div>' +
      (cap ? '<div class="muted small" style="margin-bottom:4px">' + nf(c.impressions) + ' / ' + nf(cap) + ' vues</div><div style="height:6px;border-radius:9px;background:rgba(255,255,255,.08);overflow:hidden;margin-bottom:10px"><div style="height:100%;width:' + pct(c.impressions, cap) + '%;background:' + PAL[1] + '"></div></div>' : '') +
      '<div class="row" style="gap:6px;flex-wrap:wrap">' +
      '<button class="btn sm" onclick="AdsAdmin.stats(\'' + c.id + '\')">📈 Stats</button>' +
      (can(3) ? '<button class="btn sm" onclick="goPage(\'ads\',\'' + c.id + '\')">✏️ Modifier</button>' +
        (c.status === 'active' ? '<button class="btn sm" onclick="AdsAdmin.status(\'' + c.id + '\',\'paused\')">⏸ Pause</button>' : (c.status !== 'ended' || true) ? '<button class="btn sm ok" onclick="AdsAdmin.status(\'' + c.id + '\',\'active\')">▶ ' + (c.status === 'draft' ? 'Publier' : 'Relancer') + '</button>' : '') +
        '<button class="btn sm" onclick="AdsAdmin.dup(\'' + c.id + '\')">⧉</button><button class="btn sm danger" onclick="AdsAdmin.del(\'' + c.id + '\',\'' + esc(c.name).replace(/'/g, '') + '\')">🗑</button>' : '') +
      '</div></div></div>';
  }

  /* ═════════════ ÉDITEUR ═════════════ */
  async function editor(id) {
    if (!can(3)) { $('mainArea').innerHTML = '<div class="stub">Créer une campagne nécessite le rôle Administrateur.</div>'; return; }
    $('mainArea').innerHTML = pageHead(id === 'new' ? 'Nouvelle campagne' : 'Modifier la campagne', '', '<button class="btn" onclick="goPage(\'ads\')">← Retour</button>') + loading();
    if (id === 'new') AD = blank();
    else {
      var q = await sb.from('ad_campaigns').select('*').eq('id', id).single();
      if (q.error) { $('mainArea').innerHTML = errBox(q.error); return; }
      AD = q.data; AD.theme = Object.assign(blank().theme, AD.theme || {}); AD.audience = Object.assign(blank().audience, AD.audience || {});
    }
    renderEditor();
  }
  function f(label, inner, hint) { return '<label class="adf"><span class="adl">' + label + '</span>' + inner + (hint ? '<span class="muted small">' + hint + '</span>' : '') + '</label>'; }
  function chk(id, label, on) { return '<label class="row small" style="gap:6px;cursor:pointer"><input type="checkbox" id="' + id + '"' + (on ? ' checked' : '') + '> ' + label + '</label>'; }
  function opts(list, cur) { return list.map(function (o) { return '<option value="' + o[0] + '"' + (o[0] === cur ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join(''); }

  function renderEditor() {
    var a = AD, t = a.theme, u = a.audience;
    if (!document.getElementById('adAdminCss')) {
      var s = document.createElement('style'); s.id = 'adAdminCss';
      s.textContent = '.adf{display:flex;flex-direction:column;gap:5px;margin-bottom:12px}.adl{font-size:12px;font-weight:700;color:var(--ink2)}.adf input.f,.adf select.f,.adf textarea.f{width:100%}.adg2{display:grid;grid-template-columns:1fr 1fr;gap:12px}' +
        '.adtile{border:1.5px solid var(--border);border-radius:12px;padding:10px;cursor:pointer;text-align:center;font-size:12px;background:var(--bg)}.adtile.on{border-color:var(--accent);background:rgba(99,102,241,.12)}.adtile b{display:block;font-size:13px;margin:3px 0}' +
        '.adedit{display:grid;grid-template-columns:minmax(0,1fr) 380px;gap:18px;align-items:start}@media(max-width:1100px){.adedit{grid-template-columns:1fr}}' +
        '.adpv{position:sticky;top:12px}.adphone{position:relative;width:340px;height:620px;margin:0 auto;border-radius:34px;border:8px solid #0b0d18;background:linear-gradient(160deg,#e8ecf8,#cfd6ee);overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.45)}' +
        '.adphone .fake{position:absolute;inset:0;padding:42px 18px;color:#5b6280;font-size:12px}.adphone .fake i{display:block;height:14px;border-radius:7px;background:rgba(80,90,130,.18);margin:10px 0}' +
        '.addrop{border:2px dashed var(--border);border-radius:14px;padding:18px;text-align:center;cursor:pointer;background:var(--bg)}.addrop.hot{border-color:var(--accent)}' +
        '.sw{width:26px;height:26px;border-radius:50%;border:2px solid transparent;cursor:pointer}.sw.on{border-color:var(--ink)}';
      document.head.appendChild(s);
    }
    var tile = FORMATS.map(function (x) { return '<div class="adtile ' + (a.format === x[0] ? 'on' : '') + '" onclick="AdsAdmin.set(\'format\',\'' + x[0] + '\')"><div style="font-size:22px">' + x[1] + '</div><b>' + x[2] + '</b><span class="muted">' + x[3] + '</span></div>'; }).join('');
    var sw = COLORS.map(function (c) { return '<span class="sw ' + (t.accent === c[0] ? 'on' : '') + '" style="background:' + c[0] + '" onclick="AdsAdmin.accent(\'' + c[0] + '\')"></span>'; }).join('');
    $('mainArea').innerHTML = pageHead(a.id ? 'Modifier la campagne' : 'Nouvelle campagne', 'Les réglages sont visibles tout de suite dans l\'aperçu', '<button class="btn" onclick="goPage(\'ads\')">← Retour</button>') +
      '<div class="adedit"><div>' +

      '<div class="card" style="margin-bottom:14px"><h3>1 · Contenu</h3>' +
      f('Nom interne (visible seulement par vous)', '<input class="f" id="ad_name" maxlength="120" value="' + esc(a.name) + '" placeholder="Ex. Black Friday — partenaire formation">') +
      '<div class="adf"><span class="adl">Média</span><div class="chips"><span class="chip ' + (a.media_type === 'image' ? 'on' : '') + '" onclick="AdsAdmin.set(\'media_type\',\'image\')">🖼 Image</span><span class="chip ' + (a.media_type === 'video' ? 'on' : '') + '" onclick="AdsAdmin.set(\'media_type\',\'video\')">🎬 Mini-vidéo</span><span class="chip ' + (a.media_type === 'none' ? 'on' : '') + '" onclick="AdsAdmin.set(\'media_type\',\'none\')">Texte seul</span></div></div>' +
      (a.media_type !== 'none' ? '<div class="adf"><div class="addrop" id="ad_drop" onclick="$(\'ad_file\').click()"><div style="font-size:26px">⬆️</div><b>' + (a.media_url ? 'Remplacer le fichier' : 'Glissez un fichier ici ou cliquez') + '</b><div class="muted small">' + (a.media_type === 'video' ? 'MP4 ou WebM · 25 Mo max · idéal 9:16 ou 1:1, 5 à 15 s' : 'JPG, PNG, WebP ou GIF · 25 Mo max · idéal 1080×1350 ou 1080×1080') + '</div><div class="small" id="ad_up"></div></div><input type="file" id="ad_file" hidden accept="' + (a.media_type === 'video' ? 'video/mp4,video/webm' : 'image/jpeg,image/png,image/webp,image/gif') + '"></div>' +
        f('…ou URL du média (https)', '<input class="f" id="ad_media" value="' + esc(a.media_url || '') + '" placeholder="https://…">') +
        (a.media_type === 'video' ? f('Image d\'aperçu de la vidéo (facultatif)', '<input class="f" id="ad_poster" value="' + esc(a.poster_url || '') + '" placeholder="https://…">') +
          '<div class="row" style="gap:16px;margin-bottom:12px">' + chk('ad_vauto', 'Lecture automatique', a.video_autoplay) + chk('ad_vmute', 'Sans le son au départ', a.video_muted) + chk('ad_vloop', 'En boucle', a.video_loop) + '</div>' : '') : '') +
      f('Titre', '<input class="f" id="ad_title" maxlength="120" value="' + esc(a.title || '') + '" placeholder="Accroche courte et claire">') +
      f('Texte', '<textarea class="f" id="ad_body" maxlength="400" style="min-height:70px">' + esc(a.body || '') + '</textarea>') +
      '<div class="adg2">' + f('Texte du bouton', '<input class="f" id="ad_cta" maxlength="40" value="' + esc(a.cta_label) + '">') + f('Mention de transparence', '<input class="f" id="ad_sp" maxlength="24" value="' + esc(a.sponsor_label) + '">') + '</div>' +
      f('Lien de destination', '<input class="f" id="ad_link" value="' + esc(a.link_url || '') + '" placeholder="https://site-du-partenaire.com/offre">', 'Au clic sur l\'image ou le bouton, l\'utilisateur est redirigé vers ce lien. L\'annonce reste affichée jusqu\'à la croix.') +
      '<div class="row" style="gap:16px">' + chk('ad_tab', 'Ouvrir dans un nouvel onglet', a.link_new_tab) + chk('ad_utm', 'Ajouter le suivi UTM automatiquement', false) + '</div></div>' +

      '<div class="card" style="margin-bottom:14px"><h3>2 · Comportement</h3>' +
      f('Délai avant de pouvoir fermer : <b id="ad_cd_v">' + a.close_delay_s + ' s</b>', '<input type="range" id="ad_cd" min="0" max="30" value="' + a.close_delay_s + '">', 'La croix apparaît grisée avec un compte à rebours, puis devient active (5 à 10 s recommandé).') +
      '<div class="row" style="gap:16px;margin-bottom:12px">' + chk('ad_allow', 'Afficher la croix de fermeture', a.allow_close) + '</div>' +
      f('Fermeture automatique après (secondes, vide = jamais)', '<input class="f" id="ad_auto" type="number" min="3" max="300" value="' + (a.auto_close_s || '') + '">') + '</div>' +

      '<div class="card" style="margin-bottom:14px"><h3>3 · Apparence</h3><div class="adf"><span class="adl">Format</span><div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(110px,1fr));gap:8px">' + tile + '</div></div>' +
      '<div class="adf"><span class="adl">Couleur du bouton</span><div class="row" style="gap:8px">' + sw + '<input type="color" id="ad_ac" value="' + esc(t.accent) + '" style="width:34px;height:28px;border:0;background:none"></div></div>' +
      '<div class="adg2">' + f('Fond de la carte', '<input type="color" id="ad_bg" value="' + esc(t.bg) + '" style="width:100%;height:34px">') + f('Animation', '<select class="f" id="ad_an">' + opts([['zoom', 'Zoom'], ['slide', 'Glissement'], ['fade', 'Fondu'], ['none', 'Aucune']], t.animation) + '</select>') + '</div>' +
      '<div class="adg2">' + f('Assombrissement du fond : <b id="ad_ov_v">' + t.overlay + ' %</b>', '<input type="range" id="ad_ov" min="0" max="90" value="' + t.overlay + '">') + f('Arrondi : <b id="ad_rd_v">' + t.radius + ' px</b>', '<input type="range" id="ad_rd" min="0" max="40" value="' + t.radius + '">') + '</div>' +
      '<div class="adg2">' + f('Alignement du texte', '<select class="f" id="ad_al">' + opts([['left', 'À gauche'], ['center', 'Centré']], t.align) + '</select>') + '<div style="padding-top:22px">' + chk('ad_spon', 'Afficher le badge « ' + esc(a.sponsor_label) + ' »', t.sponsor !== false) + '</div></div></div>' +

      '<div class="card" style="margin-bottom:14px"><h3>4 · Ciblage</h3><div class="adf"><span class="adl">Formules concernées (aucune cochée = tout le monde)</span><div class="row" style="gap:14px;flex-wrap:wrap">' + PLANS.map(function (p) { return chk('ad_pl_' + p, p, (u.plans || []).indexOf(p) >= 0); }).join('') + '</div></div>' +
      f('Pays (codes ISO séparés par des virgules, vide = tous)', '<input class="f" id="ad_co" value="' + esc((u.countries || []).join(', ')) + '" placeholder="CI, SN, FR">') +
      '<div class="adf"><span class="adl">Appareils (aucun coché = tous)</span><div class="row" style="gap:14px">' + chk('ad_dv_mobile', '📱 Mobile', (u.devices || []).indexOf('mobile') >= 0) + chk('ad_dv_desktop', '💻 Ordinateur', (u.devices || []).indexOf('desktop') >= 0) + '</div></div>' +
      '<div class="adg2">' + f('Compte créé depuis au moins (jours)', '<input class="f" id="ad_min" type="number" min="0" value="' + esc(u.min_account_days) + '">') + f('…et au plus (jours)', '<input class="f" id="ad_max" type="number" min="0" value="' + esc(u.max_account_days) + '">') + '</div>' +
      f('A déjà téléchargé un CV', '<select class="f" id="ad_ex">' + opts([['any', 'Peu importe'], ['yes', 'Oui seulement'], ['no', 'Non seulement']], u.has_exported || 'any') + '</select>') +
      chk('ad_adm', 'Afficher aussi aux comptes administrateurs (pour tester sur votre propre compte)', u.include_admins === true || u.include_admins === 'true') + '</div>' +

      '<div class="card" style="margin-bottom:14px"><h3>5 · Diffusion</h3>' +
      f('Où et quand', '<select class="f" id="ad_pl">' + opts(PLACEMENTS, a.placement) + '</select>') +
      '<div class="adg2">' + f('Délai après le déclencheur (s)', '<input class="f" id="ad_td" type="number" min="0" max="120" value="' + a.trigger_delay_s + '">') + f('Priorité : <b id="ad_pr_v">' + a.priority + '</b> / 10', '<input type="range" id="ad_pr" min="1" max="10" value="' + a.priority + '">', 'Si plusieurs campagnes sont éligibles, la plus haute passe en premier.') + '</div>' +
      '<div class="adg2">' + f('Fréquence', '<select class="f" id="ad_fq">' + opts(FREQ, a.frequency) + '</select>') + f('N (jours)', '<input class="f" id="ad_fd" type="number" min="1" max="90" value="' + a.frequency_days + '">') + '</div>' +
      '<div class="adg2">' + f('Nombre total de vues maximum', '<input class="f" id="ad_mi" type="number" min="1" value="' + (a.max_impressions || '') + '" placeholder="Illimité">') + f('Vues maximum par utilisateur', '<input class="f" id="ad_mu" type="number" min="1" value="' + (a.max_per_user || '') + '" placeholder="Illimité">') + '</div>' +
      '<div class="adg2">' + f('Plafond de vues par jour', '<input class="f" id="ad_dc" type="number" min="1" value="' + (a.daily_cap || '') + '" placeholder="Illimité">') + f('Clics maximum', '<input class="f" id="ad_mc" type="number" min="1" value="' + (a.max_clicks || '') + '" placeholder="Illimité">') + '</div>' +
      '<div class="adg2">' + f('Début', '<input class="f" id="ad_st" type="datetime-local" value="' + toLocal(a.starts_at) + '">') + f('Fin', '<input class="f" id="ad_en" type="datetime-local" value="' + toLocal(a.ends_at) + '">') + '</div>' +
      '<div class="muted small">La campagne s\'arrête automatiquement dès qu\'un plafond ou la date de fin est atteint.</div></div>' +

      '<div class="row" style="gap:10px;flex-wrap:wrap;margin-bottom:30px"><button class="btn" onclick="AdsAdmin.save(false)">💾 Enregistrer en brouillon</button><button class="btn pri" onclick="AdsAdmin.save(true)">🚀 Enregistrer et publier</button>' + (a.id ? '<span class="muted small">Statut actuel : ' + STATUS_FR[a.status] + '</span>' : '') + '</div>' +

      '</div><div class="adpv"><div class="card"><div class="row" style="justify-content:space-between;margin-bottom:10px"><h3 style="margin:0">Aperçu en direct</h3><button class="btn sm" onclick="AdsAdmin.replay()">↻ Rejouer</button></div><div class="adphone" id="ad_phone"><div class="fake"><b>Mes CV</b><i style="width:70%"></i><i></i><i style="width:85%"></i><i style="width:60%"></i><i></i><i style="width:75%"></i></div></div><div class="muted small" style="text-align:center;margin-top:8px">Aperçu : aucun évènement n\'est compté.</div></div></div></div>';
    wire(); preview();
  }

  function collect() {
    var a = AD, g = function (id) { var e = $(id); return e ? e.value : null; }, c = function (id) { var e = $(id); return e ? e.checked : false; };
    if (!$('ad_name')) return;
    a.name = g('ad_name').trim(); a.title = g('ad_title').trim(); a.body = g('ad_body').trim(); a.cta_label = g('ad_cta').trim() || 'En savoir plus'; a.sponsor_label = g('ad_sp').trim() || 'Sponsorisé';
    a.link_url = g('ad_link').trim(); a.link_new_tab = c('ad_tab');
    if ($('ad_media')) a.media_url = g('ad_media').trim(); if ($('ad_poster')) a.poster_url = g('ad_poster').trim();
    if ($('ad_vauto')) { a.video_autoplay = c('ad_vauto'); a.video_muted = c('ad_vmute'); a.video_loop = c('ad_vloop'); }
    a.close_delay_s = +g('ad_cd'); a.allow_close = c('ad_allow'); a.auto_close_s = intOrNull(g('ad_auto'));
    a.theme = { bg: g('ad_bg'), text: '', accent: g('ad_ac'), overlay: +g('ad_ov'), radius: +g('ad_rd'), animation: g('ad_an'), align: g('ad_al'), sponsor: c('ad_spon') };
    a.audience = {
      plans: PLANS.filter(function (p) { return c('ad_pl_' + p); }),
      countries: g('ad_co').split(/[,\s;]+/).map(function (x) { return x.trim().toUpperCase(); }).filter(function (x) { return /^[A-Z]{2}$/.test(x); }),
      devices: ['mobile', 'desktop'].filter(function (d) { return c('ad_dv_' + d); }),
      min_account_days: g('ad_min'), max_account_days: g('ad_max'), has_exported: g('ad_ex'), include_admins: c('ad_adm')
    };
    a.placement = g('ad_pl'); a.trigger_delay_s = intOrNull(g('ad_td')) || 0; a.priority = +g('ad_pr'); a.frequency = g('ad_fq'); a.frequency_days = intOrNull(g('ad_fd')) || 3;
    a.max_impressions = intOrNull(g('ad_mi')); a.max_per_user = intOrNull(g('ad_mu')); a.daily_cap = intOrNull(g('ad_dc')); a.max_clicks = intOrNull(g('ad_mc'));
    a.starts_at = fromLocal(g('ad_st')); a.ends_at = fromLocal(g('ad_en'));
  }
  var pvT = null;
  function preview() {
    clearTimeout(pvT);
    pvT = setTimeout(function () {
      collect(); var box = $('ad_phone'); if (!box) return;
      if (PV) { try { PV.close(); } catch (e) { } }
      box.querySelectorAll('.adx-ov').forEach(function (n) { n.remove(); });
      var ad = JSON.parse(JSON.stringify(AD)); ad.link_url = AD.link_url || null; if (!ad.title && !ad.body && !ad.media_url) ad.title = 'Votre titre ici';
      PV = AdsRender.show(ad, { preview: true, container: box });
    }, 150);
  }
  function wire() {
    var root = $('mainArea');
    root.querySelectorAll('input,select,textarea').forEach(function (e) {
      if (e.type === 'file') return;
      e.addEventListener(e.type === 'range' || e.type === 'text' || e.tagName === 'TEXTAREA' || e.type === 'number' ? 'input' : 'change', function () {
        var m = { ad_cd: ['ad_cd_v', ' s'], ad_ov: ['ad_ov_v', ' %'], ad_rd: ['ad_rd_v', ' px'], ad_pr: ['ad_pr_v', ''] }[e.id]; if (m) $(m[0]).textContent = e.value + m[1];
        preview();
      });
    });
    var fl = $('ad_file'); if (fl) fl.addEventListener('change', function () { if (fl.files[0]) upload(fl.files[0]); });
    var dr = $('ad_drop'); if (dr) {
      ['dragenter', 'dragover'].forEach(function (ev) { dr.addEventListener(ev, function (e) { e.preventDefault(); dr.classList.add('hot'); }); });
      ['dragleave', 'drop'].forEach(function (ev) { dr.addEventListener(ev, function (e) { e.preventDefault(); dr.classList.remove('hot'); }); });
      dr.addEventListener('drop', function (e) { var fi = e.dataTransfer.files[0]; if (fi) upload(fi); });
    }
  }
  async function upload(file) {
    var isV = AD.media_type === 'video', ok = isV ? ['video/mp4', 'video/webm'] : ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
    if (ok.indexOf(file.type) < 0) return toast('Format non accepté (' + (file.type || 'inconnu') + ')', 'bad');
    if (file.size > 25 * 1024 * 1024) return toast('Fichier trop lourd (' + (file.size / 1048576).toFixed(1) + ' Mo, maximum 25)', 'bad');
    var st = $('ad_up'); st.textContent = '⏳ Envoi de ' + file.name + ' (' + (file.size / 1048576).toFixed(1) + ' Mo)…';
    var ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, ''), path = new Date().getFullYear() + '/' + slug(AD.name || 'annonce') + '-' + Date.now().toString(36) + '.' + ext;
    var r = await sb.storage.from('ad-media').upload(path, file, { contentType: file.type, cacheControl: '31536000', upsert: false });
    if (r.error) { st.textContent = ''; return toast('Envoi impossible : ' + (r.error.message || r.error) + '. Vérifiez que le bucket « ad-media » existe (migration SQL).', 'bad'); }
    var url = sb.storage.from('ad-media').getPublicUrl(path).data.publicUrl;
    collect(); AD.media_url = url; $('ad_media').value = url; st.textContent = '✅ Fichier envoyé'; preview(); toast('Média envoyé', 'ok');
  }

  function applyUtm(url, name) {
    try { var u = new URL(url); if (!u.searchParams.has('utm_source')) { u.searchParams.set('utm_source', 'cvxmaker'); u.searchParams.set('utm_medium', 'app_ad'); u.searchParams.set('utm_campaign', slug(name)); } return u.href; } catch (e) { return url; }
  }
  function validate(a, publish) {
    if (!a.name) return 'Donnez un nom interne à la campagne.';
    if (a.media_type !== 'none' && a.media_url && !/^https:\/\//i.test(a.media_url)) return 'L\'URL du média doit commencer par https://';
    if (a.poster_url && !/^https:\/\//i.test(a.poster_url)) return 'L\'URL de l\'aperçu vidéo doit commencer par https://';
    if (a.link_url && !/^https?:\/\//i.test(a.link_url)) return 'Le lien doit commencer par http:// ou https://';
    if (a.starts_at && a.ends_at && new Date(a.ends_at) <= new Date(a.starts_at)) return 'La date de fin doit être après le début.';
    if (publish) {
      if (a.media_type !== 'none' && !a.media_url) return 'Ajoutez une image ou une vidéo (ou choisissez « Texte seul »).';
      if (!a.title && !a.body && !a.media_url) return 'Ajoutez un titre, un texte ou un média.';
      if (a.ends_at && new Date(a.ends_at) <= new Date()) return 'La date de fin est déjà passée.';
    }
    return null;
  }
  function row(a) {
    var au = Object.assign({}, a.audience); au.min_account_days = au.min_account_days === '' ? '' : String(au.min_account_days); au.max_account_days = au.max_account_days === '' ? '' : String(au.max_account_days);
    return { name: a.name, priority: a.priority, format: a.format, media_type: a.media_type, media_url: a.media_type === 'none' ? null : (a.media_url || null), poster_url: a.media_type === 'video' ? (a.poster_url || null) : null,
      title: a.title || null, body: a.body || null, cta_label: a.cta_label, link_url: a.link_url || null, link_new_tab: a.link_new_tab, sponsor_label: a.sponsor_label,
      close_delay_s: a.close_delay_s, allow_close: a.allow_close, auto_close_s: a.auto_close_s, video_autoplay: a.video_autoplay, video_muted: a.video_muted, video_loop: a.video_loop,
      theme: a.theme, audience: au, placement: a.placement, trigger_delay_s: a.trigger_delay_s, frequency: a.frequency, frequency_days: a.frequency_days,
      max_impressions: a.max_impressions, max_per_user: a.max_per_user, daily_cap: a.daily_cap, max_clicks: a.max_clicks, starts_at: a.starts_at, ends_at: a.ends_at };
  }
  async function save(publish) {
    collect(); var a = AD;
    if (($('ad_utm') || {}).checked && a.link_url) { a.link_url = applyUtm(a.link_url, a.name); $('ad_link').value = a.link_url; }
    var err = validate(a, publish); if (err) return toast(err, 'bad');
    try {
      var r;
      if (a.id) r = await sb.from('ad_campaigns').update(row(a)).eq('id', a.id).select('id').single();
      else { var rw = row(a); rw.created_by = admin.id; rw.status = 'draft'; r = await sb.from('ad_campaigns').insert(rw).select('id').single(); }
      if (r.error) throw r.error; a.id = r.data.id;
      sb.rpc('admin_log', { p_action: 'ad.save', p_type: 'ad_campaign', p_id: a.id, p_data: { name: a.name } });
      if (publish) await rpc('admin_ad_set_status', { p_id: a.id, p_status: 'active' });
      toast(publish ? 'Campagne publiée 🚀' : 'Brouillon enregistré', 'ok'); goPage('ads');
    } catch (e) { toast(userMsg(e), 'bad'); }
  }

  /* ═════════════ ACTIONS ═════════════ */
  async function setStatus(id, s) {
    if (await act(function () { return rpc('admin_ad_set_status', { p_id: id, p_status: s }); }, s === 'active' ? 'Campagne en ligne' : 'Campagne mise en pause')) loadList();
  }
  async function dup(id) { if (await act(function () { return rpc('admin_ad_duplicate', { p_id: id }); }, 'Copie créée en brouillon')) loadList(); }
  function del(id, name) {
    ask('Supprimer la campagne', 'Supprimer « ' + esc(name) + ' » et toutes ses statistiques ? Cette action est définitive.', 'Supprimer', async function () {
      var r = await sb.from('ad_campaigns').delete().eq('id', id); if (r.error) { toast(userMsg(r.error), 'bad'); return false; }
      sb.rpc('admin_log', { p_action: 'ad.delete', p_type: 'ad_campaign', p_id: id, p_data: { name: name } }); loadList();
    }, true);
  }
  async function stats(id) {
    openModal('<h3>Statistiques</h3>' + loading(), true);
    try {
      var s = await rpc('admin_ad_stats', { p_campaign: id, p_days: 30 }), c = s.campaign || {};
      var closeRate = c.impressions ? Math.round(c.closes / c.impressions * 100) : 0, vid = c.media_type === 'video' ? '<div class="kpi"><div class="l">Vidéos vues en entier</div><div class="v">' + nf(c.video_completions) + '</div><div class="d flat">' + (c.impressions ? Math.round(c.video_completions / c.impressions * 100) : 0) + ' % des vues</div></div>' : '';
      var st = liveState(c);
      $('modal').innerHTML = '<h3>' + esc(c.name) + ' <span class="badge ' + st[1] + '">' + esc(st[0]) + '</span></h3>' +
        '<div class="grid g-kpi" style="margin-bottom:12px"><div class="kpi"><div class="l">Vues</div><div class="v">' + nf(c.impressions) + '</div>' + (c.max_impressions ? '<div class="d flat">sur ' + nf(c.max_impressions) + '</div>' : '') + '</div><div class="kpi"><div class="l">Utilisateurs uniques</div><div class="v">' + nf(c.unique_viewers) + '</div></div><div class="kpi"><div class="l">Clics</div><div class="v">' + nf(c.clicks) + '</div><div class="d flat">CTR ' + ctr(c) + '</div></div><div class="kpi"><div class="l">Fermetures</div><div class="v">' + nf(c.closes) + '</div><div class="d flat">' + closeRate + ' % des vues</div></div>' + vid + '</div>' +
        '<div class="card" style="margin-bottom:12px"><h3>Vues par jour (30 j)</h3>' + lineChart(s.imp_series, { color: PAL[0] }) + '</div><div class="card" style="margin-bottom:12px"><h3>Clics par jour</h3>' + lineChart(s.clk_series, { color: PAL[1] }) + '</div>' +
        '<div class="grid g3" style="margin-bottom:12px"><div class="card"><h3>Emplacement</h3>' + bars(s.by_placement || []) + '</div><div class="card"><h3>Appareil</h3>' + bars(s.by_device || [], { color: 3 }) + '</div><div class="card"><h3>Formule</h3>' + bars(s.by_plan || [], { color: 2 }) + '</div></div>' +
        '<div class="card"><h3>Derniers évènements</h3>' + ((s.last_events || []).map(function (e) { return '<div class="list-item"><span>' + ({ impression: '👁 Vue', click: '🖱 Clic', close: '✕ Fermeture', video_complete: '🎬 Vidéo terminée' }[e.event] || esc(e.event)) + ' <span class="muted small">' + esc(e.email || '') + ' · ' + esc(e.device || '') + '</span></span><span class="muted small">' + ago(e.created_at) + '</span></div>'; }).join('') || '<div class="muted small">Aucun évènement.</div>') + '</div>' +
        '<div class="acts"><button class="btn" onclick="AdsAdmin.csv(\'' + id + '\')">⬇ Export CSV</button>' + (can(3) ? '<button class="btn danger" onclick="AdsAdmin.reset(\'' + id + '\')">Remettre à zéro</button>' : '') + '<button class="btn pri" onclick="closeAll()">Fermer</button></div>';
      AdsAdmin._s = s;
    } catch (e) { $('modal').innerHTML = '<h3>Statistiques</h3>' + errBox(e) + '<div class="acts"><button class="btn" onclick="closeAll()">Fermer</button></div>'; }
  }
  function csv() {
    var s = AdsAdmin._s; if (!s) return; var clk = {}, cl = {};
    (s.clk_series || []).forEach(function (x) { clk[x.d] = x.v; }); (s.close_series || []).forEach(function (x) { cl[x.d] = x.v; });
    csvDownload('campagne-' + slug(s.campaign.name), ['Date', 'Vues', 'Clics', 'Fermetures'], (s.imp_series || []).map(function (x) { return [x.d, x.v, clk[x.d] || 0, cl[x.d] || 0]; }));
  }
  function reset(id) { ask('Remettre à zéro', 'Les compteurs et l\'historique de cette campagne seront effacés. Les utilisateurs pourront revoir l\'annonce.', 'Remettre à zéro', async function () { if (await act(function () { return rpc('admin_ad_reset_stats', { p_id: id }); }, 'Statistiques remises à zéro')) loadList(); }, true); }

  w_export();
  function w_export() {
    window.AdsAdmin = {
      reload: loadList, filter: function (k) { AD_FILTER = k; loadList(); }, status: setStatus, dup: dup, del: del, stats: stats, csv: csv, reset: reset, save: save,
      set: function (k, v) { collect(); AD[k] = v; if (k === 'media_type' && v === 'video') { AD.media_url = ''; } renderEditor(); },
      accent: function (c) { collect(); AD.theme.accent = c; renderEditor(); },
      replay: function () { collect(); preview(); }
    };
  }

  /* ═════════════ UTILISATEURS EN DIRECT ═════════════ */
  var LIVE_DAYS = 30;
  PAGEFN.live = async function pageLive() {
    $('mainArea').innerHTML = pageHead('Utilisateurs en direct', 'Combien de personnes utilisent CVxMaker, maintenant et dans le temps',
      '<div class="chips">' + [14, 30, 90].map(function (d) { return '<span class="chip ' + (d === LIVE_DAYS ? 'on' : '') + '" onclick="LIVE_DAYS_SET(' + d + ')">' + d + ' j</span>'; }).join('') + '</div>') + '<div id="liveBody">' + loading() + '</div>';
    await draw(); AUTO = setInterval(draw, 30000);
  };
  window.LIVE_DAYS_SET = function (d) { LIVE_DAYS = d; goPage('live'); };
  async function draw() {
    if (CURRENT !== 'live') return;
    try {
      var s = await rpc('admin_user_stats', { p_days: LIVE_DAYS }), g = s.new_30 - s.new_prev_30;
      var K = function (l, v, d) { return '<div class="kpi"><div class="l">' + l + '</div><div class="v">' + v + '</div>' + (d ? '<div class="d flat">' + d + '</div>' : '') + '</div>'; };
      var hrs = []; for (var h = 0; h < 24; h++) { var x = (s.hours || []).filter(function (r) { return r.id === h; })[0]; hrs.push({ id: (h < 10 ? '0' : '') + h + ' h', n: x ? x.n : 0 }); }
      var plans = Object.keys(s.plans || {}).map(function (k) { return { id: k, n: s.plans[k] }; });
      $('liveBody').innerHTML =
        '<div class="grid g-kpi" style="margin-bottom:14px">' +
        K('🟢 En ligne maintenant', nf(s.online_now), nf(s.online_30m) + ' dans les 30 dernières min') +
        K('Utilisateurs inscrits', nf(s.total), nf(s.new_today) + ' aujourd\'hui · ' + nf(s.new_7) + ' cette semaine') +
        K('Actifs aujourd\'hui', nf(s.active_today), 'hier : ' + nf(s.active_yesterday)) +
        K('Actifs 7 j / 30 j', nf(s.wau) + ' <span class="muted" style="font-size:14px">/ ' + nf(s.mau) + '</span>', s.total ? Math.round(s.mau / s.total * 100) + ' % de la base' : '') +
        K('Nouveaux (30 j)', nf(s.new_30), (g >= 0 ? '▲ +' : '▼ ') + g + ' vs 30 j précédents') +
        K('Reviennent (7 j)', nf(s.returning_7), 'inscrits > 7 j et revenus') +
        K('Ont un CV', nf(s.with_cv), s.total ? Math.round(s.with_cv / s.total * 100) + ' % des inscrits' : '') +
        K('Ont téléchargé', nf(s.exporters), s.total ? Math.round(s.exporters / s.total * 100) + ' % des inscrits' : '') + '</div>' +
        (s.tracking_since ? '' : '<div class="alert" style="margin-bottom:14px">Le suivi de présence démarre à la première connexion après la mise à jour. Les chiffres « actifs » se rempliront dans les heures qui viennent.</div>') +
        '<div class="grid g2" style="margin-bottom:14px"><div class="card"><h3>Utilisateurs actifs par jour</h3>' + lineChart(s.dau_series, { color: PAL[1] }) + '</div><div class="card"><h3>Nouvelles inscriptions par jour</h3>' + lineChart(s.signup_series, { color: PAL[0] }) + '</div></div>' +
        '<div class="grid g3" style="margin-bottom:14px"><div class="card"><h3>Heures d\'activité (14 j)</h3>' + bars(hrs.filter(function (x) { return x.n > 0; }).slice(0, 24)) + '</div><div class="card"><h3>Formules</h3>' + donut(plans) + '</div><div class="card"><h3>Pays</h3>' + bars(s.countries || [], { color: 3 }) + '</div></div>' +
        '<div class="card"><h3>En ligne en ce moment</h3>' + ((s.online_users || []).map(function (u) { return '<div class="list-item"><a style="cursor:pointer" onclick="openUser(\'' + u.id + '\')">' + esc(u.email || u.name) + '</a><span class="muted small">' + planBadge(u.plan) + ' ' + esc(u.country || '') + ' · ' + ago(u.last_seen_at) + '</span></div>'; }).join('') || '<div class="muted small">Personne en ce moment.</div>') + '</div>' +
        '<div class="muted small" style="margin-top:8px">Actualisation automatique toutes les 30 secondes · « en ligne » = activité dans les 5 dernières minutes.</div>';
    } catch (e) { $('liveBody').innerHTML = errBox(e); }
  }
  /* lien direct #ads / #live : la page principale s'est ouverte avant le chargement de ce fichier */
  var hh = window.__H0 || '', tries = 0;
  if (hh === 'ads' || hh === 'live') { var iv = setInterval(function () { tries++; try { if (typeof admin !== 'undefined' && admin) { clearInterval(iv); if (CURRENT !== hh) goPage(hh); } } catch (e) { } if (tries > 40) clearInterval(iv); }, 250); }
})();
