-- ═══════════════════════════════════════════════════════════════════════
-- CVxMaker — INTÉRÊT POUR LES FONCTIONNALITÉS À VENIR
-- Liste « Me prévenir » (lettre de motivation, demande d'emploi/stage,
-- import de CV). N'importe qui peut s'inscrire ; seul un admin peut lire.
-- Script idempotent (relançable sans risque).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.feature_interest (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  feature    TEXT        NOT NULL CHECK (feature IN ('lettre','demande','import')),
  email      TEXT        NOT NULL CHECK (char_length(email) BETWEEN 5 AND 200 AND email LIKE '%_@_%._%'),
  user_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_feature_interest ON public.feature_interest(feature, lower(email));

ALTER TABLE public.feature_interest ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fi_public_insert" ON public.feature_interest;
CREATE POLICY "fi_public_insert" ON public.feature_interest FOR INSERT
  TO anon, authenticated
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

DROP POLICY IF EXISTS "fi_admin_all" ON public.feature_interest;
CREATE POLICY "fi_admin_all" ON public.feature_interest FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());
