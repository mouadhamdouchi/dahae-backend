-- 20260831120000_resource_doors.sql
--
-- Les portes des ressources : écrire l'adresse d'un média, et la relire.
--
-- `20260829090200` a fermé `resource_media` exactement comme `streams` : RLS active, aucune
-- policy, aucun grant. C'est juste — une clé de stockage ou un identifiant Cloudinary n'a rien
-- à faire dans une colonne que quelqu'un peut `select` (DEC-070). Et comme pour le direct, il
-- manquait la moitié : `app.resource_media` sait **lire** une adresse, rien ne sait en
-- **écrire** une. Téléverser un PDF était donc impossible, quelle que soit l'interface.
--
-- Et `app.resource_media` vit dans le schéma `app`, que PostgREST n'expose pas : injoignable
-- depuis le site. On ajoute le pont, comme pour le consentement et pour le direct.
--
-- `resources` elle-même n'a besoin de rien : ses policies laissent déjà l'enseignant de la
-- matière insérer et modifier, et réservent la suppression au super admin (DEC-057). On ne
-- réécrit pas ici une règle qui tient déjà ailleurs.

-- ---------------------------------------------------------------------------
-- Attacher un média à une ressource
-- ---------------------------------------------------------------------------

-- Une ressource sans adresse est une ligne dans une liste qui ne s'ouvre pas. Les deux
-- écritures sont donc faites ensemble par l'appelant, et celle-ci refuse d'avance ce que la
-- contrainte `resource_media_one_address` refuserait de toute façon — une adresse ou l'autre,
-- jamais les deux, jamais aucune.
create or replace function app.attach_resource_media(
  p_resource   uuid,
  p_bucket     text default null,
  p_key        text default null,
  p_provider   text default null,
  p_public_id  text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_lesson uuid;
begin
  if auth.uid() is null then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  select r.lesson_id into v_lesson from public.resources r where r.id = p_resource;
  if v_lesson is null then
    raise exception 'unknown resource' using errcode = 'no_data_found';
  end if;

  -- La même question que pose `resources_insert`, posée ici parce que `definer` contourne les
  -- policies. Un enseignant n'attache un média qu'aux chapitres de ses matières.
  if not app.teaches_lesson(v_lesson) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  insert into public.resource_media
    (resource_id, storage_bucket, storage_key, provider, provider_public_id)
  values (p_resource, p_bucket, p_key, p_provider, p_public_id)
  on conflict (resource_id) do update
    set storage_bucket     = excluded.storage_bucket,
        storage_key        = excluded.storage_key,
        provider           = excluded.provider,
        provider_public_id = excluded.provider_public_id;
end;
$fn$;

comment on function app.attach_resource_media(uuid, text, text, text, text) is
  'Écrit l''adresse d''une ressource. Réservé à qui enseigne le chapitre. Seul écrivain de '
  'resource_media, qui n''a ni policy ni grant (DEC-070).';

-- ---------------------------------------------------------------------------
-- Les ponts PostgREST
--
-- `security invoker` : le pont n'ajoute rien. Les fonctions appelées sont `definer` et
-- contrôlent l'appelant elles-mêmes.
-- ---------------------------------------------------------------------------

create or replace function public.attach_resource_media(
  p_resource   uuid,
  p_bucket     text default null,
  p_key        text default null,
  p_provider   text default null,
  p_public_id  text default null
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.attach_resource_media(p_resource, p_bucket, p_key, p_provider, p_public_id)
$fn$;

-- Lire une adresse. `app.resource_media` demande déjà les trois bonnes questions : enseigne-t-il
-- ce chapitre, l'a-t-il payé, ou est-ce la première leçon gratuite (DEC-034).
create or replace function public.resource_media(p_resource uuid)
returns table (
  storage_bucket     text,
  storage_key        text,
  provider           text,
  provider_public_id text
)
language sql
stable
security invoker
set search_path = ''
as $fn$
  select m.storage_bucket, m.storage_key, m.provider, m.provider_public_id
  from app.resource_media(p_resource) m
$fn$;

revoke all on function public.attach_resource_media(uuid, text, text, text, text) from public;
revoke all on function public.resource_media(uuid) from public;

grant execute on function public.attach_resource_media(uuid, text, text, text, text) to authenticated;
grant execute on function public.resource_media(uuid) to authenticated;
grant execute on function app.attach_resource_media(uuid, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- La vidéo dans le seau privé
--
-- Le seau n'acceptait que des PDF et des images. Une vidéo de cours part chez Cloudinary
-- (architecture.md), mais une **correction filmée au téléphone** que l'enseignant dépose comme
-- un fichier n'a aucune raison de faire un détour par un fournisseur externe. On ouvre donc
-- les types que le seau accepte, sans toucher à sa taille limite ni à son caractère privé.
-- ---------------------------------------------------------------------------

update storage.buckets
set allowed_mime_types = array[
      'application/pdf',
      'image/png', 'image/jpeg', 'image/webp',
      'video/mp4', 'video/webm', 'video/quicktime'
    ]
where id = 'learning-resources';
