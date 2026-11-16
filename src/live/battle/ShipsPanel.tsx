import { formatFixed, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { BattleShipCard } from '../../lib/rpc'
import { fittedWords } from './shipCards'
import type { ShipState } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SIDE'S SHIPS, EACH ON A SMALL CARD (0450; owner 2026-11-16: "in fight, i want to see levels, their stats, their crew
// state, equipments").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ICONS AND NUMBERS, NOT SENTENCES (the owner: "too much words"): a ship is her name, `Lv n`, her class, a hull bar with
// hull now / her size, crew now / what she may carry (red, with "Short", under the crew her class needs), then one small
// grid of three across: guns, attack, accuracy, reach, armour, sighting, speed, handling, and under it what is fitted and her captains.
// EVERY FIGURE IS THE SERVER'S: the card is the hull as `world.battle_ticks` serves it from the battle sheet, frozen at
// the open (`ships.a|b[i]`), so these are the stats the fight is fought with; the hull NOW is the timeline's fold
// (./timeline.ts). A battle opened before 0450 has no card: the name, the hull and what the sheet had are drawn, no more.
// The words are the ship panel's own (`ship.*`): one word for one thing in the whole game.

function Stat({ icon, word, value }: { icon: string; word: string; value: string | null }) {
  if (value === null) return null
  return (
    <span className="flex items-center gap-1 whitespace-nowrap" title={word} aria-label={`${word} ${value}`} data-stat={word}>
      <span aria-hidden="true">{icon}</span>
      <span className="tabular-nums" aria-hidden="true">
        {value}
      </span>
    </span>
  )
}

const fig = (v: number | undefined, dp = 0): string | null => (typeof v === 'number' && Number.isFinite(v) ? (dp > 0 ? formatFixed(v, dp) : formatInt(Math.round(v))) : null)

function ShipCard({ card, now, side }: { card: BattleShipCard | undefined; now: ShipState; side: 0 | 1 }) {
  const t = useT()
  const max = Number(card?.maxd ?? now.ship.m) || 0
  const hull = Math.max(0, now.hull)
  const share = max > 0 ? Math.max(0, Math.min(1, hull / max)) : 0
  const lv = card?.lv ?? now.ship.lv
  const crew = card?.crew
  const short = typeof crew === 'number' && typeof card?.crew_need === 'number' && crew < card.crew_need
  const fitted = fittedWords(card?.fit)
  return (
    <div
      className={`flex min-w-0 flex-col gap-1 rounded-control bg-surface-2 px-2 py-1.5 text-t-caption ${now.struck || !now.up ? 'opacity-50' : ''}`}
      data-testid="battle-ship-card"
      data-side={side}
      data-struck={now.struck ? '1' : '0'}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span className={`min-w-0 break-words text-t-label font-semibold ${side === 0 ? 'text-info' : 'text-danger'}`} data-testid="battle-ship-name">
          {card?.name ?? now.ship.n}
        </span>
        {typeof lv === 'number' && (
          <span className="shrink-0 font-semibold text-accent" data-testid="battle-ship-level" data-level={lv}>
            {t('ship.level', { n: formatInt(lv) })}
          </span>
        )}
      </div>
      {(card?.cls || now.struck || !now.up) && (
        <div className="break-words text-ink-muted">
          {[card?.cls, now.struck ? t('battle.sunk') : !now.up ? t('fight.onWay') : null].filter(Boolean).join(' · ')}
        </div>
      )}
      <div className="flex items-center gap-2" title={t('ship.hull')} aria-label={`${t('ship.hull')} ${formatInt(Math.round(hull))} / ${formatInt(Math.round(max))}`}>
        <div className="h-2 min-w-0 flex-1 overflow-hidden rounded-chip bg-app">
          <div className={`h-full rounded-chip ${share > 0.5 ? 'bg-success' : share > 0.25 ? 'bg-warning' : 'bg-danger'}`} style={{ width: `${share * 100}%` }} />
        </div>
        <span className="shrink-0 tabular-nums" data-testid="battle-ship-hull" aria-hidden="true">
          {formatInt(Math.round(hull))}/{formatInt(Math.round(max))}
        </span>
      </div>
      {typeof crew === 'number' && (
        <div
          className={`flex items-center gap-1 ${short ? 'text-danger' : ''}`}
          title={t('ship.crew')}
          aria-label={`${t('ship.crew')} ${formatInt(crew)}${typeof card?.crew_max === 'number' ? ` / ${formatInt(card.crew_max)}` : ''}${short ? ` ${t('battle.short')}` : ''}`}
          data-testid="battle-ship-crew"
          data-short={short ? '1' : '0'}
        >
          <span aria-hidden="true">👥</span>
          <span className="tabular-nums" aria-hidden="true">
            {formatInt(crew)}
            {typeof card?.crew_max === 'number' ? `/${formatInt(card.crew_max)}` : ''}
          </span>
          {short && <span aria-hidden="true">{t('battle.short')}</span>}
        </div>
      )}
      <div className="grid grid-cols-3 gap-x-2 gap-y-0.5" data-testid="battle-ship-stats">
        <Stat icon="💣" word={t('battle.guns')} value={fig(card?.guns)} />
        <Stat icon="⚔️" word={t('ship.attack')} value={fig(card?.attack)} />
        <Stat icon="🎯" word={t('ship.accuracy')} value={fig(card?.accuracy)} />
        <Stat icon="📏" word={t('ship.reach')} value={fig(card?.reach)} />
        <Stat icon="🛡️" word={t('ship.armour')} value={fig(card?.armour)} />
        <Stat icon="👁️" word={t('ship.sighting')} value={fig(card?.sighting)} />
        <Stat icon="⛵" word={t('ship.speed')} value={fig(card?.speed, 1)} />
        <Stat icon="☸️" word={t('ship.handling')} value={fig(card?.handling)} />
        <Stat icon="⭐" word={t('battle.tier')} value={fig(card?.tier ?? now.ship.t)} />
        <Stat icon="💨" word={t('command.lvEvasion')} value={fig(card?.ev)} />
      </div>
      {fitted.length > 0 && (
        <div className="break-words text-ink-muted" title={t('ship.equipment')} aria-label={`${t('ship.equipment')}: ${fitted.join(', ')}`} data-testid="battle-ship-fit">
          <span aria-hidden="true">🧰 </span>
          {fitted.join(' · ')}
        </div>
      )}
      {(card?.caps ?? []).length > 0 && (
        <div className="break-words text-ink-muted" title={t('battle.captain')} data-testid="battle-ship-caps">
          <span aria-hidden="true">⚓ </span>
          {(card?.caps ?? []).map((c) => `${c.n} ${t('ship.level', { n: formatInt(c.lv) })}`).join(' · ')}
        </div>
      )}
    </div>
  )
}

/** One side's ships. `cards[i]` is the sheet's hull for the timeline's ship `i` (the same order, by the contract). */
export function ShipsPanel({ side, ships, cards, className = '' }: { side: 0 | 1; ships: readonly ShipState[]; cards: readonly BattleShipCard[] | undefined; className?: string }) {
  return (
    <div className={`grid content-start gap-2 grid-cols-[repeat(auto-fill,minmax(11.5rem,1fr))] ${className}`} data-testid={`battle-ships-${side}`}>
      {ships.map((s, i) => (
        <ShipCard key={i} card={cards?.[i]} now={s} side={side} />
      ))}
    </div>
  )
}
