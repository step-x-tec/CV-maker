-- ═════════════════════════════════════════════════════════════════════════════
-- CVxMaker — PRÉSENCE DES UTILISATEURS + CAMPAGNES PUBLICITAIRES
--
--  1. Présence : « en ligne », actifs 24 h / 7 j / 30 j réellement renseignés
--     (jusqu'ici rien n'écrivait profiles.last_seen_at → compteurs à zéro).
--  2. Campagnes : images ou mini-vidéos, lien de redirection, bouton « fermer »
--     retardé, plafonds de vues / clics, planning, ciblage, fréquence, priorité,
--     statistiques (impressions, clics, CTR, fermetures, visiteurs uniques).
--
-- • Idempotent : peut être relancé sans risque.
-- • À exécuter APRÈS 20261017000000_admin_suite.sql.
-- • Toute la logique de diffusion est côté base (SECURITY DEFINER) : le navigateur
--   ne peut ni lire les campagnes brouillon, ni fausser les compteurs des autres.
-- ═════════════════════════════════════════════════════════════════════════════

-- ───────────── 1. PRÉSENCE ─────────────
CREATE TABLE IF NOT EXISTS public.presence_daily (
  day      DATE        NOT NULL,
  user_id  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pings    INTEGER     NOT NULL DEFAULT 1,
  first_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (day, user_id)
);
CREATE INDEX IF NOT EXISTS presence_daily_user_idx ON public.presence_daily(user_id, day DESC);
ALTER TABLE public.presence_daily ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS presence_admin_read ON public.presence_daily;
CREATE POLICY presence_admin_read ON public.presence_daily FOR SELECT TO authenticated USING (public.admin_rank() >= 1);

-- Appelée par l'application toutes les 2 minutes tant que l'onglet est visible.
CREATE OR REPLACE FUNCTION public.touch_presence()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  -- au plus un enregistrement toutes les 45 s par utilisateur
  UPDATE public.profiles SET last_seen_at = NOW()
   WHERE id = v_uid AND (last_seen_at IS NULL OR last_seen_at < NOW() - INTERVAL '45 seconds');
  IF NOT FOUND THEN RETURN; END IF;
  INSERT INTO public.presence_daily(day, user_id) VALUES (CURRENT_DATE, v_uid)
  ON CONFLICT (day, user_id) DO UPDATE SET pings = public.presence_daily.pings + 1, last_at = NOW();
END $$;
REVOKE ALL ON FUNCTION public.touch_presence() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.touch_presence() TO authenticated;

