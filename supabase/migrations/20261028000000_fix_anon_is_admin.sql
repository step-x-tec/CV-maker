-- ═══════════════════════════════════════════════════════════════════════
-- CORRECTIF : « Vous n'avez pas l'autorisation d'effectuer cette action »
-- sur la page d'accueil (« Me prévenir », avis/témoignages, etc.).
--
-- Cause : le durcissement de sécurité avait retiré à « anon » le droit d'exécuter
-- is_admin() / admin_rank(). Or plusieurs règles d'accès (RLS) appellent ces fonctions ;
-- PostgreSQL les évalue aussi pour les visiteurs non connectés → erreur « permission
-- denied for function is_admin » avant même d'examiner la règle publique.
--
-- Remède : les deux fonctions ne renvoient qu'un booléen / un rang sur l'appelant lui-même
-- (faux / 0 pour un visiteur sans compte) ; on rend leur exécution à « anon ».
-- Relançable sans risque.
-- ═══════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated, service_role;
DO $$ BEGIN
  IF to_regprocedure('public.admin_rank()') IS NOT NULL THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_rank() TO anon, authenticated, service_role';
  END IF;
END $$;
