# -*- coding: utf-8 -*-
"""Génère les pages SEO, sitemap.xml, robots.txt, llms.txt, l'image de partage et met à jour index.html.
Usage :  python3 tools/build_seo.py [https://votre-domaine.com]
Relancer avec le nouveau domaine quand vous en aurez un : tout est régénéré (canonical, sitemap, balises)."""
import sys, os, re, json, html, datetime
sys.path.insert(0, os.path.dirname(__file__))
from seo_content import PAGES, ARTICLES, HOME_FAQ
ALL = PAGES + ARTICLES

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PUB = os.path.join(ROOT, 'public')
BASE = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get('SITE_BASE', 'https://cvxmaker.netlify.app')).rstrip('/')
TODAY = os.environ.get('SEO_DATE', datetime.date.today().isoformat())
E = html.escape
SITE = 'CVxMaker'
OG_IMG = BASE + '/assets/og-cvxmaker.png'
GSC_TOKEN = 'jPniFugUSK36Cj67q9cHcqI7tHJomW1wsIybUcWMcC0'   # Google Search Console (balise de vérification)

def jl(obj):
    return '<script type="application/ld+json">' + json.dumps(obj, ensure_ascii=False, separators=(',', ':')) + '</script>'

def faq_ld(faq):
    return {"@context": "https://schema.org", "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faq]}

ORG = {"@context": "https://schema.org", "@type": "Organization", "name": SITE, "url": BASE + '/',
       "logo": BASE + '/icons/icon-512.png'}
WEBSITE = {"@context": "https://schema.org", "@type": "WebSite", "name": SITE, "url": BASE + '/', "inLanguage": "fr"}
APP = {"@context": "https://schema.org", "@type": "WebApplication", "name": SITE, "url": BASE + '/',
       "applicationCategory": "BusinessApplication", "operatingSystem": "Web, Android, iOS", "inLanguage": "fr",
       "description": "Créateur de CV en ligne : 50 modèles, score ATS, lettres de motivation, export PDF et Word.",
       "offers": {"@type": "Offer", "price": "0", "priceCurrency": "XOF"}}

CSS = """:root{--bg:#F6F4EF;--ink:#211D2C;--ink2:#5d5868;--nav:#1B1640;--accent:#B0691E;--border:#E7E2D8}
*{box-sizing:border-box}html,body{margin:0;background:var(--bg);color:var(--ink);font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;line-height:1.65}
a{color:#8A5113}.wrap{max-width:820px;margin:0 auto;padding:0 20px}
.nav{background:#fff;border-bottom:1px solid var(--border)}.nav .wrap{display:flex;align-items:center;justify-content:space-between;height:60px;max-width:1080px}
.logo{display:flex;align-items:center;gap:9px;font-weight:800;color:var(--nav);text-decoration:none}.logo img{width:28px;height:28px;border-radius:8px}
.btn{display:inline-block;padding:12px 22px;border-radius:99px;font-weight:700;font-size:14px;background:linear-gradient(135deg,#C97D2C,#B0691E);color:#fff;text-decoration:none}
.crumb{font-size:12.5px;color:var(--ink2);margin:18px 0 0}.crumb a{color:#4F4A5A}
h1{font-size:32px;line-height:1.2;margin:14px 0 12px;color:var(--nav)}h2{font-size:21px;margin:30px 0 8px;color:var(--nav)}
.lead{font-size:17px;color:var(--ink2)}li{margin:6px 0}
.cta{background:var(--nav);color:#fff;border-radius:18px;padding:26px;margin:34px 0;text-align:center}.cta p{margin:0 0 14px;color:#cbd5e1}
.faq details{background:#fff;border:1px solid var(--border);border-radius:12px;padding:12px 16px;margin:8px 0}.faq summary{font-weight:700;cursor:pointer}
.rel{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;padding:0;list-style:none}.rel a{display:block;background:#fff;border:1px solid var(--border);border-radius:12px;padding:12px 14px;text-decoration:none;font-weight:600}
footer{background:var(--nav);color:#94a3b8;padding:28px 0;margin-top:40px;font-size:13px}footer a{color:#cbd5e1;margin-right:6px;display:inline-block;padding:12px 8px}
@media(max-width:600px){h1{font-size:26px}}"""

TITLES = {p['slug']: p['h1'] for p in ALL}
SHORT = {p['slug']: re.sub(r'\s*[:|—].*$', '', p['h1']) for p in ALL}

def page_html(p):
    url = f"{BASE}/{p['slug']}"
    body = ''.join(f"<h2>{E(h)}</h2>{c}" for h, c in p['sections'])
    faq = ''.join(f"<details><summary>{E(q)}</summary><p>{E(a)}</p></details>" for q, a in p['faq'])
    rel = ''.join(f'<li><a href="/{s}">{E(TITLES[s])}</a></li>' for s in p['related'])
    crumbs = {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "Accueil", "item": BASE + '/'},
        {"@type": "ListItem", "position": 2, "name": p['h1'], "item": url}]}
    article = {"@context": "https://schema.org", "@type": "Article", "headline": p['h1'], "description": p['desc'],
               "inLanguage": "fr", "mainEntityOfPage": url, "dateModified": TODAY, "datePublished": TODAY,
               "image": OG_IMG, "author": {"@type": "Organization", "name": SITE},
               "publisher": {"@type": "Organization", "name": SITE, "logo": {"@type": "ImageObject", "url": BASE + '/icons/icon-512.png'}}}
    return f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{E(p['title'])}</title>
