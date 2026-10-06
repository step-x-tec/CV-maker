# SmartCV Pro — Guide de déploiement

Suivez les étapes dans l'ordre. Comptez 30 à 45 minutes la première fois.

## 0. Prérequis

- Un projet Supabase (celui déjà utilisé pendant le développement, ou un nouveau).
- Un compte CinetPay actif (dashboard.cinetpay.com) si vous activez les paiements.
- Le CLI Supabase installé : `npm install -g supabase`
- Un hébergeur pour les fichiers statiques : Netlify ou Vercel (configs déjà incluses), ou n'importe quel hébergeur qui sert du HTML.

## 1. Clés à régénérer AVANT tout déploiement public

Le prompt de développement d'origine contenait une clé GROQ et une clé `service_role` Supabase en clair. Si ces clés n'ont pas déjà été régénérées :

1. Supabase → Settings → API → **Reset service_role secret**
2. groq.com → régénérer/révoquer la clé existante
3. Ne remettez plus jamais ces clés dans un fichier HTML/JS — c'est justement ce que les Edge Functions de ce dossier évitent.

## 2. Base de données (`supabase/migrations/`)

Dans Supabase → SQL Editor, exécutez **dans l'ordre** :

1. `20260101000000_base_schema.sql` — tables, RLS de base, triggers, fonctions (votre schéma d'origine, inchangé)
2. `20260928000100_security_hardening.sql` — corrige 5 failles trouvées dans le schéma d'origine (voir le détail en tête du fichier : élévation de privilège possible, récursion RLS, fonctions qui faisaient confiance à l'ID envoyé par le client, tables sans RLS, messages de support usurpables)

Si vous aviez déjà exécuté l'ancien `SQL_STEP2_CREATE.sql` sur ce projet, exécutez seulement le fichier n°2 : il est conçu pour s'appliquer par-dessus (toutes les commandes utilisent `CREATE OR REPLACE` / `DROP POLICY IF EXISTS`).

## 3. Authentification (Supabase Dashboard → Authentication)

- **Providers → Email** : activé (déjà par défaut)
- **Providers → Google** : activez-le, renseignez le Client ID / Secret Google, et ajoutez l'URL de redirection affichée par Supabase dans votre config Google Cloud Console
- **Providers → Phone** : activez-le et configurez un fournisseur SMS (Twilio, Vonage…) si vous voulez garder la connexion par OTP. Sans ça, l'onglet "Téléphone" du formulaire échouera proprement (l'email/mot de passe et Google continueront de fonctionner).
- **URL Configuration** : renseignez votre **Site URL** finale (ex. `https://smartcv.exemple.com`) et ajoutez-la aux **Redirect URLs**

## 4. Edge Functions (`supabase/functions/`)

```bash
supabase login
supabase link --project-ref VOTRE_REF_PROJET

# Secrets (jamais dans le code)
supabase secrets set SITE_URL=https://votre-domaine.com
supabase secrets set CINETPAY_APIKEY=xxx CINETPAY_SITE_ID=xxx CINETPAY_CHANNELS=MOBILE_MONEY
# Optionnel — seulement si vous activez l'IA hébergée en plus du moteur local :
supabase secrets set GROQ_API_KEY=xxx

supabase functions deploy create-payment
supabase functions deploy cinetpay-webhook   # verify_jwt=false est déjà dans supabase/config.toml
supabase functions deploy ai-chat            # optionnel
```

## 5. CinetPay

Dashboard CinetPay → Intégration :
- Copiez **API Key** et **Site ID** → ce sont les secrets `CINETPAY_APIKEY` / `CINETPAY_SITE_ID` ci-dessus
- Renseignez l'URL de notification si demandée : `https://VOTRE-PROJET.supabase.co/functions/v1/cinetpay-webhook`
- Activez les canaux de paiement voulus (Mobile Money par défaut ; ajoutez la carte bancaire via `CINETPAY_CHANNELS=ALL` si votre compte y est éligible)

## 6. Premier compte administrateur

1. Inscrivez-vous normalement sur le site avec l'email qui doit être admin.
2. Dans Supabase → SQL Editor, ouvrez `supabase/seed/create_first_admin.sql`, remplacez l'email, exécutez.
3. Connectez-vous sur `/admin.html` avec ce compte.

## 7. Déploiement du site — avec Git (recommandé)

Le dossier `public/` contient 3 pages autonomes (aucune étape de build requise) :
- `index.html` — landing page
- `app.html` — l'éditeur de CV
- `admin.html` — le tableau de bord admin

