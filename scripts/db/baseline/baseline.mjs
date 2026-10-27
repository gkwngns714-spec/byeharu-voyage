#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// baseline.mjs — the chain baseline: 0001..N folded into ONE file, and the lines that prove it
// (slice S1 of docs/CHAIN_BASELINE.md, 2026-10-27). DARK: nothing here is committed as a migration
// and nothing reads the file it writes except the proof job (.github/workflows/chain-baseline.yml).
//
// The baseline is the CHAIN'S state at N, not prod's: it is pg_dump of a database that applied
// 0001..N from zero on CI's disposable Supabase (D-chain), with four repairs a plain dump lacks,
// each one found by the digest, never assumed:
//   1. a PRELUDE: 0001's shims copied verbatim from 0001 itself (roles / auth.uid() / pgcrypto
//      when absent), pg_cron created when the platform has it (0012's guard), and the migration
//      role's OWN default privileges in the four schemas cleared. Supabase ships `postgres`
//      defaults in public that grant anon/authenticated/service_role everything; pg_dump writes
//      every object's ACL relative to acldefault(), so without the clearing every table the
//      baseline creates would be born writable by anon before the dump's own REVOKEs could know.
//   2. EXPLICIT owner-only ACLs re-issued (and multi-role policies' TO lists in the chain's order): pg_dump omits an ACL equal to acldefault(), so an
//      object whose ACL is explicitly the default would come back NULL (88 relations in the
//      design's trial). Same effective access, but the digest is exact, not normalised.
//   3. THE SCHEMA-LESS DEFAULT ACL (0018: "no new function is executable by PUBLIC"): a
//      --schema-filtered pg_dump never emits it (measured, CHAIN_BASELINE.md §4). It is rebuilt
//      here from D-chain's own pg_default_acl row, and the closing self-assert proves it by
//      BEHAVIOUR: a probe function created after it must not be executable by PUBLIC/anon/
//      authenticated (0018 §6(a)'s technique), with a positive control.
//   4. pg_cron's jobs: cron.job is not in a schema dump. Read from D-chain's cron.job (never
//      retyped) and re-scheduled in 0012's guarded shape, with each job's active flag as the chain
//      left it.
// and one closing self-assert with a "self-assert ok:" receipt (README §3).
//
// USAGE (every command reads/writes plain files; DB_URL is a postgres:// URL to a local database)
//   node scripts/db/baseline/baseline.mjs build   --db-url URL --container NAME --out FILE
//   node scripts/db/baseline/baseline.mjs lines   --db-url URL --out-dir DIR      (catalog, content, cron)
//   node scripts/db/baseline/baseline.mjs pglite  --baseline FILE --out-dir DIR   (load on PGlite + preamble, then lines)
//   node scripts/db/baseline/baseline.mjs compare A B [--allow FILE --section S]  (exit 1 on any difference or stale allow entry)
//   node scripts/db/baseline/baseline.mjs prod-lines --json FILE --out FILE       (prod's catalog, from `db query -o json`)
//   node scripts/db/baseline/baseline.mjs prod-compare CI_CATALOG PROD_CATALOG     (named platform normalisations only)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { contentLines } from '../prefix-cache.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = path.resolve(HERE, '..', '..', '..')
const MIGRATIONS_DIR = path.join(REPO_ROOT, 'supabase', 'migrations')
const CATALOG_SQL = path.join(HERE, 'catalog.sql')
const ACL_PROOF_SQL = path.join(HERE, 'default-acl-proof.sql')
const GAME_SCHEMAS = ['public', 'world', 'cmd', 'voyage']
// The search_path every catalog read runs under: prod's (`"$user", public, extensions`, read
// 2026-10-27) has the same visible schemas. Rendered definitions qualify names by it.
const CATALOG_SEARCH_PATH = 'public, extensions'

