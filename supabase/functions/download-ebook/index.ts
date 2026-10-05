import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type', 'Content-Type': 'application/json' };
const reply = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
  try {
    const { token } = await req.json();
    if (typeof token !== 'string' || !/^[a-f0-9]{64}$/i.test(token)) return reply({ error: 'Invalid download link' }, 400);
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: download, error } = await admin.from('downloads').select('id, status, expires_at, download_count, books!inner(file_path)').eq('token_hash', await sha256(token)).maybeSingle();
    if (error || !download || download.status !== 'active' || !download.expires_at || new Date(download.expires_at) <= new Date()) return reply({ error: 'This download link has expired or is unavailable' }, 404);
    const path = (download.books as { file_path: string | null }).file_path;
    if (!path) return reply({ error: 'The ebook file is not available yet' }, 404);
    const { data: signed, error: signedError } = await admin.storage.from('mindora-private').createSignedUrl(path, 600);
    if (signedError || !signed?.signedUrl) return reply({ error: 'Could not prepare the ebook download' }, 500);
    await admin.from('downloads').update({ download_count: download.download_count + 1, last_downloaded_at: new Date().toISOString() }).eq('id', download.id);
    return reply({ signed_url: signed.signedUrl });
  } catch (error) { return reply({ error: error instanceof Error ? error.message : 'Server error' }, 500); }
});
