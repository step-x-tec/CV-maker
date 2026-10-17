-- ═══════════════════════════════════════════════════════════════════════════
-- CVxMaker — SUITE ADMIN : rôles, statistiques, gestion utilisateurs / CV /
-- paiements, notes internes, journal d'audit, réglages du site.
--
-- • Toutes les fonctions sont SECURITY DEFINER et vérifient le RÔLE de l'appelant
--   en base (viewer < moderator < admin < superadmin). Le navigateur n'a jamais
--   besoin d'une clé secrète.
-- • Idempotent : peut être relancé sans risque.
-- • À exécuter APRÈS les migrations précédentes (base, sécurité, etc.).
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────── Rôles ─────────────
-- viewer(1) : lecture seule · moderator(2) : modération (CV, avis, support, bannir)
-- admin(3) : plans, paiements, réglages · superadmin(4) : gestion des admins, suppression
CREATE OR REPLACE FUNCTION public.admin_rank()
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((
    SELECT CASE WHEN NOT p.is_admin THEN 0
      ELSE CASE COALESCE(p.admin_role,'admin') WHEN 'viewer' THEN 1 WHEN 'moderator' THEN 2 WHEN 'admin' THEN 3 WHEN 'superadmin' THEN 4 ELSE 3 END
    END FROM public.profiles p WHERE p.id = auth.uid()), 0)
$$;

CREATE OR REPLACE FUNCTION public.admin_require(p_min INTEGER)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.admin_rank() < p_min THEN
    RAISE EXCEPTION 'FORBIDDEN : droits insuffisants' USING ERRCODE = '42501';
  END IF;
END $$;

