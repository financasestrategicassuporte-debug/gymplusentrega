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
- Cadastro de clientes (cria automaticamente o login do cliente).
- Jornada semanal, plano de ação (editável pelo admin), progresso, status de atividade/financeiro.
- Formulário semanal do cliente (com upload de evidências) — libera a próxima semana automaticamente.
- Ficha de contrato (link de cadastro, dados da empresa e pagamento).
- Automações (regras de disparo) — criar, ativar/desativar.
- Financeiro (situação por cliente + checklist de cobrança).
- Auditoria (pasta por cliente com o histórico de formulários e anotações).

## O que **não** é real (fica para uma próxima etapa, se quiser)

- **Envio de e-mail/WhatsApp**: os botões existem na tela, mas nenhum
  provedor de envio (ex.: um serviço de e-mail, ou a API do WhatsApp) está
  conectado ainda. Hoje nada é disparado de verdade.
- **Importar reunião do Google Meet**: é só uma simulação visual (não puxa
  transcrição real).
- Ícone "Pix" na ficha de contrato usa um nome de ícone que a fonte de
  ícones do Google não possui — aparece como texto em vez de um ícone.

---

## Passo a passo para colocar no ar

### 1. Criar o projeto no Supabase

1. Crie uma conta gratuita em https://supabase.com e clique em **New project**.
2. Depois de criado, vá em **SQL Editor**, abra o arquivo
   [`supabase-schema.sql`](supabase-schema.sql) deste repositório, cole o
   conteúdo inteiro e clique em **Run**. Isso cria todas as tabelas, as
   regras de segurança (RLS) e os dados iniciais (plano de 12 semanas,
   checklist de cobrança e automações padrão).

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
supabase-schema.sql                     → tabelas, permissões e dados iniciais do banco (rodar no SQL Editor do Supabase)
supabase-edge-function-create-client.ts → função que cria o login de cada cliente novo (colar no Edge Functions do Supabase)
```
