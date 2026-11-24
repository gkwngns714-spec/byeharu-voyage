// A WORLD WHOSE NAMED READS ANSWER LATE, AND A WATCH THAT SAYS WHAT MOVED WHEN THEY DID (2026-11-25).
//
// The owner's law: nothing on a page moves by itself. Main's Acceptance went red three times in a day on a different test each
// time, and two of the three were one cause: a block that draws NOTHING until its own read answers, then stands up inside a page
// that was already on the glass and pushes what is under it. On a fast machine the read lands in the same frame and no test sees
// it; on a loaded runner it lands a second later, between a spec's "before" and "after" measurements. A test that waits for it to
// happen by luck proves nothing, so this file makes it happen every time:
//
//   · `lateWorld(reads, seconds)` is the shipped image with each named read (`world.house_room`) answering `seconds` late: the
//     function is renamed and a wrapper of the same name and arguments sleeps, then asks it. Nothing else in the chain changes.
//   · `watchBoxes(page, marks)` records, from the first commit an element is drawn in, every box it takes. `movesOf(page)` is the
//     list of boxes that CHANGED after standing still for `STOOD_MS`: a box that was on the glass and then moved by itself.
//
// The watch reads on a MutationObserver (after every commit), not on a timer: the database runs on the page's own thread, so a
// sleeping read holds the page still, and a timer would not fire between "the page drew" and "the late answer redrew it".

import type { Page } from '@playwright/test'
import type { PGlite } from '@electric-sql/pglite'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

/** A box that stood this long was on the glass: the eye saw it there before it moved. */
export const STOOD_MS = 250

/** Make `schema.fn` answer `seconds` late. Only a plain function returning jsonb, defined once, can be wrapped this way; anything else throws. */
export async function makeLate(pg: PGlite, read: string, seconds: number): Promise<void> {
  const [schema, fn] = read.split('.')
  const found = await pg.query<{ args: string; n: number; ok: boolean }>(
    `select pg_get_function_arguments(p.oid) as args, p.pronargs::int as n,
            (p.prorettype = 'jsonb'::regtype and not p.proretset and p.prokind = 'f') as ok
       from pg_proc p join pg_namespace s on s.oid = p.pronamespace
      where s.nspname = $1 and p.proname = $2`,
    [schema, fn],
  )
  if (found.rows.length !== 1) throw new Error(`lateRead: ${read} has ${found.rows.length} definitions, expected one`)
  const { args, n, ok } = found.rows[0]
  if (!ok) throw new Error(`lateRead: ${read} is not a plain function returning jsonb`)
  const pass = Array.from({ length: n }, (_, i) => `$${i + 1}`).join(', ')
  await pg.exec(`
    alter function ${schema}.${fn}(${args}) rename to ${fn}__now;
    create function ${schema}.${fn}(${args}) returns jsonb language plpgsql as $late$
    begin
      perform pg_sleep(${seconds});
      return ${schema}.${fn}__now(${pass});
    end $late$;
    grant execute on function ${schema}.${fn}(${args}) to authenticated;
  `)
}

/** Make the no-argument read `schema.fn` answer `value` instead of its own answer (a world state a spec cannot walk to: a choice open at sea).
 *  The stub keeps the read's name, so `makeLate` can still wrap it afterwards. */
export async function stubRead(pg: PGlite, read: string, value: unknown): Promise<void> {
  const [schema, fn] = read.split('.')
  const json = JSON.stringify(value).replace(/'/g, "''")
  await pg.exec(`
    alter function ${schema}.${fn}() rename to ${fn}__real;
    create function ${schema}.${fn}() returns jsonb language sql stable as $stub$ select '${json}'::jsonb $stub$;
    grant execute on function ${schema}.${fn}() to authenticated;
  `)
}

/** The shipped world with these reads late. Built once per worker per list. */
export function lateWorld(reads: readonly string[], seconds = 2): Promise<Buffer> {
  return patchedWorldImage(`late:${seconds}:${reads.join(',')}`, async (pg) => {
    for (const read of reads) await makeLate(pg, read, seconds)
  })
}

export async function serveLateWorld(page: Page, reads: readonly string[], seconds = 2): Promise<void> {
  await serveWorldImage(page, await lateWorld(reads, seconds))
}

export interface Move {
  /** The mark's name and the element's index under it: `row#0`. */
  mark: string
  from: number[]
  to: number[]
  /** How long the first box stood before it changed, in ms. */
  stood: number
}

/** Start the watch BEFORE the page is opened. `marks` names the selectors to follow: `{ card: '[data-testid="fleets-list"]' }`.
 *  `within`: read each box from this element's corner instead of the glass's, to watch one block apart from what stands over it. */
export async function watchBoxes(page: Page, marks: Record<string, string>, within: string | null = null): Promise<void> {
  await page.addInitScript(
    ({ marks, stoodMs, within }) => {
      const seen = new Map<string, { box: number[]; at: number }>()
      const moves: unknown[] = []
      const w = window as unknown as { __boxMoves: unknown[]; __boxSeen: () => string[] }
      w.__boxMoves = moves
      w.__boxSeen = () => [...seen.keys()]
      const read = () => {
        const now = performance.now()
        const frame = within ? document.querySelector(within) : null
        if (within && !frame) return
        const from = frame ? frame.getBoundingClientRect() : { left: 0, top: 0 }
        for (const [name, selector] of Object.entries(marks)) {
          document.querySelectorAll(selector).forEach((el, i) => {
            const r = el.getBoundingClientRect()
            if (r.width === 0 && r.height === 0) return
            const box = [r.left - from.left, r.top - from.top, r.width, r.height].map((n) => Math.round(n * 10) / 10)
            const key = `${name}#${i}`
            const was = seen.get(key)
            if (!was) {
              seen.set(key, { box, at: now })
            } else if (was.box.some((n, k) => n !== box[k])) {
              if (now - was.at >= stoodMs) moves.push({ mark: key, from: was.box, to: box, stood: Math.round(now - was.at) })
              seen.set(key, { box, at: now })
            }
          })
        }
      }
      new MutationObserver(read).observe(document, { subtree: true, childList: true, attributes: true, characterData: true })
    },
    { marks, stoodMs: STOOD_MS, within },
  )
}

/** Every watched box that moved after standing still, and the marks seen at all (a watch that saw nothing proves nothing). */
export async function movesOf(page: Page): Promise<{ moves: Move[]; seen: string[] }> {
  return page.evaluate(() => {
    const w = window as unknown as { __boxMoves: Move[]; __boxSeen: () => string[] }
    return { moves: w.__boxMoves, seen: w.__boxSeen() }
  })
}

/** A move in one line, for the failure message. */
export const sayMove = (m: Move) => `${m.mark} stood ${m.stood} ms at [${m.from.join(', ')}] then went to [${m.to.join(', ')}] (left, top, width, height)`
