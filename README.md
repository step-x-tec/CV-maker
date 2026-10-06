# SmartCV Pro — Package de déploiement

Tout ce qu'il faut pour mettre l'application en ligne. Démarrez par **DEPLOY.md**, dans l'ordre.

```
public/                                  → les 3 pages du site (aucun build nécessaire)
  index.html                             → landing page
  app.html                               → éditeur de CV
  admin.html                             → dashboard admin
  config.example.js                      → à copier en config.js si besoin d'un autre projet Supabase

supabase/
  migrations/
    20260101000000_base_schema.sql       → schéma de base (tables, RLS, fonctions)
    20260928000100_security_hardening.sql→ correctifs de sécurité — à exécuter après le schéma de base
  functions/
    create-payment/                      → crée un paiement CinetPay (identité vérifiée par JWT)
    cinetpay-webhook/                    → confirme le paiement et active le plan (jamais côté client)
    ai-chat/                             → optionnel : IA hébergée (GROQ) en remplacement du moteur local
  seed/
    create_first_admin.sql               → à exécuter une fois pour créer votre premier admin
  config.toml                            → config des Edge Functions (verify_jwt)

netlify.toml / vercel.json               → config d'hébergement prête à l'emploi
.env.example                             → liste des secrets à configurer (via `supabase secrets set`, jamais en dur)
DEPLOY.md                                → guide pas à pas complet
```

## Ce qui a changé par rapport aux versions précédentes du chat

- Les paiements ne passent plus par un `prompt()` demandant une URL : l'app appelle directement l'Edge Function avec le token de l'utilisateur connecté.
- La sauvegarde cloud automatique du CV (`syncFromCloud` / sauvegarde vers la table `cvs`) est maintenant réellement branchée, avec une règle simple de résolution de conflit (la version la plus récente gagne).
- Les messages de support échouaient silencieusement (colonne `sender_id` obligatoire non envoyée) — corrigé.
- La génération de licences dans l'admin ne faisait qu'un affichage local : les clés sont maintenant réellement enregistrées en base, avec des identifiants aléatoires cryptographiquement sûrs.
- Mot de passe oublié : ajouté (l'app n'avait aucun moyen de le réinitialiser).
- Photo de profil : compressée automatiquement avant stockage (évite de saturer la base avec des photos de plusieurs Mo).
- 5 failles de sécurité corrigées dans le schéma SQL (détaillées en tête de `20260928000100_security_hardening.sql`).
