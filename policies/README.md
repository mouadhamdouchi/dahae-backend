# Row Level Security

## Where the policies live

The executable `create policy` statements are in `../supabase/migrations/`, beside the tables they
protect. That is deliberate and it follows the rule in `../README.md`: *constraints, indexes and
RLS arrive in the same migration as the feature that needs them.* A policy that lived in a
second folder would be a policy somebody could forget to apply.

This folder holds the reasoning and the test matrix — the two things a `create policy` statement
cannot say for itself.

## The four questions

Every policy in this database is built out of four `security definer` helpers, and almost
nothing else. If you are adding a policy, ask which of these you mean before writing a subquery.

| Helper | Question | Answers for the super admin |
| --- | --- | --- |
| `app.is_super_admin()` | Is this the owner? | yes |
| `app.teaches(track_subject)` | Is this subject in the caller's scope? | yes, always |
| `app.entitled(subject, semester)` | Has the caller ever paid for this half-year? | — |
| `app.entitled_now(subject, semester)` | Is that access still running? | — |

Two of those rows carry a rule from the decision log:

- `app.teaches` answers **yes** for the super admin without an assignment row. The super admin
  can do everything a teacher can do (`roles-permissions.md`), and this is where that is true in
  the database — the same rule `frontend/lib/auth/capabilities.ts` enforces in the application,
  by spreading the teacher bundle into the owner bundle rather than writing a second list.
- `entitled` and `entitled_now` are **not** interchangeable (DEC-062). `entitled` includes a
  grant that has ended, because a family that paid for the first semester keeps the first
  semester. `entitled_now` is what gates joining a live that is happening. Using the first where
  the second belongs lets a lapsed learner into today's class; using the second where the first
  belongs deletes a semester somebody paid for.

## Why every helper is `security definer`

A policy on `user_roles` that reads `user_roles` sends Postgres back through the same policy,
which sends it back again. `security definer` runs the function as its owner and skips RLS,
which breaks the loop.

That makes these the most dangerous functions in the database, so all of them:

- live in the `app` schema, which is on nobody's search path;
- declare `set search_path = ''` and fully qualify every name, so a caller cannot plant a table
  in front of ours;
- answer exactly one closed question and return a boolean or a scalar;
- are granted `execute` one at a time, never by wildcard.

## The three tables you cannot select from

`resource_media`, `streams` and `audit_events` are the exceptions to "a table has policies".

| Table | Grants | Policies | How anything gets out |
| --- | --- | --- | --- |
| `resource_media` | none | none | `app.resource_media(resource)` |
| `streams` | none | none | `app.live_ingest`, `app.live_playback`, `app.recording_playback` |
| `audit_events` | `select` | `select` for the owner only | written only by `app.record_audit` |

**"No grant" is not the default; it has to be taken back.** A Supabase project ships
`alter default privileges in schema public grant all on tables to anon, authenticated`, so
these tables were created holding every privilege for both roles until migration
`20260829120000` revoked them (DEC-077). Until that migration they were protected by RLS
alone — one lock where this table promises two. If you add a table and do not write its
grants, you are back to the same place, and `npm run check:sql` will not catch it: it reads
the migrations, not the database.

This is DEC-066 expressed as structure rather than as discipline. A playback address is handed
out per request after the grant is checked; a stream key reaches the person who opened the live
and nobody else — not the other teacher on the subject, not the super admin. Because the tables
carry no grant, there is no query a client can write that returns one of these values, whatever
the application layer does.

`audit_events` is the same idea pointed the other way: the super admin may read it, nobody may
write it directly, and a `before update or delete` trigger refuses an edit from **anyone** — the
service role and the table owner included. The log's job is to record a role with no second
administrator watching it, so it cannot be edited by the person it records.

## The free-lesson exception

`resources_read_free_preview` is written as its own policy and must stay that way. It is not a
loosened version of `resources_read_entitled`; it is a different rule with a different reason
(DEC-034), and merging the two is how a narrow exception quietly becomes a wide one.

The same shape appears in `lesson_progress`: a learner may record progress against a chapter
they are entitled to *or* the free first one, and nothing else.

## Test matrix

Partly executed. The **anonymous** column of every case below has been run against the live
project with the publishable key, and it is what caught DEC-077. Everything that needs a
signed-in session — a student with a grant, a teacher with a scope, the super admin — is still
unrun, because it needs real accounts. FND-07 is not complete until the whole matrix runs
green.

