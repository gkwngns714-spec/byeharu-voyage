import { formatInt, formatNm, formatPctPoints } from '../../lib/format'
import { parsePointToken, pointLabel } from '../../domain/passage'
// THE ONE READER OF A JSONB FIELD (2026-08-23). `num`/`str` were declared here AND in
// features/command/PreviewPanel.tsx, and they had already drifted; docs/NO_SPAGHETTI.md §2 listed
// the pair as debt to fold. See src/lib/json.ts for why the stronger version is the one that
// survived.
import { num, str } from '../../lib/json'
import type { LedgerEvent } from '../../lib/rpc'

// ── THE ONE HEADLINE COMPOSER ───────────────────────────────────────────────────────────────────
// One sentence per server kind, built from that kind's payload and nothing else. The payloads are
// written by `public.emit_event()` in migration 0007 and 0004 and are exactly:
//
//   FOUNDED       {company, port}                             (port is a CODE)
//   BOUGHT/SOLD   {fleet, good, qty, avg_price, total}        (good is the NAME)
//   DEPARTED      {fleet, voyage_id, total_nm, points, dest, eta}   (0039: dest is a code or a "lat,lon")
//   VOYAGE_REPORT {fleet, voyage_id, from, to, from_point?, to_point?, total_nm, lines[]}
//   PROVISIONED   {fleet, water_t, food_t, cost}
//   HIRED         {fleet, count, urgent, cost}
//   REPAIRING     {fleet, points, cost, sim_hours}
//   REPAIRED      {fleet}
//   SIGNED_OFFICER {officer, code, specialty, bonus_pct, cost}   (0015:231 — NO fleet key)
//   STUDIED       {skill, code, level, port, cost}               (0016:239 — port is a CODE)
//
// An unknown kind falls through to the kind itself rather than to an invented sentence — a new
// migration's event shows up as a legible row on the day it lands, without lying about its content.
//
// The headline is not served (README §4.12): the client composes it from `kind` + `payload`, once,
// here. The prose report IS served — `payload.lines`, already sentences — and `payloadLines` is its
// one reader.
//
// ── WHY THE FALLBACK NO LONGER SUPPLIES A SUBJECT ───────────────────────────────────────────────
// The last two kinds shipped without their half of this composer and fell to the default, which
// read `${fleet} · …` off a `fleet` that defaulted to "A fleet". So signing Bartolomeu Dias
// printed "A fleet · signed officer." — legible, and about a fleet that had nothing to do with it.
// NEITHER PAYLOAD CONTAINS A FLEET AT ALL: an officer signs with the HOUSE (0015 refuses to put an
// officer column on `fleets`), and a trade is learned by the CAPTAIN. So the fallback names a fleet
// only when the payload names one.
//
// This file MOVED out of LedgerScreen.tsx on 2026-09-09 (docs/UI_DIRECTION.md §5: a screen file is
// ≤ 250 lines and contains one exported component; sub-views are files). Not one sentence changed.

