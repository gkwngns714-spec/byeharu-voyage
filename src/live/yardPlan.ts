// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE YARD'S PLAN — what a hull still wants, where it stands, and the next thing she can do (S1, 0358).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A FOLD OF THREE SERVED ANSWERS, and no rule of its own:
//   · the hull's recipe against what she keeps HERE   world.building_yard  (`qty`, `have`)
//   · each good's seller, weight and price now        world.yard_sources   (0358: `bulk`, `ask`, a part's `inputs`)
//   · what lies in the hold of the fleet at this quay world.fleets         (`ships[].cargo`, `free_hold`)
// Whether an order is taken is the server's alone: cmd.do_make reads her hold, cmd.do_store moves hold to
// storage, cmd.do_build reads this city's storage and her parts here. This file only says which of those
// three orders her hold and her storage would satisfy NOW, so the sheet's one button can name it.
//
// THE ORDER OF THE HOLD. A good can be wanted twice: a Barca's tar goes into the hull (8, from storage) and
// into her two parts (1 each, from the hold). So what is on board is counted for the PARTS first, and only
// what is left over is offered to storage. Storing the tar first would make MAKE refuse (proof 61).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { PlanLine, YardHull, YardInput, YardSource, YardSources } from '../lib/rpc'

/** One good the errand asks for: a hull good (kept in storage) or a part's input (kept in the hold). */
export interface PlanGood {
  code: string
  name: string
  /** How many the recipe asks for: the hull's count, or the part's count for the parts still to make. */
  need: number
  /** In this city's storage. Always 0 for a part's input: a part is made from the hold. */
  stored: number
  /** On board and counted for THIS line (the parts are counted first). */
  aboard: number
  /** Still to fetch: need less what is stored and what is on board for it. */
  short: number
  /** Where it is sold nearest, with the price and weight; undefined while the read is on the wire or before 0358. */
  source?: YardSource | YardInput
}

/** One part of the hull, with the goods it is made of. */
export interface PlanPart {
  code: string
  name: string
  need: number
  /** Kept in this city. */
  have: number
  inputs: PlanGood[]
  /** Where the part is made nearest (0349). */
  source?: YardSource
  /** Every input of the parts still to make is on board, and the part is made in THIS city (the read names this
   *  yard's own port, 0 miles). A part made elsewhere is never offered as "Make parts" here: MAKE would refuse. */
  makeable: boolean
}

export type PlanStep = 'make' | 'store' | 'build' | 'wait'

export interface YardPlan {
  goods: PlanGood[]
  parts: PlanPart[]
  /** Lines of the recipe that are fully there, and how many lines there are. */
  ready: number
  of: number
  /** The next thing she can do, and the orders that do it (empty for build and wait). */
  step: PlanStep
  lines: PlanLine[]
  /** What is still to buy at the sellers' prices now, or null when a price is not known yet. */
  goodsCost: number | null
  /** The weight of what is still to fetch, or null when a weight is not known yet. */
  weight: number | null
}

/** A count as an order's argument: "40", "2.5", never "40.00". */
const count = (n: number) => String(Math.round(n * 100) / 100)

export function yardPlan(hull: YardHull, sources: YardSources | undefined, aboard: Readonly<Record<string, number>>): YardPlan {
  const left: Record<string, number> = { ...aboard }
  const take = (code: string, want: number) => {
    const got = Math.max(0, Math.min(left[code] ?? 0, want))
    left[code] = (left[code] ?? 0) - got
    return got
  }

  // THE PARTS FIRST: their inputs come out of the hold.
  const parts: PlanPart[] = hull.items.map((item) => {
    const source = sources?.items.find((s) => s.code === item.code)
    const missing = Math.max(0, item.qty - item.have)
    // `inputs[].qty` is for every one of this part the hull takes; scale to the ones still to make
    const share = item.qty > 0 ? missing / item.qty : 0
    const inputs: PlanGood[] = (source?.inputs ?? []).map((input) => {
      const need = input.qty * share
      const got = take(input.code, need)
      return { code: input.code, name: input.good, need, stored: 0, aboard: got, short: Math.max(0, need - got), source: input }
    })
    return {
      code: item.code,
      name: item.name,
      need: item.qty,
      have: item.have,
      inputs,
      source,
      makeable: missing > 0 && source?.miles === 0 && inputs.length > 0 && inputs.every((i) => i.short <= 0),
    }
  })

  // THEN THE HULL'S GOODS: what is left on board may go to storage.
  const goods: PlanGood[] = hull.goods.map((good) => {
    const missing = Math.max(0, good.qty - good.have)
    const got = take(good.code, missing)
    return {
      code: good.code,
      name: good.name,
      need: good.qty,
      stored: good.have,
      aboard: got,
      short: Math.max(0, missing - got),
      source: sources?.goods.find((s) => s.code === good.code),
    }
  })

  const make: PlanLine[] = parts
    .filter((p) => p.makeable)
    .flatMap((p) => Array.from({ length: Math.round(p.need - p.have) }, () => ({ text: `MAKE ${p.code}` })))
  const store: PlanLine[] = goods.filter((g) => g.aboard > 0).map((g) => ({ text: `STORE ${g.code} ${count(g.aboard)}` }))
  const ready = goods.filter((g) => g.stored >= g.need).length + parts.filter((p) => p.have >= p.need).length
  const of = goods.length + parts.length
  const step: PlanStep = make.length > 0 ? 'make' : store.length > 0 ? 'store' : ready === of ? 'build' : 'wait'

  // What is still to fetch, priced and weighed. A part already made elsewhere than here is not folded: the sheet says where it is made.
  const toFetch = [...goods, ...parts.flatMap((p) => p.inputs)].filter((g) => g.short > 0)
  const priced = toFetch.every((g) => g.source !== undefined && 'ask' in g.source && typeof g.source.ask === 'number')
  const weighed = toFetch.every((g) => g.source !== undefined && typeof g.source.bulk === 'number')
  const waiting = sources === undefined && (hull.goods.length > 0 || hull.items.length > 0)
  return {
    goods,
    parts,
    ready,
    of,
    step,
    lines: step === 'make' ? make : step === 'store' ? store : [],
    goodsCost: waiting || !priced ? null : toFetch.reduce((sum, g) => sum + g.short * ((g.source as { ask: number }).ask), 0),
    weight: waiting || !weighed ? null : toFetch.reduce((sum, g) => sum + g.short * ((g.source as { bulk: number }).bulk), 0),
  }
}
