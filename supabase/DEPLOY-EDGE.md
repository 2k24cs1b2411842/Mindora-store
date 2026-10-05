# Deploy secure ebook download (required once)

Buyers open **`download.html`** on your live site, enter their **Order ID** (e.g. `MN-20261005-303EAE`) and **checkout email**. The page calls the **`download-ebook`** Edge Function, which:

1. Confirms the order is **verified** and the email matches.
2. Confirms download access is still within the **7-day** window.
3. Returns a **signed URL** to the PDF in the private `mindora-private` bucket (valid ~10 minutes).

The PDF is never linked from the public storefront.

## 1. Host the static site

Deploy this folder to Render (or similar) so you have a public HTTPS URL, for example:

`https://mindora-store.onrender.com`

Set that exact URL in **`js/config.js`**:

```js
SITE_URL: 'https://mindora-store.onrender.com',
```

Redeploy the site after changing config.

## 2. Deploy `download-ebook`

From this project folder (with [Supabase CLI](https://supabase.com/docs/guides/cli) installed and logged in):

```bash
supabase link --project-ref wmhskjxanbwsewblqahq
supabase functions deploy download-ebook --no-verify-jwt
```

Supabase injects `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` automatically.

Or in the **Supabase Dashboard**: Edge Functions → create function **`download-ebook`** → paste `supabase/functions/download-ebook/index.ts` → deploy with JWT verification **off** (the function validates the download token itself).

## 3. Upload the ebook

Storage → bucket **`mindora-private`** → upload your PDF at the path stored in `books.file_path` (default seed uses `ebooks/the-ai-advantage.pdf`).

## 4. Run SQL migrations (if not already)

In SQL Editor, run (in order):

- `supabase/migrations/20261005_fix_approve_payment_collision.sql`
- `supabase/migrations/20261006_regenerate_buyer_download.sql`

## 5. Send details to buyers

1. After checkout, the customer sees their **Order ID** with a **Copy** button.
2. After you **approve** in admin, send them the Order ID (or use **Email buyer**).
3. They open `https://YOUR-SITE/download.html`, enter Order ID + email, and tap **Get my ebook**.

If download fails with “Could not reach the download service”, redeploy **`download-ebook`** (step 2 above).
