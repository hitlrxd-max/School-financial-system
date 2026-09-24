-- Dhiaa Al Mustaqbal School
-- Neon/PostgreSQL migration
-- Phase 3: fees, discounts, payments, invoices, and expenses

CREATE SEQUENCE IF NOT EXISTS app.invoice_number_seq START WITH 1;

CREATE TABLE IF NOT EXISTS app.student_fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES app.students(id) ON DELETE RESTRICT,
  branch_id UUID NOT NULL REFERENCES app.branches(id) ON DELETE RESTRICT,
  academic_year_id UUID NOT NULL REFERENCES app.academic_years(id) ON DELETE RESTRICT,
  total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT student_fees_student_year_unique
    UNIQUE (student_id, academic_year_id)
);

CREATE INDEX IF NOT EXISTS student_fees_branch_year_idx
  ON app.student_fees (branch_id, academic_year_id);

CREATE TABLE IF NOT EXISTS app.discounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_fee_id UUID NOT NULL REFERENCES app.student_fees(id) ON DELETE CASCADE,
  fixed_amount NUMERIC(12, 2),
  percentage NUMERIC(5, 2),
  reason TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES app.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT discounts_one_type_only CHECK (
    (fixed_amount IS NOT NULL AND fixed_amount >= 0 AND percentage IS NULL)
    OR
    (fixed_amount IS NULL AND percentage IS NOT NULL AND percentage >= 0 AND percentage <= 100)
  ),
  CONSTRAINT discounts_reason_not_blank CHECK (length(btrim(reason)) > 0)
);

CREATE INDEX IF NOT EXISTS discounts_fee_idx
  ON app.discounts (student_fee_id, is_active);

CREATE TABLE IF NOT EXISTS app.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_fee_id UUID NOT NULL REFERENCES app.student_fees(id) ON DELETE RESTRICT,
  branch_id UUID NOT NULL REFERENCES app.branches(id) ON DELETE RESTRICT,
  academic_year_id UUID NOT NULL REFERENCES app.academic_years(id) ON DELETE RESTRICT,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  payment_method TEXT NOT NULL
    CHECK (payment_method IN ('cash', 'card', 'bank_transfer', 'cheque')),
  transaction_number TEXT NOT NULL,
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_by UUID NOT NULL DEFAULT app.current_user_id()
    REFERENCES app.profiles(id) ON DELETE RESTRICT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'completed'
    CHECK (status IN ('completed', 'voided')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT payments_transaction_unique UNIQUE (transaction_number)
);

CREATE INDEX IF NOT EXISTS payments_fee_idx
  ON app.payments (student_fee_id, status);

CREATE INDEX IF NOT EXISTS payments_branch_date_idx
  ON app.payments (branch_id, paid_at DESC);

