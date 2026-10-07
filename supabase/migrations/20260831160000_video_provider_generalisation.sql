-- 20260831160000_video_provider_generalisation.sql
--
-- Rendre la couche vidéo indépendante du fournisseur, et nommer les états.
--
-- Trois changements, tous additifs. Aucune colonne n'est supprimée, aucune donnée n'est
-- réécrite : les directs et les enregistrements Cloudinary existants restent lisibles pendant
-- toute la bascule vers AWS IVS.
--
-- ## 1. `provider_ref` — la poignée opaque
--
-- Chaque fournisseur a besoin d'un jeu d'identifiants différent, et ils n'ont rien en commun :
-- Cloudinary veut un `public_id` et un identifiant de flux, IVS veut un ARN de chaîne, un ARN
-- de clé de diffusion et un préfixe S3 d'enregistrement. Les colonnes existantes ont été
-- taillées pour le premier. Ajouter une colonne par identifiant du second — puis du suivant —
-- transformerait `streams` en union de tous les fournisseurs qu'on aura jamais essayés.
--
-- `provider_ref` est du `jsonb` **opaque à tout sauf à l'adaptateur**. Rien en SQL ne le lit,
-- aucune contrainte ne dépend de sa forme, aucune policy ne s'y réfère. C'est exactement ce que
-- veut dire « migrable » : le schéma cesse de connaître le fournisseur.
--
-- Il n'y met **jamais de secret**. La clé de diffusion garde sa colonne, parce qu'elle a des
-- règles propres — elle ne sort que par `app.live_ingest`, pour la seule personne qui a ouvert
-- le direct (DEC-066). Un secret noyé dans un `jsonb` est un secret qu'on oublie de protéger.
--
-- ## 2. Les états, nommés
--
-- Aujourd'hui « en cours de traitement » se déduit d'un `playback_url` nul, et « prêt » de sa
-- présence. Ça marche tant qu'il n'y a qu'une raison d'être nul. Avec un enregistrement qui
-- peut aussi échouer chez le fournisseur, une absence d'adresse ne distingue plus « patiente »
-- de « ça ne viendra jamais » — et c'est la différence entre une page qui dit d'attendre et une
-- page qui ment.
--
-- `scheduled` n'existe pas ici volontairement : une ligne `live_sessions` n'est créée qu'à
-- l'ouverture. Le direct *prévu*, c'est la séance dans `sessions`. Deux tables, deux faits.
--
-- ## 3. Pas de table `videos`
--
-- Une vidéo de cours pré-enregistrée **est** une ressource d'un chapitre — c'est la hiérarchie
-- que le produit impose (Filière → Matière → Cours → Ressources), et `resources` la porte déjà
-- avec `kind = 'video'`. Une table parallèle donnerait deux endroits où le média d'un chapitre
-- peut vivre, avec deux chemins d'autorisation à garder d'accord. `resource_media` gagne donc
-- ce qui manque à une vidéo — un état, une durée, une poignée de fournisseur — au lieu d'une
-- seconde table.

-- ---------------------------------------------------------------------------
-- Les états
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'live_status') then
    create type app.live_status as enum (
      'created',    -- la salle existe, aucun encodeur n'est connecté
      'live',       -- le fournisseur voit une diffusion
      'ending',     -- la fermeture est demandée, l'archive n'est pas finie
      'processing', -- l'encodeur est parti, l'archive s'écrit
      'ready',      -- l'enregistrement est regardable
      'failed',
      'cancelled'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'asset_status') then
    create type app.asset_status as enum ('processing', 'ready', 'failed');
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- streams
-- ---------------------------------------------------------------------------

alter table public.streams
  add column if not exists provider_ref jsonb not null default '{}'::jsonb;

comment on column public.streams.provider_ref is
  'Identifiants propres au fournisseur, opaques au SQL : rien ne les lit ici, aucune '
  'contrainte ni policy n''en dépend. Jamais de secret — la cle de diffusion garde sa '
  'colonne et ses regles (DEC-066).';

-- La contrainte de fournisseur doit accueillir IVS. `drop` puis `add` : une contrainte de
-- vérification ne se remplace pas.
alter table public.streams drop constraint if exists streams_provider_check;
alter table public.streams
  add constraint streams_provider_check
  check (provider in ('demo', 'cloudinary', 'aws-ivs'));

-- ---------------------------------------------------------------------------
-- live_sessions
-- ---------------------------------------------------------------------------

alter table public.live_sessions
  add column if not exists status app.live_status not null default 'created';

-- Les directs déjà fermés sont, par définition, passés par le traitement et arrivés au bout :
-- un enregistrement existe pour eux. Les remettre à `created` mentirait sur le passé.
update public.live_sessions
set status = 'ready'
where closed_at is not null and status = 'created';

create index if not exists live_sessions_status_idx
  on public.live_sessions (status)
  where status in ('live', 'ending', 'processing');

comment on column public.live_sessions.status is
  'Ou en est ce direct. `scheduled` n''existe pas : une seance prevue est une ligne de '
  '`sessions`, pas un direct qui n''a pas commence.';

-- ---------------------------------------------------------------------------
-- recordings
-- ---------------------------------------------------------------------------

alter table public.recordings
  add column if not exists status app.asset_status not null default 'processing';

-- Un enregistrement existant dont le flux porte déjà une adresse de lecture est prêt ; les
-- autres attendent encore leur archive. C'est exactement la règle que le code déduisait.
update public.recordings r
set status = 'ready'
from public.streams s
where s.id = r.stream_id
  and s.playback_url is not null
  and r.status = 'processing';

comment on column public.recordings.status is
  'Une adresse absente ne distingue pas « patiente » de « ca ne viendra jamais ». Cette '
  'colonne le fait, pour que l''ecran puisse dire l''un ou l''autre.';

-- ---------------------------------------------------------------------------
-- resource_media — la moitié VOD
-- ---------------------------------------------------------------------------

alter table public.resource_media
  add column if not exists status app.asset_status not null default 'ready',
  add column if not exists duration_seconds integer check (duration_seconds > 0),
  add column if not exists provider_ref jsonb not null default '{}'::jsonb;

-- `ready` par défaut, et c'est le bon défaut : tout ce qui est déjà là a été téléversé
-- directement dans le bucket et est lisible. Seule une vidéo confiée à un fournisseur qui
-- transcode naît `processing`.

alter table public.resource_media drop constraint if exists resource_media_provider_check;
alter table public.resource_media
  add constraint resource_media_provider_check
  check (provider in ('supabase', 'cloudinary', 's3'));

-- La contrainte d'adresse unique doit accepter S3, qui adresse par clé comme Supabase Storage.
alter table public.resource_media drop constraint if exists resource_media_one_address;
alter table public.resource_media
  add constraint resource_media_one_address check (
    (storage_key is not null and provider_public_id is null and storage_bucket is not null)
    or (provider_public_id is not null and storage_key is null and provider = 'cloudinary')
  );

comment on column public.resource_media.status is
  'Une video confiee a un fournisseur qui transcode nait `processing`. Un fichier televerse '
  'dans un bucket est `ready` des l''ecriture.';
