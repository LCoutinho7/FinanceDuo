# 💰 FinançasDuo v2 — Controle Financeiro Real do Casal

Sistema financeiro completo com **persistência real no Supabase**, sincronização em tempo real entre Lucas e Leticia, e dashboard consolidado do casal.

---

## 🏗️ Arquitetura

```
financasduo/
├── frontend/
│   └── index.html          # SPA completo (Bootstrap 5 + Chart.js)
├── services/
│   └── supabase.js         # Camada de serviços (referência/documentação)
├── database/
│   └── schema.sql          # Schema completo + RLS + funções SQL
├── vercel.json             # Config de deploy
└── README.md
```

### Stack
| Camada | Tecnologia |
|--------|-----------|
| Frontend | HTML + CSS + JavaScript (ES Modules) |
| CSS Framework | Bootstrap Icons + CSS customizado |
| Gráficos | Chart.js 4 |
| Backend/DB | **Supabase** (PostgreSQL + Auth + Realtime) |
| Deploy | Vercel (static) |

---

## 🚀 Setup em 5 passos

### 1. Criar projeto no Supabase

1. Acesse [supabase.com](https://supabase.com) → **New Project**
2. Escolha nome: `financasduo`
3. Defina uma senha forte para o banco
4. Aguarde o projeto inicializar (~2 min)

### 2. Executar o schema SQL

1. No painel do Supabase → **SQL Editor** → **New Query**
2. Cole o conteúdo completo de `database/schema.sql`
3. Clique em **Run** (⌘+Enter)
4. Verifique que as tabelas foram criadas em **Table Editor**

### 3. Configurar o frontend

Edite o arquivo `config.js` e substitua:

```javascript
window.SUPABASE_URL = 'https://SEU_PROJETO.supabase.co';
window.SUPABASE_ANON_KEY = 'SUA_ANON_KEY_AQUI';
```

Suas credenciais estão em:
**Supabase Dashboard → Settings → API**
- `Project URL` → SUPABASE_URL
- `anon public` key → SUPABASE_ANON_KEY

### 4. Criar contas de usuário

Antes de testar localmente, suba um servidor HTTP simples. Evite abrir o `index.html` direto via `file://`.

Exemplo:

```bash
python3 -m http.server 4173
```

Depois abra `http://localhost:4173`.

**Opção A: Via interface do app**
1. Abra o `index.html` no navegador
2. Clique em "Criar conta"
3. Crie conta para Lucas: `lucas@financasduo.com` / `Lucas2024!`
4. Crie conta para Leticia: `leticia@financasduo.com` / `Leticia2024!`

**Opção B: Via Supabase Dashboard**
→ Authentication → Users → Add User

### 5. Vincular o casal

1. Faça login como Lucas
2. No sidebar → clique em "Vincular"
3. Informe o e-mail de Leticia: `leticia@financasduo.com`
4. Pronto! Agora estão vinculados

---

## 🌐 Deploy na Vercel

```bash
# Opção 1: Via CLI
npm i -g vercel
vercel --prod

# Opção 2: Via GitHub
# 1. Push para um repositório GitHub
# 2. Acesse vercel.com/new
# 3. Importe o repositório
# 4. Deploy automático!
```

### Variáveis de ambiente na Vercel (opcional)
Se quiser evitar hardcode no HTML, use variáveis de ambiente:
```
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_ANON_KEY=sua-anon-key
```

---

## 🗄️ Modelagem de dados

### Tabelas principais

```sql
profiles        -- Usuários (extensão do auth.users)
  id, name, email, partner_id

couple_links    -- Vínculo bidirecional Lucas ↔ Leticia
  user_a_id, user_b_id

transactions    -- Receitas e despesas
  user_id, type, valor, categoria, data, descricao
  shared BOOLEAN  -- TRUE = visível para o casal

bills           -- Boletos / contas fixas
  user_id, nome, valor, vencimento, frequencia, pago

goals           -- Metas financeiras
  user_id, nome, valor_total, valor_atual, shared

budgets         -- Orçamentos mensais por categoria
  user_id, categoria, valor_limite, mes
```

### Regras de visibilidade (RLS)

| Transação | Lucas vê? | Leticia vê? |
|-----------|-----------|-------------|
| `shared=false`, dono=Lucas | ✅ | ❌ |
| `shared=false`, dono=Leticia | ❌ | ✅ |
| `shared=true`, dono=qualquer | ✅ | ✅ |
| Dashboard Casal | Tudo dos dois | Tudo dos dois |

---

## 🔄 Sincronização em tempo real

O Supabase Realtime é ativado automaticamente:

```
Lucas adiciona despesa → Supabase emite evento via WebSocket
→ Leticia recebe a atualização instantaneamente
→ Dashboard do casal atualiza sem refresh
```

O indicador de sync no sidebar mostra:
- 🟢 Verde pulsando = sincronizado em tempo real
- 🟡 Amarelo pulsando = atualizando
- 🔴 Vermelho = sem conexão

---

## ✨ Funcionalidades

### Individual vs Casal
| Feature | Individual | Casal |
|---------|-----------|-------|
| Saldo | Só suas transações + compartilhadas | Tudo dos dois |
| Gráfico pizza | Suas categorias | Categorias consolidadas |
| Gráfico linha | Evolução individual | Evolução consolidada |
| Gráfico barra | — | Lucas vs Leticia |

### Controle de permissões
- Cada usuário **só pode editar/excluir** suas próprias transações
- Transações do parceiro aparecem marcadas como "só leitura"
- Boletos criados por qualquer um são visíveis para o casal

### Indicadores visuais
- 🤝 **Compartilhada** = badge azul nas transações do casal
- 🔒 **Individual** = badge amarelo nas transações privadas
- Cor do avatar diferente: azul (você) vs pink/gold (parceiro)

---

## 🔧 Configuração do Supabase Realtime

Para garantir que o Realtime funcione, ative nas tabelas:

1. Supabase Dashboard → **Database** → **Replication**
2. Habilite para as tabelas: `transactions`, `bills`, `goals`
3. Ou execute:
```sql
ALTER TABLE public.transactions REPLICA IDENTITY FULL;
ALTER TABLE public.bills        REPLICA IDENTITY FULL;
ALTER TABLE public.goals        REPLICA IDENTITY FULL;
```

---

## 🔐 Segurança

- **Row Level Security (RLS)** ativo em todas as tabelas
- Usuários só acessam dados que têm permissão
- Chave `anon` é segura para o frontend (acesso limitado pelo RLS)
- Autenticação via Supabase Auth (JWT)
- Senhas hasheadas pelo Supabase (bcrypt)

---

## 🐛 Troubleshooting

**"Erro ao carregar dados"**
→ Verifique se SUPABASE_URL e SUPABASE_ANON_KEY estão corretos

**"Parceiro não encontrado"**
→ O parceiro precisa ter criado conta antes de vincular

**Realtime não atualiza**
→ Verifique se o Replication está ativado para as tabelas

**RLS bloqueando dados**
→ Execute o schema SQL novamente para recriar as policies

---

## 🔮 Melhorias futuras sugeridas

- [ ] Notificações push (Supabase Edge Functions)
- [ ] Importação de extrato bancário (OFX/CSV)
- [ ] Divisão automática de gastos (split)
- [ ] Relatório PDF (html2pdf.js)
- [ ] Autenticação Google/Apple
- [ ] App mobile (Capacitor.js)
