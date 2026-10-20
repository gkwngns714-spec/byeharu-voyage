import { formatFixed, formatInt, formatMiles, formatPct, formatPctChange } from '../../../lib/format'
import type { PriceWhy } from '../../../lib/rpc'
import { t as tw, wordTable } from '../../../lib/i18n'

// WHY THIS PRICE, AS LINES (docs/PRICE_FACTORS.md §5; migration 0185): world.price_why's served terms named
// and ranked by their served multipliers. Pure, so the face (WhyThisPrice.tsx) and the spec share it.

/** One printed line: what moves the price, and by how much. */
export interface WhyLine {
  key: string
  label: string
  /** The multiplier this line puts on the price. */
  mult: number
  /** "×4.3" for a large factor, "+12.0%" / "−8.0%" otherwise. */
  effect: string
}

/** Below this a term does not move the price enough to print (0.5 %). */
const QUIET = 0.005

/** 0191: the company's own line — its rank among this city's givers and what that spares it of the spread. */
export function stakeLine(why: PriceWhy): string | null {
  const s = why.stake
  if (!s) return null
  const shave = Number(s.shave)
  return shave > 0
    ? tw('markets.stakeShave', { rank: s.rank, pct: formatFixed(shave * 100, 0) })
    : tw('markets.stake', { rank: s.rank })
}

/** 0196: the company's own profit tax here and the relation that moves it (world.price_why `tariff`). The
 *  stance is named only when it moves the rate (the race off, every company pays the city's rate); the
 *  multiplier is the served rate over the served base, never a rule re-derived here. */
export function tariffLine(why: PriceWhy): { label: string; value: string } | null {
  const t = why.tariff
  if (!t) return null
  const rate = Number(t.rate)
  const base = Number(t.base)
  const moved = base > 0 && Math.abs(rate - base) > 1e-9
  const where = t.stance === 'home' ? tw('markets.ownCountry') : t.holder ? t.holder.name : tw('markets.freeCity')
  const how = !moved || t.stance === 'home' ? '' : `, ${STANCE_WORD[t.stance]}`
  return {
    label: tw('markets.tariff', { where, how }),
    value: moved ? `${formatPct(rate, 1)} (×${Number((rate / base).toFixed(2))})` : formatPct(rate, 1),
  }
}

const STANCE_WORD: Readonly<Record<'ally' | 'peace' | 'rival' | 'war', string>> = wordTable({
  ally: 'markets.ally',
  peace: 'markets.peace',
  rival: 'markets.rival',
  war: 'markets.war',
})

function effectOf(mult: number): string {
  return mult >= 2 ? `×${formatFixed(mult, mult >= 10 ? 0 : 1)}` : formatPctChange((mult - 1) * 100)
}

/** The served terms as lines, largest effect first. The taste prints as its two halves (the region's
 *  appetite for the kind of good, the faith's for the good). Pure: the spec and the face share it. */
export function whyLines(why: PriceWhy): WhyLine[] {
  const out: WhyLine[] = []
  const add = (key: string, label: string, mult: number | undefined) => {
    if (mult === undefined || !Number.isFinite(mult) || mult <= 0 || Math.abs(mult - 1) < QUIET) return
    out.push({ key, label, mult, effect: effectOf(mult) })
  }
  for (const t of why.terms) {
    switch (t.key) {
      case 'haul':
        add('haul', t.nm ? tw('markets.farMiles', { miles: formatMiles(t.nm) }) : tw('markets.far'), t.mult)
        break
      case 'affinity':
        add('affinity', tw(t.mult < 1 ? 'markets.madeHere' : 'markets.scarce'), t.mult)
        break
      case 'taste':
        add('taste-region', why.region ? tw('markets.tasteIn', { region: why.region }) : tw('markets.localTaste'), t.region)
        add('taste-faith', why.faith ? tw('markets.faithDemand', { faith: why.faith.name }) : tw('markets.faith'), t.faith)
        break
      case 'stock':
        add(
          'stock',
          tw(t.mult > 1 ? 'markets.short' : 'markets.plenty') +
            (t.stock !== undefined && t.target !== undefined
              ? tw('markets.stockOf', { stock: formatInt(t.stock), target: formatInt(t.target) })
              : ''),
          t.mult,
        )
        break
      case 'drift':
        add('drift', tw('markets.today'), t.mult)
        break
      case 'season':
        add('season', tw('markets.season'), t.mult)
        break
      case 'development':
        add('development', tw('markets.busyTown'), t.mult)
        break
      case 'band':
        add('band', tw(t.mult < 1 ? 'markets.ceiling' : 'markets.floor'), t.mult)
        break
      case 'glut': // 0194: recent heavy selling here, fading by half each game day
        add('glut', tw('markets.glut'), t.mult)
        break
    }
  }
  return out.sort((a, b) => Math.abs(Math.log(b.mult)) - Math.abs(Math.log(a.mult)))
}

/** 0190: the volume line under the terms — what changed hands here today (bought + sold) and by how many
 *  companies, players and merchants alike. Null before the server serves it. */
export function volumeLine(why: PriceWhy): string | null {
  const v = why.volume
  if (!v) return null
  const units = Number(v.units)
  if (!(units > 0)) return tw('markets.nobodyTraded')
  return tw('markets.traded', {
    units: tw('markets.units', { n: formatInt(units), count: units }),
    houses: tw('markets.companies', { n: v.houses }),
  })
}
