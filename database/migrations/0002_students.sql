-- Dhiaa Al Mustaqbal School
-- Neon/PostgreSQL migration
-- Phase 2: students and guardians

CREATE TABLE IF NOT EXISTS app.guardians (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  relationship TEXT NOT NULL,
  phone TEXT NOT NULL,
  alternate_phone TEXT,
  address TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT guardians_full_name_not_blank CHECK (length(btrim(full_name)) > 0),
  CONSTRAINT guardians_relationship_not_blank CHECK (length(btrim(relationship)) > 0),
  CONSTRAINT guardians_phone_not_blank CHECK (length(btrim(phone)) > 0)
);

CREATE TABLE IF NOT EXISTS app.students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_number TEXT NOT NULL,
  full_name TEXT NOT NULL,
  registration_number TEXT NOT NULL,
  seat_number TEXT,
  branch_id UUID NOT NULL REFERENCES app.branches(id) ON DELETE RESTRICT,
  academic_year_id UUID NOT NULL REFERENCES app.academic_years(id) ON DELETE RESTRICT,
  stage TEXT NOT NULL,
  grade TEXT NOT NULL,
  birth_date DATE,
  gender TEXT NOT NULL DEFAULT 'unspecified'
    CHECK (gender IN ('male', 'female', 'unspecified')),
  phone TEXT,
  address TEXT,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive', 'graduated', 'withdrawn')),
  notes TEXT,
  is_archived BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  archived_at TIMESTAMPTZ,
  CONSTRAINT students_number_not_blank CHECK (length(btrim(student_number)) > 0),
  CONSTRAINT students_name_not_blank CHECK (length(btrim(full_name)) > 0),
  CONSTRAINT students_registration_not_blank CHECK (length(btrim(registration_number)) > 0),
  CONSTRAINT students_stage_not_blank CHECK (length(btrim(stage)) > 0),
  CONSTRAINT students_grade_not_blank CHECK (length(btrim(grade)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS students_number_scope_unique
  ON app.students (branch_id, academic_year_id, lower(student_number));

CREATE UNIQUE INDEX IF NOT EXISTS students_registration_scope_unique
  ON app.students (branch_id, academic_year_id, lower(registration_number));

CREATE INDEX IF NOT EXISTS students_branch_year_idx
  ON app.students (branch_id, academic_year_id);

CREATE INDEX IF NOT EXISTS students_name_search_idx
  ON app.students (lower(full_name));

CREATE INDEX IF NOT EXISTS students_phone_search_idx
  ON app.students (phone)
  WHERE phone IS NOT NULL;

CREATE INDEX IF NOT EXISTS students_active_idx
  ON app.students (is_archived, status);

CREATE TABLE IF NOT EXISTS app.student_guardians (
  student_id UUID NOT NULL REFERENCES app.students(id) ON DELETE CASCADE,
  guardian_id UUID NOT NULL REFERENCES app.guardians(id) ON DELETE CASCADE,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (student_id, guardian_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS student_one_primary_guardian_unique
  ON app.student_guardians (student_id)
  WHERE is_primary = true;

CREATE INDEX IF NOT EXISTS student_guardians_guardian_idx
  ON app.student_guardians (guardian_id);

CREATE UNIQUE INDEX IF NOT EXISTS guardians_phone_unique
  ON app.guardians (lower(phone));

DROP TRIGGER IF EXISTS guardians_touch_updated_at ON app.guardians;
CREATE TRIGGER guardians_touch_updated_at
BEFORE UPDATE ON app.guardians
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

DROP TRIGGER IF EXISTS students_touch_updated_at ON app.students;
CREATE TRIGGER students_touch_updated_at
BEFORE UPDATE ON app.students
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE OR REPLACE FUNCTION app.can_manage_students()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT app.current_role_code() IN ('admin', 'student_affairs');
$$;

ALTER TABLE app.guardians ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.student_guardians ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS students_read_by_scope ON app.students;
CREATE POLICY students_read_by_scope
ON app.students
FOR SELECT
USING (
  app.is_admin()
  OR branch_id = app.current_branch_id()
);

DROP POLICY IF EXISTS students_manage_by_role ON app.students;
CREATE POLICY students_manage_by_role
ON app.students
FOR ALL
USING (
  app.can_manage_students()
  AND (app.is_admin() OR branch_id = app.current_branch_id())
)
WITH CHECK (
  app.can_manage_students()
  AND (app.is_admin() OR branch_id = app.current_branch_id())
);

DROP POLICY IF EXISTS guardians_read_by_student_scope ON app.guardians;
CREATE POLICY guardians_read_by_student_scope
ON app.guardians
FOR SELECT
USING (
  app.is_admin()
  OR EXISTS (
    SELECT 1
    FROM app.student_guardians sg
    JOIN app.students s ON s.id = sg.student_id
    WHERE sg.guardian_id = app.guardians.id
      AND s.branch_id = app.current_branch_id()
  )
);

DROP POLICY IF EXISTS guardians_manage_by_role ON app.guardians;
CREATE POLICY guardians_manage_by_role
ON app.guardians
FOR ALL
USING (app.can_manage_students())
WITH CHECK (app.can_manage_students());

DROP POLICY IF EXISTS student_guardians_read_by_scope ON app.student_guardians;
CREATE POLICY student_guardians_read_by_scope
ON app.student_guardians
FOR SELECT
USING (
  app.is_admin()
  OR EXISTS (
    SELECT 1
    FROM app.students s
    WHERE s.id = student_id
      AND s.branch_id = app.current_branch_id()
  )
);

DROP POLICY IF EXISTS student_guardians_manage_by_role ON app.student_guardians;
CREATE POLICY student_guardians_manage_by_role
ON app.student_guardians
FOR ALL
USING (app.can_manage_students())
WITH CHECK (app.can_manage_students());