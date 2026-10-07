-- 20260829090100_identity_and_audit.sql
--
-- Who someone is, what the academy has recorded them as, and the append-only record of the
-- decisions taken about them.
--
-- Three things decided here that everything downstream leans on:
--
-- 1. A student has no role row. Everyone arrives through the same Google sign-in (DEC-034);
--    what makes somebody staff is an appointment the super admin records (DEC-060). So
--    user_roles holds staff only, and app.current_role() answers 'student' for any signed-in
--    person with no row. There is no role column on profiles, because a second place to read
--    the role from is a second place to get it wrong.
--
-- 2. The role is never read from user metadata. auth.users.raw_user_meta_data is writable by
--    the user (security.md section 4). A role that lived there would let anybody appoint
--    themselves.
--
-- 3. Guardian data is required by default, not when a birthdate says so. Most Bac learners
--    are under 18 (security.md section 2) and Google hands us no birthdate. So
--    app.requires_guardian() answers yes unless a date of birth is on file and it is more
--    than eighteen years old. Getting this wrong in the safe direction costs an adult one
--    extra field; getting it wrong in the other direction means processing a minor's data
--    with no consent behind it. DEC-028 is still open and may add retention and wording
--    rules on top; it will not remove these columns.

-- ---------------------------------------------------------------------------
-- Centres
-- ---------------------------------------------------------------------------

create table public.centers (
  id          uuid primary key default extensions.gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name        text not null check (char_length(name) between 1 and 120),
  city        text not null check (char_length(city) between 1 and 120),
  -- Fes is the launch centre; Tanger is enabled by the roadmap, not by a developer
  -- (CLAUDE.md). The column is what enables it, and nothing seeds a second row today.
  is_active   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger centers_touch before update on public.centers
  for each row execute function app.touch();

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id                           uuid primary key references auth.users (id) on delete cascade,
  full_name                    text not null check (char_length(full_name) between 1 and 120),
  email                        text not null check (char_length(email) between 3 and 254),
  avatar_url                   text,
  locale                       text not null default 'fr' check (locale in ('fr', 'ar', 'en')),
  -- The stream the person picked at sign-up. A hint the super admin confirms in the WhatsApp
  -- conversation, never a fact (lib/demo-data/accounts.ts). The foreign key is added by the
  -- catalogue migration, which is where tracks is created.
  declared_track_id            uuid,
  -- Asked at profile completion (FND-06). Null means "we do not know", which is treated as
  -- a minor.
  date_of_birth                date check (date_of_birth > date '1900-01-01'),
  guardian_full_name           text check (char_length(guardian_full_name) between 1 and 120),
  guardian_phone               text check (guardian_phone ~ '^\+?[0-9]{8,15}$'),
  guardian_relationship        text check (char_length(guardian_relationship) between 1 and 40),
  guardian_consent_at          timestamptz,
  guardian_consent_recorded_by uuid references public.profiles (id) on delete set null,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),

  -- A consent timestamp with nobody attached to it records nothing.
  constraint profiles_consent_needs_contact check (
    guardian_consent_at is null
    or (guardian_full_name is not null and guardian_phone is not null)
  )
);

-- One account per address: the super admin searches by it to open an access (DEC-037).
create unique index profiles_email_key on public.profiles (lower(email));
create index profiles_declared_track_idx on public.profiles (declared_track_id);

create trigger profiles_touch before update on public.profiles
  for each row execute function app.touch();

-- A profile is created by the database the moment Supabase Auth creates the user, so there
-- is never a signed-in session without one. security definer because the inserting role at
-- that moment is the auth service, not the person.
create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  insert into public.profiles (id, full_name, email, avatar_url)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', ''),
      split_part(new.email, '@', 1)
    ),
    new.email,
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$fn$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- ---------------------------------------------------------------------------
-- Role assignments
-- ---------------------------------------------------------------------------

create table public.user_roles (
  id          uuid primary key default extensions.gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        app.role not null,
  -- Set when the assignment is bound to one centre. Null means organization-wide, which is
  -- what the super admin is.
  center_id   uuid references public.centers (id) on delete restrict,
  granted_by  uuid references public.profiles (id) on delete set null,
  granted_at  timestamptz not null default now(),

  constraint user_roles_unique unique (user_id, role),
  -- 'student' is the absence of a row, not a row. Storing it would give two ways to say the
  -- same thing and let them disagree.
  constraint user_roles_staff_only check (role <> 'student')
);

create index user_roles_user_idx on public.user_roles (user_id);
create index user_roles_role_idx on public.user_roles (role);

