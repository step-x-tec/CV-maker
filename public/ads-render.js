/* CVxMaker — rendu des annonces (partagé : application + aperçu de l'admin)
 *
 *  AdsRender.show(ad, { preview, container, onEvent(type), onClose })  → { close(), el }
 *  AdsEngine.init({ sb, getUser, canShow })  /  AdsEngine.trigger(placement)
 *  Presence.start(sb)
 *
 *  Règles : lien http(s) uniquement · clic = on ouvre la source, l'annonce reste jusqu'à la croix ·
 *  croix active après `close_delay_s` secondes (compte à rebours visible) · tout texte échappé (textContent).
 */
(function (w) {
  'use strict';
  var d = document;

  function css() {
    if (d.getElementById('adsCss')) return;
    var s = d.createElement('style'); s.id = 'adsCss';
    s.textContent = [
      '.adx-ov{position:fixed;inset:0;z-index:99990;display:flex;padding:16px;background:rgba(8,10,20,var(--adx-ov,.62));backdrop-filter:blur(3px);opacity:0;transition:opacity .25s}',
      '.adx-ov.in{opacity:1}',
      '.adx-ov.pop{align-items:center;justify-content:center}',
      '.adx-ov.full{padding:0;align-items:stretch;justify-content:stretch}',
      '.adx-ov.sheet{align-items:flex-end;justify-content:center;padding:0}',
      '.adx-ov.banner{inset:auto 0 0 0;background:none;backdrop-filter:none;padding:10px;pointer-events:none}',
      '.adx-ov.corner{inset:auto 0 0 auto;background:none;backdrop-filter:none;padding:14px;pointer-events:none;max-width:340px}',
      '.adx-ov.banner .adx,.adx-ov.corner .adx{pointer-events:auto}',
      '.adx{position:relative;display:flex;flex-direction:column;overflow:hidden;width:100%;max-width:420px;max-height:92vh;font-family:inherit;',
      ' background:var(--adx-bg,#fff);color:var(--adx-tx,#111827);border-radius:var(--adx-r,18px);box-shadow:0 24px 60px rgba(0,0,0,.35)}',
      '.adx-ov.full .adx{max-width:none;max-height:none;height:100%;border-radius:0}',
      '.adx-ov.sheet .adx{max-width:520px;border-radius:var(--adx-r,18px) var(--adx-r,18px) 0 0}',
      '.adx-ov.banner .adx{max-width:560px;margin:0 auto;flex-direction:row;align-items:center}',
      '.adx-ov.banner .adx-m{width:92px;min-width:92px;height:92px;max-height:none}',
      '.adx-ov.banner .adx-b{padding:10px 40px 10px 12px;gap:4px}',
      '.adx-ov.corner .adx{max-width:300px}',
      '.adx-ov.corner .adx-m{max-height:150px}',
      /* animations */
      '.adx.a-zoom{animation:adxZoom .32s cubic-bezier(.2,.9,.3,1.2)}.adx.a-slide{animation:adxSlide .34s cubic-bezier(.2,.8,.2,1)}.adx.a-fade{animation:adxFade .3s}.adx.a-none{animation:none}',
      '@keyframes adxZoom{from{transform:scale(.86);opacity:0}to{transform:none;opacity:1}}',
      '@keyframes adxSlide{from{transform:translateY(40px);opacity:0}to{transform:none;opacity:1}}',
      '@keyframes adxFade{from{opacity:0}to{opacity:1}}',
      '.adx-m{position:relative;width:100%;background:#0b1020;flex:0 1 auto;min-height:0;display:flex;align-items:center;justify-content:center;cursor:pointer;max-height:56vh}',
      '.adx-ov.full .adx-m{flex:1 1 auto;max-height:none}',
      '.adx-m img,.adx-m video{display:block;width:100%;height:100%;max-height:inherit;object-fit:cover}',
      '.adx-ov.pop .adx-m img,.adx-ov.pop .adx-m video,.adx-ov.sheet .adx-m img,.adx-ov.sheet .adx-m video{height:auto;object-fit:contain;max-height:56vh}',
      '.adx-ov.full .adx-m img,.adx-ov.full .adx-m video{object-fit:contain}',
      '.adx-b{display:flex;flex-direction:column;gap:8px;padding:16px 18px 18px;text-align:var(--adx-al,left)}',
      '.adx-t{margin:0;font-size:18px;line-height:1.25;font-weight:800;letter-spacing:-.01em}',
      '.adx-p{margin:0;font-size:14px;line-height:1.5;opacity:.82;white-space:pre-line}',
      '.adx-cta{appearance:none;border:0;cursor:pointer;font:inherit;font-weight:700;font-size:15px;padding:12px 18px;border-radius:calc(var(--adx-r,18px) * .65);background:var(--adx-ac,#4f46e5);color:var(--adx-ac-tx,#fff);margin-top:4px;text-align:center;text-decoration:none;display:block}',
      '.adx-cta:active{transform:scale(.98)}',
      '.adx-sp{position:absolute;left:10px;top:10px;z-index:3;font-size:10.5px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;padding:3px 8px;border-radius:99px;background:rgba(0,0,0,.55);color:#fff;pointer-events:none}',
      '.adx-x{position:absolute;right:10px;top:10px;z-index:4;min-width:34px;height:34px;padding:0 10px;border-radius:99px;border:0;font:inherit;font-weight:700;font-size:12.5px;display:flex;align-items:center;justify-content:center;gap:6px;background:rgba(0,0,0,.62);color:#fff;cursor:not-allowed}',
      '.adx-x.on{cursor:pointer;background:rgba(0,0,0,.78);font-size:18px;line-height:1}',
      '.adx-x.on:hover{background:#000}',
      '.adx-bar{position:absolute;left:0;bottom:0;height:3px;width:100%;background:var(--adx-ac,#4f46e5);transform-origin:left;transform:scaleX(0);z-index:3}',
      '.adx-snd{position:absolute;left:10px;bottom:10px;z-index:3;width:34px;height:34px;border-radius:50%;border:0;background:rgba(0,0,0,.6);color:#fff;font-size:15px;cursor:pointer}',
      '@media (prefers-reduced-motion:reduce){.adx{animation:none!important}.adx-ov{transition:none}}'
    ].join('');
    d.head.appendChild(s);
  }

  function safeUrl(u) {
    try { var x = new URL(u, location.href); return (x.protocol === 'https:' || x.protocol === 'http:') ? x.href : null; } catch (e) { return null; }
  }
  function el(tag, cls, txt) { var e = d.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }
  function hex(c, fb) { return (typeof c === 'string' && /^#[0-9a-f]{3,8}$/i.test(c)) ? c : fb; }
  function readable(bg) {
    var h = (bg || '').replace('#', ''); if (h.length === 3) h = h.replace(/(.)/g, '$1$1');
    var r = parseInt(h.substr(0, 2), 16), g = parseInt(h.substr(2, 2), 16), b = parseInt(h.substr(4, 2), 16);
    if (isNaN(r)) return '#fff';
    return (r * 299 + g * 587 + b * 114) / 1000 > 150 ? '#111827' : '#fff';
  }

  function show(ad, opt) {
    opt = opt || {}; css();
    var th = ad.theme || {};
    var fmt = ({ popup: 'pop', fullscreen: 'full', banner: 'banner', sheet: 'sheet', corner: 'corner' })[ad.format] || 'pop';
    var ov = el('div', 'adx-ov ' + fmt);
    ov.setAttribute('role', 'dialog'); ov.setAttribute('aria-modal', fmt === 'banner' || fmt === 'corner' ? 'false' : 'true');
    ov.setAttribute('aria-label', ad.title || 'Annonce');
    var bg = hex(th.bg, '#ffffff'), ac = hex(th.accent, '#4f46e5');
    ov.style.setProperty('--adx-ov', String(Math.min(90, Math.max(0, +(th.overlay != null ? th.overlay : 62))) / 100));
    var box = el('div', 'adx a-' + (['zoom', 'slide', 'fade', 'none'].indexOf(th.animation) >= 0 ? th.animation : (fmt === 'sheet' || fmt === 'banner' || fmt === 'corner' ? 'slide' : 'zoom')));
    box.style.setProperty('--adx-bg', bg);
    box.style.setProperty('--adx-tx', hex(th.text, readable(bg)));
    box.style.setProperty('--adx-ac', ac);
    box.style.setProperty('--adx-ac-tx', readable(ac));
    box.style.setProperty('--adx-r', Math.min(40, Math.max(0, +(th.radius != null ? th.radius : 18))) + 'px');
    box.style.setProperty('--adx-al', th.align === 'center' ? 'center' : 'left');
    ov.appendChild(box);

    var link = ad.link_url ? safeUrl(ad.link_url) : null;
    var closed = false, timers = [], tracked = {};
    function emit(t, once) { if (once && tracked[t]) return; tracked[t] = 1; if (!opt.preview && opt.onEvent) try { opt.onEvent(t); } catch (e) { } }
    function go() {
      if (!link) return;
      emit('click');
      if (opt.preview) return;
      if (ad.link_new_tab === false) { w.location.href = link; }
      else { var a = w.open(link, '_blank', 'noopener,noreferrer'); if (!a) w.location.href = link; }
    }

    // média
    var media = null, vid = null;
    if (ad.media_type !== 'none' && ad.media_url && safeUrl(ad.media_url)) {
      media = el('div', 'adx-m');
      if (ad.media_type === 'video') {
        vid = d.createElement('video');
        vid.src = safeUrl(ad.media_url); if (ad.poster_url && safeUrl(ad.poster_url)) vid.poster = safeUrl(ad.poster_url);
        vid.playsInline = true; vid.setAttribute('playsinline', ''); vid.preload = 'auto';
        vid.muted = ad.video_muted !== false; vid.loop = !!ad.video_loop; vid.autoplay = ad.video_autoplay !== false;
        vid.addEventListener('ended', function () { emit('video_complete', true); });
        if (vid.autoplay) { var pp = vid.play(); if (pp && pp.catch) pp.catch(function () { vid.muted = true; vid.play().catch(function () { }); }); }
        media.appendChild(vid);
        var snd = el('button', 'adx-snd', vid.muted ? '🔇' : '🔊'); snd.type = 'button'; snd.setAttribute('aria-label', 'Activer ou couper le son');
        snd.onclick = function (e) { e.stopPropagation(); vid.muted = !vid.muted; snd.textContent = vid.muted ? '🔇' : '🔊'; if (!vid.paused) return; vid.play().catch(function () { }); };
        media.appendChild(snd);
      } else {
        var im = d.createElement('img'); im.src = safeUrl(ad.media_url); im.alt = ad.title || ''; im.decoding = 'async';
        media.appendChild(im);
      }
      if (link) media.addEventListener('click', go);
      box.appendChild(media);
    }
    if (th.sponsor !== false) box.appendChild(el('span', 'adx-sp', ad.sponsor_label || 'Sponsorisé'));

    // texte + bouton
    if (ad.title || ad.body || link) {
      var b = el('div', 'adx-b');
      if (ad.title) b.appendChild(el('h3', 'adx-t', ad.title));
      if (ad.body) b.appendChild(el('p', 'adx-p', ad.body));
      if (link) {
        var cta = el('a', 'adx-cta', ad.cta_label || 'En savoir plus');
        cta.href = link; cta.rel = 'noopener noreferrer sponsored'; if (ad.link_new_tab !== false) cta.target = '_blank';
        cta.addEventListener('click', function (e) { e.preventDefault(); go(); });
        b.appendChild(cta);
      }
      box.appendChild(b);
    }

    // croix avec compte à rebours
    var x = el('button', 'adx-x'); x.type = 'button';
    var delay = ad.allow_close === false ? null : Math.max(0, +ad.close_delay_s || 0);
    function enable() { x.classList.add('on'); x.textContent = '✕'; x.setAttribute('aria-label', 'Fermer l\'annonce'); x.disabled = false; }
    function close(why) {
      if (closed) return; closed = true;
      timers.forEach(clearInterval); timers.forEach(clearTimeout);
      d.removeEventListener('keydown', onKey, true);
      if (vid) try { vid.pause(); vid.removeAttribute('src'); vid.load(); } catch (e) { }
      emit('close');
      ov.classList.remove('in');
      setTimeout(function () { if (ov.parentNode) ov.parentNode.removeChild(ov); if (opt.onClose) opt.onClose(why); }, 230);
    }
    function onKey(e) { if (e.key === 'Escape' && x.classList.contains('on')) { e.stopPropagation(); close('esc'); } }
    if (delay !== null) {
      box.appendChild(x);
      x.onclick = function (e) { e.stopPropagation(); if (x.classList.contains('on')) close('x'); };
      if (delay <= 0) enable();
      else {
        var left = delay; x.disabled = true; x.textContent = 'Fermer dans ' + left; x.setAttribute('aria-label', 'Fermer dans ' + left + ' secondes');
        timers.push(setInterval(function () { left--; if (left <= 0) { clearInterval(timers[0]); enable(); } else x.textContent = 'Fermer dans ' + left; }, 1000));
      }
    }
    if (ad.auto_close_s) {
      var bar = el('div', 'adx-bar'); box.appendChild(bar);
      bar.style.transition = 'transform ' + ad.auto_close_s + 's linear'; requestAnimationFrame(function () { requestAnimationFrame(function () { bar.style.transform = 'scaleX(1)'; }); });
      timers.push(setTimeout(function () { close('auto'); }, ad.auto_close_s * 1000));
    }
    d.addEventListener('keydown', onKey, true);

    (opt.container || d.body).appendChild(ov);
    if (opt.container) { ov.style.position = 'absolute'; }
    requestAnimationFrame(function () { ov.classList.add('in'); });
    emit('impression', true);
    return { el: ov, close: function () { close('api'); } };
  }

  // ───────── moteur de diffusion (application) ─────────
  var E = { sb: null, session: null, current: null, last: 0, busy: false, opts: {} };
  function sid() {
    try { var s = sessionStorage.getItem('adx_sid'); if (!s) { s = (w.crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(36).slice(2); sessionStorage.setItem('adx_sid', s); } return s; }
    catch (e) { return E.session || (E.session = String(Date.now())); }
  }
  function device() { return w.matchMedia && w.matchMedia('(min-width: 900px)').matches ? 'desktop' : 'mobile'; }
  E.init = function (o) { E.sb = o.sb; E.opts = o || {}; };
  E.trigger = function (placement) {
    if (!E.sb || E.busy || E.current) return;
    if (E.opts.canShow && !E.opts.canShow()) return;
    if (Date.now() - E.last < 150000 && placement !== 'after_export') return; // 1 annonce / 2,5 min max
    E.busy = true;
    E.sb.rpc('ads_pick', { p_placement: placement, p_device: device(), p_session: sid() }).then(function (r) {
      E.busy = false;
      var ad = r && r.data; if (!ad || !ad.id) return;
      setTimeout(function () {
        if (E.current || (E.opts.canShow && !E.opts.canShow())) return;
        E.last = Date.now();
        E.current = show(ad, {
          onEvent: function (t) { E.sb.rpc('ads_track', { p_campaign: ad.id, p_event: t, p_session: sid(), p_placement: placement, p_device: device() }).then(function () { }, function () { }); },
          onClose: function () { E.current = null; }
        });
      }, Math.max(0, (ad.trigger_delay_s || 0)) * 1000);
    }, function () { E.busy = false; });
  };

  // ───────── présence (en ligne / actifs) ─────────
  var P = { t: null };
  P.start = function (sb) {
    if (P.t) return;
    function ping() { if (d.visibilityState === 'visible') sb.rpc('touch_presence').then(function () { }, function () { }); }
    ping(); P.t = setInterval(ping, 120000);
    d.addEventListener('visibilitychange', function () { if (d.visibilityState === 'visible') ping(); });
  };
  P.stop = function () { clearInterval(P.t); P.t = null; };

  w.AdsRender = { show: show };
  w.AdsEngine = E;
  w.Presence = P;
})(window);
