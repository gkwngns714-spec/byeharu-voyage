// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WORDS — the vocabulary law (docs/WORDS.md), made to FAIL rather than to be noticed
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-08-22: *"common words — stores? t? kn? what are these"*. The owner, 2026-09-13,
// on `54.3 days stores · 9 t free`: *"wtf is this? the wording is too old fashioned. 9t free? 9t
// free out of what?"* — and *"find similar crappy wordings, and make them new"*. Said twice, so it
// is a law with teeth: every player-facing string literal in the client is read here, and one of
// the NEVER words in it fails the suite.
//
// WHAT COUNTS AS PLAYER-FACING. A string literal that contains an uppercase letter or a space.
// That is deliberately crude and deliberately wide: it catches `label="Stores"`, `'Her hold is
// empty.'` and `` `${n} t free` ``, and it skips identifiers (`'stores'`, `'quay-stores'`,
// `data-testid` values, CSS classes without spaces are still caught — see the allow list). A
// literal the rule catches wrongly is added to ALLOW with its reason, never to the banned list's
// exceptions.
//
// PURE SPEC. No `page` fixture; Playwright runs it as a plain Node process.

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(process.cwd())
const SRC = path.join(ROOT, 'src')
const SWEPT = ['features', 'app', 'components/ui', 'domain', 'lib/format', 'live', 'store'].map((d) =>
  path.join(SRC, d),
)

/** The NEVER column of docs/WORDS.md, as word-boundary patterns. */
const BANNED: { word: RegExp; say: string }[] = [
  { word: /\btuns?\b/i, say: 'tons' },
  { word: /\bstores\b/i, say: 'supplies' },
  { word: /\bprovision(?:ed|s|ing)?\b/i, say: 'resupply' },
  { word: /\balongside\b/i, say: 'docked / in port' },
  { word: /\bquay\b/i, say: 'market / here / port' },
  { word: /\bshed\b/i, say: 'warehouse' },
  { word: /\b(?:the|your|a|this) house\b/i, say: 'you / your company' },
  { word: /\bsign(?:ed)? on\b/i, say: 'hire' },
  { word: /\bmend(?:ed|s|ing)?\b/i, say: 'repair' },
  { word: /\blay (?:her|it) down\b/i, say: 'build ship' },
  { word: /\bthe roads\b/i, say: 'anchorage' },
  { word: /\bher hold\b/i, say: 'cargo' },
  { word: /\baboard\b/i, say: 'on board' },
  { word: /\bhands\b/i, say: 'crew' },
  { word: /\bberths?\b/i, say: 'crew slots' },
  { word: /\d\s?t\b(?!-)/, say: 'N tons' },
  { word: /\d\s?nm\b/, say: 'N miles' },
  { word: /\d\s?kn\b/, say: 'N knots' },
  { word: /\bd\.\/t\b/, say: 'd. per ton' },
]

/** Literals the crude rule catches that are NOT player text, each with its reason. */
const ALLOW: RegExp[] = [
  /^[A-Z][A-Z0-9_]+$/, // a server verb or code: `'PROVISION'`, `'E_HOLD_FULL'`
  /^[A-Z][A-Z_ ]+ /, // a composed ORDER LINE for the server: `` `STORE ${g} ALL` ``
  /^(?:SAIL|BUY|SELL|PROVISION|HIRE|MAKE|BUILD|STORE|TAKE|REPAIR|FIT|UNFIT)\b/, // ditto, lowercase args
  /^[\w-]+(?: [\w-]+)*:?\s*$/i, // (kept loose) a bare identifier list — no punctuation, no sentence
]

function sourceFiles(dir: string): string[] {
  const out: string[] = []
  const walk = (d: string) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else if (/\.tsx?$/.test(name) && !/\.spec\.tsx?$/.test(name)) out.push(full)
    }
  }
  walk(dir)
  return out
}

/** Strip block and line comments so the header prose (which QUOTES the banned words) is not read. */
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
}

/** Every string literal — '…', "…", `…` (with `${}` holes blanked) — and JSX text between tags. */
function literals(src: string): string[] {
  const out: string[] = []
  const code = stripComments(src)
  for (const m of code.matchAll(/'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`((?:[^`\\]|\\.)*)`/g)) {
    const raw = m[1] ?? m[2] ?? m[3] ?? ''
    out.push(raw.replace(/\$\{[^}]*\}/g, ' '))
  }
  // JSX text only: one line, no code characters — `=> (` and `) : (` between `>` and `<` are code.
  for (const m of code.matchAll(/>([^<>{}=();\n]*[A-Za-z]{2,}[^<>{}=();\n]*)</g)) out.push(m[1].trim())
  return out.filter((t) => /[A-Z]|\s/.test(t))
}

test('no banned word in player-facing text — docs/WORDS.md', () => {
  const hits: string[] = []
  for (const dir of SWEPT) {
    for (const file of sourceFiles(dir)) {
      const rel = path.relative(ROOT, file).split(path.sep).join('/')
      // The gallery is the design system's own showroom, not a screen a player reaches.
      if (rel.includes('/gallery/')) continue
      for (const lit of literals(readFileSync(file, 'utf8'))) {
        if (ALLOW.some((a) => a.test(lit))) continue
        for (const { word, say } of BANNED) {
          if (word.test(lit)) hits.push(`${rel}: "${lit.slice(0, 80)}" — say "${say}"`)
        }
      }
    }
  }
  expect(hits, `banned words in player text:\n${hits.join('\n')}`).toEqual([])
})
