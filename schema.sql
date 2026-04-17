-- ═══════════════════════════════════════════════════════════
-- FinançasDuo — Supabase Schema
-- Execute este script no SQL Editor do Supabase
-- ═══════════════════════════════════════════════════════════

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ───────────────────────────────────────
-- TABELA: profiles
-- Extensão da tabela auth.users do Supabase
-- ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  email       TEXT NOT NULL UNIQUE,
  partner_id  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  avatar_color TEXT DEFAULT '#4f8ef7',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ───────────────────────────────────────
-- TABELA: couple_links
-- Vinculação bidirecional entre parceiros
-- ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.couple_links (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_a_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_b_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_a_id, user_b_id)
);

-- ───────────────────────────────────────
-- TABELA: transactions
-- ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.transactions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN ('receita', 'despesa')),
  valor       NUMERIC(12,2) NOT NULL CHECK (valor > 0),
  categoria   TEXT NOT NULL,
  data        DATE NOT NULL,
  descricao   TEXT NOT NULL,
  pagamento   TEXT NOT NULL DEFAULT 'pix',
  owner       TEXT NOT NULL DEFAULT 'me' CHECK (owner IN ('me', 'partner', 'shared')),
  shared      BOOLEAN NOT NULL DEFAULT FALSE,
  split_value NUMERIC(12,2),           -- Valor dividido para o parceiro
  tags        TEXT[] DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_transactions_user_id   ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_data       ON public.transactions(data DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_type       ON public.transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_shared     ON public.transactions(shared);
CREATE INDEX IF NOT EXISTS idx_transactions_owner      ON public.transactions(owner);

-- ───────────────────────────────────────
-- TABELA: bills (boletos / contas fixas)
-- ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bills (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  nome        TEXT NOT NULL,
  valor       NUMERIC(12,2) NOT NULL CHECK (valor > 0),
  vencimento  DATE NOT NULL,
  frequencia  TEXT NOT NULL DEFAULT 'mensal' CHECK (frequencia IN ('mensal','semanal','anual','unico')),
  categoria   TEXT NOT NULL DEFAULT 'Outros',
  owner       TEXT NOT NULL DEFAULT 'shared' CHECK (owner IN ('me', 'partner', 'shared')),
  pago        BOOLEAN NOT NULL DEFAULT FALSE,
  pago_em     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bills_user_id    ON public.bills(user_id);
CREATE INDEX IF NOT EXISTS idx_bills_vencimento ON public.bills(vencimento);

-- ───────────────────────────────────────
-- TABELA: goals (metas financeiras)
-- ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.goals (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  nome        TEXT NOT NULL,
  valor_total NUMERIC(12,2) NOT NULL CHECK (valor_total > 0),
  valor_atual NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (valor_atual >= 0),
  data_alvo   DATE,
  mensal      NUMERIC(12,2) DEFAULT 0,
  icone       TEXT DEFAULT 'bi-trophy',
  shared      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ───────────────────────────────────────
-- TABELA: budgets (orçamentos mensais)
-- ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.budgets (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  categoria   TEXT NOT NULL,
  valor_limite NUMERIC(12,2) NOT NULL CHECK (valor_limite > 0),
  mes         TEXT NOT NULL,  -- formato: YYYY-MM
  shared      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, categoria, mes)
);

-- ═══════════════════════════════════════
-- ROW LEVEL SECURITY (RLS)
-- ═══════════════════════════════════════

ALTER TABLE public.profiles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couple_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bills        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goals        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets      ENABLE ROW LEVEL SECURITY;

-- PROFILES: cada um vê o próprio + parceiro
CREATE POLICY "profiles_select" ON public.profiles
  FOR SELECT USING (
    auth.uid() = id
    OR id IN (
      SELECT CASE WHEN user_a_id = auth.uid() THEN user_b_id ELSE user_a_id END
      FROM public.couple_links
      WHERE user_a_id = auth.uid() OR user_b_id = auth.uid()
    )
  );

CREATE POLICY "profiles_insert" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- COUPLE_LINKS
CREATE POLICY "couple_links_select" ON public.couple_links
  FOR SELECT USING (user_a_id = auth.uid() OR user_b_id = auth.uid());

CREATE POLICY "couple_links_insert" ON public.couple_links
  FOR INSERT WITH CHECK (user_a_id = auth.uid());

CREATE POLICY "couple_links_delete" ON public.couple_links
  FOR DELETE USING (user_a_id = auth.uid() OR user_b_id = auth.uid());

-- TRANSACTIONS: ver as próprias + compartilhadas do parceiro
CREATE POLICY "transactions_select" ON public.transactions
  FOR SELECT USING (
    user_id = auth.uid()
    OR (
      shared = TRUE
      AND user_id IN (
        SELECT CASE WHEN user_a_id = auth.uid() THEN user_b_id ELSE user_a_id END
        FROM public.couple_links
        WHERE user_a_id = auth.uid() OR user_b_id = auth.uid()
      )
    )
  );

CREATE POLICY "transactions_insert" ON public.transactions
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "transactions_update" ON public.transactions
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "transactions_delete" ON public.transactions
  FOR DELETE USING (user_id = auth.uid());

-- BILLS
CREATE POLICY "bills_select" ON public.bills
  FOR SELECT USING (
    user_id = auth.uid()
    OR (
      owner IN ('shared', 'partner')
      AND user_id IN (
        SELECT CASE WHEN user_a_id = auth.uid() THEN user_b_id ELSE user_a_id END
        FROM public.couple_links
        WHERE user_a_id = auth.uid() OR user_b_id = auth.uid()
      )
    )
  );

CREATE POLICY "bills_insert" ON public.bills
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "bills_update" ON public.bills
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "bills_delete" ON public.bills
  FOR DELETE USING (user_id = auth.uid());

-- GOALS
CREATE POLICY "goals_select" ON public.goals
  FOR SELECT USING (
    user_id = auth.uid()
    OR (
      shared = TRUE
      AND user_id IN (
        SELECT CASE WHEN user_a_id = auth.uid() THEN user_b_id ELSE user_a_id END
        FROM public.couple_links
        WHERE user_a_id = auth.uid() OR user_b_id = auth.uid()
      )
    )
  );

CREATE POLICY "goals_insert" ON public.goals
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "goals_update" ON public.goals
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "goals_delete" ON public.goals
  FOR DELETE USING (user_id = auth.uid());

-- BUDGETS
CREATE POLICY "budgets_select" ON public.budgets
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "budgets_insert" ON public.budgets
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "budgets_update" ON public.budgets
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "budgets_delete" ON public.budgets
  FOR DELETE USING (user_id = auth.uid());

-- ═══════════════════════════════════════
-- FUNÇÕES / TRIGGERS
-- ═══════════════════════════════════════

-- Auto-criar profile após signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NEW.email
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at     BEFORE UPDATE ON public.profiles     FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER transactions_updated_at BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER bills_updated_at        BEFORE UPDATE ON public.bills        FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER goals_updated_at        BEFORE UPDATE ON public.goals        FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ═══════════════════════════════════════
-- FUNÇÃO: get_dashboard_stats
-- Retorna stats consolidados para um usuário
-- ═══════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_dashboard_stats(p_user_id UUID, p_view TEXT DEFAULT 'individual')
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_partner_id UUID;
  v_mes_atual TEXT := TO_CHAR(NOW(), 'YYYY-MM');
  v_result JSON;
BEGIN
  -- Busca partner_id via couple_links
  SELECT CASE WHEN user_a_id = p_user_id THEN user_b_id ELSE user_a_id END
  INTO v_partner_id
  FROM public.couple_links
  WHERE user_a_id = p_user_id OR user_b_id = p_user_id
  LIMIT 1;

  WITH relevant_transactions AS (
    SELECT t.*, p.name as owner_name
    FROM public.transactions t
    JOIN public.profiles p ON p.id = t.user_id
    WHERE (
      -- Vista individual: próprias + compartilhadas
      (p_view = 'individual' AND (
        t.user_id = p_user_id
        OR (t.shared = TRUE AND t.user_id = v_partner_id)
      ))
      OR
      -- Vista casal: tudo dos dois
      (p_view = 'casal' AND (
        t.user_id = p_user_id
        OR t.user_id = v_partner_id
      ))
    )
  ),
  mes_stats AS (
    SELECT
      COALESCE(SUM(CASE WHEN type='receita' THEN valor ELSE 0 END), 0) AS receitas_mes,
      COALESCE(SUM(CASE WHEN type='despesa' THEN valor ELSE 0 END), 0) AS despesas_mes
    FROM relevant_transactions
    WHERE TO_CHAR(data, 'YYYY-MM') = v_mes_atual
  ),
  saldo_total AS (
    SELECT COALESCE(SUM(CASE WHEN type='receita' THEN valor ELSE -valor END), 0) AS saldo
    FROM relevant_transactions
  ),
  me_stats AS (
    SELECT
      COALESCE(SUM(CASE WHEN type='receita' AND user_id=p_user_id THEN valor ELSE 0 END), 0) AS me_receitas,
      COALESCE(SUM(CASE WHEN type='despesa' AND user_id=p_user_id THEN valor ELSE 0 END), 0) AS me_despesas
    FROM relevant_transactions
    WHERE TO_CHAR(data, 'YYYY-MM') = v_mes_atual
  ),
  partner_stats AS (
    SELECT
      COALESCE(SUM(CASE WHEN type='receita' AND user_id=v_partner_id THEN valor ELSE 0 END), 0) AS partner_receitas,
      COALESCE(SUM(CASE WHEN type='despesa' AND user_id=v_partner_id THEN valor ELSE 0 END), 0) AS partner_despesas
    FROM relevant_transactions
    WHERE TO_CHAR(data, 'YYYY-MM') = v_mes_atual
  ),
  cat_despesas AS (
    SELECT categoria, SUM(valor) as total
    FROM relevant_transactions
    WHERE type='despesa' AND TO_CHAR(data,'YYYY-MM') = v_mes_atual
    GROUP BY categoria
    ORDER BY total DESC
    LIMIT 10
  )
  SELECT json_build_object(
    'saldo',        st.saldo,
    'receitas_mes', ms.receitas_mes,
    'despesas_mes', ms.despesas_mes,
    'economia_mes', ms.receitas_mes - ms.despesas_mes,
    'me_receitas',  mts.me_receitas,
    'me_despesas',  mts.me_despesas,
    'partner_receitas', ps.partner_receitas,
    'partner_despesas', ps.partner_despesas,
    'categorias', (SELECT json_agg(json_build_object('categoria', c.categoria, 'total', c.total)) FROM cat_despesas c),
    'partner_id', v_partner_id,
    'mes', v_mes_atual
  )
  INTO v_result
  FROM mes_stats ms, saldo_total st, me_stats mts, partner_stats ps;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════
-- SEED: Dados de demo (Lucas & Leticia)
-- Execute manualmente após criar as contas
-- ═══════════════════════════════════════

-- INSTRUÇÕES:
-- 1. Crie as contas pelo signup do app:
--    lucas@financasduo.com / Lucas2024!
--    leticia@financasduo.com / Leticia2024!
-- 2. Copie os UUIDs gerados pelo Supabase Auth
-- 3. Substitua os placeholders abaixo e execute

-- Exemplo (substituir UUIDs reais):
/*
DO $$
DECLARE
  lucas_id UUID := 'UUID-DO-LUCAS-AQUI';
  leticia_id UUID := 'UUID-DA-LETICIA-AQUI';
  hoje DATE := CURRENT_DATE;
  mes_atual TEXT := TO_CHAR(CURRENT_DATE, 'YYYY-MM');
BEGIN
  -- Vincular casal
  INSERT INTO public.couple_links (user_a_id, user_b_id) VALUES (lucas_id, leticia_id);

  -- Transações de Lucas
  INSERT INTO public.transactions (user_id, type, valor, categoria, data, descricao, pagamento, owner, shared) VALUES
    (lucas_id, 'receita', 6500, 'Salário', hoje - 14, 'Salário Lucas', 'ted', 'me', false),
    (lucas_id, 'despesa', 320, 'Transporte', hoje - 10, 'Combustível', 'credito', 'me', false),
    (lucas_id, 'despesa', 199, 'Academia', hoje - 8, 'Mensalidade Academia', 'debito', 'me', false),
    (lucas_id, 'despesa', 1800, 'Aluguel', hoje - 12, 'Aluguel Apartamento', 'boleto', 'me', true),
    (lucas_id, 'despesa', 420, 'Alimentação', hoje - 5, 'Supermercado', 'debito', 'me', true),
    (lucas_id, 'despesa', 89.90, 'Lazer', hoje - 3, 'Netflix + Spotify', 'credito', 'me', true);

  -- Transações de Leticia
  INSERT INTO public.transactions (user_id, type, valor, categoria, data, descricao, pagamento, owner, shared) VALUES
    (leticia_id, 'receita', 5200, 'Salário', hoje - 14, 'Salário Leticia', 'ted', 'me', false),
    (leticia_id, 'despesa', 280, 'Saúde', hoje - 9, 'Farmácia', 'credito', 'me', false),
    (leticia_id, 'despesa', 450, 'Roupas', hoje - 6, 'Shopping', 'credito', 'me', false),
    (leticia_id, 'receita', 500, 'Freelance', hoje - 2, 'Trabalho Extra', 'pix', 'me', false);

  -- Boletos compartilhados (criados por Lucas)
  INSERT INTO public.bills (user_id, nome, valor, vencimento, frequencia, categoria, owner) VALUES
    (lucas_id, 'Aluguel', 1800, hoje + 5, 'mensal', 'Aluguel', 'shared'),
    (lucas_id, 'Internet', 120, hoje + 8, 'mensal', 'Tecnologia', 'shared'),
    (lucas_id, 'Energia', 185, hoje + 3, 'mensal', 'Outros', 'shared');

  -- Metas
  INSERT INTO public.goals (user_id, nome, valor_total, valor_atual, data_alvo, mensal, icone, shared) VALUES
    (lucas_id, 'Viagem Europa', 25000, 8500, hoje + 540, 1500, 'bi-airplane', true),
    (lucas_id, 'Reserva Emergência', 30000, 12000, hoje + 360, 2000, 'bi-shield-check', true);

  -- Orçamentos
  INSERT INTO public.budgets (user_id, categoria, valor_limite, mes, shared) VALUES
    (lucas_id, 'Alimentação', 1500, mes_atual, true),
    (lucas_id, 'Aluguel', 2000, mes_atual, true),
    (lucas_id, 'Transporte', 600, mes_atual, false),
    (lucas_id, 'Lazer', 500, mes_atual, true);

END $$;
*/