<meta name="description" content="{E(p['desc'])}">
<link rel="canonical" href="{url}">
<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
<link rel="alternate" hreflang="fr" href="{url}">
<link rel="alternate" hreflang="x-default" href="{url}">
<meta name="theme-color" content="#1B1640">
<link rel="icon" type="image/svg+xml" href="/icons/icon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="/icons/favicon-32.png">
<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
<link rel="manifest" href="/manifest.json">
<meta property="og:type" content="article"><meta property="og:site_name" content="{SITE}"><meta property="og:locale" content="fr_FR">
<meta property="og:title" content="{E(p['title'])}"><meta property="og:description" content="{E(p['desc'])}">
<meta property="og:url" content="{url}"><meta property="og:image" content="{OG_IMG}">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{E(p['title'])}">
<meta name="twitter:description" content="{E(p['desc'])}"><meta name="twitter:image" content="{OG_IMG}">
{jl(article)}
{jl(crumbs)}
{jl(faq_ld(p['faq']))}
<style>{CSS}</style>
</head>
<body>
<header class="nav"><div class="wrap"><a class="logo" href="/"><img src="/icons/logo-96.png" alt="" width="28" height="28">CVxMaker</a><a class="btn" href="/app/">Créer mon CV</a></div></header>
<main class="wrap">
<nav class="crumb" aria-label="Fil d'Ariane"><a href="/">Accueil</a> › {E(SHORT[p['slug']])}</nav>
<h1>{E(p['h1'])}</h1>
<p class="lead">{E(p['intro'])}</p>
{body}
<div class="cta"><p>Prêt à passer à l'action ? Votre CV peut être terminé en quelques minutes.</p><a class="btn" href="/app/">Créer mon CV gratuitement</a></div>
<section class="faq"><h2>Questions fréquentes</h2>{faq}</section>
<h2>À lire aussi</h2>
<ul class="rel">{rel}</ul>
</main>
<footer><div class="wrap"><a href="/">Accueil</a><a href="/modeles-de-cv">Modèles</a><a href="/lettre-de-motivation">Lettres</a><a href="/guides">Tous les guides</a><a href="/confidentialite.html">Confidentialité</a><p>© 2026 CVxMaker</p></div></footer>
</body>
</html>
"""

def write(path, s):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)

def sub1(s, old, new, label):
    if old not in s:
        raise SystemExit(f"[home] motif introuvable : {label}")
    return s.replace(old, new, 1)

def build_home():
    path = os.path.join(PUB, 'index.html')
    s = open(path, encoding='utf-8').read()
    if 'data-seo="v1"' not in s:   # déjà patché : seules les balises dépendantes du domaine sont régénérées
        s = sub1(s, '<html lang="fr" style="color-scheme:only light">', '<html lang="fr" style="color-scheme:only light" data-seo="v1">', 'html tag')
    title = 'Créer un CV gratuit en ligne : modèles et PDF | CVxMaker'
    desc = "Créez un CV professionnel gratuit depuis votre téléphone : 50 modèles, score ATS, lettre de motivation, export PDF. Adapté à l'Afrique francophone."
    head = f"""<!--SEO-HEAD-->
