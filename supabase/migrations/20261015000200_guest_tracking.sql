-- ═══════════════════════════════════════════════════════════════════════
-- CVxMaker — SUIVI DES VISITEURS SANS COMPTE (« invités »)
-- Un visiteur qui remplit un CV sans créer de compte reçoit un identifiant
-- unique (guest_profiles) ; ses CV enregistrés / exportés sont conservés
-- (guest_cvs) avec un jeton de lien. Visible uniquement par un admin.
-- Consentement : la fonction refuse tout enregistrement sans p_consent = TRUE.
-- Aucun accès direct aux tables pour anon : tout passe par des fonctions
-- SECURITY DEFINER. Script idempotent.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.guest_profiles (
  guest_id    UUID        PRIMARY KEY,
  ref_no      BIGINT      GENERATED ALWAYS AS IDENTITY,
  name        TEXT,
  email       TEXT,
  phone       TEXT,
  address     TEXT,
  consent_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  first_seen  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_guest_ref ON public.guest_profiles(ref_no);
CREATE INDEX IF NOT EXISTS idx_guest_last_seen ON public.guest_profiles(last_seen DESC);

CREATE TABLE IF NOT EXISTS public.guest_cvs (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  guest_id     UUID        NOT NULL REFERENCES public.guest_profiles(guest_id) ON DELETE CASCADE,
  cv_key       TEXT        NOT NULL CHECK (char_length(cv_key) BETWEEN 1 AND 64),
  token        TEXT        NOT NULL UNIQUE DEFAULT replace(uuid_generate_v4()::text, '-', ''),
  title        TEXT,
  model_id     TEXT,
  accent_color TEXT,
  data         JSONB       NOT NULL DEFAULT '{}'::jsonb,
  saves        INTEGER     NOT NULL DEFAULT 0,
  exports      INTEGER     NOT NULL DEFAULT 0,
  last_event   TEXT        CHECK (last_event IN ('saved','exported')),
  is_public    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (guest_id, cv_key)
);
CREATE INDEX IF NOT EXISTS idx_guest_cvs_guest ON public.guest_cvs(guest_id);

ALTER TABLE public.guest_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_cvs      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "guest_profiles_admin" ON public.guest_profiles;
CREATE POLICY "guest_profiles_admin" ON public.guest_profiles FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "guest_cvs_admin" ON public.guest_cvs;
CREATE POLICY "guest_cvs_admin" ON public.guest_cvs FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Enregistrement / mise à jour d'un CV invité (après consentement)
CREATE OR REPLACE FUNCTION public.track_guest_cv(
  p_guest UUID, p_cv_key TEXT, p_title TEXT, p_model TEXT, p_accent TEXT,
  p_data JSONB, p_event TEXT, p_consent BOOLEAN
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p JSONB := COALESCE(p_data->'p', '{}'::jsonb);
BEGIN
  IF p_consent IS NOT TRUE THEN RAISE EXCEPTION 'consent required'; END IF;
  IF p_guest IS NULL OR p_cv_key IS NULL OR char_length(p_cv_key) > 64 THEN RAISE EXCEPTION 'invalid ids'; END IF;
  IF p_event NOT IN ('saved','exported') THEN RAISE EXCEPTION 'invalid event'; END IF;
  IF p_data IS NULL OR octet_length(p_data::text) > 300000 THEN RAISE EXCEPTION 'data too large'; END IF;

  INSERT INTO public.guest_profiles(guest_id, name, email, phone, address)
  VALUES (p_guest, left(v_p->>'name',120), left(v_p->>'email',200), left(v_p->>'phone',60), left(v_p->>'address',200))
  ON CONFLICT (guest_id) DO UPDATE
    SET name    = COALESCE(NULLIF(EXCLUDED.name,''),    public.guest_profiles.name),
        email   = COALESCE(NULLIF(EXCLUDED.email,''),   public.guest_profiles.email),
        phone   = COALESCE(NULLIF(EXCLUDED.phone,''),   public.guest_profiles.phone),
        address = COALESCE(NULLIF(EXCLUDED.address,''), public.guest_profiles.address),
        last_seen = NOW();

  INSERT INTO public.guest_cvs(guest_id, cv_key, title, model_id, accent_color, data, saves, exports, last_event)
  VALUES (p_guest, p_cv_key, left(p_title,120), left(p_model,60), left(p_accent,20), p_data,
          CASE WHEN p_event='saved' THEN 1 ELSE 0 END, CASE WHEN p_event='exported' THEN 1 ELSE 0 END, p_event)
  ON CONFLICT (guest_id, cv_key) DO UPDATE
    SET title=EXCLUDED.title, model_id=EXCLUDED.model_id, accent_color=EXCLUDED.accent_color, data=EXCLUDED.data,
        saves   = public.guest_cvs.saves   + CASE WHEN p_event='saved'    THEN 1 ELSE 0 END,
        exports = public.guest_cvs.exports + CASE WHEN p_event='exported' THEN 1 ELSE 0 END,
        last_event = p_event, updated_at = NOW();
END;
$$;
REVOKE ALL ON FUNCTION public.track_guest_cv(UUID,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.track_guest_cv(UUID,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT,BOOLEAN) TO anon, authenticated;

-- Lecture d'un CV invité par jeton : public seulement si is_public, sinon réservé aux admins
CREATE OR REPLACE FUNCTION public.get_guest_cv(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.guest_cvs;
BEGIN
  SELECT * INTO r FROM public.guest_cvs WHERE token = p_token;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF r.is_public IS NOT TRUE AND NOT public.is_admin() THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('model_id', r.model_id, 'accent_color', r.accent_color, 'data', r.data, 'design', '{}'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.get_guest_cv(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_guest_cv(TEXT) TO anon, authenticated;

-- Droit à l'effacement : un visiteur peut supprimer toutes ses données depuis son appareil
CREATE OR REPLACE FUNCTION public.delete_guest_data(p_guest UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM public.guest_profiles WHERE guest_id = p_guest;
$$;
REVOKE ALL ON FUNCTION public.delete_guest_data(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_guest_data(UUID) TO anon, authenticated;
