import { useState } from 'react'
import { Button } from '../../components/ui'
import { useT } from '../../lib/i18n'
import type { FightCard } from '../../lib/rpc'
import { cmdBattleJoin, type BattleSide } from '../../lib/rpc/battleJoin'
import { joinOffers, joinRefusalKey, type JoinFleet, type JoinOffer } from './joinOffers'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE JOIN BUTTON (docs/design/tick-combat.md section 8; the owner: joining is OPTIONAL; 2026-11-15: "simplify all").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE button, Join, drawn only when a fleet of hers may join (./joinOffers.ts: in reach, free, no side against a
// player). A press opens the choice: one button for each fleet and side she may take (the fleet's name, and the side when
// there is more than one). With a single fleet and a single side there is nothing to choose, so the press joins at once.
// The server's answer is one short word: Joined, or the refusal's own word (Too far, No PvP, ...). A ship that does not
// press Join sails on: this is the only door, and it stops nothing.
// Shown on the circle's tray (src/live/FightSheet.tsx `actions`) and on the battle screen (BattleScreen `actions`).

type Answer = { kind: 'joined' } | { kind: 'refused'; code: string } | null

export function JoinBar({
  card,
  fleets,
  nowMs,
  allCards,
  startOpen = false,
}: {
  card: FightCard
  fleets: readonly JoinFleet[]
  nowMs: number
  allCards?: readonly FightCard[]
  /** the choice already open (the spec's server render) */
  startOpen?: boolean
}) {
  const t = useT()
  const offers = joinOffers(card, fleets, nowMs, allCards)
  const [open, setOpen] = useState(startOpen)
  const [busy, setBusy] = useState(false)
  const [answer, setAnswer] = useState<Answer>(null)
  if (offers.length === 0 && !answer) return null
  const choices = offers.flatMap((o) => o.sides.map((side) => ({ offer: o, side })))
  const manyFleets = offers.length > 1
  const manySides = offers.some((o) => o.sides.length > 1)

  const join = async (offer: JoinOffer, side: BattleSide) => {
    setBusy(true)
    const r = await cmdBattleJoin(card.id, offer.fleet.id, side).catch(() => null)
    setBusy(false)
    setOpen(false)
    setAnswer(r?.ok ? { kind: 'joined' } : { kind: 'refused', code: r && !r.ok ? r.refusal.code : 'E_OTHER' })
  }
  const press = () => {
    if (choices.length === 1) void join(choices[0].offer, choices[0].side)
    else setOpen(true)
  }

  return (
    <div data-testid="join-bar" data-battle={card.id} data-fleets={offers.map((o) => o.fleet.id).join(' ')} className="flex flex-wrap items-center gap-2">
      {answer?.kind !== 'joined' && !open && choices.length > 0 && (
        <Button variant="primary" busy={busy} onClick={press} data-testid="join-open">
          {t('join.join')}
        </Button>
      )}
      {open &&
        choices.map(({ offer, side }) => (
          <Button
            key={`${offer.fleet.id}:${side}`}
            variant="primary"
            disabled={busy}
            onClick={() => void join(offer, side)}
            data-testid="join-press"
            data-fleet={offer.fleet.id}
            data-side={side}
          >
            <span className="break-words">
              {[manyFleets || !manySides ? offer.fleet.name : null, manySides ? t(side === 'DEFENDER' ? 'fight.sideD' : 'fight.sideA') : null].filter(Boolean).join(' · ')}
            </span>
          </Button>
        ))}
      {answer && (
        <span data-testid="join-answer" data-code={answer.kind === 'joined' ? 'OK' : answer.code} className={`text-t-label ${answer.kind === 'joined' ? 'text-ink' : 'text-danger'}`}>
          {t(answer.kind === 'joined' ? 'join.joined' : joinRefusalKey(answer.code))}
        </span>
      )}
    </div>
  )
}
