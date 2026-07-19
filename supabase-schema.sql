-- ============================================================================
-- GYMPLUS - schema do banco de dados (Supabase / Postgres)
-- Rode este arquivo inteiro no SQL Editor do seu projeto Supabase.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- PROFILES (papel de cada usuário logado: admin / consultor / cliente)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','consultor','cliente')),
  full_name text not null default '',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- helper: verdadeiro se o usuário logado é admin ou consultor (equipe)
-- (security definer: roda sem RLS, evitando recursão da política de profiles
-- consultando a própria tabela profiles)
create or replace function public.is_staff()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('admin','consultor')
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

create policy "profiles_select_self_or_staff"
  on public.profiles for select
  using (id = auth.uid() or public.is_staff());

create policy "profiles_update_self"
  on public.profiles for update
  using (id = auth.uid());

-- ---------------------------------------------------------------------------
-- CLIENTS (cada cliente = um projeto/jornada)
-- ---------------------------------------------------------------------------
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  email text,
  whatsapp text,
  plan text not null default 'SOS Academias',
  week int not null default 1,
  total_weeks int not null default 12,
  atividade text not null default 'no_prazo' check (atividade in ('no_prazo','atrasado','prazo_encerrado')),
  financeiro text not null default 'em_dia' check (financeiro in ('em_dia','inadimplente','sem_contato')),
  progress int not null default 0,
  avatar_bg text not null default 'linear-gradient(135deg,#22c55e,#15803d)',
  start_date date not null default current_date,
  consultant text not null default 'Sandro Marcelino',
  valor text not null default 'R$ 2.400',
  vencimento text not null default '10/07',
  contract_link_sent boolean not null default false,
  cadastro_sent boolean not null default false,
  contract_approved boolean not null default false,
  cadastro jsonb not null default '{}'::jsonb,
  cadastro_token uuid not null default gen_random_uuid(),
  raiox jsonb not null default '{}'::jsonb,
  raiox_submitted_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.clients enable row level security;

create policy "clients_select_staff_or_own"
  on public.clients for select
  using (public.is_staff() or user_id = auth.uid());

create policy "clients_insert_staff"
  on public.clients for insert
  with check (public.is_staff());

create policy "clients_update_staff_or_own"
  on public.clients for update
  using (public.is_staff() or user_id = auth.uid());

create policy "clients_delete_staff"
  on public.clients for delete
  using (public.is_staff());

