-- 20260829090400_schedule_lives_recordings.sql
--
-- The weekly timetable, the live that runs on one of its slots, and the archive the live
-- leaves behind.
--
-- Two rules from the decision log are structural here rather than procedural.
--
-- A teacher builds the timetable and the super admin publishes it (DEC-064). An unpublished
-- seance reaches no learner and no live can be opened on it — that second half is a trigger,
-- because a policy can refuse a row but cannot refuse a row on account of another table's
-- state as clearly.
--
-- A finished live files itself (DEC-063). Closing it writes the recording in the same action,
-- under the same provider id, because a separate "save the recording" step is a step somebody
-- forgets and a seance that left no trace is one a learner who paid for that semester cannot
-- catch up on.
--
-- And the thing this file is most careful about: **an address is never a column somebody can
-- select** (DEC-066). The ingest address, the stream key and the playback address live in
-- `streams`, which has RLS on and no policy and no grant. Three `security definer` functions
-- are the only doors, and each one checks something different before it answers.

-- ---------------------------------------------------------------------------
-- The weekly timetable
-- ---------------------------------------------------------------------------

create table public.sessions (
  id                uuid primary key default extensions.gen_random_uuid(),
  track_subject_id  uuid not null references public.track_subjects (id) on delete cascade,
  -- Carried alongside the subject so the exclusion constraint below can key on the stream.
  -- The composite foreign key is what stops the two disagreeing.
  track_id          uuid not null,
  center_id         uuid references public.centers (id) on delete restrict,
  teacher_id        uuid references public.profiles (id) on delete set null,
  weekday           smallint not null check (weekday between 0 and 6),
  start_time        time not null,
  end_time          time not null,
  modality          app.modality not null default 'hybrid',
  published         boolean not null default false,
  proposed_by       uuid not null references public.profiles (id) on delete restrict,
  proposed_at       timestamptz not null default now(),
  published_by      uuid references public.profiles (id) on delete set null,
  published_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- Minutes from midnight, so the overlap test below can use an integer range and this file
  -- does not have to define a range type over `time`.
  slot int4range generated always as (
    int4range(
      (extract(hour from start_time) * 60 + extract(minute from start_time))::integer,
      (extract(hour from end_time) * 60 + extract(minute from end_time))::integer
    )
  ) stored,

  constraint sessions_time_ordered check (end_time > start_time),
  constraint sessions_published_together check (
    (published and published_at is not null) or (not published and published_at is null)
  ),
  constraint sessions_subject_in_track
    foreign key (track_subject_id, track_id) references public.track_subjects (id, track_id)
);

-- A class cannot be in two places at once (DEC-064). Keyed on the stream rather than the
-- subject, and on every row rather than the published ones, because turning a proposal down
-- deletes it — there is no refused state to exclude.
alter table public.sessions
  add constraint sessions_no_overlap
  exclude using gist (track_id with =, weekday with =, slot with &&);

create index sessions_scope_idx on public.sessions (track_subject_id, weekday, start_time);
create index sessions_published_idx on public.sessions (published, weekday, start_time);

create trigger sessions_touch before update on public.sessions
  for each row execute function app.touch();

create or replace function app.session_is_published(p_session uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1 from public.sessions s where s.id = p_session and s.published
  );
$fn$;

-- ---------------------------------------------------------------------------
-- Streams
--
-- The provider's room. No grant, no policy: `anon` and `authenticated` cannot reach this
-- table at all, whatever query they write. Everything anybody is allowed to know about a
-- stream comes back from one of the three functions further down, one request at a time.
-- ---------------------------------------------------------------------------

