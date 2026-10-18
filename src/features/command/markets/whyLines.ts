import { formatFixed, formatInt, formatPct, formatPctChange } from '../../../lib/format'
import type { PriceWhy } from '../../../lib/rpc'

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
    ? `Your company is #${s.rank} among this city's givers: ${formatFixed(shave * 100, 0)}% off the port's spread`
    : `Your company is #${s.rank} among this city's givers`
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
  const where = t.stance === 'home' ? 'your own country' : t.holder ? t.holder.name : 'a free city'
  const how = !moved || t.stance === 'home' ? '' : `, ${STANCE_WORD[t.stance]}`
  return {
    label: `Tax on your profit · ${where}${how}`,
    value: moved ? `${formatPct(rate, 1)} (×${Number((rate / base).toFixed(2))})` : formatPct(rate, 1),
  }
}

const STANCE_WORD: Record<'ally' | 'peace' | 'rival' | 'war', string> = {
  ally: 'an ally',
  peace: 'at peace',
  rival: 'a rival',
  war: 'at war',
}

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
        add('haul', t.nm ? `Far from where it is made · ${formatInt(t.nm)} nm` : 'Far from where it is made', t.mult)
        break
      case 'affinity':
        add('affinity', t.mult < 1 ? 'Made on this coast' : 'Scarce on this coast', t.mult)
        break
      case 'taste':
        add('taste-region', why.region ? `Taste in ${why.region}` : 'Local taste', t.region)
        add('taste-faith', why.faith ? `${why.faith.name} demand` : 'Faith', t.faith)
        break
      case 'stock':
        add(
          'stock',
          `${t.mult > 1 ? 'Short of stock' : 'Plenty in stock'}${
            t.stock !== undefined && t.target !== undefined ? ` · ${formatInt(t.stock)} of ${formatInt(t.target)}` : ''
          }`,
          t.mult,
        )
        break
      case 'drift':
        add('drift', 'The market today', t.mult)
        break
      case 'season':
        add('season', 'The season', t.mult)
        break
      case 'development':
        add('development', 'A busy trading town', t.mult)
        break
      case 'band':
        add('band', t.mult < 1 ? 'Held at the price ceiling' : 'Held at the price floor', t.mult)
        break
      case 'glut': // 0194: recent heavy selling here, fading by half each game day
        add('glut', 'Sold heavily here lately', t.mult)
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
  if (!(units > 0)) return 'Nobody has traded it here today.'
  return `Traded here today: ${formatInt(units)} ${units === 1 ? 'unit' : 'units'} by ${v.houses} ${v.houses === 1 ? 'company' : 'companies'}`
}
