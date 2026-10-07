-- 20260831090000_live_doors.sql
--
-- Les portes d'écriture du direct, et le pont PostgREST pour les portes de lecture.
--
-- `20260829090400` a bien fermé `public.streams` : RLS active, aucune policy, aucun grant.
-- C'est exactement ce que demande DEC-066 — une adresse d'ingestion et une clé de flux ne
-- doivent jamais être une colonne que quelqu'un peut `select`. Mais il en manquait la moitié :
-- trois fonctions pour **lire** un flux, aucune pour en **ouvrir** un. L'application ne
-- pouvait donc pas insérer une ligne dans `streams`, donc pas ouvrir un live, donc tout le
-- direct tournait sur l'espace de démonstration en mémoire — invisible pour un vrai élève.
--
-- Et les trois fonctions de lecture vivent dans `app`, que PostgREST n'expose pas : elles
-- étaient injoignables depuis le site. Ce fichier ajoute les ponts `public`, comme
-- `20260830200000_public_rpc.sql` l'a fait pour le consentement.
--
-- Le principe ne change pas : `security definer` pour franchir l'absence de grant, et chaque
-- fonction contrôle elle-même l'appelant avant d'écrire. Aucune policy n'est affaiblie.

-- ---------------------------------------------------------------------------
-- Le semestre en cours
-- ---------------------------------------------------------------------------

-- Le 31 août ne tombe dans aucun terme : l'année scolaire marocaine va de septembre à juin, et
-- l'été est un trou. Une séance de rattrapage ouverte fin août appartient au semestre qui
-- **arrive** — c'est ce que l'enseignant a en tête et c'est le semestre que l'élève aura payé.
-- D'où l'ordre : le terme qui couvre aujourd'hui, sinon le prochain, sinon le dernier connu.
-- Sans ce repli, ouvrir un live échouerait toutes les vacances sans que personne comprenne.
create or replace function app.current_term()
returns uuid
language sql
stable
security definer
set search_path = ''
as $fn$
  select t.id
  from public.academic_terms t
  order by
    (current_date between t.starts_on and t.ends_on) desc,
    (t.starts_on >= current_date) desc,
    case when t.starts_on >= current_date then t.starts_on end asc nulls last,
    t.starts_on desc
  limit 1;
$fn$;

comment on function app.current_term() is
  'Le terme du jour, sinon le prochain, sinon le dernier. Jamais nul tant qu''un terme existe.';

-- ---------------------------------------------------------------------------
-- Ouvrir un direct
-- ---------------------------------------------------------------------------

