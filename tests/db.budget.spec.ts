// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DATABASE BUDGET — a new migration may not quietly spend the disk (docs/DATABASE_BUDGET.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-15: "for the supabase issue before, make procedures so that this mistake does not happen again".
// On 2026-11-14 production was IO-bound for ~2.5 hours (docs/dev-log/2026-11-15-db-guard.md). Three of its causes were written
// into migrations and sat there for weeks: fixed tiny autovacuum thresholds with scale factor 0 (0224, 0226, 0275, 0291, 0297:
// ~3,000 whole-heap passes a day), tables created with no retention (city_wants kept 993 periods and read 2), and a job that
// rewrote a whole table every minute (the drift on port_goods at fillfactor 30). This spec is those three lessons with teeth.
//
// THE RULES, for every migration NEWER than the frozen head (FROZEN_HEAD below; older files are history and never edited):
//   a. AUTOVACUUM   an option list that sets autovacuum_vacuum_threshold / autovacuum_analyze_threshold below
//                   AUTOVACUUM_THRESHOLD_FLOOR (or to a value this reader cannot see, like a format() %s) together with the
//                   matching scale factor 0, or that sets autovacuum_enabled off.
//   b. RETENTION    every CREATE TABLE (not TEMP) carries a `-- retention: <rule or knob name>` or
//                   `-- retention: none, bounded by <why>` line: next to it (in its statement, or the comment block above it),
//                   or anywhere in the file naming the table.
//   c. CRON         every cron.schedule( / cron.schedule_in_database( / cron.alter_job( and every `update cron.job … schedule`
//                   carries a `-- budget:` line next to it that states its expected rows touched per run (a number and the word
//                   "row"). This covers a new job, a reschedule, and a job more often than once a minute ('N seconds').
//   d. FILLFACTOR   a fillfactor below FILLFACTOR_FLOOR carries a `-- budget:` line next to it.
// "NEXT TO IT" = between the end of the previous statement (the last `;` before it) and the end of its own statement, so the
// comment block directly above a statement counts, and so does a line inside it. A `-- budget:` reason must say something:
// at least MIN_REASON characters.
//
// HOW A FILE IS READ. Comments are blanked (same length, so positions hold) by a small scanner that knows single-quoted and E''
// strings, so a `--` inside a string is not a comment; dollar-quoted bodies are read as code (a cron.schedule inside a `do`
// block counts). String literals are NOT blanked: a cron.schedule built with execute format(...) is still seen. A hunk that
// quotes an old body holding one of these words is flagged too: give it a `-- budget:` / `-- retention:` line saying so.
//
// PURE SPEC. No `page`, no database: it reads files. CI runs it in `build` (a required check) and in Acceptance's db shard.

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'

// ── THE FLOORS (docs/DATABASE_BUDGET.md, "Rules for a migration") ─────────────────────────────────────────────────────
/** The newest migration that is history. Files after it are judged. */
const FROZEN_HEAD = 418
/** A fixed autovacuum threshold below this, with scale factor 0, is a pass every few minutes on a busy table. 0412 put the
 *  smallest churn table (city_wants) at 20,000; 0291 had put standing_route_laps at 500. */
const AUTOVACUUM_THRESHOLD_FLOOR = 20_000
/** Below this a table is mostly air: port_goods at 30 was 113 MB of heap for ~27 MB of rows. */
const FILLFACTOR_FLOOR = 50
/** A `-- budget:` reason shorter than this is not a reason. */
const MIN_REASON = 10

const DIR = path.resolve('supabase', 'migrations')

// ── THE READER ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/** The text with every comment replaced by spaces (newlines kept), so an index into it is an index into the file. */
function blankComments(sql: string): string {
  const out = sql.split('')
  let i = 0
  const n = sql.length
  while (i < n) {
    const c = sql[i]
    const d = sql[i + 1]
    if (c === '-' && d === '-') {
      while (i < n && sql[i] !== '\n') out[i++] = ' '
    } else if (c === '/' && d === '*') {
      let depth = 0
      while (i < n) {
        if (sql[i] === '/' && sql[i + 1] === '*') { depth++; out[i] = out[i + 1] = ' '; i += 2; continue }
        if (sql[i] === '*' && sql[i + 1] === '/') { depth--; out[i] = out[i + 1] = ' '; i += 2; if (depth === 0) break; continue }
        if (sql[i] !== '\n') out[i] = ' '
        i++
      }
    } else if (c === "'") {
      const escaped = i > 0 && /[eE]/.test(sql[i - 1]) && (i < 2 || !/\w/.test(sql[i - 2]))
      i++
      while (i < n) {
        if (escaped && sql[i] === '\\') { i += 2; continue }
        if (sql[i] === "'") { if (sql[i + 1] === "'") { i += 2; continue } i++; break }
        i++
      }
    } else i++
  }
  return out.join('')
}

