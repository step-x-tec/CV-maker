-- ═══════════════════════════════════════════════════════════════════════
-- SmartCV Pro — DURCISSEMENT SÉCURITÉ (à exécuter APRÈS le schéma de base)
-- Corrige les failles trouvées dans le schéma initial :
--  1. Élévation de privilège : un utilisateur pouvait faire UPDATE profiles SET is_admin=true / plan='pro'
--  2. Récursion infinie des politiques RLS (les politiques "admin" interrogeaient profiles depuis profiles)
--  3. Fonctions SECURITY DEFINER qui faisaient confiance à un p_user_id fourni par le client
--  4. Tables sans RLS (ai_logs, export_logs, admin_broadcasts, audit_logs, platform_stats) = lisibles/modifiables par n'importe qui
--  5. support_messages : possibilité d'écrire dans le ticket d'un autre, ou de se faire passer pour l'admin
-- Ce script est idempotent (relançable sans risque).
-- ═══════════════════════════════════════════════════════════════════════

-- 1. is_admin() : lit profiles en contournant la RLS (SECURITY DEFINER) → plus de récursion
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT COALESCE((SELECT is_admin FROM public.profiles WHERE id = auth.uid()), FALSE);
$$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

-- 2. Politiques admin réécrites avec is_admin()
DROP POLICY IF EXISTS "profiles_admin_all" ON public.profiles;
CREATE POLICY "profiles_admin_all" ON public.profiles FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "cvs_admin" ON public.cvs;
CREATE POLICY "cvs_admin" ON public.cvs FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "cvv_admin" ON public.cv_versions;
CREATE POLICY "cvv_admin" ON public.cv_versions FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "pay_admin" ON public.payments;
CREATE POLICY "pay_admin" ON public.payments FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "lic_admin" ON public.license_keys;
CREATE POLICY "lic_admin" ON public.license_keys FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "tkt_admin" ON public.support_tickets;
CREATE POLICY "tkt_admin" ON public.support_tickets FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "notif_admin" ON public.notifications;
CREATE POLICY "notif_admin" ON public.notifications FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "fb_admin" ON public.feedback;
CREATE POLICY "fb_admin" ON public.feedback FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "sess_admin" ON public.user_sessions;
CREATE POLICY "sess_admin" ON public.user_sessions FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 3. Colonnes sensibles de profiles : modifiables uniquement par un admin ou par une fonction serveur
--    (activate_license_key, consume_ai_request, webhook de paiement). Un simple utilisateur ne peut plus les toucher.
CREATE OR REPLACE FUNCTION public.protect_profile_columns()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Requête directe d'un client (rôle authenticated/anon) ET non admin → colonnes protégées interdites
  IF current_user IN ('authenticated','anon') AND NOT public.is_admin() THEN
    IF NEW.plan              IS DISTINCT FROM OLD.plan
    OR NEW.plan_activated_at IS DISTINCT FROM OLD.plan_activated_at
    OR NEW.plan_expires_at   IS DISTINCT FROM OLD.plan_expires_at
    OR NEW.plan_tx_id        IS DISTINCT FROM OLD.plan_tx_id
    OR NEW.ai_used_today     IS DISTINCT FROM OLD.ai_used_today
    OR NEW.ai_last_reset     IS DISTINCT FROM OLD.ai_last_reset
    OR NEW.ai_total_used     IS DISTINCT FROM OLD.ai_total_used
    OR NEW.exports_used      IS DISTINCT FROM OLD.exports_used
    OR NEW.exports_total     IS DISTINCT FROM OLD.exports_total
    OR NEW.is_active         IS DISTINCT FROM OLD.is_active
    OR NEW.is_banned         IS DISTINCT FROM OLD.is_banned
    OR NEW.ban_reason        IS DISTINCT FROM OLD.ban_reason
    OR NEW.banned_at         IS DISTINCT FROM OLD.banned_at
    OR NEW.banned_by         IS DISTINCT FROM OLD.banned_by
    OR NEW.is_admin          IS DISTINCT FROM OLD.is_admin
    OR NEW.admin_role        IS DISTINCT FROM OLD.admin_role
    OR NEW.referred_by       IS DISTINCT FROM OLD.referred_by
    THEN
      RAISE EXCEPTION 'Modification interdite : colonne protégée' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS profiles_protect ON public.profiles;
CREATE TRIGGER profiles_protect BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.protect_profile_columns();

