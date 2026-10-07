-- 20260829090000_extensions_and_helpers.sql
--
-- The floor everything else stands on: the extensions, the `app` schema, the enumerated
-- vocabularies and the two touch triggers.
--
-- Why an `app` schema. Every helper an RLS policy calls is `security definer`, which means
-- it runs with the privileges of its owner and ignores RLS. That is exactly what a policy
-- helper must do — a policy on `user_roles` that reads `user_roles` through RLS recurses
-- until Postgres gives up — but it also means these functions are the most dangerous
-- objects in the database. They live in one schema, that schema is not on anybody's search
-- path, and `execute` is granted deliberately, one function at a time.
--
-- Every function here sets `search_path = ''` and fully qualifies every name. Without it a
-- caller can put a table of their own in front of ours and a `security definer` function
-- reads it.
--
-- Forward-only: never edit this file once it is applied (CLAUDE.md). Add another.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
-- `btree_gist` lets an exclusion constraint mix equality (stream, weekday) with overlap
-- (the time range), which is what refuses two séances of the same stream at the same hour.
create extension if not exists btree_gist with schema extensions;

create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Vocabularies
--
-- These are enumerated types rather than free text because each one is a closed list the
-- interface has to translate. Adding a value is `alter type ... add value` in a new
-- migration, which is deliberate friction: a new audit action with no label in the three
-- locales is an audit line nobody can read.
-- ---------------------------------------------------------------------------

-- Three roles, no more (DEC-032). `student` is the absence of an appointment, so it is
-- present here for completeness and almost never stored.
create type app.role as enum ('student', 'teacher', 'super_admin');

-- The unit the offer is sold in (DEC-030, DEC-062). A chapter carries one of these; so does
-- an academic term. Entitlement is the pair (subject, semester).
create type app.semester as enum ('s1', 's2');

create type app.level as enum ('1bac', '2bac');

-- Null at 1ère Bac, where the class is common to both filières (DEC-030).
create type app.filiere as enum ('sciences-economiques', 'sgc');

create type app.modality as enum ('hybrid', 'in_person', 'online');

create type app.resource_kind as enum ('pdf', 'video', 'serie', 'correction');

-- Cash or transfer, recorded after the fact. There is no gateway and no online payment
-- (DEC-037), so there is no `card` and no pending state.
create type app.payment_method as enum ('cash', 'transfer');

create type app.deletion_status as enum ('pending', 'approved', 'refused');

-- Mirrors `AuditAction` in `frontend/lib/demo-data/staff.ts`, which is the list the three
-- message catalogues already carry.
create type app.audit_action as enum (
  'accessGranted',
  'accessExtended',
  'accessRevoked',
  'paymentRecorded',
  'resourceAdded',
  'sessionMoved',
  'sessionProposed',
  'sessionPublished',
  'sessionRefused',
  'courseDrafted',
  'coursePublished',
  'courseDeleted',
  'deletionRequested',
  'deletionApproved',
  'deletionRefused',
  'liveStarted',
  'liveEnded',
  'recordingSaved',
  'recordingRenamed',
  'recordingDeleted',
  'teacherAppointed',
  'teacherSubjectsChanged',
  'teacherRemoved'
);

-- ---------------------------------------------------------------------------
-- Touch triggers
--
-- Two, not one: a single function would have to discover at runtime whether the row it was
-- handed has an `updated_by` column, and doing that through `to_jsonb` on every write is a
-- lot of machinery to avoid writing a second five-line function.
-- ---------------------------------------------------------------------------

create or replace function app.touch()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function app.touch_with_actor()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

comment on schema app is
  'Authorization helpers and shared trigger functions. Everything here is security definer '
  'with an empty search_path; nothing here is exposed through PostgREST.';
