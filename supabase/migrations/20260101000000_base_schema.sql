-- ════════════════════════════════════════
-- SmartCV — PARTIE 2: CRÉATION COMPLÈTE
-- Exécuter APRÈS que STEP1_DROP soit "Success"
-- ════════════════════════════════════════

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ════════════════════════════════════════
-- 1. PROFILES
-- ════════════════════════════════════════
CREATE TABLE public.profiles (
  id                UUID         PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email             TEXT         NOT NULL DEFAULT '',
  name              TEXT         NOT NULL DEFAULT '',
  avatar_url        TEXT,
  phone             TEXT,
  country           TEXT         DEFAULT 'CI',
  city              TEXT,
  language          TEXT         NOT NULL DEFAULT 'fr',
  timezone          TEXT         NOT NULL DEFAULT 'Africa/Abidjan',
  plan              TEXT         NOT NULL DEFAULT 'free'
                    CHECK (plan IN ('free','starter','premium','pro')),
  plan_activated_at TIMESTAMPTZ,
  plan_expires_at   TIMESTAMPTZ,
  plan_tx_id        TEXT,
  ai_used_today     INTEGER      NOT NULL DEFAULT 0,
  ai_last_reset     DATE,
  ai_total_used     INTEGER      NOT NULL DEFAULT 0,
  exports_used      INTEGER      NOT NULL DEFAULT 0,
  exports_total     INTEGER      NOT NULL DEFAULT 0,
  is_active         BOOLEAN      NOT NULL DEFAULT TRUE,
  is_banned         BOOLEAN      NOT NULL DEFAULT FALSE,
  ban_reason        TEXT,
  banned_at         TIMESTAMPTZ,
  banned_by         UUID,
  is_admin          BOOLEAN      NOT NULL DEFAULT FALSE,
  admin_role        TEXT         CHECK (admin_role IN ('viewer','moderator','admin','superadmin')),
  last_seen_at      TIMESTAMPTZ,
  last_ip           TEXT,
  signup_source     TEXT,
  referral_code     TEXT,
  referred_by       UUID         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 2. CVS
-- ════════════════════════════════════════
CREATE TABLE public.cvs (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title            TEXT        NOT NULL DEFAULT 'Mon CV',
  model_id         TEXT        NOT NULL DEFAULT 't01',
  accent_color     TEXT        NOT NULL DEFAULT '#2563EB',
  language         TEXT        NOT NULL DEFAULT 'fr',
  data             JSONB       NOT NULL DEFAULT '{"p":{},"exp":[],"edu":[],"sk":[],"lang":[],"cert":[],"hobby":[],"ref":[],"award":[],"ec":{}}',
  design           JSONB       NOT NULL DEFAULT '{"font":"inter","fontSize":"md","spacing":"normal","showPhoto":true,"showSummary":true}',
  ats_score        INTEGER     CHECK (ats_score BETWEEN 0 AND 100),
  ats_details      JSONB,
  view_count       INTEGER     NOT NULL DEFAULT 0,
  download_count   INTEGER     NOT NULL DEFAULT 0,
  share_token      TEXT        UNIQUE,
  is_public        BOOLEAN     NOT NULL DEFAULT FALSE,
  shared_at        TIMESTAMPTZ,
  is_draft         BOOLEAN     NOT NULL DEFAULT TRUE,
  is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
  deleted_at       TIMESTAMPTZ,
  version          INTEGER     NOT NULL DEFAULT 1,
  last_exported_at TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 3. CV_VERSIONS
-- ════════════════════════════════════════
CREATE TABLE public.cv_versions (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  cv_id      UUID        NOT NULL REFERENCES public.cvs(id) ON DELETE CASCADE,
  user_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  version    INTEGER     NOT NULL,
  data       JSONB       NOT NULL,
  design     JSONB       NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 4. PAYMENTS
-- ════════════════════════════════════════
CREATE TABLE public.payments (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  transaction_id  TEXT        NOT NULL UNIQUE,
  plan            TEXT        NOT NULL CHECK (plan IN ('starter','premium','pro')),
  amount          INTEGER     NOT NULL,
  currency        TEXT        NOT NULL DEFAULT 'XOF',
  status          TEXT        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','processing','success','failed','refunded','disputed')),
  payment_method  TEXT,
  provider        TEXT        NOT NULL DEFAULT 'cinetpay',
  provider_ref    TEXT,
  country         TEXT,
  phone           TEXT,
  initiated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  paid_at         TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  refunded_at     TIMESTAMPTZ,
  ip_address      TEXT,
  user_agent      TEXT,
  metadata        JSONB       NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 5. LICENSE_KEYS
-- ════════════════════════════════════════
CREATE TABLE public.license_keys (
  key            TEXT        PRIMARY KEY,
  plan           TEXT        NOT NULL CHECK (plan IN ('starter','premium','pro')),
  duration_days  INTEGER     NOT NULL DEFAULT 30,
  price_fcfa     INTEGER     NOT NULL DEFAULT 0,
  status         TEXT        NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active','used','revoked','expired')),
  max_uses       INTEGER     NOT NULL DEFAULT 1,
  uses_count     INTEGER     NOT NULL DEFAULT 0,
  used_by        UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  used_at        TIMESTAMPTZ,
  expires_at     TIMESTAMPTZ,
  created_by     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  note           TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 6. AI_LOGS
-- ════════════════════════════════════════
CREATE TABLE public.ai_logs (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  session_id      TEXT,
  action          TEXT        NOT NULL,
  provider        TEXT        NOT NULL DEFAULT 'groq',
  model           TEXT,
  prompt_tokens   INTEGER     DEFAULT 0,
  response_tokens INTEGER     DEFAULT 0,
  total_tokens    INTEGER     DEFAULT 0,
  duration_ms     INTEGER,
  success         BOOLEAN     NOT NULL DEFAULT TRUE,
  error_code      TEXT,
  error_message   TEXT,
  cv_id           UUID        REFERENCES public.cvs(id) ON DELETE SET NULL,
  user_plan       TEXT,
  ip_address      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 7. EXPORT_LOGS
-- ════════════════════════════════════════
CREATE TABLE public.export_logs (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  cv_id       UUID        REFERENCES public.cvs(id) ON DELETE SET NULL,
  format      TEXT        NOT NULL CHECK (format IN ('pdf','word','json','image','print')),
  success     BOOLEAN     NOT NULL DEFAULT TRUE,
  file_size   INTEGER,
  duration_ms INTEGER,
  ip_address  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 8. SUPPORT_TICKETS
-- ════════════════════════════════════════
CREATE TABLE public.support_tickets (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  ticket_no    TEXT        NOT NULL UNIQUE DEFAULT 'TKT-PENDING',
  category     TEXT        NOT NULL DEFAULT 'general'
               CHECK (category IN ('bug','feature_request','payment','account',
                                   'cv_help','ai_issue','feedback','other','general')),
  priority     TEXT        NOT NULL DEFAULT 'normal'
               CHECK (priority IN ('low','normal','high','urgent')),
  subject      TEXT        NOT NULL,
  status       TEXT        NOT NULL DEFAULT 'open'
               CHECK (status IN ('open','in_progress','waiting_user','resolved','closed')),
  assigned_to  UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_at  TIMESTAMPTZ,
  resolved_at  TIMESTAMPTZ,
  resolved_by  UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  resolution   TEXT,
  rating       INTEGER     CHECK (rating BETWEEN 1 AND 5),
  rated_at     TIMESTAMPTZ,
  user_plan    TEXT,
  cv_id        UUID        REFERENCES public.cvs(id) ON DELETE SET NULL,
  metadata     JSONB       NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 9. SUPPORT_MESSAGES
-- ════════════════════════════════════════
CREATE TABLE public.support_messages (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_id    UUID        NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  sender_type  TEXT        NOT NULL CHECK (sender_type IN ('user','admin','system','bot')),
  content      TEXT        NOT NULL,
  content_type TEXT        NOT NULL DEFAULT 'text'
               CHECK (content_type IN ('text','markdown','image','file','system')),
  attachments  JSONB       DEFAULT '[]',
  is_internal  BOOLEAN     NOT NULL DEFAULT FALSE,
  is_read      BOOLEAN     NOT NULL DEFAULT FALSE,
  read_at      TIMESTAMPTZ,
  edited_at    TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 10. NOTIFICATIONS
-- ════════════════════════════════════════
CREATE TABLE public.notifications (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        TEXT        NOT NULL DEFAULT 'system',
  title       TEXT        NOT NULL,
  message     TEXT        NOT NULL,
  link        TEXT,
  is_read     BOOLEAN     NOT NULL DEFAULT FALSE,
  read_at     TIMESTAMPTZ,
  data        JSONB       DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 11. ADMIN_BROADCASTS
-- ════════════════════════════════════════
CREATE TABLE public.admin_broadcasts (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  title       TEXT        NOT NULL,
  message     TEXT        NOT NULL,
  type        TEXT        NOT NULL DEFAULT 'info'
              CHECK (type IN ('info','warning','success','maintenance')),
  target_plan TEXT        DEFAULT 'all',
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  starts_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 12. USER_SESSIONS
-- ════════════════════════════════════════
CREATE TABLE public.user_sessions (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_token TEXT        NOT NULL UNIQUE,
  ip_address    TEXT,
  user_agent    TEXT,
  country       TEXT,
  city          TEXT,
  device_type   TEXT,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at      TIMESTAMPTZ,
  is_active     BOOLEAN     NOT NULL DEFAULT TRUE
);

-- ════════════════════════════════════════
-- 13. AUDIT_LOGS
-- ════════════════════════════════════════
CREATE TABLE public.audit_logs (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  admin_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  action      TEXT        NOT NULL,
  entity_type TEXT        NOT NULL,
  entity_id   TEXT,
  old_data    JSONB,
  new_data    JSONB,
  ip_address  TEXT,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 14. PLATFORM_STATS
-- ════════════════════════════════════════
CREATE TABLE public.platform_stats (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  date             DATE        NOT NULL UNIQUE,
  new_users        INTEGER     NOT NULL DEFAULT 0,
  active_users     INTEGER     NOT NULL DEFAULT 0,
  cvs_created      INTEGER     NOT NULL DEFAULT 0,
  exports_done     INTEGER     NOT NULL DEFAULT 0,
  ai_requests      INTEGER     NOT NULL DEFAULT 0,
  payments_total   INTEGER     NOT NULL DEFAULT 0,
  revenue_xof      INTEGER     NOT NULL DEFAULT 0,
  tickets_opened   INTEGER     NOT NULL DEFAULT 0,
  tickets_resolved INTEGER     NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- 15. FEEDBACK
-- ════════════════════════════════════════
CREATE TABLE public.feedback (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  type        TEXT        NOT NULL DEFAULT 'general'
              CHECK (type IN ('general','template','ai','export','ux','bug','feature')),
  rating      INTEGER     NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title       TEXT,
  message     TEXT        NOT NULL,
  is_public   BOOLEAN     NOT NULL DEFAULT FALSE,
  is_featured BOOLEAN     NOT NULL DEFAULT FALSE,
  status      TEXT        NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending','approved','rejected')),
  admin_note  TEXT,
  user_plan   TEXT,
  template_id TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ════════════════════════════════════════
-- INDEX (créés APRÈS toutes les tables)
-- ════════════════════════════════════════
CREATE INDEX idx_cvs_user_id      ON public.cvs(user_id);
CREATE INDEX idx_cvs_updated      ON public.cvs(updated_at DESC);
CREATE INDEX idx_cvs_share_token  ON public.cvs(share_token) WHERE share_token IS NOT NULL;
CREATE INDEX idx_cvs_not_deleted  ON public.cvs(user_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_cvs_public       ON public.cvs(id) WHERE is_public = TRUE AND is_deleted = FALSE;

CREATE INDEX idx_payments_user    ON public.payments(user_id);
CREATE INDEX idx_payments_status  ON public.payments(status);
CREATE INDEX idx_payments_tx      ON public.payments(transaction_id);

CREATE INDEX idx_ai_logs_user     ON public.ai_logs(user_id, created_at DESC);
CREATE INDEX idx_ai_logs_date     ON public.ai_logs(created_at DESC);

CREATE INDEX idx_tickets_user     ON public.support_tickets(user_id);
CREATE INDEX idx_tickets_status   ON public.support_tickets(status);
CREATE INDEX idx_tickets_assigned ON public.support_tickets(assigned_to) WHERE assigned_to IS NOT NULL;

CREATE INDEX idx_messages_ticket  ON public.support_messages(ticket_id, created_at ASC);
CREATE INDEX idx_messages_unread  ON public.support_messages(ticket_id) WHERE is_read = FALSE;

CREATE INDEX idx_notifs_user      ON public.notifications(user_id, created_at DESC);
CREATE INDEX idx_notifs_unread    ON public.notifications(user_id) WHERE is_read = FALSE;

CREATE INDEX idx_audit_user       ON public.audit_logs(user_id, created_at DESC);
CREATE INDEX idx_sessions_user    ON public.user_sessions(user_id) WHERE is_active = TRUE;
CREATE INDEX idx_cv_versions      ON public.cv_versions(cv_id, version DESC);
CREATE INDEX idx_profiles_plan    ON public.profiles(plan);
CREATE INDEX idx_profiles_admin   ON public.profiles(id) WHERE is_admin = TRUE;

-- ════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════
ALTER TABLE public.profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cvs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cv_versions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_tickets  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_sessions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.license_keys     ENABLE ROW LEVEL SECURITY;

-- Profiles
CREATE POLICY "profiles_own_read"   ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "profiles_own_update" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "profiles_admin_all"  ON public.profiles FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- CVs
CREATE POLICY "cvs_own"       ON public.cvs FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "cvs_public_r"  ON public.cvs FOR SELECT USING (is_public = TRUE AND is_deleted = FALSE);
CREATE POLICY "cvs_admin"     ON public.cvs FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- CV versions
CREATE POLICY "cvv_own"   ON public.cv_versions FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "cvv_admin" ON public.cv_versions FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- Payments
CREATE POLICY "pay_own"   ON public.payments FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "pay_admin" ON public.payments FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- License keys
CREATE POLICY "lic_admin" ON public.license_keys FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);
CREATE POLICY "lic_read_own" ON public.license_keys FOR SELECT USING (
  used_by = auth.uid()
);

-- Support tickets
CREATE POLICY "tkt_own"   ON public.support_tickets FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "tkt_admin" ON public.support_tickets FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- Support messages
CREATE POLICY "msg_member" ON public.support_messages FOR ALL USING (
  auth.uid() = sender_id
  OR EXISTS(
    SELECT 1 FROM public.support_tickets t
    WHERE t.id = ticket_id AND t.user_id = auth.uid()
  )
  OR EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- Notifications
CREATE POLICY "notif_own"   ON public.notifications FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "notif_admin" ON public.notifications FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- Feedback
CREATE POLICY "fb_own_ins"  ON public.feedback FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "fb_own_read" ON public.feedback FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "fb_public"   ON public.feedback FOR SELECT USING (is_public = TRUE AND status = 'approved');
CREATE POLICY "fb_admin"    ON public.feedback FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- Sessions
CREATE POLICY "sess_own"   ON public.user_sessions FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "sess_admin" ON public.user_sessions FOR ALL USING (
  EXISTS(SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = TRUE)
);

-- ════════════════════════════════════════
-- FONCTIONS & TRIGGERS
-- ════════════════════════════════════════

-- Auto updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE TRIGGER cvs_upd      BEFORE UPDATE ON public.cvs              FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER profiles_upd BEFORE UPDATE ON public.profiles         FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER tickets_upd  BEFORE UPDATE ON public.support_tickets  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER payments_upd BEFORE UPDATE ON public.payments         FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles(id, email, name)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(COALESCE(NEW.email,'user'),'@',1))
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name  = CASE WHEN profiles.name = '' THEN EXCLUDED.name ELSE profiles.name END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Reset AI quota daily
CREATE OR REPLACE FUNCTION public.reset_ai_quota()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ai_last_reset IS DISTINCT FROM CURRENT_DATE THEN
    NEW.ai_used_today := 0;
    NEW.ai_last_reset := CURRENT_DATE;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_reset_ai
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.reset_ai_quota();

-- Auto ticket number
CREATE SEQUENCE public.ticket_seq START 1;

CREATE OR REPLACE FUNCTION public.generate_ticket_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ticket_no = 'TKT-PENDING' OR NEW.ticket_no IS NULL THEN
    NEW.ticket_no := 'TKT-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
      LPAD(NEXTVAL('public.ticket_seq')::TEXT, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER ticket_no_gen
  BEFORE INSERT ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.generate_ticket_no();

-- CV version history
CREATE OR REPLACE FUNCTION public.save_cv_version()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.data IS DISTINCT FROM NEW.data OR OLD.design IS DISTINCT FROM NEW.design THEN
    NEW.version := OLD.version + 1;
    INSERT INTO public.cv_versions(cv_id, user_id, version, data, design)
    VALUES (OLD.id, OLD.user_id, OLD.version, OLD.data, OLD.design);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER cvs_versioning
  BEFORE UPDATE ON public.cvs
  FOR EACH ROW EXECUTE FUNCTION public.save_cv_version();

-- Notify user when admin replies
CREATE OR REPLACE FUNCTION public.notify_on_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_ticket public.support_tickets%ROWTYPE;
BEGIN
  SELECT * INTO v_ticket FROM public.support_tickets WHERE id = NEW.ticket_id;
  IF NEW.sender_type IN ('admin','system') AND v_ticket.user_id IS NOT NULL THEN
    INSERT INTO public.notifications(user_id, type, title, message, link)
    VALUES (
      v_ticket.user_id,
      'ticket_reply',
      'Réponse de support',
      'Support a répondu à : ' || v_ticket.subject,
      '/support/ticket/' || v_ticket.id::TEXT
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_support_msg
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_message();

-- ════════════════════════════════════════
-- RPC FUNCTIONS
-- ════════════════════════════════════════

-- Consommer une requête IA
CREATE OR REPLACE FUNCTION public.consume_ai_request(p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_limit   INTEGER;
BEGIN
  SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN RETURN '{"error":"USER_NOT_FOUND"}'::JSONB; END IF;

  v_limit := CASE v_profile.plan
    WHEN 'free'    THEN 3
    WHEN 'starter' THEN 20
    WHEN 'premium' THEN 999999
    WHEN 'pro'     THEN 999999
    ELSE 3
  END;

  -- Reset si nouveau jour
  IF v_profile.ai_last_reset IS DISTINCT FROM CURRENT_DATE THEN
    UPDATE public.profiles SET ai_used_today=0, ai_last_reset=CURRENT_DATE WHERE id=p_user_id;
    v_profile.ai_used_today := 0;
  END IF;

  IF v_profile.ai_used_today >= v_limit THEN
    RETURN jsonb_build_object('error','QUOTA_EXCEEDED','used',v_profile.ai_used_today,'limit',v_limit);
  END IF;

  UPDATE public.profiles
  SET ai_used_today = ai_used_today + 1, ai_total_used = ai_total_used + 1
  WHERE id = p_user_id;

  RETURN jsonb_build_object('ok',TRUE,'used',v_profile.ai_used_today+1,'limit',v_limit);
END;
$$;

-- Activer une clé de licence
CREATE OR REPLACE FUNCTION public.activate_license_key(p_key TEXT, p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_key public.license_keys%ROWTYPE;
BEGIN
  SELECT * INTO v_key FROM public.license_keys WHERE key = p_key FOR UPDATE;
  IF NOT FOUND                              THEN RETURN '{"error":"KEY_NOT_FOUND"}'::JSONB; END IF;
  IF v_key.status <> 'active'             THEN RETURN jsonb_build_object('error','KEY_' || UPPER(v_key.status)); END IF;
  IF v_key.expires_at IS NOT NULL AND v_key.expires_at < NOW() THEN
    UPDATE public.license_keys SET status='expired' WHERE key=p_key;
    RETURN '{"error":"KEY_EXPIRED"}'::JSONB;
  END IF;
  IF v_key.uses_count >= v_key.max_uses    THEN RETURN '{"error":"KEY_MAX_USES"}'::JSONB; END IF;

  UPDATE public.license_keys
  SET status='used', used_by=p_user_id, used_at=NOW(), uses_count=uses_count+1
  WHERE key=p_key;

  UPDATE public.profiles
  SET plan=v_key.plan,
      plan_activated_at=NOW(),
      plan_expires_at=NOW() + (v_key.duration_days || ' days')::INTERVAL,
      plan_tx_id=p_key
  WHERE id=p_user_id;

  RETURN jsonb_build_object(
    'ok',TRUE,
    'plan',v_key.plan,
    'expires_at',(NOW()+(v_key.duration_days||' days')::INTERVAL)::TEXT
  );
END;
$$;

-- Stats admin dashboard
CREATE OR REPLACE FUNCTION public.get_admin_stats()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_result JSONB;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_admin=TRUE) THEN
    RETURN '{"error":"FORBIDDEN"}'::JSONB;
  END IF;

  SELECT jsonb_build_object(
    'users', jsonb_build_object(
      'total',  (SELECT COUNT(*) FROM public.profiles),
      'today',  (SELECT COUNT(*) FROM public.profiles WHERE DATE(created_at)=CURRENT_DATE),
      'week',   (SELECT COUNT(*) FROM public.profiles WHERE created_at > NOW()-INTERVAL '7 days'),
      'active', (SELECT COUNT(*) FROM public.profiles WHERE last_seen_at > NOW()-INTERVAL '24 hours'),
      'banned', (SELECT COUNT(*) FROM public.profiles WHERE is_banned=TRUE),
      'by_plan',(SELECT COALESCE(jsonb_object_agg(plan,cnt),'{}') FROM (SELECT plan,COUNT(*) cnt FROM public.profiles GROUP BY plan) x)
    ),
    'cvs', jsonb_build_object(
      'total', (SELECT COUNT(*) FROM public.cvs WHERE is_deleted=FALSE),
      'today', (SELECT COUNT(*) FROM public.cvs WHERE DATE(created_at)=CURRENT_DATE),
      'public',(SELECT COUNT(*) FROM public.cvs WHERE is_public=TRUE AND is_deleted=FALSE)
    ),
    'revenue', jsonb_build_object(
      'total_xof',(SELECT COALESCE(SUM(amount),0) FROM public.payments WHERE status='success'),
      'today',   (SELECT COALESCE(SUM(amount),0) FROM public.payments WHERE status='success' AND DATE(paid_at)=CURRENT_DATE),
      'week',    (SELECT COALESCE(SUM(amount),0) FROM public.payments WHERE status='success' AND paid_at>NOW()-INTERVAL '7 days'),
      'month',   (SELECT COALESCE(SUM(amount),0) FROM public.payments WHERE status='success' AND paid_at>NOW()-INTERVAL '30 days')
    ),
    'ai', jsonb_build_object(
      'total_requests',(SELECT COUNT(*) FROM public.ai_logs),
      'today',        (SELECT COUNT(*) FROM public.ai_logs WHERE DATE(created_at)=CURRENT_DATE),
      'success_rate', (SELECT ROUND(100.0*SUM(CASE WHEN success THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1) FROM public.ai_logs)
    ),
    'support', jsonb_build_object(
      'open',       (SELECT COUNT(*) FROM public.support_tickets WHERE status='open'),
      'in_progress',(SELECT COUNT(*) FROM public.support_tickets WHERE status='in_progress'),
      'unread',     (SELECT COUNT(*) FROM public.support_messages WHERE is_read=FALSE AND sender_type='user')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Données complètes d'un utilisateur (admin)
CREATE OR REPLACE FUNCTION public.get_user_full_data(p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_result JSONB;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_admin=TRUE) THEN
    RETURN '{"error":"FORBIDDEN"}'::JSONB;
  END IF;

  SELECT jsonb_build_object(
    'profile',  to_jsonb(p),
    'cvs',      (SELECT COALESCE(jsonb_agg(to_jsonb(c)),'[]') FROM public.cvs c WHERE c.user_id=p_user_id AND c.is_deleted=FALSE),
    'payments', (SELECT COALESCE(jsonb_agg(to_jsonb(py) ORDER BY py.created_at DESC),'[]') FROM public.payments py WHERE py.user_id=p_user_id LIMIT 10),
    'tickets',  (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]') FROM public.support_tickets t WHERE t.user_id=p_user_id LIMIT 10),
    'ai_usage', (SELECT jsonb_build_object('total',COUNT(*),'today',SUM(CASE WHEN DATE(created_at)=CURRENT_DATE THEN 1 ELSE 0 END)) FROM public.ai_logs WHERE user_id=p_user_id)
  ) INTO v_result
  FROM public.profiles p WHERE p.id=p_user_id;

  RETURN COALESCE(v_result,'{"error":"NOT_FOUND"}'::JSONB);
END;
$$;

-- ════════════════════════════════════════
-- REALTIME — Activer pour chat support
-- ════════════════════════════════════════
ALTER PUBLICATION supabase_realtime ADD TABLE public.support_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

-- ════════════════════════════════════════
-- ADMIN INITIAL — À PERSONNALISER
-- Remplacez votre_email@example.com par votre vrai email
-- ════════════════════════════════════════
-- UPDATE public.profiles
--   SET is_admin = TRUE, admin_role = 'superadmin'
-- WHERE email = 'votre_email@example.com';