-- 4. Fonctions "métier" : l'appelant ne peut agir que sur SON compte
CREATE OR REPLACE FUNCTION public.consume_ai_request(p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_profile public.profiles%ROWTYPE; v_limit INTEGER;
BEGIN
  IF auth.role() <> 'service_role' AND p_user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN
    RETURN '{"error":"FORBIDDEN"}'::JSONB;
  END IF;
  SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN RETURN '{"error":"USER_NOT_FOUND"}'::JSONB; END IF;
  v_limit := CASE v_profile.plan WHEN 'free' THEN 3 WHEN 'starter' THEN 20 WHEN 'premium' THEN 999999 WHEN 'pro' THEN 999999 ELSE 3 END;
  IF v_profile.ai_last_reset IS DISTINCT FROM CURRENT_DATE THEN
    UPDATE public.profiles SET ai_used_today=0, ai_last_reset=CURRENT_DATE WHERE id=p_user_id;
    v_profile.ai_used_today := 0;
  END IF;
  IF v_profile.ai_used_today >= v_limit THEN
    RETURN jsonb_build_object('error','QUOTA_EXCEEDED','used',v_profile.ai_used_today,'limit',v_limit);
  END IF;
  UPDATE public.profiles SET ai_used_today = ai_used_today + 1, ai_total_used = ai_total_used + 1 WHERE id = p_user_id;
  RETURN jsonb_build_object('ok',TRUE,'used',v_profile.ai_used_today+1,'limit',v_limit);
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_license_key(p_key TEXT, p_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_key public.license_keys%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' AND p_user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN
    RETURN '{"error":"FORBIDDEN"}'::JSONB;
  END IF;
  SELECT * INTO v_key FROM public.license_keys WHERE key = p_key FOR UPDATE;
  IF NOT FOUND                  THEN RETURN '{"error":"KEY_NOT_FOUND"}'::JSONB; END IF;
  IF v_key.status <> 'active'   THEN RETURN jsonb_build_object('error','KEY_' || UPPER(v_key.status)); END IF;
  IF v_key.expires_at IS NOT NULL AND v_key.expires_at < NOW() THEN
    UPDATE public.license_keys SET status='expired' WHERE key=p_key;
    RETURN '{"error":"KEY_EXPIRED"}'::JSONB;
  END IF;
  IF v_key.uses_count >= v_key.max_uses THEN RETURN '{"error":"KEY_MAX_USES"}'::JSONB; END IF;
  -- La clé ne passe à "used" qu'une fois toutes ses utilisations consommées (le schéma d'origine la marquait "used" dès la 1re)
  UPDATE public.license_keys
     SET uses_count = uses_count + 1,
         used_by    = p_user_id,
         used_at    = NOW(),
         status     = CASE WHEN uses_count + 1 >= max_uses THEN 'used' ELSE 'active' END
   WHERE key = p_key;
  UPDATE public.profiles
     SET plan = v_key.plan, plan_activated_at = NOW(),
         plan_expires_at = NOW() + (v_key.duration_days || ' days')::INTERVAL, plan_tx_id = p_key
   WHERE id = p_user_id;
  RETURN jsonb_build_object('ok',TRUE,'plan',v_key.plan,'expires_at',(NOW()+(v_key.duration_days||' days')::INTERVAL)::TEXT);
END;
$$;

-- Droits d'exécution : jamais pour anon
REVOKE ALL ON FUNCTION public.consume_ai_request(UUID)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.activate_license_key(TEXT, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_admin_stats()                FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_user_full_data(UUID)         FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_ai_request(UUID)         TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.activate_license_key(TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_stats()                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_full_data(UUID)         TO authenticated, service_role;
ALTER FUNCTION public.get_admin_stats()        SET search_path = public;
ALTER FUNCTION public.get_user_full_data(UUID) SET search_path = public;

-- 5. Support : tickets et messages
DROP POLICY IF EXISTS "tkt_own" ON public.support_tickets;
CREATE POLICY "tkt_own_select" ON public.support_tickets FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "tkt_own_insert" ON public.support_tickets FOR INSERT
  WITH CHECK (auth.uid() = user_id AND status = 'open' AND assigned_to IS NULL AND resolved_by IS NULL);

DROP POLICY IF EXISTS "msg_member" ON public.support_messages;
CREATE POLICY "msg_select" ON public.support_messages FOR SELECT USING (
  public.is_admin()
  OR (is_internal = FALSE AND EXISTS (SELECT 1 FROM public.support_tickets t WHERE t.id = ticket_id AND t.user_id = auth.uid()))
);
CREATE POLICY "msg_insert_user" ON public.support_messages FOR INSERT WITH CHECK (
  sender_id = auth.uid() AND sender_type = 'user' AND is_internal = FALSE
  AND EXISTS (SELECT 1 FROM public.support_tickets t WHERE t.id = ticket_id AND t.user_id = auth.uid())
);
CREATE POLICY "msg_admin_all" ON public.support_messages FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Feedback : un utilisateur ne peut pas s'auto-approuver
DROP POLICY IF EXISTS "fb_own_ins" ON public.feedback;
CREATE POLICY "fb_own_ins" ON public.feedback FOR INSERT
  WITH CHECK (auth.uid() = user_id AND status = 'pending' AND is_public = FALSE);

-- 6. Tables jusque-là SANS RLS (exposées publiquement via l'API)
ALTER TABLE public.ai_logs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_logs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_broadcasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_stats  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ailogs_own_read"  ON public.ai_logs;
DROP POLICY IF EXISTS "ailogs_admin"     ON public.ai_logs;
CREATE POLICY "ailogs_own_read" ON public.ai_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "ailogs_admin"    ON public.ai_logs FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "exportlogs_own_read"   ON public.export_logs;
DROP POLICY IF EXISTS "exportlogs_own_insert" ON public.export_logs;
DROP POLICY IF EXISTS "exportlogs_admin"      ON public.export_logs;
CREATE POLICY "exportlogs_own_read"   ON public.export_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "exportlogs_own_insert" ON public.export_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "exportlogs_admin"      ON public.export_logs FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "bc_read_active" ON public.admin_broadcasts;
DROP POLICY IF EXISTS "bc_admin"       ON public.admin_broadcasts;
CREATE POLICY "bc_read_active" ON public.admin_broadcasts FOR SELECT TO authenticated
  USING (is_active AND starts_at <= NOW() AND (ends_at IS NULL OR ends_at > NOW()));
CREATE POLICY "bc_admin" ON public.admin_broadcasts FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "audit_admin" ON public.audit_logs;
CREATE POLICY "audit_admin" ON public.audit_logs FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "pstats_admin" ON public.platform_stats;
CREATE POLICY "pstats_admin" ON public.platform_stats FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Vérification rapide (doit renvoyer 0 ligne) : tables publiques SANS RLS
-- SELECT tablename FROM pg_tables WHERE schemaname='public' AND NOT rowsecurity;
