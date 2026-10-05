(() => {
  const message = document.querySelector('#message');
  const button = document.querySelector('#download');
  const token = new URLSearchParams(location.hash.slice(1)).get('token');
  if (!token || !/^[a-f0-9]{64}$/i.test(token)) { message.textContent = 'This download link is invalid or incomplete. Please contact Mindora support.'; return; }
  const functionsUrl = `${window.MINDORA_CONFIG.SUPABASE_URL}/functions/v1/download-ebook`;
  fetch(functionsUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${window.MINDORA_CONFIG.SUPABASE_ANON_KEY}`,
      apikey: window.MINDORA_CONFIG.SUPABASE_ANON_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ token })
  }).then(async response => {
    const payload = await response.json().catch(() => ({}));
    if (response.status === 404) {
      throw new Error(
        'Download service is not deployed yet. The store owner must deploy the download-ebook Edge Function in Supabase (see supabase/DEPLOY-EDGE.md).'
      );
    }
    if (!response.ok) throw new Error(payload.error || 'Unable to create your download.');
    button.href = payload.signed_url;
    button.hidden = false;
    message.textContent = 'Your private download is ready. The file link expires in 10 minutes.';
    history.replaceState(null, '', location.pathname);
  }).catch(error => {
    const text = error.message || 'This link has expired or is no longer available. Please contact Mindora support.';
    message.textContent = text.includes('Failed to fetch')
      ? 'Could not reach the download service. Check your connection, or ask the store owner to deploy download-ebook in Supabase.'
      : text;
  });
})();
