-- ============================================================
-- MINDORA EBOOK STORE
-- Complete Supabase Database Schema
-- Version: 1.0
-- ============================================================
--
-- Purpose:
--   Digital ebook store with:
--   - Multiple books
--   - Customers
--   - Orders
--   - UPI payments
--   - UTR/payment confirmation
--   - Admin verification
--   - Reviews
--   - Secure download records
--
-- IMPORTANT:
--   This script drops ONLY the Mindora application tables/functions.
--   It does NOT touch auth.users.
--
-- ============================================================


-- ============================================================
-- 1. EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


-- ============================================================
-- 2. CLEAN OLD MINDORA FUNCTIONS
-- ============================================================
--
-- This fixes:
-- ERROR: 42P13 cannot change return type of existing function
--
-- PostgreSQL requires an existing function to be dropped before
-- recreating it with a different return type.
--

DROP FUNCTION IF EXISTS public.submit_payment(uuid, text, text);
DROP FUNCTION IF EXISTS public.create_order(uuid, text, text);
DROP FUNCTION IF EXISTS public.is_admin();
DROP FUNCTION IF EXISTS public.verify_payment(uuid);
DROP FUNCTION IF EXISTS public.reject_payment(uuid, text);
DROP FUNCTION IF EXISTS public.create_download_token(uuid);
DROP FUNCTION IF EXISTS public.approve_payment(uuid);
DROP FUNCTION IF EXISTS public.regenerate_buyer_download(uuid);


-- ============================================================
-- 3. CLEAN OLD MINDORA TABLES
-- ============================================================
--
-- WARNING:
-- This removes existing data from these Mindora tables.
--
-- Do NOT run this section on production after you have real
-- customer orders unless you intentionally want to reset them.
--

DROP TABLE IF EXISTS public.downloads CASCADE;
DROP TABLE IF EXISTS public.payment_submissions CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.reviews CASCADE;
DROP TABLE IF EXISTS public.books CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.admin_users CASCADE;


-- ============================================================
-- 4. ENUM TYPES
-- ============================================================

DROP TYPE IF EXISTS public.book_status CASCADE;
DROP TYPE IF EXISTS public.order_status CASCADE;
DROP TYPE IF EXISTS public.payment_status CASCADE;
DROP TYPE IF EXISTS public.download_status CASCADE;

CREATE TYPE public.book_status AS ENUM (
    'draft',
    'published',
    'coming_soon',
    'archived'
);

CREATE TYPE public.order_status AS ENUM (
    'pending',
    'payment_submitted',
    'verified',
    'rejected',
    'cancelled',
    'refunded'
);

CREATE TYPE public.payment_status AS ENUM (
    'submitted',
    'verified',
    'rejected'
);

CREATE TYPE public.download_status AS ENUM (
    'active',
    'expired',
    'revoked'
);


-- ============================================================
-- 5. CUSTOMERS
-- ============================================================

CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,

    email TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT customers_email_not_empty
        CHECK (length(trim(email)) > 3)
);

CREATE UNIQUE INDEX customers_email_unique_idx
ON public.customers (lower(email));


-- ============================================================
-- 6. BOOKS
-- ============================================================

CREATE TABLE public.books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    slug TEXT NOT NULL UNIQUE,

    title TEXT NOT NULL,

    subtitle TEXT,

    description TEXT NOT NULL,

    short_description TEXT,

    author TEXT NOT NULL DEFAULT 'SK',

    cover_image_url TEXT,

    preview_url TEXT,

    file_path TEXT,

    price NUMERIC(10,2) NOT NULL,

    currency TEXT NOT NULL DEFAULT 'INR',

    category TEXT,

    page_count INTEGER,

    language TEXT NOT NULL DEFAULT 'English',

    status public.book_status NOT NULL DEFAULT 'draft',

    featured BOOLEAN NOT NULL DEFAULT FALSE,

    published_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT books_price_positive
        CHECK (price >= 0),

    CONSTRAINT books_currency_length
        CHECK (length(currency) = 3),

    CONSTRAINT books_page_count_positive
        CHECK (page_count IS NULL OR page_count > 0)
);

CREATE INDEX books_status_idx
ON public.books(status);

CREATE INDEX books_featured_idx
ON public.books(featured);

CREATE INDEX books_category_idx
ON public.books(category);


-- ============================================================
-- 7. ORDERS
-- ============================================================

CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    order_number TEXT NOT NULL UNIQUE,

    customer_id UUID NOT NULL
        REFERENCES public.customers(id)
        ON DELETE RESTRICT,

    book_id UUID NOT NULL
        REFERENCES public.books(id)
        ON DELETE RESTRICT,

    amount NUMERIC(10,2) NOT NULL,

    currency TEXT NOT NULL DEFAULT 'INR',

    status public.order_status NOT NULL DEFAULT 'pending',

    customer_name TEXT NOT NULL,

    customer_email TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT orders_amount_positive
        CHECK (amount >= 0)
);

CREATE INDEX orders_customer_id_idx
ON public.orders(customer_id);

CREATE INDEX orders_book_id_idx
ON public.orders(book_id);

CREATE INDEX orders_status_idx
ON public.orders(status);

CREATE INDEX orders_created_at_idx
ON public.orders(created_at DESC);


-- ============================================================
-- 8. PAYMENT SUBMISSIONS
-- ============================================================

CREATE TABLE public.payment_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    order_id UUID NOT NULL
        REFERENCES public.orders(id)
        ON DELETE CASCADE,

    upi_id TEXT NOT NULL,

    utr_number TEXT NOT NULL,

    amount NUMERIC(10,2) NOT NULL,

    currency TEXT NOT NULL DEFAULT 'INR',

    status public.payment_status NOT NULL DEFAULT 'submitted',

    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    verified_at TIMESTAMPTZ,

    verified_by UUID
        REFERENCES auth.users(id)
        ON DELETE SET NULL,

    admin_note TEXT
);

CREATE INDEX payment_submissions_order_id_idx
ON public.payment_submissions(order_id);

CREATE INDEX payment_submissions_status_idx
ON public.payment_submissions(status);

CREATE INDEX payment_submissions_utr_idx
ON public.payment_submissions(utr_number);

CREATE UNIQUE INDEX payment_submissions_utr_unique_idx
ON public.payment_submissions(utr_number);


-- ============================================================
-- 9. DOWNLOADS
-- ============================================================

CREATE TABLE public.downloads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    order_id UUID NOT NULL
        REFERENCES public.orders(id)
        ON DELETE CASCADE,

    book_id UUID NOT NULL
        REFERENCES public.books(id)
        ON DELETE RESTRICT,

    customer_id UUID NOT NULL
        REFERENCES public.customers(id)
        ON DELETE RESTRICT,

    token_hash TEXT NOT NULL UNIQUE,

    status public.download_status NOT NULL DEFAULT 'active',

    expires_at TIMESTAMPTZ,

    download_count INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    last_downloaded_at TIMESTAMPTZ,

    CONSTRAINT downloads_count_positive
        CHECK (download_count >= 0),

    CONSTRAINT downloads_one_per_order UNIQUE (order_id)
);

CREATE INDEX downloads_order_id_idx
ON public.downloads(order_id);

CREATE INDEX downloads_customer_id_idx
ON public.downloads(customer_id);

CREATE INDEX downloads_status_idx
ON public.downloads(status);


-- ============================================================
-- 10. REVIEWS
-- ============================================================

CREATE TABLE public.reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    book_id UUID NOT NULL
        REFERENCES public.books(id)
        ON DELETE CASCADE,

    customer_id UUID
        REFERENCES public.customers(id)
        ON DELETE SET NULL,

    rating INTEGER NOT NULL,

    review TEXT NOT NULL,

    verified_purchase BOOLEAN NOT NULL DEFAULT FALSE,

    approved BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT reviews_rating_range
        CHECK (rating BETWEEN 1 AND 5),

    CONSTRAINT reviews_text_length
        CHECK (length(trim(review)) >= 5)
);

CREATE INDEX reviews_book_id_idx
ON public.reviews(book_id);

CREATE INDEX reviews_approved_idx
ON public.reviews(approved);


-- ============================================================
-- 11. ADMIN USERS
-- ============================================================
--
-- The actual login account is created through:
-- Supabase Authentication → Users
--
-- This table stores the application-level admin role.
--

CREATE TABLE public.admin_users (
    id UUID PRIMARY KEY
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    email TEXT NOT NULL,

    role TEXT NOT NULL DEFAULT 'admin',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT admin_users_role_check
        CHECK (role IN ('admin', 'editor'))
);


