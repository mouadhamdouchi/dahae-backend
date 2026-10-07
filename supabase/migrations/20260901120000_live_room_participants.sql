-- 20260901120000_live_room_participants.sql
--
-- La salle, et qui s'y trouve.
--
-- Jusqu'ici un direct était une **diffusion** : l'enseignant poussait un flux, les élèves le
-- regardaient, et personne des deux côtés ne savait qui était là. Le produit demande autre
-- chose (DEC-126) — une salle où l'enseignant voit la liste des présents se remplir en direct,
-- où l'élève peut prendre la parole et lever la main, et où l'enseignant et le super admin
-- peuvent couper un micro.
--
-- Ce fichier ajoute la seule chose qu'une salle a de plus qu'une diffusion : **une liste de
-- présents**. Le média reste chez le fournisseur ; ici on ne stocke que des personnes, des
-- horaires et des permissions.
--
-- ## Trois règles que la table porte plutôt que le code
--
-- **La caméra d'un élève n'existe pas.** Ce n'est pas une préférence par défaut, c'est le
-- produit (DEC-127) : un cours de trente élèves n'est pas une visioconférence, et la caméra
-- d'un mineur allumée dans sa chambre est une question de protection avant d'être une question
-- de bande passante. Il n'y a donc aucune colonne `can_publish_video` : rien à mettre à `true`,
-- et rien qu'une erreur puisse activer.
--
-- **Le micro est libre, et se retire.** `can_publish_audio` vaut `true` à l'arrivée. Le retirer
-- est un acte d'enseignant ou de super admin, il est daté et il est signé — `muted_by` répond à
-- « qui a coupé ce micro », qui est exactement la question posée quand un élève se plaint.
--
-- **Une main levée est un horodatage, pas un booléen.** `hand_raised_at` ordonne la file : le
-- premier qui a demandé la parole passe en premier, ce qu'un `boolean` ne peut pas dire. Baisser
-- la main remet la colonne à `null`.
--
-- ## Ce que la présence ne peut pas savoir
--
-- Un navigateur qui se ferme proprement appelle `app.live_leave`. Un navigateur qui plante, un
-- portable qui perd le réseau, un onglet tué par le système : rien n'est appelé, et la ligne
-- resterait « présente » indéfiniment. D'où `last_seen_at`, rafraîchi par un battement, et un
-- roster qui ne compte présent que ce qui a donné signe de vie récemment. C'est la seule façon
-- honnête d'afficher une liste de présents : la connexion est la source de vérité, pas la
-- dernière intention exprimée.

-- ---------------------------------------------------------------------------
-- Le fournisseur temps réel
-- ---------------------------------------------------------------------------

-- AWS IVS Real-Time (Stages) est un service distinct d'IVS Low-Latency : l'un est une salle
-- WebRTC, l'autre une diffusion RTMPS. Ils ne partagent ni API ni identifiants, donc ils ne
-- partagent pas non plus un nom de fournisseur (DEC-126).
alter table public.streams drop constraint if exists streams_provider_check;
alter table public.streams
  add constraint streams_provider_check
  check (provider in ('demo', 'cloudinary', 'aws-ivs', 'aws-ivs-realtime'));

-- ---------------------------------------------------------------------------
-- Les rôles dans la salle
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'room_role') then
    -- `host` publie et modère. `observer` est le super admin qui regarde sans être vu ni
    -- entendu — sa présence est un contrôle, pas une participation. `learner` écoute et peut
    -- parler.
    create type app.room_role as enum ('host', 'observer', 'learner');
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Les présents
-- ---------------------------------------------------------------------------

