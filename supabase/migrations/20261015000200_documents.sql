-- ═══════════════════════════════════════════════════════════════════════
-- CVxMaker — DOCUMENTS DE CANDIDATURE (lettres de motivation, demandes
-- d'emploi / de stage, candidatures spontanées), synchronisés par compte.
-- Chaque utilisateur ne voit que ses propres documents ; un admin peut les
-- lire (support). Script idempotent (relançable sans risque).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.documents (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind        TEXT        NOT NULL CHECK (kind IN ('lettre','emploi','stage','spontanee')),
  title       TEXT        NOT NULL DEFAULT '' CHECK (char_length(title) <= 200),
  data        JSONB       NOT NULL CHECK (pg_column_size(data) < 60000),
  is_deleted  BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_user ON public.documents(user_id, updated_at DESC) WHERE is_deleted = FALSE;

DROP TRIGGER IF EXISTS documents_upd ON public.documents;
CREATE TRIGGER documents_upd BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "docs_own_select" ON public.documents;
CREATE POLICY "docs_own_select" ON public.documents FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "docs_own_insert" ON public.documents;
CREATE POLICY "docs_own_insert" ON public.documents FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "docs_own_update" ON public.documents;
CREATE POLICY "docs_own_update" ON public.documents FOR UPDATE
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "docs_own_delete" ON public.documents;
CREATE POLICY "docs_own_delete" ON public.documents FOR DELETE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "docs_admin_select" ON public.documents;
CREATE POLICY "docs_admin_select" ON public.documents FOR SELECT
  USING (public.is_admin());
