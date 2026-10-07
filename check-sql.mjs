/**
 * `npm run check:sql` — parses every migration and seed with the real PostgreSQL 17 grammar
 * (libpg-query, the parser Postgres itself uses, compiled to WebAssembly), then runs this
 * project's own structural rules over the statements it gets back:
 *
 *   - every table created in `public` enables row level security;
 *   - every insert / update / all policy has a WITH CHECK, and every read policy a USING
 *     (`security.md` section 4 requires both halves);
 *   - every `security definer` function pins its `search_path`, so a caller cannot plant a
 *     table in front of ours.
 *
 * It is not a substitute for applying the migrations, and it never touches a database. What
 * it catches is the class of mistake that would otherwise be found in production: a typo in
 * a policy nobody exercises, a table whose RLS was never switched on, an update rule that
 * writes anything because its WITH CHECK is missing.
 *
 * A table printed as "NO POLICY (deny all)" is deliberate for `streams` and `resource_media`
 * (DEC-070) and a bug anywhere else.
 */
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as pg from 'libpg-query'

const api = pg.default ?? pg
const root = dirname(fileURLToPath(import.meta.url))

const dirs = ['supabase/migrations', 'seed']
const files = dirs.flatMap((dir) =>
  readdirSync(join(root, dir))
    .filter((name) => name.endsWith('.sql'))
    .sort()
    .map((name) => ({ dir, name, path: join(root, dir, name) })),
)

const problems = []
const tables = new Map() // name -> { rls: false, policies: [], grants: [] }
// Supabase owns these; we only attach policies to them.
const provided = new Set(['storage.objects', 'auth.users'])
let statements = 0

function note(file, message) {
  problems.push(`${file}: ${message}`)
}

function relName(rel) {
  if (!rel) return null
  return `${rel.schemaname ?? 'public'}.${rel.relname}`
}

for (const file of files) {
  const sql = readFileSync(file.path, 'utf8')
  let parsed
  try {
    parsed = await api.parse(sql)
  } catch (error) {
    note(file.name, `parse error — ${error.message}`)
    continue
  }

  for (const raw of parsed.stmts ?? []) {
    statements += 1
    const stmt = raw.stmt ?? {}
    const [kind] = Object.keys(stmt)
    const node = stmt[kind]

    if (kind === 'CreateStmt') {
      const name = relName(node.relation)
      if (name?.startsWith('public.')) {
        tables.set(name, { rls: false, policies: [], file: file.name })
      }
    }

    if (kind === 'AlterTableStmt') {
      const name = relName(node.relation)
      for (const cmd of node.cmds ?? []) {
        if (cmd.AlterTableCmd?.subtype === 'AT_EnableRowSecurity') {
          const entry = tables.get(name)
          if (entry) entry.rls = true
          else note(file.name, `enables RLS on unknown table ${name}`)
        }
      }
    }

    if (kind === 'CreatePolicyStmt') {
      const name = relName(node.table)
      const entry = tables.get(name)
      const policy = {
        name: node.policy_name,
        cmd: node.cmd_name,
        hasUsing: Boolean(node.qual),
        hasCheck: Boolean(node.with_check),
        file: file.name,
      }
      if (entry) entry.policies.push(policy)
      else if (!provided.has(name)) note(file.name, `policy ${node.policy_name} on unknown table ${name}`)

      // security.md section 4: every user-facing table has RLS with both USING and
      // WITH CHECK. A policy that writes rows and has no WITH CHECK writes anything.
      if (['insert', 'update', 'all'].includes(policy.cmd) && !policy.hasCheck) {
        note(file.name, `policy ${policy.name} (${policy.cmd}) has no WITH CHECK`)
      }
      if (['select', 'update', 'delete', 'all'].includes(policy.cmd) && !policy.hasUsing) {
        note(file.name, `policy ${policy.name} (${policy.cmd}) has no USING`)
      }
    }

    // A security definer function that does not pin its search_path can be made to read a
    // table the caller planted in front of ours.
    if (kind === 'CreateFunctionStmt') {
      const fname = (node.funcname ?? []).map((part) => part.String?.sval).join('.')
      const options = Object.fromEntries(
        (node.options ?? []).map((opt) => [opt.DefElem?.defname, opt.DefElem]),
      )
      const definer = 'security' in options && options.security?.arg?.Boolean?.boolval === true
      const setsPath = (node.options ?? []).some(
        (opt) => opt.DefElem?.defname === 'set' && opt.DefElem?.arg?.VariableSetStmt?.name === 'search_path',
      )
      if (definer && !setsPath) note(file.name, `security definer ${fname} does not set search_path`)
    }
  }
}

// Every table this project creates in `public` is user-facing.
for (const [name, entry] of tables) {
  if (!entry.rls) problems.push(`${entry.file}: table ${name} never enables row level security`)
}

console.log(`parsed ${files.length} files, ${statements} statements, ${tables.size} public tables`)
for (const [name, entry] of tables) {
  const cmds = entry.policies.map((p) => p.cmd).join(', ') || 'NO POLICY (deny all)'
  console.log(`  ${name.padEnd(34)} rls=${entry.rls ? 'on ' : 'OFF'}  ${cmds}`)
}

if (problems.length) {
  console.log(`\n${problems.length} problem(s):`)
  for (const problem of problems) console.log(`  - ${problem}`)
  process.exit(1)
}
console.log('\nall checks pass')
