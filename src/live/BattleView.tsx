import { Figure, Note, Row, Segmented, type SegmentSpec } from '../components/ui'
import { formatCountdown, formatDucats, formatInt } from '../lib/format'
import type { BattleRead, BattleStanceWord, Refusal } from '../lib/rpc'
import { useT } from '../lib/i18n'
import { FightLog } from './FightLog'
import { parseFightLog } from './fightLines'

// THE BATTLE CARD'S FACE (0357; src/live/BattleCard.tsx says the whole of it). No clock, no network and no store of
// its own: it draws one read at one instant of the server's clock, so tests/battle.card.spec.ts can render it in Node.
// The log is the one `FightLog`. Nothing here computes a round, a chance or an outcome.
// 0364: A WATCHER'S READ (`world.fight`, `read.watch`) is drawn by this same face: the clock and the log, no stance
// (none is served), no loot and no hands (they are hers alone), and the two sides named, not You and Them.
// 0379: AN ARMADA'S BATTLE (`read.armada`, `read.fleets`): her name, every fleet of hers on her side by its whole name,
// the stance said to act for all of them (the server keeps one stance a side) and, once it is over, each fleet's share
// as the server counted it. A fleet that fights alone serves none of it and the card is what it was.

const STANCES: readonly BattleStanceWord[] = ['FIGHT', 'FLEE', 'PAY']
const RANGE_KEY = { LONG: 'fight.rangeL', MEDIUM: 'fight.rangeM', CLOSE: 'fight.rangeC' } as const

export function BattleView({
  read,
  nowMs,
  refusal = null,
  onStance,
  className = '',
}: {
  read: BattleRead
  /** The server's clock now, in ms. */
  nowMs: number
  refusal?: Refusal | null
  onStance?: (stance: BattleStanceWord) => void
  className?: string
}) {
  const t = useT()
  if (!read.on || !read.battle) return null
  const fighting = read.status === 'FIGHTING'
  const watch = read.watch === true
  const log = parseFightLog(read.log, { open: true })
  const may = STANCES.filter((s) => (read.may ?? []).includes(s))
  const segments: SegmentSpec<BattleStanceWord>[] = may.map((id) => ({
    id,
    label: <span data-testid={`battle-stance-${id}`}>{t(id === 'FLEE' ? 'fight.orderFlee' : id === 'PAY' ? 'fight.orderPay' : 'fight.orderFight')}</span>,
  }))
  const nextMs = read.next_at ? Date.parse(read.next_at) : NaN
  const range = read.next_range === 'LONG' || read.next_range === 'MEDIUM' || read.next_range === 'CLOSE' ? read.next_range : null
  const next = range ? `${t('fight.round')} ${formatInt((read.rounds_done ?? 0) + 1)} · ${t(RANGE_KEY[range])}` : t('fight.boarding')
  const fleets = !watch && read.armada ? (read.fleets ?? []) : []
  const shareOf = (id: string) => (fighting ? undefined : (read.shares ?? []).find((s) => s.fleet === id))

  return (
    <div className={`pb-2 ${className}`} data-testid="battle-card" data-status={read.status} data-stance={read.stance} data-rounds-done={read.rounds_done ?? 0} data-watch={watch || undefined}>
      {!watch && <Row hairline={false} label={t('fight.battle')} value={<span data-testid="battle-foe">{read.foe ?? ''}</span>} />}
      {fleets.length > 0 && (
        <div data-testid="battle-armada" data-fleets={fleets.length}>
          <Row label={t('fight.armada')} value={<span className="break-words text-right" data-testid="battle-armada-name">{read.armada}</span>} />
          {fleets.map((f) => {
            const share = shareOf(f.id)
            return (
              <Row
                key={f.id}
                label={<span className="break-words" data-testid="battle-armada-fleet">{f.name}</span>}
                value={share ? <Figure value={<span data-testid="battle-armada-loot">{formatDucats(share.loot)}</span>} /> : undefined}
                data-testid="battle-armada-row"
                data-lead={f.lead || undefined}
              >
                <span className="break-words text-t-caption text-ink-muted">
                  {t('fight.shipsN', { n: formatInt(f.ships) })}
                  {share && (
                    <span data-testid="battle-armada-share">
                      {' · '}
                      {t('fight.crewLost')} {formatInt(share.crew_lost)} · {t('fight.hullLost')} {formatInt(Math.round(share.hull_lost))}
                    </span>
                  )}
                </span>
              </Row>
            )
          })}
        </div>
      )}
      {read.word && <Row label={t('map.attackFoe')} value={<span data-testid="battle-word" data-word={read.word}>{t(`map.attackWord_${read.word}`)}</span>} />}
      {fighting && (
        <>
          <Row hairline={!watch} label={next} value={<Figure value={<span data-testid="battle-clock">{formatCountdown(nextMs - nowMs)}</span>} />} data-testid="battle-next" />
          {read.stance && segments.length > 1 && (
            <>
              <Row
                hairline={false}
                label={t('fight.stance')}
                value={
                  <span className="text-t-caption text-ink-faint">
                    {fleets.length > 0 && <span data-testid="battle-stance-all">{t('fight.stanceAll')} · </span>}
                    {t('fight.nextRound')}
                  </span>
                }
              />
              <Segmented segments={segments} value={read.stance} onChange={(s) => onStance?.(s)} label={t('fight.stance')} fill columns={segments.length === 3 ? 3 : 2} />
            </>
          )}
        </>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} data-testid="battle-refusal">
          {refusal.sentence}
        </Note>
      )}
      {log && <FightLog log={log} loss={null} watch={watch} />}
      {!fighting && !watch && (
        <>
          <Row label={t('fight.loot')} value={<Figure value={<span data-testid="battle-loot">{formatDucats(read.loot ?? 0)}</span>} />} />
          <Row label={t('fight.crewLost')} value={<Figure value={<span data-testid="battle-crew-lost">{formatInt(read.crew_lost ?? 0)}</span>} />} hairline={!!read.navy} />
          {read.navy && <Row tone="muted" hairline={false} label={read.navy} data-testid="battle-navy" />}
        </>
      )}
    </div>
  )
}
