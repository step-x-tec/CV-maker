-- ============================================================================
--  Pubs pour les visiteurs SANS compte + plusieurs emplacements par campagne
--  À exécuter APRÈS 20261029000000_ads_interactive.sql (idempotent).
--  - ads_pick / ads_track accessibles au rôle anon (identifiant anonyme = p_session, ≥ 8 caractères)
--  - ciblage « plans » : la valeur 'guest' désigne les visiteurs sans compte
--  - ad_campaigns.extra_placements : emplacements supplémentaires (ex. ["my_cvs","after_export"])
-- ============================================================================
ALTER TABLE public.ad_campaigns ADD COLUMN IF NOT EXISTS extra_placements JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.ad_campaigns DROP CONSTRAINT IF EXISTS ad_campaigns_extra_pl_chk;
ALTER TABLE public.ad_campaigns ADD CONSTRAINT ad_campaigns_extra_pl_chk CHECK (jsonb_typeof(extra_placements) = 'array' AND jsonb_array_length(extra_placements) <= 4);

CREATE OR REPLACE FUNCTION public.ads_pick(p_placement TEXT, p_device TEXT DEFAULT 'mobile', p_session TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid  UUID := auth.uid();
  pr     public.profiles%ROWTYPE;
  c      public.ad_campaigns%ROWTYPE;
  v_dev  TEXT := CASE WHEN p_device IN ('mobile','desktop') THEN p_device ELSE 'mobile' END;
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT * INTO pr FROM public.profiles WHERE id = v_uid;
    IF NOT FOUND OR pr.is_banned THEN RETURN NULL; END IF;
  ELSE  -- visiteur sans compte : identifié par un identifiant anonyme stocké sur son appareil
    IF p_session IS NULL OR char_length(p_session) < 8 THEN RETURN NULL; END IF;
    pr.plan := 'guest'; pr.is_admin := FALSE; pr.country := NULL; pr.created_at := NOW();
  END IF;

  SELECT a.* INTO c FROM public.ad_campaigns a
   WHERE a.status = 'active'
     AND (a.placement = p_placement OR COALESCE(a.extra_placements,'[]'::jsonb) ? p_placement)
     AND (a.starts_at IS NULL OR a.starts_at <= NOW())
     AND (a.ends_at   IS NULL OR a.ends_at   >  NOW())
     AND (a.max_impressions IS NULL OR a.impressions < a.max_impressions)
     AND (a.max_clicks      IS NULL OR a.clicks      < a.max_clicks)
     AND (a.daily_cap IS NULL OR (SELECT COUNT(*) FROM public.ad_events e
            WHERE e.campaign_id = a.id AND e.event = 'impression' AND e.created_at >= date_trunc('day', NOW())) < a.daily_cap)
     AND (a.max_per_user IS NULL OR (SELECT COUNT(*) FROM public.ad_events e
            WHERE e.campaign_id = a.id AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = p_session)) AND e.event = 'impression') < a.max_per_user)
     AND CASE a.frequency
           WHEN 'once' THEN NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = p_session)) AND e.event = 'impression')
           WHEN 'once_per_session' THEN p_session IS NULL OR NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = p_session)) AND e.event = 'impression' AND e.session_id = p_session)
           WHEN 'once_per_day' THEN NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = p_session)) AND e.event = 'impression' AND e.created_at > NOW() - INTERVAL '20 hours')
           WHEN 'every_n_days' THEN NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = p_session)) AND e.event = 'impression' AND e.created_at > NOW() - make_interval(days => a.frequency_days))
           ELSE TRUE END
     -- ciblage
     AND (NOT pr.is_admin OR COALESCE(a.audience->>'include_admins','false') = 'true')
     AND (jsonb_typeof(a.audience->'plans') IS DISTINCT FROM 'array' OR jsonb_array_length(a.audience->'plans') = 0 OR (a.audience->'plans') ? pr.plan)
     AND (jsonb_typeof(a.audience->'countries') IS DISTINCT FROM 'array' OR jsonb_array_length(a.audience->'countries') = 0 OR (a.audience->'countries') ? upper(COALESCE(pr.country,'')))
     AND (jsonb_typeof(a.audience->'devices') IS DISTINCT FROM 'array' OR jsonb_array_length(a.audience->'devices') = 0 OR (a.audience->'devices') ? v_dev)
     AND (NULLIF(a.audience->>'min_account_days','') IS NULL OR EXTRACT(EPOCH FROM (NOW() - pr.created_at))/86400 >= (a.audience->>'min_account_days')::numeric)
     AND (NULLIF(a.audience->>'max_account_days','') IS NULL OR EXTRACT(EPOCH FROM (NOW() - pr.created_at))/86400 <= (a.audience->>'max_account_days')::numeric)
     AND CASE COALESCE(a.audience->>'has_exported','any')
           WHEN 'yes' THEN EXISTS (SELECT 1 FROM public.export_logs x WHERE x.user_id = v_uid)
           WHEN 'no'  THEN NOT EXISTS (SELECT 1 FROM public.export_logs x WHERE x.user_id = v_uid)
           ELSE TRUE END
   ORDER BY a.priority DESC, random()
   LIMIT 1;

  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'id', c.id, 'format', c.format, 'media_type', c.media_type, 'media_url', c.media_url, 'poster_url', c.poster_url,
    'title', c.title, 'body', c.body, 'cta_label', c.cta_label, 'link_url', c.link_url, 'link_new_tab', c.link_new_tab,
    'sponsor_label', c.sponsor_label, 'close_delay_s', c.close_delay_s, 'allow_close', c.allow_close, 'auto_close_s', c.auto_close_s,
    'video_autoplay', c.video_autoplay, 'video_muted', c.video_muted, 'video_loop', c.video_loop,
    'theme', c.theme, 'buttons', COALESCE(c.buttons,'[]'::jsonb), 'trigger_delay_s', c.trigger_delay_s, 'placement', c.placement);
