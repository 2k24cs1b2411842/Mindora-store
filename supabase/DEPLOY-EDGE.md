# Deploy secure ebook download (required once)

Buyers open `download.html` on your **live website**. That page calls the **`download-ebook`** Edge Function, which:

1. Checks the secret token (only a hash is stored in the database).
2. Confirms the link is still within the 7-day window.
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

## 5. Send links to buyers

1. Open **`admin.html` on your live site** (same `SITE_URL`), not as a local `file://` page.
2. Approve payment → copy link or **Email buyer**.
3. Buyer opens `https://YOUR-SITE/download.html#token=…` and clicks Download.

If a link was created with a wrong URL, use **Create new buyer link** under Recent verified orders.
