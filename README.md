# Mindora — Ebook Store MVP

A premium long-scroll ebook storefront built with HTML, CSS and vanilla JavaScript, with Supabase PostgreSQL for products/orders and a secure UPI + UTR confirmation workflow.

## 1. Frontend

Open `index.html` locally for the visual UI. For production, serve the folder from a static host.

Edit `js/config.js`:

```js
window.MINDORA_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR_SUPABASE_ANON_KEY',
  UPI_ID: 'yourupi@bank',
  CURRENCY_SYMBOL: '₹'
};
```

Do not put the Supabase service-role key in the frontend.

## 2. Supabase

1. Create a Supabase project.
2. Run `supabase/schema.sql` in SQL Editor.
3. Create a private Storage bucket named `mindora-private` (the schema creates it too; confirm it is **not public**).
4. Upload the full ebook to `ebooks/the-ai-advantage.pdf`.
5. Optionally create a public bucket for cover/preview assets.
6. Create an admin user in Supabase Auth.
7. Insert that user's UUID into `admin_users`.

Example:

```sql
insert into public.admin_users(id,email,role)
values ('AUTH_USER_UUID','your-admin-email@example.com','admin');
```

## 3. UPI

Set your actual UPI ID in `js/config.js`.

For a QR image, add your QR as `assets/upi-qr.png` and replace the placeholder in `index.html` with an `<img>` tag. The UPI ID is safe to display publicly; never expose bank login credentials or Supabase service-role credentials.

## 4. Payment verification and protected ebook delivery

UPI payments made directly to a UPI ID cannot be verified automatically from a static website. The customer submits a UTR; the order remains `payment_submitted` until you match it in your bank/UPI app and approve it in `admin.html`.

Approval creates a 32-byte delivery secret. The database stores only its SHA-256 hash. The admin receives a private `download.html#token=…` link to send to the buyer; it expires after 7 days. Opening it creates a signed Storage URL valid for only 10 minutes. The ebook bucket stays private and is never linked from the public storefront.

Deploy both Edge Functions after configuring your project and secrets:

```bash
supabase secrets set SITE_URL=https://YOUR-RENDER-SITE.onrender.com
supabase functions deploy verify-payment
supabase functions deploy download-ebook
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are supplied to hosted Edge Functions by Supabase. Never add the service-role key to `js/config.js`, Render, or Git.

If you already installed the older schema, run `supabase/migrations/20261004_secure_delivery.sql` once in the Supabase SQL Editor instead of rerunning the destructive schema.

## 5. Deploy the website on Render

1. Put this folder in a GitHub repository and create a **Static Site** in Render from it. `render.yaml` is included, so Render should detect the settings automatically.
2. Use `.` as the publish directory and leave the build command empty if entering the settings manually.
3. Before deployment, replace `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `js/config.js`. The anon key is designed to be public; protection comes from RLS and the private bucket.
4. Deploy once to get the Render URL. Set that exact HTTPS URL as the `SITE_URL` secret above, then redeploy `verify-payment`.
5. Add the Render site URL to Supabase Authentication → URL Configuration → Site URL and Redirect URLs. This lets the admin sign-in flow work correctly.

The frontend is a static Render site. Payments, permissions, and ebook signing stay in Supabase Edge Functions—not in Render—so no payment secret is exposed in the browser.

## 6. Important launch checklist

- Replace placeholder UPI ID.
- Replace placeholder Supabase URL/key.
- Upload the real ebook to private storage.
- Add the real UPI QR.
- Replace the starter refund policy with your final policy.
- Test a real low-value payment before public launch.
- Verify that private ebook files cannot be opened without a signed URL.
- Test one purchase end to end: order → UTR → admin approval → buyer delivery link → download.
- For automatic UPI confirmation, replace the manual UTR flow with a regulated payment gateway such as Razorpay or Cashfree and verify its webhook signature in a server-side function. Do not mark an order paid from browser-provided payment data.
- A buyer can still share a PDF after downloading it; no website can completely prevent that. Add a purchaser watermark/terms if that risk matters.

## 6. Brand

Mindora — Ideas worth knowing.

Featured book: The AI Advantage — AI + Career + Personal Productivity.

## 7. Admin dashboard

Open `admin.html` after configuring Supabase. Sign in with the admin Auth account. The dashboard reads pending orders through RLS and calls the `verify-payment` Edge Function for verification. The function requires the admin user's UUID to exist in `admin_users` and uses the service-role key only on the server.

The dashboard returns a one-time delivery page URL after approval. Send it only to the purchaser. For a polished production launch, connect that event to an email provider so the link is delivered automatically.