create table if not exists public.live_participants (
  id               uuid primary key default extensions.gen_random_uuid(),
  live_id          uuid not null references public.live_sessions (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  room_role        app.room_role not null,

  joined_at        timestamptz not null default now(),
  -- Nul tant que la personne est dans la salle. Renseigné au départ propre, et par le ménage
  -- pour ce qui n'a plus donné signe de vie.
  left_at          timestamptz,
  last_seen_at     timestamptz not null default now(),

  -- Quand la main a été levée. L'ordre des demandes est l'ordre des horodatages.
  hand_raised_at   timestamptz,

  -- Le micro. Retiré par un enseignant ou le super admin, jamais par l'élève lui-même : se
  -- taire ne demande la permission de personne et ne s'écrit pas en base.
  can_publish_audio boolean not null default true,
  muted_by         uuid references public.profiles (id) on delete set null,
  muted_at         timestamptz,

  /*
    L'identifiant que le fournisseur donne à cette personne dans sa salle.

    C'est la seule chose qu'un appel de déconnexion sait viser : couper un micro écrit un droit
    ici, mais faire taire un navigateur qui publie déjà se fait chez le fournisseur, et il ne
    connaît ni nos comptes ni nos lignes. Sans cette colonne, la modération ne prendrait effet
    qu'à la bonne volonté du client.

    Nul jusqu'au premier jeton : la ligne existe dès l'entrée, l'identifiant n'arrive qu'avec
    la réponse du fournisseur.
  */
  provider_participant_id text check (char_length(provider_participant_id) between 1 and 200),

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  -- Une personne, un direct, une ligne. Revenir après une coupure met la ligne à jour, il ne
  -- s'en crée pas une seconde — sinon la liste des présents compterait deux fois le même élève
  -- dès la première reconnexion, et l'assiduité serait fausse.
  constraint live_participants_once unique (live_id, user_id),

  constraint live_participants_left_after_join check (left_at is null or left_at >= joined_at),
  -- Un micro coupé porte toujours qui l'a coupé et quand. Un micro ouvert ne porte rien : la
  -- paire est vidée à la réouverture, sinon l'écran afficherait le nom du modérateur sous un
  -- micro qui marche.
  constraint live_participants_mute_signed check (
    (can_publish_audio and muted_by is null and muted_at is null)
    or (not can_publish_audio and muted_at is not null)
  )
);

-- La question posée en boucle par l'écran de l'enseignant : qui est présent dans ce direct.
create index if not exists live_participants_room_idx
  on public.live_participants (live_id, left_at, last_seen_at desc);

-- La file de parole : les mains levées, dans l'ordre où elles se sont levées.
create index if not exists live_participants_hands_idx
  on public.live_participants (live_id, hand_raised_at)
  where hand_raised_at is not null;

-- L'assiduité d'un élève, tous directs confondus. C'est ce que lira la condition de présence
-- d'une attestation.
create index if not exists live_participants_user_idx
  on public.live_participants (user_id, joined_at desc);

drop trigger if exists live_participants_touch on public.live_participants;
create trigger live_participants_touch before update on public.live_participants
  for each row execute function app.touch();

comment on table public.live_participants is
  'Qui est dans une salle de direct, depuis quand, la main levee ou non, le micro ouvert ou '
  'non. Aucune colonne de camera : un eleve ne publie jamais de video (DEC-127).';

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- Lecture seulement, et rien d'autre. Toutes les écritures passent par les portes plus bas :
-- une policy `update` sur cette table laisserait un élève s'ouvrir le micro que l'enseignant
-- vient de fermer, en une requête PostgREST et sans rien contourner.
-- ---------------------------------------------------------------------------

alter table public.live_participants enable row level security;

drop policy if exists live_participants_read on public.live_participants;

-- Sa propre ligne, et rien d'autre — plus la salle entière pour l'encadrement de la matière.
--
-- Un premier jet laissait chaque élève lire les lignes de tous les autres, au motif qu'on voit
-- bien ses camarades dans une vraie classe. Deux choses le rendent faux ici. La liste ne porte
-- pas des visages mais des identifiants de comptes, donc elle ne donne rien d'utile à l'élève
-- tout en distribuant l'annuaire des inscrits d'une matière ; et une part importante des
-- apprenants sont mineurs, ce qui rend le défaut « le moins possible » plutôt que « ce qui
-- semble naturel » (`context/security.md`).
--
-- Ce dont l'élève a réellement besoin, c'est de sa propre ligne — pour que la coupure de son
-- micro lui arrive à la seconde par le flux temps réel — et du nombre de présents, que
-- `app.live_headcount` rend sans nommer personne.
create policy live_participants_read on public.live_participants
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.live_sessions l
      where l.id = live_id and app.teaches(l.track_subject_id)
    )
  );

