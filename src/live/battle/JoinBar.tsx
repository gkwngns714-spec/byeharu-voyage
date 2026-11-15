import { useState } from 'react'
import { Button, Segmented } from '../../components/ui'
import { useT } from '../../lib/i18n'
import type { FightCard } from '../../lib/rpc'
import { cmdBattleJoin, type BattleSide } from '../../lib/rpc/battleJoin'
import { joinOffers, joinRefusalKey, type JoinFleet, type JoinOffer } from './joinOffers'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE JOIN BAR (docs/design/tick-combat.md section 8; the owner: joining is OPTIONAL).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Her fleets in the red circle that are free, each with the sides she may take (./joinOffers.ts: in reach, free, no
// side against a player) and one Join button that asks `cmd.battle_join`. The server's answer is one short word: Joined,
// or the refusal's own word (Too far, No PvP, ...). Nothing is offered, and nothing is drawn, when no fleet of hers may
// join. A ship that does not press Join sails on: this bar is the only door, and it stops nothing.
// Shown on the circle's tray (src/live/FightSheet.tsx `actions`) and on the battle screen (BattleScreen `actions`).

export function JoinBar({ card, fleets, nowMs, allCards }: { card: FightCard; fleets: readonly JoinFleet[]; nowMs: number; allCards?: readonly FightCard[] }) {
  const t = useT()
  const offers = joinOffers(card, fleets, nowMs, allCards)
  if (offers.length === 0) return null
  return (
    <div data-testid="join-bar" data-battle={card.id} className="flex flex-col gap-2 py-2">
      <span className="text-t-caption text-ink-muted">{t('join.title')}</span>
      {offers.map((o) => (
        <JoinRow key={o.fleet.id} battleId={card.id} offer={o} />
      ))}
    </div>
  )
}

type Answer = { kind: 'joined' } | { kind: 'refused'; code: string } | null

function JoinRow({ battleId, offer }: { battleId: string; offer: JoinOffer }) {
  const t = useT()
  const [side, setSide] = useState<BattleSide>(offer.sides[0])
  const [busy, setBusy] = useState(false)
  const [answer, setAnswer] = useState<Answer>(null)
  const chosen = offer.sides.includes(side) ? side : offer.sides[0]
  const press = async () => {
    setBusy(true)
    const r = await cmdBattleJoin(battleId, offer.fleet.id, chosen).catch(() => null)
    setBusy(false)
    setAnswer(r?.ok ? { kind: 'joined' } : { kind: 'refused', code: r && !r.ok ? r.refusal.code : 'E_OTHER' })
  }
  return (
    <div data-testid="join-row" data-fleet={offer.fleet.id} data-sides={offer.sides.join(' ')} className="flex flex-col gap-1">
      <span className="break-words text-t-body text-ink" data-testid="join-fleet-name">
        {offer.fleet.name}
      </span>
      <Segmented
        label={t('join.side')}
        segments={offer.sides.map((s) => ({ id: s, label: t(s === 'DEFENDER' ? 'fight.sideD' : 'fight.sideA') }))}
        value={chosen}
        onChange={setSide}
      />
      <div className="flex items-center gap-2">
        <Button variant="primary" busy={busy} disabled={answer?.kind === 'joined'} onClick={() => void press()} data-testid="join-press" data-side={chosen}>
          {t('join.join')}
        </Button>
        {answer && (
          <span
            data-testid="join-answer"
            data-code={answer.kind === 'joined' ? 'OK' : answer.code}
            className={`text-t-caption ${answer.kind === 'joined' ? 'text-ink' : 'text-danger'}`}
          >
            {t(answer.kind === 'joined' ? 'join.joined' : joinRefusalKey(answer.code))}
          </span>
        )}
      </div>
    </div>
  )
}