Ce dossier est déjà un dépôt Git initialisé avec un premier commit. Il ne vous reste qu'à le pousser sur GitHub, puis brancher votre hébergeur dessus — chaque `git push` republiera automatiquement le site.

### 7.1 Créer le dépôt GitHub et pousser

```bash
cd smartcv-deploy
# Créez d'abord un dépôt VIDE sur github.com (sans README ni licence), puis :
git remote add origin https://github.com/VOTRE-COMPTE/smartcv-pro.git
git branch -M main
git push -u origin main
```

*(Si `git status` affiche des fichiers non suivis parce que vous avez déjà créé `public/config.js` en local : c'est normal, il est volontairement ignoré par `.gitignore` pour ne jamais committer de configuration spécifique à un environnement.)*

### 7.2 Brancher l'hébergeur sur le dépôt (déploiement continu)

**Netlify** : app.netlify.com → *Add new site → Import an existing project* → autorisez GitHub → sélectionnez le dépôt. Build command : *(laisser vide)*. Publish directory : `public`. Le fichier `netlify.toml` du dépôt configure déjà les routes `/app/` → `app.html` et `/admin/` → `admin.html`.

**Vercel** : vercel.com → *Add New → Project* → importez le dépôt GitHub. Root Directory : `.` (racine). Le fichier `vercel.json` est détecté automatiquement.

Dans les deux cas, chaque `git push` sur `main` republie le site en quelques secondes — plus besoin de glisser-déposer de fichiers.

### 7.3 (Optionnel) Déployer les Edge Functions automatiquement via GitHub Actions

Un workflow est déjà inclus dans `.github/workflows/deploy-functions.yml` : il redéploie les 3 Edge Functions à chaque push qui touche `supabase/functions/`. Pour l'activer, ajoutez ces deux secrets dans GitHub → *Settings → Secrets and variables → Actions* :
- `SUPABASE_ACCESS_TOKEN` (Supabase → icône de compte → Access Tokens → *Generate new token*)
- `SUPABASE_PROJECT_REF` (Supabase → Settings → General → *Reference ID*)

Sans ces secrets configurés, le workflow échoue simplement sans rien casser — vous pouvez continuer à déployer les fonctions à la main (§4) si vous préférez.

### 7.4 Alternative sans Git

Si vous préférez ne pas utiliser Git : glissez le dossier `public/` sur app.netlify.com/drop, ou `netlify deploy --prod` / `vercel --prod` en local depuis ce dossier. Ça fonctionne aussi très bien, simplement sans redéploiement automatique à chaque changement.

### 7.5 Configuration Supabase différente

Si vous utilisez un projet Supabase différent de celui par défaut, copiez `public/config.example.js` en `public/config.js` et renseignez votre URL et votre clé anonyme (clé publique, sans danger à exposer — protégée par la RLS). Ce fichier est volontairement dans `.gitignore` : il ne sera pas versionné, donc chaque environnement (test/prod) peut avoir le sien sans conflit.

## 8. Checklist avant l'ouverture au public

- [ ] Étape 1 (clés) faite
- [ ] Les deux migrations exécutées sans erreur
- [ ] `SELECT tablename FROM pg_tables WHERE schemaname='public' AND NOT rowsecurity;` ne renvoie **aucune** ligne
- [ ] Inscription + connexion email/mot de passe fonctionnent
- [ ] Connexion Google fonctionne (si activée)
- [ ] Créer un CV → se déconnecter → se reconnecter → le CV est bien retrouvé
- [ ] Un paiement CinetPay de test active bien le plan (vérifiez la ligne dans `payments` et `profiles.plan`)
- [ ] Un ticket de support créé côté app apparaît côté `/admin.html`
- [ ] Le compte admin peut se connecter sur `/admin.html` ; un compte normal ne le peut pas
- [ ] `robots.txt` / meta noindex sur `/admin.html` (déjà inclus) pour ne pas l'indexer sur Google

## 9. Ce qui reste volontairement hors-périmètre

- **Assistant IA hébergé (GROQ)** : désactivé par défaut, l'app utilise son moteur local. La fonction `ai-chat` est prête si vous changez d'avis (voir DEPLOY.md §4).
- **Vérification manuelle des paiements par carte** : selon votre compte CinetPay, la validation de certains moyens de paiement peut prendre plus de temps ; le webhook gère ça automatiquement (statut `pending` → `success`/`failed`).
- **Sauvegardes de la base** : activez les sauvegardes automatiques dans Supabase → Settings → Database (Point-in-time recovery recommandé au-delà de la phase de test).
