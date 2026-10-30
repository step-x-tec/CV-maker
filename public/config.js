/* ============================================================================
   CVxMaker — CONFIGURATION DU PROJET SUPABASE (côté navigateur)
   ----------------------------------------------------------------------------
   Seul fichier à modifier pour brancher l'application sur votre projet.
   Utilisé par : index.html (accueil), app.html (éditeur), admin.html (admin).

   Où trouver ces valeurs : Supabase → Project Settings → API
     • SUPABASE_URL      = "Project URL"                (https://xxxxxxxx.supabase.co)
     • SUPABASE_ANON_KEY = clé "anon public" (eyJ…) ou "Publishable key" (sb_publishable_…)

   ⚠️ Ne mettez JAMAIS ici la clé service_role / secret : ce fichier est public.
   CONTACT_EMAIL = adresse de contact publique de votre service (facultatif).
   La clé anon est faite pour être exposée ; la sécurité vient des règles RLS.
   ============================================================================ */
window.__SC_CONFIG__ = {
  SUPABASE_URL: "https://sjhguxrclyjpyqudwywd.supabase.co",
  SUPABASE_ANON_KEY: "COLLEZ_ICI_VOTRE_CLE_ANON_OU_PUBLISHABLE",

  // Adresse affichée aux visiteurs (pied de page de l'accueil, page confidentialité). Laissez vide pour masquer le lien.
  CONTACT_EMAIL: ""
};
