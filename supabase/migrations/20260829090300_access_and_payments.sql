-- 20260829090300_access_and_payments.sql
--
-- What a learner may actually open, and the offline payment behind it.
--
-- There is no enrollment, no application, no invoice and no payment plan (DEC-037). Somebody
-- signs in with Google, reads the free first chapter, writes on WhatsApp, pays at the academy,
-- and the super admin opens their access by hand. The grant *is* the relationship: it says who
-- may open which subjects, for which semester, until when, and who decided it.
--
-- The rule this table shape exists for (DEC-062): a learner holds **one grant per semester**,
-- not one row that keeps being edited. Somebody who took S1 and did not come back still opens
-- the S1 chapters and the S1 recordings, because the row that says so is still there and has
-- not been overwritten by selling them S2. Entitlement is the pair (subject, semester), and it
-- is read in two flavours that must not be confused:
--
--   app.entitled(...)     -- may read: every grant ever held, ended ones included
--   app.entitled_now(...) -- may join a live happening now: only a grant still running
--
-- Money: integers in minor units with an ISO currency, never floating point (security.md
-- section 10). Nothing here charges anything — the payment is recorded, not taken.

-- ---------------------------------------------------------------------------
-- The school calendar
-- ---------------------------------------------------------------------------

create table public.academic_terms (
  id           uuid primary key default extensions.gen_random_uuid(),
  -- '2026-2027'. The Moroccan school year runs September to June.
  school_year  text not null check (school_year ~ '^[0-9]{4}-[0-9]{4}$'),
  semester     app.semester not null,
  starts_on    date not null,
  ends_on      date not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint academic_terms_unique unique (school_year, semester),
  constraint academic_terms_ordered check (ends_on > starts_on)
);

create index academic_terms_span_idx on public.academic_terms (starts_on, ends_on);

create trigger academic_terms_touch before update on public.academic_terms
  for each row execute function app.touch();

-- ---------------------------------------------------------------------------
-- The offer
--
-- One, two or three subjects for one semester, at a price. Published on the subject pages and
-- on the home page (DEC-036, DEC-049) with the WhatsApp conversation as the only action.
-- `is_demo_price` is what makes the demonstration warning on those pages truthful; it comes
-- off when the real amounts arrive (open question F5).
-- ---------------------------------------------------------------------------

