// Edge Function: create-client
//
// Cria o login do cliente (Supabase Auth) + a linha em public.clients,
// usando a service_role key (nunca exposta ao navegador). Só quem estiver
// logado como admin ou consultor pode chamar isso com sucesso.
//
// Deploy: supabase functions deploy create-client
// (ou cole este arquivo no Dashboard > Edge Functions > create-client > Deploy)

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";

    // Cliente "como o usuário que chamou" - respeita RLS, só serve pra checar o papel dele.
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "Não autenticado." }, 401);
    }

    const { data: profile, error: profileErr } = await callerClient
      .from("profiles")
      .select("role")
      .eq("id", userData.user.id)
      .single();
    if (profileErr || !profile || !["admin", "consultor"].includes(profile.role)) {
      return json({ error: "Sem permissão para criar clientes." }, 403);
    }

    const body = await req.json();
    const { name, email, plan, consultant, valor, vencimento, financeiro } = body ?? {};
    if (!name || !email) {
      return json({ error: "Nome e e-mail são obrigatórios." }, 400);
    }

    // Cliente com privilégio total - só usado a partir daqui, dentro da function.
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const tempPassword = crypto.randomUUID().slice(0, 12);

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: { full_name: name, role: "cliente" },
    });
    if (createErr || !created?.user) {
      return json({ error: createErr?.message || "Falha ao criar usuário." }, 400);
    }

    const newUserId = created.user.id;

    const { error: profileInsertErr } = await admin
      .from("profiles")
      .insert({ id: newUserId, role: "cliente", full_name: name });
    if (profileInsertErr) {
      return json({ error: profileInsertErr.message }, 400);
    }

    const { data: clientRow, error: clientErr } = await admin
      .from("clients")
      .insert({
        user_id: newUserId,
        name,
        email,
        plan: plan || "SOS Academias",
        consultant: consultant || "Sandro Marcelino",
        valor: valor || "R$ 2.400",
        vencimento: vencimento || "10/07",
        financeiro: financeiro || "em_dia",
      })
      .select()
      .single();
    if (clientErr) {
      return json({ error: clientErr.message }, 400);
    }

    // Tenta mandar um link de redefinição de senha por e-mail (usa o serviço
    // de e-mail padrão do Supabase). Se falhar, devolvemos a senha temporária
    // para o admin repassar manualmente ao cliente.
    let inviteSent = false;
    try {
      const { error: resetErr } = await admin.auth.resetPasswordForEmail(email);
      inviteSent = !resetErr;
    } catch (_e) {
      inviteSent = false;
    }

    return json({ client: clientRow, tempPassword, inviteSent });
  } catch (e) {
    return json({ error: String(e?.message || e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