const sha256 = (s) => createHash('sha256').update(s).digest('hex')
const arg = (name, def) => {
  const i = process.argv.indexOf(name)
  return i === -1 ? def : process.argv[i + 1]
}
const need = (name) => {
  const v = arg(name)
  if (!v) throw new Error(`missing ${name}`)
  return v
}
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`

// ── a pg-like adapter over psql: query(sql) -> { rows }, every call its own session ─────────────
function psqlClient(url, searchPath) {
  return {
    async query(sql) {
      const wrapped = `select coalesce(json_agg(_bv_row), '[]'::json) from (${sql}) _bv_row`
      const out = execFileSync(
        'psql',
        [url, '-X', '-q', '-tA', '-v', 'ON_ERROR_STOP=1', '-c', `set search_path = ${searchPath}`, '-c', wrapped],
        { encoding: 'utf8', maxBuffer: 2 ** 30 },
      )
      return { rows: JSON.parse(out.trim() || '[]') }
    },
  }
}

// ── the lines ───────────────────────────────────────────────────────────────────────────────────
async function catalogLines(pg) {
  const sql = (await readFile(CATALOG_SQL, 'utf8')).replace(/;\s*$/, '')
  return (await pg.query(sql)).rows.map((r) => r.l)
}

const schemaOf = (qualified) => qualified.replace(/"/g, '').split('.')[0]

/**
 * contentLines() (scripts/db/prefix-cache.mjs, the digest the snapshot round trip already trusts)
 * scoped to the four game schemas. It must run with search_path = '' so every name it renders is
 * schema-qualified. Blocks, in its order: table rows + sequences, routines, relations, policies,
 * roles, default ACLs, namespaces, each closed by '--'. Roles are kept (`dropRoles` for PGlite,
 * whose roles are the preamble's model, not the platform's).
 */
function scopeContent(lines, { dropRoles = false } = {}) {
  const game = new Set(GAME_SCHEMAS)
  const out = []
  let block = 0
  for (const l of lines) {
    if (l === '--') {
      out.push(l)
      block += 1
      continue
    }
    const tok = l.split(' ')
    let keep
    if (block === 0) keep = game.has(schemaOf(tok[0] === 'T' ? tok[1] : tok[0]))
    else if (block === 4) keep = !dropRoles
    else if (block === 5) keep = tok[1] === '-' ? tok[0] === 'postgres' : game.has(tok[1])
    else keep = game.has(schemaOf(tok[0]))
    if (keep) out.push(l)
  }
  return out
}

async function cronLines(pg) {
  const has = (await pg.query(`select to_regclass('cron.job') is not null as x`)).rows[0].x
  if (!has) return ['(no pg_cron)']
  return (
    await pg.query(
      `select format('%s %s %s %s %s %s', jobname, schedule, md5(command), active, username, database) as l
         from cron.job order by jobname collate "C"`,
    )
  ).rows.map((r) => r.l)
}

async function writeLines(dir, name, lines) {
  await writeFile(path.join(dir, `${name}.txt`), lines.join('\n') + '\n')
  return sha256(lines.join('\n'))
}

async function allLines(pgFor, outDir, { dropRoles = false, cron = true } = {}) {
  await mkdir(outDir, { recursive: true })
  const digests = {}
  digests.catalog = await writeLines(outDir, 'catalog', await catalogLines(pgFor(CATALOG_SEARCH_PATH)))
  const bare = pgFor("''")
  digests.content_exact = await writeLines(outDir, 'content-exact', scopeContent(await contentLines(bare), { dropRoles }))
  const stable = scopeContent(await contentLines(bare, { stableOnly: true }), { dropRoles })
  digests.content_stable = await writeLines(outDir, 'content-stable', stable)
  // RUN-TO-RUN: two INDEPENDENT from-zero applies differ in uuids and clocks (stableOnly drops
  // those columns) and in ONE routine body, 0076's voyage.assert_paths_water, which embeds the
  // instant it applied (catalog.sql reads that literal as '<applied>'). So the digest two runs must
  // share is the catalog's plus this one: every table's stable rows and every sequence position.
  digests.rows_stable = sha256(stable.slice(0, stable.indexOf('--')).join('\n'))
  if (cron) digests.cron = await writeLines(outDir, 'cron', await cronLines(bare))
  await writeFile(path.join(outDir, 'digests.json'), JSON.stringify(digests, null, 2) + '\n')
  console.log(JSON.stringify(digests, null, 2))
  return digests
}

// ── the build ───────────────────────────────────────────────────────────────────────────────────
async function prelude() {
  // 0001's shims, VERBATIM from 0001: from its "Gap-filling shims" heading through the end of its
  // pgcrypto block. A changed 0001 (it is frozen) would fail here loudly rather than drift.
  const f = (await import('node:fs')).readdirSync(MIGRATIONS_DIR).filter((x) => /^\d{14}_.*\.sql$/.test(x)).sort()[0]
  const src = await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')
  const start = src.indexOf('-- ── 2. Gap-filling shims')
  const pgc = src.indexOf("execute 'create extension if not exists pgcrypto'")
  const end = pgc === -1 ? -1 : src.indexOf('end $$;', pgc)
  if (start === -1 || end === -1) throw new Error(`0001 (${f}) no longer has the shim section the baseline copies`)
  const shims = src.slice(start, end + 'end $$;'.length)
  return `-- ── PRELUDE 1: 0001's shims, copied verbatim from ${f} (no-ops on Supabase) ──
