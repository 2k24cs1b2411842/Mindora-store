import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Content-Type': 'application/json'
};

const reply = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
};

const normalizeOrderNumber = (value: string) => value.trim().toUpperCase();

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !serviceRoleKey) {
      return reply({ error: 'Supabase server configuration is incomplete' }, 500);
    }

    const admin = createClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    });

    const body = await req.json();
    const token = typeof body?.token === 'string' ? body.token.trim() : '';
    const orderNumber = typeof body?.order_number === 'string' ? normalizeOrderNumber(body.order_number) : '';
    const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';

    let downloadId: string | null = null;
    let filePath: string | null = null;
    let downloadCount = 0;

    if (token && /^[a-f0-9]{64}$/i.test(token)) {
      const { data: download, error } = await admin
        .from('downloads')
        .select('id, status, expires_at, download_count, books!inner(file_path)')
        .eq('token_hash', await sha256(token))
        .maybeSingle();

      if (error || !download || download.status !== 'active') {
        return reply({ error: 'This download link has expired or is unavailable' }, 404);
      }
      if (!download.expires_at || new Date(download.expires_at) <= new Date()) {
        return reply({ error: 'This download link has expired or is unavailable' }, 404);
      }

      downloadId = download.id;
      downloadCount = download.download_count ?? 0;
      filePath = (download.books as { file_path: string | null }).file_path;
    } else if (orderNumber && email) {
      if (!/^MN-\d{8}-[A-F0-9]{6}$/.test(orderNumber)) {
        return reply({ error: 'Invalid order ID format' }, 400);
      }

      const { data: order, error: orderError } = await admin
        .from('orders')
        .select('id, status, customer_email')
        .eq('order_number', orderNumber)
        .maybeSingle();

      if (orderError) return reply({ error: orderError.message }, 400);
      if (!order) return reply({ error: 'Order ID not found' }, 404);
      if (order.status !== 'verified') {
        return reply({
          error:
            order.status === 'payment_submitted'
              ? 'Your payment is still being verified. You will be able to download once it is approved.'
              : 'This order is not eligible for download.'
        }, 403);
      }
      if (order.customer_email.trim().toLowerCase() !== email) {
        return reply({ error: 'Order ID and email do not match our records' }, 403);
      }

      const { data: download, error: downloadError } = await admin
        .from('downloads')
        .select('id, status, expires_at, download_count, book_id')
        .eq('order_id', order.id)
        .maybeSingle();

      if (downloadError) return reply({ error: downloadError.message }, 400);
      if (!download || download.status !== 'active') {
        return reply({ error: 'Download access is not available for this order' }, 404);
      }
      if (!download.expires_at || new Date(download.expires_at) <= new Date()) {
        return reply({ error: 'Download access for this order has expired. Contact Mindora support.' }, 404);
      }

      const { data: book, error: bookError } = await admin
        .from('books')
        .select('file_path')
        .eq('id', download.book_id)
        .maybeSingle();

      if (bookError) return reply({ error: bookError.message }, 400);
      filePath = book?.file_path ?? null;
      downloadId = download.id;
      downloadCount = download.download_count ?? 0;
    } else {
      return reply({ error: 'Provide order_number and email, or a valid download token' }, 400);
    }

    if (!filePath) return reply({ error: 'The ebook file is not available yet' }, 404);

    const { data: signed, error: signedError } = await admin.storage
      .from('mindora-private')
      .createSignedUrl(filePath, 600);

    if (signedError || !signed?.signedUrl) {
      return reply({ error: 'Could not prepare the ebook download' }, 500);
    }

    if (downloadId) {
      await admin
        .from('downloads')
        .update({
          download_count: downloadCount + 1,
          last_downloaded_at: new Date().toISOString()
        })
        .eq('id', downloadId);
    }

    return reply({ signed_url: signed.signedUrl });
  } catch (error) {
    return reply({ error: error instanceof Error ? error.message : 'Server error' }, 500);
  }
});
