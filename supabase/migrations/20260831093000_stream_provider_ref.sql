-- 20260831093000_stream_provider_ref.sql
--
-- La référence du flux **chez le fournisseur**, et la porte pour la relire.
--
-- Fermer un direct ne se limite pas à écrire `closed_at` : il faut aussi arrêter et supprimer
-- le flux chez Cloudinary. Sans ça chaque séance et chaque test laissent un flux derrière eux
-- pour toujours, avec une clé de diffusion toujours valide.
--
-- Pour l'adresser, il faut son identifiant Cloudinary. Il n'était nulle part : `public_id`
-- porte l'identifiant de **l'archive**, pas du flux. On pourrait le déduire de l'autre par
-- découpage de chaîne — `live_stream_<id>_archive` — et c'est précisément ce que
-- `lib/live/provider.ts` interdit en toutes lettres, parce que ça casse le jour où le
-- fournisseur renomme. On le stocke donc.
--
-- La colonne est dans `streams`, qui reste sans grant et sans policy : personne ne peut la
-- lire par une requête. Une fonction `security definer` de plus, avec son propre contrôle.

alter table public.streams
  add column provider_stream_id text
    check (char_length(provider_stream_id) between 1 and 200);

comment on column public.streams.provider_stream_id is
  'L''identifiant du flux chez le fournisseur, pour l''arrêter et le supprimer à la fermeture. '
  'Pas un secret — mais dans une table sans grant, donc lisible seulement par app.live_stream_ref.';

-- `create or replace` : même signature, un paramètre de plus en fin de liste avec un défaut,
-- pour que l'ancien appel à six arguments continue de fonctionner pendant le déploiement.
create or replace function app.open_live(
  p_session      uuid,
  p_provider     text,
  p_public_id    text,
  p_ingest_url   text,
  p_stream_key   text,
  p_playback_url text,
  p_stream_ref   text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_link     uuid;
  v_term     uuid;
  v_semester app.semester;
  v_stream   uuid;
  v_live     uuid;
begin
  if auth.uid() is null then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  select s.track_subject_id into v_link
  from public.sessions s
  where s.id = p_session and s.published;

  if v_link is null then
    raise exception 'unknown or unpublished seance' using errcode = 'no_data_found';
  end if;

  if not app.teaches(v_link) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  v_term := app.current_term();
  if v_term is null then
    raise exception 'no academic term' using errcode = 'no_data_found';
  end if;
  select t.semester into v_semester from public.academic_terms t where t.id = v_term;

  insert into public.streams
    (provider, public_id, ingest_url, stream_key, playback_url, provider_stream_id, opened_by)
  values
    (p_provider, p_public_id, p_ingest_url, p_stream_key, p_playback_url, p_stream_ref, auth.uid())
  returning id into v_stream;

  insert into public.live_sessions
    (session_id, track_subject_id, term_id, semester, stream_id, opened_by)
  values (p_session, v_link, v_term, v_semester, v_stream, auth.uid())
  returning id into v_live;

  return v_live;
end;
$fn$;

-- L'identifiant du flux, à qui enseigne la matière. Volontairement plus large que
-- `app.live_ingest` : ce n'est pas une clé, et le super admin doit pouvoir couper un direct
-- qu'un enseignant a laissé ouvert. La clé, elle, ne sort toujours que par `live_ingest`.
create or replace function app.live_stream_ref(p_live uuid)
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
  if not found then
    return null;
  end if;
  if not app.teaches(row_live.track_subject_id) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;
  return (select s.provider_stream_id from public.streams s where s.id = row_live.stream_id);
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Ponts PostgREST
-- ---------------------------------------------------------------------------

-- L'ancienne signature à six arguments est retirée : deux surcharges du même nom rendent
-- l'appel PostgREST ambigu, et le pont est né dans la migration précédente — rien en
-- production ne l'appelle encore.
drop function if exists public.open_live(uuid, text, text, text, text, text);

create or replace function public.open_live(
  p_session      uuid,
  p_provider     text,
  p_public_id    text,
  p_ingest_url   text,
  p_stream_key   text,
  p_playback_url text,
  p_stream_ref   text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.open_live(
    p_session, p_provider, p_public_id, p_ingest_url, p_stream_key, p_playback_url, p_stream_ref
  )
$fn$;

create or replace function public.live_stream_ref(p_live uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $fn$
  select app.live_stream_ref(p_live)
$fn$;

revoke all on function public.open_live(uuid, text, text, text, text, text, text) from public;
revoke all on function public.live_stream_ref(uuid) from public;

grant execute on function public.open_live(uuid, text, text, text, text, text, text) to authenticated;
grant execute on function public.live_stream_ref(uuid) to authenticated;
grant execute on function app.open_live(uuid, text, text, text, text, text, text) to authenticated;
grant execute on function app.live_stream_ref(uuid) to authenticated;