create table public.packs (
  id             uuid primary key default extensions.gen_random_uuid(),
  slug           text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  subject_count  smallint not null check (subject_count between 1 and 3),
  price_minor    integer not null check (price_minor > 0),
  currency       char(3) not null default 'MAD' check (currency ~ '^[A-Z]{3}$'),
  billing        text not null default 'per_semester' check (billing = 'per_semester'),
  is_demo_price  boolean not null default true,
  published      boolean not null default false,
  position       integer not null check (position > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint packs_subject_count_unique unique (subject_count)
);

create trigger packs_touch before update on public.packs
  for each row execute function app.touch();

-- ---------------------------------------------------------------------------
-- Access grants
-- ---------------------------------------------------------------------------

create table public.access_grants (
  id            uuid primary key default extensions.gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  track_id      uuid not null references public.tracks (id) on delete restrict,
  term_id       uuid not null references public.academic_terms (id) on delete restrict,
  pack_id       uuid references public.packs (id) on delete set null,
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz not null,
  granted_by    uuid not null references public.profiles (id) on delete restrict,
  granted_at    timestamptz not null default now(),
  -- Closing an access before its end date (DEC-060). Not a refund and not a cancellation:
  -- nothing was charged on the site, and the person keeps their account and the free first
  -- chapter of every subject.
  revoked_at    timestamptz,
  revoked_by    uuid references public.profiles (id) on delete set null,
  revoke_reason text check (char_length(revoke_reason) between 3 and 500),
  note          text check (char_length(note) between 1 and 500),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- One grant per semester (DEC-062). Selling the second semester adds a row; it does not
  -- edit the first, which is what keeps a finished semester open.
  constraint access_grants_one_per_term unique (user_id, term_id),
  constraint access_grants_ordered check (ends_at > starts_at),
  constraint access_grants_revoked_together check (
    (revoked_at is null and revoked_by is null)
    or (revoked_at is not null and revoked_by is not null)
  ),
  -- Lets the subject rows below prove they belong to the same stream as the grant.
  constraint access_grants_id_track_key unique (id, track_id)
);

create index access_grants_user_idx on public.access_grants (user_id, ends_at desc);
create index access_grants_term_idx on public.access_grants (term_id);
create index access_grants_running_idx on public.access_grants (ends_at) where revoked_at is null;

create trigger access_grants_touch before update on public.access_grants
  for each row execute function app.touch();

-- The subjects the grant covers. The composite foreign keys are doing real work: they make it
-- impossible to attach a 2eme Bac subject to a 1ere Bac grant, without a trigger and without
-- trusting whoever wrote the insert (domain-model.md: "its subjects must belong to the same
-- track").
create table public.access_grant_subjects (
  grant_id          uuid not null references public.access_grants (id) on delete cascade,
  track_subject_id  uuid not null references public.track_subjects (id) on delete restrict,
  track_id          uuid not null,

  primary key (grant_id, track_subject_id),
  constraint access_grant_subjects_same_track_as_grant
    foreign key (grant_id, track_id) references public.access_grants (id, track_id),
  constraint access_grant_subjects_subject_in_track
    foreign key (track_subject_id, track_id) references public.track_subjects (id, track_id)
);

create index access_grant_subjects_scope_idx on public.access_grant_subjects (track_subject_id);

-- A minor's profile must carry a guardian contact and a consent timestamp before any grant is
-- created (domain-model.md, security.md section 2). Not knowing the age counts as a minor —
-- see app.requires_guardian.
create or replace function app.require_guardian_consent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if app.requires_guardian(new.user_id) then
    if not exists (
      select 1
      from public.profiles p
      where p.id = new.user_id
        and p.guardian_consent_at is not null
        and p.guardian_full_name is not null
        and p.guardian_phone is not null
    ) then
      raise exception 'a guardian contact and consent are required before an access is opened'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$fn$;

create trigger access_grants_require_guardian
  before insert on public.access_grants
  for each row execute function app.require_guardian_consent();

-- ---------------------------------------------------------------------------
-- Payments
--
-- One per grant, recorded after the fact, in cash or by transfer (DEC-033, DEC-037).
-- Cancellation is a state, not a delete: the record of what was recorded stays.
-- ---------------------------------------------------------------------------

create table public.payments (
  id            uuid primary key default extensions.gen_random_uuid(),
  grant_id      uuid not null unique references public.access_grants (id) on delete cascade,
  amount_minor  integer not null check (amount_minor > 0),
  currency      char(3) not null default 'MAD' check (currency ~ '^[A-Z]{3}$'),
  method        app.payment_method not null,
  paid_at       timestamptz not null default now(),
  recorded_by   uuid not null references public.profiles (id) on delete restrict,
  recorded_at   timestamptz not null default now(),
  status        text not null default 'recorded' check (status in ('recorded', 'cancelled')),
  cancelled_at  timestamptz,
  cancel_reason text check (char_length(cancel_reason) between 3 and 500),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint payments_cancelled_together check (
    (status = 'recorded' and cancelled_at is null and cancel_reason is null)
    or (status = 'cancelled' and cancelled_at is not null and cancel_reason is not null)
  )
);

create index payments_paid_idx on public.payments (paid_at desc);

create trigger payments_touch before update on public.payments
  for each row execute function app.touch();

-- ---------------------------------------------------------------------------
-- Settings
--
-- One row. The WhatsApp number, the address and the completion threshold are read by public
-- pages, so no contact detail is ever hardcoded in a component (frontend/lib/settings.ts).
-- ---------------------------------------------------------------------------

create table public.settings (
  id                    boolean primary key default true check (id),
  whatsapp_number       text not null check (whatsapp_number ~ '^[0-9]{8,15}$'),
  email                 text not null check (char_length(email) between 3 and 254),
  location              text not null check (char_length(location) between 1 and 200),
  -- The "% de completion" a chapter needs before it counts as done. Read from here rather
  -- than from a constant in the code (domain-model.md).
  completion_threshold  smallint not null default 80 check (completion_threshold between 1 and 100),
  updated_by            uuid references public.profiles (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create trigger settings_touch before update on public.settings
  for each row execute function app.touch_with_actor();

-- ---------------------------------------------------------------------------
-- Entitlement
-- ---------------------------------------------------------------------------

-- May read. Every grant the learner has ever held counts, ended ones included: the family
-- paid for that semester's teaching and keeps it (DEC-062). A revoked grant counts for
-- nothing — closing an access closes that semester (DEC-060).
create or replace function app.entitled(p_track_subject uuid, p_semester app.semester)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.access_grants g
    join public.access_grant_subjects gs on gs.grant_id = g.id
    join public.academic_terms t on t.id = g.term_id
    where g.user_id = auth.uid()
      and g.revoked_at is null
      and gs.track_subject_id = p_track_subject
      and t.semester = p_semester
  );
$fn$;

-- May join what is happening now. The same grant, still running (DEC-058, DEC-062).
create or replace function app.entitled_now(p_track_subject uuid, p_semester app.semester)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.access_grants g
    join public.access_grant_subjects gs on gs.grant_id = g.id
    join public.academic_terms t on t.id = g.term_id
    where g.user_id = auth.uid()
      and g.revoked_at is null
      and g.starts_at <= now()
      and g.ends_at > now()
      and gs.track_subject_id = p_track_subject
      and t.semester = p_semester
  );
$fn$;

create or replace function app.entitled_to_lesson(p_lesson uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.lessons l
    where l.id = p_lesson
      and app.entitled(l.track_subject_id, l.semester)
  );
$fn$;

-- The learners one teacher may see: those holding a grant on a subject they are assigned
-- ("Assigned students only", roles-permissions.md). A `security definer` function rather than
-- a subquery inside the policy, so reading `profiles` never sends Postgres back through the
-- policies on `access_grants`.
create or replace function app.teaches_learner(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select app.current_role() = 'teacher' and exists (
    select 1
    from public.access_grants g
    join public.access_grant_subjects gs on gs.grant_id = g.id
    join public.teacher_subjects ts on ts.track_subject_id = gs.track_subject_id
    where g.user_id = p_user
      and ts.user_id = auth.uid()
  );
$fn$;

-- Where a resource lives, answered per request after the grant is checked — the same shape a
-- playback address gets (DEC-066). `resource_media` has no policy, so this function is the
-- only way to an address, and there is no query a client can write that returns one.
create or replace function app.resource_media(p_resource uuid)
returns table (
  storage_bucket     text,
  storage_key        text,
  provider           text,
  provider_public_id text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  lesson uuid;
begin
  select r.lesson_id into lesson from public.resources r where r.id = p_resource;

  if lesson is null then
    return;
  end if;

  if not (
    app.teaches_lesson(lesson)
    or app.entitled_to_lesson(lesson)
    or (app.is_signed_in() and app.lesson_is_free_preview(lesson))
  ) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  return query
    select m.storage_bucket, m.storage_key, m.provider, m.provider_public_id
    from public.resource_media m
    where m.resource_id = p_resource;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.academic_terms enable row level security;
alter table public.packs enable row level security;
alter table public.access_grants enable row level security;
alter table public.access_grant_subjects enable row level security;
alter table public.payments enable row level security;
alter table public.settings enable row level security;

grant select on public.academic_terms to anon, authenticated;
grant insert, update, delete on public.academic_terms to authenticated;
grant select on public.packs to anon, authenticated;
grant insert, update, delete on public.packs to authenticated;
grant select, insert, update, delete on public.access_grants to authenticated;
grant select, insert, update, delete on public.access_grant_subjects to authenticated;
grant select, insert, update, delete on public.payments to authenticated;
grant select on public.settings to anon, authenticated;
grant update on public.settings to authenticated;

grant execute on function app.resource_media(uuid) to authenticated;

-- A calendar. Nothing about a person is in it.
create policy academic_terms_read on public.academic_terms
  for select to anon, authenticated
  using (true);

create policy academic_terms_write on public.academic_terms
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

create policy packs_read on public.packs
  for select to anon, authenticated
  using (published or app.is_super_admin());

create policy packs_write on public.packs
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

-- Your own grants, always. The super admin sees every one, because opening and closing them is
-- their job alone. A teacher sees the grants of the learners on their own subjects, and
-- nothing about the money behind them.
create policy access_grants_read on public.access_grants
  for select to authenticated
  using (
    user_id = auth.uid()
    or app.is_super_admin()
    or app.teaches_learner(user_id)
  );

-- Opening an access records who decided it, and the database reads that from the session
-- rather than from the request body (security.md section 4).
create policy access_grants_open on public.access_grants
  for insert to authenticated
  with check (app.is_super_admin() and granted_by = auth.uid());

-- Closing one is a separate policy on purpose. Folding it into the insert rule with FOR ALL
-- would carry `granted_by = auth.uid()` onto the update too, and a second super admin would
-- then be unable to close an access the first one opened. There is one owner today; there
-- will not always be.
create policy access_grants_amend on public.access_grants
  for update to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

create policy access_grants_delete on public.access_grants
  for delete to authenticated
  using (app.is_super_admin());

create policy access_grant_subjects_read on public.access_grant_subjects
  for select to authenticated
  using (
    exists (
      select 1 from public.access_grants g
      where g.id = grant_id
        and (g.user_id = auth.uid() or app.is_super_admin() or app.teaches_learner(g.user_id))
    )
  );

create policy access_grant_subjects_write on public.access_grant_subjects
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

-- Teachers never see money (roles-permissions.md). This policy has no teacher branch on
-- purpose: the pedagogical and the financial sides are separated by construction, not by which
-- screen renders what.
create policy payments_read on public.payments
  for select to authenticated
  using (
    app.is_super_admin()
    or exists (
      select 1 from public.access_grants g
      where g.id = grant_id and g.user_id = auth.uid()
    )
  );

create policy payments_record on public.payments
  for insert to authenticated
  with check (app.is_super_admin() and recorded_by = auth.uid());

-- Split from the insert for the same reason as the grants above: cancelling a payment must
-- not require being the person who recorded it.
create policy payments_amend on public.payments
  for update to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

create policy payments_delete on public.payments
  for delete to authenticated
  using (app.is_super_admin());

create policy settings_read on public.settings
  for select to anon, authenticated
  using (true);

create policy settings_update on public.settings
  for update to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

-- ---------------------------------------------------------------------------
-- The two policies that could only be written once entitlement existed
-- ---------------------------------------------------------------------------

-- Added to `profiles`, alongside the own-row and super-admin policies from the identity
-- migration. Policies are additive, so this widens a teacher's view to their own learners
-- without touching what was already there.
create policy profiles_read_learners on public.profiles
  for select to authenticated
  using (app.teaches_learner(id));

-- What the learner paid for. Separate from the free-preview policy on purpose
-- (roles-permissions.md): the exception stays a narrow rule of its own rather than becoming a
-- loosened version of this one.
create policy resources_read_entitled on public.resources
  for select to authenticated
  using (app.entitled_to_lesson(lesson_id));
