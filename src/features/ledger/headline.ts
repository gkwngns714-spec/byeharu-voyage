import { formatDucats, formatDucatsDelta, formatInt, formatMiles, formatPct, formatPctPoints, formatUnitPrice, pointLabel } from '../../lib/format'
import { parsePointToken } from '../../domain/passage'
import { routePausedEventWords } from '../../domain/route'
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
//   TOWED         {fleet, from, to, nm, fee}                  (0152 — from / to are CODES)
//   SIGNED_OFFICER {officer, code, specialty, bonus_pct, cost}   (0015:231 — NO fleet key)
//   STUDIED       {skill, code, level, port, cost}               (0016:239 — port is a CODE)
//   ENROLLED      {skill, code, port, cost}                       (0131 — enrolment in a skill)
//   ROUTE_LAP     {route, fleet, lap, stops, sold, bought, supplies, repairs, wages, net, skipped, skipped_lines}  (0092)
//   ROUTE_PAUSED  {route, fleet, reason, code?, sentence?}        (0092; 0093: sentence names ports)
//   NATION_CHANGED {from, from_name, to, to_name}                 (0143 — codes and names)
//   DONATED       {port, port_name, amount, nation}               (0144 — a gift to a city)
//   FLAG_CHANGED  {port, port_name, from, from_name, to, to_name, share_to, share_from}  (0146)
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
      const company = str(p, 'company') ?? 'Your company'
      const port = str(p, 'port')
      return `${company} founded${port ? ` at ${portName(port)}` : ''}.`
    }
    case 'BOUGHT': {
      const qty = num(p, 'qty')
      const good = str(p, 'good') ?? 'cargo'
      const price = num(p, 'avg_price')
      return `${fleet} bought ${qty === null ? 'some' : formatQty(qty)} ${good}${
        price === null ? '' : ` at ${formatUnitPrice(price)}`
      }.`
    }
    case 'SOLD': {
      const qty = num(p, 'qty')
      const good = str(p, 'good') ?? 'cargo'
      const price = num(p, 'avg_price')
      return `${fleet} sold ${qty === null ? 'some' : formatQty(qty)} ${good}${
        price === null ? '' : ` at ${formatUnitPrice(price)}`
      }.`
    }
    case 'DEPARTED': {
      // 0039: the payload names the destination — a port code, or the "lat,lon" of a pinpointed
      // spot of open sea — and the course's point count replaced the retired leg count.
      const nm = num(p, 'total_nm')
      const dest = str(p, 'dest')
      const destPoint = dest ? parsePointToken(dest) : null
      const bound = dest ? ` for ${destPoint ? pointLabel(destPoint) : portName(dest)}` : ''
      return `${fleet} departed${bound}${nm === null ? '' : ` — ${formatMiles(nm)}`}.`
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
      return `${fleet} arrived${toLabel}${leg}${nm === null ? '' : ` — ${formatMiles(nm)} sailed`}.`
    }
    case 'PROVISIONED': {
      // "resupplied", not "watered and victualled" and not "provisioned" — sailor's cant reads as
      // period flavour to whoever writes it and as nonsense to whoever plays it (the owner's
      // plain-words rule, 2026-08-23, said again 2026-09-13; docs/WORDS.md).
      const water = num(p, 'water_t')
      const food = num(p, 'food_t')
      return `${fleet} resupplied${
        water === null || food === null ? '' : ` — ${water.toFixed(1)} tons of water, ${food.toFixed(1)} tons of food`
      }.`
    }
    // A STANDING ORDER THAT COULD NOT RUN IS AN EVENT, not a silence. 0034 writes this row when a
    // fleet makes port under a preset and the purse or the hold cannot carry it — and the whole
    // reason the server writes it rather than shrugging is so the player can find out WHY their
    // ship is under-provisioned.
    case 'PROVISION_REFUSED': {
      const preset = str(p, 'preset')
      const reason = str(p, 'reason')
      return `${fleet} arrived with a ${preset ?? 'standing'} resupply order, but ${
        reason ?? 'could not be resupplied'
      }.`
    }
    case 'HIRED': {
      const count = num(p, 'count')
      const urgent = p['urgent'] === true || num(p, 'urgent') === 1
      // "crew", NOT "hands" — the owner's no-jargon rule (2026-08-23). This headline is composed
      // CLIENT-side, so the word is this file's to choose; the served `payload.lines` prose is not.
      return `${count === null ? 'Crew' : `${formatQty(count)} crew`} hired for ${fleet}${
        urgent ? ', at the urgent rate' : ''
      }.`
    }
    case 'DISMISSED': {
      // 0086: crew let go in port. No money moved, so there is no movement beside this line;
      // `crew` is what stays aboard, served on the event so nothing is subtracted here.
      const count = num(p, 'count')
      const crew = num(p, 'crew')
      return `${count === null ? 'Crew' : `${formatQty(count)} crew`} dismissed from ${fleet}${
        crew === null ? '' : ` — ${formatQty(crew)} crew stay on board`
      }.`
    }
    case 'REPAIRING': {
      const points = num(p, 'points')
      return `${fleet} is being repaired${points === null ? '' : ` — ${Math.round(points)} hull points`}.`
    }
    case 'REPAIRED':
      return `${fleet} repaired.`
    // 0152: a wreck towed to the nearest shipyard — or brought into the one where it lay (0 miles).
    case 'TOWED': {
      const to = str(p, 'to')
      const from = str(p, 'from')
      const nm = num(p, 'nm')
      if (!to) return `${fleet} was towed.`
      return from === to || nm === 0
        ? `${fleet} was brought in for repair at ${portName(to)}.`
        : `${fleet} was towed${nm === null ? '' : ` ${formatMiles(nm)}`} to ${portName(to)}.`
    }
    case 'SIGNED_OFFICER': {
      // Who, what they are, what they are worth. The wage is deliberately absent — it is the
      // movement printed beside this sentence, and saying it twice would make one movement look
      // like two. It says "worth", never "makes her faster": three of the four specialties are
      // read by no rule yet (0015's header), and a ledger line that claimed an effect the world
      // does not apply would be exactly the fabricated figure this screen exists to refuse.
      const officer = str(p, 'officer') ?? 'An officer'
      const specialty = str(p, 'specialty')
      const bonus = num(p, 'bonus_pct')
      return `${officer} hired${specialty ? ` as ${specialty.toLowerCase()}` : ''}${
        bonus === null ? '' : `, +${formatPctPoints(bonus)} bonus`
      }.`
    }
    case 'STUDIED': {
      // The SKILL is the subject: the payload has no captain in it and this house has exactly one,
      // so "The captain studied…" would add a word carrying no information.
      const skill = str(p, 'skill') ?? 'A skill'
      const level = num(p, 'level')
      const port = str(p, 'port')
      return `${skill} trained${level === null ? '' : ` to level ${formatInt(level)}`}${
        port ? ` at ${portName(port)}` : ''
      }.`
    }
    case 'ENROLLED': {
      // 0131: the tuition of a skill, paid once where it is taught; its levels then train by time.
      const skill = str(p, 'skill') ?? 'A skill'
      const port = str(p, 'port')
      return `Enrolled in ${skill}${port ? ` at ${portName(port)}` : ''}.`
    }
    case 'WAGES':
      return `Wages paid to ${fleet} from profit.`
    // 0087: a request met. The SOLD event beside it says what the sale paid; this line says what
    // the request paid over it, from the payload's own `premium` — never re-derived here.
    case 'FULFILLED': {
      const qty = num(p, 'qty')
      const good = str(p, 'good') ?? 'cargo'
      const port = str(p, 'port')
      const premium = num(p, 'premium')
      return `${fleet} delivered ${qty === null ? 'some' : formatQty(qty)} ${good} on ${port ? `${portName(port)}'s` : 'the'} request${
        premium === null ? '' : ` — ${formatDucats(premium)} premium`
      }.`
    }
    // 0092: A LAP OF A STANDING ROUTE — one line per lap, every figure the server summed from the
    // executors' own results (docs/TRADE_ROUTES.md §6). Nothing is added up here.
    case 'ROUTE_LAP': {
      const route = str(p, 'route') ?? 'its route'
      const lap = num(p, 'lap')
      const net = num(p, 'net')
      // Every term of the net, so the figures beside it add up to it (0093 review, NIT 9).
      const parts = (['sold', 'bought', 'supplies', 'repairs', 'wages'] as const)
        .map((k) => [k, num(p, k)] as const)
        .filter(([, v]) => v !== null)
        .map(([k, v]) => `${k} ${formatDucats(v as number)}`)
      const skipped = num(p, 'skipped')
      return `${fleet} finished lap ${lap === null ? '' : `${formatInt(lap)} `}of ${route}${
        net === null ? '' : ` — ${formatDucatsDelta(net)}`
      }${parts.length > 0 ? ` (${parts.join(', ')})` : ''}${skipped ? ` · ${formatInt(skipped)} skipped` : ''}.`
    }
    // A ROUTE THAT STOPPED ITSELF WHILE YOU WERE AWAY SAYS SO — the served REASON, worded in
    // src/domain/route (the one wording, shared with COMMAND's fold); the server's sentence only
    // for `error`, where it is the caught refusal's own.
    // 0146: a city changed country at the daily count — `Havana now flies the flag of England (54% to 41%).`
    case 'FLAG_CHANGED': {
      const where = str(p, 'port_name') ?? (str(p, 'port') ? portName(str(p, 'port') as string) : 'A city')
      const to = str(p, 'to_name') ?? str(p, 'to') ?? 'another country'
      const a = num(p, 'share_to')
      const b = num(p, 'share_from')
      const shares = a !== null ? ` (${formatPct(a)}${b !== null && str(p, 'from') ? ` to ${formatPct(b)}` : ''})` : ''
      return `${where} now flies the flag of ${to}${shares}.`
    }
    // 0144: a gift to a city — it counts as influence for your country there.
    case 'DONATED': {
      const amount = num(p, 'amount')
      const where = str(p, 'port_name') ?? (str(p, 'port') ? portName(str(p, 'port') as string) : null)
      return `Gave ${amount !== null ? formatDucats(amount) : 'coin'}${where ? ` to ${where}` : ''}.`
    }
    // 0143: the company's change of country, in the country's own name.
    case 'NATION_CHANGED': {
      const to = str(p, 'to_name') ?? str(p, 'to')
      const from = str(p, 'from_name') ?? str(p, 'from')
      // 0187 (GP1, docs/GREAT_POWERS.md): the world moved the company — its old country is a local ruler now.
      if (str(p, 'reason') === 'great_powers' && to && from) {
        return `${from} is a local ruler now; your company sails for ${to}.`
      }
      return to ? `Your company now sails for ${to}${from ? `, no longer ${from}` : ''}.` : `${kindWords(event.kind)}.`
    }
    case 'ROUTE_PAUSED':
      return routePausedEventWords(str(p, 'route') ?? 'A route', str(p, 'reason'), str(p, 'sentence'))
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

/** 0189: THE BATTLE REPORTS of a VOYAGE_REPORT — `payload.fights`, one per day a raid was fought in
 *  rounds: `line` is the index into `payload.lines` of that day's sentence ("Day 4. Sail sighted…"),
 *  `rounds` the fight in words, composed server-side by `voyage.fight_resolve`. The client neither
 *  re-words nor re-orders them; it only hangs each fight under its day. Absent on a report with no
 *  fight (and on every report while `combat_bite` is off): an empty list. */
export interface ReportFight {
  line: number
  rounds: string[]
}
export function payloadFights(payload: Record<string, unknown>): ReportFight[] {
  const v = payload['fights']
  if (!Array.isArray(v)) return []
  return v.flatMap((f): ReportFight[] => {
    if (f === null || typeof f !== 'object') return []
    const line = (f as Record<string, unknown>)['line']
    const rounds = (f as Record<string, unknown>)['rounds']
    if (typeof line !== 'number' || !Array.isArray(rounds)) return []
    return [{ line, rounds: rounds.filter((r): r is string => typeof r === 'string') }]
  })
}

/** A whole-number count reads as a count; a fractional one keeps its tenth. */
function formatQty(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}
