-- ============================================================================
-- CVxMaker — Audit de sécurité (v32)
-- ============================================================================
-- 1) FAILLE CRITIQUE corrigée : le déclencheur protect_profile_columns() était SECURITY DEFINER.
--    Dans une fonction SECURITY DEFINER, current_user vaut le PROPRIÉTAIRE (postgres), jamais « authenticated » :
--    la protection ne se déclenchait donc jamais et n'importe quel utilisateur connecté pouvait modifier
--    sa propre ligne profiles (plan, quotas, is_admin, bannissement…) via l'API.
--    Elle devient SECURITY INVOKER : current_user est bien le rôle de l'appelant.
CREATE OR REPLACE FUNCTION public.protect_profile_columns()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN
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
    OR NEW.id                IS DISTINCT FROM OLD.id
    OR NEW.email             IS DISTINCT FROM OLD.email
    THEN
      RAISE EXCEPTION 'Modification interdite : colonne protégée' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- 2) Surface d'API : par défaut Postgres donne EXECUTE à PUBLIC sur toute fonction, donc les visiteurs
--    anonymes pouvaient appeler via /rest/v1/rpc des fonctions internes. On retire tout, puis on rend
--    uniquement ce qui est voulu.
DO $$
DECLARE r record;
  anon_ok text[] := ARRAY['ads_pick','ads_track','delete_guest_data','get_guest_cv','get_public_settings',
                          'increment_cv_view','get_public_cv','track_event','track_guest_cv','is_admin','admin_rank'];
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, p.prorettype::regtype::text AS rt, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')   -- hors extensions
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon', r.proname, r.args);
    IF r.rt = 'trigger' OR left(r.proname,1) = '_' THEN   -- déclencheurs et utilitaires internes (_safe_count, _series…) : jamais exposés à l'API
      EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM authenticated', r.proname, r.args);
    ELSE
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role', r.proname, r.args);
      IF r.proname = ANY (anon_ok) THEN
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO anon', r.proname, r.args);
      END IF;
    END IF;
  END LOOP;
END $$;