${shims}

-- ── PRELUDE 2: pg_cron where the platform has it (0012's guard); absent under PGlite ──
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron';
  else
    raise notice 'baseline: pg_cron is not available here (as under PGlite) — nothing will be scheduled';
  end if;
end $$;

-- ── PRELUDE 3: the migration role's OWN default privileges in the four schemas, cleared ──
-- pg_dump writes every object's ACL relative to acldefault(), so objects must be born with exactly
-- that. Supabase ships postgres-owned defaults in public granting anon/authenticated/service_role
-- everything; left in place they would be added to every table below before the dump's REVOKEs.
-- The chain's own final default ACLs are restored at the END, from the dump and from D-chain.
do $$
declare
  r record;
begin
  if exists (select 1 from pg_default_acl where defaclrole = current_user::regrole and defaclnamespace = 0) then
    raise exception 'baseline prelude: % already holds a schema-less default ACL on this target; the baseline does not know what that means — stop and look', current_user;
  end if;
  for r in
    select n.nspname, d.defaclobjtype as t
      from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
     where d.defaclrole = current_user::regrole
       and n.nspname in ('public', 'world', 'cmd', 'voyage')
  loop
    execute format('alter default privileges for role %I in schema %I revoke all on %s from public, anon, authenticated, service_role, %I',
                   current_user, r.nspname,
                   case r.t when 'r' then 'tables' when 'S' then 'sequences' when 'f' then 'functions' when 'T' then 'types' end,
                   current_user);
  end loop;
  if exists (select 1 from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
              where d.defaclrole = current_user::regrole and n.nspname in ('public', 'world', 'cmd', 'voyage')) then
    raise exception 'baseline prelude: the default privileges of % in the game schemas did not clear', current_user;
  end if;
end $$;
`
}

/** Objects whose ACL is EXPLICITLY the default: pg_dump omits them, so re-issue one owner grant. */
async function explicitDefaultAcls(pg) {
  const q = await pg.query(`
    select format('GRANT ALL ON %s %I.%I TO %I;', case when c.relkind = 'S' then 'SEQUENCE' else 'TABLE' end,
                  n.nspname, c.relname, pg_get_userbyid(c.relowner)) as l
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname in ('public','world','cmd','voyage') and c.relkind in ('r','p','v','m','f','S')
       and c.relacl is not null
       and c.relacl = acldefault(case when c.relkind = 'S' then 's' else 'r' end::"char", c.relowner)
    union all
    select format('GRANT EXECUTE ON %s %s TO %I;', case p.prokind when 'p' then 'PROCEDURE' else 'FUNCTION' end,
                  p.oid::regprocedure, pg_get_userbyid(p.proowner))
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public','world','cmd','voyage') and p.prokind in ('f','p','w')
       and p.proacl is not null and p.proacl = acldefault('f', p.proowner)
    union all
    select format('GRANT USAGE ON SCHEMA %I TO %I;', n.nspname, pg_get_userbyid(n.nspowner))
      from pg_namespace n
     where n.nspname in ('public','world','cmd','voyage') and n.nspacl is not null
       and n.nspacl = acldefault('n', n.nspowner)
    union all
    select format('GRANT USAGE ON TYPE %I.%I TO %I;', n.nspname, t.typname, pg_get_userbyid(t.typowner))
      from pg_type t join pg_namespace n on n.oid = t.typnamespace
     where n.nspname in ('public','world','cmd','voyage') and t.typacl is not null
       and t.typacl = acldefault('T', t.typowner)
    order by 1`)
  return q.rows.map((r) => r.l)
}

/** The migration role's SCHEMA-LESS default ACLs (0018), as statements, from D-chain's own row. */
async function schemalessDefaultAcls(pg) {
  const q = await pg.query(`
    with d as (
      select d.defaclobjtype as t, d.defaclacl as acl, d.defaclrole as owner
        from pg_default_acl d
       where d.defaclnamespace = 0 and d.defaclrole = current_user::regrole
    ),
    have as (select d.t, a.grantee, a.privilege_type from d, aclexplode(d.acl) a),
    base as (select d.t, a.grantee, a.privilege_type
               from d, aclexplode(acldefault(case d.t when 'S' then 's' else d.t end::"char", d.owner)) a),
    diff as (
      select 'REVOKE' as verb, t, grantee, privilege_type from base
       where (t, grantee, privilege_type) not in (select t, grantee, privilege_type from have)
      union all
      select 'GRANT', t, grantee, privilege_type from have
       where (t, grantee, privilege_type) not in (select t, grantee, privilege_type from base)
    )
    select format('ALTER DEFAULT PRIVILEGES FOR ROLE %I %s %s ON %s %s %s;', current_user, verb, privilege_type,
                  case t when 'r' then 'TABLES' when 'S' then 'SEQUENCES' when 'f' then 'FUNCTIONS'
                         when 'T' then 'TYPES' when 'n' then 'SCHEMAS' end,
                  case verb when 'GRANT' then 'TO' else 'FROM' end,
                  case when grantee = 0 then 'PUBLIC' else quote_ident(pg_get_userbyid(grantee)) end) as l
      from diff order by verb desc, t, grantee, privilege_type`)
  return q.rows.map((r) => r.l)
}

/**
 * Every policy naming more than one role, re-issued with its roles in the CHAIN'S order. pg_dump
 * writes a policy's TO list in pg_roles order, not in polroles' stored order (measured: 11 policies
 * the chain wrote "to anon, authenticated" came back "authenticated, anon"). Same meaning; the
 * exact digest (pg_policies.roles) is what notices, so the order is restored rather than ignored.
 */
async function policyRoleOrder(pg) {
  const q = await pg.query(`
    select format('ALTER POLICY %I ON %I.%I TO %s;', pol.polname, n.nspname, c.relname,
                  (select string_agg(case when u.r = 0 then 'PUBLIC' else quote_ident(pg_get_userbyid(u.r)) end, ', ' order by u.o)
                     from unnest(pol.polroles) with ordinality u(r, o))) as l
      from pg_policy pol join pg_class c on c.oid = pol.polrelid join pg_namespace n on n.oid = c.relnamespace
     where n.nspname in ('public','world','cmd','voyage') and cardinality(pol.polroles) > 1
     order by 1`)
  return q.rows.map((r) => r.l)
}

async function cronBlock(pg) {
  const has = (await pg.query(`select to_regclass('cron.job') is not null as x`)).rows[0].x
  if (!has) throw new Error('D-chain has no cron.job: the baseline must be built on a Supabase that has pg_cron')
  const jobs = (
    await pg.query(`select jobname, schedule, command, active from cron.job order by jobname collate "C"`)
  ).rows
  const sched = jobs.map((j) => `  perform cron.schedule(${lit(j.jobname)}, ${lit(j.schedule)}, ${lit(j.command)});`)
  const off = jobs
    .filter((j) => !j.active)
    .map((j) => `  perform cron.alter_job(job_id := (select jobid from cron.job where jobname = ${lit(j.jobname)}), active := false);`)
  return {
    count: jobs.length,
    sql: `-- ── pg_cron: the ${jobs.length} job(s) D-chain's cron.job held, as the chain left them (0012's guard) ──
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'baseline: pg_cron is not available here, so NOTHING was scheduled (0012''s posture under PGlite)';
    return;
  end if;
  perform cron.unschedule(jobname) from cron.job where jobname in (${jobs.map((j) => lit(j.jobname)).join(', ') || "''"});
