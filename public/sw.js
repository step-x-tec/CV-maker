// CVxMaker — Service Worker
// Permet l'installation de l'app (PWA) et un fonctionnement correct hors-ligne
// pour l'éditeur déjà visité. Ne met jamais en cache les appels Supabase
// (API externe, toujours en réseau) ni les requêtes non-GET.

const SW_VERSION = 'cvxmaker-v13';
const SHELL_CACHE = SW_VERSION + '-shell';

const SHELL_FILES = [
  '/app/',
  '/app.html',
  '/ads-render.js',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/apple-touch-icon.png',
  '/icons/icon.svg',
  '/favicon.ico'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((cache) => Promise.all(SHELL_FILES.map((f) => cache.add(f).catch(() => {})))) // une ressource manquante ne bloque pas l'installation
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => Promise.all(
      names.filter((n) => n.startsWith('cvxmaker-') && n !== SHELL_CACHE).map((n) => caches.delete(n))
    )).then(() => self.clients.claim())
  );
});

function isSupabaseOrApi(url) {
  return url.hostname.endsWith('.supabase.co') || url.pathname.startsWith('/api/');
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return; // ne jamais intercepter POST/PUT/DELETE (écritures Supabase)

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // ressources externes (CDN, Supabase) : réseau direct
  if (isSupabaseOrApi(url)) return;
  if (url.pathname === '/config.js') return; // config toujours en direct
  if (url.pathname.startsWith('/admin')) return; // l'admin reste toujours en direct

  // Navigation (ouverture de page / de l'app) : réseau d'abord, repli sur le cache si hors-ligne
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(req).then((cached) => cached || caches.match('/app.html')))
    );
    return;
  }

  // Fichiers statiques du même site (CSS/JS inline, icônes, polices…) : cache d'abord, réseau en secours
  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => cached);
    })
  );
});
