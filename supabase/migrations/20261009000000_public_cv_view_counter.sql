-- ════════════════════════════════════════
-- Lien public du CV : compteur de vues
-- ════════════════════════════════════════
-- Les colonnes share_token / is_public / shared_at / view_count existent déjà sur public.cvs
-- (voir 20260101000000_base_schema.sql), de même que la policy RLS "cvs_public_r" qui autorise
-- la lecture anonyme d'une ligne quand is_public = TRUE. Il ne manquait qu'un moyen sûr pour un
-- visiteur anonyme (qui n'a donc pas la permission UPDATE sur la table) d'incrémenter le compteur
-- de vues sans pouvoir modifier quoi que ce soit d'autre sur le CV.
--
-- SECURITY DEFINER : la fonction s'exécute avec les droits de son propriétaire (postgres), donc
-- l'UPDATE qu'elle contient passe même pour le rôle anon. Elle ne touche qu'à view_count, et
-- uniquement sur une ligne déjà publique et non supprimée — aucune autre donnée n'est exposée
-- ni modifiable par ce chemin.
CREATE OR REPLACE FUNCTION public.increment_cv_view(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.cvs
     SET view_count = view_count + 1
   WHERE share_token = p_token
     AND is_public = TRUE
     AND is_deleted = FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.increment_cv_view(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_cv_view(TEXT) TO anon, authenticated;
