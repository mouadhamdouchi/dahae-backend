# backend

The Supabase project for Dahae Academy: PostgreSQL schema, Row Level Security, Edge Functions,
seeds and generated types. Supabase *is* the backend — there is no separate API server (DEC-031).

## Structure

```text
supabase/
  config.toml     Supabase project configuration
  migrations/     forward-only SQL; never edit an applied migration, add a new one
  functions/      Edge Functions: bulk notifications, exports, batch generation
policies/         the reasoning behind the RLS, and its test matrix
seed/             reference data and the generator that writes it
types/            generated database types, imported by the frontend
check-sql.mjs     parses every migration and checks the RLS structure
```

`config.toml`, `migrations/` and `functions/` sit inside `supabase/` because the CLI requires
it: it only ever reads `<workdir>/supabase/migrations`, and a `db push` run against any other
layout reports "up to date" while applying nothing — which is exactly how it failed the first
time (DEC-076). Everything that is ours rather than the tool's stays one level up.

## What is here today

**Applied** to `ijauiiokhifuetcgiqlg` (dahae-academy-paris, `eu-west-3`) on 2026-08-29:
seven migrations, both seeds, and the generated types. The catalogue holds 79 chapters, nine
of them free, across nine published teaching units.

Seven migrations that build the whole MVP model: identity and audit, catalogue, access and
payments, timetable and lives, progress and storage. Every table has RLS enabled with grants and
policies written out explicitly, and every invariant that must hold whoever is calling is a
constraint or a trigger rather than a rule in a service.

Two seeds: `0001_reference.sql` (the centre, the school calendar, the settings row) and
`0002_catalogue.sql`, which is **generated** from `frontend/lib/demo-data/catalogue.ts` and
carries the 79 chapters of the real syllabus in three locales. Both are idempotent.

## Applying it

```bash
cd backend
npx supabase login
npx supabase link --project-ref <ref>

npx supabase db push

npx supabase db query --linked --file seed/0001_reference.sql
npx supabase db query --linked --file seed/0002_catalogue.sql

npm run db:types   # never edited by hand
```

## Checks

```bash
cd backend
npm install
npm run check:sql        # parse every migration and seed, and check the RLS structure
npm run seed:catalogue   # rewrite 0002_catalogue.sql from the catalogue module
```

`check:sql` parses with the grammar Postgres itself uses and then asserts this project's own
rules: RLS enabled on every table in `public`, a `WITH CHECK` on every write policy, a `USING`
on every read policy, and a pinned `search_path` on every `security definer` function. It never
touches a database, so it is not a substitute for running the migrations — it catches the
mistakes that would otherwise be found in production.

`seed:catalogue` reads the catalogue module the frontend already runs on, so a chapter is
corrected in one place (DEC-051, DEC-072). Run it after changing a chapter title, the semester
split or which chapter is free.

## Still open

- **The guardian-consent policy** (DEC-028). The columns are in `profiles` and the rule is
  enforced — no grant without a guardian contact and a consent timestamp — but the wording,
  the retention period and who may withdraw consent are not settled.
- **Law 09-08 / CNDP** (DEC-029). Blocks production, not development.

## Rules

- No React component lives here — the UI belongs in `../frontend/`.
- Every user-facing table has RLS enabled, with both `USING` and `WITH CHECK`, and ships with
  positive and negative tests.
- Constraints, indexes and RLS arrive in the same migration as the feature that needs them.
- Types are regenerated after every migration and never edited by hand.
- The service-role key is used only here, never in the frontend bundle.
- Never edit a migration that has been applied. Add another.

Full rules: `../context/domain-model.md`, `../context/security.md`,
`../context/roles-permissions.md`. The RLS reasoning and its test matrix: `policies/README.md`.
