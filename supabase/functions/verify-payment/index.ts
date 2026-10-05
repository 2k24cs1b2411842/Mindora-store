import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Content-Type': 'application/json'
};

const reply = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

const cleanSiteUrl = (value: string) => value.replace(/\/$/, '');

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function randomHex(bytes = 32) {
  const buffer = new Uint8Array(bytes);
  crypto.getRandomValues(buffer);
  return Array.from(buffer)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);

  try {
    const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!token) return reply({ error: 'Unauthenticated' }, 401);

    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const siteUrl = Deno.env.get('SITE_URL');

    if (!url || !anonKey || !serviceRoleKey) {
      return reply({ error: 'Supabase server configuration is incomplete' }, 500);
    }

    if (!siteUrl) {
      return reply({ error: 'SITE_URL is not configured' }, 500);
    }

    // Verify the caller's Supabase Auth session with the user's JWT.
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } }
    });

    const {
      data: { user },
      error: userError
    } = await userClient.auth.getUser();

    if (userError || !user) return reply({ error: 'Unauthenticated' }, 401);

    // Server-side client. The service-role key never reaches the browser.
    const adminClient = createClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    });

    // Authorize the caller as a Mindora admin.
    const { data: adminUser, error: adminError } = await adminClient
      .from('admin_users')
      .select('id, role')
      .eq('id', user.id)
      .maybeSingle();

    if (adminError) {
      return reply({ error: `Admin authorization failed: ${adminError.message}` }, 500);
    }

    if (!adminUser) {
      return reply({ error: 'Admin access required' }, 403);
    }

    const body = await req.json();
    const orderId = typeof body?.order_id === 'string' ? body.order_id.trim() : '';
    const approve = body?.approve;
    const note = typeof body?.note === 'string' ? body.note.trim().slice(0, 500) : '';

    if (!orderId || typeof approve !== 'boolean') {
      return reply({ error: 'Invalid request' }, 400);
    }

    // Load the order and its submitted payment directly. We intentionally do
    // not call approve_payment/reject_payment RPCs here because the existing
    // database functions have a PostgreSQL order_id name collision.
    const { data: order, error: orderError } = await adminClient
      .from('orders')
      .select(`
        id,
        order_number,
        customer_id,
        book_id,
        customer_name,
        customer_email,
        amount,
        currency,
        status
      `)
      .eq('id', orderId)
      .maybeSingle();

    if (orderError) return reply({ error: orderError.message }, 400);
    if (!order) return reply({ error: 'Order not found' }, 404);

    if (order.status !== 'payment_submitted') {
      return reply({ error: 'Only submitted payments can be reviewed' }, 400);
    }

    const { data: payments, error: paymentError } = await adminClient
      .from('payment_submissions')
      .select(`
        id,
        order_id,
        utr_number,
        upi_id,
        amount,
        currency,
        status,
        submitted_at
      `)
      .eq('order_id', orderId)
      .eq('status', 'submitted')
      .order('submitted_at', { ascending: false })
      .limit(1);

    if (paymentError) return reply({ error: paymentError.message }, 400);

    const payment = payments?.[0];
    if (!payment) return reply({ error: 'No submitted payment found for this order' }, 400);

    if (!approve) {
      const rejectionReason = note || 'Payment could not be verified';

      const { error: rejectPaymentError } = await adminClient
        .from('payment_submissions')
        .update({
          status: 'rejected',
          verified_at: new Date().toISOString(),
          verified_by: user.id,
          admin_note: rejectionReason
        })
        .eq('id', payment.id);

      if (rejectPaymentError) return reply({ error: rejectPaymentError.message }, 400);

      const { error: rejectOrderError } = await adminClient
        .from('orders')
        .update({
          status: 'rejected',
          updated_at: new Date().toISOString()
        })
        .eq('id', orderId);

      if (rejectOrderError) {
        // Best-effort rollback so the payment remains reviewable if the order update fails.
        await adminClient
          .from('payment_submissions')
          .update({
            status: 'submitted',
            verified_at: null,
            verified_by: null,
            admin_note: null
          })
          .eq('id', payment.id);

        return reply({ error: rejectOrderError.message }, 400);
      }

      return reply({
        ok: true,
        status: 'rejected',
        order_number: order.order_number
      });
    }

    // Prevent accidentally creating a second buyer-access record.
    const { data: existingDownload, error: existingDownloadError } = await adminClient
      .from('downloads')
      .select('id, status, expires_at')
      .eq('order_id', orderId)
      .maybeSingle();

    if (existingDownloadError) {
      return reply({ error: existingDownloadError.message }, 400);
    }

    if (existingDownload) {
      return reply({ error: 'Buyer access already exists for this order' }, 409);
    }

    // Generate the raw token for the buyer URL and store only its SHA-256 hash.
    const downloadToken = randomHex(32);
    const tokenHash = await sha256Hex(downloadToken);
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

    const { error: downloadError } = await adminClient
      .from('downloads')
      .insert({
        order_id: order.id,
        book_id: order.book_id,
        customer_id: order.customer_id,
        token_hash: tokenHash,
        status: 'active',
        expires_at: expiresAt
      });

    if (downloadError) return reply({ error: downloadError.message }, 400);

    const verifiedAt = new Date().toISOString();

    const { error: verifyPaymentError } = await adminClient
      .from('payment_submissions')
      .update({
        status: 'verified',
        verified_at: verifiedAt,
        verified_by: user.id
      })
      .eq('id', payment.id);

    if (verifyPaymentError) {
      await adminClient.from('downloads').delete().eq('order_id', order.id);
      return reply({ error: verifyPaymentError.message }, 400);
    }

    const { error: verifyOrderError } = await adminClient
      .from('orders')
      .update({
        status: 'verified',
        updated_at: verifiedAt
      })
      .eq('id', order.id);

    if (verifyOrderError) {
      await adminClient.from('downloads').delete().eq('order_id', order.id);
      await adminClient
        .from('payment_submissions')
        .update({
          status: 'submitted',
          verified_at: null,
          verified_by: null
        })
        .eq('id', payment.id);
      return reply({ error: verifyOrderError.message }, 400);
    }

    return reply({
      ok: true,
      status: 'verified',
      order_number: order.order_number,
      download_url: `${cleanSiteUrl(siteUrl)}/download.html#token=${downloadToken}`
    });
  } catch (error) {
    return reply({
      error: error instanceof Error ? error.message : 'Server error'
    }, 500);
  }
});