${sched.join('\n')}
${off.join('\n')}
end $$;
`,
  }
}

async function rowManifest(pg) {
  const tables = (
    await pg.query(`
      select format('%I.%I', n.nspname, c.relname) as t
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public','world','cmd','voyage') and c.relkind in ('r','p') order by 1`)
  ).rows.map((r) => r.t)
  const out = []
  for (const t of tables) {
    const n = (await pg.query(`select count(*)::bigint::text as n from ${t}`)).rows[0].n
    out.push([t, n])
  }
  return out
}

function closingAssert(n, manifest, cronCount) {
  const rows = manifest.map(([t, c]) => `      (${lit(t)}, ${c}::bigint)`).join(',\n')
  return `-- ── THE CLOSING SELF-ASSERT ──
do $$
declare
  v_probe   regprocedure;
  v_bad     text;
  r         record;
  v_have    bigint;
  v_tables  int := 0;
  v_rows    bigint := 0;
begin
  -- (a) 0018 BY BEHAVIOUR: a function created now, after the schema-less default ACL above, must
  --     be executable by nobody but its owner — not PUBLIC, not anon, not authenticated.
  execute 'create function public._baseline_probe(p_x uuid) returns void language plpgsql '
       || 'security definer set search_path = public, pg_temp as $p$ begin '
       || 'raise exception ''baseline probe must never run''; end $p$';
  v_probe := 'public._baseline_probe(uuid)'::regprocedure;
  if has_function_privilege('anon', v_probe, 'execute')
     or has_function_privilege('authenticated', v_probe, 'execute')
     or exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 where p.oid = v_probe and a.grantee = 0) then
    raise exception 'baseline self-assert FAIL: a function created after the baseline is executable by a client or PUBLIC — 0018''s schema-less default ACL is missing';
  end if;
  -- positive control: grant it on purpose and require the same check to see it
  execute 'grant execute on function public._baseline_probe(uuid) to anon';
  if not has_function_privilege('anon', v_probe, 'execute') then
    raise exception 'baseline self-assert FAIL: the probe check cannot see a grant made on purpose';
  end if;
  execute 'drop function public._baseline_probe(uuid)';

  -- (b) the lockdown authorities, exactly as every migration calls them
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception 'baseline self-assert FAIL: client_write_grants() is not empty';
  end if;
  if (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception 'baseline self-assert FAIL: client_executable_writers() is not empty';
  end if;

  -- (c) every table holds exactly the rows the chain left at ${n}
  for r in select * from (values
${rows}
    ) m(t, n)
  loop
    execute format('select count(*) from %s', r.t) into v_have;
    if v_have <> r.n then
      v_bad := coalesce(v_bad || ', ', '') || format('%s %s<>%s', r.t, v_have, r.n);
    end if;
    v_tables := v_tables + 1;
    v_rows := v_rows + v_have;
  end loop;
  if v_bad is not null then
    raise exception 'baseline self-assert FAIL: row counts differ from the chain at ${n}: %', v_bad;
  end if;

  raise notice 'baseline ${n} self-assert ok: 0018 default ACL holds by behaviour (probe denied to PUBLIC/anon/authenticated, positive control seen), 0 client write grants, 0 client-executable writers, % tables / % rows equal the chain at ${n}, ${cronCount} cron job(s) defined', v_tables, v_rows;
end $$;
`
}