-- ───────────── Utilitaires internes ─────────────
CREATE OR REPLACE FUNCTION public._safe_count(p_sql TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n BIGINT;
BEGIN EXECUTE p_sql INTO n; RETURN n;
EXCEPTION WHEN undefined_table OR undefined_column THEN RETURN NULL; END $$;

-- Série journalière : nombre de lignes (ou somme) par jour sur p_days jours
CREATE OR REPLACE FUNCTION public._series(p_table TEXT, p_ts TEXT, p_cond TEXT, p_agg TEXT, p_days INTEGER)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB; d0 DATE := CURRENT_DATE - (p_days - 1);
BEGIN
  EXECUTE format(
    'SELECT COALESCE(jsonb_agg(jsonb_build_object(''d'', g.d, ''v'', COALESCE(c.n,0)) ORDER BY g.d), ''[]''::jsonb)
       FROM (SELECT (generate_series($1::date, CURRENT_DATE, interval ''1 day''))::date AS d) g
       LEFT JOIN (SELECT (%1$s)::date AS d, %2$s AS n FROM public.%3$I WHERE (%1$s) >= $1 AND (%4$s) GROUP BY 1) c ON c.d = g.d',
    p_ts, p_agg, p_table, COALESCE(NULLIF(p_cond,''),'TRUE')) INTO v USING d0;
  RETURN v;
EXCEPTION WHEN undefined_table OR undefined_column THEN RETURN '[]'::jsonb;
END $$;

REVOKE ALL ON FUNCTION public._safe_count(TEXT), public._series(TEXT,TEXT,TEXT,TEXT,INTEGER) FROM PUBLIC, anon, authenticated;

-- Journal d'audit (interne)
CREATE OR REPLACE FUNCTION public._audit(p_action TEXT, p_type TEXT, p_id TEXT, p_old JSONB, p_new JSONB)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.audit_logs(admin_id, action, entity_type, entity_id, old_data, new_data)
  VALUES (auth.uid(), p_action, p_type, p_id, p_old, p_new);
$$;
REVOKE ALL ON FUNCTION public._audit(TEXT,TEXT,TEXT,JSONB,JSONB) FROM PUBLIC, anon, authenticated;

-- Journal d'audit pour les actions faites côté navigateur (modération, tickets…)
CREATE OR REPLACE FUNCTION public.admin_log(p_action TEXT, p_type TEXT, p_id TEXT, p_data JSONB DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN PERFORM public.admin_require(1); PERFORM public._audit(p_action, p_type, p_id, NULL, p_data); END $$;

-- ───────────── Lecture des journaux par les admins ─────────────
DROP POLICY IF EXISTS "audit_admin_read" ON public.audit_logs;
CREATE POLICY "audit_admin_read" ON public.audit_logs FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "export_admin_read" ON public.export_logs;
CREATE POLICY "export_admin_read" ON public.export_logs FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "ai_admin_read" ON public.ai_logs;
CREATE POLICY "ai_admin_read" ON public.ai_logs FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "stats_admin_read" ON public.platform_stats;
CREATE POLICY "stats_admin_read" ON public.platform_stats FOR SELECT USING (public.is_admin());

-- ───────────── Notes internes (jamais visibles des utilisateurs) ─────────────
CREATE TABLE IF NOT EXISTS public.admin_notes (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type TEXT        NOT NULL CHECK (entity_type IN ('user','ticket','cv','payment')),
  entity_id   TEXT        NOT NULL,
  admin_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  note        TEXT        NOT NULL CHECK (char_length(note) BETWEEN 1 AND 2000),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_notes_entity ON public.admin_notes(entity_type, entity_id, created_at DESC);
ALTER TABLE public.admin_notes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notes_admin_read" ON public.admin_notes;
CREATE POLICY "notes_admin_read" ON public.admin_notes FOR SELECT USING (public.admin_rank() >= 1);
DROP POLICY IF EXISTS "notes_admin_insert" ON public.admin_notes;
CREATE POLICY "notes_admin_insert" ON public.admin_notes FOR INSERT WITH CHECK (public.admin_rank() >= 2 AND admin_id = auth.uid());
DROP POLICY IF EXISTS "notes_admin_delete" ON public.admin_notes;
CREATE POLICY "notes_admin_delete" ON public.admin_notes FOR DELETE USING (public.admin_rank() >= 3 OR (public.admin_rank() >= 2 AND admin_id = auth.uid()));

-- ───────────── Réglages du site ─────────────
CREATE TABLE IF NOT EXISTS public.admin_settings (
  key        TEXT        PRIMARY KEY,
  value      JSONB       NOT NULL,
  updated_by UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.admin_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "settings_admin_read" ON public.admin_settings;
CREATE POLICY "settings_admin_read" ON public.admin_settings FOR SELECT USING (public.admin_rank() >= 1);
-- aucune policy d'écriture : tout passe par admin_set_setting()

INSERT INTO public.admin_settings(key, value) VALUES
  ('maintenance', '{"enabled":false,"message":"Maintenance en cours, merci de revenir dans quelques minutes."}'),
  ('banner',      '{"enabled":false,"text":"","type":"info"}')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_setting(p_key TEXT, p_value JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old JSONB;
BEGIN
  PERFORM public.admin_require(3);
  IF p_key NOT IN ('maintenance','banner') THEN RAISE EXCEPTION 'Réglage inconnu'; END IF;
  SELECT value INTO v_old FROM public.admin_settings WHERE key = p_key;
  INSERT INTO public.admin_settings(key, value, updated_by, updated_at) VALUES (p_key, p_value, auth.uid(), NOW())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_by = auth.uid(), updated_at = NOW();
  PERFORM public._audit('setting.update', 'setting', p_key, v_old, p_value);
END $$;

-- Lecture publique (visiteurs + app) : uniquement maintenance et bandeau
CREATE OR REPLACE FUNCTION public.get_public_settings()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb) FROM public.admin_settings WHERE key IN ('maintenance','banner')
$$;

-- ───────────── Tableau de bord ─────────────
CREATE OR REPLACE FUNCTION public.admin_dashboard(p_days INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  n  INTEGER := LEAST(GREATEST(COALESCE(p_days,30),7),365);
  d0 DATE := CURRENT_DATE - (LEAST(GREATEST(COALESCE(p_days,30),7),365) - 1);
  dp DATE := CURRENT_DATE - 2*(LEAST(GREATEST(COALESCE(p_days,30),7),365)) + 1;
  v  JSONB;
BEGIN
  PERFORM public.admin_require(1);
  SELECT jsonb_build_object(
    'days', n,
    'kpi', jsonb_build_object(
      'users_total',   (SELECT COUNT(*) FROM public.profiles),
      'users_new',     (SELECT COUNT(*) FROM public.profiles WHERE created_at::date >= d0),
      'users_prev',    (SELECT COUNT(*) FROM public.profiles WHERE created_at::date >= dp AND created_at::date < d0),
      'users_active24',(SELECT COUNT(*) FROM public.profiles WHERE last_seen_at > NOW() - INTERVAL '24 hours'),
      'users_active7', (SELECT COUNT(*) FROM public.profiles WHERE last_seen_at > NOW() - INTERVAL '7 days'),
      'paying',        (SELECT COUNT(*) FROM public.profiles WHERE plan <> 'free' AND (plan_expires_at IS NULL OR plan_expires_at > NOW())),
      'expiring7',     (SELECT COUNT(*) FROM public.profiles WHERE plan <> 'free' AND plan_expires_at BETWEEN NOW() AND NOW() + INTERVAL '7 days'),
      'banned',        (SELECT COUNT(*) FROM public.profiles WHERE is_banned),
      'cvs_total',     (SELECT COUNT(*) FROM public.cvs WHERE NOT is_deleted),
      'cvs_new',       (SELECT COUNT(*) FROM public.cvs WHERE created_at::date >= d0 AND NOT is_deleted),
      'cvs_prev',      (SELECT COUNT(*) FROM public.cvs WHERE created_at::date >= dp AND created_at::date < d0 AND NOT is_deleted),
      'cvs_public',    (SELECT COUNT(*) FROM public.cvs WHERE is_public AND NOT is_deleted),
      'views_total',   (SELECT COALESCE(SUM(view_count),0) FROM public.cvs),
      'revenue',       (SELECT COALESCE(SUM(amount),0) FROM public.payments WHERE status = 'success' AND COALESCE(paid_at,created_at)::date >= d0),
      'revenue_prev',  (SELECT COALESCE(SUM(amount),0) FROM public.payments WHERE status = 'success' AND COALESCE(paid_at,created_at)::date >= dp AND COALESCE(paid_at,created_at)::date < d0),
      'revenue_total', (SELECT COALESCE(SUM(amount),0) FROM public.payments WHERE status = 'success'),
      'payments_ok',   (SELECT COUNT(*) FROM public.payments WHERE status = 'success' AND COALESCE(paid_at,created_at)::date >= d0),
      'payments_pending',(SELECT COUNT(*) FROM public.payments WHERE status IN ('pending','processing') AND created_at < NOW() - INTERVAL '1 hour'),
      'payments_failed',(SELECT COUNT(*) FROM public.payments WHERE status = 'failed' AND created_at::date >= d0),
      'exports',       (SELECT COUNT(*) FROM public.export_logs WHERE created_at::date >= d0),
      'exports_prev',  (SELECT COUNT(*) FROM public.export_logs WHERE created_at::date >= dp AND created_at::date < d0),
      'ai',            (SELECT COUNT(*) FROM public.ai_logs WHERE created_at::date >= d0),
      'ai_err',        (SELECT COUNT(*) FROM public.ai_logs WHERE created_at::date >= d0 AND NOT success),
      'tickets_open',  (SELECT COUNT(*) FROM public.support_tickets WHERE status IN ('open','in_progress','waiting_user')),
      'tickets_urgent',(SELECT COUNT(*) FROM public.support_tickets WHERE status IN ('open','in_progress') AND priority IN ('high','urgent')),
      'tickets_unread',(SELECT COUNT(*) FROM public.support_messages WHERE NOT is_read AND sender_type = 'user'),
      'testimonials_pending', public._safe_count('SELECT COUNT(*) FROM public.testimonials WHERE status = ''pending'''),
      'feedback_pending',     public._safe_count('SELECT COUNT(*) FROM public.feedback WHERE status = ''pending'''),
      'guests',        public._safe_count('SELECT COUNT(*) FROM public.guest_profiles'),
      'guests_new',    public._safe_count('SELECT COUNT(*) FROM public.guest_profiles WHERE first_seen::date >= CURRENT_DATE - ' || (n-1)),
      'interest',      public._safe_count('SELECT COUNT(*) FROM public.feature_interest'),
      'documents',     public._safe_count('SELECT COUNT(*) FROM public.documents WHERE NOT is_deleted')
    ),
    'series', jsonb_build_object(
      'signups',  public._series('profiles','created_at','','COUNT(*)',n),
      'cvs',      public._series('cvs','created_at','NOT is_deleted','COUNT(*)',n),
      'revenue',  public._series('payments','COALESCE(paid_at,created_at)','status = ''success''','COALESCE(SUM(amount),0)',n),
      'exports',  public._series('export_logs','created_at','','COUNT(*)',n),
      'ai',       public._series('ai_logs','created_at','','COUNT(*)',n),
      'guests',   public._series('guest_profiles','first_seen','','COUNT(*)',n)
    ),
    'plans',     (SELECT COALESCE(jsonb_object_agg(plan, c), '{}'::jsonb) FROM (SELECT plan, COUNT(*) c FROM public.profiles GROUP BY plan) x),
    'templates', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', model_id, 'n', c) ORDER BY c DESC), '[]'::jsonb) FROM (SELECT model_id, COUNT(*) c FROM public.cvs WHERE NOT is_deleted GROUP BY model_id ORDER BY c DESC LIMIT 8) x),
    'countries', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', COALESCE(NULLIF(country,''),'—'), 'n', c) ORDER BY c DESC), '[]'::jsonb) FROM (SELECT country, COUNT(*) c FROM public.profiles GROUP BY country ORDER BY c DESC LIMIT 6) x),
    'recent_users', (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT id, email, name, plan, created_at FROM public.profiles ORDER BY created_at DESC LIMIT 6) x),
    'recent_payments', (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT p.id, p.transaction_id, p.plan, p.amount, p.currency, p.status, p.created_at, u.email FROM public.payments p LEFT JOIN public.profiles u ON u.id = p.user_id ORDER BY p.created_at DESC LIMIT 6) x),
    'recent_tickets', (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT t.id, t.ticket_no, t.subject, t.status, t.priority, t.created_at, u.email FROM public.support_tickets t LEFT JOIN public.profiles u ON u.id = t.user_id WHERE t.status IN ('open','in_progress') ORDER BY t.created_at DESC LIMIT 6) x)
  ) INTO v;
  RETURN v;
END $$;

-- ───────────── Utilisateurs ─────────────
CREATE OR REPLACE FUNCTION public.admin_list_users(
  p_q TEXT DEFAULT '', p_plan TEXT DEFAULT 'all', p_status TEXT DEFAULT 'all',
  p_sort TEXT DEFAULT 'created_at', p_dir TEXT DEFAULT 'desc', p_limit INTEGER DEFAULT 25, p_offset INTEGER DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_col TEXT; v_dir TEXT; v_total BIGINT; v_rows JSONB; v_lim INTEGER := LEAST(GREATEST(COALESCE(p_limit,25),1),200); v_off INTEGER := GREATEST(COALESCE(p_offset,0),0);
BEGIN
  PERFORM public.admin_require(1);
  v_col := CASE p_sort WHEN 'email' THEN 'email' WHEN 'name' THEN 'name' WHEN 'plan' THEN 'plan' WHEN 'last_seen_at' THEN 'last_seen_at'
                       WHEN 'ai_total_used' THEN 'ai_total_used' WHEN 'exports_total' THEN 'exports_total' WHEN 'cv_count' THEN 'cv_count'
                       WHEN 'paid_total' THEN 'paid_total' ELSE 'created_at' END;
  v_dir := CASE WHEN lower(COALESCE(p_dir,'desc')) = 'asc' THEN 'ASC' ELSE 'DESC' END;

  EXECUTE $q$
    WITH f AS (
      SELECT p.* FROM public.profiles p
      WHERE (COALESCE($1,'') = '' OR p.email ILIKE '%'||$1||'%' OR p.name ILIKE '%'||$1||'%' OR COALESCE(p.phone,'') ILIKE '%'||$1||'%' OR p.id::text = $1)
        AND (COALESCE($2,'all') IN ('all','') OR p.plan = $2)
        AND (CASE COALESCE($3,'all')
               WHEN 'banned'   THEN p.is_banned
               WHEN 'active'   THEN NOT p.is_banned
               WHEN 'admin'    THEN p.is_admin
               WHEN 'paying'   THEN p.plan <> 'free' AND (p.plan_expires_at IS NULL OR p.plan_expires_at > NOW())
               WHEN 'expiring' THEN p.plan <> 'free' AND p.plan_expires_at BETWEEN NOW() AND NOW() + INTERVAL '7 days'
               WHEN 'expired'  THEN p.plan <> 'free' AND p.plan_expires_at < NOW()
               WHEN 'inactive' THEN COALESCE(p.last_seen_at, p.created_at) < NOW() - INTERVAL '30 days'
               ELSE TRUE END)
    )
    SELECT (SELECT COUNT(*) FROM f),
           (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) FROM (
              SELECT u.* FROM (
                SELECT f.id, f.email, f.name, f.phone, f.country, f.city, f.plan, f.plan_expires_at, f.is_banned, f.ban_reason, f.is_admin, f.admin_role,
                       f.created_at, f.last_seen_at, f.ai_total_used, f.exports_total,
                       (SELECT COUNT(*) FROM public.cvs c WHERE c.user_id = f.id AND NOT c.is_deleted) AS cv_count,
                       (SELECT COALESCE(SUM(amount),0) FROM public.payments y WHERE y.user_id = f.id AND y.status = 'success') AS paid_total
                FROM f) u
              ORDER BY u.$q$ || quote_ident(v_col) || ' ' || v_dir || $q$ NULLS LAST, u.created_at DESC
              LIMIT $4 OFFSET $5) r)
  $q$ INTO v_total, v_rows USING p_q, p_plan, p_status, v_lim, v_off;
  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END $$;

CREATE OR REPLACE FUNCTION public.admin_user_detail(p_user UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  SELECT jsonb_build_object(
    'profile', to_jsonb(p),
    'cvs', (SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.updated_at DESC), '[]'::jsonb)
              FROM (SELECT id, title, model_id, ats_score, is_public, share_token, view_count, download_count, is_deleted, created_at, updated_at FROM public.cvs WHERE user_id = p_user ORDER BY updated_at DESC LIMIT 50) c),
    'payments', (SELECT COALESCE(jsonb_agg(to_jsonb(y) ORDER BY y.created_at DESC), '[]'::jsonb)
              FROM (SELECT id, transaction_id, plan, amount, currency, status, provider, paid_at, created_at FROM public.payments WHERE user_id = p_user ORDER BY created_at DESC LIMIT 30) y),
    'tickets', (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC), '[]'::jsonb)
              FROM (SELECT id, ticket_no, subject, status, priority, created_at FROM public.support_tickets WHERE user_id = p_user ORDER BY created_at DESC LIMIT 30) t),
    'ai', (SELECT jsonb_build_object('total', COUNT(*), 'errors', COUNT(*) FILTER (WHERE NOT success), 'tokens', COALESCE(SUM(total_tokens),0), 'last', MAX(created_at)) FROM public.ai_logs WHERE user_id = p_user),
    'exports', (SELECT jsonb_build_object('total', COUNT(*), 'last', MAX(created_at)) FROM public.export_logs WHERE user_id = p_user),
    'documents', public._safe_count('SELECT COUNT(*) FROM public.documents WHERE NOT is_deleted AND user_id = ''' || p_user::text || ''''),
    'audit', (SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.created_at DESC), '[]'::jsonb)
              FROM (SELECT l.id, l.action, l.old_data, l.new_data, l.created_at, ad.email AS admin_email FROM public.audit_logs l LEFT JOIN public.profiles ad ON ad.id = l.admin_id
                    WHERE l.entity_type = 'user' AND l.entity_id = p_user::text ORDER BY l.created_at DESC LIMIT 30) a)
  ) INTO v FROM public.profiles p WHERE p.id = p_user;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_plan(p_user UUID, p_plan TEXT, p_days INTEGER DEFAULT 30, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old public.profiles%ROWTYPE; v_exp TIMESTAMPTZ;
BEGIN
  PERFORM public.admin_require(3);
  IF p_plan NOT IN ('free','starter','premium','pro') THEN RAISE EXCEPTION 'Plan invalide'; END IF;
  SELECT * INTO v_old FROM public.profiles WHERE id = p_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  v_exp := CASE WHEN p_plan = 'free' THEN NULL ELSE NOW() + make_interval(days => LEAST(GREATEST(COALESCE(p_days,30),1),3650)) END;
  UPDATE public.profiles SET plan = p_plan, plan_activated_at = CASE WHEN p_plan = 'free' THEN NULL ELSE NOW() END, plan_expires_at = v_exp WHERE id = p_user;
  PERFORM public._audit('user.plan', 'user', p_user::text,
    jsonb_build_object('plan', v_old.plan, 'expires', v_old.plan_expires_at),
    jsonb_build_object('plan', p_plan, 'expires', v_exp, 'days', p_days, 'reason', p_reason));
  RETURN jsonb_build_object('ok', TRUE, 'plan', p_plan, 'expires', v_exp);
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_ban(p_user UUID, p_banned BOOLEAN, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_t public.profiles%ROWTYPE;
BEGIN
  PERFORM public.admin_require(2);
  IF p_user = auth.uid() THEN RAISE EXCEPTION 'Vous ne pouvez pas vous bannir vous-même'; END IF;
  SELECT * INTO v_t FROM public.profiles WHERE id = p_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF v_t.is_admin AND public.admin_rank() < 4 THEN RAISE EXCEPTION 'Seul un superadmin peut modifier un administrateur'; END IF;
  UPDATE public.profiles SET is_banned = p_banned, ban_reason = CASE WHEN p_banned THEN p_reason END,
         banned_at = CASE WHEN p_banned THEN NOW() END, banned_by = CASE WHEN p_banned THEN auth.uid() END WHERE id = p_user;
  PERFORM public._audit(CASE WHEN p_banned THEN 'user.ban' ELSE 'user.unban' END, 'user', p_user::text, jsonb_build_object('banned', v_t.is_banned), jsonb_build_object('banned', p_banned, 'reason', p_reason));
  RETURN jsonb_build_object('ok', TRUE);
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_admin(p_user UUID, p_is_admin BOOLEAN, p_role TEXT DEFAULT 'moderator')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_t public.profiles%ROWTYPE; v_supers INTEGER;
BEGIN
  PERFORM public.admin_require(4);
  IF p_user = auth.uid() THEN RAISE EXCEPTION 'Vous ne pouvez pas modifier votre propre rôle'; END IF;
  IF p_is_admin AND p_role NOT IN ('viewer','moderator','admin','superadmin') THEN RAISE EXCEPTION 'Rôle invalide'; END IF;
  SELECT * INTO v_t FROM public.profiles WHERE id = p_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF v_t.is_admin AND v_t.admin_role = 'superadmin' AND (NOT p_is_admin OR p_role <> 'superadmin') THEN
    SELECT COUNT(*) INTO v_supers FROM public.profiles WHERE is_admin AND admin_role = 'superadmin';
    IF v_supers <= 1 THEN RAISE EXCEPTION 'Impossible : il doit rester au moins un superadmin'; END IF;
  END IF;
  UPDATE public.profiles SET is_admin = p_is_admin, admin_role = CASE WHEN p_is_admin THEN p_role END WHERE id = p_user;
  PERFORM public._audit('user.role', 'user', p_user::text, jsonb_build_object('is_admin', v_t.is_admin, 'role', v_t.admin_role), jsonb_build_object('is_admin', p_is_admin, 'role', CASE WHEN p_is_admin THEN p_role END));
  RETURN jsonb_build_object('ok', TRUE);
END $$;

CREATE OR REPLACE FUNCTION public.admin_reset_quota(p_user UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_require(3);
  UPDATE public.profiles SET ai_used_today = 0, ai_last_reset = CURRENT_DATE, exports_used = 0 WHERE id = p_user;
  PERFORM public._audit('user.reset_quota', 'user', p_user::text, NULL, NULL);
  RETURN jsonb_build_object('ok', TRUE);
END $$;

CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_t public.profiles%ROWTYPE;
BEGIN
  PERFORM public.admin_require(4);
  IF p_user = auth.uid() THEN RAISE EXCEPTION 'Vous ne pouvez pas supprimer votre propre compte ici'; END IF;
  SELECT * INTO v_t FROM public.profiles WHERE id = p_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;
  IF v_t.is_admin THEN RAISE EXCEPTION 'Retirez d''abord le rôle administrateur'; END IF;
  PERFORM public._audit('user.delete', 'user', p_user::text, jsonb_build_object('email', v_t.email, 'plan', v_t.plan), NULL);
  DELETE FROM auth.users WHERE id = p_user;       -- cascade vers profiles, cvs, documents…
  RETURN jsonb_build_object('ok', TRUE);
END $$;

-- ───────────── CV ─────────────
CREATE OR REPLACE FUNCTION public.admin_list_cvs(p_q TEXT DEFAULT '', p_vis TEXT DEFAULT 'all', p_limit INTEGER DEFAULT 25, p_offset INTEGER DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total BIGINT; v_rows JSONB; v_lim INTEGER := LEAST(GREATEST(COALESCE(p_limit,25),1),200); v_off INTEGER := GREATEST(COALESCE(p_offset,0),0);
BEGIN
  PERFORM public.admin_require(1);
  WITH f AS (
    SELECT c.id, c.title, c.model_id, c.ats_score, c.is_public, c.share_token, c.view_count, c.download_count, c.is_deleted, c.created_at, c.updated_at, c.user_id, u.email AS owner_email, u.name AS owner_name
    FROM public.cvs c LEFT JOIN public.profiles u ON u.id = c.user_id
    WHERE (COALESCE(p_q,'') = '' OR c.title ILIKE '%'||p_q||'%' OR u.email ILIKE '%'||p_q||'%' OR u.name ILIKE '%'||p_q||'%' OR c.id::text = p_q)
      AND (CASE COALESCE(p_vis,'all') WHEN 'public' THEN c.is_public AND NOT c.is_deleted WHEN 'private' THEN NOT c.is_public AND NOT c.is_deleted
                                      WHEN 'deleted' THEN c.is_deleted WHEN 'all' THEN NOT c.is_deleted ELSE TRUE END)
  )
  SELECT (SELECT COUNT(*) FROM f),
         (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) FROM (SELECT * FROM f ORDER BY updated_at DESC LIMIT v_lim OFFSET v_off) r)
  INTO v_total, v_rows;
  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END $$;

CREATE OR REPLACE FUNCTION public.admin_get_cv(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  SELECT to_jsonb(c) || jsonb_build_object('owner_email', u.email, 'owner_name', u.name) INTO v
  FROM public.cvs c LEFT JOIN public.profiles u ON u.id = c.user_id WHERE c.id = p_id;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.admin_cv_action(p_id UUID, p_action TEXT, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_require(2);
  IF p_action = 'unpublish' THEN UPDATE public.cvs SET is_public = FALSE WHERE id = p_id;
  ELSIF p_action = 'delete'  THEN UPDATE public.cvs SET is_deleted = TRUE, deleted_at = NOW(), is_public = FALSE WHERE id = p_id;
  ELSIF p_action = 'restore' THEN UPDATE public.cvs SET is_deleted = FALSE, deleted_at = NULL WHERE id = p_id;
  ELSE RAISE EXCEPTION 'Action inconnue'; END IF;
  PERFORM public._audit('cv.' || p_action, 'cv', p_id::text, NULL, jsonb_build_object('reason', p_reason));
  RETURN jsonb_build_object('ok', TRUE);
END $$;

-- ───────────── Paiements ─────────────
CREATE OR REPLACE FUNCTION public.admin_list_payments(p_q TEXT DEFAULT '', p_status TEXT DEFAULT 'all', p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL, p_limit INTEGER DEFAULT 25, p_offset INTEGER DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total BIGINT; v_sum BIGINT; v_rows JSONB; v_lim INTEGER := LEAST(GREATEST(COALESCE(p_limit,25),1),500); v_off INTEGER := GREATEST(COALESCE(p_offset,0),0);
BEGIN
  PERFORM public.admin_require(1);
  WITH f AS (
    SELECT y.id, y.transaction_id, y.plan, y.amount, y.currency, y.status, y.provider, y.payment_method, y.phone, y.country, y.paid_at, y.created_at, y.user_id, u.email AS user_email, u.name AS user_name
    FROM public.payments y LEFT JOIN public.profiles u ON u.id = y.user_id
    WHERE (COALESCE(p_q,'') = '' OR y.transaction_id ILIKE '%'||p_q||'%' OR u.email ILIKE '%'||p_q||'%' OR COALESCE(y.phone,'') ILIKE '%'||p_q||'%')
      AND (COALESCE(p_status,'all') IN ('all','') OR y.status = p_status)
      AND (p_from IS NULL OR y.created_at::date >= p_from) AND (p_to IS NULL OR y.created_at::date <= p_to)
  )
  SELECT (SELECT COUNT(*) FROM f), (SELECT COALESCE(SUM(amount),0) FROM f WHERE status = 'success'),
         (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) FROM (SELECT * FROM f ORDER BY created_at DESC LIMIT v_lim OFFSET v_off) r)
  INTO v_total, v_sum, v_rows;
  RETURN jsonb_build_object('total', v_total, 'sum_success', v_sum, 'rows', v_rows);
END $$;

CREATE OR REPLACE FUNCTION public.admin_payment_action(p_id UUID, p_action TEXT, p_days INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p public.payments%ROWTYPE;
BEGIN
  PERFORM public.admin_require(3);
  SELECT * INTO v_p FROM public.payments WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Paiement introuvable'; END IF;
  IF p_action = 'mark_success' THEN
    UPDATE public.payments SET status = 'success', paid_at = COALESCE(paid_at, NOW()) WHERE id = p_id;
    IF v_p.user_id IS NOT NULL THEN
      UPDATE public.profiles SET plan = v_p.plan, plan_activated_at = NOW(), plan_expires_at = NOW() + make_interval(days => LEAST(GREATEST(COALESCE(p_days,30),1),3650)), plan_tx_id = v_p.transaction_id WHERE id = v_p.user_id;
    END IF;
  ELSIF p_action = 'refund' THEN
    UPDATE public.payments SET status = 'refunded', refunded_at = NOW() WHERE id = p_id;
    IF v_p.user_id IS NOT NULL THEN
      UPDATE public.profiles SET plan = 'free', plan_expires_at = NULL WHERE id = v_p.user_id AND plan_tx_id = v_p.transaction_id;
    END IF;
  ELSIF p_action = 'mark_failed' THEN
    UPDATE public.payments SET status = 'failed' WHERE id = p_id;
  ELSE RAISE EXCEPTION 'Action inconnue'; END IF;
  PERFORM public._audit('payment.' || p_action, 'payment', p_id::text, jsonb_build_object('status', v_p.status), jsonb_build_object('tx', v_p.transaction_id, 'days', p_days));
  RETURN jsonb_build_object('ok', TRUE);
END $$;

-- ───────────── Support ─────────────
CREATE OR REPLACE FUNCTION public.admin_list_tickets(p_status TEXT DEFAULT 'active', p_priority TEXT DEFAULT 'all', p_q TEXT DEFAULT '', p_limit INTEGER DEFAULT 25, p_offset INTEGER DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total BIGINT; v_rows JSONB; v_lim INTEGER := LEAST(GREATEST(COALESCE(p_limit,25),1),200); v_off INTEGER := GREATEST(COALESCE(p_offset,0),0);
BEGIN
  PERFORM public.admin_require(1);
  WITH f AS (
    SELECT t.id, t.ticket_no, t.subject, t.status, t.priority, t.category, t.created_at, t.updated_at, t.assigned_to, t.user_plan, u.email AS user_email, u.name AS user_name,
           (SELECT COUNT(*) FROM public.support_messages m WHERE m.ticket_id = t.id) AS msg_count,
           (SELECT COUNT(*) FROM public.support_messages m WHERE m.ticket_id = t.id AND NOT m.is_read AND m.sender_type = 'user') AS unread
    FROM public.support_tickets t LEFT JOIN public.profiles u ON u.id = t.user_id
    WHERE (CASE COALESCE(p_status,'active') WHEN 'active' THEN t.status IN ('open','in_progress','waiting_user') WHEN 'all' THEN TRUE ELSE t.status = p_status END)
      AND (COALESCE(p_priority,'all') IN ('all','') OR t.priority = p_priority)
      AND (COALESCE(p_q,'') = '' OR t.subject ILIKE '%'||p_q||'%' OR t.ticket_no ILIKE '%'||p_q||'%' OR u.email ILIKE '%'||p_q||'%')
  )
  SELECT (SELECT COUNT(*) FROM f),
         (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) FROM (SELECT * FROM f ORDER BY (priority = 'urgent') DESC, (priority = 'high') DESC, updated_at DESC LIMIT v_lim OFFSET v_off) r)
  INTO v_total, v_rows;
  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ticket_thread(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  SELECT jsonb_build_object(
    'ticket', to_jsonb(t) || jsonb_build_object('user_email', u.email, 'user_name', u.name, 'user_id', t.user_id),
    'messages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', m.id, 'sender_type', m.sender_type, 'content', m.content, 'created_at', m.created_at, 'sender_email', s.email) ORDER BY m.created_at), '[]'::jsonb)
                 FROM public.support_messages m LEFT JOIN public.profiles s ON s.id = m.sender_id WHERE m.ticket_id = t.id),
    'notes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', n.id, 'note', n.note, 'created_at', n.created_at, 'admin_email', a.email) ORDER BY n.created_at), '[]'::jsonb)
              FROM public.admin_notes n LEFT JOIN public.profiles a ON a.id = n.admin_id WHERE n.entity_type = 'ticket' AND n.entity_id = t.id::text)
  ) INTO v FROM public.support_tickets t LEFT JOIN public.profiles u ON u.id = t.user_id WHERE t.id = p_id;
  UPDATE public.support_messages SET is_read = TRUE, read_at = NOW() WHERE ticket_id = p_id AND sender_type = 'user' AND NOT is_read AND public.admin_rank() >= 1;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.admin_ticket_update(p_id UUID, p_status TEXT DEFAULT NULL, p_priority TEXT DEFAULT NULL, p_assign_me BOOLEAN DEFAULT FALSE, p_resolution TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_require(2);
  IF p_status IS NOT NULL AND p_status NOT IN ('open','in_progress','waiting_user','resolved','closed') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  IF p_priority IS NOT NULL AND p_priority NOT IN ('low','normal','high','urgent') THEN RAISE EXCEPTION 'Priorité invalide'; END IF;
  UPDATE public.support_tickets SET
    status = COALESCE(p_status, status), priority = COALESCE(p_priority, priority),
    assigned_to = CASE WHEN p_assign_me THEN auth.uid() ELSE assigned_to END, assigned_at = CASE WHEN p_assign_me THEN NOW() ELSE assigned_at END,
    resolved_at = CASE WHEN p_status IN ('resolved','closed') THEN NOW() WHEN p_status IS NOT NULL THEN NULL ELSE resolved_at END,
    resolved_by = CASE WHEN p_status IN ('resolved','closed') THEN auth.uid() ELSE resolved_by END,
    resolution = COALESCE(p_resolution, resolution)
  WHERE id = p_id;
  PERFORM public._audit('ticket.update', 'ticket', p_id::text, NULL, jsonb_build_object('status', p_status, 'priority', p_priority, 'assign_me', p_assign_me));
  RETURN jsonb_build_object('ok', TRUE);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ticket_reply(p_id UUID, p_content TEXT, p_status TEXT DEFAULT 'waiting_user')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_require(2);
  IF COALESCE(btrim(p_content),'') = '' THEN RAISE EXCEPTION 'Message vide'; END IF;
  INSERT INTO public.support_messages(ticket_id, sender_id, sender_type, content) VALUES (p_id, auth.uid(), 'admin', left(p_content, 5000));
  UPDATE public.support_tickets SET status = COALESCE(p_status, status), assigned_to = COALESCE(assigned_to, auth.uid()) WHERE id = p_id;
  PERFORM public._audit('ticket.reply', 'ticket', p_id::text, NULL, jsonb_build_object('status', p_status));
  RETURN jsonb_build_object('ok', TRUE);
END $$;

-- ───────────── IA & exports ─────────────
CREATE OR REPLACE FUNCTION public.admin_ai_stats(p_days INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER := LEAST(GREATEST(COALESCE(p_days,30),1),365); v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  SELECT jsonb_build_object(
    'total', (SELECT COUNT(*) FROM public.ai_logs WHERE created_at >= NOW() - make_interval(days => n)),
    'errors',(SELECT COUNT(*) FROM public.ai_logs WHERE created_at >= NOW() - make_interval(days => n) AND NOT success),
    'tokens',(SELECT COALESCE(SUM(total_tokens),0) FROM public.ai_logs WHERE created_at >= NOW() - make_interval(days => n)),
    'avg_ms',(SELECT COALESCE(ROUND(AVG(duration_ms)),0) FROM public.ai_logs WHERE created_at >= NOW() - make_interval(days => n) AND duration_ms IS NOT NULL),
    'series', public._series('ai_logs','created_at','','COUNT(*)',n),
    'by_action',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id', action, 'n', c, 'err', e) ORDER BY c DESC), '[]'::jsonb) FROM (SELECT action, COUNT(*) c, COUNT(*) FILTER (WHERE NOT success) e FROM public.ai_logs WHERE created_at >= NOW() - make_interval(days => n) GROUP BY action ORDER BY c DESC LIMIT 10) x),
    'by_provider',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id', provider || '/' || COALESCE(model,'—'), 'n', c) ORDER BY c DESC), '[]'::jsonb) FROM (SELECT provider, model, COUNT(*) c FROM public.ai_logs WHERE created_at >= NOW() - make_interval(days => n) GROUP BY provider, model ORDER BY c DESC LIMIT 8) x),
    'top_users',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id', user_id, 'email', email, 'n', c) ORDER BY c DESC), '[]'::jsonb) FROM (SELECT l.user_id, u.email, COUNT(*) c FROM public.ai_logs l LEFT JOIN public.profiles u ON u.id = l.user_id WHERE l.created_at >= NOW() - make_interval(days => n) GROUP BY l.user_id, u.email ORDER BY c DESC LIMIT 8) x),
    'last_errors',(SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT action, provider, error_code, error_message, created_at FROM public.ai_logs WHERE NOT success ORDER BY created_at DESC LIMIT 8) x)
  ) INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.admin_export_stats(p_days INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER := LEAST(GREATEST(COALESCE(p_days,30),1),365); v JSONB;
BEGIN
  PERFORM public.admin_require(1);
  SELECT jsonb_build_object(
    'total',(SELECT COUNT(*) FROM public.export_logs WHERE created_at >= NOW() - make_interval(days => n)),
    'failed',(SELECT COUNT(*) FROM public.export_logs WHERE created_at >= NOW() - make_interval(days => n) AND NOT success),
    'series', public._series('export_logs','created_at','','COUNT(*)',n),
    'by_format',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id', format, 'n', c) ORDER BY c DESC), '[]'::jsonb) FROM (SELECT format, COUNT(*) c FROM public.export_logs WHERE created_at >= NOW() - make_interval(days => n) GROUP BY format) x),
    'recent',(SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT l.format, l.success, l.created_at, u.email FROM public.export_logs l LEFT JOIN public.profiles u ON u.id = l.user_id ORDER BY l.created_at DESC LIMIT 30) x)
  ) INTO v;
  RETURN v;
END $$;

-- ───────────── Audit, recherche globale, santé ─────────────
CREATE OR REPLACE FUNCTION public.admin_list_audit(p_q TEXT DEFAULT '', p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total BIGINT; v_rows JSONB; v_lim INTEGER := LEAST(GREATEST(COALESCE(p_limit,50),1),200); v_off INTEGER := GREATEST(COALESCE(p_offset,0),0);
BEGIN
  PERFORM public.admin_require(1);
  WITH f AS (
    SELECT l.id, l.action, l.entity_type, l.entity_id, l.old_data, l.new_data, l.created_at, a.email AS admin_email,
           CASE WHEN l.entity_type = 'user' THEN (SELECT email FROM public.profiles WHERE id::text = l.entity_id) END AS target_email
    FROM public.audit_logs l LEFT JOIN public.profiles a ON a.id = l.admin_id
    WHERE COALESCE(p_q,'') = '' OR l.action ILIKE '%'||p_q||'%' OR l.entity_type ILIKE '%'||p_q||'%' OR COALESCE(l.entity_id,'') ILIKE '%'||p_q||'%' OR a.email ILIKE '%'||p_q||'%'
  )
  SELECT (SELECT COUNT(*) FROM f), (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) FROM (SELECT * FROM f ORDER BY created_at DESC LIMIT v_lim OFFSET v_off) r)
  INTO v_total, v_rows;
  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END $$;

CREATE OR REPLACE FUNCTION public.admin_search(p_q TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB; q TEXT := btrim(COALESCE(p_q,''));
BEGIN
  PERFORM public.admin_require(1);
  IF char_length(q) < 2 THEN RETURN '{"users":[],"cvs":[],"payments":[],"tickets":[]}'::jsonb; END IF;
  SELECT jsonb_build_object(
    'users',   (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT id, email, name, plan FROM public.profiles WHERE email ILIKE '%'||q||'%' OR name ILIKE '%'||q||'%' OR COALESCE(phone,'') ILIKE '%'||q||'%' OR id::text = q ORDER BY created_at DESC LIMIT 6) x),
    'cvs',     (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT c.id, c.title, u.email AS owner_email FROM public.cvs c LEFT JOIN public.profiles u ON u.id = c.user_id WHERE NOT c.is_deleted AND (c.title ILIKE '%'||q||'%' OR c.share_token = q OR c.id::text = q) ORDER BY c.updated_at DESC LIMIT 6) x),
    'payments',(SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT id, transaction_id, plan, amount, status FROM public.payments WHERE transaction_id ILIKE '%'||q||'%' OR COALESCE(phone,'') ILIKE '%'||q||'%' ORDER BY created_at DESC LIMIT 6) x),
    'tickets', (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (SELECT id, ticket_no, subject, status FROM public.support_tickets WHERE subject ILIKE '%'||q||'%' OR ticket_no ILIKE '%'||q||'%' ORDER BY created_at DESC LIMIT 6) x)
  ) INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.admin_system_health()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB; t TEXT; tables JSONB := '{}'::jsonb;
BEGIN
  PERFORM public.admin_require(1);
  FOREACH t IN ARRAY ARRAY['profiles','cvs','payments','license_keys','ai_logs','export_logs','support_tickets','support_messages','admin_broadcasts','audit_logs','feedback','testimonials','feature_interest','guest_profiles','guest_cvs','documents','admin_notes','admin_settings'] LOOP
    tables := tables || jsonb_build_object(t, CASE WHEN to_regclass('public.' || t) IS NULL THEN NULL ELSE public._safe_count('SELECT COUNT(*) FROM public.' || quote_ident(t)) END);
  END LOOP;
  SELECT jsonb_build_object(
    'db_size', pg_database_size(current_database()),
    'tables', tables,
    'stale_payments', (SELECT COUNT(*) FROM public.payments WHERE status IN ('pending','processing') AND created_at < NOW() - INTERVAL '1 hour'),
    'ai_fail_24h', (SELECT COUNT(*) FROM public.ai_logs WHERE NOT success AND created_at > NOW() - INTERVAL '24 hours'),
    'ai_total_24h', (SELECT COUNT(*) FROM public.ai_logs WHERE created_at > NOW() - INTERVAL '24 hours'),
    'last_signup', (SELECT MAX(created_at) FROM public.profiles),
    'last_payment', (SELECT MAX(COALESCE(paid_at, created_at)) FROM public.payments WHERE status = 'success'),
    'oldest_open_ticket', (SELECT MIN(created_at) FROM public.support_tickets WHERE status IN ('open','in_progress')),
    'expired_still_paid', (SELECT COUNT(*) FROM public.profiles WHERE plan <> 'free' AND plan_expires_at < NOW()),
    'server_time', NOW()
  ) INTO v;
  RETURN v;
END $$;

-- Rétrograde les plans expirés (à appeler depuis l'admin ou un cron)
CREATE OR REPLACE FUNCTION public.admin_expire_plans()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER;
BEGIN
  PERFORM public.admin_require(3);
  UPDATE public.profiles SET plan = 'free' WHERE plan <> 'free' AND plan_expires_at IS NOT NULL AND plan_expires_at < NOW();
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM public._audit('plans.expire', 'system', NULL, NULL, jsonb_build_object('count', n));
  RETURN jsonb_build_object('ok', TRUE, 'count', n);
END $$;

-- ───────────── Droits d'exécution ─────────────
DO $$
DECLARE f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'admin_rank()','admin_require(integer)','admin_log(text,text,text,jsonb)','admin_set_setting(text,jsonb)','admin_dashboard(integer)',
    'admin_list_users(text,text,text,text,text,integer,integer)','admin_user_detail(uuid)','admin_set_plan(uuid,text,integer,text)',
    'admin_set_ban(uuid,boolean,text)','admin_set_admin(uuid,boolean,text)','admin_reset_quota(uuid)','admin_delete_user(uuid)',
    'admin_list_cvs(text,text,integer,integer)','admin_get_cv(uuid)','admin_cv_action(uuid,text,text)',
    'admin_list_payments(text,text,date,date,integer,integer)','admin_payment_action(uuid,text,integer)',
    'admin_list_tickets(text,text,text,integer,integer)','admin_ticket_thread(uuid)','admin_ticket_update(uuid,text,text,boolean,text)','admin_ticket_reply(uuid,text,text)',
    'admin_ai_stats(integer)','admin_export_stats(integer)','admin_list_audit(text,integer,integer)','admin_search(text)','admin_system_health()','admin_expire_plans()'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated, service_role', f);
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.get_public_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_settings() TO anon, authenticated, service_role;
