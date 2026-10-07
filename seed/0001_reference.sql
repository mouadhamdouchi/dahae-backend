-- 0001_reference.sql — reference data, safe to run on production.
--
-- Idempotent: every statement is an upsert keyed on a natural key, so running the file twice
-- changes nothing. Run it after the migrations and before 0002_catalogue.sql.
--
-- What is deliberately NOT here: accounts, grants, payments, teachers. Those need real
-- `auth.users` rows, and inventing sign-ins in a live project would put four fictional
-- learners in the super admin's Accès screen on day one. The demonstration data stays in
-- `frontend/lib/demo-data/`, which is per-browser and never touches this database.

-- ---------------------------------------------------------------------------
-- Centres
--
-- Fes is the launch centre. Tanger is enabled by the roadmap, so there is no row for it —
-- an inactive row nobody asked for is a row somebody eventually activates by accident.
-- ---------------------------------------------------------------------------

insert into public.centers (slug, name, city, is_active)
values ('fes', 'Dahae Academy — Fès', 'Fès', true)
on conflict (slug) do update
  set name = excluded.name,
      city = excluded.city,
      is_active = excluded.is_active;

-- ---------------------------------------------------------------------------
-- The school calendar
--
-- The Moroccan school year runs September to June, in two semesters. Two years are seeded:
-- the one that has just finished and the one that starts now, because DEC-062 — a paid
-- semester stays open after it ends — is only observable when a past term exists to hold a
-- past grant.
-- ---------------------------------------------------------------------------

insert into public.academic_terms (school_year, semester, starts_on, ends_on)
values
  ('2025-2026', 's1', date '2025-09-01', date '2026-01-31'),
  ('2025-2026', 's2', date '2026-02-01', date '2026-06-30'),
  ('2026-2027', 's1', date '2026-09-01', date '2027-01-31'),
  ('2026-2027', 's2', date '2027-02-01', date '2027-06-30')
on conflict (school_year, semester) do update
  set starts_on = excluded.starts_on,
      ends_on = excluded.ends_on;

-- ---------------------------------------------------------------------------
-- Settings
--
-- One row, and the source of every contact detail the public pages render
-- (frontend/lib/settings.ts). The WhatsApp number below is a placeholder and must be replaced
-- with the academy's real number before launch (open question H1) — it is the only action on
-- the entire public site.
-- ---------------------------------------------------------------------------

insert into public.settings (id, whatsapp_number, email, location, completion_threshold)
values (true, '212600000000', 'contact@dahae-academy.ma', 'Fès, Maroc', 80)
on conflict (id) do nothing;
