-- 20260830190000_profile_names.sql
--
-- Le nom donné par Google n'est pas le nom de l'élève.
--
-- Google renvoie un seul champ, tel que la personne l'a écrit dans son compte : « MOUAD
-- HAMDOUCHI » en capitales, un prénom seul, un surnom, parfois un compte partagé avec un
-- parent. C'est assez pour dire bonjour ; ce n'est pas assez pour une liste de classe, un
-- reçu de paiement ni un certificat, et une académie a besoin des trois.
--
-- Deux colonnes plutôt qu'une chaîne à découper : un établissement trie par nom de famille,
-- et `split_part(full_name, ' ', 2)` est faux dès qu'un nom composé apparaît — ce qui, au
-- Maroc, est la règle et non l'exception.
--
-- `full_name` reste la colonne d'affichage et reste `not null` : tout ce qui existe déjà la
-- lit. Elle est recomposée à partir des deux nouvelles à chaque enregistrement du profil, de
-- sorte qu'il n'y ait jamais deux vérités.

alter table public.profiles
  add column first_name text check (char_length(first_name) between 1 and 60),
  add column last_name  text check (char_length(last_name)  between 1 and 60);

comment on column public.profiles.first_name is
  'Prénom déclaré par la personne. Null tant que le profil n''est pas complété.';
comment on column public.profiles.last_name is
  'Nom de famille déclaré par la personne. Null tant que le profil n''est pas complété.';

-- Amorce à partir de ce que Google a fourni, pour les comptes déjà créés. Le premier mot est
-- le prénom, le reste le nom : c'est une proposition affichée dans le formulaire, jamais une
-- réponse — la personne la corrige avant d'enregistrer.
update public.profiles
set
  first_name = nullif(split_part(trim(full_name), ' ', 1), ''),
  last_name  = nullif(trim(substr(trim(full_name), length(split_part(trim(full_name), ' ', 1)) + 2)), '')
where first_name is null and last_name is null;

-- Le grant reste colonne par colonne (DEC-075) : ajouter une colonne sans l'ajouter ici la
-- rendrait non modifiable par son propriétaire, et l'ajouter en accordant la table entière
-- rouvrirait `guardian_consent_at`. Deux colonnes de plus, rien d'autre.
grant update (first_name, last_name) on public.profiles to authenticated;