CREATE TABLE IF NOT EXISTS app.invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number TEXT NOT NULL DEFAULT (
    'INV-' || lpad(nextval('app.invoice_number_seq')::TEXT, 6, '0')
  ),
  payment_id UUID NOT NULL UNIQUE REFERENCES app.payments(id) ON DELETE RESTRICT,
  student_fee_id UUID NOT NULL REFERENCES app.student_fees(id) ON DELETE RESTRICT,
  branch_id UUID NOT NULL REFERENCES app.branches(id) ON DELETE RESTRICT,
  academic_year_id UUID NOT NULL REFERENCES app.academic_years(id) ON DELETE RESTRICT,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  discount_amount NUMERIC(12, 2) NOT NULL CHECK (discount_amount >= 0),
  net_fee NUMERIC(12, 2) NOT NULL CHECK (net_fee >= 0),
  paid_total NUMERIC(12, 2) NOT NULL CHECK (paid_total >= 0),
  remaining NUMERIC(12, 2) NOT NULL CHECK (remaining >= 0),
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES app.profiles(id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS invoices_number_unique
  ON app.invoices (invoice_number);

CREATE INDEX IF NOT EXISTS invoices_branch_date_idx
  ON app.invoices (branch_id, issued_at DESC);

CREATE TABLE IF NOT EXISTS app.expense_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT expense_categories_name_not_blank CHECK (length(btrim(name)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS expense_categories_name_unique
  ON app.expense_categories (lower(name));

CREATE TABLE IF NOT EXISTS app.expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_number TEXT NOT NULL,
  category_id UUID NOT NULL REFERENCES app.expense_categories(id) ON DELETE RESTRICT,
  branch_id UUID NOT NULL REFERENCES app.branches(id) ON DELETE RESTRICT,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  description TEXT NOT NULL,
  payment_method TEXT NOT NULL
    CHECK (payment_method IN ('cash', 'card', 'bank_transfer', 'cheque')),
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_by UUID NOT NULL DEFAULT app.current_user_id()
    REFERENCES app.profiles(id) ON DELETE RESTRICT,
  attachment_path TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT expenses_number_unique UNIQUE (expense_number),
  CONSTRAINT expenses_description_not_blank CHECK (length(btrim(description)) > 0)
);

CREATE INDEX IF NOT EXISTS expenses_branch_date_idx
  ON app.expenses (branch_id, paid_at DESC);

CREATE OR REPLACE FUNCTION app.fee_discount_total(p_fee_id UUID)
RETURNS NUMERIC(12, 2)
LANGUAGE sql
STABLE
AS $$
  SELECT round(
    least(
      sf.total_amount,
      COALESCE(SUM(
        CASE
          WHEN d.fixed_amount IS NOT NULL THEN d.fixed_amount
          ELSE sf.total_amount * d.percentage / 100
        END
      ), 0)
    ),
    2
  )
  FROM app.student_fees sf
  LEFT JOIN app.discounts d
    ON d.student_fee_id = sf.id
   AND d.is_active = true
  WHERE sf.id = p_fee_id
  GROUP BY sf.id, sf.total_amount;
$$;

CREATE OR REPLACE VIEW app.student_fee_summary AS
SELECT
  sf.id,
  sf.student_id,
  sf.branch_id,
  sf.academic_year_id,
  sf.total_amount,
  app.fee_discount_total(sf.id) AS discount_amount,
  round(sf.total_amount - app.fee_discount_total(sf.id), 2) AS net_amount,
  round(COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'completed'), 0), 2) AS paid_amount,
  round(
    greatest(
      0,
      sf.total_amount
      - app.fee_discount_total(sf.id)
      - COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'completed'), 0)
    ),
    2
  ) AS remaining_amount
FROM app.student_fees sf
LEFT JOIN app.payments p ON p.student_fee_id = sf.id
GROUP BY sf.id;

CREATE OR REPLACE FUNCTION app.can_manage_finance()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT app.current_role_code() IN ('admin', 'finance');
$$;

CREATE OR REPLACE FUNCTION app.prepare_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  fee_branch UUID;
  fee_year UUID;
  fee_total NUMERIC(12, 2);
  discount_total NUMERIC(12, 2);
  paid_total NUMERIC(12, 2);
  remaining_total NUMERIC(12, 2);
BEGIN
  IF NOT app.can_manage_finance() THEN
    RAISE EXCEPTION 'not authorized to record payments';
  END IF;

  SELECT branch_id, academic_year_id, total_amount
    INTO fee_branch, fee_year, fee_total
  FROM app.student_fees
  WHERE id = NEW.student_fee_id
  FOR UPDATE;

  IF fee_branch IS NULL THEN
    RAISE EXCEPTION 'student fee record not found';
  END IF;

  discount_total := app.fee_discount_total(NEW.student_fee_id);

  SELECT COALESCE(SUM(amount), 0)
    INTO paid_total
  FROM app.payments
  WHERE student_fee_id = NEW.student_fee_id
    AND status = 'completed';

  remaining_total := greatest(0, fee_total - discount_total - paid_total);

  IF NEW.amount > remaining_total THEN
    RAISE EXCEPTION 'payment exceeds the remaining balance';
  END IF;

  NEW.branch_id := fee_branch;
  NEW.academic_year_id := fee_year;
  NEW.recorded_by := COALESCE(NEW.recorded_by, app.current_user_id());

  IF NEW.recorded_by IS NULL THEN
    RAISE EXCEPTION 'recorded_by is required';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION app.create_payment_invoice()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  fee_total NUMERIC(12, 2);
  discount_total NUMERIC(12, 2);
  paid_total NUMERIC(12, 2);