function cleanDump(sql) {
  const out = []
  let dropped = 0
  const foreign = []
  for (const line of sql.replace(/\r/g, '').split('\n')) {
    // psql meta-commands (pg_dump 17.6+ writes \restrict / \unrestrict): no non-psql loader takes them
    if (line.startsWith('\\')) {
      dropped += 1
      continue
    }
    // ANOTHER grantor's default privileges (Supabase's supabase_admin ships them in public): they
    // are the platform's, already on every target, and the migration role may not set them
    // (0001 §5b: "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin is refused outright").
    if (/^ALTER DEFAULT PRIVILEGES FOR ROLE /.test(line) && !/^ALTER DEFAULT PRIVILEGES FOR ROLE postgres /.test(line)) {
      foreign.push(line)
      continue
    }
    out.push(line.replace(/^CREATE SCHEMA ([a-z_]+);$/, 'CREATE SCHEMA IF NOT EXISTS $1;'))
  }
  return { sql: out.join('\n'), dropped, foreign }
}

async function build() {
  const url = need('--db-url')
  const container = need('--container')
  const outFile = need('--out')
  const pg = psqlClient(url, "''")
  const head = (
    await pg.query(`select max(version) as v, count(*)::int as c from supabase_migrations.schema_migrations`)
  ).rows[0]
  const n = String(head.v).slice(-4)
  const t0 = Date.now()
  const dump = execFileSync(
    'docker',
    ['exec', '-e', 'PGPASSWORD=postgres', container, 'pg_dump', '-h', '127.0.0.1', '-U', 'supabase_admin', '-d', 'postgres',
      ...GAME_SCHEMAS.flatMap((s) => ['--schema', s]), '--inserts', '--rows-per-insert=500'],
    { encoding: 'utf8', maxBuffer: 2 ** 31 },
  )
  const dumpMs = Date.now() - t0
  const pgDumpVersion = execFileSync('docker', ['exec', container, 'pg_dump', '--version'], { encoding: 'utf8' }).trim()
  const cleaned = cleanDump(dump)
  const fixes = await explicitDefaultAcls(pg)
  const policies = await policyRoleOrder(pg)
  const global = await schemalessDefaultAcls(pg)
  if (global.length === 0) throw new Error('D-chain holds no schema-less default ACL: 0018 is missing from the chain itself')
  const cron = await cronBlock(pg)
  const manifest = await rowManifest(pg)
  const digestsPath = arg('--chain-digests')
  const digests = digestsPath ? JSON.parse(await readFile(digestsPath, 'utf8')) : null

  const header = `-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- THE WORLD AS IT STOOD AT ${n} — the chain 0001..${n} folded into one file (docs/CHAIN_BASELINE.md)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Replaces: the ${head.c} migration files 0001..${n} (version ${head.v}). It is NOT a dump of prod: it is
-- the chain applied from zero on CI's disposable Supabase, then pg_dump (${pgDumpVersion}) of the four
-- game schemas, with the repairs scripts/db/baseline/baseline.mjs names (prelude, explicit default
-- ACLs, 0018's schema-less default ACL, pg_cron's jobs) and one closing self-assert.
-- Built by .github/workflows/chain-baseline.yml${process.env.GITHUB_RUN_ID ? `, run ${process.env.GITHUB_RUN_ID}` : ''}${process.env.GITHUB_SHA ? `, commit ${process.env.GITHUB_SHA}` : ''}.
-- D-chain digests (scripts/db/baseline/baseline.mjs lines):
${digests ? Object.entries(digests).map(([k, v]) => `--   ${k.padEnd(15)} ${v}`).join('\n') : '--   (not given)'}
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
`
  const body = [
    header,
    await prelude(),
    '-- ── THE DUMP (pg_dump --schema public/world/cmd/voyage --inserts --rows-per-insert=500) ──',
    cleaned.sql,
    `-- ── EXPLICIT DEFAULT ACLs pg_dump omits (${fixes.length}) ──`,
    ...fixes,
    '',
    `-- ── POLICY ROLE LISTS in the chain's order (${policies.length}) ──`,
    ...policies,
    '',
    `-- ── 0018: the migration role's schema-less default ACL, from D-chain's pg_default_acl (${global.length} statement(s)) ──`,
    '-- the dump set search_path to empty and client_min_messages to warning; the receipt below must be heard',
    'RESET search_path;',
    'RESET client_min_messages;',
    ...global,
    '',
    cron.sql,
    closingAssert(n, manifest, cron.count),
  ].join('\n')
  await writeFile(outFile, body.endsWith('\n') ? body : body + '\n')
  const stats = {
    n,
    version: head.v,
    files: head.c,
    pg_dump: pgDumpVersion,
    dump_seconds: +(dumpMs / 1000).toFixed(1),
    dump_bytes: Buffer.byteLength(dump),
    baseline_bytes: Buffer.byteLength(body),
    baseline_sha256: sha256(body),
    meta_lines_dropped: cleaned.dropped,
    foreign_default_acls_dropped: cleaned.foreign,
    explicit_default_acls: fixes.length,
    policy_role_orders: policies.length,
    schemaless_default_acl: global,
    cron_jobs: cron.count,
    tables: manifest.length,
    rows: manifest.reduce((s, [, c]) => s + Number(c), 0),
  }
  console.log(JSON.stringify(stats, null, 2))
  const statsOut = arg('--stats')
  if (statsOut) await writeFile(statsOut, JSON.stringify(stats, null, 2) + '\n')
}

