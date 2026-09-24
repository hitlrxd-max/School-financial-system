-- Dhiaa Al Mustaqbal School
-- Neon/PostgreSQL migration
-- Phase 4: super admin role and classes

INSERT INTO app.roles (code, name_ar, description_ar)
VALUES (
  'super_admin',
  'المدير العام',
  'صلاحية كاملة على جميع الفروع والإعدادات'
)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION app.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT app.current_role_code() IN ('admin', 'super_admin');
$$;

CREATE OR REPLACE FUNCTION app.can_manage_students()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT app.current_role_code() IN ('admin', 'super_admin', 'student_affairs');
$$;

CREATE OR REPLACE FUNCTION app.can_manage_finance()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT app.current_role_code() IN ('admin', 'super_admin', 'finance');
$$;

CREATE TABLE IF NOT EXISTS app.classes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  stage TEXT NOT NULL,
  grade TEXT NOT NULL,
  branch_id UUID NOT NULL REFERENCES app.branches(id) ON DELETE RESTRICT,
  academic_year_id UUID NOT NULL REFERENCES app.academic_years(id) ON DELETE RESTRICT,
  capacity INTEGER CHECK (capacity IS NULL OR capacity > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT classes_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT classes_stage_not_blank CHECK (length(btrim(stage)) > 0),
  CONSTRAINT classes_grade_not_blank CHECK (length(btrim(grade)) > 0),
  CONSTRAINT classes_scope_unique UNIQUE (name, branch_id, academic_year_id)
);

CREATE INDEX IF NOT EXISTS classes_branch_year_idx
  ON app.classes (branch_id, academic_year_id, is_active);

ALTER TABLE app.students
  ADD COLUMN IF NOT EXISTS class_id UUID REFERENCES app.classes(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS students_class_idx
  ON app.students (class_id);

DROP TRIGGER IF EXISTS classes_touch_updated_at ON app.classes;
CREATE TRIGGER classes_touch_updated_at
BEFORE UPDATE ON app.classes
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

ALTER TABLE app.classes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS classes_read_by_scope ON app.classes;
CREATE POLICY classes_read_by_scope
ON app.classes
FOR SELECT
USING (app.is_admin() OR branch_id = app.current_branch_id());

DROP POLICY IF EXISTS classes_manage_by_role ON app.classes;
CREATE POLICY classes_manage_by_role
ON app.classes
FOR ALL
USING (app.can_manage_students() AND (app.is_admin() OR branch_id = app.current_branch_id()))
WITH CHECK (app.can_manage_students() AND (app.is_admin() OR branch_id = app.current_branch_id()));