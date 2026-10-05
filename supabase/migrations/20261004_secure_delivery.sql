-- Run this once only if you already ran the previous schema.sql in Supabase.
-- New projects should run the current schema.sql instead.

DROP FUNCTION IF EXISTS public.approve_payment(UUID);

ALTER TABLE public.downloads
  ADD CONSTRAINT downloads_one_per_order UNIQUE (order_id);

CREATE UNIQUE INDEX IF NOT EXISTS payment_submissions_utr_unique_idx
ON public.payment_submissions (utr_number);

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.approve_payment(p_order_id UUID)
RETURNS TABLE (order_id UUID, order_number TEXT, download_token TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
#variable_conflict use_column
DECLARE
    v_order public.orders%ROWTYPE;
    v_payment public.payment_submissions%ROWTYPE;
    v_token TEXT;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND OR v_order.status <> 'payment_submitted' THEN RAISE EXCEPTION 'Only submitted payments can be approved'; END IF;
    SELECT * INTO v_payment FROM public.payment_submissions ps WHERE ps.order_id = p_order_id AND ps.status = 'submitted' ORDER BY ps.submitted_at DESC LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'No submitted payment found'; END IF;
    v_token := encode(gen_random_bytes(32), 'hex');
    UPDATE public.payment_submissions SET status = 'verified', verified_at = NOW(), verified_by = auth.uid() WHERE id = v_payment.id;
    UPDATE public.orders SET status = 'verified', updated_at = NOW() WHERE id = v_order.id;
    INSERT INTO public.downloads (order_id, book_id, customer_id, token_hash, status, expires_at)
    VALUES (v_order.id, v_order.book_id, v_order.customer_id, encode(digest(v_token, 'sha256'), 'hex'), 'active', NOW() + INTERVAL '7 days');
    RETURN QUERY SELECT v_order.id, v_order.order_number, v_token;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verify_payment(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_payment(UUID) TO authenticated;