async function lines() {
  const url = need('--db-url')
  await allLines((sp) => psqlClient(url, sp), need('--out-dir'))
}

async function pglite() {
  const { PGlite } = await import('@electric-sql/pglite')
  const { applyPreamble } = await import('../apply-chain.mjs')
  const file = need('--baseline')
  const outDir = need('--out-dir')
  await mkdir(outDir, { recursive: true })
  const db = await new PGlite(process.env.BV_CHAIN_DATA_DIR || undefined)
  await applyPreamble(db)
  const sql = await readFile(file, 'utf8')
  const notices = []
  const t0 = Date.now()
  await db.exec(sql, { onNotice: (m) => notices.push(m.message ?? String(m)) })
  const loadMs = Date.now() - t0
  const receipt = notices.find((m) => /self-assert ok:/.test(m))
  console.log(`PGlite load: ${(loadMs / 1000).toFixed(1)} s; ${notices.length} notice(s)`)
  for (const m of notices) console.log(`  notice: ${m}`)
  if (!receipt) throw new Error('the baseline printed no "self-assert ok:" receipt on PGlite')
  // the 0018 proof, the same file the Supabase leg runs through psql (rolled back)
  const proof = await readFile(ACL_PROOF_SQL, 'utf8')
  const proofNotices = []
  await db.exec(`begin;\n${proof}\nrollback;`, { onNotice: (m) => proofNotices.push(m.message ?? String(m)) })
  for (const m of proofNotices) console.log(`  proof: ${m}`)
  if (!proofNotices.some((m) => /PASS: BASELINE_DEFAULT_ACL_HOLDS/.test(m)) || !proofNotices.some((m) => /PASS: BASELINE_DEFAULT_ACL_CONTROL/.test(m))) {
    throw new Error('the default-ACL proof did not print both PASS markers on PGlite')
  }
  const adapter = (sp) => ({
    async query(q) {
      await db.exec(`set search_path = ${sp}`)
      return db.query(q)
    },
  })
  await allLines(adapter, outDir, { dropRoles: true, cron: false })
  await writeFile(path.join(outDir, 'load.json'), JSON.stringify({ load_seconds: +(loadMs / 1000).toFixed(1) }) + '\n')
}