/** The `-- <tag>:` comment lines of a file, with their offsets and their text after the tag. */
function tagLines(sql: string, tag: string): { at: number; text: string }[] {
  const re = new RegExp(`--\\s*${tag}:[ \\t]*([^\\n]*)`, 'gi')
  return [...sql.matchAll(re)].map((m) => ({ at: m.index ?? 0, text: m[1].trim() }))
}

/** [start, end) of the statement around offset `at`, read on the comment-blanked text: from just after the previous `;`
 *  to just after the next one. Inside a dollar body that is the PL/pgSQL statement, which is what "next to it" means there. */
function span(code: string, at: number): [number, number] {
  const start = code.lastIndexOf(';', at - 1) + 1
  const next = code.indexOf(';', at)
  return [start, next < 0 ? code.length : next + 1]
}

const lineOf = (sql: string, at: number) => sql.slice(0, at).split('\n').length

/** Every option list `set (…)` / `with (…)` / `reset (…)` in the code, with its offset. Lists may run across a string
 *  concatenation (0412 built its own with format()); a list ends at its closing parenthesis. */
function optionLists(code: string): { at: number; body: string }[] {
  return [...code.matchAll(/\b(?:set|with)\s*\(([^()]*)\)/gi)].map((m) => ({ at: m.index ?? 0, body: m[1] }))
}

/** The value given to option `key` in a list: a number, a word (`false`), `?` when it is there but not a literal (a %s), or null. */
function option(body: string, key: string): string | null {
  const m = body.match(new RegExp(`(?:^|[\\s,'(])(?:toast\\.)?${key}\\s*=\\s*([^,)\\s']+)`, 'i'))
  if (!m) return null
  return /^[\w.]+$/.test(m[1]) ? m[1].toLowerCase() : '?'
}

const isNumber = (v: string | null) => v !== null && /^\d+(\.\d+)?$/.test(v)

type Finding = { file: string; line: number; rule: 'a' | 'b' | 'c' | 'd'; what: string }

