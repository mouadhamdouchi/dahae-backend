-- 20260831161000_video_doors.sql
--
-- Les portes, mises au niveau de la couche fournisseur générique.
--
-- Trois choses :
--
--   1. `app.open_live` range la poignée opaque du fournisseur et pose l'état de départ ;
--   2. `app.close_live` distingue « l'archive s'écrit » de « l'archive est prête » ;
--   3. `app.finish_recording` est la porte du webhook — la seule qui fasse passer un
--      enregistrement à `ready`.
--
-- ## Pourquoi une porte séparée pour le webhook
--
-- Jusqu'ici, la fin d'un direct et la disponibilité du replay étaient le même instant. Elles ne
-- le sont pas : chez tout fournisseur, l'archive se termine **après** que l'encodeur s'est
-- déconnecté, et chez celui-ci la mesure a donné environ six minutes (DEC-090). Le code
-- attendait cet instant en repassant plus tard — un balayage au prochain `openRoom`. C'est
-- exactement ce qu'il ne faut pas : l'information arrive quand le fournisseur le dit, pas quand
-- on repasse.
--
-- `finish_recording` n'est donc appelable ni par un élève ni par un enseignant. Elle est
-- appelée par la route de webhook, qui a vérifié la signature de l'événement et parle à la base
-- avec la clé de service. Elle ne prend pas d'identifiant interne : elle retrouve le flux par
-- sa poignée chez le fournisseur, parce que c'est la seule chose que l'événement contient.

-- ---------------------------------------------------------------------------
-- Ouvrir : ranger la poignée, nommer l'état
-- ---------------------------------------------------------------------------

