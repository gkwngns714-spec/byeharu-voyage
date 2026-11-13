import { useEffect, useState } from 'react'
import { formatInt, MINUS } from '../lib/format'
import type { FightLog as Log, FightLoss } from '../lib/rpc'
import { useT, type T } from '../lib/i18n'
import { barCells, fightHull, fightRows, type FightCell } from './fightLines'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A RAID'S LOG ON THE GLASS (0353, owner row 315: "combat - like a log ... showing logs, damages etc.";
// docs/COMBAT_LOG.md 1.5, 6.1). THE ONE COMPONENT: History hangs it under its day, the arrival card unfolds it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// It draws the SERVER'S numbers (the engine's rounds, kept by voyage.raid_extras) and computes no outcome.
//   Raid · 2 Şebek · 81 crew
//   Order Flee · They saw first
//   1  Long   You Run · Slip 6%   Them 1/2 −41
//      ▮▮▮▮▯ 90%   Foe ▮▮▮▮▮ 100%
//   Result   Fled, round 3
//   Lost     Hull −120 (30%) · Crew 0 · Cargo 0
//   Gaivota  Hull 400 → 280
// ONE LIST ITEM A ROUND. In a wide box it is one line; in a narrow one the same item wraps to two BY ITS GRID (a
// container query, never by spaces: the font is not fixed-width). A bar is text cells, 10 wide or 5, with the percent
// always printed beside it. A cell says `hits/shots −damage`, or the reason there is none: No guns, Out of range,
// Caught unready, Run. Law 4 stands: no board, no art, no dice. Text.
// `dense` is the arrival card: always the narrow form. `paced` (the card) lets the lines come one at a time, 600 ms a
// round and a longer beat before the result; a player who asked for less motion gets them all at once.
// 0357: THE SAME COMPONENT DRAWS A BATTLE SHE STARTED (src/live/BattleCard.tsx, and its report in History): the log
// says whose deck it is (`attacker`), so the title is Battle and no standing order is named. A battle still being
// fought (end OPEN) has its rounds and nothing after them: no result is told before the server has one.

const STEP_MS = 600
const RESULT_MS = 1200

