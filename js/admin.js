(() => {
  const cfg = window.MINDORA_CONFIG;
  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
  const $ = selector => document.querySelector(selector);
  const loginView = $('#loginView');
  const dashboard = $('#dashboard');
  const money = (amount, currency = 'INR') => new Intl.NumberFormat('en-IN', { style: 'currency', currency, maximumFractionDigits: 2 }).format(Number(amount));
  const escapeHtml = value => String(value ?? '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));
  const dateTime = value => value ? new Date(value).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }) : '—';

  function resolveSiteBase() {
    const configured = String(cfg.SITE_URL || '').trim().replace(/\/$/, '');
    if (configured && /^https?:\/\//i.test(configured)) return configured;
    const origin = window.location.origin;
    if (origin && origin !== 'null' && !/^file:/i.test(origin)) return origin.replace(/\/$/, '');
    return null;
  }

  function buyerDownloadUrl(token) {
    const base = resolveSiteBase();
    if (!base) {
      throw new Error(
        'Set SITE_URL in js/config.js to your public website (https://your-site.onrender.com). ' +
        'Buyer links cannot be built when admin is opened as a local file (file://).'
      );
    }
    return `${base}/download.html#token=${token}`;
  }

  function buildMailto(email, orderNumber, url) {
    const subject = encodeURIComponent(`Your Mindora ebook — order ${orderNumber}`);
    const body = encodeURIComponent(
      `Hi,\n\nThank you for your purchase. Your payment is verified.\n\n` +
      `Open this private link on your phone or computer to download your ebook (link valid 7 days):\n\n${url}\n\n` +
      `On that page, tap Download — the file link works for about 10 minutes; you can reopen the same page anytime before it expires.\n\n` +
      `— Mindora`
    );
    return `mailto:${encodeURIComponent(email)}?subject=${subject}&body=${body}`;
  }

  function showBuyerAccess({ orderNumber, customerEmail, token }) {
    const url = buyerDownloadUrl(token);
    $('#accessUrl').value = url;
    $('#accessMessage').textContent =
      `Access created for order ${orderNumber}. Send the link below only to ${customerEmail}. It expires after 7 days.`;
    const emailLink = $('#emailBuyer');
    emailLink.href = buildMailto(customerEmail, orderNumber, url);
    emailLink.hidden = !customerEmail;
    const preview = $('#previewDownload');
    preview.href = url;
    preview.hidden = false;
    $('#accessCard').hidden = false;
    $('#accessCard').scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  function refreshSiteUrlWarning() {
    const box = $('#siteUrlWarning');
    if (!box) return;
    if (resolveSiteBase()) {
      box.hidden = true;
      return;
    }
    box.textContent =
      'Set SITE_URL in js/config.js to your live store URL (for example your Render site). ' +
      'Until you do, buyer download links will not work for customers.';
    box.hidden = false;
  }

  async function checkSession() {
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return;
    const { data: admin } = await sb.from('admin_users').select('id').eq('id', user.id).maybeSingle();
    if (!admin) { await sb.auth.signOut(); showLoginError('This account is not authorised to access Mindora Admin.'); return; }
    loginView.hidden = true;
    dashboard.hidden = false;
    refreshSiteUrlWarning();
    loadOrders();
    loadRecentDeliveries();
  }

  function showLoginError(message) { const box = $('#loginError'); box.textContent = message; box.hidden = false; }

  $('#loginForm').addEventListener('submit', async event => {
    event.preventDefault();
    const button = event.submitter;
    button.disabled = true; button.textContent = 'Signing in…';
    const { error } = await sb.auth.signInWithPassword({ email: $('#loginEmail').value.trim(), password: $('#loginPassword').value });
    button.disabled = false; button.textContent = 'Sign in →';
    if (error) return showLoginError(error.message);
    $('#loginError').hidden = true;
    checkSession();
  });

  $('#logout').addEventListener('click', async () => { await sb.auth.signOut(); location.reload(); });
  $('#copyAccess').addEventListener('click', async () => {
    const link = $('#accessUrl').value;
    if (!link) return;
    await navigator.clipboard.writeText(link);
    $('#copyAccess').textContent = 'Copied';
    setTimeout(() => { $('#copyAccess').textContent = 'Copy buyer link'; }, 1500);
  });

  async function loadOrders() {
    const { data, error } = await sb.from('orders').select('id,order_number,customer_name,customer_email,amount,currency,status,created_at,books(title),payment_submissions(id,utr_number,upi_id,amount,currency,status,submitted_at)').eq('status', 'payment_submitted').order('created_at', { ascending: false });
    if (error) { $('#orders').innerHTML = `<div class="error-box">${escapeHtml(error.message)}</div>`; return; }
    const pending = data || [];
    $('#pendingCount').textContent = pending.length;
    $('#pendingValue').textContent = money(pending.reduce((total, order) => total + Number(order.amount), 0));
    if (!pending.length) { $('#orders').innerHTML = '<p class="empty">No payment submissions need review right now.</p>'; return; }
    $('#orders').innerHTML = pending.map(order => {
      const payment = order.payment_submissions?.find(entry => entry.status === 'submitted');
      return `<article class="admin-card"><div class="order-head"><div><small>Order ${escapeHtml(order.order_number)}</small><h3>${escapeHtml(order.books?.title || 'Ebook')}</h3></div><span class="status submitted">Awaiting UTR check</span></div><div class="admin-grid"><div class="data-block"><small>Buyer</small><strong>${escapeHtml(order.customer_name)}</strong><p>${escapeHtml(order.customer_email)}</p></div><div class="data-block"><small>Payment received</small><strong>${escapeHtml(money(order.amount, order.currency))}</strong><p>Created ${escapeHtml(dateTime(order.created_at))}</p></div><div class="data-block"><small>UPI confirmation</small><strong>${escapeHtml(payment?.utr_number || 'Missing UTR')}</strong><p>UPI: ${escapeHtml(payment?.upi_id || '—')}<br>Submitted ${escapeHtml(dateTime(payment?.submitted_at))}</p></div></div><div class="admin-btns"><button class="approve" data-action="approve" data-id="${order.id}" data-email="${escapeHtml(order.customer_email)}" data-order="${escapeHtml(order.order_number)}">Approve & create buyer access</button><button class="reject" data-action="reject" data-id="${order.id}">Reject payment</button></div></article>`;
    }).join('');
    document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => reviewPayment(button)));
  }

  async function loadRecentDeliveries() {
    const section = $('#recentDeliveries');
    const list = $('#deliveryList');
    if (!section || !list) return;
    const { data, error } = await sb.from('orders')
      .select('id,order_number,customer_name,customer_email,updated_at,downloads(status,expires_at)')
      .eq('status', 'verified')
      .order('updated_at', { ascending: false })
      .limit(8);
    if (error) {
      list.innerHTML = `<p class="empty">${escapeHtml(error.message)}</p>`;
      section.hidden = false;
      return;
    }
    const rows = (data || []).filter(order => order.downloads);
    if (!rows.length) {
      section.hidden = true;
      return;
    }
    section.hidden = false;
    list.innerHTML = rows.map(order => {
      const dl = Array.isArray(order.downloads) ? order.downloads[0] : order.downloads;
      const expires = dl?.expires_at ? dateTime(dl.expires_at) : '—';
      return `<article class="admin-card"><div class="order-head"><div><small>Order ${escapeHtml(order.order_number)}</small><h3>${escapeHtml(order.customer_name)}</h3></div><span class="status submitted">Verified</span></div><p>${escapeHtml(order.customer_email)} · access expires ${escapeHtml(expires)}</p><div class="admin-btns"><button type="button" class="approve" data-regenerate="${order.id}" data-email="${escapeHtml(order.customer_email)}" data-order="${escapeHtml(order.order_number)}">Create new buyer link</button></div></article>`;
    }).join('');
    list.querySelectorAll('[data-regenerate]').forEach(button => {
      button.addEventListener('click', () => regenerateBuyerLink(button));
    });
  }

  async function regenerateBuyerLink(button) {
    if (!confirm('Create a new private download link? The old link will stop working immediately.')) return;
    if (!resolveSiteBase()) return alert('Set SITE_URL in js/config.js to your live website URL first.');
    button.disabled = true;
    button.textContent = 'Creating link…';
    try {
      const { data, error } = await sb.rpc('regenerate_buyer_download', { p_order_id: button.dataset.regenerate });
      if (error) throw new Error(error.message);
      const row = Array.isArray(data) ? data[0] : data;
      if (!row?.download_token) throw new Error('No download token returned.');
      showBuyerAccess({
        orderNumber: row.order_number || button.dataset.order,
        customerEmail: button.dataset.email,
        token: row.download_token
      });
    } catch (err) {
      alert(err.message || 'Could not create a new link.');
    } finally {
      button.disabled = false;
      button.textContent = 'Create new buyer link';
    }
  }

  async function reviewPayment(button) {
    const orderId = button.dataset.id;
    const approve = button.dataset.action === 'approve';
    const confirmation = approve
      ? 'Confirm you matched this UTR and amount in your UPI or bank account. This will create buyer access.'
      : 'Reject this payment submission? The buyer will not receive the ebook.';
    if (!confirm(confirmation)) return;
    if (approve && !resolveSiteBase()) {
      return alert('Set SITE_URL in js/config.js to your public store URL before approving (for example https://your-app.onrender.com).');
    }
    const { data: { session } } = await sb.auth.getSession();
    if (!session?.access_token) return alert('Your session expired. Please sign in again.');
    button.disabled = true;
    button.textContent = approve ? 'Creating access…' : 'Rejecting…';
    try {
      const note = approve ? '' : (prompt('Reason for rejecting this payment:', 'Payment could not be verified') || '').trim();
      if (!approve && !note) { button.disabled = false; button.textContent = 'Reject payment'; return; }
      if (approve) {
        const { data, error } = await sb.rpc('approve_payment', { p_order_id: orderId });
        if (error) throw new Error(error.message);
        const row = Array.isArray(data) ? data[0] : data;
        if (!row?.download_token) throw new Error('Approval succeeded but no download token was returned. Run the latest schema fix in Supabase SQL Editor.');
        showBuyerAccess({
          orderNumber: row.order_number || button.dataset.order,
          customerEmail: button.dataset.email,
          token: row.download_token
        });
      } else {
        const { error } = await sb.rpc('reject_payment', { p_order_id: orderId, p_reason: note });
        if (error) throw new Error(error.message);
      }
      await loadOrders();
      await loadRecentDeliveries();
    } catch (error) {
      alert(error.message || 'Could not update this payment.');
      button.disabled = false;
      button.textContent = approve ? 'Approve & create buyer access' : 'Reject payment';
    }
  }

  checkSession();
})();