async function compare() {
  const [a, b] = process.argv.slice(3, 5)
  const allowFile = arg('--allow')
  const allow = allowFile
    ? (await readFile(allowFile, 'utf8'))
        .split('\n')
        .filter((l) => l && !l.startsWith('#'))
        .map((l) => /^([a-z-]+): (.*)$/.exec(l))
        .filter((m) => m && m[1] === need('--section'))
        .map((m) => new RegExp(m[2]))
    : []
  const A = (await readFile(a, 'utf8')).split('\n').filter(Boolean)
  const B = (await readFile(b, 'utf8')).split('\n').filter(Boolean)
  const setB = new Set(B)
  const setA = new Set(A)
  const onlyA = A.filter((l) => !setB.has(l))
  const onlyB = B.filter((l) => !setA.has(l))
  const allowed = (l) => allow.some((re) => re.test(l))
  const badA = onlyA.filter((l) => !allowed(l))
  const badB = onlyB.filter((l) => !allowed(l))
  console.log(`compare ${a} (${A.length}) vs ${b} (${B.length}): ${onlyA.length} only in A, ${onlyB.length} only in B, ${onlyA.length + onlyB.length - badA.length - badB.length} allowed`)
  for (const l of onlyA) console.log(`${allowed(l) ? '  (allowed) ' : ''}< ${l}`)
  for (const l of onlyB) console.log(`${allowed(l) ? '  (allowed) ' : ''}> ${l}`)
  // an allow-list entry that matches nothing is stale: it must not quietly grow into a blanket
  const unused = allow.filter((re) => ![...onlyA, ...onlyB].some((l) => re.test(l)))
  for (const re of unused) console.log(`UNUSED allow entry (stale — remove it): ${re}`)
  if (badA.length || badB.length || unused.length) process.exit(1)
  console.log('EQUAL (beyond the allow-list)')
}