function lessMotion(): boolean {
  return typeof window === 'undefined' || typeof window.matchMedia !== 'function' || window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function cellText(t: T, c: FightCell): string {
  if (c.kind === 'shots') return c.dealt > 0 ? `${c.hits}/${c.fired} ${MINUS}${formatInt(Math.round(c.dealt))}` : `${c.hits}/${c.fired}`
  return t(c.kind === 'run' ? 'fight.run' : c.kind === 'noGuns' ? 'fight.noGuns' : c.kind === 'outOfRange' ? 'fight.outOfRange' : 'fight.unready')
}

function HullCells({ pct, dense, testId }: { pct: number; dense: boolean; testId: string }) {
  return (
    <span className="whitespace-nowrap tabular-nums" data-testid={testId} data-pct={pct}>
      <span aria-hidden className={dense ? '' : '@xl:hidden'}>
        {barCells(pct, 5)}
      </span>
      {!dense && (
        <span aria-hidden className="hidden @xl:inline">
          {barCells(pct, 10)}
        </span>
      )}{' '}
      {pct}%
    </span>
  )
}

export function FightLog({ log, loss, dense = false, paced = false }: { log: Log; loss: FightLoss | null; dense?: boolean; paced?: boolean }) {
  const t = useT()
  const rows = fightRows(log)
  const hull = fightHull(log)
  // the lines that come one at a time: the foe, the order, each round, then the result and what follows it together
  const open = log.end === 'OPEN'
  const total = 2 + rows.length + (open ? 0 : 1)
  const [step, setShown] = useState(() => (paced && !lessMotion() ? 1 : total))
  // only a paced log counts its lines in: a log that grows as it is read (a battle) shows each new round at once
  const shown = paced ? step : total
  useEffect(() => {
    if (shown >= total) return
    const id = window.setTimeout(() => setShown((n) => n + 1), shown === total - 1 ? RESULT_MS : STEP_MS)
    return () => window.clearTimeout(id)
  }, [shown, total])

  const ended = t(`fight.end_${log.end}`)
  // a fight that ended in a round (they broke off, she got away) names the round
  const result = (log.end === 'FLED' || log.end === 'BROKE' || log.end === 'A_BROKE') && rows.length > 0 ? t('fight.resultRound', { end: ended, n: rows.length }) : ended
  const cargo = loss ? Object.values(loss.cargo).reduce((n, q) => n + q, 0) : 0
  const lost = [
    `${t('fight.hull')} ${MINUS}${formatInt(Math.round(hull.lost))} (${hull.lostPct}%)`,
    loss && loss.crew !== null ? `${t('fight.crew')} ${loss.crew > 0 ? MINUS : ''}${formatInt(loss.crew)}` : null,
    loss ? `${t('fight.cargo')} ${cargo > 0 ? MINUS : ''}${formatInt(cargo)}` : null,
    loss && loss.ransom > 0 ? `${t('fight.ransom')} ${MINUS}${formatInt(loss.ransom)}` : null,
  ].filter(Boolean)
  const order = [
    log.attacker ? null : `${t('fight.order')} ${t(log.order === 'FLEE' ? 'fight.orderFlee' : log.order === 'PAY' ? 'fight.orderPay' : 'fight.orderFight')}`,
    log.noPay ? t(`fight.noPay_${log.noPay}`) : null,
    t(log.first === 'YOU' ? 'fight.sawFirstYou' : log.first === 'THEY' ? 'fight.sawFirstThey' : 'fight.sawFirstBoth'),
  ].filter(Boolean)
  // THE ROUND'S GRID. Narrow: the number, then two lines that wrap by themselves when the box is very small (320 px):
  // range, you, them; her bar, theirs. Wide (a container query): the two lines dissolve (`contents`) and the six
  // cells stand on one line in fixed columns.
  const grid = dense
    ? 'grid grid-cols-[1.25rem_minmax(0,1fr)] gap-x-2'
    : 'grid grid-cols-[1.25rem_minmax(0,1fr)] gap-x-2 @xl:grid-cols-[1.25rem_4.5rem_minmax(0,1.3fr)_minmax(0,1fr)_9.5rem_11.5rem]'
  const line = dense ? 'col-start-2 flex flex-wrap gap-x-3' : 'col-start-2 flex flex-wrap gap-x-3 @xl:contents'
  const word = 'text-ink-faint'

  return (
    <div
      className={`@container mt-2 border-l border-edge pl-3 text-t-caption text-ink-muted ${dense ? 'max-h-64 overflow-y-auto' : ''}`}
      data-testid="fight-log"
      data-end={log.end}
      data-deck={log.attacker ? 'attacker' : 'raided'}
      data-order={log.order}
      data-rounds={rows.length}
    >
      <p data-testid="fight-log-foe">
        {[t(log.attacker ? 'fight.battle' : 'fight.raid'), t('fight.foeLine', { n: formatInt(Math.max(1, Math.round(log.foe.ships))), name: log.foe.name, crew: formatInt(log.foe.crew) }), log.foe.ship]
          .filter(Boolean)
          .join(' · ')}
      </p>
      {shown >= 2 && <p data-testid="fight-log-order">{order.join(' · ')}</p>}
      {rows.length > 0 && shown > 2 && (
        <ol className="mt-1 space-y-1" data-testid="fight-log-rounds">
          {rows.slice(0, shown - 2).map((r) => (
            <li key={r.round} className={grid} data-testid="fight-log-round" data-round={r.round}>
              <span className="tabular-nums">{r.round}</span>
              <span className={line}>
                <span>{t(`fight.range${r.range}`)}</span>
                <span data-testid="fight-log-you" data-kind={r.you.kind}>
                  <span className={word}>{t('fight.you')}</span> {cellText(t, r.you)}
                  {r.slipPct !== null && ` · ${t('fight.slip', { n: r.slipPct })}`}
                </span>
                <span data-testid="fight-log-them" data-kind={r.them.kind}>
                  <span className={word}>{t('fight.them')}</span> {cellText(t, r.them)}
                </span>
              </span>
              <span className={line}>
                <span>
                  <HullCells pct={r.hullPct} dense={dense} testId="fight-log-hull" />
                </span>
                <span className="whitespace-nowrap">
                  <span className={word}>{t('fight.foe')}</span> <HullCells pct={r.foePct} dense={dense} testId="fight-log-foe-hull" />
                </span>
              </span>
            </li>
          ))}
        </ol>
      )}
      {!open && shown >= total && (
        <div className="mt-1 space-y-0.5">
          {log.board && (
            <p data-testid="fight-log-board">
              <span className={word}>{t('fight.boarding')}</span> {t('fight.boardingLine', { you: formatInt(log.board.crew), them: formatInt(log.board.foeCrew) })}
            </p>
          )}
          <p data-testid="fight-log-result">
            <span className={word}>{t('fight.result')}</span> <span className="font-semibold text-ink">{result}</span>
          </p>
          <p data-testid="fight-log-lost" data-hull-lost={Math.round(hull.lost)} data-hull-pct={hull.lostPct}>
            <span className={word}>{t('fight.lost')}</span> {lost.join(' · ')}
          </p>
          {log.you.map((s, i) => (
            <p key={i} className="tabular-nums" data-testid="fight-log-ship">
              {s.name} <span className={word}>{t('fight.hull')}</span> {formatInt(Math.round(s.hull))} → {formatInt(Math.round(log.after[i].hull))}
            </p>
          ))}
        </div>
      )}
    </div>
  )
}
