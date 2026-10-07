-- 20260829120000_revoke_default_grants.sql
--
-- Reprend la main sur les privilèges de table, que Supabase accorde par défaut.
--
-- Ce que la première application du schéma a révélé : un projet Supabase pose
-- `alter default privileges in schema public grant all on tables to anon, authenticated`.
-- Chaque table créée par nos migrations a donc reçu SELECT, INSERT, UPDATE, DELETE,
-- TRUNCATE, REFERENCES et TRIGGER pour les deux rôles — par-dessus les `grant` précis que
-- ces migrations écrivaient. Vérifié sur le projet, pas supposé.
--
-- Deux conséquences, dont une est un vrai trou :
--
-- 1. `streams` et `resource_media` n'étaient pas « injoignables faute de privilège »
--    (DEC-070). Elles restaient protégées, mais par la RLS seule : aucune policy, donc
--    aucune ligne. C'est une seule serrure là où la décision en promettait deux.
--
-- 2. **Le grant colonne par colonne sur `profiles` était annulé** (DEC-075). Un UPDATE
--    accordé sur la table entière rend la restriction de colonnes sans effet : un élève
--    mineur pouvait écrire son propre `guardian_consent_at`. C'est précisément ce que cette
--    colonne existe pour empêcher.
--
-- Donc : on révoque tout, on réaccorde exactement ce que les migrations 2 à 6 voulaient, et
-- on retire le privilège par défaut pour que les tables à venir n'en héritent plus.
--
-- Toute migration qui crée une table après celle-ci doit continuer d'écrire ses `grant` :
-- ils redeviennent la seule source, ce qu'ils auraient toujours dû être.

-- ---------------------------------------------------------------------------
-- 1. Table rase
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- Et pour les tables futures. Selon le rôle qui a posé les privilèges par défaut à la
-- création du projet, cette instruction peut ne rien retirer — c'est pour cela que la règle
-- « chaque migration écrit ses grants » reste la protection réelle, et que
-- `npm run check:sql` la vérifie.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Identité et journal
-- ---------------------------------------------------------------------------

grant select on public.centers to anon, authenticated;

grant select on public.profiles to authenticated;

-- Colonne par colonne, et c'est la partie porteuse. La RLS choisit les *lignes*, elle ne
-- choisit pas les *colonnes* : sans ce grant restreint, la policy `profiles_update_own`
-- laisserait un élève écrire `guardian_consent_at`, c'est-à-dire un mineur de quinze ans
-- attestant l'accord de son propre parent. Le consentement se recueille auprès du tuteur
-- (`security.md` section 2) ; `app.record_guardian_consent` est le seul écrivain.
grant update (
  full_name, avatar_url, locale, declared_track_id, date_of_birth,
  guardian_full_name, guardian_phone, guardian_relationship
) on public.profiles to authenticated;

grant select, insert, update, delete on public.user_roles to authenticated;

grant select on public.audit_events to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Catalogue
-- ---------------------------------------------------------------------------

grant select on public.tracks to anon, authenticated;
grant insert, update, delete on public.tracks to authenticated;

grant select on public.subjects to anon, authenticated;
grant insert, update, delete on public.subjects to authenticated;

grant select on public.track_subjects to anon, authenticated;
grant insert, update, delete on public.track_subjects to authenticated;

grant select, insert, update, delete on public.teacher_subjects to authenticated;

grant select on public.lessons to anon, authenticated;
grant insert, update, delete on public.lessons to authenticated;

grant select, insert, update, delete on public.resources to authenticated;

-- La vue qui laisse le catalogue public afficher ses pastilles « PDF, vidéo, série,
-- correction » sans ouvrir `resources` à un visiteur anonyme.
grant select on public.lesson_resource_kinds to anon, authenticated;

grant select, insert, update, delete on public.deletion_requests to authenticated;

-- `resource_media` : rien. Volontairement (DEC-070). C'est maintenant vrai.

-- ---------------------------------------------------------------------------
-- 4. Accès et paiements
-- ---------------------------------------------------------------------------

grant select on public.academic_terms to anon, authenticated;
grant insert, update, delete on public.academic_terms to authenticated;

grant select on public.packs to anon, authenticated;
grant insert, update, delete on public.packs to authenticated;

grant select, insert, update, delete on public.access_grants to authenticated;
grant select, insert, update, delete on public.access_grant_subjects to authenticated;
grant select, insert, update, delete on public.payments to authenticated;

grant select on public.settings to anon, authenticated;
grant update on public.settings to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Emploi du temps, lives, enregistrements
-- ---------------------------------------------------------------------------

grant select on public.sessions to anon, authenticated;
grant insert, update, delete on public.sessions to authenticated;

grant select, insert, update on public.live_sessions to authenticated;

grant select, insert, update, delete on public.recordings to authenticated;

-- `streams` : rien. La clé de flux, l'adresse d'ingestion et l'adresse de lecture ne sortent
-- que par `app.live_ingest`, `app.live_playback` et `app.recording_playback`, chacune après
-- sa propre vérification (DEC-066, DEC-070). C'est maintenant vrai aussi.

-- ---------------------------------------------------------------------------
-- 6. Progression
-- ---------------------------------------------------------------------------

grant select, insert, update on public.lesson_progress to authenticated;
