-- Dhiaa Al Mustaqbal School
-- Neon/PostgreSQL core migration
-- Phase 1: users, roles, branches, and academic years

BEGIN;

CREATE SCHEMA IF NOT EXISTS app;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS app.roles (
  code TEXT PRIMARY KEY,
  name_ar TEXT NOT NULL,
  description_ar TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app.roles (code, name_ar, description_ar)
VALUES
  ('admin', 'مدير النظام', 'صلاحية كاملة على النظام'),
  ('finance', 'موظف المالية', 'إدارة الأقساط والمدفوعات والمصروفات والتقارير المالية'),
  ('student_affairs', 'شؤون الطلاب', 'إدارة الطلاب والحضور وتقاريرهم'),
  ('hr', 'الموارد البشرية', 'إدارة الموظفين والمعلمين ومستنداتهم'),
  ('archive', 'موظف الأرشيف', 'إدارة الصادر والوارد والقرارات والمراسلات')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS app.branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  archived_at TIMESTAMPTZ,
  CONSTRAINT branches_name_not_blank CHECK (length(btrim(name)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS branches_active_name_unique
  ON app.branches (lower(name))
  WHERE archived_at IS NULL;

CREATE TABLE IF NOT EXISTS app.profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  password_hash TEXT,
  role_code TEXT NOT NULL REFERENCES app.roles(code),
  branch_id UUID REFERENCES app.branches(id) ON DELETE RESTRICT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  CONSTRAINT profiles_full_name_not_blank CHECK (length(btrim(full_name)) > 0),
  CONSTRAINT profiles_email_not_blank CHECK (length(btrim(email)) > 3)
);

CREATE UNIQUE INDEX IF NOT EXISTS profiles_email_unique
  ON app.profiles (lower(email));

CREATE INDEX IF NOT EXISTS profiles_branch_id_idx
  ON app.profiles (branch_id);

CREATE INDEX IF NOT EXISTS profiles_role_code_idx
  ON app.profiles (role_code);

CREATE TABLE IF NOT EXISTS app.academic_years (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  starts_on DATE NOT NULL,
  ends_on DATE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT academic_years_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT academic_years_valid_range CHECK (ends_on > starts_on)
);

CREATE UNIQUE INDEX IF NOT EXISTS academic_years_name_unique
  ON app.academic_years (lower(name));

CREATE INDEX IF NOT EXISTS academic_years_active_idx
  ON app.academic_years (is_active)
  WHERE is_active = true;

CREATE OR REPLACE FUNCTION app.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS branches_touch_updated_at ON app.branches;
CREATE TRIGGER branches_touch_updated_at
BEFORE UPDATE ON app.branches
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

DROP TRIGGER IF EXISTS profiles_touch_updated_at ON app.profiles;
CREATE TRIGGER profiles_touch_updated_at
BEFORE UPDATE ON app.profiles
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

DROP TRIGGER IF EXISTS academic_years_touch_updated_at ON app.academic_years;
CREATE TRIGGER academic_years_touch_updated_at
BEFORE UPDATE ON app.academic_years
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- The Next.js server sets these values transaction-locally after Auth.js
-- authenticates a request:
--   SET LOCAL app.user_id = '<profile uuid>';
--   SET LOCAL app.role_code = '<role code>';
--   SET LOCAL app.branch_id = '<branch uuid>';
-- Direct browser connections are never given DATABASE_URL.
CREATE OR REPLACE FUNCTION app.current_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.user_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION app.current_role_code()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.role_code', true), '');
$$;

CREATE OR REPLACE FUNCTION app.current_branch_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.branch_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION app.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT app.current_role_code() = 'admin';
$$;

ALTER TABLE app.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.academic_years ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS roles_read_authenticated ON app.roles;
CREATE POLICY roles_read_authenticated
ON app.roles
FOR SELECT
USING (app.current_user_id() IS NOT NULL);

DROP POLICY IF EXISTS branches_read_by_scope ON app.branches;
CREATE POLICY branches_read_by_scope
ON app.branches
FOR SELECT
USING (
  app.is_admin()
  OR id = app.current_branch_id()
);

DROP POLICY IF EXISTS branches_admin_write ON app.branches;
CREATE POLICY branches_admin_write
ON app.branches
FOR ALL
USING (app.is_admin())
WITH CHECK (app.is_admin());

DROP POLICY IF EXISTS profiles_read_by_scope ON app.profiles;
CREATE POLICY profiles_read_by_scope
ON app.profiles
FOR SELECT
USING (
  app.is_admin()
  OR id = app.current_user_id()
  OR branch_id = app.current_branch_id()
);

DROP POLICY IF EXISTS profiles_admin_write ON app.profiles;
CREATE POLICY profiles_admin_write
ON app.profiles
FOR ALL
USING (app.is_admin())
WITH CHECK (app.is_admin());

DROP POLICY IF EXISTS academic_years_read_authenticated ON app.academic_years;
CREATE POLICY academic_years_read_authenticated
ON app.academic_years
FOR SELECT
USING (app.current_user_id() IS NOT NULL);

DROP POLICY IF EXISTS academic_years_admin_write ON app.academic_years;
CREATE POLICY academic_years_admin_write
ON app.academic_years
FOR ALL
USING (app.is_admin())
WITH CHECK (app.is_admin());

COMMIT;