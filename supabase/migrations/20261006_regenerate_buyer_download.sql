-- Admin: issue a new buyer download link (invalidates the previous token).

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.regenerate_buyer_download(p_order_id UUID)
RETURNS TABLE (order_number TEXT, download_token TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
    v_token TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;

    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
    IF NOT FOUND OR v_order.status <> 'verified' THEN
        RAISE EXCEPTION 'Only verified orders can receive a new download link';
    END IF;

    v_token := encode(gen_random_bytes(32), 'hex');

    UPDATE public.downloads d
    SET
        token_hash = encode(digest(v_token, 'sha256'), 'hex'),
        status = 'active',
        expires_at = NOW() + INTERVAL '7 days'
    WHERE d.order_id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No download record exists for this order';
    END IF;

    RETURN QUERY SELECT v_order.order_number, v_token;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.regenerate_buyer_download(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regenerate_buyer_download(UUID) TO authenticated;