export function headline(event: LedgerEvent, portName: (code: string) => string): string {
  const p = event.payload
  // The fallback for a payload that IS about a fleet and has lost the key. Not read by the
  // default branch: see the note above.
  const fleet = str(p, 'fleet') ?? 'A fleet'

  switch (event.kind) {
    case 'FOUNDED': {
      const company = str(p, 'company') ?? 'The house'
      const port = str(p, 'port')
      return `${company} opens its books${port ? ` at ${portName(port)}` : ''}.`
    }
    case 'BOUGHT': {
      const qty = num(p, 'qty')
      const good = str(p, 'good') ?? 'cargo'
      const price = num(p, 'avg_price')
      return `${fleet} took aboard ${qty === null ? 'a parcel of' : formatQty(qty)} ${good}${
        price === null ? '' : ` at ${Math.round(price)} d. the tun`
      }.`
    }
    case 'SOLD': {
      const qty = num(p, 'qty')
      const good = str(p, 'good') ?? 'cargo'
      const price = num(p, 'avg_price')
      return `${fleet} sold ${qty === null ? 'a parcel of' : formatQty(qty)} ${good}${
        price === null ? '' : ` at ${Math.round(price)} d. the tun`
      }.`
    }
    case 'DEPARTED': {
      // 0039: the payload names the destination — a port code, or the "lat,lon" of a pinpointed
      // spot of open sea — and the course's point count replaced the retired leg count.
      const nm = num(p, 'total_nm')
      const dest = str(p, 'dest')
      const destPoint = dest ? parsePointToken(dest) : null
      const bound = dest ? ` for ${destPoint ? pointLabel(destPoint) : portName(dest)}` : ''
      return `${fleet} put to sea${bound}${nm === null ? '' : ` — ${formatNm(nm)}`}.`
    }
    case 'VOYAGE_REPORT': {
      const from = str(p, 'from')
      const to = str(p, 'to')
      const nm = num(p, 'total_nm')
      // 0039: an open-water end carries its POINT instead of a code; the report names the spot
      // rather than leaving the sentence trailing (pointLabel is the one wording of a point).
      const toPoint = p['to_point']
      const toLabel = to
        ? ` to ${portName(to)}`
        : Array.isArray(toPoint) && toPoint.length === 2
          ? ` to ${pointLabel({ lat: Number(toPoint[0]), lon: Number(toPoint[1]) })}`
          : ''
      const leg = from ? ` from ${portName(from)}` : ''
      return `${fleet} came in${toLabel}${leg}${nm === null ? '' : ` — ${formatNm(nm)} sailed`}.`
    }
    case 'PROVISIONED': {
      // "provisioned", not "watered and victualled" — sailor's cant reads as period flavour to
      // whoever writes it and as nonsense to whoever plays it (the owner's plain-words rule,
      // 2026-08-23). PROVISION is the verb the player pressed; the report uses their own word.
      const water = num(p, 'water_t')
      const food = num(p, 'food_t')
      return `${fleet} provisioned${
        water === null || food === null ? '' : ` — ${water.toFixed(1)} t of water, ${food.toFixed(1)} t of food`
      }.`
    }
    // A STANDING ORDER THAT COULD NOT RUN IS AN EVENT, not a silence. 0034 writes this row when a
    // fleet makes port under a preset and the purse or the hold cannot carry it — and the whole
    // reason the server writes it rather than shrugging is so the player can find out WHY their
    // ship is under-provisioned.
    case 'PROVISION_REFUSED': {
      const preset = str(p, 'preset')
      const reason = str(p, 'reason')
      return `${fleet} made port under her ${preset ?? 'standing'} order, but ${
        reason ?? 'she could not be provisioned'
      }.`
    }
    case 'HIRED': {
      const count = num(p, 'count')
      const urgent = p['urgent'] === true || num(p, 'urgent') === 1
      // "crew", NOT "hands" — the owner's no-jargon rule (2026-08-23). This headline is composed
      // CLIENT-side, so the word is this file's to choose; the served `payload.lines` prose is not.
      return `${count === null ? 'Crew' : `${formatQty(count)} crew`} signed for ${fleet}${
        urgent ? ', at the urgent rate' : ''
      }.`
    }
    case 'REPAIRING': {
      const points = num(p, 'points')
      return `${fleet} went into the shipyard${points === null ? '' : ` for ${Math.round(points)} points of hull`}.`
    }
    case 'REPAIRED':
      return `${fleet} came out of the shipyard, sound again.`
    case 'SIGNED_OFFICER': {
      // Who, what they are, what they are worth. The wage is deliberately absent — it is the
      // movement printed beside this sentence, and saying it twice would make one movement look
      // like two. It says "worth", never "makes her faster": three of the four specialties are
      // read by no rule yet (0015's header), and a ledger line that claimed an effect the world
      // does not apply would be exactly the fabricated figure this screen exists to refuse.
      const officer = str(p, 'officer') ?? 'An officer'
      const specialty = str(p, 'specialty')
      const bonus = num(p, 'bonus_pct')
      return `${officer} signed on${specialty ? ` as ${specialty.toLowerCase()}` : ''}${
        bonus === null ? '' : `, worth +${formatPctPoints(bonus)}`
      }.`
    }
    case 'STUDIED': {
      // The SKILL is the subject: the payload has no captain in it and this house has exactly one,
      // so "The captain studied…" would add a word carrying no information.
      const skill = str(p, 'skill') ?? 'A trade'
      const level = num(p, 'level')
      const port = str(p, 'port')
      return `${skill} studied${level === null ? '' : ` to level ${formatInt(level)}`}${
        port ? ` at ${portName(port)}` : ''
      }.`
    }
    case 'WAGES':
      return `Wages paid to ${fleet}.`
    default: {
      const named = str(p, 'fleet')
      const what = kindWords(event.kind)
      return named ? `${named} · ${what}.` : `${what}.`
    }
  }
}

/** How a server kind is spelled for a human, in one place. `/_/g`, not `'_'` — the old spelling
 *  stopped at the first underscore. */
function kindWords(kind: string): string {
  return kind.toLowerCase().replace(/_/g, ' ')
}

/** The after-action prose: `string[]`, composed server-side by `voyage.report_line()`. Already
 *  whole sentences ("Day 1. A quiet watch; nothing to report.") — the client neither parses the
 *  day out of them nor re-words them. */
export function payloadLines(payload: Record<string, unknown>): string[] {
  const v = payload['lines']
  return Array.isArray(v) ? v.filter((line): line is string => typeof line === 'string') : []
}

/** A whole-number count reads as a count; a fractional one keeps its tenth. */
function formatQty(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}
