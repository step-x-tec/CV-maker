# CVxMaker — Guide de déploiement

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

3. `20261015000000_testimonials.sql` — avis publics des visiteurs, validés par un admin avant publication
4. `20261015000100_feature_interest.sql` — liste « Me prévenir » des prochaines fonctionnalités
5. `20261009000000_public_cv_view_counter.sql` — compteur de vues des liens publics de CV
6. `20261015000200_documents.sql` — lettres de motivation et demandes d'emploi / de stage, synchronisées par compte (chaque utilisateur ne voit que les siens)
7. `20261015000200_guest_tracking.sql` — suivi des visiteurs sans compte (avec leur accord) visible dans l'admin
8. `20261017000000_admin_suite.sql` — **espace admin complet** : rôles (lecture seule / modérateur / admin / super-admin), statistiques, gestion des utilisateurs, CV, paiements, support, notes internes, journal d'audit, mode maintenance et bandeau d'annonce. Toutes les fonctions vérifient le rôle en base ; relançable sans risque.

Si vous aviez déjà exécuté l'ancien `SQL_STEP2_CREATE.sql` sur ce projet, exécutez seulement le fichier n°2 : il est conçu pour s'appliquer par-dessus (toutes les commandes utilisent `CREATE OR REPLACE` / `DROP POLICY IF EXISTS`).

## 3. Authentification (Supabase Dashboard → Authentication)

- **Providers → Email** : activé (déjà par défaut)
- **Providers → Google** : activez-le, renseignez le Client ID / Secret Google, et ajoutez l'URL de redirection affichée par Supabase dans votre config Google Cloud Console
- **Providers → Phone** : activez-le et configurez un fournisseur SMS (Twilio, Vonage…) si vous voulez garder la connexion par OTP. Sans ça, l'onglet "Téléphone" du formulaire échouera proprement (l'email/mot de passe et Google continueront de fonctionner).
- **URL Configuration** : renseignez votre **Site URL** finale (ex. `https://cvxmaker.exemple.com`) et ajoutez-la aux **Redirect URLs**

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

**Configuration obligatoire :** ouvrez `public/config.js` et renseignez `SUPABASE_URL` et `SUPABASE_ANON_KEY` (Supabase → Project Settings → API ; clé *anon public* uniquement, jamais la `service_role`). Aucune valeur n'est codée en dur dans les pages. Renseignez aussi `CONTACT_EMAIL` (adresse publique affichée dans le pied de page et la page `confidentialite.html` ; laissez vide pour la masquer). Les erreurs techniques ne sont jamais montrées aux visiteurs : elles restent dans la console du navigateur. Les secrets serveur (CinetPay, service_role) se déclarent dans Supabase (`supabase secrets set`) et dans `.env` en local, jamais dans `public/`.

## 8. Checklist avant l'ouverture au public

- [ ] Étape 1 (clés) faite
- [ ] Les cinq migrations exécutées sans erreur, dans l'ordre
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

## Suivi du parcours (nouveau)

Exécutez aussi `supabase/migrations/20261020000000_funnel_events.sql`. Elle enregistre, sans aucune donnée personnelle, les étapes : visite, clic sur « Créer mon CV », ouverture de l'éditeur, inscription, import, comparaison à une offre, export PDF.

Pour voir les chiffres (connecté en admin) dans l'éditeur SQL de Supabase :
`select * from admin_funnel(30);` (30 derniers jours, par campagne et source).

Pour mesurer une pub, ajoutez à votre lien : `?utm_source=tiktok&utm_medium=video&utm_campaign=pub_pro`.

## Personnalisation de la mise en page (nouveau)

Dans l'aperçu du CV, le bouton « ✋ Personnaliser » permet de sélectionner n'importe quel élément et de le déplacer, le redimensionner, le réordonner (même d'une colonne à l'autre), régler les lettres (taille, espacement, interligne, police, couleur, gras, italique, alignement) ou le masquer. Les réglages sont enregistrés par modèle dans le CV (champ `lay`) et rejoués à l'identique à l'écran, en PDF et sur le lien public. Aucun changement de base de données n'est nécessaire.

---

## Publicité et utilisateurs en direct (nouveau)

Exécutez `supabase/migrations/20261027000000_ads_and_presence.sql` (après les précédentes ; relançable sans risque). Elle crée :

- **La présence** : l'application enregistre l'activité des connectés toutes les 2 minutes. Avant cette migration, les compteurs « actifs 24 h / 7 j » restaient à zéro. Admin → *Utilisateurs en direct* (en ligne maintenant, actifs, nouveaux, heures, pays).
- **Les campagnes** : Admin → *Publicité → Campagnes*. Image ou mini-vidéo, titre, texte, bouton, lien (clic = redirection vers la source, l'annonce reste jusqu'à la croix), croix active après N secondes (0 à 30), fermeture automatique, 5 formats (pop-up, plein écran, volet bas, bannière, coin), couleurs / arrondi / animation, ciblage (formules, pays, appareil, ancienneté, a déjà téléchargé), emplacements (ouverture, Mes CV, après téléchargement), fréquence, plafonds (vues totales, par utilisateur, par jour, clics), planning, priorité, UTM, statistiques et export CSV.
- **Le stockage** `ad-media` (bucket public, 25 Mo, images et MP4/WebM). Si le script ne peut pas le créer, créez-le à la main dans Supabase → Storage.

Par défaut, les comptes administrateurs ne voient pas les annonces : cochez « Afficher aussi aux comptes administrateurs » pour tester sur votre compte.