-- Une seule transaction pour le flux et le live : un flux créé chez le fournisseur puis
-- orphelin en base, c'est une clé de diffusion qui existe et que plus personne ne peut
-- révoquer. Si l'insertion du live échoue — séance déjà à l'antenne, séance non publiée — le
-- flux disparaît avec elle.
create or replace function app.open_live(
  p_session      uuid,
  p_provider     text,
  p_public_id    text,
  p_ingest_url   text,
  p_stream_key   text,
  p_playback_url text
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

  -- Publiée, sinon rien : une proposition qui attend le super admin ne passe pas à l'antenne,
  -- même pour l'enseignant qui l'a proposée (DEC-064).
  select s.track_subject_id into v_link
  from public.sessions s
  where s.id = p_session and s.published;

  if v_link is null then
    raise exception 'unknown or unpublished seance' using errcode = 'no_data_found';
  end if;

  -- Le contrôle de portée est ici et non dans une policy, parce que `definer` les contourne.
  -- C'est la même question que `live_sessions_open` pose, posée au même moment.
  if not app.teaches(v_link) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  v_term := app.current_term();
  if v_term is null then
    raise exception 'no academic term' using errcode = 'no_data_found';
  end if;
  select t.semester into v_semester from public.academic_terms t where t.id = v_term;

  insert into public.streams (provider, public_id, ingest_url, stream_key, playback_url, opened_by)
  values (p_provider, p_public_id, p_ingest_url, p_stream_key, p_playback_url, auth.uid())
  returning id into v_stream;

  -- L'index `live_sessions_one_open` refuse un second direct sur la même séance, et le trigger
  -- `live_sessions_check_session` revérifie la publication. Les deux lèvent, donc annulent
  -- l'insertion du flux ci-dessus.
  insert into public.live_sessions
    (session_id, track_subject_id, term_id, semester, stream_id, opened_by)
  values (p_session, v_link, v_term, v_semester, v_stream, auth.uid())
  returning id into v_live;

  return v_live;
end;
$fn$;

comment on function app.open_live(uuid, text, text, text, text, text) is
  'Ouvre un direct sur une séance publiée. Réservé à qui enseigne la matière. Écrit le flux '
  'et le live dans la même transaction (DEC-065, DEC-066).';

-- ---------------------------------------------------------------------------
-- Fermer un direct
-- ---------------------------------------------------------------------------

-- Fermer classe la séance dans le même geste (DEC-063) : il n'y a pas d'étape « enregistrer »
-- qu'on puisse oublier. L'enregistrement est écrit même sans adresse de lecture — le
-- fournisseur met quelques minutes à finir l'archive, et une séance qui a eu lieu ne doit pas
-- se perdre pendant ce délai.
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

  update public.live_sessions set closed_at = now() where id = p_live;

  -- La clé de diffusion meurt avec le direct. Elle n'autorise plus rien chez le fournisseur —
  -- le flux y est supprimé à la fermeture — et une clé conservée est une clé qui peut fuir.
  update public.streams
  set stream_key   = null,
      ingest_url   = null,
      playback_url = coalesce(p_playback_url, playback_url),
      closed_at    = now()
  where id = row_live.stream_id;

  insert into public.recordings
    (live_id, session_id, track_subject_id, semester, stream_id, title, started_at, ended_at)
  values (
    p_live,
    row_live.session_id,
    row_live.track_subject_id,
    row_live.semester,
    row_live.stream_id,
    nullif(btrim(coalesce(p_title, '')), ''),
    row_live.opened_at,
    now()
  )
  returning id into v_rec;

  return v_rec;
end;
$fn$;

comment on function app.close_live(uuid, text, text) is
  'Ferme un direct, efface la clé de diffusion et classe la séance en enregistrement (DEC-063).';

-- ---------------------------------------------------------------------------
-- Les ponts PostgREST
--
-- `security invoker` volontairement : un pont ne doit rien ajouter. Les fonctions appelées
-- sont `definer` et contrôlent l'appelant elles-mêmes. Un pont `definer` déplacerait ces
-- contrôles ici, où on les oublierait.
-- ---------------------------------------------------------------------------

create or replace function public.open_live(
  p_session      uuid,
  p_provider     text,
  p_public_id    text,
  p_ingest_url   text,
  p_stream_key   text,
  p_playback_url text
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.open_live(p_session, p_provider, p_public_id, p_ingest_url, p_stream_key, p_playback_url)
$fn$;

create or replace function public.close_live(
  p_live         uuid,
  p_title        text default null,
  p_playback_url text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.close_live(p_live, p_title, p_playback_url)
$fn$;

-- L'adresse d'ingestion et la clé, à la seule personne qui a ouvert le direct. Le pont ne
-- change pas ça : `app.live_ingest` filtre déjà sur `opened_by = auth.uid()`.
create or replace function public.live_ingest(p_live uuid)
returns table (ingest_url text, stream_key text)
language sql
stable
security invoker
set search_path = ''
as $fn$
  select i.ingest_url, i.stream_key from app.live_ingest(p_live) i
$fn$;

create or replace function public.live_playback(p_live uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $fn$
  select app.live_playback(p_live)
$fn$;

create or replace function public.recording_playback(p_recording uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $fn$
  select app.recording_playback(p_recording)
$fn$;

-- `public` inclut `anon` : on retire, puis on accorde à la seule audience qui a une identité.
revoke all on function public.open_live(uuid, text, text, text, text, text) from public;
revoke all on function public.close_live(uuid, text, text) from public;
revoke all on function public.live_ingest(uuid) from public;
revoke all on function public.live_playback(uuid) from public;
revoke all on function public.recording_playback(uuid) from public;

grant execute on function public.open_live(uuid, text, text, text, text, text) to authenticated;
grant execute on function public.close_live(uuid, text, text) to authenticated;
grant execute on function public.live_ingest(uuid) to authenticated;
grant execute on function public.live_playback(uuid) to authenticated;
grant execute on function public.recording_playback(uuid) to authenticated;

grant execute on function app.open_live(uuid, text, text, text, text, text) to authenticated;
grant execute on function app.close_live(uuid, text, text) to authenticated;
grant execute on function app.current_term() to authenticated;
