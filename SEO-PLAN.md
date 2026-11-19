# CVxMaker — Plan de référencement (SEO)

## Ce qui est réaliste

Aucun site ne peut être garanti n°1 sur 100 % des recherches : Google, Bing, TikTok, YouTube et les assistants IA classent selon la requête, le pays, l'appareil, la concurrence et l'historique de chaque personne. Des sites comme Canva, Indeed ou Zety ont des années d'avance sur les requêtes génériques (« modèle de CV »).

Ce qui est atteignable, et ce que ce plan vise :
1. Être **bien classé sur des requêtes précises** où la concurrence est faible : « cv Afrique francophone », « cv compatible ATS gratuit », « faire un cv sur téléphone », « lettre de motivation Togo », etc.
2. Être **le premier résultat quand on cherche « CVxMaker »** (recherche de marque) : c'est le plus facile et le plus fiable.
3. Monter progressivement sur les requêtes plus larges grâce au contenu, aux liens et à la durée. Comptez **3 à 6 mois** avant des résultats visibles.

## Ce qui est déjà fait dans le code (cette mise à jour)

- Page d'accueil : titre, description, balise canonique, Open Graph / Twitter (aperçu de partage avec image 1200×630), données structurées (Organization, WebSite, WebApplication, FAQPage), H1 orienté requête, FAQ visible dans le HTML (lisible par les robots), lien vers les guides.
- 7 pages de contenu principales (`/creer-un-cv-gratuit`, `/modeles-de-cv`, `/lettre-de-motivation`, `/demande-d-emploi`, `/cv-compatible-ats`, `/cv-en-anglais`, `/cv-afrique-francophone`), chacune avec titre/description uniques, fil d'Ariane, FAQ + données structurées, maillage interne.
- `sitemap.xml`, `robots.txt` (avec adresse du sitemap), `llms.txt` (aide les assistants IA à décrire le site).
- L'éditeur (`/app`) et les CV partagés (`/cv/…`) sont en `noindex` : ils n'ont pas de valeur pour la recherche et contiennent des données privées.
- Pas de note d'étoiles dans les données structurées : afficher des avis non vérifiables est contraire aux règles de Google et peut entraîner une pénalité.

Pour régénérer après un changement de domaine : `python3 tools/build_seo.py https://votre-domaine.com`.

## Passe n°2 (déjà dans le code) : vitesse, accessibilité, contenu, indexation rapide

Mesures Lighthouse mobile en local (simulation de connexion lente) :
- Accueil : performance 99, accessibilité 100, SEO 100 (avant : 98 / 88 / 100). Le 96 en « bonnes pratiques » vient seulement de l'absence de clés Supabase dans mon test local.
- Pages de guides : performance 100, SEO 100, accessibilité 95 à 100.
Ces scores comptent pour le classement mobile, mais ne garantissent pas la position : ils enlèvent un obstacle.

Ce qui a changé : script Supabase chargé après l'affichage (plus de blocage), polices non bloquantes, miniatures en WebP (≈ 18 Ko au lieu de ≈ 50 Ko chacune), contraste et tailles tactiles corrigés, titres dans le bon ordre.

Contenu : un hub `/guides` et 8 articles supplémentaires (CV sans expérience, CV étudiant/stage, centres d'intérêt, décrire ses missions, erreurs fréquentes, lettre de démission, préparer un entretien, postuler à l'étranger), soit 15 pages indexables en plus de l'accueil, toutes reliées entre elles.

Indexation rapide : `python3 tools/indexnow.py` prévient Bing, Yandex et d'autres moteurs dès le déploiement (clé incluse). Google passe par la Search Console.

## À faire de votre côté (dans cet ordre)

1. **Déployer** cette version sur Netlify.
2. **Google Search Console** (search.google.com/search-console) → ajouter le site, vérifier la propriété, **envoyer `sitemap.xml`**, puis « Inspecter l'URL » → « Demander une indexation » pour la page d'accueil et les 7 pages. Faire pareil avec **Bing Webmaster Tools** (couvre aussi DuckDuckGo et Ecosia).
3. **Domaine propre** : `cvxmaker.netlify.app` est un sous-domaine partagé, moins bien perçu et impossible à protéger. Un domaine à vous (`cvxmaker.com`, ou un `.fr`/`.tg`/`.sn` selon la cible) aide la confiance, la recherche de marque et le consentement Google OAuth. Après achat : régénérer avec le nouveau domaine, ajouter les redirections de l'ancien vers le nouveau.
4. **Profils de marque** avec le même nom, le logo V4 et un lien vers le site : Facebook, Instagram, TikTok, YouTube, LinkedIn, X. Ils occupent les premiers résultats de « CVxMaker » et fournissent des liens.
5. **Vidéos** (celles que nous produisons) : titre commençant par la requête (« Faire un CV sur téléphone — gratuit »), description avec le lien et 3–5 mots-clés, sous-titres activés, publication sur TikTok, Reels, Shorts et YouTube. YouTube et TikTok sont aussi des moteurs de recherche en Afrique francophone.
6. **Liens entrants** (le facteur n°1 sur les requêtes concurrentielles) : annuaires d'applications et de produits (Product Hunt, AlternativeTo…), groupes d'emploi et d'étudiants (Facebook, WhatsApp, Telegram), universités et centres de formation, blogs emploi africains, presse locale tech. Proposez-leur un guide utile, pas seulement un lien.
7. **Avis réels** : demandez à vos utilisateurs de laisser un avis sur Google (fiche d'établissement si vous avez une adresse) et sur le site. Ne publiez jamais de faux avis.
8. **Mesure** : Search Console (requêtes et positions), plus un outil d'audience respectueux de la vie privée si vous le souhaitez.

## Calendrier de contenu (1 article par semaine, 600–900 mots chacun)

Chaque article cible une question réelle et renvoie vers le guide et l'outil correspondants :
modèle de lettre de motivation par métier (comptable, infirmier, enseignant…) · CV sans expérience · CV d'étudiant stagiaire · quoi mettre en « centres d'intérêt » · comment décrire une mission (verbes d'action) · CV pour une ONG · CV pour une banque · erreurs de CV les plus fréquentes · CV pour postuler à l'étranger · lettre de démission · comment préparer un entretien · réponses aux questions d'entretien fréquentes.

À éviter : des centaines de pages quasi identiques par ville ou par métier. Google les considère comme du contenu de faible valeur et peut déclasser tout le site.

## Points à corriger dans la page d'accueil (honnêteté et confiance)

- J'ai retiré le compteur « 14 382 CVs créés » qui augmentait au hasard et la mention « +280 personnes créent leur CV en ce moment » : ces chiffres n'étaient pas réels. Si vous voulez un compteur, branchez-le sur le vrai nombre de CV en base.
- Vérifiez que les quatre témoignages affichés viennent bien de vrais utilisateurs (nom et accord de la personne).

## Performance (facteur de classement mobile)

- Le script Supabase est chargé dans l'en-tête de la page d'accueil et bloque l'affichage ; à terme, le charger après le premier affichage (gain de vitesse sur connexion lente).
- Les miniatures de modèles sont des JPEG d'environ 50 Ko : les passer en WebP/AVIF et leur donner largeur/hauteur.
- Vérifiez régulièrement avec PageSpeed Insights (pagespeed.web.dev), mobile en priorité.
