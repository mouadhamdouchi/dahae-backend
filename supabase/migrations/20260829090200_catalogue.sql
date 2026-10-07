-- 20260829090200_catalogue.sql
--
-- Filiere -> Matiere -> Cours -> Ressources (CLAUDE.md), and the two workflow rows that hang
-- off it: which subjects a teacher is responsible for, and the requests to delete a chapter.
--
-- Three shape decisions worth stating, because they are the ones a reader will question.
--
-- 1. Tracks and subjects carry no name columns. There are exactly three of each, they are a
--    closed set for the whole MVP (DEC-030, DEC-035), and their names already live in the
--    three message catalogues keyed by slug. A second copy in the database would be a second
--    thing to translate and a second thing to disagree. Lessons are the opposite case — 79
--    chapters of real syllabus text (DEC-051) — so they carry explicit per-locale columns.
--
-- 2. Chapter titles are public; resources are not. The courses page lists every chapter of
--    every stream to anonymous visitors on purpose (DEC-052). What is sold is the material,
--    so the gate sits on `resources`, not on the chapter row.
--
-- 3. A resource never carries its own address. The key and the provider id live in
--    `resource_media`, a table with RLS on and no policy at all, reachable only through a
--    `security definer` function that checks the grant first. That is the same shape the
--    streams table uses (DEC-066): the address is handed out per request, never selected.

-- ---------------------------------------------------------------------------
-- Tracks and subjects
-- ---------------------------------------------------------------------------

create table public.tracks (
  id          uuid primary key default extensions.gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  level       app.level not null,
  -- Null at 1ere Bac, where the class is common to both filieres (DEC-030).
  filiere     app.filiere,
  position    integer not null check (position > 0),
  published   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint tracks_position_unique unique (position) deferrable initially deferred,
  -- A 2eme Bac stream is one filiere or the other; the common year is neither.
  constraint tracks_filiere_matches_level check (
    (level = '1bac' and filiere is null) or (level = '2bac' and filiere is not null)
  )
);

create index tracks_published_idx on public.tracks (published, position);

create trigger tracks_touch before update on public.tracks
  for each row execute function app.touch();

alter table public.profiles
  add constraint profiles_declared_track_fkey
  foreign key (declared_track_id) references public.tracks (id) on delete set null;