<meta name="description" content="{E(desc)}">
<link rel="canonical" href="{BASE}/">
<meta name="google-site-verification" content="{GSC_TOKEN}">
<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
<link rel="alternate" hreflang="fr" href="{BASE}/"><link rel="alternate" hreflang="x-default" href="{BASE}/">
<meta property="og:type" content="website"><meta property="og:site_name" content="{SITE}"><meta property="og:locale" content="fr_FR">
<meta property="og:title" content="{E(title)}"><meta property="og:description" content="{E(desc)}">
<meta property="og:url" content="{BASE}/"><meta property="og:image" content="{OG_IMG}">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{E(title)}">
<meta name="twitter:description" content="{E(desc)}"><meta name="twitter:image" content="{OG_IMG}">
{jl(ORG)}
{jl(WEBSITE)}
{jl(APP)}
{jl(faq_ld(HOME_FAQ))}
<!--/SEO-HEAD-->
"""
    s = re.sub(r'<title>.*?</title>', f'<title>{E(title)}</title>', s, count=1, flags=re.S)
    if '<!--SEO-HEAD-->' not in s:
        s = sub1(s, '<meta name="color-scheme" content="only light">', head + '<meta name="color-scheme" content="only light">', 'head insert')
    else:
        s = re.sub(r'<!--SEO-HEAD-->.*?<!--/SEO-HEAD-->\n?', head, s, flags=re.S)
    if 'data-seo-body="v1"' not in s:
        # H1 orienté requête + ticker conservé en sous-titre
        s = sub1(s, '<div class="eyebrow">+280 personnes créent leur CV en ce moment</div>\n  <h1>Le CV parfait pour <span class="ticker" id="ticker">Médecin</span></h1>',
                 '<div class="eyebrow" data-seo-body="v1">Gratuit · Sur téléphone · Export PDF et Word</div>\n  <h1>Créer un CV professionnel gratuit en ligne</h1>\n  <p class="hero-sub" style="font-size:20px;font-weight:700;color:var(--nav);margin:0 auto 4px">Le CV parfait pour <span class="ticker" id="ticker">Médecin</span></p>', 'hero h1')
        s = sub1(s, '<div class="stat-live"><b id="statCount">14 382</b> CVs créés sur CVxMaker</div>', '', 'compteur')
        s = sub1(s, "let base = 14382;\nsetInterval(()=>{\n  base += Math.floor(Math.random()*3);\n  document.getElementById('statCount').textContent = base.toLocaleString('fr-FR');\n}, 5000);\n", '', 'compteur js')
        # FAQ statique (visible par les robots) : même balisage que le rendu JS
        faq_html = ''.join(f'<div class="faq-item" id="faq{i}"><div class="faq-q" onclick="document.getElementById(\'faq{i}\').classList.toggle(\'open\')">{E(q)}<span>+</span></div><div class="faq-a">{E(a)}</div></div>' for i, (q, a) in enumerate(HOME_FAQ))
        s = sub1(s, '<div class="faq" id="faqList"></div>', f'<div class="faq" id="faqList">{faq_html}</div>', 'faq html')
        s = re.sub(r"const FAQ = \[.*?\];\ndocument\.getElementById\('faqList'\)\.innerHTML = FAQ\.map\(.*?\)\.join\(''\);\n", '', s, count=1, flags=re.S)
        # Import n'est plus « bientôt » : fonctionnalité disponible
        s = re.sub(r'<section id="bientot">.*?</section>\n', '', s, count=1, flags=re.S)
        s = sub1(s, '<div class="feat-card"><div class="ic">☁️</div>',
                 '<div class="feat-card"><div class="ic">📥</div><h3>Import de CV existant</h3><p>PDF, Word ou texte collé : lu sur votre appareil, rien n\'est envoyé. Vous corrigez ensuite dans l\'éditeur.</p></div>\n    <div class="feat-card"><div class="ic">🌍</div><h3>Version anglaise</h3><p>Affichez votre CV en anglais sans toucher à l\'original français.</p></div>\n    <div class="feat-card"><div class="ic">☁️</div>', 'features')
        # Maillage interne : guides
        guides = ''.join(f'<a href="/{p["slug"]}">{E(SHORT[p["slug"]])}</a>' for p in PAGES)
        s = sub1(s, '<div><h4>Pays couverts</h4>', f'<div><h4>Guides</h4>{guides}</div>\n    <div><h4>Pays couverts</h4>', 'footer guides')
        sect = ('<section id="guides"><div class="wrap"><div class="eyebrow center">Guides</div><h2 class="h2 center">Tout pour réussir sa candidature</h2>'
                '<p class="sub center">Modèles, lettres, ATS, version anglaise : des conseils concrets pour chaque étape.</p>'
                '<div class="feat-grid">' + ''.join(f'<a class="feat-card" href="/{p["slug"]}" style="display:block"><h3>{E(SHORT[p["slug"]])}</h3><p>{E(p["desc"])}</p></a>' for p in PAGES) + '</div></div></section>\n\n')
        s = sub1(s, '<section id="faq"', sect + '<section id="faq"', 'guides section')
        s = sub1(s, '<a href="#faq">FAQ</a></div>', '<a href="#guides">Guides</a><a href="#faq">FAQ</a></div>', 'nav guides')
        s = s.replace('<img class="logo-img" style="width:28px;height:28px;border-radius:8px;display:block" alt=""', '<img class="logo-img" style="width:28px;height:28px;border-radius:8px;display:block" alt="Logo CVxMaker" width="28" height="28"', 1)
    write(path, s)

def build_webp():
    from PIL import Image
    d = os.path.join(PUB, 'assets', 'templates')
    for f in sorted(os.listdir(d)):
        if f.endswith('.jpg'):
            out = os.path.join(d, f[:-4] + '.webp')
            if not os.path.exists(out):
                im = Image.open(os.path.join(d, f)).convert('RGB')
                im = im.resize((360, round(360 * im.height / im.width)), Image.LANCZOS)
                im.save(out, 'WEBP', quality=78, method=6)

A11Y_CSS = '.eyebrow,.hero .eyebrow{color:#8A5113}footer h3{color:#fff;font-size:13px;margin-bottom:10px}.nav-links a{display:inline-flex;align-items:center;min-height:44px;padding:0 8px}.tpl-more{color:#4F4A5A}footer a{padding:6px 0;margin-bottom:0}footer .bottom{color:#A8B3C4}'

def link_hub_home():
    path = os.path.join(PUB, 'index.html')
    s = open(path, encoding='utf-8').read()
    if 'href="/guides"' in s: return
    old = '</div>\n    <div><h3>Pays couverts</h3>'
    if old not in s: raise SystemExit('[hub] pied de page introuvable')
    s = s.replace(old, '<a href="/guides">Tous les guides</a></div>\n    <div><h3>Pays couverts</h3>', 1)
    s = s.replace('<a href="#guides">Guides</a>', '<a href="/guides">Guides</a>', 1)
    write(path, s)

def build_perf():
    """Vitesse : script Supabase chargé après l'affichage, polices non bloquantes, images WebP, accessibilité."""
    path = os.path.join(PUB, 'index.html')
    s = open(path, encoding='utf-8').read()
    if 'data-perf="v1"' in s:
        s2 = re.sub(r'<style id="seoA11y">.*?</style>', '<style id="seoA11y">:root{--ink2:#615B6C}' + A11Y_CSS + '</style>', s, flags=re.S)
        if s2 != s: write(path, s2)
        return
    s = sub1(s, '<html lang="fr" style="color-scheme:only light" data-seo="v1">', '<html lang="fr" style="color-scheme:only light" data-seo="v1" data-perf="v1">', 'perf marker')
    s = sub1(s, '<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>\n<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4"></script>\n', '', 'supabase tag')
    m = re.search(r'<link href="(https://fonts\.googleapis\.com/css2[^"]+)" rel="stylesheet">', s)
    if not m: raise SystemExit('[perf] polices introuvables')
    u = m.group(1)
    s = s.replace(m.group(0), f'<link rel="preload" as="style" href="{u}" onload="this.onload=null;this.rel=\'stylesheet\'"><noscript><link href="{u}" rel="stylesheet"></noscript>', 1)
    s = sub1(s, "const sb = (CONFIG_OK && window.supabase && window.supabase.createClient) ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;",
             "let sb = null;\nfunction initSb(){ if(!sb && CONFIG_OK && window.supabase && window.supabase.createClient){ sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY); } return sb; }", 'sb init')
    s = sub1(s, "cvxTrack('landing_view',{},false);\n", '', 'landing_view')
    s = sub1(s, '(async function siteNotice(){', 'async function siteNotice(){', 'siteNotice open')
    s = sub1(s, '}catch(e){}\n})();\n\n\nfunction escH', '}catch(e){}\n}\n\n\nfunction escH', 'siteNotice close')
    s = sub1(s, 'loadApprovedTestimonials();\n\nasync function submitTestimonial', 'async function submitTestimonial', 'testimonials call')
    boot = """
/* Supabase est chargé après l'affichage de la page (ne bloque plus le premier rendu). */
(function(){
  function boot(){ initSb(); cvxTrack('landing_view',{},false); siteNotice(); loadApprovedTestimonials(); }
  function load(){ var t=document.createElement('script'); t.src='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4'; t.async=true; t.onload=boot; t.onerror=boot; document.head.appendChild(t); }
  if(document.readyState==='complete') setTimeout(load,0); else window.addEventListener('load',function(){ setTimeout(load,0); });
})();
"""
    i = s.rindex('</script>')
    s = s[:i] + boot + s[i:]
    # images en WebP + dimensions (évite les sauts de mise en page)
    s = re.sub(r'<img src="assets/templates/(t\d+)\.jpg" alt="([^"]*)" loading="lazy">', r'<img src="assets/templates/\1.webp" alt="\2" width="360" height="509" loading="lazy" decoding="async">', s)
    # accessibilité : contraste, ordre des titres, cibles tactiles
    s = s.replace('<h4>', '<h3>').replace('</h4>', '</h3>')
    a11y = '<style id="seoA11y">:root{--ink2:#615B6C}' + A11Y_CSS + '</style>\n'
    s = sub1(s, '<style id="noDark">', a11y + '<style id="noDark">', 'a11y')
    write(path, s)