Roles under test: anonymous, `student-none` (signed in, no grant), `student-s1` (grant on
Comptabilité, S1, running), `student-past` (grant on Comptabilité, S2 of last year, ended),
`student-revoked`, `teacher-compta` (assigned Comptabilité in 1ère Bac only), `super_admin`.

### Catalogue

| Case | Expected |
| --- | --- |
| anonymous reads a published chapter title | allowed |
| anonymous reads an unpublished chapter | denied |
| anonymous reads a chapter of an unpublished stream | denied |
| `teacher-compta` reads their own unpublished draft | allowed |
| `teacher-compta` reads a draft of Économie générale | denied |
| `teacher-compta` inserts a chapter with `published = true` | denied |
| `teacher-compta` inserts a chapter with `published = false` | allowed |
| `teacher-compta` flips their own draft to published | denied |
| `super_admin` publishes it | allowed |
| `teacher-compta` deletes a chapter | denied |
| publishing a `track_subject` with no free chapter | denied by trigger |
| a second `is_free_preview` on one subject | denied by unique index |

### Resources and material

| Case | Expected |
| --- | --- |
| anonymous reads any resource row | denied |
| anonymous reads `lesson_resource_kinds` for a published chapter | allowed |
| `student-none` reads a resource of the free first chapter | allowed |
| `student-none` reads a resource of chapter 2 | denied |
| `student-s1` reads a resource of an S1 chapter of Comptabilité | allowed |
| `student-s1` reads a resource of an S2 chapter | denied |
| `student-s1` reads a resource of Économie générale | denied |
| `student-past` reads an S2 chapter of Comptabilité | allowed (DEC-062) |
| `student-revoked` reads the same chapter | denied |
| any client selects from `resource_media` | denied (no grant) |
| `app.resource_media` called by an entitled learner | returns one row |
| `app.resource_media` called by a learner with no grant | raises |

### Access, payments, people

| Case | Expected |
| --- | --- |
| `student-s1` reads their own grant | allowed |
| `student-s1` reads another learner's grant | denied |
| `teacher-compta` reads the grant of a learner on their subject | allowed |
| `teacher-compta` reads any payment | denied |
| `teacher-compta` inserts a grant | denied |
| `super_admin` inserts a grant with `granted_by` set to somebody else | denied |
| a grant for a learner with no guardian consent on file | denied by trigger |
| a grant whose subject belongs to another stream | denied by composite FK |
| a second grant for the same learner and term | denied by unique |
| `teacher-compta` inserts a row in `user_roles` | denied |
| `super_admin` inserts a `super_admin` row from a session | denied by trigger |
| deleting the last `super_admin` row | denied by trigger |

### Timetable, lives, recordings

| Case | Expected |
| --- | --- |
| anonymous reads a published séance | allowed |
| anonymous reads a proposal | denied |
| `teacher-compta` proposes a séance on their subject | allowed, `published = false` |
| `teacher-compta` proposes one with `published = true` | denied |
| `teacher-compta` publishes their own proposal | denied |
| two séances overlapping in the same stream | denied by exclusion constraint |
| opening a live on an unpublished séance | denied by trigger |
| `app.live_ingest` called by the teacher who opened it | returns the key |
| `app.live_ingest` called by the super admin | returns nothing |
| `student-s1` reads a live on their subject while it runs | allowed |
| `student-past` reads that live | denied |
| `student-past` reads a recording of the semester they paid for | allowed |
| `teacher-compta` deletes a recording | denied |
| `super_admin` deletes a recording | allowed |

### Audit

| Case | Expected |
| --- | --- |
| `super_admin` reads the trail | allowed |
| `teacher-compta` reads the trail | denied |
| any role inserts into `audit_events` directly | denied |
| `app.record_audit` called by a student | raises |
| `update` on an audit row, as the table owner | raises |
| a metadata object containing `stream_key` | denied by check constraint |

### Storage

| Case | Expected |
| --- | --- |
| anonymous lists `learning-resources` | denied |
| `student-s1` reads an object under an entitled chapter | allowed |
| `student-s1` reads an object under a chapter they have not bought | denied |
| `student-none` reads an object under the free first chapter | allowed |
| `teacher-compta` uploads under their own subject | allowed |
| `teacher-compta` uploads under another subject | denied |
| `teacher-compta` deletes an object | denied |
