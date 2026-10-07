/**
 * Writes `0002_catalogue.sql` from the catalogue module the frontend already runs on.
 *
 * DEC-051 said it in as many words: when the Supabase catalogue lands, `programme.ts` is the
 * seed, not a fixture to throw away. So the 79 chapters of the real syllabus, their three
 * locales, the semester each falls in and the one free chapter per subject are not retyped
 * here — they are read from `frontend/lib/demo-data/catalogue.ts`, which is also what decides
 * the semester split (`firstSemesterChapters`) and which chapter is free (DEC-034). One place
 * to correct a chapter, one place to move the January break.
 *
 * Run it after changing the catalogue module:
 *
 *     node backend/seed/generate-catalogue.mjs
 *
 * It reads TypeScript directly: Node strips the types, and the resolve hook below adds the
 * `.ts` extension that TypeScript's own import style leaves off. Nothing is compiled and no
 * build artefact is left behind.
 *
 * This script is a data generator, not application code. It writes SQL and imports no React,
 * which is what keeps it on the right side of the `frontend/` — `backend/` boundary (DEC-031).
 */
import { register } from 'node:module'
import { writeFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

register(
  'data:text/javascript,export async function resolve(s,c,n){try{return await n(s,c)}catch(e){if(s.startsWith(".")&&!s.endsWith(".ts"))return await n(s+".ts",c);throw e}}',
)

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..')
const source = pathToFileURL(join(root, 'frontend', 'lib', 'demo-data', 'catalogue.ts')).href

const { tracks, subjects, lessons, packs } = await import(source)

/** Postgres string literal. Doubles the quote and nothing else — no interpolation anywhere. */
const q = (value) => `'${String(value).replaceAll("'", "''")}'`

const lines = []
const say = (line = '') => lines.push(line)

say('-- 0002_catalogue.sql — GENERATED, do not edit by hand.')
say('--')
say('-- Written by backend/seed/generate-catalogue.mjs from')
say('-- frontend/lib/demo-data/catalogue.ts, which reads the real syllabus in')
say('-- programme.ts (DEC-051). Correct a chapter there and run the generator again.')
say('--')
say('-- Idempotent: every statement is an upsert on a natural key. Run it after')
say('-- 0001_reference.sql.')
say('--')
say('-- Order matters in one place. A subject cannot be published without a free first')
say('-- chapter (DEC-034) and the database refuses it, so the nine subjects go in')
say('-- unpublished, the chapters follow, and the last statement publishes them.')
say()

say('-- Streams. Names live in the three message catalogues, keyed by slug: there are three')
say('-- of them, they are a closed set for the MVP, and one copy is enough.')
say('insert into public.tracks (slug, level, filiere, position, published) values')
say(
  tracks
    .map(
      (track) =>
        `  (${q(track.slug)}, ${q(track.level)}::app.level, ` +
        `${track.filiere === null ? 'null' : `${q(track.filiere)}::app.filiere`}, ` +
        `${track.order}, ${track.published})`,
    )
    .join(',\n'),
)
say('on conflict (slug) do update')
say('  set level = excluded.level,')
say('      filiere = excluded.filiere,')
say('      position = excluded.position,')
say('      published = excluded.published;')
say()

say('-- The same three subjects run in every stream (DEC-030).')
say('insert into public.subjects (slug, position) values')
say(subjects.map((subject) => `  (${q(subject.slug)}, ${subject.order})`).join(',\n'))
say('on conflict (slug) do update set position = excluded.position;')
say()

say('-- Nine teaching units. Left unpublished here on purpose; the last statement of this')
say('-- file publishes them, once their chapters exist.')
say('insert into public.track_subjects (track_id, subject_id, modality, published)')
say('select t.id, s.id, \'hybrid\'::app.modality, false')
say('from public.tracks t cross join public.subjects s')
say('on conflict (track_id, subject_id) do nothing;')
say()

say('-- The offer (DEC-030, DEC-036, DEC-049). Amounts are placeholders and every screen that')
say('-- shows one carries the demonstration warning until the real prices arrive (F5) —')
say('-- `is_demo_price` is what makes that warning truthful rather than decorative.')
say('insert into public.packs (slug, subject_count, price_minor, currency, billing, is_demo_price, published, position) values')
say(
  packs
    .map(
      (pack, index) =>
        `  (${q(pack.id)}, ${pack.subjectCount}, ${pack.priceMinor}, ${q(pack.currency)}, ` +
        `${q(pack.billing)}, ${pack.isDemoPrice}, true, ${index + 1})`,
    )
    .join(',\n'),
)
say('on conflict (slug) do update')
say('  set subject_count = excluded.subject_count,')
say('      price_minor = excluded.price_minor,')
say('      currency = excluded.currency,')
say('      is_demo_price = excluded.is_demo_price,')
say('      published = excluded.published,')
say('      position = excluded.position;')
say()

const s1 = lessons.filter((lesson) => lesson.semester === 's1').length
const free = lessons.filter((lesson) => lesson.isFreePreview).length
say(`-- ${lessons.length} chapters of the official syllabus: ${s1} in the first semester,`)
say(`-- ${lessons.length - s1} in the second, ${free} free first chapters — one per subject, which is`)
say('-- the promise the catalogue makes on every card (DEC-034).')
say('insert into public.lessons (')
say('  track_subject_id, position, slug,')
say('  title_fr, title_ar, title_en,')
say('  summary_fr, summary_ar, summary_en,')
say('  semester, is_free_preview, published')
say(')')
say('select')
say('  ts.id, v.ordinal_position, v.slug,')
say('  v.title_fr, v.title_ar, v.title_en,')
say('  v.summary_fr, v.summary_ar, v.summary_en,')
say('  v.semester::app.semester, v.is_free_preview, true')
say('from (values')
say(
  lessons
    .map(
      (lesson) =>
        `  (${q(lesson.track)}, ${q(lesson.subject)}, ${lesson.order}, ${q(lesson.slug)}, ` +
        `${q(lesson.title.fr)}, ${q(lesson.title.ar)}, ${q(lesson.title.en)}, ` +
        `${q(lesson.summary.fr)}, ${q(lesson.summary.ar)}, ${q(lesson.summary.en)}, ` +
        `${q(lesson.semester)}, ${lesson.isFreePreview})`,
    )
    .join(',\n'),
)
say(') as v (')
say('  track_slug, subject_slug, ordinal_position, slug,')
say('  title_fr, title_ar, title_en,')
say('  summary_fr, summary_ar, summary_en,')
say('  semester, is_free_preview')
say(')')
say('join public.tracks t on t.slug = v.track_slug')
say('join public.subjects s on s.slug = v.subject_slug')
say('join public.track_subjects ts on ts.track_id = t.id and ts.subject_id = s.id')
say('on conflict (track_subject_id, slug) do update')
say('  set position = excluded.position,')
say('      title_fr = excluded.title_fr,')
say('      title_ar = excluded.title_ar,')
say('      title_en = excluded.title_en,')
say('      summary_fr = excluded.summary_fr,')
say('      summary_ar = excluded.summary_ar,')
say('      summary_en = excluded.summary_en,')
say('      semester = excluded.semester,')
say('      is_free_preview = excluded.is_free_preview,')
say('      published = excluded.published;')
say()

say('-- Now that every subject has its free first chapter, the trigger will let them through.')
say('update public.track_subjects set published = true where not published;')
say()

const out = join(here, '0002_catalogue.sql')
writeFileSync(out, `${lines.join('\n')}`, 'utf8')
console.log(
  `wrote 0002_catalogue.sql — ${tracks.length} streams, ${subjects.length} subjects, ` +
    `${lessons.length} chapters (${free} free), ${packs.length} packs`,
)