-- Statistiques utilisateurs détaillées (page « Utilisateurs en direct » de l'admin)
CREATE OR REPLACE FUNCTION public.admin_user_stats(p_days INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  n INTEGER := LEAST(GREATEST(COALESCE(p_days,30),7),365);
  v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  SELECT jsonb_build_object(
    'days', n,
    'total',        (SELECT COUNT(*) FROM public.profiles),
    'online_now',   (SELECT COUNT(*) FROM public.profiles WHERE last_seen_at > NOW() - INTERVAL '5 minutes'),
    'online_30m',   (SELECT COUNT(*) FROM public.profiles WHERE last_seen_at > NOW() - INTERVAL '30 minutes'),
    'active_today', (SELECT COUNT(*) FROM public.presence_daily WHERE day = CURRENT_DATE),
    'active_yesterday', (SELECT COUNT(*) FROM public.presence_daily WHERE day = CURRENT_DATE - 1),
    'wau',          (SELECT COUNT(DISTINCT user_id) FROM public.presence_daily WHERE day > CURRENT_DATE - 7),
    'mau',          (SELECT COUNT(DISTINCT user_id) FROM public.presence_daily WHERE day > CURRENT_DATE - 30),
    'new_today',    (SELECT COUNT(*) FROM public.profiles WHERE created_at::date = CURRENT_DATE),
    'new_7',        (SELECT COUNT(*) FROM public.profiles WHERE created_at::date > CURRENT_DATE - 7),
    'new_30',       (SELECT COUNT(*) FROM public.profiles WHERE created_at::date > CURRENT_DATE - 30),
    'new_prev_30',  (SELECT COUNT(*) FROM public.profiles WHERE created_at::date > CURRENT_DATE - 60 AND created_at::date <= CURRENT_DATE - 30),
    'with_cv',      (SELECT COUNT(DISTINCT user_id) FROM public.cvs WHERE NOT is_deleted),
    'exporters',    (SELECT COUNT(DISTINCT user_id) FROM public.export_logs),
    'returning_7',  (SELECT COUNT(*) FROM public.profiles p WHERE p.created_at < NOW() - INTERVAL '7 days'
                      AND EXISTS (SELECT 1 FROM public.presence_daily d WHERE d.user_id = p.id AND d.day > CURRENT_DATE - 7)),
    'tracking_since', (SELECT MIN(day) FROM public.presence_daily),
    'dau_series',   public._series('presence_daily','day','','COUNT(*)',n),
    'signup_series',public._series('profiles','created_at','','COUNT(*)',n),
    'hours',        (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', h, 'n', c) ORDER BY h), '[]'::jsonb)
                       FROM (SELECT EXTRACT(HOUR FROM last_at)::int AS h, COUNT(*) AS c FROM public.presence_daily WHERE day > CURRENT_DATE - 14 GROUP BY 1) x),
    'plans',        (SELECT COALESCE(jsonb_object_agg(plan, c), '{}'::jsonb) FROM (SELECT plan, COUNT(*) c FROM public.profiles GROUP BY plan) x),
    'countries',    (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', COALESCE(NULLIF(country,''),'—'), 'n', c) ORDER BY c DESC), '[]'::jsonb)
                       FROM (SELECT country, COUNT(*) c FROM public.profiles GROUP BY country ORDER BY c DESC LIMIT 8) x),
    'online_users', (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                       FROM (SELECT id, email, name, plan, country, last_seen_at FROM public.profiles
                              WHERE last_seen_at > NOW() - INTERVAL '5 minutes' ORDER BY last_seen_at DESC LIMIT 12) x)
  ) INTO v;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.admin_user_stats(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_user_stats(INTEGER) TO authenticated;

-- ───────────── 2. CAMPAGNES PUBLICITAIRES ─────────────
CREATE TABLE IF NOT EXISTS public.ad_campaigns (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  status          TEXT        NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused','ended')),
  priority        INTEGER     NOT NULL DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
  -- contenu
  format          TEXT        NOT NULL DEFAULT 'popup' CHECK (format IN ('popup','fullscreen','banner','sheet','corner')),
  media_type      TEXT        NOT NULL DEFAULT 'image' CHECK (media_type IN ('image','video','none')),
  media_url       TEXT        CHECK (media_url  IS NULL OR media_url  ~* '^https://'),
  poster_url      TEXT        CHECK (poster_url IS NULL OR poster_url ~* '^https://'),
  title           TEXT        CHECK (char_length(title) <= 120),
  body            TEXT        CHECK (char_length(body)  <= 400),
  cta_label       TEXT        NOT NULL DEFAULT 'En savoir plus' CHECK (char_length(cta_label) BETWEEN 1 AND 40),
  link_url        TEXT        CHECK (link_url IS NULL OR link_url ~* '^https?://'),
  link_new_tab    BOOLEAN     NOT NULL DEFAULT TRUE,
  sponsor_label   TEXT        NOT NULL DEFAULT 'Sponsorisé' CHECK (char_length(sponsor_label) <= 24),
  -- comportement
  close_delay_s   INTEGER     NOT NULL DEFAULT 5 CHECK (close_delay_s BETWEEN 0 AND 60),
  allow_close     BOOLEAN     NOT NULL DEFAULT TRUE,
  auto_close_s    INTEGER     CHECK (auto_close_s IS NULL OR auto_close_s BETWEEN 3 AND 300),
  video_autoplay  BOOLEAN     NOT NULL DEFAULT TRUE,
  video_muted     BOOLEAN     NOT NULL DEFAULT TRUE,
  video_loop      BOOLEAN     NOT NULL DEFAULT FALSE,
  -- apparence : { bg, text, accent, overlay (0-90), radius (0-40), animation, align, sponsor }
  theme           JSONB       NOT NULL DEFAULT '{}'::jsonb,
  -- ciblage : { plans[], countries[], devices[], min_account_days, max_account_days, has_exported, include_admins }
  audience        JSONB       NOT NULL DEFAULT '{}'::jsonb,
  -- diffusion
  placement       TEXT        NOT NULL DEFAULT 'app_open' CHECK (placement IN ('app_open','after_export','my_cvs','editor')),
  trigger_delay_s INTEGER     NOT NULL DEFAULT 3 CHECK (trigger_delay_s BETWEEN 0 AND 120),
  frequency       TEXT        NOT NULL DEFAULT 'once_per_day' CHECK (frequency IN ('once','once_per_session','once_per_day','every_n_days','always')),
  frequency_days  INTEGER     NOT NULL DEFAULT 3 CHECK (frequency_days BETWEEN 1 AND 90),
  max_impressions INTEGER     CHECK (max_impressions IS NULL OR max_impressions > 0),
  max_per_user    INTEGER     CHECK (max_per_user    IS NULL OR max_per_user    > 0),
  daily_cap       INTEGER     CHECK (daily_cap       IS NULL OR daily_cap       > 0),
  max_clicks      INTEGER     CHECK (max_clicks      IS NULL OR max_clicks      > 0),
  starts_at       TIMESTAMPTZ,
  ends_at         TIMESTAMPTZ,
  -- compteurs (mis à jour par ads_track)
  impressions       BIGINT    NOT NULL DEFAULT 0,
  unique_viewers    BIGINT    NOT NULL DEFAULT 0,
  clicks            BIGINT    NOT NULL DEFAULT 0,
  closes            BIGINT    NOT NULL DEFAULT 0,
  video_completions BIGINT    NOT NULL DEFAULT 0,
  created_by      UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS ad_campaigns_pick_idx ON public.ad_campaigns(status, placement, priority DESC);

CREATE OR REPLACE FUNCTION public._ad_touch() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := NOW(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS ad_campaigns_touch ON public.ad_campaigns;
CREATE TRIGGER ad_campaigns_touch BEFORE UPDATE ON public.ad_campaigns FOR EACH ROW EXECUTE FUNCTION public._ad_touch();

CREATE TABLE IF NOT EXISTS public.ad_events (
  id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  campaign_id UUID        NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  user_id     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  event       TEXT        NOT NULL CHECK (event IN ('impression','click','close','video_complete')),
  session_id  TEXT        CHECK (char_length(session_id) <= 64),
  placement   TEXT,
  device      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ad_events_camp_time_idx ON public.ad_events(campaign_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ad_events_user_idx      ON public.ad_events(campaign_id, user_id, event, created_at DESC);

ALTER TABLE public.ad_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_events    ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ad_campaigns_read  ON public.ad_campaigns;
DROP POLICY IF EXISTS ad_campaigns_write ON public.ad_campaigns;
CREATE POLICY ad_campaigns_read  ON public.ad_campaigns FOR SELECT TO authenticated USING (public.admin_rank() >= 1);
CREATE POLICY ad_campaigns_write ON public.ad_campaigns FOR ALL    TO authenticated USING (public.admin_rank() >= 3) WITH CHECK (public.admin_rank() >= 3);
DROP POLICY IF EXISTS ad_events_read ON public.ad_events;
CREATE POLICY ad_events_read ON public.ad_events FOR SELECT TO authenticated USING (public.admin_rank() >= 1);
-- (aucune politique d'écriture sur ad_events : uniquement via ads_track)
REVOKE ALL ON public.ad_campaigns, public.ad_events FROM anon;

-- ── Choix de la campagne à afficher (une seule, la plus prioritaire éligible) ──
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
    'theme', c.theme, 'trigger_delay_s', c.trigger_delay_s, 'placement', c.placement);
END $$;
REVOKE ALL ON FUNCTION public.ads_pick(TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ads_pick(TEXT,TEXT,TEXT) TO authenticated;

-- ── Enregistrement d'un évènement (impression, clic, fermeture, fin de vidéo) ──
CREATE OR REPLACE FUNCTION public.ads_track(p_campaign UUID, p_event TEXT, p_session TEXT DEFAULT NULL, p_placement TEXT DEFAULT NULL, p_device TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_first BOOLEAN := FALSE;
  v_row   public.ad_campaigns%ROWTYPE;
  v_sess  TEXT := LEFT(p_session, 64);
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'AUTH'); END IF;
  IF p_event NOT IN ('impression','click','close','video_complete') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'EVENT'); END IF;
  PERFORM 1 FROM public.ad_campaigns WHERE id = p_campaign AND status IN ('active','paused','ended');
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'CAMPAIGN'); END IF;

  -- anti-doublon : même évènement, même utilisateur, même session, mêmes 3 dernières secondes
  -- (une impression n'est comptée qu'une fois par session et par campagne)
  IF p_event = 'impression' AND v_sess IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND e.user_id = v_uid AND e.event = 'impression' AND e.session_id = v_sess) THEN
    RETURN jsonb_build_object('ok', TRUE, 'dup', TRUE);
  END IF;
  IF p_event <> 'impression' AND EXISTS (
       SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND e.user_id = v_uid AND e.event = p_event
          AND e.session_id IS NOT DISTINCT FROM v_sess AND e.created_at > NOW() - INTERVAL '3 seconds') THEN
    RETURN jsonb_build_object('ok', TRUE, 'dup', TRUE);
  END IF;

  IF p_event = 'impression' THEN
    v_first := NOT EXISTS (SELECT 1 FROM public.ad_events e WHERE e.campaign_id = p_campaign AND e.user_id = v_uid AND e.event = 'impression');
  END IF;

  INSERT INTO public.ad_events(campaign_id, user_id, event, session_id, placement, device)
  VALUES (p_campaign, v_uid, p_event, v_sess, LEFT(p_placement, 24), LEFT(p_device, 12));

  UPDATE public.ad_campaigns SET
    impressions       = impressions       + CASE WHEN p_event = 'impression'     THEN 1 ELSE 0 END,
    unique_viewers    = unique_viewers    + CASE WHEN p_event = 'impression' AND v_first THEN 1 ELSE 0 END,
    clicks            = clicks            + CASE WHEN p_event = 'click'          THEN 1 ELSE 0 END,
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
REVOKE ALL ON FUNCTION public.ads_track(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ads_track(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;

-- ── Admin : vue d'ensemble ──
CREATE OR REPLACE FUNCTION public.admin_ads_overview(p_days INTEGER DEFAULT 14)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER := LEAST(GREATEST(COALESCE(p_days,14),7),180); d0 DATE; v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  d0 := CURRENT_DATE - (n - 1);
  SELECT jsonb_build_object(
    'days', n,
    'active',    (SELECT COUNT(*) FROM public.ad_campaigns WHERE status = 'active' AND (ends_at IS NULL OR ends_at > NOW()) AND (starts_at IS NULL OR starts_at <= NOW())),
    'scheduled', (SELECT COUNT(*) FROM public.ad_campaigns WHERE status = 'active' AND starts_at > NOW()),
    'drafts',    (SELECT COUNT(*) FROM public.ad_campaigns WHERE status = 'draft'),
    'impressions',(SELECT COUNT(*) FROM public.ad_events WHERE event = 'impression' AND created_at::date >= d0),
    'clicks',     (SELECT COUNT(*) FROM public.ad_events WHERE event = 'click'      AND created_at::date >= d0),
    'closes',     (SELECT COUNT(*) FROM public.ad_events WHERE event = 'close'      AND created_at::date >= d0),
    'viewers',    (SELECT COUNT(DISTINCT user_id) FROM public.ad_events WHERE event = 'impression' AND created_at::date >= d0),
    'imp_series', public._series('ad_events','created_at','event = ''impression''','COUNT(*)',n),
    'clk_series', public._series('ad_events','created_at','event = ''click''','COUNT(*)',n)
  ) INTO v;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.admin_ads_overview(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ads_overview(INTEGER) TO authenticated;

-- ── Admin : statistiques d'une campagne ──
CREATE OR REPLACE FUNCTION public.admin_ad_stats(p_campaign UUID, p_days INTEGER DEFAULT 14)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER := LEAST(GREATEST(COALESCE(p_days,14),7),180); cond TEXT; v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  cond := format('campaign_id = %L::uuid AND ', p_campaign);
  SELECT jsonb_build_object(
    'campaign', (SELECT to_jsonb(c) FROM public.ad_campaigns c WHERE c.id = p_campaign),
    'days', n,
    'imp_series',   public._series('ad_events','created_at', cond || 'event = ''impression''', 'COUNT(*)', n),
    'clk_series',   public._series('ad_events','created_at', cond || 'event = ''click''', 'COUNT(*)', n),
    'close_series', public._series('ad_events','created_at', cond || 'event = ''close''', 'COUNT(*)', n),
    'by_placement', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', COALESCE(placement,'—'), 'n', c) ORDER BY c DESC), '[]'::jsonb)
                       FROM (SELECT placement, COUNT(*) c FROM public.ad_events WHERE campaign_id = p_campaign AND event = 'impression' GROUP BY placement) x),
    'by_device',    (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', COALESCE(device,'—'), 'n', c) ORDER BY c DESC), '[]'::jsonb)
                       FROM (SELECT device, COUNT(*) c FROM public.ad_events WHERE campaign_id = p_campaign AND event = 'impression' GROUP BY device) x),
    'by_plan',      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', COALESCE(plan,'—'), 'n', c) ORDER BY c DESC), '[]'::jsonb)
                       FROM (SELECT p.plan, COUNT(*) c FROM public.ad_events e JOIN public.profiles p ON p.id = e.user_id
                              WHERE e.campaign_id = p_campaign AND e.event = 'impression' GROUP BY p.plan) x),
    'last_events',  (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                       FROM (SELECT e.event, e.placement, e.device, e.created_at, p.email FROM public.ad_events e
                               LEFT JOIN public.profiles p ON p.id = e.user_id
                              WHERE e.campaign_id = p_campaign ORDER BY e.created_at DESC LIMIT 15) x)
  ) INTO v;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.admin_ad_stats(UUID,INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ad_stats(UUID,INTEGER) TO authenticated;

-- ── Admin : actions (statut, duplication, remise à zéro) — avec journal d'audit ──
CREATE OR REPLACE FUNCTION public.admin_ad_set_status(p_id UUID, p_status TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE old_s TEXT;
BEGIN
  PERFORM public.admin_require(3);
  IF p_status NOT IN ('draft','active','paused','ended') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  SELECT status INTO old_s FROM public.ad_campaigns WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Campagne introuvable'; END IF;
  IF p_status = 'active' THEN
    -- on ne publie pas une campagne vide
    PERFORM 1 FROM public.ad_campaigns WHERE id = p_id
       AND (title IS NOT NULL AND title <> '' OR media_url IS NOT NULL OR body IS NOT NULL AND body <> '');
    IF NOT FOUND THEN RAISE EXCEPTION 'Ajoutez au moins un titre, un texte ou un média avant de publier.'; END IF;
  END IF;
  UPDATE public.ad_campaigns SET status = p_status WHERE id = p_id;
  PERFORM public._audit('ad.status', 'ad_campaign', p_id::text, jsonb_build_object('status', old_s), jsonb_build_object('status', p_status));
  RETURN jsonb_build_object('ok', TRUE, 'status', p_status);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ad_duplicate(p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE new_id UUID;
BEGIN
  PERFORM public.admin_require(3);
  INSERT INTO public.ad_campaigns(name, status, priority, format, media_type, media_url, poster_url, title, body, cta_label, link_url, link_new_tab,
      sponsor_label, close_delay_s, allow_close, auto_close_s, video_autoplay, video_muted, video_loop, theme, audience, placement, trigger_delay_s,
      frequency, frequency_days, max_impressions, max_per_user, daily_cap, max_clicks, starts_at, ends_at, created_by)
  SELECT LEFT(name || ' (copie)', 120), 'draft', priority, format, media_type, media_url, poster_url, title, body, cta_label, link_url, link_new_tab,
      sponsor_label, close_delay_s, allow_close, auto_close_s, video_autoplay, video_muted, video_loop, theme, audience, placement, trigger_delay_s,
      frequency, frequency_days, max_impressions, max_per_user, daily_cap, max_clicks, starts_at, ends_at, auth.uid()
    FROM public.ad_campaigns WHERE id = p_id
  RETURNING id INTO new_id;
  IF new_id IS NULL THEN RAISE EXCEPTION 'Campagne introuvable'; END IF;
  PERFORM public._audit('ad.duplicate', 'ad_campaign', new_id::text, NULL, jsonb_build_object('from', p_id));
  RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_ad_reset_stats(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_require(3);
  DELETE FROM public.ad_events WHERE campaign_id = p_id;
  UPDATE public.ad_campaigns SET impressions = 0, unique_viewers = 0, clicks = 0, closes = 0, video_completions = 0 WHERE id = p_id;
  PERFORM public._audit('ad.reset', 'ad_campaign', p_id::text, NULL, NULL);
  RETURN jsonb_build_object('ok', TRUE);
END $$;

REVOKE ALL ON FUNCTION public.admin_ad_set_status(UUID,TEXT), public.admin_ad_duplicate(UUID), public.admin_ad_reset_stats(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ad_set_status(UUID,TEXT), public.admin_ad_duplicate(UUID), public.admin_ad_reset_stats(UUID) TO authenticated;

-- ───────────── 3. STOCKAGE DES MÉDIAS (images / mini-vidéos) ─────────────
-- Bucket public en lecture (les utilisateurs doivent pouvoir afficher l'annonce),
-- écriture réservée aux admins (rôle admin ou plus). 25 Mo max par fichier.
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES ('ad-media', 'ad-media', TRUE, 26214400,
          ARRAY['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm'])
  ON CONFLICT (id) DO UPDATE SET public = TRUE, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;

  DROP POLICY IF EXISTS ad_media_insert ON storage.objects;
  DROP POLICY IF EXISTS ad_media_update ON storage.objects;
  DROP POLICY IF EXISTS ad_media_delete ON storage.objects;
  DROP POLICY IF EXISTS ad_media_select ON storage.objects;
  CREATE POLICY ad_media_select ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'ad-media' AND public.admin_rank() >= 1);
  CREATE POLICY ad_media_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'ad-media' AND public.admin_rank() >= 3);
  CREATE POLICY ad_media_update ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'ad-media' AND public.admin_rank() >= 3);
  CREATE POLICY ad_media_delete ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'ad-media' AND public.admin_rank() >= 3);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Stockage non configuré automatiquement (%). Créez à la main un bucket public « ad-media » dans Supabase > Storage.', SQLERRM;
END $$;