def hub_html():
    url = BASE + '/guides'
    title = 'Guides CV, lettre de motivation et candidature | CVxMaker'
    desc = "Tous nos guides : créer un CV, modèles, lettre de motivation, ATS, CV en anglais, entretien, démission. Conseils concrets pour réussir sa candidature."
    cards = ''.join(f'<li><a href="/{p["slug"]}"><b>{E(p["h1"])}</b><br><span style="font-weight:400;color:#5d5868">{E(p["desc"])}</span></a></li>' for p in ALL)
    ld = {"@context": "https://schema.org", "@type": "CollectionPage", "name": "Guides CVxMaker", "url": url, "inLanguage": "fr",
          "mainEntity": {"@type": "ItemList", "itemListElement": [{"@type": "ListItem", "position": i + 1, "url": f"{BASE}/{p['slug']}", "name": p['h1']} for i, p in enumerate(ALL)]}}
    crumbs = {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "Accueil", "item": BASE + '/'}, {"@type": "ListItem", "position": 2, "name": "Guides", "item": url}]}
    return f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{E(title)}</title>
<meta name="description" content="{E(desc)}">
<link rel="canonical" href="{url}">
<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
<meta name="theme-color" content="#1B1640">
<link rel="icon" type="image/svg+xml" href="/icons/icon.svg">
<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
<meta property="og:type" content="website"><meta property="og:site_name" content="{SITE}"><meta property="og:locale" content="fr_FR">
<meta property="og:title" content="{E(title)}"><meta property="og:description" content="{E(desc)}"><meta property="og:url" content="{url}"><meta property="og:image" content="{OG_IMG}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="{OG_IMG}">
{jl(ld)}
{jl(crumbs)}
<style>{CSS}</style>
</head>
<body>
<header class="nav"><div class="wrap"><a class="logo" href="/"><img src="/icons/logo-96.png" alt="" width="28" height="28">CVxMaker</a><a class="btn" href="/app/">Créer mon CV</a></div></header>
<main class="wrap">
<nav class="crumb" aria-label="Fil d'Ariane"><a href="/">Accueil</a> › Guides</nav>
<h1>Guides : CV, lettres et candidature</h1>
<p class="lead">Des conseils concrets pour chaque étape : créer son CV, rédiger une lettre, passer les filtres de recrutement, préparer un entretien.</p>
<ul class="rel" style="grid-template-columns:1fr">{cards}</ul>
<div class="cta"><p>Prêt à passer à l'action ?</p><a class="btn" href="/app/">Créer mon CV gratuitement</a></div>
</main>
<footer><div class="wrap"><a href="/">Accueil</a><a href="/modeles-de-cv">Modèles</a><a href="/lettre-de-motivation">Lettres</a><a href="/confidentialite.html">Confidentialité</a><p>© 2026 CVxMaker</p></div></footer>
</body>
</html>
"""

def build_pages():
    for p in ALL:
        write(os.path.join(PUB, p['slug'] + '.html'), page_html(p))
    write(os.path.join(PUB, 'guides.html'), hub_html())

def build_files():
    urls = [('/', '1.0'), ('/guides', '0.9')] + [('/' + p['slug'], '0.8') for p in ALL] + [('/confidentialite.html', '0.3')]
    sm = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(
        f'  <url><loc>{BASE}{u}</loc><lastmod>{TODAY}</lastmod></url>\n' for u, _ in urls) + '</urlset>\n'
    write(os.path.join(PUB, 'sitemap.xml'), sm)
    write(os.path.join(PUB, 'robots.txt'),
          f"User-agent: *\nAllow: /\nDisallow: /admin.html\nDisallow: /admin/\n\nSitemap: {BASE}/sitemap.xml\n")
    lines = [f"# {SITE}", "", "> Créateur de CV en ligne en français : 50 modèles, score ATS, lettres de motivation et demandes d'emploi, import de CV, version anglaise, export PDF et Word. Pensé pour l'Afrique francophone et les candidatures internationales.", "", "## Pages principales", f"- [Accueil]({BASE}/)"]
    lines += [f"- [Tous les guides]({BASE}/guides)"] + [f"- [{p['h1']}]({BASE}/{p['slug']}): {p['desc']}" for p in ALL]
    write(os.path.join(PUB, 'llms.txt'), '\n'.join(lines) + '\n')

def build_og():
    from PIL import Image, ImageDraw, ImageFont
    W, H = 1200, 630
    im = Image.new('RGB', (W, H), '#1B1640')
    px = im.load()
    for y in range(H):
        for x in range(W):
            t = (x / W * 0.6 + y / H * 0.4)
            px[x, y] = (int(27 + 40 * t), int(22 + 25 * t), int(64 + 90 * t))
    d = ImageDraw.Draw(im)
    def F(sz, bold=False):
        for f in (['/usr/share/fonts/opentype/inter/Inter-Bold.otf'] if bold else []) + ['/usr/share/fonts/opentype/inter/Inter-Regular.otf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf']:
            if os.path.exists(f):
                return ImageFont.truetype(f, sz)
        return ImageFont.load_default()
    logo = Image.open(os.path.join(PUB, 'icons', 'icon-512.png')).convert('RGBA').resize((150, 150))
    im.paste(logo, (80, 80), logo)
    d.text((255, 112), 'CVxMaker', font=F(64, True), fill='white')
    d.text((80, 300), 'Créez un CV professionnel', font=F(70, True), fill='white')
    d.text((80, 385), 'gratuit, depuis votre téléphone', font=F(70, True), fill='#FFA631')
    d.text((80, 520), '50 modèles  ·  Score ATS  ·  Lettres  ·  Export PDF', font=F(34), fill='#cbd5e1')
    os.makedirs(os.path.join(PUB, 'assets'), exist_ok=True)
    im.save(os.path.join(PUB, 'assets', 'og-cvxmaker.png'), optimize=True)

if __name__ == '__main__':
    build_og(); build_webp(); build_pages(); build_home(); build_perf(); link_hub_home(); build_files()
    print('OK', BASE, TODAY, len(ALL), 'pages')