/** Every breach of rules a-d in one migration's text. */
function budgetFindings(file: string, sql: string): Finding[] {
  sql = sql.replaceAll('\r', '')
  const code = blankComments(sql)
  const budget = tagLines(sql, 'budget')
  const retention = tagLines(sql, 'retention')
  const found: Finding[] = []
  const near = (lines: { at: number; text: string }[], at: number, ok: (t: string) => boolean) => {
    const [s, e] = span(code, at)
    return lines.some((l) => l.at >= s && l.at < e && ok(l.text))
  }
  const reasoned = (t: string) => t.length >= MIN_REASON
  const statesRows = (t: string) => reasoned(t) && /\d/.test(t) && /\brows?\b/i.test(t)

  // a + d: the option lists
  for (const { at, body } of optionLists(code)) {
    for (const kind of ['vacuum', 'analyze'] as const) {
      const thr = option(body, `autovacuum_${kind}_threshold`)
      const sf = option(body, `autovacuum_${kind}_scale_factor`)
      if (thr === null || sf === null || !isNumber(sf) || Number(sf) !== 0) continue
      if (isNumber(thr) && Number(thr) >= AUTOVACUUM_THRESHOLD_FLOOR) continue
      if (near(budget, at, reasoned)) continue
      found.push({ file, line: lineOf(sql, at), rule: 'a',
        what: `autovacuum_${kind}_threshold = ${thr} with scale factor 0 (floor ${AUTOVACUUM_THRESHOLD_FLOOR}) and no "-- budget: <reason>" next to it` })
    }
    const en = option(body, 'autovacuum_enabled')
    if (en !== null && !['true', 'on', '1', 'yes'].includes(en) && !near(budget, at, reasoned))
      found.push({ file, line: lineOf(sql, at), rule: 'a', what: `autovacuum_enabled = ${en} and no "-- budget: <reason>" next to it` })
    const ff = option(body, 'fillfactor')
    if (ff !== null && (!isNumber(ff) || Number(ff) < FILLFACTOR_FLOOR) && !near(budget, at, reasoned))
      found.push({ file, line: lineOf(sql, at), rule: 'd', what: `fillfactor = ${ff} (floor ${FILLFACTOR_FLOOR}) and no "-- budget: <reason>" next to it` })
  }

  // b: CREATE TABLE
  const retentionOk = (t: string) => t.length > 0 && (!/^none\b/i.test(t) || /\bbounded by\b\s*\S/i.test(t))
  for (const m of code.matchAll(/\bcreate\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?((?:"?\w+"?\.)?"?(\w+)"?)/gi)) {
    const at = m.index ?? 0
    const bare = m[2].toLowerCase()
    const named = retention.some((l) => retentionOk(l.text) && new RegExp(`\\b${bare}\\b`, 'i').test(l.text))
    if (named || near(retention, at, retentionOk)) continue
    found.push({ file, line: lineOf(sql, at), rule: 'b',
      what: `create table ${m[1]} with no "-- retention: <rule or knob>" or "-- retention: none, bounded by <why>" line` })
  }

  // c: cron
  const cron = [
    ...code.matchAll(/\bcron\.(?:schedule|schedule_in_database|alter_job)\s*\(/gi),
    ...code.matchAll(/\bupdate\s+cron\.job\b[^;]*\bschedule\b/gi),
  ]
  for (const m of cron) {
    const at = m.index ?? 0
    if (near(budget, at, statesRows)) continue
    found.push({ file, line: lineOf(sql, at), rule: 'c',
      what: `${m[0].replace(/\s+/g, ' ').slice(0, 40)} with no "-- budget:" line stating its expected rows touched per run` })
  }
  return found.sort((x, y) => x.line - y.line)
}

const judged = () =>
  readdirSync(DIR)
    .filter((f) => /^\d{14}_.+\.sql$/.test(f))
    .filter((f) => Number(f.slice(8, 14)) > FROZEN_HEAD)
    .sort()

const say = (fs: Finding[]) => fs.map((f) => `${f.file}:${f.line} rule ${f.rule}: ${f.what}`).join('\n')

// ── THE LAW ────────────────────────────────────────────────────────────────────────────────────────────────────────────

test('every migration after the frozen head keeps the database budget (autovacuum, retention, cron, fillfactor)', () => {
  const all = readdirSync(DIR).filter((f) => /^\d{14}_.+\.sql$/.test(f))
  expect(all.length, 'no migration was read: the directory reader is broken').toBeGreaterThan(300)
  const bad = judged().flatMap((f) => budgetFindings(f, readFileSync(path.join(DIR, f), 'utf8')))
  expect(
    bad,
    'A migration spends the database without saying why. See docs/DATABASE_BUDGET.md ("Rules for a migration"): fix it, or ' +
      'put the reasoned line next to it.\n' + say(bad),
  ).toEqual([])
})

// ── THE READER, PROVED ─────────────────────────────────────────────────────────────────────────────────────────────────

test('history: the reader would have caught the files that caused 2026-11-14', () => {
  const at = (n: string) => {
    const f = readdirSync(DIR).find((x) => x.slice(8, 14) === n)
    if (!f) throw new Error(`migration ${n} not found`)
    return budgetFindings(f, readFileSync(path.join(DIR, f), 'utf8'))
  }
  // 0291: standing_route_laps at threshold 500 / analyze 2,000, scale factor 0.
  expect(at('000291').filter((f) => f.rule === 'a').length).toBe(2)
  // 0292: port_goods at fillfactor 30. Its `'fillfactor=30'` strings in the self-assert are reads, not settings.
  expect(at('000292').filter((f) => f.rule === 'd').length).toBe(1)
  // 0412: the thresholds built with format(… %s …): a value the reader cannot see, with scale factor 0.
  expect(at('000412').some((f) => f.rule === 'a')).toBe(true)
  // 0248: arrivals_beats is a ring of 3,600 rows, but nothing in the file said so.
  expect(at('000248').some((f) => f.rule === 'b' && f.what.includes('arrivals_beats'))).toBe(true)
})

test('the rules: bad text is found, the same text with its reasoned line passes', () => {
  const F = (sql: string) => budgetFindings('t.sql', sql).map((f) => f.rule)

  // a
  expect(F('alter table public.t set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 500);')).toEqual(['a'])
  expect(F('alter table public.t set (autovacuum_analyze_scale_factor = 0, autovacuum_analyze_threshold = 19999);')).toEqual(['a'])
  expect(F('alter table public.t set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 20000);')).toEqual([])
  expect(F('alter table public.t set (autovacuum_vacuum_threshold = 500);')).toEqual([])   // the default scale factor still scales
  expect(F('alter table public.t set (autovacuum_enabled = false);')).toEqual(['a'])
  expect(F('alter table public.t set (toast.autovacuum_enabled = off);')).toEqual(['a'])
  expect(F("-- budget: a 300-row ring; a pass reads 3 pages\nalter table public.t set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 500);")).toEqual([])
  expect(F('-- budget: short\nalter table public.t set (autovacuum_enabled = false);')).toEqual(['a'])
  // the line must be next to it: a budget line before an EARLIER statement does not cover this one
  expect(F('-- budget: the ring holds 300 rows, 3 pages\nselect 1;\nalter table public.t set (autovacuum_enabled = false);')).toEqual(['a'])

  // b
  expect(F('create table public.t (id int primary key);')).toEqual(['b'])
  expect(F('create temp table t on commit drop as select 1;')).toEqual([])
  expect(F('-- retention: t_keep_days, trimmed by tick_compact\ncreate table public.t (id int);')).toEqual([])
  expect(F('create table if not exists public.t (id int);\n-- retention: public.t keeps 3,600 rows, a ring by slot')).toEqual([])
  expect(F('-- retention: none\ncreate table public.t (id int);')).toEqual(['b'])
  expect(F('-- retention: none, bounded by one row a harbour (263)\ncreate table public.t (id int);')).toEqual([])
  expect(F("-- retention: none, bounded by one row\nselect 1;\ncreate table public.u (id int);")).toEqual(['b'])
  // a comment or a string is not a statement
  expect(F("-- create table public.t (id int);\nselect 'x';")).toEqual([])
  expect(F("select E'it\\'s -- create table'; create table public.t (id int);")).toEqual(['b'])

  // c
  expect(F("select cron.schedule('j', '* * * * *', 'select 1');")).toEqual(['c'])
  expect(F("select cron.schedule('j', '5 seconds', 'select 1');")).toEqual(['c'])
  expect(F("-- budget: about 260 rows a run (one a harbour)\nselect cron.schedule('j', '*/10 * * * *', 'select 1');")).toEqual([])
  expect(F("-- budget: cheap, runs fast and rarely\nselect cron.schedule('j', '0 * * * *', 'select 1');")).toEqual(['c'])
  expect(F("do $$ begin\n  -- budget: 2,000 rows a run at most (compact_trim_rows)\n  perform cron.schedule('j', '* * * * *', 'select 1');\nend $$;")).toEqual([])
  expect(F("do $$ begin\n  perform cron.alter_job(7, schedule => '* * * * *');\nend $$;")).toEqual(['c'])
  expect(F("update cron.job set schedule = '* * * * *' where jobname = 'j';")).toEqual(['c'])
  expect(F("do $$ begin execute format('select cron.schedule(%L, %L, %L)', 'j', '* * * * *', 'select 1'); end $$;")).toEqual(['c'])

  // d
  expect(F('alter table public.t set (fillfactor = 30);')).toEqual(['d'])
  expect(F('create index i on public.t (a) with (fillfactor = 40);')).toEqual(['d'])
  expect(F('alter table public.t set (fillfactor = 70);')).toEqual([])
  expect(F("select 1 from pg_class c where c.reloptions @> array['fillfactor=30'];")).toEqual([])
  expect(F('-- budget: every row is rewritten each minute; 3 versions a page\nalter table public.t set (fillfactor = 30);')).toEqual([])
})
