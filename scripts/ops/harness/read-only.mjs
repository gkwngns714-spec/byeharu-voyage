#!/usr/bin/env node
// read-only.mjs — THE ONE READER of a harness SQL file, and the one judge of "this file is a read-only prod check".
//
// Two callers, one rule:
//   tests/harness.guard.spec.ts   imports the reader and holds the whole tree to it (README.md, "Two classes").
//   every *.sh that sends a file to production (`db query --linked -f`) asks it first:
//       node read-only.mjs <file.sql>     exit 0: a read-only prod check.  exit 3: REFUSING, with the reason.
//
// THE RULE (readOnlyVerdict). With comments gone and every string and dollar-quoted literal one word:
//   1. the FIRST statement is `begin transaction read only` (any case, any line ending, any length of header
//      comment before it) — so Postgres itself refuses a write, whatever follows;
//   2. the LAST statement is `commit` or `rollback`;
//   3. no statement holds a write verb (insert, update, delete, merge, truncate, create, alter, drop, grant,
//      revoke, copy, refresh, call, perform, execute) or `explain analyze`. A hunk `$h$ … update … $h$` is DATA
//      and is not a write; the body of a `do` block, and of an `execute` literal inside one, is CODE.
//
// Until 2026-11-12 the shell scripts looked for the words in the file's first 40 or 400 BYTES. `combat-log/after.sql`
// opens with a 700-byte header comment, so the 30-minute after-check of 0353 refused its own check on prod. A byte
// count is not the rule; the first statement is.
//
// Not judged here: volatility (does the file call a function the chain does not declare stable or immutable).
// That needs the whole migration chain; the spec reads it, and `volatility.sql` asks production.

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const LIT = ' LIT '

/** `top`: the file's top-level text — comments gone, every literal AND every dollar-quoted body one word, so
 *  splitting on ';' gives the top-level statements. `code`: as `top`, but a `do` body and an `execute` literal
 *  inside one are inlined (their own literals stripped, recursively), because that is where a scene writes. */
export function tokenize(text) {
  let top = ''
  let code = ''
  let i = 0
  let lastWord = ''
  const n = text.length
  const word = /[A-Za-z_][A-Za-z0-9_]*/y
  while (i < n) {
    const c = text[i]
    const c2 = text[i + 1]
    if (c === '-' && c2 === '-') {
      const e = text.indexOf('\n', i)
      i = e < 0 ? n : e
      continue
    }
    if (c === '/' && c2 === '*') {
      let depth = 1
      i += 2
      while (i < n && depth > 0) {
        if (text[i] === '/' && text[i + 1] === '*') {
          depth++
          i += 2
        } else if (text[i] === '*' && text[i + 1] === '/') {
          depth--
          i += 2
        } else i++
      }
      top += ' '
      code += ' '
      continue
    }
    if (c === "'") {
      let j = i + 1
      while (j < n) {
        if (text[j] === "'") {
          if (text[j + 1] === "'") {
            j += 2
            continue
          }
          break
        }
        j++
      }
      top += LIT
      code += LIT
      i = j + 1
      continue
    }
    if (c === '"') {
      const j = text.indexOf('"', i + 1)
      const e = j < 0 ? n : j + 1
      top += text.slice(i, e)
      code += text.slice(i, e)
      i = e
      continue
    }
    if (c === '$') {
      const m = /^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/.exec(text.slice(i, i + 64))
      if (m) {
        const tag = m[0]
        const close = text.indexOf(tag, i + tag.length)
        const body = text.slice(i + tag.length, close < 0 ? n : close)
        top += LIT
        if (lastWord === 'do' || lastWord === 'execute') code += ' ; ' + tokenize(body).code + ' ; '
        else code += LIT
        i = close < 0 ? n : close + tag.length
        continue
      }
    }
    word.lastIndex = i
    const w = word.exec(text)
    if (w) {
      lastWord = w[0].toLowerCase()
      top += w[0]
      code += w[0]
      i += w[0].length
      continue
    }
    top += c
    code += c
    i++
  }
  return { top, code }
}

/** The top-level statements of a tokenised file: lower case, one space between words, no empty ones. */
export const statements = (top) =>
  top
    .split(';')
    .map((s) => s.replace(/\s+/g, ' ').trim().toLowerCase())
    .filter((s) => s !== '')

/** The statements a read-only transaction refuses, plus the PL/pgSQL verbs that run anything. */
const WRITE =
  /\b(insert|update|delete|merge|truncate|create|alter|drop|grant|revoke|copy|refresh|call|perform|execute)\b/gi
const EXPLAIN_ANALYZE = /\bexplain\s*(?:\([^)]*\banalyze\b[^)]*\)|analyze\b)/i
const GAME_CALL = /\b(public|voyage|cmd|world)\.([a-z_][a-z0-9_]*)\s*\(/gi

export const writesIn = (code) => {
  const found = new Set()
  for (const m of code.matchAll(WRITE)) found.add(m[1].toLowerCase())
  if (EXPLAIN_ANALYZE.test(code)) found.add('explain analyze')
  return [...found].sort()
}

export const gameCallsIn = (code) => {
  const found = new Set()
  for (const m of code.matchAll(GAME_CALL)) found.add(`${m[1]}.${m[2]}`.toLowerCase())
  return [...found].sort()
}

export const isReadOnlyTransaction = (stmts) =>
  stmts.length >= 2 &&
  /^(?:begin|start) (?:transaction |work )?read only$/.test(stmts[0]) &&
  /^(?:commit|rollback)$/.test(stmts[stmts.length - 1])

/** THE RULE, for a file about to be sent to production. `text` is the file as read from disk (CRLF or LF). */
export function readOnlyVerdict(text) {
  const { top, code } = tokenize(text.replaceAll('\r', ''))
  const stmts = statements(top)
  if (!isReadOnlyTransaction(stmts))
    return {
      ok: false,
      reason: `its first statement is "${(stmts[0] ?? '').slice(0, 60)}" and its last "${(stmts[stmts.length - 1] ?? '').slice(0, 40)}"; a prod check opens with "begin transaction read only" and closes with "commit" or "rollback"`,
    }
  const writes = writesIn(code)
  if (writes.length > 0) return { ok: false, reason: `it writes: ${writes.join(', ')}` }
  return { ok: true, reason: '' }
}

// The command line: node read-only.mjs <file.sql>
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const file = process.argv[2]
  if (!file || process.argv.length !== 3) {
    console.error('usage: node read-only.mjs <file.sql>')
    process.exit(64)
  }
  let text
  try {
    text = readFileSync(file, 'utf8')
  } catch (e) {
    console.log(`REFUSING: ${file} could not be read (${e.code ?? e.message})`)
    process.exit(3)
  }
  const v = readOnlyVerdict(text)
  if (!v.ok) {
    console.log(`REFUSING: ${file} is not a read-only prod check: ${v.reason}`)
    process.exit(3)
  }
}
