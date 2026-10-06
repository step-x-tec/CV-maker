// Edge Function : cinetpay-webhook   (déployée avec verify_jwt = false, voir supabase/config.toml)
// CinetPay l'appelle de serveur à serveur. On NE FAIT PAS confiance au contenu reçu :
//  - la transaction doit exister dans notre table payments (créée par create-payment),
//  - son statut est revérifié directement auprès de CinetPay,
//  - le montant payé doit être égal au montant enregistré,
//  - le traitement est idempotent (un webhook rejoué n'active pas le plan deux fois).
// Secrets : CINETPAY_APIKEY, CINETPAY_SITE_ID  (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const env = (k: string) => Deno.env.get(k) ?? "";
const sb = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

Deno.serve(async (req: Request) => {
  try {
    let txId = "", siteId = "";
    const ct = req.headers.get("content-type") ?? "";
    if (ct.includes("application/json")) { const b = await req.json().catch(() => ({})); txId = b.cpm_trans_id ?? ""; siteId = b.cpm_site_id ?? ""; }
    else { const f = await req.formData().catch(() => null); txId = String(f?.get("cpm_trans_id") ?? ""); siteId = String(f?.get("cpm_site_id") ?? ""); }
    if (!txId) return new Response("ok", { status: 200 });            // ping de test CinetPay : on répond 200
    if (siteId && siteId !== env("CINETPAY_SITE_ID")) return new Response("site mismatch", { status: 400 });

    const { data: pay } = await sb.from("payments").select("*").eq("transaction_id", txId).maybeSingle();
    if (!pay) return new Response("unknown transaction", { status: 200 });   // pas de fuite d'information
    if (pay.status === "success") return new Response("already processed", { status: 200 });

    const check = await fetch("https://api-checkout.cinetpay.com/v2/payment/check", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ apikey: env("CINETPAY_APIKEY"), site_id: env("CINETPAY_SITE_ID"), transaction_id: txId }),
    });
    const r = await check.json().catch(() => ({}));
    const accepted = r.code === "00" && r.data?.status === "ACCEPTED";
    const paidAmount = Number(r.data?.amount);

    if (!accepted) {
      const failed = r.data?.status === "REFUSED" || r.code === "600";
      if (failed) await sb.from("payments").update({ status: "failed", payment_method: r.data?.payment_method ?? null }).eq("transaction_id", txId);
      return new Response("not accepted", { status: 200 });
    }
    if (paidAmount !== Number(pay.amount)) {
      await sb.from("payments").update({ status: "disputed", metadata: { ...pay.metadata, paid_amount: paidAmount } }).eq("transaction_id", txId);
      return new Response("amount mismatch", { status: 200 });
    }

    await sb.from("payments").update({ status: "success", paid_at: new Date().toISOString(), payment_method: r.data?.payment_method ?? null }).eq("transaction_id", txId);

    // Activation du plan (prolongation si le même plan est déjà actif)
    const months = pay.metadata?.period === "y" ? 12 : 1;
    const { data: prof } = await sb.from("profiles").select("plan, plan_expires_at").eq("id", pay.user_id).maybeSingle();
    const base = (prof?.plan === pay.plan && prof?.plan_expires_at && new Date(prof.plan_expires_at) > new Date()) ? new Date(prof.plan_expires_at) : new Date();
    base.setMonth(base.getMonth() + months);
    await sb.from("profiles").update({ plan: pay.plan, plan_activated_at: new Date().toISOString(), plan_expires_at: base.toISOString(), plan_tx_id: txId }).eq("id", pay.user_id);

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("cinetpay-webhook", e);
    return new Response("error", { status: 500 });   // CinetPay réessaiera
  }
});