-- Toute future fonction : aucun accès public par défaut (il faudra l'ouvrir explicitement).
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;

-- 3) FAILLE CRITIQUE : _safe_count(p_sql) exécutait du SQL arbitraire en SECURITY DEFINER et était appelable par
--    n'importe quel utilisateur (voire visiteur) via /rest/v1/rpc : lecture/écriture de toute la base, élévation admin.
--    Désormais (a) retirée de l'API (voir boucle ci-dessus), (b) elle n'accepte plus qu'un simple « SELECT count(*) … »
--    en une seule instruction, par défense en profondeur.
CREATE OR REPLACE FUNCTION public._safe_count(p_sql text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n BIGINT;
BEGIN
  IF p_sql !~* '^\s*select\s+count\s*\(' OR position(';' IN p_sql) > 0 OR p_sql ~* '\m(insert|update|delete|drop|alter|create|grant|revoke|truncate|copy|do|call|pg_sleep)\M' THEN
    RAISE EXCEPTION 'requête non autorisée';
  END IF;
  EXECUTE p_sql INTO n; RETURN n;
EXCEPTION WHEN undefined_table OR undefined_column THEN RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public._safe_count(text) FROM PUBLIC, anon, authenticated;

-- 4) Les CV publics ne doivent être lisibles QUE par quelqu'un qui connaît le lien (jeton).
--    Avant : la règle « cvs_public_r » laissait n'importe qui lister TOUS les CV publics
--    (/rest/v1/cvs?is_public=eq.true) avec e-mail, téléphone et jetons. Maintenant : lecture par jeton uniquement.
DROP POLICY IF EXISTS "cvs_public_r" ON public.cvs;
CREATE OR REPLACE FUNCTION public.get_public_cv(p_token text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT to_jsonb(r) FROM (
    SELECT model_id, accent_color, data, design, is_public, share_token
    FROM public.cvs
    WHERE share_token = p_token AND is_public = TRUE AND is_deleted = FALSE
      AND p_token IS NOT NULL AND char_length(p_token) >= 6
    LIMIT 1
  ) r;
$$;
REVOKE ALL ON FUNCTION public.get_public_cv(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_cv(text) TO anon, authenticated, service_role;

-- 5) Un visiteur sans compte ne peut pas enregistrer plus de 30 CV (anti-saturation du stockage).
CREATE OR REPLACE FUNCTION public.guest_cvs_cap() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF (SELECT COUNT(*) FROM public.guest_cvs WHERE guest_id = NEW.guest_id) >= 30 THEN
    RAISE EXCEPTION 'limite atteinte';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.guest_cvs_cap() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS guest_cvs_cap_trg ON public.guest_cvs;
CREATE TRIGGER guest_cvs_cap_trg BEFORE INSERT ON public.guest_cvs FOR EACH ROW EXECUTE FUNCTION public.guest_cvs_cap();

-- 6) Anti-devinette des clés de licence : 8 essais par utilisateur et par 10 minutes.
CREATE TABLE IF NOT EXISTS public.license_attempts (
  id BIGSERIAL PRIMARY KEY, user_id UUID, at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.license_attempts ENABLE ROW LEVEL SECURITY;      -- aucune policy : inaccessible depuis l'API
REVOKE ALL ON public.license_attempts FROM anon, authenticated;
CREATE INDEX IF NOT EXISTS license_attempts_user_at ON public.license_attempts(user_id, at DESC);

CREATE OR REPLACE FUNCTION public.activate_license_key(p_key text, p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_key public.license_keys%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' AND p_user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN
    RETURN '{"error":"FORBIDDEN"}'::JSONB;
  END IF;
  IF (SELECT COUNT(*) FROM public.license_attempts WHERE user_id = p_user_id AND at > NOW() - INTERVAL '10 minutes') >= 8 THEN
    RETURN '{"error":"TOO_MANY_ATTEMPTS"}'::JSONB;
  END IF;
  INSERT INTO public.license_attempts(user_id) VALUES (p_user_id);
  DELETE FROM public.license_attempts WHERE at < NOW() - INTERVAL '2 days';
  SELECT * INTO v_key FROM public.license_keys WHERE key = p_key FOR UPDATE;
  IF NOT FOUND                  THEN RETURN '{"error":"KEY_NOT_FOUND"}'::JSONB; END IF;
  IF v_key.status <> 'active'   THEN RETURN jsonb_build_object('error','KEY_' || UPPER(v_key.status)); END IF;
  IF v_key.expires_at IS NOT NULL AND v_key.expires_at < NOW() THEN
    UPDATE public.license_keys SET status='expired' WHERE key=p_key;
    RETURN '{"error":"KEY_EXPIRED"}'::JSONB;
  END IF;
  IF v_key.uses_count >= v_key.max_uses THEN RETURN '{"error":"KEY_MAX_USES"}'::JSONB; END IF;
  UPDATE public.license_keys
     SET uses_count = uses_count + 1, used_by = p_user_id, used_at = NOW(),
         status = CASE WHEN uses_count + 1 >= max_uses THEN 'used' ELSE 'active' END
   WHERE key = p_key;
  UPDATE public.profiles
     SET plan = v_key.plan, plan_activated_at = NOW(),
         plan_expires_at = NOW() + (v_key.duration_days || ' days')::INTERVAL, plan_tx_id = p_key
   WHERE id = p_user_id;
  RETURN jsonb_build_object('ok',TRUE,'plan',v_key.plan,'expires_at',(NOW()+(v_key.duration_days||' days')::INTERVAL)::TEXT);
END $$;
REVOKE ALL ON FUNCTION public.activate_license_key(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activate_license_key(text, uuid) TO authenticated, service_role;
