// Edge Function OPTIONNELLE : ai-chat
// L'application utilise par défaut son moteur IA local (aucune API). Cette fonction ne sert que si vous voulez
// brancher plus tard un vrai modèle hébergé (GROQ) sans jamais exposer la clé dans le navigateur.
// Secrets : GROQ_API_KEY, SITE_URL   —   JWT utilisateur obligatoire (verify_jwt = true) + quota via consume_ai_request.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const env = (k: string) => Deno.env.get(k) ?? "";
const SITE_URL = env("SITE_URL").replace(/\/$/, "");
const cors = { "Access-Control-Allow-Origin": SITE_URL, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const SYSTEM = "Tu es un expert RH et coach carrière spécialisé en Afrique francophone. Réponds en français, de façon concise et pratique.";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const sbUser = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: { user } } = await sbUser.auth.getUser(token);
  if (!user) return json({ error: "Non authentifié" }, 401);
  const { data: quota } = await sbUser.rpc("consume_ai_request", { p_user_id: user.id });
  if (quota?.error) return json({ error: quota.error, quota }, 429);

  const { messages } = await req.json().catch(() => ({ messages: [] }));
  if (!Array.isArray(messages) || !messages.length || JSON.stringify(messages).length > 12000) return json({ error: "messages invalides" }, 400);
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${env("GROQ_API_KEY")}` },
    body: JSON.stringify({ model: "llama-3.3-70b-versatile", messages: [{ role: "system", content: SYSTEM }, ...messages], temperature: 0.6, max_tokens: 1000 }),
  });
  if (!res.ok) return json({ error: "Erreur du fournisseur IA" }, 502);
  const data = await res.json();
  return json({ reply: data.choices?.[0]?.message?.content ?? "" });
});