create table public.streams (
  id            uuid primary key default extensions.gen_random_uuid(),
  provider      text not null check (provider in ('demo', 'cloudinary')),
  public_id     text not null unique check (char_length(public_id) between 1 and 200),
  -- Where the teacher's encoder pushes. A credential in its own right.
  ingest_url    text check (char_length(ingest_url) between 1 and 400),
  -- The credential DEC-066 is written about: it authorises broadcasting as the academy.
  stream_key    text check (char_length(stream_key) between 1 and 400),
  -- Absent for the first minutes after a live, while the provider finishes the archive. That
  -- is a state the screen names, not a broken player it shows (DEC-063).
  playback_url  text check (char_length(playback_url) between 1 and 600),
  opened_by     uuid references public.profiles (id) on delete set null,
  opened_at     timestamptz not null default now(),
  closed_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger streams_touch before update on public.streams
  for each row execute function app.touch();

comment on table public.streams is
  'Ingest address, stream key and playback address. RLS is on and there is no policy and no '
  'grant: reachable only through app.live_ingest, app.live_playback and '
  'app.recording_playback, each of which checks the caller first (DEC-066).';

-- ---------------------------------------------------------------------------
-- Lives
-- ---------------------------------------------------------------------------

create table public.live_sessions (
  id                uuid primary key default extensions.gen_random_uuid(),
  session_id        uuid not null references public.sessions (id) on delete cascade,
  track_subject_id  uuid not null references public.track_subjects (id) on delete cascade,
  term_id           uuid not null references public.academic_terms (id) on delete restrict,
  -- Denormalised from the term so entitlement can be answered without a join in a policy.
  -- Kept honest by the trigger below.
  semester          app.semester not null,
  stream_id         uuid not null unique references public.streams (id) on delete restrict,
  opened_by         uuid not null references public.profiles (id) on delete restrict,
  opened_at         timestamptz not null default now(),
  closed_at         timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint live_sessions_closed_after_open check (closed_at is null or closed_at > opened_at)
);

-- One live at a time on a seance. A second "open" while the first is still running is a
-- mistake, not a second class.
create unique index live_sessions_one_open
  on public.live_sessions (session_id)
  where closed_at is null;

create index live_sessions_scope_idx on public.live_sessions (track_subject_id, opened_at desc);

create trigger live_sessions_touch before update on public.live_sessions
  for each row execute function app.touch();

-- A live can only be opened on a published seance (DEC-064), and the semester it is filed
-- under has to be the semester of the term it names.
create or replace function app.check_live_opens_on_published_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if not app.session_is_published(new.session_id) then
    raise exception 'a live can only be opened on a published seance'
      using errcode = 'check_violation';
  end if;

  if new.semester <> (select t.semester from public.academic_terms t where t.id = new.term_id) then
    raise exception 'the live semester must match its academic term'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$fn$;

create trigger live_sessions_check_session
  before insert on public.live_sessions
  for each row execute function app.check_live_opens_on_published_session();

-- ---------------------------------------------------------------------------
-- Recordings
-- ---------------------------------------------------------------------------

create table public.recordings (
  id                uuid primary key default extensions.gen_random_uuid(),
  live_id           uuid unique references public.live_sessions (id) on delete set null,
  session_id        uuid references public.sessions (id) on delete set null,
  track_subject_id  uuid not null references public.track_subjects (id) on delete cascade,
  semester          app.semester not null,
  stream_id         uuid not null references public.streams (id) on delete restrict,
  -- Optional. A recording nobody named is listed by the day it was taught, which is what
  -- somebody looking for last Wednesday actually searches for (DEC-063).
  title             text check (char_length(title) between 1 and 200),
  started_at        timestamptz not null,
  ended_at          timestamptz not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.profiles (id) on delete set null,

  constraint recordings_ordered check (ended_at > started_at)
);

create index recordings_scope_idx on public.recordings (track_subject_id, semester, started_at desc);
create index recordings_started_idx on public.recordings (started_at desc);

create trigger recordings_touch before update on public.recordings
  for each row execute function app.touch_with_actor();

-- ---------------------------------------------------------------------------
-- The three doors into `streams`
-- ---------------------------------------------------------------------------

-- The ingest address and the stream key, to the person who opened the live and to nobody
-- else — not the other teacher on the subject, and not the super admin (DEC-066). A
-- credential that reaches a second screen is a credential in a second place.
create or replace function app.live_ingest(p_live uuid)
returns table (ingest_url text, stream_key text)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  return query
    select s.ingest_url, s.stream_key
    from public.live_sessions l
    join public.streams s on s.id = l.stream_id
    where l.id = p_live
      and l.opened_by = auth.uid()
      and l.closed_at is null;
end;
$fn$;

-- Watching a live happening now needs a grant that is still running (DEC-058, DEC-062). Staff
-- within their scope are answered on scope, which is what lets a teacher check their own
-- broadcast.
create or replace function app.live_playback(p_live uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  row_live public.live_sessions%rowtype;
begin
  select * into row_live from public.live_sessions l where l.id = p_live;
  if not found or row_live.closed_at is not null then
    return null;
  end if;

  if not (
    app.teaches(row_live.track_subject_id)
    or (
      app.session_is_published(row_live.session_id)
      and app.entitled_now(row_live.track_subject_id, row_live.semester)
    )
  ) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  return (select s.playback_url from public.streams s where s.id = row_live.stream_id);
end;
$fn$;

-- The archive is the other half of DEC-062: a semester that was paid for stays watchable
-- after it ends, so this one asks `app.entitled`, not `app.entitled_now`.
create or replace function app.recording_playback(p_recording uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  row_rec public.recordings%rowtype;
begin
  select * into row_rec from public.recordings r where r.id = p_recording;
  if not found then
    return null;
  end if;

  if not (
    app.teaches(row_rec.track_subject_id)
    or app.entitled(row_rec.track_subject_id, row_rec.semester)
  ) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  return (select s.playback_url from public.streams s where s.id = row_rec.stream_id);
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.sessions enable row level security;
alter table public.streams enable row level security;
alter table public.live_sessions enable row level security;
alter table public.recordings enable row level security;

grant select on public.sessions to anon, authenticated;
grant insert, update, delete on public.sessions to authenticated;
grant select, insert, update on public.live_sessions to authenticated;
grant select, insert, update, delete on public.recordings to authenticated;

grant execute on function app.live_ingest(uuid) to authenticated;
grant execute on function app.live_playback(uuid) to authenticated;
grant execute on function app.recording_playback(uuid) to authenticated;

-- `streams` gets no grant. See the table comment.

-- The published timetable is a public page. A proposal is visible to the staff who can act on
-- it and to nobody else — that is what "reaches no learner" means (DEC-064).
create policy sessions_read on public.sessions
  for select to anon, authenticated
  using (published or app.teaches(track_subject_id));

create policy sessions_propose on public.sessions
  for insert to authenticated
  with check (
    app.teaches(track_subject_id)
    and proposed_by = auth.uid()
    -- The super admin's own addition is published as it is made, because asking themselves
    -- for permission is not a workflow. A teacher's is not.
    and (app.is_super_admin() or published = false)
  );

create policy sessions_update on public.sessions
  for update to authenticated
  using (app.teaches(track_subject_id))
  with check (
    app.teaches(track_subject_id)
    and (app.is_super_admin() or published = false)
  );

-- Turning a proposal down removes it, and that decision is the super admin's (DEC-064).
create policy sessions_delete on public.sessions
  for delete to authenticated
  using (app.is_super_admin());

create policy live_sessions_read on public.live_sessions
  for select to authenticated
  using (
    app.teaches(track_subject_id)
    or (app.session_is_published(session_id) and app.entitled_now(track_subject_id, semester))
  );

create policy live_sessions_open on public.live_sessions
  for insert to authenticated
  with check (app.teaches(track_subject_id) and opened_by = auth.uid());

create policy live_sessions_close on public.live_sessions
  for update to authenticated
  using (app.teaches(track_subject_id))
  with check (app.teaches(track_subject_id));

-- No delete policy: a live that happened is a fact, and the archive it leaves is the point.

create policy recordings_read on public.recordings
  for select to authenticated
  using (app.teaches(track_subject_id) or app.entitled(track_subject_id, semester));

create policy recordings_insert on public.recordings
  for insert to authenticated
  with check (app.teaches(track_subject_id));

create policy recordings_rename on public.recordings
  for update to authenticated
  using (app.teaches(track_subject_id))
  with check (app.teaches(track_subject_id));

-- Only the super admin deletes, because a teacher who could delete their own recordings could
-- quietly remove a seance a learner paid for (DEC-063).
create policy recordings_delete on public.recordings
  for delete to authenticated
  using (app.is_super_admin());