/**
 * Prod's catalog vs a CI database's, with the platform's differences NAMED and COUNTED rather than
 * allow-listed line by line (measured 2026-10-27, prod vs the chain at 0248):
 *   1. service_role's grants in public: prod's stock postgres default privileges give service_role
 *      everything (D postgres public r = arwdDxtm), a fresh CLI 2.114 Supabase gives it Dxtm/w/none;
 *      the chain never names service_role in those statements, so every object differs by it.
 *   2. a routine ACL written out as exactly acldefault() ({=X/owner,owner=X/owner}) equals NULL.
 * Everything else must be byte-equal.
 */
async function prodCompare() {
  const [a, b] = process.argv.slice(3, 5)
  const counts = { service_role_items: 0, explicit_default_routine_acl: 0 }
  const norm = (l) => {
    let x = l.replace(/,?service_role=[A-Za-z*]*\/postgres/g, () => {
      counts.service_role_items += 1
      return ''
    })
    x = x.replace(/\{,/g, '{')
    if (/^F /.test(x) && / \{=X\/postgres,postgres=X\/postgres\} postgres /.test(x)) {
      counts.explicit_default_routine_acl += 1
      x = x.replace(/ \{=X\/postgres,postgres=X\/postgres\} postgres /, ' - postgres ')
    }
    return x
  }
  const A = (await readFile(a, 'utf8')).split('\n').filter(Boolean)
  const B = (await readFile(b, 'utf8')).split('\n').filter(Boolean)
  const rawA = new Set(A)
  const rawB = new Set(B)
  const rawOnly = A.filter((l) => !rawB.has(l)).length + B.filter((l) => !rawA.has(l)).length
  const nA = A.map(norm)
  const nB = B.map(norm)
  const sA = new Set(nA)
  const sB = new Set(nB)
  const onlyA = nA.filter((l) => !sB.has(l))
  const onlyB = nB.filter((l) => !sA.has(l))
  console.log(`prod compare ${a} (${A.length}) vs ${b} (${B.length}): ${rawOnly} raw differing line(s); normalised: ${JSON.stringify(counts)}`)
  for (const l of onlyA) console.log(`< ${l}`)
  for (const l of onlyB) console.log(`> ${l}`)
  if (onlyA.length || onlyB.length) process.exit(1)
  console.log('EQUAL after the two named platform normalisations')
}

async function prodLines() {
  const j = JSON.parse(await readFile(need('--json'), 'utf8'))
  const rows = (j.rows ?? j).map((r) => r.l)
  await writeFile(need('--out'), rows.join('\n') + '\n')
  console.log(`${rows.length} prod catalog line(s), sha256 ${sha256(rows.join('\n'))}`)
}

const cmd = process.argv[2]
const commands = { build, lines, pglite, compare, 'prod-lines': prodLines, 'prod-compare': prodCompare }
if (!commands[cmd]) {
  console.error(`usage: baseline.mjs ${Object.keys(commands).join('|')} ...`)
  process.exit(2)
}
await commands[cmd]()