create table public.subjects (
  id          uuid primary key default extensions.gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  position    integer not null check (position > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint subjects_position_unique unique (position) deferrable initially deferred
);

create trigger subjects_touch before update on public.subjects
  for each row execute function app.touch();

-- The real teaching unit: a subject as taught inside one stream. The same three subjects run
-- in all three streams, so this table always holds nine rows, and the content behind each one
-- differs even where the name does not.
create table public.track_subjects (
  id              uuid primary key default extensions.gen_random_uuid(),
  track_id        uuid not null references public.tracks (id) on delete cascade,
  subject_id      uuid not null references public.subjects (id) on delete restrict,
  modality        app.modality not null default 'hybrid',
  -- Optional per-stream override of the message-file description. Null means "use the
  -- catalogue wording", which is the case for all nine today.
  description_fr  text,
  description_ar  text,
  description_en  text,
  published       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint track_subjects_unique unique (track_id, subject_id),
  -- Lets a child row name a track_subject and its track together, so the database can prove
  -- the two agree instead of trusting whoever wrote the insert. Used by `sessions`.
  constraint track_subjects_id_track_key unique (id, track_id)
);

create index track_subjects_track_idx on public.track_subjects (track_id, published);
create index track_subjects_subject_idx on public.track_subjects (subject_id);

create trigger track_subjects_touch before update on public.track_subjects
  for each row execute function app.touch();

-- ---------------------------------------------------------------------------
-- Teaching scope
--
-- An appointment, not a kind of sign-in (DEC-060). The staff screen offers subjects, which
-- maps to one row per stream the subject is taught in; removing the appointment removes the
-- scope in the same action.
-- ---------------------------------------------------------------------------

create table public.teacher_subjects (
  id                uuid primary key default extensions.gen_random_uuid(),
  user_id           uuid not null references public.profiles (id) on delete cascade,
  track_subject_id  uuid not null references public.track_subjects (id) on delete cascade,
  assigned_by       uuid references public.profiles (id) on delete set null,
  assigned_at       timestamptz not null default now(),

  constraint teacher_subjects_unique unique (user_id, track_subject_id)
);

create index teacher_subjects_user_idx on public.teacher_subjects (user_id);
create index teacher_subjects_scope_idx on public.teacher_subjects (track_subject_id);

-- ---------------------------------------------------------------------------
-- Lessons — "Cours" in the interface, `lessons` in the database (domain-model.md)
-- ---------------------------------------------------------------------------

create table public.lessons (
  id                uuid primary key default extensions.gen_random_uuid(),
  track_subject_id  uuid not null references public.track_subjects (id) on delete cascade,
  position          integer not null check (position > 0),
  slug              text not null check (slug ~ '^[a-z0-9-]{2,80}$'),
  title_fr          text not null check (char_length(title_fr) between 1 and 200),
  title_ar          text not null check (char_length(title_ar) between 1 and 200),
  title_en          text not null check (char_length(title_en) between 1 and 200),
  summary_fr        text not null check (char_length(summary_fr) between 1 and 600),
  summary_ar        text not null check (char_length(summary_ar) between 1 and 600),
  summary_en        text not null check (char_length(summary_en) between 1 and 600),
  -- The half of the year this chapter is taught in. Access is sold by semester (DEC-030), so
  -- this is what an entitlement is matched against (DEC-062). It is the semester, not a term:
  -- a chapter belongs to S1 of every year, not to S1 of one year.
  semester          app.semester not null,
  is_free_preview   boolean not null default false,
  published         boolean not null default false,
  available_from    timestamptz,
  available_until   timestamptz,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint lessons_slug_unique unique (track_subject_id, slug),
  -- Deferred because reordering a syllabus swaps two positions inside one transaction, and a
  -- constraint checked per statement would refuse the halfway state.
  constraint lessons_position_unique unique (track_subject_id, position) deferrable initially deferred,
  constraint lessons_window_ordered check (
    available_from is null or available_until is null or available_until > available_from
  )
);

-- Exactly one free chapter per subject: the catalogue promises it (DEC-034), so the database
-- refuses a second one rather than letting a screen decide which is "the" free one.
create unique index lessons_one_free_preview
  on public.lessons (track_subject_id)
  where is_free_preview;

create index lessons_scope_idx on public.lessons (track_subject_id, position);
create index lessons_published_idx on public.lessons (published, track_subject_id);
create index lessons_semester_idx on public.lessons (track_subject_id, semester, position);

create trigger lessons_touch before update on public.lessons
  for each row execute function app.touch_with_actor();

-- ---------------------------------------------------------------------------
-- Resources, and the addresses that are kept away from them
-- ---------------------------------------------------------------------------

create table public.resources (
  id          uuid primary key default extensions.gen_random_uuid(),
  lesson_id   uuid not null references public.lessons (id) on delete cascade,
  kind        app.resource_kind not null,
  position    integer not null check (position > 0),
  label_fr    text check (char_length(label_fr) between 1 and 200),
  label_ar    text check (char_length(label_ar) between 1 and 200),
  label_en    text check (char_length(label_en) between 1 and 200),
  size_bytes  bigint check (size_bytes > 0),
  mime_type   text check (char_length(mime_type) between 3 and 120),
  created_by  uuid references public.profiles (id) on delete set null,
  updated_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint resources_position_unique unique (lesson_id, position) deferrable initially deferred
);

create index resources_lesson_idx on public.resources (lesson_id, position);

create trigger resources_touch before update on public.resources
  for each row execute function app.touch_with_actor();

-- Where a resource actually lives. RLS is on and there is no policy, which denies every
-- request from `anon` and `authenticated` outright; `app.resource_media` below is the only
-- way in, and it checks the grant before it answers. A PDF sits in the private
-- `learning-resources` bucket and is served through a short-lived signed URL; a video sits
-- with Cloudinary and is never in Supabase Storage (architecture.md).
create table public.resource_media (
  resource_id         uuid primary key references public.resources (id) on delete cascade,
  storage_bucket      text check (char_length(storage_bucket) between 1 and 60),
  storage_key         text check (char_length(storage_key) between 1 and 400),
  provider            text check (provider in ('supabase', 'cloudinary')),
  provider_public_id  text check (char_length(provider_public_id) between 1 and 200),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- One address or the other, never neither and never both.
  constraint resource_media_one_address check (
    (storage_key is not null and provider_public_id is null and storage_bucket is not null)
    or (provider_public_id is not null and storage_key is null and provider = 'cloudinary')
  )
);

create trigger resource_media_touch before update on public.resource_media
  for each row execute function app.touch();

-- ---------------------------------------------------------------------------
-- Deletion requests
--
-- A teacher adds, never removes (DEC-057). Asking is a row; deciding is the super admin's.
-- ---------------------------------------------------------------------------

create table public.deletion_requests (
  id                uuid primary key default extensions.gen_random_uuid(),
  -- Null once the chapter is gone. The label below is what keeps the row readable.
  lesson_id         uuid references public.lessons (id) on delete set null,
  track_subject_id  uuid not null references public.track_subjects (id) on delete cascade,
  -- The chapter title as it read when the request was made, so the row survives the deletion
  -- it asked for.
  label             text not null check (char_length(label) between 1 and 200),
  reason            text not null check (char_length(reason) between 3 and 1000),
  status            app.deletion_status not null default 'pending',
  requested_by      uuid not null references public.profiles (id) on delete cascade,
  requested_at      timestamptz not null default now(),
  decided_by        uuid references public.profiles (id) on delete set null,
  decided_at        timestamptz,
  decision_note     text check (char_length(decision_note) between 3 and 1000),

  constraint deletion_decided_together check (
    (status = 'pending' and decided_at is null and decided_by is null)
    or (status <> 'pending' and decided_at is not null)
  ),
  -- A refusal with no note teaches the teacher nothing, which is the only reason the note
  -- field exists.
  constraint deletion_refusal_explains check (status <> 'refused' or decision_note is not null)
);

create index deletion_requests_status_idx on public.deletion_requests (status, requested_at desc);
create index deletion_requests_scope_idx on public.deletion_requests (track_subject_id);

-- ---------------------------------------------------------------------------
-- Catalogue helpers
-- ---------------------------------------------------------------------------

-- The super admin can do everything a teacher can do, so it answers true for them without an
-- assignment row (roles-permissions.md).
create or replace function app.teaches(p_track_subject uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select app.is_super_admin() or exists (
    select 1
    from public.teacher_subjects ts
    where ts.user_id = auth.uid()
      and ts.track_subject_id = p_track_subject
  );
$fn$;

create or replace function app.teaches_lesson(p_lesson uuid)
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
      and app.teaches(l.track_subject_id)
  );
$fn$;

-- Published, in a published subject, in a published stream. A chapter is publicly visible
-- only when all three agree (domain-model.md).
create or replace function app.lesson_is_public(p_lesson uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.lessons l
    join public.track_subjects ts on ts.id = l.track_subject_id
    join public.tracks t on t.id = ts.track_id
    where l.id = p_lesson
      and l.published
      and ts.published
      and t.published
  );
$fn$;

-- The narrow exception of DEC-034, written as its own question rather than as a loosened
-- version of the entitlement one.
create or replace function app.lesson_is_free_preview(p_lesson uuid)
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
      and l.is_free_preview
  ) and app.lesson_is_public(p_lesson);