create or replace function app.open_live(
  p_session      uuid,
  p_provider     text,
  p_public_id    text,
  p_ingest_url   text,
  p_stream_key   text,
  p_playback_url text,
  p_stream_ref   text default null,
  p_provider_ref jsonb default '{}'::jsonb
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
    (provider, public_id, ingest_url, stream_key, playback_url, provider_stream_id,
     provider_ref, opened_by)
  values
    (p_provider, p_public_id, p_ingest_url, p_stream_key, p_playback_url, p_stream_ref,
     coalesce(p_provider_ref, '{}'::jsonb), auth.uid())
  returning id into v_stream;

  insert into public.live_sessions
    (session_id, track_subject_id, term_id, semester, stream_id, opened_by, status)
  values (p_session, v_link, v_term, v_semester, v_stream, auth.uid(), 'created')
  returning id into v_live;

  return v_live;
end;
$fn$;

-- L'ancienne signature à sept arguments disparaît : deux surcharges rendent l'appel ambigu
-- pour PostgREST, et c'est une panne au moment précis où un enseignant ouvre son cours.
drop function if exists public.open_live(uuid, text, text, text, text, text, text);

create or replace function public.open_live(
  p_session      uuid,
  p_provider     text,
  p_public_id    text,
  p_ingest_url   text,
  p_stream_key   text,
  p_playback_url text,
  p_stream_ref   text default null,
  p_provider_ref jsonb default '{}'::jsonb
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.open_live(p_session, p_provider, p_public_id, p_ingest_url, p_stream_key,
                       p_playback_url, p_stream_ref, p_provider_ref);
$fn$;

-- ---------------------------------------------------------------------------
-- Fermer : le direct s'arrête, l'enregistrement commence à se faire attendre
-- ---------------------------------------------------------------------------

create or replace function app.close_live(
  p_live         uuid,
  p_title        text default null,
  p_playback_url text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  row_live public.live_sessions%rowtype;
  v_rec    uuid;
  v_ready  boolean;
begin
  if auth.uid() is null then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  select * into row_live from public.live_sessions l where l.id = p_live;
  if not found then
    raise exception 'unknown live' using errcode = 'no_data_found';
  end if;
  if not app.teaches(row_live.track_subject_id) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;
  if row_live.closed_at is not null then
    -- Fermer deux fois n'est pas une erreur à afficher : le premier appel a fait le travail.
    return (select r.id from public.recordings r where r.live_id = p_live);
  end if;

  -- Une adresse rendue à la fermeture veut dire que le fournisseur avait déjà fini l'archive.
  -- Rare, et c'est le seul cas où l'on peut annoncer un replay sans attendre l'événement.
  v_ready := nullif(btrim(coalesce(p_playback_url, '')), '') is not null;

  update public.live_sessions
  set closed_at = now(),
      status    = case when v_ready then 'ready'::app.live_status else 'processing'::app.live_status end
  where id = p_live;

  -- La clé de diffusion meurt avec le direct. Elle n'autorise plus rien chez le fournisseur —
  -- le flux y est supprimé à la fermeture — et une clé conservée est une clé qui peut fuir.
  update public.streams
  set stream_key   = null,
      ingest_url   = null,
      playback_url = coalesce(nullif(btrim(coalesce(p_playback_url, '')), ''), playback_url),
      closed_at    = now()
  where id = row_live.stream_id;

  insert into public.recordings
    (live_id, session_id, track_subject_id, semester, stream_id, title,
     started_at, ended_at, status)
  values (
    p_live,
    row_live.session_id,
    row_live.track_subject_id,
    row_live.semester,
    row_live.stream_id,
    nullif(btrim(coalesce(p_title, '')), ''),
    row_live.opened_at,
    now(),
    case when v_ready then 'ready'::app.asset_status else 'processing'::app.asset_status end
  )
  returning id into v_rec;

  return v_rec;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- La porte du webhook
-- ---------------------------------------------------------------------------

create or replace function app.finish_recording(
  p_provider     text,
  p_provider_key text,
  p_playback_url text,
  p_failed       boolean default false
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_stream uuid;
  v_rec    uuid;
begin
  -- Retrouvé par ce que l'événement porte, jamais par un identifiant interne : le fournisseur
  -- ne connaît que le sien. `public_id` d'abord parce que c'est ce qui adresse l'archive ;
  -- `provider_stream_id` ensuite parce que certains événements ne citent que le flux.
  select s.id into v_stream
  from public.streams s
  where s.provider = p_provider
    and (s.public_id = p_provider_key or s.provider_stream_id = p_provider_key)
  order by s.opened_at desc
  limit 1;

  if v_stream is null then
    -- Un événement pour un flux qu'on ne connaît pas n'est pas une erreur à faire remonter :
    -- le fournisseur réessaiera, et un webhook qui répond 500 finit par être désactivé.
    return null;
  end if;

  if p_failed then
    update public.live_sessions set status = 'failed' where stream_id = v_stream;
    update public.recordings set status = 'failed' where stream_id = v_stream
    returning id into v_rec;
    return v_rec;
  end if;

  update public.streams
  set playback_url = coalesce(nullif(btrim(coalesce(p_playback_url, '')), ''), playback_url)
  where id = v_stream;

  update public.live_sessions set status = 'ready' where stream_id = v_stream;

  update public.recordings set status = 'ready' where stream_id = v_stream
  returning id into v_rec;

  return v_rec;
end;
$fn$;

comment on function app.finish_recording(text, text, text, boolean) is
  'Appelee uniquement par la route de webhook, apres verification de la signature de '
  'l''evenement et avec la cle de service. Aucun grant a `anon` ni `authenticated` : un eleve '
  'qui pourrait declarer un enregistrement pret pourrait aussi le declarer pour un cours '
  'qu''il n''a pas paye.';

-- Aucun pont `public.finish_recording` : PostgREST n'expose que `public`, et cette fonction
-- n'a rien à y faire. La route de webhook parle au schéma `app` avec la clé de service.
revoke all on function app.finish_recording(text, text, text, boolean) from public;
revoke all on function app.finish_recording(text, text, text, boolean) from anon;
revoke all on function app.finish_recording(text, text, text, boolean) from authenticated;
