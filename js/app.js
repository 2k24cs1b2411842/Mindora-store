(() => {
  const cfg = window.MINDORA_CONFIG;
  const hasSupabase = cfg && !cfg.SUPABASE_URL.includes('YOUR-PROJECT') && !cfg.SUPABASE_ANON_KEY.includes('YOUR_SUPABASE');
  const sb = hasSupabase ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;
  let selectedBook = null;
  let selectedOrder = null;

  const $ = (s) => document.querySelector(s);
  const $$ = (s) => [...document.querySelectorAll(s)];

  $('#navToggle')?.addEventListener('click', () => {
    const links = $('#navLinks'); const open = links.classList.toggle('open'); $('#navToggle').setAttribute('aria-expanded', open);
  });
  $$('#navLinks a').forEach(a => a.addEventListener('click', () => $('#navLinks').classList.remove('open')));

  const observer = new IntersectionObserver(entries => entries.forEach(e => { if (e.isIntersecting) e.target.classList.add('visible'); }), {threshold:.12});
  $$('.reveal').forEach(el => observer.observe(el));

  const modal = $('#checkoutModal');
  function openModal(){ modal.classList.add('open'); modal.setAttribute('aria-hidden','false'); document.body.style.overflow='hidden'; }
  function closeModal(){ modal.classList.remove('open'); modal.setAttribute('aria-hidden','true'); document.body.style.overflow=''; }
  $$('[data-close]').forEach(el => el.addEventListener('click', closeModal));
  document.addEventListener('keydown', e => { if(e.key==='Escape') closeModal(); });

  function showStep(n){ [1,2,3].forEach(i => $(`#checkoutStep${i}`).hidden = i !== n); $('#checkoutError').hidden = true; }
  function error(msg){ const box=$('#checkoutError'); box.textContent=msg; box.hidden=false; }
  function money(amount,currency='INR'){ const symbols={INR:'₹',GBP:'£',USD:'$'}; return `${symbols[currency]||currency}${Number(amount).toFixed(0)}`; }
  function renderUpiQr(){
    const target=$('#qrCode');
    if(!target || !selectedOrder || !window.QRCode) return;
    const params=new URLSearchParams({pa:cfg.UPI_ID,pn:'Mindora',am:Number(selectedOrder.amount).toFixed(2),cu:selectedOrder.currency||'INR',tn:`Mindora ${selectedOrder.order_number}`});
    target.replaceChildren();
    new window.QRCode(target,{text:`upi://pay?${params.toString()}`,width:160,height:160,colorDark:'#0b1420',colorLight:'#ffffff',correctLevel:window.QRCode.CorrectLevel.M});
  }

  async function loadBook(){
    if(!sb) return;
    const {data,error}=await sb.from('books').select('*').eq('slug','the-ai-advantage').eq('status','published').maybeSingle();
    if(error || !data) return;
    selectedBook=data;
    $('#bookPrice').textContent=money(data.price,data.currency);
  }

  $$('.buy-btn').forEach(btn => btn.addEventListener('click', async () => {
    selectedBook = selectedBook || {id:null,slug:'the-ai-advantage',title:'The AI Advantage',price:499,currency:'INR'};
    $('#checkoutPrice').textContent=money(selectedBook.price,selectedBook.currency);
    $('#upiAmount').textContent=money(selectedBook.price,selectedBook.currency);
    $('#upiId').textContent=cfg.UPI_ID;
    showStep(1); openModal();
    await loadBook();
    if(selectedBook){ $('#checkoutPrice').textContent=money(selectedBook.price,selectedBook.currency); $('#upiAmount').textContent=money(selectedBook.price,selectedBook.currency); }
  }));

  $('#copyUpi')?.addEventListener('click', async () => { try { await navigator.clipboard.writeText(cfg.UPI_ID); $('#copyUpi').textContent='Copied'; setTimeout(()=>$('#copyUpi').textContent='Copy',1200); } catch {} });

  $('#orderForm')?.addEventListener('submit', async e => {
    e.preventDefault();
    if(!sb){ error('Supabase is not configured yet. Add your Supabase URL and anon key in js/config.js.'); return; }
    const name=$('#customerName').value.trim(), email=$('#customerEmail').value.trim().toLowerCase();
    if(!selectedBook?.id){ await loadBook(); }
    if(!selectedBook?.id){ error('The book is not available yet. Please try again later.'); return; }
    const button=e.submitter; button.disabled=true; button.textContent='Creating order…';
    try{
      const {data,error}=await sb.rpc('create_order',{p_book_id:selectedBook.id,p_customer_name:name,p_customer_email:email});
      if(error) throw error;
      selectedOrder=data;
      $('#upiAmount').textContent=money(selectedOrder.amount,selectedOrder.currency);
      renderUpiQr();
      showStep(2);
    }catch(err){ error(err.message || 'Could not create the order.'); }
    finally{ button.disabled=false; button.textContent='Continue to UPI payment →'; }
  });

  $('#paymentForm')?.addEventListener('submit', async e => {
    e.preventDefault();
    if(!sb || !selectedOrder){ error('Your order session has expired. Please start again.'); return; }
    const utr=$('#utr').value.trim();
    if(utr.length<6){ error('Please enter a valid UTR / transaction ID.'); return; }
    const button=e.submitter; button.disabled=true; button.textContent='Submitting…';
    try{
      const {data,error}=await sb.rpc('submit_payment',{p_order_id:selectedOrder.id,p_upi_id:cfg.UPI_ID,p_utr_number:utr});
      if(error) throw error;
      $('#orderCode').textContent=`Order ${data.order_number} · Payment confirmation submitted`;
      showStep(3);
    }catch(err){ error(err.message || 'Could not submit payment confirmation.'); }
    finally{ button.disabled=false; button.textContent='Submit payment confirmation →'; }
  });

  loadBook();
})();
