-- ============================================================================
--  Publicités interactives : jusqu'à 3 boutons d'action par annonce
--  Actions : link · app · copy · share · whatsapp · mailto · tel · vote · close
--  À exécuter APRÈS 20261027000000_ads_and_presence.sql (idempotent).
-- ============================================================================
ALTER TABLE public.ad_campaigns ADD COLUMN IF NOT EXISTS buttons JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.ad_campaigns DROP CONSTRAINT IF EXISTS ad_campaigns_buttons_chk;
ALTER TABLE public.ad_campaigns ADD CONSTRAINT ad_campaigns_buttons_chk
  CHECK (jsonb_typeof(buttons) = 'array' AND jsonb_array_length(buttons) <= 3);
ALTER TABLE public.ad_events ADD COLUMN IF NOT EXISTS detail TEXT;
ALTER TABLE public.ad_events DROP CONSTRAINT IF EXISTS ad_events_event_check;
ALTER TABLE public.ad_events ADD CONSTRAINT ad_events_event_check CHECK (event IN ('impression','click','close','video_complete','button'));

CREATE OR REPLACE FUNCTION public.ads_pick(p_placement TEXT, p_device TEXT DEFAULT 'mobile', p_session TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid  UUID := auth.uid();
  pr     public.profiles%ROWTYPE;
  c      public.ad_campaigns%ROWTYPE;
  v_dev  TEXT := CASE WHEN p_device IN ('mobile','desktop') THEN p_device ELSE 'mobile' END;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO pr FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND OR pr.is_banned THEN RETURN NULL; END IF;

  SELECT a.* INTO c FROM public.ad_campaigns a
   WHERE a.status = 'active'
     AND a.placement = p_placement
     AND (a.starts_at IS NULL OR a.starts_at <= NOW())
     AND (a.ends_at   IS NULL OR a.ends_at   >  NOW())
     AND (a.max_impressions IS NULL OR a.impressions < a.max_impressions)
     AND (a.max_clicks      IS NULL OR a.clicks      < a.max_clicks)
     AND (a.daily_cap IS NULL OR (SELECT COUNT(*) FROM public.ad_events e
            WHERE e.campaign_id = a.id AND e.event = 'impression' AND e.created_at >= date_trunc('day', NOW())) < a.daily_cap)
     AND (a.max_per_user IS NULL OR (SELECT COUNT(*) FROM public.ad_events e
            WHERE e.campaign_id = a.id AND e.user_id = v_uid AND e.event = 'impression') < a.max_per_user)
     AND CASE a.frequency
           WHEN 'once' THEN NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND e.user_id = v_uid AND e.event = 'impression')
           WHEN 'once_per_session' THEN p_session IS NULL OR NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND e.user_id = v_uid AND e.event = 'impression' AND e.session_id = p_session)
           WHEN 'once_per_day' THEN NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND e.user_id = v_uid AND e.event = 'impression' AND e.created_at > NOW() - INTERVAL '20 hours')
           WHEN 'every_n_days' THEN NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = a.id AND e.user_id = v_uid AND e.event = 'impression' AND e.created_at > NOW() - make_interval(days => a.frequency_days))
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
REVOKE ALL ON FUNCTION public.ads_pick(TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ads_pick(TEXT,TEXT,TEXT) TO authenticated;

DROP FUNCTION IF EXISTS public.ads_track(UUID,TEXT,TEXT,TEXT,TEXT);
CREATE OR REPLACE FUNCTION public.ads_track(p_campaign UUID, p_event TEXT, p_session TEXT DEFAULT NULL, p_placement TEXT DEFAULT NULL, p_device TEXT DEFAULT NULL, p_detail TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_first BOOLEAN := FALSE;
  v_row   public.ad_campaigns%ROWTYPE;
  v_sess  TEXT := LEFT(p_session, 64);
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'AUTH'); END IF;
  IF p_event NOT IN ('impression','click','close','video_complete','button') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'EVENT'); END IF;
  PERFORM 1 FROM public.ad_campaigns WHERE id = p_campaign AND status IN ('active','paused','ended');
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'CAMPAIGN'); END IF;

  -- anti-doublon : même évènement, même utilisateur, même session, mêmes 3 dernières secondes
  -- (une impression n'est comptée qu'une fois par session et par campagne)
  IF p_event = 'impression' AND v_sess IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND e.user_id = v_uid AND e.event = 'impression' AND e.session_id = v_sess) THEN
    RETURN jsonb_build_object('ok', TRUE, 'dup', TRUE);
  END IF;
  IF p_event <> 'impression' AND EXISTS (
       SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND e.user_id = v_uid AND e.event = p_event AND e.detail IS NOT DISTINCT FROM LEFT(p_detail,80)
          AND e.session_id IS NOT DISTINCT FROM v_sess AND e.created_at > NOW() - INTERVAL '3 seconds') THEN
    RETURN jsonb_build_object('ok', TRUE, 'dup', TRUE);
  END IF;

  IF p_event = 'impression' THEN
    v_first := NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND e.user_id = v_uid AND e.event = 'impression');
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
REVOKE ALL ON FUNCTION public.ads_track(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ads_track(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