-- ---------------------------------------------------------------------------
-- Authorization helpers
--
-- Every one of these is security definer, which is the point: a policy that reads user_roles
-- through RLS recurses forever, and a policy that reads it through one of these does not.
-- They are the only functions in the database allowed to ignore RLS, and each one answers a
-- single closed question.
-- ---------------------------------------------------------------------------

create or replace function app.role_of(p_user uuid)
returns app.role
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(
    (
      select ur.role
      from public.user_roles ur
      where ur.user_id = p_user
      order by case ur.role when 'super_admin' then 1 else 2 end
      limit 1
    ),
    'student'::app.role
  );
$fn$;

-- Null when nobody is signed in. Deliberately not 'student': a policy that reads this must
-- not be able to mistake a passer-by for a learner.
create or replace function app.current_role()
returns app.role
language sql
stable
security definer
set search_path = ''
as $fn$
  select case when auth.uid() is null then null else app.role_of(auth.uid()) end;
$fn$;

create or replace function app.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select app.current_role() = 'super_admin';
$fn$;

-- Teacher or super admin. The super admin can do everything a teacher can do
-- (roles-permissions.md), and this is where that is true in the database — the same rule
-- capabilities.ts enforces in the application.
create or replace function app.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select app.current_role() in ('teacher', 'super_admin');
$fn$;

create or replace function app.is_signed_in()
returns boolean
language sql
stable
set search_path = ''
as $fn$
  select auth.uid() is not null;
$fn$;

-- Yes unless a date of birth is on file and it is more than eighteen years old. See the
-- header: not knowing is treated as a minor, on purpose.
create or replace function app.requires_guardian(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select not exists (
    select 1
    from public.profiles p
    where p.id = p_user
      and p.date_of_birth is not null
      and p.date_of_birth <= (current_date - interval '18 years')
  );
$fn$;

-- The last super admin cannot be removed, and no screen may create one.
--
-- auth.uid() is null for the service role and for a migration, and non-null for anything
-- that arrives with a session. So this refuses every request-bound write to an owner row
-- while leaving the seed and the SQL console able to do it — which is the shape DEC-060 asks
-- for: the owner cannot be appointed or removed from a screen, because a screen that can
-- remove the last owner can lock everyone out.
create or replace function app.protect_owner_role()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
declare
  target app.role := coalesce(new.role, old.role);
begin
  if target = 'super_admin' and auth.uid() is not null then
    raise exception 'the super admin role is not assignable from the application'
      using errcode = 'insufficient_privilege';
  end if;

  if tg_op in ('DELETE', 'UPDATE') and old.role = 'super_admin' then
    if (select count(*) from public.user_roles where role = 'super_admin') <= 1 then
      raise exception 'the last super admin cannot be removed'
        using errcode = 'restrict_violation';
    end if;
  end if;

  return case tg_op when 'DELETE' then old else new end;
end;
$fn$;

create trigger user_roles_protect_owner
  before insert or update or delete on public.user_roles
  for each row execute function app.protect_owner_role();

-- ---------------------------------------------------------------------------
-- Audit
--
-- Append-only, and append-only for everybody. The trigger refuses an update or a delete
-- whoever is asking, including the service role and the owner of the table — because the
-- log's whole job is to record a role that has no second administrator watching it
-- (roles-permissions.md). Undoing that is a deliberate migration, not a stray statement.
-- ---------------------------------------------------------------------------

create table public.audit_events (
  id            uuid primary key default extensions.gen_random_uuid(),
  action        app.audit_action not null,
  actor_id      uuid references public.profiles (id) on delete set null,
  actor_role    app.role not null,
  -- What the line is about, as it read at the time: a learner's given name, a chapter title,
  -- a seance label. Kept as text so the row survives the thing it names being deleted.
  subject_label text not null check (char_length(subject_label) between 1 and 200),
  target_type   text check (char_length(target_type) between 1 and 40),
  target_id     uuid,
  metadata      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),

  -- A stream key, an ingest address and a playback address are credentials, and DEC-066 says
  -- in as many words that none of them appears in an audit line. A comment would be advice;
  -- this is a refusal.
  constraint audit_metadata_carries_no_credential check (
    not (metadata ?| array[
      'stream_key', 'streamKey',
      'ingest_url', 'ingestUrl',
      'playback_url', 'playbackUrl',
      'password', 'token', 'secret'
    ])
  )
);

create index audit_events_created_idx on public.audit_events (created_at desc);
create index audit_events_actor_idx on public.audit_events (actor_id, created_at desc);
create index audit_events_target_idx on public.audit_events (target_type, target_id);

create or replace function app.audit_is_append_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  raise exception 'audit_events is append-only'
    using errcode = 'insufficient_privilege';
end;
$fn$;

