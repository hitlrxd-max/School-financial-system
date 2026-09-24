/**
 * Production-safe Neon seed.
 *
 * Required runtime secrets:
 *   DATABASE_URL  - managed by Neon/Replit; never commit it.
 *   SEED_ADMIN_PASSWORD - supplied through the workspace Secrets flow.
 *
 * The admin password is hashed in memory and is never written to source,
 * logs, SQL text, or seed data.
 */
import { Pool } from "@neondatabase/serverless";
import bcrypt from "bcryptjs";

const databaseUrl = process.env.DATABASE_URL;
const adminPassword = process.env.SEED_ADMIN_PASSWORD;
const adminEmail = "hitlrxd@gmail.com";

if (!databaseUrl) {
  throw new Error("DATABASE_URL is required");
}

if (!adminPassword) {
  throw new Error("SEED_ADMIN_PASSWORD must be provided through Secrets");
}

const pool = new Pool({ connectionString: databaseUrl });
const client = await pool.connect();

try {
  await client.query("BEGIN");

  const roleResult = await client.query<{ code: string }>(
    `SELECT code
     FROM app.roles
     WHERE code = 'super_admin'`
  );

  if (roleResult.rowCount !== 1) {
    throw new Error("super_admin role is missing; run database migrations first");
  }

  const branchResult = await client.query<{ id: string }>(
    `INSERT INTO app.branches (name, address, phone, status)
     VALUES ($1, $2, $3, 'active')
     ON CONFLICT ((lower(name))) WHERE archived_at IS NULL
     DO UPDATE SET status = 'active', updated_at = now()
     RETURNING id`,
    ["الفرع الرئيسي", "طرابلس - ليبيا", null]
  );
  const branchId = branchResult.rows[0]?.id;

  if (!branchId) {
    throw new Error("Unable to create the primary branch");
  }

  const yearResult = await client.query<{ id: string }>(
    `INSERT INTO app.academic_years (name, starts_on, ends_on, is_active)
     VALUES ($1, $2, $3, true)
     ON CONFLICT ((lower(name)))
     DO UPDATE SET is_active = true, updated_at = now()
     RETURNING id`,
    ["2026/2027", "2026-09-01", "2027-06-30"]
  );
  const academicYearId = yearResult.rows[0]?.id;

  if (!academicYearId) {
    throw new Error("Unable to create the active academic year");
  }

  const passwordHash = await bcrypt.hash(adminPassword, 12);
  const adminResult = await client.query<{ id: string }>(
    `INSERT INTO app.profiles
      (full_name, email, password_hash, role_code, branch_id, is_active)
     VALUES ($1, lower($2), $3, 'super_admin', $4, true)
     ON CONFLICT ((lower(email)))
     DO UPDATE SET
       full_name = EXCLUDED.full_name,
       password_hash = EXCLUDED.password_hash,
       role_code = 'super_admin',
       branch_id = EXCLUDED.branch_id,
       is_active = true,
       updated_at = now()
     RETURNING id`,
    ["المدير العام", adminEmail, passwordHash, branchId]
  );
  const adminId = adminResult.rows[0]?.id;

  if (!adminId) {
    throw new Error("Unable to create the administrator profile");
  }

  await client.query(
    `SELECT
       set_config('app.user_id', $1, true),
       set_config('app.role_code', 'super_admin', true),
       set_config('app.branch_id', $2, true)`,
    [adminId, branchId]
  );

  const classRows = [
    ["الصف الأول - فصل أ", "التعليم الأساسي", "الأول", 28],
    ["الصف الرابع - فصل أ", "التعليم الأساسي", "الرابع", 30],
    ["الصف التاسع - فصل أ", "التعليم الأساسي", "التاسع", 30],
  ];
  const classIds: string[] = [];

  for (const [name, stage, grade, capacity] of classRows) {
    const result = await client.query<{ id: string }>(
      `INSERT INTO app.classes
        (name, stage, grade, branch_id, academic_year_id, capacity)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (name, branch_id, academic_year_id)
       DO UPDATE SET is_active = true, capacity = EXCLUDED.capacity, updated_at = now()
       RETURNING id`,
      [name, stage, grade, branchId, academicYearId, capacity]
    );
    classIds.push(result.rows[0].id);
  }

  const guardianRows = [
    ["محمد سالم الورفلي", "الأب", "0912000001", "حي الأندلس"],
    ["سعاد علي المقريف", "الأم", "0912000002", "شارع الجمهورية"],
    ["خالد عمر الزنتاني", "الأب", "0912000003", "طريق الشط"],
  ];
  const guardianIds: string[] = [];

  for (const [fullName, relationship, phone, address] of guardianRows) {
    const result = await client.query<{ id: string }>(
      `INSERT INTO app.guardians (full_name, relationship, phone, address)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT ((lower(phone)))
       DO UPDATE SET
         full_name = EXCLUDED.full_name,
         relationship = EXCLUDED.relationship,
         address = EXCLUDED.address,
         updated_at = now()
       RETURNING id`,
      [fullName, relationship, phone, address]
    );
    guardianIds.push(result.rows[0].id);
  }

  const studentRows = [
    ["ST-2026-0001", "أحمد محمد سالم", "REG-2026-0001", classIds[0], guardianIds[0], "male", "0913000001"],
    ["ST-2026-0002", "ليان خالد علي", "REG-2026-0002", classIds[0], guardianIds[1], "female", "0913000002"],
    ["ST-2026-0003", "يوسف عمر خالد", "REG-2026-0003", classIds[1], guardianIds[2], "male", "0913000003"],
    ["ST-2026-0004", "مريم سالم محمد", "REG-2026-0004", classIds[1], guardianIds[0], "female", "0913000004"],
    ["ST-2026-0005", "عبدالله علي عمر", "REG-2026-0005", classIds[2], guardianIds[2], "male", "0913000005"],
    ["ST-2026-0006", "نور محمد خالد", "REG-2026-0006", classIds[2], guardianIds[1], "female", "0913000006"],
  ];

  const studentIds: string[] = [];
  for (const [studentNumber, fullName, registrationNumber, classId, guardianId, gender, phone] of studentRows) {
    const result = await client.query<{ id: string }>(
      `INSERT INTO app.students
        (student_number, full_name, registration_number, branch_id, academic_year_id,
         stage, grade, gender, phone, class_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (branch_id, academic_year_id, lower(student_number))
       DO UPDATE SET
         full_name = EXCLUDED.full_name,
         registration_number = EXCLUDED.registration_number,
         class_id = EXCLUDED.class_id,
         phone = EXCLUDED.phone,
         is_archived = false,
         updated_at = now()
       RETURNING id`,
      [studentNumber, fullName, registrationNumber, branchId, academicYearId, "التعليم الأساسي", "عام", gender, phone, classId]
    );
    const studentId = result.rows[0].id;
    studentIds.push(studentId);

    await client.query(
      `INSERT INTO app.student_guardians (student_id, guardian_id, is_primary)
       VALUES ($1, $2, true)
       ON CONFLICT (student_id, guardian_id)
       DO UPDATE SET is_primary = true`,
      [studentId, guardianId]
    );
  }

  const feeIds: string[] = [];
  for (let index = 0; index < studentIds.length; index += 1) {
    const result = await client.query<{ id: string }>(
      `INSERT INTO app.student_fees
        (student_id, branch_id, academic_year_id, total_amount, notes)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (student_id, academic_year_id)
       DO UPDATE SET total_amount = EXCLUDED.total_amount, updated_at = now()
       RETURNING id`,
      [studentIds[index], branchId, academicYearId, 5000, "رسوم السنة الدراسية 2026/2027"]
    );
    feeIds.push(result.rows[0].id);
  }

  await client.query(
    `INSERT INTO app.discounts
      (student_fee_id, fixed_amount, reason, created_by)
     SELECT $1, $2, $3, $4
     WHERE NOT EXISTS (
       SELECT 1
       FROM app.discounts
       WHERE student_fee_id = $1
         AND fixed_amount = $2
         AND reason = $3
         AND is_active = true
     )`,
    [feeIds[0], 500, "خصم الأشقاء", adminId]
  );

  await client.query(
    `INSERT INTO app.payments
      (student_fee_id, branch_id, academic_year_id, amount, payment_method,
       transaction_number, recorded_by, notes)
     VALUES ($1, $2, $3, $4, 'cash', $5, $6, $7)
     ON CONFLICT (transaction_number) DO NOTHING`,
    [feeIds[0], branchId, academicYearId, 1000, "SEED-PAY-0001", adminId, "دفعة أولى تجريبية"]
  );

  const categoryResult = await client.query<{ id: string }>(
    `INSERT INTO app.expense_categories (name)
     VALUES ('تشغيل وصيانة')
     ON CONFLICT ((lower(name)))
     DO UPDATE SET is_active = true
     RETURNING id`
  );

  await client.query(
    `INSERT INTO app.expenses
      (expense_number, category_id, branch_id, amount, description,
       payment_method, recorded_by, notes)
     VALUES ($1, $2, $3, $4, $5, 'cash', $6, $7)
     ON CONFLICT (expense_number) DO NOTHING`,
    ["EXP-SEED-0001", categoryResult.rows[0].id, branchId, 500, "صيانة أجهزة الفصل الدراسي", adminId, "سجل تجريبي قابل للحذف"]
  );

  await client.query("COMMIT");
  console.log("Neon seed completed without exposing the administrator password.");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
  await pool.end();
}