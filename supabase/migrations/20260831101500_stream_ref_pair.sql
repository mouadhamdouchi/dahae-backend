-- 20260831101500_stream_ref_pair.sql
--
-- `app.live_stream_ref` rendait une seule valeur, et il en faut deux.
--
-- Fermer un direct demande les deux identifiants, et ce ne sont pas les mêmes :
--
--   `provider_stream_id` adresse **le flux** chez Cloudinary — pour l'arrêter et le supprimer,
--   sans quoi il reste ouvert avec une clé de diffusion valide ;
--   `public_id` adresse **l'archive** — c'est ce qui répond encore la semaine suivante quand un
--   élève rattrape la séance, et c'est ce dont on a besoin pour composer l'adresse de lecture
--   qu'on écrit dans `streams.playback_url` en fermant.
--
-- Sans le second, la fermeture écrivait une adresse construite sur l'identifiant du live —
-- un uuid qui n'adresse rien chez le fournisseur. L'enregistrement aurait été listé, cliquable,
-- et vide. C'est exactement le genre de panne qui ne se voit qu'une semaine plus tard.
--
-- `returns table` au lieu de `returns text` : le type de retour change, donc `create or replace`
-- ne suffit pas.

drop function if exists public.live_stream_ref(uuid);
drop function if exists app.live_stream_ref(uuid);

create or replace function app.live_stream_ref(p_live uuid)
returns table (provider_stream_id text, public_id text)
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
    return;
  end if;
  -- Volontairement plus large que `app.live_ingest` : ni l'un ni l'autre n'est un secret, et le
  -- super admin doit pouvoir couper un direct qu'un enseignant a laissé ouvert. La clé, elle,
  -- ne sort toujours que par `live_ingest`, et pour la seule personne qui a ouvert le direct.
  if not app.teaches(row_live.track_subject_id) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  return query
    select s.provider_stream_id, s.public_id
    from public.streams s
    where s.id = row_live.stream_id;
end;
$fn$;

create or replace function public.live_stream_ref(p_live uuid)
returns table (provider_stream_id text, public_id text)
language sql
stable
security invoker
set search_path = ''
as $fn$
  select r.provider_stream_id, r.public_id from app.live_stream_ref(p_live) r
$fn$;

revoke all on function public.live_stream_ref(uuid) from public;
grant execute on function public.live_stream_ref(uuid) to authenticated;
grant execute on function app.live_stream_ref(uuid) to authenticated;