revoke all on public.live_participants from anon, authenticated;
grant select on public.live_participants to authenticated;

-- ---------------------------------------------------------------------------
-- Entrer dans la salle
--
-- La seule porte qui crée une ligne. Elle répond aussi à la question que le serveur de jetons
-- pose juste après : **quel rôle**, et **le micro est-il ouvert** — parce que le jeton remis au
-- fournisseur en dépend, et qu'un jeton plus large que le droit est un droit accordé.
-- ---------------------------------------------------------------------------

create or replace function app.live_join(p_live uuid)
returns table (
  participant_id    uuid,
  room_role         app.room_role,
  can_publish_audio boolean,
  hand_raised       boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  row_live public.live_sessions%rowtype;
  v_role   app.room_role;
  v_id     uuid;
  v_audio  boolean;
  v_hand   timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  select * into row_live from public.live_sessions l where l.id = p_live;
  if not found or row_live.closed_at is not null then
    raise exception 'no live' using errcode = 'no_data_found';
  end if;

  /*
    L'ordre compte.

    Celui qui a ouvert le direct anime, quel que soit son rôle par ailleurs : un super admin
    qui ouvre lui-même un cours l'anime, il ne l'observe pas. Ensuite le super admin observe —
    présent, silencieux, et c'est le seul rôle qui donne un droit de regard sans donner un
    droit de parole. Ensuite l'enseignant affecté à la matière anime. Enfin l'élève, s'il a un
    accès **en cours** sur cette matière et ce semestre (DEC-058, DEC-062) : un semestre fini
    garde ses enregistrements, pas une place dans le cours d'aujourd'hui.
  */
  if row_live.opened_by = auth.uid() then
    v_role := 'host';
  elsif app.is_super_admin() then
    v_role := 'observer';
  elsif app.teaches(row_live.track_subject_id) then
    v_role := 'host';
  elsif app.session_is_published(row_live.session_id)
        and app.entitled_now(row_live.track_subject_id, row_live.semester) then
    v_role := 'learner';
  else
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  /*
    Revenir n'efface pas ce qui a été décidé.

    `can_publish_audio` et la signature de la coupure sont volontairement absents du `set` :
    un élève dont l'enseignant vient de couper le micro le rouvrirait en rechargeant la page,
    ce qui viderait la modération de son sens. `joined_at` non plus — c'est l'heure d'arrivée
    au cours, pas l'heure de la dernière reconnexion, et c'est elle que lira l'assiduité.

    La main, en revanche, retombe : une main levée avant une coupure de réseau n'est plus une
    demande de parole quand la personne revient trois minutes plus tard.
  */
  insert into public.live_participants (live_id, user_id, room_role)
  values (p_live, auth.uid(), v_role)
  on conflict (live_id, user_id) do update
    set left_at        = null,
        last_seen_at   = now(),
        hand_raised_at = null,
        room_role      = excluded.room_role
  returning id, live_participants.can_publish_audio, live_participants.hand_raised_at
    into v_id, v_audio, v_hand;

  -- Un observateur ne publie rien, jamais. La colonne peut valoir ce qu'elle veut, la réponse
  -- est non : c'est le rôle qui décide, pas l'état d'une ligne.
  if v_role = 'observer' then
    v_audio := false;
  end if;

  return query select v_id, v_role, v_audio, (v_hand is not null);
end;
$fn$;

create or replace function public.live_join(p_live uuid)
returns table (
  participant_id    uuid,
  room_role         app.room_role,
  can_publish_audio boolean,
  hand_raised       boolean
)
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select * from app.live_join(p_live);
$fn$;

-- ---------------------------------------------------------------------------
-- Ranger l'identifiant que le fournisseur vient de donner
--
-- Écrit par la route qui a émis le jeton, pour la personne à qui elle vient de l'émettre et
-- pour personne d'autre. C'est ce qui rend une déconnexion possible plus tard ; sans lui, un
-- micro coupé ne serait qu'une demande polie adressée au navigateur de l'élève.
-- ---------------------------------------------------------------------------

create or replace function app.live_attach_participant(p_live uuid, p_provider_id text)
returns void
language sql
volatile
security definer
set search_path = ''
as $fn$
  update public.live_participants
  set provider_participant_id = p_provider_id
  where live_id = p_live and user_id = auth.uid() and left_at is null;
$fn$;

create or replace function public.live_attach_participant(p_live uuid, p_provider_id text)
returns void
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.live_attach_participant(p_live, p_provider_id);
$fn$;

-- ---------------------------------------------------------------------------
-- Le battement, et la sortie
-- ---------------------------------------------------------------------------

-- Appelé pendant que la page est ouverte. Il ne renvoie rien et ne peut rien changer d'autre
-- que l'heure : c'est la fonction la plus souvent appelée du produit, elle doit être
-- inoffensive par construction.
create or replace function app.live_heartbeat(p_live uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $fn$
  update public.live_participants
  set last_seen_at = now()
  where live_id = p_live and user_id = auth.uid() and left_at is null;
$fn$;

create or replace function public.live_heartbeat(p_live uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.live_heartbeat(p_live);
$fn$;

-- Quitter proprement. La main retombe en même temps : une main levée par quelqu'un qui est
-- parti est une demande de parole adressée à personne.
create or replace function app.live_leave(p_live uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $fn$
  update public.live_participants
  set left_at = now(), hand_raised_at = null
  where live_id = p_live and user_id = auth.uid() and left_at is null;
$fn$;

create or replace function public.live_leave(p_live uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.live_leave(p_live);
$fn$;

-- ---------------------------------------------------------------------------
-- Lever la main
-- ---------------------------------------------------------------------------

create or replace function app.live_raise_hand(p_live uuid, p_raised boolean)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  /*
    `case when hand_raised_at is null then now() else hand_raised_at end` plutôt que `now()`.

    Sans ça, un double clic — ou le second onglet que l'élève avait laissé ouvert — remettrait
    l'horodatage à maintenant et enverrait la personne à la fin de la file alors qu'elle
    demandait la parole depuis deux minutes. Lever une main déjà levée ne fait rien.
  */
  update public.live_participants
  set hand_raised_at = case
        when not p_raised then null
        when hand_raised_at is null then now()
        else hand_raised_at
      end
  where live_id = p_live
    and user_id = auth.uid()
    and left_at is null
    and room_role = 'learner'
  returning hand_raised_at into v_at;

  if not found then
    raise exception 'not in this room' using errcode = 'no_data_found';
  end if;

  return v_at;
end;
$fn$;

create or replace function public.live_raise_hand(p_live uuid, p_raised boolean)
returns timestamptz
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.live_raise_hand(p_live, p_raised);
$fn$;

-- ---------------------------------------------------------------------------
-- Couper un micro
--
-- Réservé à l'encadrement de la matière : `app.teaches` répond vrai pour le super admin comme
-- pour l'enseignant affecté, et c'est exactement la population voulue.
--
-- Ce que cette fonction fait **et ne fait pas** : elle écrit le droit. Elle ne fait pas taire
-- le navigateur de l'élève — ça, c'est l'affaire de l'appel `DisconnectParticipant` chez le
-- fournisseur, que la route déclenche juste après en lisant cette même colonne. L'ordre est
-- délibéré : le droit est retiré d'abord, la déconnexion ensuite, de sorte qu'un élève qui se
-- reconnecte dans la seconde reçoive un jeton sans droit de publier. L'inverse laisserait une
-- fenêtre où la reconnexion rend le micro.
-- ---------------------------------------------------------------------------

create or replace function app.live_set_mic(p_live uuid, p_user uuid, p_allowed boolean)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  row_live public.live_sessions%rowtype;
  v_provider text;
begin
  select * into row_live from public.live_sessions l where l.id = p_live;
  if not found then
    raise exception 'no live' using errcode = 'no_data_found';
  end if;

  if not app.teaches(row_live.track_subject_id) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  -- Un animateur ne se fait pas couper le micro par un autre animateur. La modération porte
  -- sur la classe, pas sur le corps enseignant ; ce qui se règle entre collègues ne se règle
  -- pas avec un bouton.
  update public.live_participants
  set can_publish_audio = p_allowed,
      muted_by = case when p_allowed then null else auth.uid() end,
      muted_at = case when p_allowed then null else now() end
  where live_id = p_live
    and user_id = p_user
    and room_role = 'learner'
  returning provider_participant_id into v_provider;

  if not found then
    raise exception 'not a learner in this room' using errcode = 'no_data_found';
  end if;

  perform app.record_audit(
    case when p_allowed then 'micRestored' else 'micMuted' end,
    'Micro d''un eleve pendant un direct',
    'live_participants',
    p_user,
    jsonb_build_object('live_id', p_live, 'can_publish_audio', p_allowed)
  );

  return v_provider;
end;
$fn$;

create or replace function public.live_set_mic(p_live uuid, p_user uuid, p_allowed boolean)
returns text
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.live_set_mic(p_live, p_user, p_allowed);
$fn$;

-- Couper tout le monde d'un coup. Une salle qui part en bruit se rattrape en un geste, pas en
-- trente. Les mains restent levées : couper les micros n'annule pas les demandes de parole.
create or replace function app.live_mute_all(p_live uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  row_live public.live_sessions%rowtype;
  v_count  integer;
begin
  select * into row_live from public.live_sessions l where l.id = p_live;
  if not found then
    raise exception 'no live' using errcode = 'no_data_found';
  end if;

  if not app.teaches(row_live.track_subject_id) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  update public.live_participants
  set can_publish_audio = false, muted_by = auth.uid(), muted_at = now()
  where live_id = p_live
    and room_role = 'learner'
    and left_at is null
    and can_publish_audio;

  get diagnostics v_count = row_count;

  perform app.record_audit(
    'micMuted',
    'Tous les micros coupes pendant un direct',
    'live_participants',
    null,
    jsonb_build_object('live_id', p_live, 'muted', v_count)
  );

  return v_count;
end;
$fn$;

create or replace function public.live_mute_all(p_live uuid)
returns integer
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.live_mute_all(p_live);
$fn$;

-- ---------------------------------------------------------------------------
-- La liste des présents, avec des noms
--
-- `live_participants` ne porte que des identifiants, et une liste d'UUID n'est pas une liste
-- de présents. Le nom vient de `profiles`, qu'un élève ne peut pas lire pour les autres — d'où
-- une fonction `security definer` réservée à l'encadrement plutôt qu'une jointure côté client.
--
-- « Présent » se mesure au battement, pas à l'intention : quinze secondes de battement, une
-- minute de tolérance. Un onglet fermé brutalement disparaît donc de la liste en moins d'une
-- minute, sans que personne ait rien à nettoyer.
-- ---------------------------------------------------------------------------

create or replace function app.live_roster(p_live uuid)
returns table (
  user_id           uuid,
  full_name         text,
  room_role         app.room_role,
  joined_at         timestamptz,
  last_seen_at      timestamptz,
  present           boolean,
  hand_raised_at    timestamptz,
  can_publish_audio boolean,
  muted_by_name     text,
  provider_participant_id text
)
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
    raise exception 'no live' using errcode = 'no_data_found';
  end if;

  if not app.teaches(row_live.track_subject_id) then
    raise exception 'not allowed' using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      p.user_id,
      coalesce(prof.full_name, prof.email, '—'),
      p.room_role,
      p.joined_at,
      p.last_seen_at,
      (p.left_at is null and p.last_seen_at > now() - interval '60 seconds'),
      p.hand_raised_at,
      p.can_publish_audio,
      muter.full_name,
      p.provider_participant_id
    from public.live_participants p
    join public.profiles prof on prof.id = p.user_id
    left join public.profiles muter on muter.id = p.muted_by
    where p.live_id = p_live
    order by
      -- Ce que l'enseignant doit voir en premier : les mains levées, dans l'ordre où elles se
      -- sont levées. Puis les présents, puis ceux qui sont partis.
      (p.hand_raised_at is null),
      p.hand_raised_at asc,
      (p.left_at is not null),
      p.joined_at asc;
end;
$fn$;

create or replace function public.live_roster(p_live uuid)
returns table (
  user_id           uuid,
  full_name         text,
  room_role         app.room_role,
  joined_at         timestamptz,
  last_seen_at      timestamptz,
  present           boolean,
  hand_raised_at    timestamptz,
  can_publish_audio boolean,
  muted_by_name     text,
  provider_participant_id text
)
language sql
stable
security invoker
set search_path = ''
as $fn$
  select * from app.live_roster(p_live);
$fn$;

-- ---------------------------------------------------------------------------
-- Le compte, pour tout le monde
--
-- Un élève n'a pas à connaître le nom des autres élèves — mais savoir qu'ils sont vingt-quatre
-- dans la salle change la façon dont on suit un cours, et c'est une information qu'il aurait
-- de toute façon en classe. Un entier, donc, et rien de plus.
-- ---------------------------------------------------------------------------

create or replace function app.live_headcount(p_live uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $fn$
  select count(*)::integer
  from public.live_participants p
  join public.live_sessions l on l.id = p.live_id
  where p.live_id = p_live
    and p.left_at is null
    and p.last_seen_at > now() - interval '60 seconds'
    and p.room_role <> 'observer'
    and (
      app.teaches(l.track_subject_id)
      or app.entitled_now(l.track_subject_id, l.semester)
    );
$fn$;

create or replace function public.live_headcount(p_live uuid)
returns integer
language sql
stable
security invoker
set search_path = ''
as $fn$
  select app.live_headcount(p_live);
$fn$;

-- ---------------------------------------------------------------------------
-- Fermer le direct ferme la salle
--
-- Sans ça, les lignes d'un direct terminé resteraient « présentes » jusqu'à ce que le battement
-- expire, et l'assiduité enregistrerait des départs à soixante secondes de la fin pour tout le
-- monde. La fin du cours est l'heure de sortie de ceux qui étaient encore là.
-- ---------------------------------------------------------------------------

create or replace function app.close_live_participants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.closed_at is not null and old.closed_at is null then
    update public.live_participants
    set left_at = new.closed_at, hand_raised_at = null
    where live_id = new.id and left_at is null;
  end if;
  return new;
end;
$fn$;

drop trigger if exists live_sessions_close_room on public.live_sessions;
create trigger live_sessions_close_room
  after update on public.live_sessions
  for each row execute function app.close_live_participants();

-- ---------------------------------------------------------------------------
-- Les droits d'exécution
--
-- Rien n'est ouvert à `anon` : une salle de classe se regarde connecté.
-- ---------------------------------------------------------------------------

grant execute on function public.live_join(uuid)                    to authenticated;
grant execute on function public.live_attach_participant(uuid, text) to authenticated;
grant execute on function public.live_heartbeat(uuid)               to authenticated;
grant execute on function public.live_leave(uuid)                   to authenticated;
grant execute on function public.live_raise_hand(uuid, boolean)     to authenticated;
grant execute on function public.live_set_mic(uuid, uuid, boolean)  to authenticated;
grant execute on function public.live_mute_all(uuid)                to authenticated;
grant execute on function public.live_roster(uuid)                  to authenticated;
grant execute on function public.live_headcount(uuid)               to authenticated;

-- ---------------------------------------------------------------------------
-- Le temps réel
--
-- La liste des présents doit se remplir toute seule sur l'écran de l'enseignant : sans ça il
-- faudrait interroger la base toutes les deux secondes pour trente élèves, et le « en direct »
-- de l'énoncé deviendrait « toutes les deux secondes ».
--
-- `supabase_realtime` respecte RLS : chaque abonné ne reçoit que les lignes que sa policy de
-- lecture lui laisse voir. La policy plus haut est donc aussi la règle du flux temps réel, et
-- il n'y a pas une seconde règle à garder d'accord avec la première.
--
-- `replica identity full` parce qu'un `update` doit livrer l'ancienne ligne autant que la
-- nouvelle : sans elle, un abonné reçoit « une ligne a changé » sans savoir laquelle, et la
-- main qui se lève n'a plus de propriétaire.
-- ---------------------------------------------------------------------------

alter table public.live_participants replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'live_participants'
     )
  then
    alter publication supabase_realtime add table public.live_participants;
  end if;
end
$$;