$fn$;

-- Publishing a subject with no free chapter would break a promise the catalogue makes on
-- every card, so the database refuses it (domain-model.md, critical constraints).
create or replace function app.require_free_preview()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.published and not coalesce(old.published, false) then
    if not exists (
      select 1
      from public.lessons l
      where l.track_subject_id = new.id
        and l.is_free_preview
        and l.published
    ) then
      raise exception 'a subject cannot be published without a free first chapter'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$fn$;

create trigger track_subjects_require_free_preview
  before insert or update of published on public.track_subjects
  for each row execute function app.require_free_preview();

-- ---------------------------------------------------------------------------
-- What a chapter comes with, for people who have not bought it
--
-- The courses page shows "PDF, video, serie, correction" badges to anonymous visitors
-- (DEC-052), and `resources` is not readable by anonymous visitors. This view is the whole
-- answer: kinds and nothing else, published chapters and nothing else. It runs with its
-- owner's rights on purpose — that is what lets it look past the RLS on `resources` — and it
-- is the only object in this schema that does.
-- ---------------------------------------------------------------------------

create view public.lesson_resource_kinds
with (security_barrier = true) as
  select distinct r.lesson_id, r.kind
  from public.resources r
  where app.lesson_is_public(r.lesson_id);

comment on view public.lesson_resource_kinds is
  'Which kinds of material come with a published chapter. Carries no address and no key: it '
  'exists so the public catalogue can show its badges without opening resources to anon.';

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.tracks enable row level security;
alter table public.subjects enable row level security;
alter table public.track_subjects enable row level security;
alter table public.teacher_subjects enable row level security;
alter table public.lessons enable row level security;
alter table public.resources enable row level security;
alter table public.resource_media enable row level security;
alter table public.deletion_requests enable row level security;