create trigger audit_events_no_update
  before update or delete on public.audit_events
  for each row execute function app.audit_is_append_only();

create trigger audit_events_no_truncate
  before truncate on public.audit_events
  for each statement execute function app.audit_is_append_only();

-- The only way a row gets in. There is no insert policy on the table, so the application
-- cannot write an audit line by hand with an actor of its choosing: the actor is read from
-- the session here and nowhere else.
create or replace function app.record_audit(
  p_action        app.audit_action,
  p_subject_label text,
  p_target_type   text default null,
  p_target_id     uuid default null,
  p_metadata      jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  event_id uuid;
begin
  if not app.is_staff() then
    raise exception 'only staff actions are audited'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.audit_events (
    action, actor_id, actor_role, subject_label, target_type, target_id, metadata
  )
  values (
    p_action, auth.uid(), app.current_role(), p_subject_label, p_target_type, p_target_id,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into event_id;

  return event_id;
end;
$fn$;

-- The one way a consent timestamp is written.
--
-- The super admin records it, because they are the person who speaks to the family: someone
-- signs in, writes on WhatsApp, and the conversation that ends in a payment is the same
-- conversation the guardian is on (DEC-037). The learner's own sign-up form collects the
-- guardian's name and phone so there is somebody to ask; it does not, and cannot, assert
-- that they agreed.
--
-- Refuses when the contact is not on file, so a consent record always names somebody.
create or replace function app.record_guardian_consent(p_user uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  stamped timestamptz;
begin
  if not app.is_super_admin() then
    raise exception 'only the super admin records a guardian consent'
      using errcode = 'insufficient_privilege';
  end if;

  update public.profiles p
     set guardian_consent_at = now(),
         guardian_consent_recorded_by = auth.uid()
   where p.id = p_user
     and p.guardian_full_name is not null
     and p.guardian_phone is not null
  returning p.guardian_consent_at into stamped;

  if stamped is null then
    raise exception 'a guardian name and phone must be on file before consent is recorded'
      using errcode = 'check_violation';
  end if;

  return stamped;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.centers enable row level security;
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.audit_events enable row level security;

-- Privileges first: RLS narrows what a role may reach, it does not grant it. A table with no
-- grant is unreachable whatever its policies say, and a table with a grant and no policy is
-- unreachable too. Both halves are written out on every table in this project.
grant select on public.centers to anon, authenticated;
grant select on public.profiles to authenticated;

-- Column-level, and this is the load-bearing part.
--
-- RLS decides which *rows* you may write; it cannot decide which *columns*. Without this
-- grant, `profiles_update_own` would let a learner write every field of their own row —
-- including `guardian_consent_at`, which would mean a fifteen-year-old recording their own
-- guardian's consent. Consent is collected from the guardian, not from the learner
-- (`security.md` section 2), so the two consent columns are simply not writable from a
-- session at all; `app.record_guardian_consent` below is the only way they change.
grant update (
  full_name, avatar_url, locale, declared_track_id, date_of_birth,
  guardian_full_name, guardian_phone, guardian_relationship
) on public.profiles to authenticated;
grant select, insert, update, delete on public.user_roles to authenticated;
grant select on public.audit_events to authenticated;
grant execute on function app.record_audit(app.audit_action, text, text, uuid, jsonb)
  to authenticated;
grant execute on function app.record_guardian_consent(uuid) to authenticated;

-- Centres: an address on a public page. Only the active ones are public.
create policy centers_read_active on public.centers
  for select to anon, authenticated
  using (is_active or app.is_super_admin());

create policy centers_write on public.centers
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

-- Profiles: your own, always. The super admin sees everyone, because opening an access means
-- finding the account first (DEC-037). A teacher's view of their own learners is added by the
-- access migration, where the grants that define "their own" are created — policies are
-- additive, so it composes onto this one.
create policy profiles_read_own on public.profiles
  for select to authenticated
  using (id = auth.uid() or app.is_super_admin());

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid() or app.is_super_admin())
  with check (id = auth.uid() or app.is_super_admin());

-- There is no insert policy: a profile is created by app.handle_new_user when Supabase Auth
-- creates the user, and by nothing else. Nor a delete policy — a person who leaves is removed
-- through auth.users, and the cascade takes the profile with it.

create policy user_roles_read on public.user_roles
  for select to authenticated
  using (user_id = auth.uid() or app.is_super_admin());

create policy user_roles_write on public.user_roles
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

create policy audit_read_owner on public.audit_events
  for select to authenticated
  using (app.is_super_admin());

-- No insert, update or delete policy on audit_events, on purpose. app.record_audit is the
-- only writer and the append-only trigger is the backstop.
