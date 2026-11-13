import { useEffect, useState } from 'react'
import { Bar, Figure, Row, SheetSection, Skeleton, Tray, TrayTitle, type TrayDetent } from '../components/ui'
import { CHART_CHROME } from '../chart'
import { formatInt } from '../lib/format'
import { worldFight } from '../lib/rpc'
import type { BattleRead, FightCard, FightSide } from '../lib/rpc'
import { useT } from '../lib/i18n'
import { BattleCard } from './BattleCard'
import { BattleView } from './BattleView'
import { FightLog } from './FightLog'
import { fightHull, fightRows, parseFightLog, parseFightLoss } from './fightLines'
import { HullCountry } from './HullCountry'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FIGHT, OPENED FROM ITS RING ON THE MAP (0364, owner row 321: "by clicking that circle, like info i want to see
// the actual fight").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A tray like every other the map opens. THE SERVER SERVES ALL OF IT:
//   · `card` is the battle's row of `world.fights()` (the map's own read): who is on each side, how many ships, whether
//     a called ship has come up, and whether the battle is the reader's own.
//   · the fight itself is `world.fight(battle)`, asked every 5 s ONLY WHILE THIS SHEET IS OPEN and the battle is being
//     fought; once it is over it is read once more and never again.
// HER OWN BATTLE is drawn by `BattleCard`, the card the fleet page has: her stance buttons are there, and it keeps the
// battle on the clock. ANYBODY ELSE'S is watch-only: `BattleView` with the watcher's read, which carries no stance.
// Both draw the ONE `FightLog`; nothing here draws a round.
// THE HULL BARS are the two sides' hull left, the log's own figures (`fightRows`): no second arithmetic.
// A NAME IS NEVER CUT: fleet and company names wrap whole.
// A RAID AND A NAVY FIGHT (the fights that are settled in an instant) open in this same sheet. They are over when their
// ring appears, so the card itself carries the whole log and NOTHING MORE IS ASKED: her own raid is drawn as her History
// draws it (her deck, with what the day cost her), a navy fight as a watcher's (Attacker the navy ship, Defender the
// pirate ship).

const POLL_MS = 5000

/** What a crown's or the Brethren's ship is, with her flag; a company's or a merchant's fleet says its company on the
 *  line under its name instead (two long names side by side leave a phone no room for either). */
function whose(side: FightSide, t: ReturnType<typeof useT>) {
  if (side.kind !== 'CARGO_SHIP' && side.kind !== 'NAVY' && side.kind !== 'PIRATE') return undefined
  // a raid's raiders are no named ship of the Brethren: they are the sea's own
  if (side.fleet === 'raiders') return <span>{t('fight.raiders')}</span>
  return (
    <span className="inline-flex flex-wrap items-center justify-end gap-x-1.5">
      <HullCountry nation={side.nation} compact />
      {t(side.kind === 'CARGO_SHIP' ? 'map.cargoShip' : side.kind === 'NAVY' ? 'map.navyShip' : 'map.pirateShip')}
    </span>
  )
}

function Side({ title, sides, hullPct, testId }: { title: string; sides: readonly FightSide[]; hullPct: number | null; testId: string }) {
  const t = useT()
  return (
    <SheetSection heading={title} surface data-testid={testId}>
      {sides.map((s, i) => (
        <Row
          key={s.fleet}
          hairline={i < sides.length - 1 || hullPct !== null}
          label={<span className="break-words" data-testid="fight-side-fleet">{s.name}</span>}
          value={whose(s, t)}
          data-testid="fight-side-row"
          data-here={s.here}
        >
          <span className="break-words text-t-caption text-ink-muted">
            {(s.kind === 'COMPANY' || s.kind === 'MERCHANT') && s.company ? <span data-testid="fight-side-company">{s.company} · </span> : null}
            {t('fight.shipsN', { n: formatInt(s.ships) })}
            {!s.here && ` · ${t('fight.onWay')}`}
          </span>
        </Row>
      ))}
      {hullPct !== null && (
        <Row hairline={false} label={t('fight.hull')} data-testid="fight-side-hull" data-pct={hullPct}>
          <Bar pct={hullPct} tone={hullPct <= 33 ? 'warning' : 'accent'} label={t('fight.hull')} figure={<Figure value={`${hullPct}%`} />} />
        </Row>
      )}
    </SheetSection>
  )
}

export function FightSheet({ card, onClose, mode }: { card: FightCard; onClose: () => void; mode?: 'docked' | 'side' }) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('peek')
  const [got, setGot] = useState<{ value: BattleRead; at: number } | null>(null)
  const [tick, setTick] = useState(() => Date.now())
  const battle = card.id
  const kind = card.kind ?? 'BATTLE'
  const instant = kind !== 'BATTLE'
  const read = !instant && got?.value.battle === battle ? got.value : null
  const fighting = instant ? false : read ? read.status === 'FIGHTING' : true

  useEffect(() => {
    if (!fighting) return
    let live = true
    const ask = () =>
      void worldFight(battle).then((r) => {
        if (live && r.ok) setGot({ value: r.value, at: Date.now() })
      })
    ask()
    const id = window.setInterval(ask, POLL_MS)
    return () => {
      live = false
      window.clearInterval(id)
    }
  }, [battle, fighting])

  useEffect(() => {
    if (!fighting) return
    const id = window.setInterval(() => setTick(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [fighting])

  const serverNow = got && read?.now ? Date.parse(read.now) + Math.max(0, tick - got.at) : tick
  const log = instant ? parseFightLog(card.log) : read ? parseFightLog(read.log, { open: true }) : null
  const loss = kind === 'RAID' ? parseFightLoss(card.loss) : null
  const rows = log ? fightRows(log) : []
  const last = rows.length > 0 ? rows[rows.length - 1] : null
  const hull = log ? fightHull(log) : null
  // the deck the log is told from: her hull after the last round fought (closed: after the whole fight); the other side: theirs
  const youPct = !log || !hull ? null : log.end !== 'OPEN' && hull.full > 0 ? Math.round((hull.after / hull.full) * 100) : last ? last.hullPct : hull.full > 0 ? Math.round((hull.before / hull.full) * 100) : null
  const foePct = !log ? null : last ? last.foePct : 100
  // a battle's and a navy fight's log is told from the deck of the side that closed; a raid's from the deck of the fleet set upon
  const attackerPct = log?.attacker === false ? foePct : youPct
  const defenderPct = log?.attacker === false ? youPct : foePct
  const attackers = card.sides.filter((s) => s.side === 'ATTACKER')
  const defenders = card.sides.filter((s) => s.side === 'DEFENDER')
  const mine = card.mine

  return (
    <Tray
      mode={mode}
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <TrayTitle
          name={t(kind === 'RAID' ? 'fight.raid' : kind === 'NAVY' ? 'fight.navyFight' : 'fight.battle')}
          line={
            <>
              {t('fight.fleetsShips', { f: formatInt(card.fleets), s: formatInt(card.ships) })}
              {kind !== 'RAID' && <> · {t(mine ? 'fight.yours' : 'fight.watching')}</>}
            </>
          }
          testId="fight-sheet-name"
        />
      }
      data-testid="fight-sheet"
      data-fight={battle}
      data-kind={kind}
      data-mine={mine ? 'true' : undefined}
      {...CHART_CHROME}
    >
      <div data-testid="fight-sheet-body" data-status={card.status}>
        <Side title={t('fight.sideA')} sides={attackers} hullPct={attackerPct} testId="fight-side-attacker" />
        <Side title={t('fight.sideD')} sides={defenders} hullPct={defenderPct} testId="fight-side-defender" />
        <SheetSection heading={t('fight.log')} data-testid="fight-sheet-fight">
          {instant ? (
            log ? (
              <FightLog log={log} loss={loss} watch={kind === 'NAVY'} />
            ) : null
          ) : mine ? (
            <BattleCard fleetId={mine} />
          ) : read ? (
            <BattleView read={read} nowMs={serverNow} />
          ) : (
            <Skeleton className="mt-2 h-28 w-full" />
          )}
        </SheetSection>
      </div>
    </Tray>
  )
}
