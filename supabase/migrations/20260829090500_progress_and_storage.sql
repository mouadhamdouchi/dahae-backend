-- 20260829090500_progress_and_storage.sql
--
-- What a learner has got through, and the one private bucket the material sits in.
--
-- Storage is the place where an RLS mistake is worst: a bucket left public hands out the
-- material to anybody with the address, and no policy anywhere else in the database can undo
-- that. So the bucket is private, the object path carries the chapter it belongs to, and the
-- policies below ask the *same* three questions the `resources` policies ask — teaches it, has
-- paid for it, or it is the free first chapter (DEC-034).
--
-- Video is not here. Lives and their recordings live with Cloudinary and Postgres keeps only
-- the provider id (architecture.md, DEC-065).

-- ---------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------

create table public.lesson_progress (
  user_id          uuid not null references public.profiles (id) on delete cascade,
  lesson_id        uuid not null references public.lessons (id) on delete cascade,
  percent          smallint not null default 0 check (percent between 0 and 100),
  -- Set by the application when `percent` crosses the threshold in `settings`, which is a
  -- setting rather than a constant on purpose (domain-model.md). Kept as a timestamp rather
  -- than a boolean so "when did this happen" is answerable.
  completed_at     timestamptz,
  first_opened_at  timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  primary key (user_id, lesson_id)
);

create index lesson_progress_lesson_idx on public.lesson_progress (lesson_id);
create index lesson_progress_done_idx on public.lesson_progress (user_id) where completed_at is not null;

create trigger lesson_progress_touch before update on public.lesson_progress
  for each row execute function app.touch();

-- The completion threshold, read from the single settings row. Here so a query never has to
-- carry a hardcoded 80.
create or replace function app.completion_threshold()
returns smallint
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce((select s.completion_threshold from public.settings s limit 1), 80::smallint);
$fn$;

alter table public.lesson_progress enable row level security;

grant select, insert, update on public.lesson_progress to authenticated;
grant execute on function app.completion_threshold() to anon, authenticated;

-- Own progress, always. Staff see the progress of the chapters they teach — that is what the
-- "View reports: assigned classes" row of the permission matrix is.
create policy lesson_progress_read on public.lesson_progress
  for select to authenticated
  using (user_id = auth.uid() or app.teaches_lesson(lesson_id));

-- A learner may only record progress against a chapter they may actually open, and only under
-- their own name. Never trust a client-supplied user_id (security.md section 4) — the WITH
-- CHECK is what makes that true rather than a habit.
create policy lesson_progress_write_own on public.lesson_progress
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and (app.entitled_to_lesson(lesson_id) or app.lesson_is_free_preview(lesson_id))
  );

create policy lesson_progress_update_own on public.lesson_progress
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and (app.entitled_to_lesson(lesson_id) or app.lesson_is_free_preview(lesson_id))
  );

-- No delete policy: a learner cannot un-read a chapter, and nobody else has a reason to.

-- ---------------------------------------------------------------------------
-- The private bucket
--
-- Path convention, and the policies below depend on it:
--
--     learning-resources/<track_subject_id>/<lesson_id>/<random>.<ext>
--
-- The chapter is in the path because a storage policy has nothing else to go on — there is no
-- foreign key from an object to a row. Filenames are randomised by the upload code and never
-- taken from the client (security.md section 8).
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'learning-resources',
  'learning-resources',
  false,
  52428800,
  array['application/pdf', 'image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do nothing;

-- Reads the chapter out of an object path, and answers null rather than raising when the path
-- does not follow the convention. A policy that raises on a malformed name is a policy that
-- can be turned into an error message.
create or replace function app.lesson_of_object(p_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $fn$
declare
  parts text[] := string_to_array(p_name, '/');
begin
  if array_length(parts, 1) < 3 then
    return null;
  end if;
  return parts[2]::uuid;
exception
  when others then
    return null;
end;
$fn$;

create or replace function app.track_subject_of_object(p_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $fn$
declare
  parts text[] := string_to_array(p_name, '/');
begin
  if array_length(parts, 1) < 3 then
    return null;
  end if;
  return parts[1]::uuid;
exception
  when others then
    return null;
end;
$fn$;

grant execute on function app.lesson_of_object(text) to authenticated;
grant execute on function app.track_subject_of_object(text) to authenticated;

-- The same three questions the `resources` policies ask, asked again at the file.
create policy learning_resources_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'learning-resources'
    and app.lesson_of_object(name) is not null
    and (
      app.teaches_lesson(app.lesson_of_object(name))
      or app.entitled_to_lesson(app.lesson_of_object(name))
      or app.lesson_is_free_preview(app.lesson_of_object(name))
    )
  );

create policy learning_resources_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'learning-resources'
    and app.track_subject_of_object(name) is not null
    and app.teaches(app.track_subject_of_object(name))
  );

create policy learning_resources_replace on storage.objects
  for update to authenticated
  using (
    bucket_id = 'learning-resources'
    and app.track_subject_of_object(name) is not null
    and app.teaches(app.track_subject_of_object(name))
  )
  with check (
    bucket_id = 'learning-resources'
    and app.track_subject_of_object(name) is not null
    and app.teaches(app.track_subject_of_object(name))
  );

-- A teacher adds, never removes (DEC-057) — the same rule the `resources` table follows.
create policy learning_resources_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'learning-resources' and app.is_super_admin());
