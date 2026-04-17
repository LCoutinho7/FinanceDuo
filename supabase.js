// ═══════════════════════════════════════════════════════════
// services/supabase.js
// Camada de serviços — toda comunicação com o Supabase
// ═══════════════════════════════════════════════════════════

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ── Config ────────────────────────────────────────────────
// Estas variáveis são substituídas pelo setup.js no frontend
export const supabase = createClient(
  window.SUPABASE_URL,
  window.SUPABASE_ANON_KEY
);

// ═══════════════════════════════════════
// AUTH SERVICE
// ═══════════════════════════════════════
export const AuthService = {
  async signUp({ email, password, name }) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { name } }
    });
    if (error) throw error;
    return data;
  },

  async signIn({ email, password }) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  },

  async signOut() {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  },

  async getSession() {
    const { data: { session } } = await supabase.auth.getSession();
    return session;
  },

  onAuthChange(callback) {
    return supabase.auth.onAuthStateChange(callback);
  }
};

// ═══════════════════════════════════════
// PROFILE SERVICE
// ═══════════════════════════════════════
export const ProfileService = {
  async getMe() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return null;
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();
    if (error) throw error;
    return data;
  },

  async getPartner(userId) {
    // Busca via couple_links
    const { data: link } = await supabase
      .from('couple_links')
      .select('user_a_id, user_b_id')
      .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`)
      .single();

    if (!link) return null;

    const partnerId = link.user_a_id === userId ? link.user_b_id : link.user_a_id;
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', partnerId)
      .single();
    if (error) return null;
    return data;
  },

  async linkPartner(myId, partnerEmail) {
    // Encontra o parceiro pelo email
    const { data: partner, error: findError } = await supabase
      .from('profiles')
      .select('id, name, email')
      .eq('email', partnerEmail)
      .single();

    if (findError || !partner) throw new Error('Parceiro(a) não encontrado. Verifique o e-mail.');
    if (partner.id === myId) throw new Error('Você não pode se vincular a si mesmo.');

    // Verifica se já existe vínculo
    const { data: existing } = await supabase
      .from('couple_links')
      .select('id')
      .or(`and(user_a_id.eq.${myId},user_b_id.eq.${partner.id}),and(user_a_id.eq.${partner.id},user_b_id.eq.${myId})`)
      .single();

    if (existing) throw new Error('Vocês já estão vinculados!');

    const { error } = await supabase
      .from('couple_links')
      .insert({ user_a_id: myId, user_b_id: partner.id });

    if (error) throw error;
    return partner;
  },

  async unlinkPartner(myId, partnerId) {
    const { error } = await supabase
      .from('couple_links')
      .delete()
      .or(`and(user_a_id.eq.${myId},user_b_id.eq.${partnerId}),and(user_a_id.eq.${partnerId},user_b_id.eq.${myId})`);
    if (error) throw error;
  },

  async update(updates) {
    const { data: { user } } = await supabase.auth.getUser();
    const { data, error } = await supabase
      .from('profiles')
      .update(updates)
      .eq('id', user.id)
      .select()
      .single();
    if (error) throw error;
    return data;
  }
};

// ═══════════════════════════════════════
// TRANSACTIONS SERVICE
// ═══════════════════════════════════════
export const TransactionService = {
  async getAll({ view = 'individual', partnerId = null, filters = {} } = {}) {
    const { data: { user } } = await supabase.auth.getUser();

    let query = supabase
      .from('transactions')
      .select(`
        *,
        profiles!transactions_user_id_fkey(id, name, email, avatar_color)
      `)
      .order('data', { ascending: false })
      .order('created_at', { ascending: false });

    // Filtros opcionais
    if (filters.startDate) query = query.gte('data', filters.startDate);
    if (filters.endDate)   query = query.lte('data', filters.endDate);
    if (filters.categoria) query = query.eq('categoria', filters.categoria);
    if (filters.type)      query = query.eq('type', filters.type);
    if (filters.owner)     query = query.eq('owner', filters.owner);
    if (filters.search)    query = query.ilike('descricao', `%${filters.search}%`);

    const { data, error } = await query;
    if (error) throw error;

    // Filtra no cliente baseado na view
    // (RLS já limita ao que o usuário pode ver)
    if (view === 'individual') {
      return (data || []).filter(t =>
        t.user_id === user.id || (t.shared && t.user_id === partnerId)
      );
    }
    // view === 'casal': retorna tudo (RLS já filtrou)
    return data || [];
  },

  async create(transaction) {
    const { data: { user } } = await supabase.auth.getUser();
    const { data, error } = await supabase
      .from('transactions')
      .insert({ ...transaction, user_id: user.id })
      .select(`*, profiles!transactions_user_id_fkey(id, name, avatar_color)`)
      .single();
    if (error) throw error;
    return data;
  },

  async update(id, updates) {
    const { data, error } = await supabase
      .from('transactions')
      .update(updates)
      .eq('id', id)
      .select(`*, profiles!transactions_user_id_fkey(id, name, avatar_color)`)
      .single();
    if (error) throw error;
    return data;
  },

  async delete(id) {
    const { error } = await supabase
      .from('transactions')
      .delete()
      .eq('id', id);
    if (error) throw error;
  },

  // Calcula estatísticas do dashboard no frontend
  // (complementar à função do banco)
  computeStats(transactions, userId, partnerId, mes) {
    const mesStr = mes || new Date().toISOString().substr(0, 7);
    const monthTxs = transactions.filter(t => t.data.startsWith(mesStr));

    const sum = (arr, type) => arr
      .filter(t => t.type === type)
      .reduce((s, t) => s + parseFloat(t.valor), 0);

    const saldo = transactions.reduce((s, t) =>
      t.type === 'receita' ? s + parseFloat(t.valor) : s - parseFloat(t.valor), 0);

    const myTxs = monthTxs.filter(t => t.user_id === userId);
    const partnerTxs = monthTxs.filter(t => t.user_id === partnerId);

    // Gastos por categoria
    const byCategoria = {};
    monthTxs.filter(t => t.type === 'despesa').forEach(t => {
      byCategoria[t.categoria] = (byCategoria[t.categoria] || 0) + parseFloat(t.valor);
    });

    // Evolução diária do saldo no mês
    const now = new Date();
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const dailySaldo = [];
    let running = transactions
      .filter(t => !t.data.startsWith(mesStr))
      .reduce((s, t) => t.type === 'receita' ? s + parseFloat(t.valor) : s - parseFloat(t.valor), 0);

    for (let d = 1; d <= Math.min(daysInMonth, now.getDate()); d++) {
      const dayStr = `${mesStr}-${String(d).padStart(2, '0')}`;
      transactions
        .filter(t => t.data === dayStr)
        .forEach(t => { running += t.type === 'receita' ? parseFloat(t.valor) : -parseFloat(t.valor); });
      dailySaldo.push({ day: d, saldo: running });
    }

    return {
      saldo,
      receitas_mes:     sum(monthTxs, 'receita'),
      despesas_mes:     sum(monthTxs, 'despesa'),
      economia_mes:     sum(monthTxs, 'receita') - sum(monthTxs, 'despesa'),
      me_receitas:      sum(myTxs, 'receita'),
      me_despesas:      sum(myTxs, 'despesa'),
      partner_receitas: sum(partnerTxs, 'receita'),
      partner_despesas: sum(partnerTxs, 'despesa'),
      by_categoria:     Object.entries(byCategoria).sort((a, b) => b[1] - a[1]),
      daily_saldo:      dailySaldo,
    };
  },

  subscribeToChanges(callback) {
    return supabase
      .channel('transactions-changes')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'transactions'
      }, callback)
      .subscribe();
  }
};

// ═══════════════════════════════════════
// BILLS SERVICE
// ═══════════════════════════════════════
export const BillService = {
  async getAll() {
    const { data, error } = await supabase
      .from('bills')
      .select(`*, profiles!bills_user_id_fkey(id, name)`)
      .order('vencimento', { ascending: true });
    if (error) throw error;
    return data || [];
  },

  async create(bill) {
    const { data: { user } } = await supabase.auth.getUser();
    const { data, error } = await supabase
      .from('bills')
      .insert({ ...bill, user_id: user.id })
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  async update(id, updates) {
    const { data, error } = await supabase
      .from('bills')
      .update(updates)
      .eq('id', id)
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  async markPaid(id) {
    return this.update(id, { pago: true, pago_em: new Date().toISOString() });
  },

  async markUnpaid(id) {
    return this.update(id, { pago: false, pago_em: null });
  },

  async delete(id) {
    const { error } = await supabase.from('bills').delete().eq('id', id);
    if (error) throw error;
  }
};

// ═══════════════════════════════════════
// GOALS SERVICE
// ═══════════════════════════════════════
export const GoalService = {
  async getAll() {
    const { data, error } = await supabase
      .from('goals')
      .select('*')
      .order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
  },

  async create(goal) {
    const { data: { user } } = await supabase.auth.getUser();
    const { data, error } = await supabase
      .from('goals')
      .insert({ ...goal, user_id: user.id })
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  async update(id, updates) {
    const { data, error } = await supabase
      .from('goals')
      .update(updates)
      .eq('id', id)
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  async aporte(id, valor) {
    const { data: goal } = await supabase
      .from('goals')
      .select('valor_atual, valor_total')
      .eq('id', id)
      .single();
    const novoValor = Math.min(goal.valor_total, parseFloat(goal.valor_atual) + parseFloat(valor));
    return this.update(id, { valor_atual: novoValor });
  },

  async delete(id) {
    const { error } = await supabase.from('goals').delete().eq('id', id);
    if (error) throw error;
  }
};

// ═══════════════════════════════════════
// BUDGET SERVICE
// ═══════════════════════════════════════
export const BudgetService = {
  async getByMonth(mes) {
    const monthStr = mes || new Date().toISOString().substr(0, 7);
    const { data, error } = await supabase
      .from('budgets')
      .select('*')
      .eq('mes', monthStr);
    if (error) throw error;
    return data || [];
  },

  async upsert(categoria, valorLimite, mes, shared = false) {
    const { data: { user } } = await supabase.auth.getUser();
    const monthStr = mes || new Date().toISOString().substr(0, 7);
    const { data, error } = await supabase
      .from('budgets')
      .upsert({
        user_id: user.id,
        categoria,
        valor_limite: valorLimite,
        mes: monthStr,
        shared
      }, { onConflict: 'user_id,categoria,mes' })
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  async delete(id) {
    const { error } = await supabase.from('budgets').delete().eq('id', id);
    if (error) throw error;
  }
};

// ═══════════════════════════════════════
// REALTIME SERVICE
// ═══════════════════════════════════════
export const RealtimeService = {
  channels: [],

  subscribe(table, callback) {
    const channel = supabase
      .channel(`realtime-${table}-${Date.now()}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table
      }, payload => callback(payload))
      .subscribe();
    this.channels.push(channel);
    return channel;
  },

  unsubscribeAll() {
    this.channels.forEach(ch => supabase.removeChannel(ch));
    this.channels = [];
  }
};
