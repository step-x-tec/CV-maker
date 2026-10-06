// Edge Function : create-payment
// Crée une transaction CinetPay pour l'UTILISATEUR CONNECTÉ (identité lue dans son JWT, jamais dans le corps de la requête).
// Secrets requis :  CINETPAY_APIKEY, CINETPAY_SITE_ID, SITE_URL (ex: https://smartcv.netlify.app)
// Optionnels     :  CINETPAY_CHANNELS (défaut MOBILE_MONEY ; "ALL" ajoute la carte bancaire), ALLOWED_ORIGINS (liste séparée par des virgules)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const env = (k: string) => Deno.env.get(k) ?? "";
const SITE_URL = env("SITE_URL").replace(/\/$/, "");
const ORIGINS = [SITE_URL, ...env("ALLOWED_ORIGINS").split(",").map((s) => s.trim().replace(/\/$/, ""))].filter(Boolean);
const PRICES: Record<string, number> = { starter: 1000, premium: 2500, pro: 5000 };
const CHANNELS = env("CINETPAY_CHANNELS") || "MOBILE_MONEY";

function cors(req: Request) {
  const origin = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(origin) ? origin : ORIGINS[0] ?? "",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (req: Request, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Méthode non autorisée" }, 405);
  if (!env("CINETPAY_APIKEY") || !env("CINETPAY_SITE_ID") || !SITE_URL) {
    return json(req, { error: "Paiement non configuré côté serveur" }, 500);
  }

  // 1. Identité : on valide le JWT de l'utilisateur
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const sbUser = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: { user }, error: authErr } = await sbUser.auth.getUser(token);
  if (authErr || !user) return json(req, { error: "Non authentifié" }, 401);

  // 2. Entrées validées
  let body: { plan?: string; period?: string } = {};
  try { body = await req.json(); } catch { /* corps vide */ }
  const plan = String(body.plan ?? "");
  const period = body.period === "y" ? "y" : "m";
  const monthly = PRICES[plan];
  if (!monthly) return json(req, { error: "Plan inconnu" }, 400);
  const amount = period === "y" ? Math.round(monthly * 12 * 0.8) : monthly;
  const transactionId = "SC" + Date.now().toString(36).toUpperCase() + Math.random().toString(36).slice(2, 6).toUpperCase();

  // 3. Ligne "pending" (source de vérité du montant, lue plus tard par le webhook)
  const sbAdmin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
  const { error: insErr } = await sbAdmin.from("payments").insert({
    transaction_id: transactionId, user_id: user.id, plan, amount, currency: "XOF",
    status: "pending", provider: "cinetpay", metadata: { period },
  });
  if (insErr) return json(req, { error: "Enregistrement du paiement impossible", detail: insErr.message }, 500);

  // 4. Création de la page de paiement CinetPay
  const payload: Record<string, unknown> = {
    apikey: env("CINETPAY_APIKEY"), site_id: env("CINETPAY_SITE_ID"),
    transaction_id: transactionId, amount, currency: "XOF", lang: "fr", channels: CHANNELS,
    description: `Abonnement SmartCV ${plan} ${period === "y" ? "annuel" : "mensuel"}`,
    notify_url: `${env("SUPABASE_URL")}/functions/v1/cinetpay-webhook`,
    return_url: `${SITE_URL}/app/?payment=return&tx=${transactionId}`,
    metadata: user.id,
  };
  if (CHANNELS.includes("ALL") || CHANNELS.includes("CREDIT_CARD")) {
    Object.assign(payload, { customer_id: user.id, customer_name: "Client", customer_surname: "SmartCV", customer_email: user.email ?? "",
      customer_phone_number: "+22500000000", customer_address: "N/A", customer_city: "N/A", customer_country: "CI", customer_state: "CI", customer_zip_code: "00000" });
  }
  const res = await fetch("https://api-checkout.cinetpay.com/v2/payment", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
  const data = await res.json().catch(() => ({}));
  if (data.code !== "201" || !data.data?.payment_url) {
    await sbAdmin.from("payments").update({ status: "failed", metadata: { period, error: data } }).eq("transaction_id", transactionId);
    return json(req, { error: "CinetPay a refusé la création du paiement", detail: data.message ?? data.description ?? null }, 502);
  }
  await sbAdmin.from("payments").update({ provider_ref: data.data.payment_token ?? null }).eq("transaction_id", transactionId);
  return json(req, { payment_url: data.data.payment_url, transaction_id: transactionId });
});
