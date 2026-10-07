-- 20260830200000_public_rpc.sql
--
-- Une porte dans `public` pour le consentement du tuteur.
--
-- PostgREST n'expose que les schémas listés dans `[api] schemas` — `public`, et rien d'autre.
-- `app.record_guardian_consent` est donc injoignable depuis l'application, alors que c'est le
-- seul écrivain autorisé des deux colonnes de consentement (DEC-075) et que le trigger
-- `app.require_guardian_consent` refuse d'ouvrir un accès à un mineur tant qu'elles sont
-- vides. Sans ce pont, l'écran d'octroi ne peut pas ouvrir l'accès d'un mineur — c'est-à-dire
-- de la majorité des élèves de Bac.
--
-- `security invoker` volontairement : le pont ne doit rien ajouter. La fonction appelée est
-- `definer`, refuse quiconque n'est pas super admin et refuse de dater un consentement quand
-- aucun contact de tuteur n'est enregistré. Un pont `definer` déplacerait ces contrôles ici,
-- où on les oublierait.

create or replace function public.record_guardian_consent(p_user uuid)
returns timestamptz
language sql
volatile
security invoker
set search_path = ''
as $fn$
  select app.record_guardian_consent(p_user)
$fn$;

comment on function public.record_guardian_consent(uuid) is
  'Pont PostgREST vers app.record_guardian_consent. Super admin uniquement (contrôlé côté app).';

-- `public` inclut `anon` : on retire, puis on accorde à la seule audience qui a une identité.
revoke all on function public.record_guardian_consent(uuid) from public;
grant execute on function public.record_guardian_consent(uuid) to authenticated;