BEGIN
  IF NEW.status <> 'completed' THEN
    RETURN NEW;
  END IF;

  SELECT total_amount INTO fee_total
  FROM app.student_fees
  WHERE id = NEW.student_fee_id;

  discount_total := app.fee_discount_total(NEW.student_fee_id);

  SELECT COALESCE(SUM(amount), 0) INTO paid_total
  FROM app.payments
  WHERE student_fee_id = NEW.student_fee_id
    AND status = 'completed';

  INSERT INTO app.invoices (
    payment_id,
    student_fee_id,
    branch_id,
    academic_year_id,
    amount,
    discount_amount,
    net_fee,
    paid_total,
    remaining,
    created_by
  )
  VALUES (
    NEW.id,
    NEW.student_fee_id,
    NEW.branch_id,
    NEW.academic_year_id,
    NEW.amount,
    discount_total,
    round(fee_total - discount_total, 2),
    paid_total,
    round(greatest(0, fee_total - discount_total - paid_total), 2),
    NEW.recorded_by
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS payments_prepare_trigger ON app.payments;
CREATE TRIGGER payments_prepare_trigger
BEFORE INSERT ON app.payments
FOR EACH ROW EXECUTE FUNCTION app.prepare_payment();

DROP TRIGGER IF EXISTS payments_invoice_trigger ON app.payments;
CREATE TRIGGER payments_invoice_trigger
AFTER INSERT ON app.payments
FOR EACH ROW EXECUTE FUNCTION app.create_payment_invoice();

DROP TRIGGER IF EXISTS student_fees_touch_updated_at ON app.student_fees;
CREATE TRIGGER student_fees_touch_updated_at
BEFORE UPDATE ON app.student_fees
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

ALTER TABLE app.student_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS student_fees_read_by_scope ON app.student_fees;
CREATE POLICY student_fees_read_by_scope
ON app.student_fees
FOR SELECT
USING (app.is_admin() OR branch_id = app.current_branch_id());

DROP POLICY IF EXISTS student_fees_manage_by_role ON app.student_fees;
CREATE POLICY student_fees_manage_by_role
ON app.student_fees
FOR ALL
USING (app.can_manage_finance() AND (app.is_admin() OR branch_id = app.current_branch_id()))
WITH CHECK (app.can_manage_finance() AND (app.is_admin() OR branch_id = app.current_branch_id()));

DROP POLICY IF EXISTS discounts_read_by_scope ON app.discounts;
CREATE POLICY discounts_read_by_scope
ON app.discounts
FOR SELECT
USING (
  app.is_admin()
  OR EXISTS (
    SELECT 1 FROM app.student_fees sf
    WHERE sf.id = student_fee_id
      AND sf.branch_id = app.current_branch_id()
  )
);

DROP POLICY IF EXISTS discounts_manage_by_role ON app.discounts;
CREATE POLICY discounts_manage_by_role
ON app.discounts
FOR ALL
USING (app.can_manage_finance())
WITH CHECK (app.can_manage_finance());

DROP POLICY IF EXISTS payments_read_by_scope ON app.payments;
CREATE POLICY payments_read_by_scope
ON app.payments
FOR SELECT
USING (app.is_admin() OR branch_id = app.current_branch_id());

DROP POLICY IF EXISTS payments_manage_by_role ON app.payments;
CREATE POLICY payments_manage_by_role
ON app.payments
FOR INSERT
WITH CHECK (app.can_manage_finance() AND (app.is_admin() OR branch_id = app.current_branch_id()));

DROP POLICY IF EXISTS invoices_read_by_scope ON app.invoices;
CREATE POLICY invoices_read_by_scope
ON app.invoices
FOR SELECT
USING (app.is_admin() OR branch_id = app.current_branch_id());

DROP POLICY IF EXISTS expense_categories_read_authenticated ON app.expense_categories;
CREATE POLICY expense_categories_read_authenticated
ON app.expense_categories
FOR SELECT
USING (app.current_user_id() IS NOT NULL);

DROP POLICY IF EXISTS expense_categories_manage_by_role ON app.expense_categories;
CREATE POLICY expense_categories_manage_by_role
ON app.expense_categories
FOR ALL
USING (app.can_manage_finance())
WITH CHECK (app.can_manage_finance());

DROP POLICY IF EXISTS expenses_read_by_scope ON app.expenses;
CREATE POLICY expenses_read_by_scope
ON app.expenses
FOR SELECT
USING (app.is_admin() OR branch_id = app.current_branch_id());

DROP POLICY IF EXISTS expenses_manage_by_role ON app.expenses;
CREATE POLICY expenses_manage_by_role
ON app.expenses
FOR ALL
USING (app.can_manage_finance() AND (app.is_admin() OR branch_id = app.current_branch_id()))
WITH CHECK (app.can_manage_finance() AND (app.is_admin() OR branch_id = app.current_branch_id()));