-- ---------------------------------------------------------------------------
-- PLAN_WEEKS (modelo padrão do plano de ação, compartilhado por todos os clientes)
-- ---------------------------------------------------------------------------
create table if not exists public.plan_weeks (
  id uuid primary key default gen_random_uuid(),
  num int not null,
  title text not null,
  detail text not null default '',
  channels jsonb not null default '["email","whats"]'::jsonb,
  form jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.plan_weeks enable row level security;

create policy "plan_weeks_select_authenticated"
  on public.plan_weeks for select
  using (auth.uid() is not null);

create policy "plan_weeks_write_staff"
  on public.plan_weeks for all
  using (public.is_staff())
  with check (public.is_staff());

-- ---------------------------------------------------------------------------
-- AUTOMATIONS (regras de disparo automático - admin)
-- ---------------------------------------------------------------------------
create table if not exists public.automations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon text not null default 'bolt',
  icon_bg text not null default '#dbeafe',
  icon_color text not null default '#1d4ed8',
  trigger_text text not null default '',
  cond_text text not null default '',
  channels jsonb not null default '["email"]'::jsonb,
  active boolean not null default true,
  runs_count int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.automations enable row level security;

create policy "automations_all_admin"
  on public.automations for all
  using (public.is_admin())
  with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- AUDITS (registros da pasta de auditoria de cada cliente)
-- ---------------------------------------------------------------------------
create table if not exists public.audits (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  tag text not null default 'Texto',
  tag_icon text not null default 'notes',
  tag_bg text not null default '#dbeafe',
  tag_color text not null default '#1d4ed8',
  author text not null default '',
  title text not null default '',
  body text,
  attachments jsonb not null default '[]'::jsonb,
  is_audio boolean not null default false,
  duration text,
  created_at timestamptz not null default now()
);

alter table public.audits enable row level security;

create policy "audits_select_staff_or_own_client"
  on public.audits for select
  using (
    public.is_staff()
    or exists (select 1 from public.clients c where c.id = audits.client_id and c.user_id = auth.uid())
  );

create policy "audits_insert_staff_or_own_client"
  on public.audits for insert
  with check (
    public.is_staff()
    or exists (select 1 from public.clients c where c.id = audits.client_id and c.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- NOTES (anotações manuais e resumos de reunião por cliente)
-- ---------------------------------------------------------------------------
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  kind text not null default 'note' check (kind in ('note','meeting')),
  title text not null default '',
  summary text not null default '',
  duration text,
  created_at timestamptz not null default now()
);

alter table public.notes enable row level security;

create policy "notes_select_staff_or_own_client"
  on public.notes for select
  using (
    public.is_staff()
    or exists (select 1 from public.clients c where c.id = notes.client_id and c.user_id = auth.uid())
  );

create policy "notes_insert_staff"
  on public.notes for insert
  with check (public.is_staff());

-- ---------------------------------------------------------------------------
-- COBRANCA_STEPS (régua de cobrança do financeiro - lista global)
-- ---------------------------------------------------------------------------
create table if not exists public.cobranca_steps (
  id uuid primary key default gen_random_uuid(),
  step text not null,
  when_text text not null default '',
  done boolean not null default false,
  sort_order int not null default 0
);

alter table public.cobranca_steps enable row level security;

create policy "cobranca_select_staff"
  on public.cobranca_steps for select
  using (public.is_staff());

create policy "cobranca_write_staff"
  on public.cobranca_steps for all
  using (public.is_staff())
  with check (public.is_staff());

-- ---------------------------------------------------------------------------
-- SCHEDULED_EMAILS (fila de e-mails com atraso — ex.: Raio-X 3 min após o login)
-- Só é lido/gravado pelas Edge Functions (via service role), por isso a
-- política abaixo só libera leitura para a equipe (não é usada pelo site).
-- ---------------------------------------------------------------------------
create table if not exists public.scheduled_emails (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  kind text not null,
  send_at timestamptz not null,
  sent boolean not null default false,
  sent_error text,
  created_at timestamptz not null default now()
);

alter table public.scheduled_emails enable row level security;

create policy "scheduled_emails_staff"
  on public.scheduled_emails for select
  using (public.is_staff());

-- ---------------------------------------------------------------------------
-- STORAGE (anexos enviados no formulário semanal e no Raio-X)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('evidencias', 'evidencias', false)
on conflict (id) do nothing;

create policy "evidencias_read_staff_or_own"
  on storage.objects for select
  using (
    bucket_id = 'evidencias'
    and (public.is_staff() or (storage.foldername(name))[1] = auth.uid()::text)
  );

create policy "evidencias_insert_authenticated"
  on storage.objects for insert
  with check (
    bucket_id = 'evidencias'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- SEED DATA — modelo padrão do plano de ação (12 semanas) e checklist de cobrança
-- ---------------------------------------------------------------------------
insert into public.plan_weeks (num, title, detail, channels, form)
select * from (values
  (1,'Diagnóstico inicial & metas','Mapeamento do processo atual e definição de metas.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (2,'Estruturação da oferta','Construção da oferta e proposta de valor.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (3,'Script de prospecção','Padronização da abordagem de prospecção.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (4,'Rotina comercial diária','Cadência e disciplina de execução diária.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (5,'Funil de qualificação','Critérios de qualificação de leads.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (6,'Objeções & follow-up','Tratamento de objeções e follow-up.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (7,'Fechamento consultivo','Condução do fechamento.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (8,'Métricas & indicadores','Definição dos indicadores de acompanhamento.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (9,'Delegação do processo','Transferência do conhecimento para o time.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (10,'Playbook do time','Documentação do playbook operacional.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (11,'Automação de rotina','Automação dos disparos e rotinas.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb),
  (12,'Auditoria final & escala','Revisão geral e plano de escala.','["email","whats"]'::jsonb,'[{"label":"Como você realizou a atividade?","type":"long"},{"label":"Anexe as evidências (prints, planilha, links)","type":"file"}]'::jsonb)
) as v(num,title,detail,channels,form)
where not exists (select 1 from public.plan_weeks);

insert into public.cobranca_steps (step, when_text, done, sort_order)
select * from (values
  ('1º lembrete via WhatsApp','D+1 do vencimento', true, 1),
  ('E-mail de cobrança formal','D+3 do vencimento', true, 2),
  ('Ligação do consultor','D+5 do vencimento', false, 3),
  ('Proposta de renegociação','D+7 do vencimento', false, 4),
  ('Suspensão de acesso','D+10 do vencimento', false, 5)
) as v(step,when_text,done,sort_order)
where not exists (select 1 from public.cobranca_steps);

insert into public.automations (name, icon, icon_bg, icon_color, trigger_text, cond_text, channels, active, runs_count)
select * from (values
  ('Disparo semanal da tarefa','event_repeat','#dbeafe','#1d4ed8','Toda sexta · 08:00','Semana anterior concluída','["email","whats"]'::jsonb, true, 128),
  ('Liberação por conclusão','lock_open','#dcfce7','#15803d','Ao enviar formulário','Formulário aprovado','["email"]'::jsonb, true, 96),
  ('Lembrete de atraso','notifications_active','#fef3c7','#b45309','D+3 sem conclusão','Atividade em aberto','["whats"]'::jsonb, true, 34),
  ('Cobrança de inadimplente','payments','#fee2e2','#b91c1c','D+1 do vencimento','Pagamento pendente','["email","whats"]'::jsonb, false, 12)
) as v(name,icon,icon_bg,icon_color,trigger_text,cond_text,channels,active,runs_count)
where not exists (select 1 from public.automations);

-- ---------------------------------------------------------------------------
-- Depois de rodar este script:
-- 1) Crie manualmente (Authentication > Users > Add user) os usuários
--    admin@suaempresa.com e consultor@suaempresa.com com senha.
-- 2) Rode, substituindo os e-mails/UUIDs, para dar o papel de cada um:
--
--    insert into public.profiles (id, role, full_name)
--    select id, 'admin', 'Admin GYMPLUS' from auth.users where email = 'admin@suaempresa.com';
--
--    insert into public.profiles (id, role, full_name)
--    select id, 'consultor', 'Sandro Marcelino' from auth.users where email = 'consultor@suaempresa.com';
--
-- Clientes recebem login automaticamente quando o admin usa "Adicionar cliente"
-- na plataforma (isso cria o usuário e o profile role='cliente' via Edge Function).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- AGENDAMENTO DO E-MAIL DO RAIO-X (roda a cada minuto, dispara os e-mails
-- cujo horário já chegou). Rode isto DEPOIS de publicar a Edge Function
-- "dispatch-scheduled-emails" — troque SEU-PROJETO e SUA_ANON_KEY pelos
-- valores do seu projeto (Project Settings > API).
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'dispatch-scheduled-emails',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://SEU-PROJETO.supabase.co/functions/v1/smart-api',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer SUA_ANON_KEY", "x-cron-secret": "SUA_CRON_SECRET"}'::jsonb,
    body := '{"action": "dispatch-scheduled-emails"}'::jsonb
  );
  $$
);

-- Para conferir se está rodando: select * from cron.job;
-- Para cancelar, se precisar: select cron.unschedule('dispatch-scheduled-emails');
