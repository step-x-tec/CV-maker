-- ═══════════════════════════════════════════════════════════════════════
-- SmartCV Pro — TÉMOIGNAGES PUBLICS (avis laissés par les visiteurs de la
-- landing page, validés par un admin avant publication)
-- Distinct de public.feedback (feedback interne, réservé aux comptes
-- connectés) : ici n'importe qui, connecté ou non, peut soumettre un avis
-- affichable sur la page d'accueil, mais seul un admin peut le publier.
-- Ce script est idempotent (relançable sans risque).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.testimonials (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  name        TEXT        NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
  role        TEXT        CHECK (role IS NULL OR char_length(role) <= 100),
  message     TEXT        NOT NULL CHECK (char_length(trim(message)) BETWEEN 10 AND 600),
  rating      INTEGER     CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
  status      TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  admin_note  TEXT,
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_testimonials_status  ON public.testimonials(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_testimonials_user     ON public.testimonials(user_id) WHERE user_id IS NOT NULL;

ALTER TABLE public.testimonials ENABLE ROW LEVEL SECURITY;

-- Lecture publique : uniquement les avis déjà validés (landing page)
DROP POLICY IF EXISTS "testi_public_read" ON public.testimonials;
CREATE POLICY "testi_public_read" ON public.testimonials FOR SELECT
  USING (status = 'approved');

-- Un utilisateur connecté peut voir ses propres avis, même en attente
DROP POLICY IF EXISTS "testi_own_read" ON public.testimonials;
CREATE POLICY "testi_own_read" ON public.testimonials FOR SELECT
  USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);

-- Tout le monde (visiteur anonyme ou connecté) peut soumettre un avis,
-- mais JAMAIS directement approuvé ni rattaché à un autre compte que le sien.
DROP POLICY IF EXISTS "testi_public_insert" ON public.testimonials;
CREATE POLICY "testi_public_insert" ON public.testimonials FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    status = 'pending'
    AND reviewed_at IS NULL
    AND reviewed_by IS NULL
    AND (user_id IS NULL OR user_id = auth.uid())
  );

-- Un admin voit tout et peut valider / rejeter / supprimer (public.is_admin()
-- défini dans 20260928000100_security_hardening.sql)
DROP POLICY IF EXISTS "testi_admin_all" ON public.testimonials;
CREATE POLICY "testi_admin_all" ON public.testimonials FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());