END $$;
REVOKE ALL ON FUNCTION public.ads_pick(TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ads_pick(TEXT,TEXT,TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.ads_track(p_campaign UUID, p_event TEXT, p_session TEXT DEFAULT NULL, p_placement TEXT DEFAULT NULL, p_device TEXT DEFAULT NULL, p_detail TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_first BOOLEAN := FALSE;
  v_row   public.ad_campaigns%ROWTYPE;
  v_sess  TEXT := LEFT(p_session, 64);
BEGIN
  IF v_uid IS NULL AND (p_session IS NULL OR char_length(p_session) < 8) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'AUTH'); END IF;
  -- anti-abus visiteurs : au plus 60 évènements par heure et par identifiant anonyme
  IF v_uid IS NULL AND (SELECT COUNT(*) FROM public.ad_events x WHERE x.user_id IS NULL AND x.session_id = LEFT(p_session,64) AND x.created_at > NOW() - INTERVAL '1 hour') >= 60 THEN
    RETURN jsonb_build_object('ok', TRUE, 'dup', TRUE);
  END IF;
  IF p_event NOT IN ('impression','click','close','video_complete','button') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'EVENT'); END IF;
  PERFORM 1 FROM public.ad_campaigns WHERE id = p_campaign AND status IN ('active','paused','ended');
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'CAMPAIGN'); END IF;

  -- anti-doublon : même évènement, même utilisateur, même session, mêmes 3 dernières secondes
  -- (une impression n'est comptée qu'une fois par session et par campagne)
  IF p_event = 'impression' AND v_sess IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = v_sess)) AND e.event = 'impression' AND e.session_id = v_sess) THEN
    RETURN jsonb_build_object('ok', TRUE, 'dup', TRUE);
  END IF;
  IF p_event <> 'impression' AND EXISTS (
       SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = v_sess)) AND e.event = p_event AND e.detail IS NOT DISTINCT FROM LEFT(p_detail,80)
          AND e.session_id IS NOT DISTINCT FROM v_sess AND e.created_at > NOW() - INTERVAL '3 seconds') THEN
    RETURN jsonb_build_object('ok', TRUE, 'dup', TRUE);
  END IF;

  IF p_event = 'impression' THEN
    v_first := NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND ((v_uid IS NOT NULL AND e.user_id = v_uid) OR (v_uid IS NULL AND e.user_id IS NULL AND e.session_id = v_sess)) AND e.event = 'impression');
  END IF;

  INSERT INTO public.ad_events(campaign_id, user_id, event, session_id, placement, device, detail)
  VALUES (p_campaign, v_uid, p_event, v_sess, LEFT(p_placement, 24), LEFT(p_device, 12), LEFT(p_detail, 80));

  UPDATE public.ad_campaigns SET
    impressions       = impressions       + CASE WHEN p_event = 'impression'     THEN 1 ELSE 0 END,
    unique_viewers    = unique_viewers    + CASE WHEN p_event = 'impression' AND v_first THEN 1 ELSE 0 END,
    clicks            = clicks            + CASE WHEN p_event IN ('click','button') THEN 1 ELSE 0 END,
    closes            = closes            + CASE WHEN p_event = 'close'          THEN 1 ELSE 0 END,
    video_completions = video_completions + CASE WHEN p_event = 'video_complete' THEN 1 ELSE 0 END
  WHERE id = p_campaign RETURNING * INTO v_row;

  -- fin automatique : plafond atteint ou date dépassée
  IF v_row.status = 'active' AND (
       (v_row.max_impressions IS NOT NULL AND v_row.impressions >= v_row.max_impressions)
    OR (v_row.max_clicks      IS NOT NULL AND v_row.clicks      >= v_row.max_clicks)
    OR (v_row.ends_at         IS NOT NULL AND v_row.ends_at     <= NOW())) THEN
    UPDATE public.ad_campaigns SET status = 'ended' WHERE id = p_campaign;
    v_row.status := 'ended';
  END IF;
  RETURN jsonb_build_object('ok', TRUE, 'status', v_row.status);
END $$;
REVOKE ALL ON FUNCTION public.ads_track(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ads_track(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO anon, authenticated;
