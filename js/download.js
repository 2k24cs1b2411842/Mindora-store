(() => {
  const cfg = window.MINDORA_CONFIG;
  const form = document.querySelector('#downloadForm');
  const message = document.querySelector('#message');
  const button = document.querySelector('#download');
  const orderInput = document.querySelector('#orderNumber');
  const emailInput = document.querySelector('#customerEmail');
  const submitBtn = document.querySelector('#submitDownload');

  const functionsUrl = `${cfg.SUPABASE_URL}/functions/v1/download-ebook`;

  function setMessage(text, isError = false) {
    message.textContent = text;
    message.style.color = isError ? '#7c2727' : '';
  }

  async function requestDownload(payload) {
    button.hidden = true;
    submitBtn.disabled = true;
    setMessage('Checking your order and preparing your download…');

    try {
      const response = await fetch(functionsUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${cfg.SUPABASE_ANON_KEY}`,
          apikey: cfg.SUPABASE_ANON_KEY,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      const result = await response.json().catch(() => ({}));

      if (response.status === 404 && !result.error) {
        throw new Error(
          'Download service is not deployed yet. Ask the store owner to deploy download-ebook in Supabase (see supabase/DEPLOY-EDGE.md).'
        );
      }
      if (!response.ok) throw new Error(result.error || 'Unable to create your download.');

      button.href = result.signed_url;
      button.hidden = false;
      setMessage('Your download is ready. The file link expires in about 10 minutes — you can return here anytime before your access period ends.');
    } catch (error) {
      const text = error.message || 'This order is not ready for download yet.';
      setMessage(
        text.includes('Failed to fetch')
          ? 'Could not reach the download service. Check your connection, or ask the store owner to deploy download-ebook in Supabase.'
          : text,
        true
      );
    } finally {
      submitBtn.disabled = false;
    }
  }

  form?.addEventListener('submit', (event) => {
    event.preventDefault();
    const order_number = orderInput.value.trim().toUpperCase();
    const email = emailInput.value.trim().toLowerCase();
    if (!order_number || !email) return;
    requestDownload({ order_number, email });
  });

  const query = new URLSearchParams(location.search);
  const presetOrder = query.get('order');
  if (presetOrder && orderInput) orderInput.value = presetOrder.trim().toUpperCase();

  const legacyToken = new URLSearchParams(location.hash.slice(1)).get('token');
  if (legacyToken && /^[a-f0-9]{64}$/i.test(legacyToken)) {
    form.hidden = true;
    requestDownload({ token: legacyToken });
  }
})();