grant select on public.tracks to anon, authenticated;
grant insert, update, delete on public.tracks to authenticated;
grant select on public.subjects to anon, authenticated;
grant insert, update, delete on public.subjects to authenticated;
grant select on public.track_subjects to anon, authenticated;
grant insert, update, delete on public.track_subjects to authenticated;
grant select, insert, update, delete on public.teacher_subjects to authenticated;
grant select on public.lessons to anon, authenticated;
grant insert, update, delete on public.lessons to authenticated;
grant select, insert, update, delete on public.resources to authenticated;
grant select on public.lesson_resource_kinds to anon, authenticated;
grant select, insert, update, delete on public.deletion_requests to authenticated;

-- `resource_media` gets no grant at all. Nothing selects from it; the function below is the
-- only door, and it is added by the access migration where entitlement is defined.

-- Streams and subjects: published to everyone, everything to staff.
create policy tracks_read on public.tracks
  for select to anon, authenticated
  using (published or app.is_staff());

create policy tracks_write on public.tracks
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

create policy subjects_read on public.subjects
  for select to anon, authenticated
  using (true);

create policy subjects_write on public.subjects
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

create policy track_subjects_read on public.track_subjects
  for select to anon, authenticated
  using (
    (published and exists (
      select 1 from public.tracks t where t.id = track_id and t.published
    ))
    or app.teaches(id)
  );

-- Publishing is the super admin's alone (DEC-057), and so is creating a subject: the nine
-- rows are the catalogue itself, not content somebody adds during a term.
create policy track_subjects_write on public.track_subjects
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

create policy teacher_subjects_read on public.teacher_subjects
  for select to authenticated
  using (user_id = auth.uid() or app.is_super_admin());

create policy teacher_subjects_write on public.teacher_subjects
  for all to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin());

-- A chapter title is public. What the chapter comes with is not.
create policy lessons_read on public.lessons
  for select to anon, authenticated
  using (app.lesson_is_public(id) or app.teaches(track_subject_id));

-- A teacher creates a chapter as a draft; only the super admin may hand one out published,
-- and only the super admin may flip an existing one to published (DEC-057). The WITH CHECK is
-- what enforces that, not the screen.
create policy lessons_insert on public.lessons
  for insert to authenticated
  with check (
    app.teaches(track_subject_id)
    and (app.is_super_admin() or published = false)
  );

create policy lessons_update on public.lessons
  for update to authenticated
  using (app.teaches(track_subject_id))
  with check (
    app.teaches(track_subject_id)
    and (app.is_super_admin() or published = false)
  );

create policy lessons_delete on public.lessons
  for delete to authenticated
  using (app.is_super_admin());

-- Resources: staff within their scope, and the free first chapter to anybody signed in
-- (DEC-034). Entitled learners are added by the access migration as a second read policy —
-- policies are additive, and writing the free-preview exception as its own narrow rule rather
-- than as a loosened entitlement rule is a requirement, not a preference
-- (roles-permissions.md).
create policy resources_read_scope on public.resources
  for select to authenticated
  using (app.teaches_lesson(lesson_id));

create policy resources_read_free_preview on public.resources
  for select to authenticated
  using (app.is_signed_in() and app.lesson_is_free_preview(lesson_id));

create policy resources_insert on public.resources
  for insert to authenticated
  with check (app.teaches_lesson(lesson_id));

create policy resources_update on public.resources
  for update to authenticated
  using (app.teaches_lesson(lesson_id))
  with check (app.teaches_lesson(lesson_id));

-- A teacher adds, never removes (DEC-057): taking material away from a chapter somebody paid
-- for is the same act as deleting the chapter, and that is the super admin's.
create policy resources_delete on public.resources
  for delete to authenticated
  using (app.is_super_admin());

-- No policy on `resource_media`, deliberately. See the table comment.

create policy deletion_requests_read on public.deletion_requests
  for select to authenticated
  using (app.teaches(track_subject_id));

create policy deletion_requests_insert on public.deletion_requests
  for insert to authenticated
  with check (
    app.teaches(track_subject_id)
    and requested_by = auth.uid()
    and status = 'pending'
  );

create policy deletion_requests_decide on public.deletion_requests
  for update to authenticated
  using (app.is_super_admin())
  with check (app.is_super_admin() and decided_by = auth.uid());

create policy deletion_requests_delete on public.deletion_requests
  for delete to authenticated
  using (app.is_super_admin());
