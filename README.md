[README.md](https://github.com/user-attachments/files/30282673/README.md)
# GYMPLUS · Plataforma

Plataforma de acompanhamento de clientes (jornada semanal, financeiro,
automações e auditoria) para consultoria/mentoria de academias.

Este repositório contém:
- **Frontend** completo em `index.html` (visual idêntico ao protótipo original).
- **Backend real** usando [Supabase](https://supabase.com): banco de dados
  Postgres, autenticação (login admin / consultor / cliente) e uma Edge
  Function para criar o login de cada cliente com segurança.

Antes só existia a tela pronta, sem dados de verdade (tudo era fixo no
código e sumia ao recarregar a página, sem login real). Agora todos os
dados são gravados no banco e o login é de verdade.

## O que já funciona de ponta a ponta

- Login real por e-mail/senha, com 3 papéis: **admin**, **consultor** e **cliente**.
- Jornada semanal, plano de ação (editável pelo admin), progresso, status de atividade/financeiro.
- Formulário semanal do cliente (com upload de evidências) — libera a próxima semana automaticamente.
- Automações (regras de disparo) — criar, ativar/desativar.
- Financeiro (situação por cliente + checklist de cobrança).
- Auditoria (pasta por cliente com o histórico de formulários e anotações).

### Fluxo completo de onboarding do cliente

1. **Admin cadastra o cliente** (nome, e-mail, WhatsApp, plano, consultor). A
   plataforma manda um e-mail com um link **público** (sem precisar de
   login) para o cliente preencher os dados do contrato (responsável
   legal, CPF, nome/CNPJ da academia, endereço, cargo, etc.).
2. O cliente preenche o link e os dados aparecem, em modo somente
   leitura, no card "Dados para o contrato" na página do projeto do
   cliente (visão do admin/consultor).
3. Seu time gera o contrato manualmente (fora da plataforma) com esses
   dados. Depois de assinado, o admin clica em **"Aprovar contrato"**.
4. **3 minutos depois** (atraso real, não simulado), o cliente recebe por
   e-mail o link — também **público, sem precisar de login** — do
   **formulário de Raio-X** (diagnóstico de marketing, vendas e evasão
   do negócio, com upload de arquivos).
5. Assim que o cliente envia o Raio-X, a plataforma cria o login dele na
   hora e manda por e-mail o usuário e a senha de acesso.
6. Com os dados do Raio-X, o consultor/admin abre o **Diagnóstico**
   (visão só interna, nunca enviada ao cliente automaticamente) e, se
   quiser, pode **baixar um relatório em HTML** e/ou **mandar um PDF por
   e-mail ao cliente** com os pontos de melhoria, para usar na reunião
   de onboarding.
7. A partir daí segue a jornada semanal normal: cada tarefa só libera a
   próxima depois que o cliente preenche o formulário da semana atual.

Etapas 1-3 (contrato) e 4-5 (Raio-X → acesso) ficam com título e
descrição editáveis pelo admin em **Plano de Ação**, antes da lista de
semanas — a mudança aparece automaticamente na timeline de onboarding
do cliente e do admin/consultor.

## O que **não** é real (fica para uma próxima etapa, se quiser)

- **Envio de WhatsApp**: os botões existem na tela, mas nenhum provedor
  (ex.: API do WhatsApp Business) está conectado ainda.
- **Importar reunião do Google Meet**: é só uma simulação visual (não puxa
  transcrição real).
- Ícone "Pix" na ficha de contrato usa um nome de ícone que a fonte de
  ícones do Google não possui — aparece como texto em vez de um ícone.
- Os anexos do formulário público de Raio-X (planilhas, prints) viajam
  como texto (base64) dentro da mesma chamada que salva o formulário —
  funciona bem para arquivos pequenos/médios (poucos MB), mas não é
  indicado para arquivos grandes (vídeos, PDFs muito pesados).

---

## Passo a passo para colocar no ar

### 1. Criar o projeto no Supabase

1. Crie uma conta gratuita em https://supabase.com e clique em **New project**.
2. Depois de criado, vá em **SQL Editor**, abra o arquivo
   [`supabase-schema.sql`](supabase-schema.sql) deste repositório, cole o
   conteúdo inteiro e clique em **Run**. Isso cria todas as tabelas, as
   regras de segurança (RLS) e os dados iniciais (plano de 12 semanas,
   checklist de cobrança e automações padrão).

> **Já tem um projeto Supabase rodando de antes?** Não precisa rodar o
> `supabase-schema.sql` inteiro de novo (ele é seguro rodar de novo, mas
> não é necessário). Basta rodar só o trecho abaixo no **SQL Editor**,
> que adiciona o que falta para o fluxo de onboarding novo:
> ```sql
> alter table public.clients add column if not exists cadastro_token uuid not null default gen_random_uuid();
> alter table public.clients add column if not exists raiox jsonb not null default '{}'::jsonb;
> alter table public.clients add column if not exists raiox_token uuid not null default gen_random_uuid();
> alter table public.clients add column if not exists raiox_submitted_at timestamptz;
> alter table public.clients add column if not exists diagnostico_sent_at timestamptz;
>
> create table if not exists public.scheduled_emails (
>   id uuid primary key default gen_random_uuid(),
>   client_id uuid not null references public.clients(id) on delete cascade,
>   kind text not null,
>   send_at timestamptz not null,
>   sent boolean not null default false,
>   sent_error text,
>   created_at timestamptz not null default now()
> );
> alter table public.scheduled_emails enable row level security;
> create policy "scheduled_emails_staff" on public.scheduled_emails for select using (public.is_staff());
>
> create table if not exists public.onboarding_steps (
>   id uuid primary key default gen_random_uuid(),
>   step_key text not null unique,
>   num int not null,
>   title text not null,
>   detail text not null default '',
>   created_at timestamptz not null default now()
> );
> alter table public.onboarding_steps enable row level security;
> create policy "onboarding_steps_select_authenticated" on public.onboarding_steps for select using (auth.uid() is not null);
> create policy "onboarding_steps_write_staff" on public.onboarding_steps for all using (public.is_staff()) with check (public.is_staff());
>
> insert into public.onboarding_steps (step_key, num, title, detail)
> select * from (values
>   ('contrato', 1, 'Assinatura do contrato', 'Cliente preenche os dados, nosso time gera o contrato manualmente e o consultor valida a assinatura.'),
>   ('raiox', 2, 'Formulário de Raio-X', 'Diagnóstico do negócio (marketing, vendas e evasão), enviado por e-mail (link público, sem precisar logar) 3 minutos após a aprovação do contrato. Ao enviar, o cliente recebe o acesso à plataforma.'),
>   ('reuniao', 3, 'Reunião de onboarding', 'Apresentação do Raio-X e alinhamento com o consultor antes de começar o plano semanal.')
> ) as v(step_key, num, title, detail)
> where not exists (select 1 from public.onboarding_steps);
> ```
> Depois disso, siga o passo 3 (Edge Function, com o código **novo** —
> se você já tinha publicado antes, é preciso colar o código atualizado
> por cima) e o passo "Agendar o e-mail do Raio-X (pg_cron)" mais abaixo.
> Se o `pg_cron` já estava configurado de uma versão anterior, não
> precisa mexer nele — o job continua funcionando igual, só o conteúdo
> do e-mail que ele dispara mudou (agora manda o link público do Raio-X).

### 2. Criar os usuários admin e consultor

1. No Supabase, vá em **Authentication > Users > Add user** e crie um
   usuário para o admin (ex.: `admin@suaempresa.com`) e outro para o
   consultor, com senha.
2. Volte ao **SQL Editor** e rode (trocando os e-mails):
   ```sql
   insert into public.profiles (id, role, full_name)
   select id, 'admin', 'Admin GYMPLUS' from auth.users where email = 'admin@suaempresa.com';

   insert into public.profiles (id, role, full_name)
   select id, 'consultor', 'Sandro Marcelino' from auth.users where email = 'consultor@suaempresa.com';
   ```
   Sem essa linha o usuário consegue logar mas o sistema não sabe qual é o papel dele.

Clientes **não** precisam ser criados manualmente — isso acontece
automaticamente quando o admin usa "Adicionar cliente" dentro da própria
plataforma (passo 4).

### 3. Publicar a Edge Function (cria o login do cliente)

Essa função roda no servidor do Supabase (não no navegador) porque
precisa de uma chave privilegiada para criar logins — por isso não dá
para fazer isso só com HTML/JS no navegador.

Forma mais simples (sem instalar nada):
1. No painel do Supabase, vá em **Edge Functions > Create a new function**, nomeie como `create-client`.
2. Abra [`supabase-edge-function-create-client.ts`](supabase-edge-function-create-client.ts) deste repositório, copie todo o conteúdo e cole no editor do Supabase.
3. Clique em **Deploy**.

(Se preferir usar a CLI do Supabase: `supabase functions deploy create-client`.)

A função já usa `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY`, que o
Supabase disponibiliza automaticamente para toda Edge Function — não
precisa configurar nada extra.

**Importante:** o nome que aparece na tela do Supabase é só um rótulo —
o endereço de verdade da função é o que aparece na **URL** dela (ex.:
`.../functions/v1/smart-api`). O front-end (`index.html`) chama a função
pelo nome que estiver depois de `/v1/` na URL — confira se bate com o
que está em `sb.functions.invoke('...')` no arquivo.

#### E-mails automáticos (link do contrato, Raio-X, login do cliente)

A plataforma manda três e-mails automáticos ao longo do onboarding: (1)
link do formulário de contrato ao cadastrar o cliente, (2) link do
formulário de Raio-X 3 minutos depois que o admin aprova o contrato, e
(3) login e senha de acesso assim que o cliente envia o Raio-X. Depois,
o consultor ainda pode mandar manualmente um quarto e-mail com o PDF do
diagnóstico (botão "Enviar PDF ao cliente" na tela de Diagnóstico).
Todos saem pelo Gmail. Para ativar:

1. Na conta do Gmail que vai enviar os e-mails, ative a **verificação em
   duas etapas** (Conta Google → Segurança).
2. Ainda em Segurança, procure **Senhas de app** (App passwords) e crie
   uma nova senha de app (escolha qualquer nome, ex.: "GYMPLUS").
   Copie o código de 16 letras gerado.
3. No Supabase, vá em **Edge Functions** → abra a função → aba
   **Settings** (ou **Secrets** / "Manage secrets", dependendo da versão
   do painel) e adicione as variáveis:
   - `GMAIL_USER` = o e-mail que envia (ex.: `ssolucoesempresariais4@gmail.com`)
   - `GMAIL_APP_PASSWORD` = a senha de app de 16 letras do passo 2 (sem espaços)
   - `SITE_URL` (opcional) = o link de produção do site, ex.:
     `https://gymplusentrega.vercel.app` (usado nos e-mails). Se não
     configurar, usa esse valor como padrão.
   - `CRON_SECRET` (opcional, mas recomendado) = uma senha qualquer,
     inventada por você, só para proteger o agendamento do e-mail do
     Raio-X (explicado a seguir). Sem essa variável o agendamento ainda
     funciona, só fica sem essa proteção extra.
4. Sem precisar reimplantar nada — na próxima vez que um cliente for
   cadastrado/aprovado, os e-mails já saem automaticamente.

Se essas variáveis não estiverem configuradas, o cliente ainda é criado
normalmente; só o e-mail não é enviado (a plataforma avisa isso na tela
e mostra a senha temporária para você repassar manualmente).

#### Agendar o e-mail do Raio-X (pg_cron)

O e-mail com o link do formulário de Raio-X é enviado **exatos 3
minutos** depois que o admin aprova o contrato (atraso real, não
simulado). Isso é feito com uma tarefa agendada (`pg_cron`) que roda a
cada minuto e dispara os e-mails cujo horário já chegou. Depois de
publicar a Edge Function (passo acima), rode no **SQL Editor**
(trocando `SEU-PROJETO`, `SUA_ANON_KEY` e `SUA_CRON_SECRET` pelos
valores do seu projeto — Project Settings > API — e pelo valor que você
escolheu para `CRON_SECRET`, se configurou um):

```sql
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
```

Para conferir se está rodando: `select * from cron.job;`
Para cancelar, se precisar: `select cron.unschedule('dispatch-scheduled-emails');`

Se você não configurou `CRON_SECRET` no passo anterior, pode deixar o
header `x-cron-secret` de fora (ou com qualquer valor) — a função só
recusa a chamada quando o segredo está configurado e não bate.

### 4. Conectar o site ao seu projeto Supabase

1. No Supabase, vá em **Project Settings > API**.
2. Copie a **Project URL** e a chave **anon public**.
3. Abra o arquivo [`config.js`](config.js) deste repositório e cole os dois valores:
   ```js
   window.GYMPLUS_CONFIG = {
     url: 'https://SEU-PROJETO.supabase.co',
     anonKey: 'sua-anon-key-aqui',
   };
   ```
   A anon key é pública por natureza (protegida pelas regras RLS do banco
   — o segredo de verdade, a service role key, só fica no servidor da
   Edge Function). Ainda assim, evite compartilhar a URL do projeto
   publicamente sem necessidade.

### 5. Subir para o GitHub

```bash
git add .
git commit -m "Configura Supabase"
git push
```

### 6. Colocar o site no ar

Este é um site 100% estático (HTML puro, sem servidor Node por trás) —
o "back-end" inteiro roda no Supabase. Então qualquer hospedagem de
arquivo estático serve, por exemplo:

- **GitHub Pages**: no repositório do GitHub, vá em *Settings > Pages*,
  escolha a branch e a pasta raiz. Pronto, o link fica disponível em
  poucos minutos.
- Ou Netlify / Vercel / Cloudflare Pages, arrastando a pasta do projeto.

Depois de publicado, acesse o link e entre com o e-mail/senha do admin
ou consultor criados no passo 2.

---

## Testando localmente antes de publicar

Não precisa de Node nem de build — é só abrir com qualquer servidor
estático simples, por exemplo:

```bash
python3 -m http.server 8000
```

E acessar `http://localhost:8000/index.html`.

## Estrutura do projeto

```
index.html                              → todo o front-end (visual + lógica)
config.js                               → URL e anon key do Supabase (edite aqui)
dc-runtime.js, react*.js, supabase.js    → bibliotecas usadas pela página — não precisa mexer
html2pdf.bundle.min.js                  → gera o PDF do diagnóstico no navegador (botão "Enviar PDF ao cliente") — não precisa mexer
supabase-schema.sql                     → tabelas, permissões e dados iniciais do banco (rodar no SQL Editor do Supabase)
supabase-edge-function-create-client.ts → função com todas as ações do backend (colar no Edge Functions do Supabase)
```
