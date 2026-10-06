-- Créer votre PREMIER administrateur.
-- 1) Inscrivez-vous normalement dans l'application avec votre email.
-- 2) Remplacez l'email ci-dessous, puis exécutez ce script dans le SQL Editor de Supabase.
--    (le SQL Editor tourne avec les droits du propriétaire : le trigger de protection ne le bloque pas)
UPDATE public.profiles
   SET is_admin = TRUE, admin_role = 'superadmin'
 WHERE email = 'VOTRE_EMAIL_ADMIN@exemple.com';

SELECT id, email, is_admin, admin_role FROM public.profiles WHERE is_admin = TRUE;