-- ============================================================
-- 12. HELPER FUNCTION — UPDATED_AT
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- ============================================================
-- 13. UPDATED_AT TRIGGERS
-- ============================================================

CREATE TRIGGER customers_updated_at_trigger
BEFORE UPDATE ON public.customers
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


CREATE TRIGGER books_updated_at_trigger
BEFORE UPDATE ON public.books
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


CREATE TRIGGER orders_updated_at_trigger
BEFORE UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 14. ADMIN CHECK FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.admin_users
        WHERE id = auth.uid()
        AND role IN ('admin', 'editor')
    );
$$;


-- ============================================================
-- 15. CREATE ORDER FUNCTION
-- ============================================================
--
-- The browser calls this function instead of directly inserting
-- arbitrary order amounts.
--
-- Parameters:
--   book_id
--   customer_name
--   customer_email
--
-- The price comes from the database.
--

CREATE OR REPLACE FUNCTION public.create_order(
    p_book_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_customer_id UUID;
    v_book public.books%ROWTYPE;
    v_order public.orders%ROWTYPE;
    v_order_number TEXT;
BEGIN

    -- Validate customer
    IF trim(p_customer_name) = '' THEN
        RAISE EXCEPTION 'Customer name is required';
    END IF;

    IF trim(p_customer_email) = '' THEN
        RAISE EXCEPTION 'Customer email is required';
    END IF;


    -- Get published book
    SELECT *
    INTO v_book
    FROM public.books
    WHERE id = p_book_id
      AND status = 'published'
    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book is not available';
    END IF;


    -- Find existing customer
    SELECT id
    INTO v_customer_id
    FROM public.customers
    WHERE lower(email) = lower(trim(p_customer_email))
    LIMIT 1;


    -- Create customer if necessary
    IF v_customer_id IS NULL THEN

        INSERT INTO public.customers (
            name,
            email
        )
        VALUES (
            trim(p_customer_name),
            lower(trim(p_customer_email))
        )
        RETURNING id INTO v_customer_id;

    ELSE

        UPDATE public.customers
        SET
            name = trim(p_customer_name),
            updated_at = NOW()
        WHERE id = v_customer_id;

    END IF;


    -- Generate order number
    v_order_number :=
        'MN-' ||
        TO_CHAR(NOW(), 'YYYYMMDD') ||
        '-' ||
        UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', '') FROM 1 FOR 6));


    -- Create order
    INSERT INTO public.orders (
        order_number,
        customer_id,
        book_id,
        amount,
        currency,
        status,
        customer_name,
        customer_email
    )
    VALUES (
        v_order_number,
        v_customer_id,
        v_book.id,
        v_book.price,
        v_book.currency,
        'pending',
        trim(p_customer_name),
        lower(trim(p_customer_email))
    )
    RETURNING * INTO v_order;


    RETURN v_order;

END;
$$;


-- ============================================================
-- 16. SUBMIT PAYMENT FUNCTION
-- ============================================================
--
-- Customer submits UPI transaction information.
--
-- IMPORTANT:
-- This does NOT verify the payment.
--
-- Admin must verify it.
--

CREATE OR REPLACE FUNCTION public.submit_payment(
    p_order_id UUID,
    p_upi_id TEXT,
    p_utr_number TEXT
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
    v_payment_exists BOOLEAN;
BEGIN

    -- Get order
    SELECT *
    INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found';
    END IF;


    -- Validate order status
    IF v_order.status NOT IN ('pending', 'payment_submitted') THEN
        RAISE EXCEPTION 'This order cannot receive another payment submission';
    END IF;


    -- Validate UPI ID
    IF trim(p_upi_id) = '' THEN
        RAISE EXCEPTION 'UPI ID is required';
    END IF;


    -- Validate UTR
    IF trim(p_utr_number) = '' THEN
        RAISE EXCEPTION 'UTR number is required';
    END IF;


    -- Prevent duplicate UTR
    SELECT EXISTS (
        SELECT 1
        FROM public.payment_submissions
        WHERE utr_number = trim(p_utr_number)
    )
    INTO v_payment_exists;


    IF v_payment_exists THEN
        RAISE EXCEPTION 'This UTR number has already been submitted';
    END IF;


    -- Insert payment submission
    INSERT INTO public.payment_submissions (
        order_id,
        upi_id,
        utr_number,
        amount,
        currency,
        status
    )
    VALUES (
        v_order.id,
        trim(p_upi_id),
        trim(p_utr_number),
        v_order.amount,
        v_order.currency,
        'submitted'
    );


    -- Update order
    UPDATE public.orders
    SET
        status = 'payment_submitted',
        updated_at = NOW()
    WHERE id = v_order.id
    RETURNING * INTO v_order;


    RETURN v_order;

END;
$$;


-- ============================================================
-- 17. VERIFY PAYMENT FUNCTION
-- ============================================================
--
-- Admin only.
--

CREATE OR REPLACE FUNCTION public.verify_payment(
    p_order_id UUID
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
    v_payment public.payment_submissions%ROWTYPE;
    v_token TEXT;
    v_token_hash TEXT;
BEGIN

    -- Check admin
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;


    -- Get order
    SELECT *
    INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;


    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found';
    END IF;


    -- Get latest payment
    SELECT *
    INTO v_payment
    FROM public.payment_submissions
    WHERE order_id = p_order_id
    ORDER BY submitted_at DESC
    LIMIT 1
    FOR UPDATE;


    IF NOT FOUND THEN
        RAISE EXCEPTION 'No payment submission found';
    END IF;


    -- Update payment
    UPDATE public.payment_submissions
    SET
        status = 'verified',
        verified_at = NOW(),
        verified_by = auth.uid()
    WHERE id = v_payment.id;


    -- Update order
    UPDATE public.orders
    SET
        status = 'verified',
        updated_at = NOW()
    WHERE id = p_order_id
    RETURNING * INTO v_order;


    -- Create secure random token
    v_token := encode(gen_random_bytes(32), 'hex');

    -- Store only SHA256 hash
    v_token_hash := encode(
        digest(v_token, 'sha256'),
        'hex'
    );


    INSERT INTO public.downloads (
        order_id,
        book_id,
        customer_id,
        token_hash,
        status,
        expires_at
    )
    VALUES (
        v_order.id,
        v_order.book_id,
        v_order.customer_id,
        v_token_hash,
        'active',
        NOW() + INTERVAL '7 days'
    );


    RETURN v_order;

END;
$$;


-- ============================================================
-- 17A. APPROVE PAYMENT AND CREATE A DELIVERY SECRET
-- ============================================================
-- The raw secret is returned once to the admin; only its hash is retained.

CREATE OR REPLACE FUNCTION public.approve_payment(
    p_order_id UUID
)
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
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;

    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND OR v_order.status <> 'payment_submitted' THEN
        RAISE EXCEPTION 'Only submitted payments can be approved';
    END IF;

    SELECT * INTO v_payment FROM public.payment_submissions ps
    WHERE ps.order_id = p_order_id AND ps.status = 'submitted'
    ORDER BY ps.submitted_at DESC LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No submitted payment found';
    END IF;

    v_token := encode(gen_random_bytes(32), 'hex');
    UPDATE public.payment_submissions SET status = 'verified', verified_at = NOW(), verified_by = auth.uid()
    WHERE id = v_payment.id;
    UPDATE public.orders SET status = 'verified', updated_at = NOW() WHERE id = v_order.id;
    INSERT INTO public.downloads (order_id, book_id, customer_id, token_hash, status, expires_at)
    VALUES (v_order.id, v_order.book_id, v_order.customer_id, encode(digest(v_token, 'sha256'), 'hex'), 'active', NOW() + INTERVAL '7 days');

    RETURN QUERY SELECT v_order.id, v_order.order_number, v_token;
END;
$$;


-- ============================================================
-- 17B. REGENERATE BUYER DOWNLOAD LINK (admin)
-- ============================================================

CREATE OR REPLACE FUNCTION public.regenerate_buyer_download(
    p_order_id UUID
)
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


-- ============================================================
-- 18. REJECT PAYMENT FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.reject_payment(
    p_order_id UUID,
    p_reason TEXT
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
BEGIN

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;


    SELECT *
    INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;


    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found';
    END IF;


    UPDATE public.payment_submissions
    SET
        status = 'rejected',
        verified_at = NOW(),
        verified_by = auth.uid(),
        admin_note = p_reason
    WHERE id = (
        SELECT id
        FROM public.payment_submissions
        WHERE order_id = p_order_id
        ORDER BY submitted_at DESC
        LIMIT 1
    );


    UPDATE public.orders
    SET
        status = 'rejected',
        updated_at = NOW()
    WHERE id = p_order_id
    RETURNING * INTO v_order;


    RETURN v_order;

END;
$$;


-- ============================================================
-- 19. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.downloads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 20. BOOK POLICIES
-- ============================================================

CREATE POLICY "Public can view published books"
ON public.books
FOR SELECT
TO anon, authenticated
USING (
    status = 'published'
    OR public.is_admin()
);


CREATE POLICY "Admins can manage books"
ON public.books
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- ============================================================
-- 21. CUSTOMER POLICIES
-- ============================================================

CREATE POLICY "Customers can create customer record"
ON public.customers
FOR INSERT
TO anon, authenticated
WITH CHECK (true);


CREATE POLICY "Admins can view customers"
ON public.customers
FOR SELECT
TO authenticated
USING (public.is_admin());


CREATE POLICY "Admins can update customers"
ON public.customers
FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- ============================================================
-- 22. ORDER POLICIES
-- ============================================================

CREATE POLICY "Customers can create orders through function"
ON public.orders
FOR INSERT
TO anon, authenticated
WITH CHECK (false);


CREATE POLICY "Admins can view all orders"
ON public.orders
FOR SELECT
TO authenticated
USING (public.is_admin());


CREATE POLICY "Admins can update orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- ============================================================
-- 23. PAYMENT POLICIES
-- ============================================================

CREATE POLICY "Customers submit payments through function"
ON public.payment_submissions
FOR INSERT
TO anon, authenticated
WITH CHECK (false);


CREATE POLICY "Admins can view payment submissions"
ON public.payment_submissions
FOR SELECT
TO authenticated
USING (public.is_admin());


CREATE POLICY "Admins can update payments"
ON public.payment_submissions
FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- ============================================================
-- 24. DOWNLOAD POLICIES
-- ============================================================

CREATE POLICY "Admins can manage downloads"
ON public.downloads
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- ============================================================
-- 25. REVIEW POLICIES
-- ============================================================

CREATE POLICY "Public can view approved reviews"
ON public.reviews
FOR SELECT
TO anon, authenticated
USING (
    approved = true
    OR public.is_admin()
);


CREATE POLICY "Public can submit reviews"
ON public.reviews
FOR INSERT
TO anon, authenticated
WITH CHECK (
    approved = false
);


CREATE POLICY "Admins can manage reviews"
ON public.reviews
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- ============================================================
-- 26. ADMIN USER POLICIES
-- ============================================================

CREATE POLICY "Admins can view admin users"
ON public.admin_users
FOR SELECT
TO authenticated
USING (public.is_admin());


CREATE POLICY "Admins can manage admin users"
ON public.admin_users
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- ============================================================
-- 27. GRANTS FOR FUNCTIONS
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.create_order(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_payment(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_payment(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reject_payment(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.regenerate_buyer_download(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_order(
    UUID,
    TEXT,
    TEXT
)
TO anon, authenticated;


GRANT EXECUTE ON FUNCTION public.submit_payment(
    UUID,
    TEXT,
    TEXT
)
TO anon, authenticated;


GRANT EXECUTE ON FUNCTION public.reject_payment(
    UUID,
    TEXT
)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.approve_payment(UUID) TO authenticated;

GRANT EXECUTE ON FUNCTION public.regenerate_buyer_download(UUID) TO authenticated;


-- ============================================================
-- 28. INSERT FIRST BOOK
-- ============================================================
--
-- The website will immediately have this book available.
--
-- Change the price here if required.
--

INSERT INTO public.books (
    slug,
    title,
    subtitle,
    description,
    short_description,
    author,
    cover_image_url,
    preview_url,
    file_path,
    price,
    currency,
    category,
    page_count,
    language,
    status,
    featured,
    published_at
)
VALUES (
    'the-ai-advantage',

    'The AI Advantage',

    'AI + Career + Personal Productivity',

    'A practical guide to working smarter, growing faster, and staying relevant in the age of AI. Learn how to integrate AI into everyday workflows, improve productivity, develop valuable skills, and build a practical career advantage.',

    'A practical guide to AI, career growth and personal productivity.',

    'SK',

    NULL,

    NULL,

    'ebooks/the-ai-advantage.pdf',

    399.00,

    'INR',

    'AI, Career & Productivity',

    50,

    'English',

    'published',

    TRUE,

    NOW()
)
ON CONFLICT (slug)
DO UPDATE SET
    title = EXCLUDED.title,
    subtitle = EXCLUDED.subtitle,
    description = EXCLUDED.description,
    short_description = EXCLUDED.short_description,
    author = EXCLUDED.author,
    price = EXCLUDED.price,
    currency = EXCLUDED.currency,
    category = EXCLUDED.category,
    page_count = EXCLUDED.page_count,
    language = EXCLUDED.language,
    status = EXCLUDED.status,
    featured = EXCLUDED.featured,
    updated_at = NOW();


-- ============================================================
-- 29. OPTIONAL FUTURE BOOKS
-- ============================================================
--
-- These are intentionally NOT published.
-- You can enable them later.
--

INSERT INTO public.books (
    slug,
    title,
    subtitle,
    description,
    short_description,
    author,
    price,
    currency,
    category,
    language,
    status,
    featured
)
VALUES

(
    'the-money-advantage',

    'The Money Advantage',

    'Personal Finance & Better Money Decisions',

    'A practical guide to understanding money, improving financial habits and making better everyday financial decisions.',

    'Practical ideas for building better money habits.',

    'SK',

    399.00,

    'INR',

    'Money & Personal Finance',

    'English',

    'coming_soon',

    FALSE
),

(
    'the-focus-advantage',

    'The Focus Advantage',

    'Attention, Productivity & Deep Work',

    'A practical guide to protecting your attention, reducing distraction and building a more focused way of working.',

    'A practical system for better focus and productivity.',

    'SK',

    399.00,

    'INR',

    'Productivity',

    'English',

    'coming_soon',

    FALSE
)

ON CONFLICT (slug)
DO NOTHING;


-- ============================================================
-- 30. STORAGE BUCKETS
-- ============================================================
--
-- Public bucket:
--   Covers and preview images
--
-- Private bucket:
--   Full ebooks
--
-- NOTE:
-- Depending on your Supabase project configuration, you may
-- prefer creating these buckets through Storage UI.
--

INSERT INTO storage.buckets (
    id,
    name,
    public
)
VALUES
(
    'mindora-public',
    'mindora-public',
    TRUE
),
(
    'mindora-private',
    'mindora-private',
    FALSE
)
ON CONFLICT (id)
DO NOTHING;


-- ============================================================
-- 31. STORAGE POLICIES — PUBLIC ASSETS
-- ============================================================

CREATE POLICY "Public can view Mindora public assets"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (
    bucket_id = 'mindora-public'
);


CREATE POLICY "Admins can upload Mindora public assets"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'mindora-public'
    AND public.is_admin()
);


CREATE POLICY "Admins can update Mindora public assets"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'mindora-public'
    AND public.is_admin()
)
WITH CHECK (
    bucket_id = 'mindora-public'
    AND public.is_admin()
);


CREATE POLICY "Admins can delete Mindora public assets"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'mindora-public'
    AND public.is_admin()
);


-- ============================================================
-- 32. STORAGE POLICIES — PRIVATE EBOOKS
-- ============================================================

CREATE POLICY "Admins can manage private ebooks"
ON storage.objects
FOR ALL
TO authenticated
USING (
    bucket_id = 'mindora-private'
    AND public.is_admin()
)
WITH CHECK (
    bucket_id = 'mindora-private'
    AND public.is_admin()
);


-- ============================================================
-- 33. BASIC DATABASE VERIFICATION
-- ============================================================

SELECT
    'books' AS table_name,
    COUNT(*) AS rows
FROM public.books

UNION ALL

SELECT
    'customers',
    COUNT(*)
FROM public.customers

UNION ALL

SELECT
    'orders',
    COUNT(*)
FROM public.orders

UNION ALL

SELECT
    'payment_submissions',
    COUNT(*)
FROM public.payment_submissions

UNION ALL

SELECT
    'downloads',
    COUNT(*)
FROM public.downloads

UNION ALL

SELECT
    'reviews',
    COUNT(*)
FROM public.reviews

UNION ALL

SELECT
    'admin_users',
    COUNT(*)
FROM public.admin_users;


-- ============================================================
-- 34. SHOW BOOKS
-- ============================================================

SELECT
    id,
    slug,
    title,
    subtitle,
    price,
    currency,
    status,
    featured
FROM public.books
ORDER BY created_at DESC;


-- ============================================================
-- END OF MINDORA DATABASE SETUP
-- ============================================================
