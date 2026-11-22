-- ============================================================================
-- CVxMaker — Durcissement n°2 (v33) : anti-flood, limites de taille, jetons
-- À exécuter APRÈS 20261101000000_security_audit.sql
-- ============================================================================

-- 1) Limiteur de débit générique pour toutes les écritures (anti-flood / anti-saturation du stockage)
--    Arguments : colonne d'identité, nombre max, fenêtre en minutes.
--    Si la colonne est NULL (visiteur anonyme), la limite s'applique à l'ensemble des lignes anonymes de la table.
CREATE OR REPLACE FUNCTION public.rate_limit_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE col text := TG_ARGV[0]; mx int := TG_ARGV[1]::int; mins int := TG_ARGV[2]::int; who uuid; n bigint;
BEGIN
  -- NB : dans une fonction SECURITY DEFINER current_user = propriétaire ; le rôle de la requête API est dans le réglage « role ».
  IF COALESCE(current_setting('role', true),'') NOT IN ('authenticated','anon') THEN RETURN NEW; END IF;   -- service_role / SQL admin : pas de limite
  EXECUTE format('SELECT ($1).%I', col) INTO who USING NEW;
  IF who IS NULL THEN
    EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE %I IS NULL AND created_at > now() - make_interval(mins => $1)', TG_TABLE_NAME, col) INTO n USING mins;
  ELSE
    EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE %I = $1 AND created_at > now() - make_interval(mins => $2)', TG_TABLE_NAME, col) INTO n USING who, mins;
  END IF;
  IF n >= mx THEN RAISE EXCEPTION 'Trop de requêtes, réessayez plus tard' USING ERRCODE = '54000'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.rate_limit_guard() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('cvs','user_id',120,60), ('documents','user_id',100,60),
    ('support_tickets','user_id',10,60), ('support_messages','sender_id',60,60),
    ('feedback','user_id',10,60), ('testimonials','user_id',5,60),
    ('feature_interest','user_id',60,60), ('notifications','user_id',200,60), ('export_logs','user_id',300,60)
  ) AS v(t,c,mx,mins)
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS rl_guard ON public.%I', r.t);
    EXECUTE format('CREATE TRIGGER rl_guard BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.rate_limit_guard(%L,%L,%L)', r.t, r.c, r.mx, r.mins);
  END LOOP;
END $$;

-- 2) Limites de taille / de longueur (NOT VALID : n'échoue pas sur l'existant, s'applique à toute nouvelle écriture)
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT * FROM (VALUES
    ('cvs','cvs_size_chk','pg_column_size(data) <= 2000000 AND char_length(title) <= 300'),
    ('cv_versions','cvv_size_chk','pg_column_size(data) <= 2000000'),
    ('documents','docs_size_chk','pg_column_size(data) <= 500000 AND char_length(title) <= 300'),
    ('testimonials','testi_len_chk','char_length(message) <= 1000 AND char_length(name) <= 100 AND (role IS NULL OR char_length(role) <= 100)'),
    ('feedback','fb_len_chk','char_length(message) <= 4000 AND (title IS NULL OR char_length(title) <= 200)'),
    ('feature_interest','fi_len_chk','char_length(feature) <= 100 AND (email IS NULL OR char_length(email) <= 254)'),
    ('support_tickets','tkt_len_chk','char_length(subject) <= 300'),
    ('support_messages','msg_len_chk','char_length(content) <= 8000 AND pg_column_size(attachments) <= 20000'),
    ('notifications','notif_len_chk','char_length(title) <= 300 AND char_length(message) <= 2000')
  ) AS v(t,n,e)
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT IF EXISTS %I', c.t, c.n);
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (%s) NOT VALID', c.t, c.n, c.e);
    EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
    END;
  END LOOP;
END $$;

-- 3) Un utilisateur ne peut pas posséder plus de 300 CV
CREATE OR REPLACE FUNCTION public.cvs_user_cap() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF COALESCE(current_setting('role', true),'') IN ('authenticated','anon') AND (SELECT COUNT(*) FROM public.cvs WHERE user_id = NEW.user_id) >= 300 THEN
    RAISE EXCEPTION 'Limite de 300 CV atteinte' USING ERRCODE = '54000';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cvs_user_cap() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS cvs_user_cap_trg ON public.cvs;
CREATE TRIGGER cvs_user_cap_trg BEFORE INSERT ON public.cvs FOR EACH ROW EXECUTE FUNCTION public.cvs_user_cap();

-- 4) Jetons de CV public : minimum 16 caractères. Les anciens jetons plus courts (devinables) sont régénérés
--    (128 bits). Les liens concernés cessent de fonctionner ; l'utilisateur peut simplement repartager.
UPDATE public.cvs SET share_token = encode(extensions.gen_random_bytes(16), 'hex')
 WHERE share_token IS NOT NULL AND char_length(share_token) < 16;
CREATE OR REPLACE FUNCTION public.get_public_cv(p_token text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT to_jsonb(r) FROM (
    SELECT model_id, accent_color, data, design, is_public, share_token
    FROM public.cvs
    WHERE share_token = p_token AND is_public = TRUE AND is_deleted = FALSE
      AND p_token IS NOT NULL AND char_length(p_token) >= 16
    LIMIT 1
  ) r;
$$;
REVOKE ALL ON FUNCTION public.get_public_cv(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_cv(text) TO anon, authenticated, service_role;

-- 5) Les visiteurs anonymes ne peuvent plus lire les colonnes sensibles des tables de suivi
REVOKE SELECT ON public.license_attempts FROM anon, authenticated;
