-- ═══════════════════════════════════════════════════════════════════════
-- CVxMaker — SUIVI DU PARCOURS (entonnoir de conversion)
-- Événements anonymes (sans données personnelles) : visite, clic sur le
-- bouton principal, ouverture de l'éditeur, export PDF, etc. + source (UTM).
-- Aucune lecture publique ; seul un admin lit les chiffres agrégés.
-- Script idempotent (relançable sans risque).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.funnel_events (
  id         BIGSERIAL   PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  visitor    UUID        NOT NULL,
  name       TEXT        NOT NULL,
  source     TEXT,
  medium     TEXT,
  campaign   TEXT,
  props      JSONB       NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_funnel_events_name_date ON public.funnel_events(name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_funnel_events_campaign  ON public.funnel_events(campaign, created_at DESC);

ALTER TABLE public.funnel_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "funnel_admin_read" ON public.funnel_events;
CREATE POLICY "funnel_admin_read" ON public.funnel_events FOR SELECT USING (public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.funnel_events FROM anon, authenticated;

-- Enregistrement : liste blanche de noms, champs bornés, limite par visiteur.
CREATE OR REPLACE FUNCTION public.track_event(
  p_visitor UUID, p_name TEXT, p_source TEXT DEFAULT NULL, p_medium TEXT DEFAULT NULL,
  p_campaign TEXT DEFAULT NULL, p_props JSONB DEFAULT '{}'::jsonb
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_visitor IS NULL OR p_name NOT IN (
    'landing_view','cta_click','app_open','template_pick','signup','cv_saved','pdf_export','job_match','cv_import','upgrade_click','payment_done'
  ) THEN RETURN; END IF;
  -- anti-abus : 120 événements par visiteur et par heure
  IF (SELECT COUNT(*) FROM public.funnel_events WHERE visitor = p_visitor AND created_at > NOW() - INTERVAL '1 hour') >= 120 THEN RETURN; END IF;
  INSERT INTO public.funnel_events(visitor, name, source, medium, campaign, props)
  VALUES (p_visitor, p_name, left(p_source,60), left(p_medium,60), left(p_campaign,80),
          CASE WHEN length(COALESCE(p_props,'{}'::jsonb)::text) <= 600 THEN COALESCE(p_props,'{}'::jsonb) ELSE '{}'::jsonb END);
END $$;
REVOKE ALL ON FUNCTION public.track_event(UUID,TEXT,TEXT,TEXT,TEXT,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.track_event(UUID,TEXT,TEXT,TEXT,TEXT,JSONB) TO anon, authenticated;

-- Entonnoir agrégé pour l'admin : visiteurs uniques par étape, par source, sur N jours.
CREATE OR REPLACE FUNCTION public.admin_funnel(p_days INT DEFAULT 30)
RETURNS TABLE(campaign TEXT, source TEXT, landing BIGINT, cta BIGINT, app_open BIGINT, signup BIGINT, exported BIGINT, paid BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Droits insuffisants'; END IF;
  RETURN QUERY
  SELECT COALESCE(e.campaign,'(direct)'), COALESCE(e.source,'(direct)'),
    COUNT(DISTINCT e.visitor) FILTER (WHERE e.name='landing_view'),
    COUNT(DISTINCT e.visitor) FILTER (WHERE e.name='cta_click'),
    COUNT(DISTINCT e.visitor) FILTER (WHERE e.name='app_open'),
    COUNT(DISTINCT e.visitor) FILTER (WHERE e.name='signup'),
    COUNT(DISTINCT e.visitor) FILTER (WHERE e.name='pdf_export'),
    COUNT(DISTINCT e.visitor) FILTER (WHERE e.name='payment_done')
  FROM public.funnel_events e
  WHERE e.created_at > NOW() - make_interval(days => GREATEST(1, LEAST(p_days, 365)))
  GROUP BY 1, 2 ORDER BY 3 DESC;
END $$;
REVOKE ALL ON FUNCTION public.admin_funnel(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_funnel(INT) TO authenticated;
