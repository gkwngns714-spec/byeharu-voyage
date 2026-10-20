import { Bar } from '../../components/ui'
import { fleetHoldBreakdown } from '../../domain/fleet'
import { formatInt, formatPct, tonsWord } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { FleetView } from '../../lib/rpc'

// WHAT THE HOLD IS MADE OF — the owner, 2026-10-20 (docs/OWNER_REQUESTS.md row 179):
//
//     "I told you that cargo space should also consider provision. Right now provision cargo is
//      separate, but I may be wrong. If so, show how much cargo is consist of. % of provision,
//      % of trade goods and so on."
//
// ── THE OWNER WAS WRONG, AND THIS IS THE ANSWER TO WHY ─────────────────────────────────────────
// Provisions have never been a separate pool. `public.fleet_free_hold` (migration 0017:183) is
// `Σ max(0, hold − cargo_tuns − water_t − food_t)`: every barrel of water already costs a tun of
// pepper, which is DESIGN C.3 in one line. What was missing was not the RULE but the READING — the
// hold gauge prints `51 / 60 tons` and says nothing about which of the 51 are barrels. This face
// splits that one figure, and changes no rule: it is `domain/fleet`'s `fleetHoldBreakdown` fold
// over figures the server already serves, drawn with the game's one `Bar`.
//
// ── THREE BARS, NOT ONE SPLIT BAR ──────────────────────────────────────────────────────────────
// `Bar` is deliberately ONE primitive with two forms (Bar.tsx's header), and a three-segment stack
// would be a third. Three bars of the same track compose what exists, keep each share's own figure
// beside it — this is a ledger, not a mood ring — and read correctly on a 390px glass, where a
// stack 4px tall split three ways would not. The tones follow §4.4: `accent` is "yours" for the
// goods, `info` is a neutral fact for the provisions, and the rest of the hold is `neutral`,
// because empty room is neither a gain nor a warning. The gauge beside it still owns the warning:
// `fleet.free_hold` decides that, and nothing here.
// NAMED FOR THE COLUMN FAMILY IT JOINS — `FleetShips` / `FleetCargo` / `FleetStores` / `FleetHold`,
// one face each. It is deliberately NOT called `HoldBreakdown`: that name belongs to the TYPE the
// domain section exports, and tests/duplication.spec.ts fails a screen that re-declares a name a
// section already owns. The data is a `HoldBreakdown`; this is the face that draws one.
export function FleetHold({ fleet }: { fleet: FleetView }) {
  const t = useT()
  const hold = fleetHoldBreakdown(fleet)
  if (hold.totalT <= 0) return null
  const word = tonsWord(hold.totalT)

  const shares = [
    { key: 'goods', share: hold.goodsShare, tons: hold.goodsT, tone: 'accent' as const, label: t('fleets.holdGoods') },
    { key: 'provisions', share: hold.provisionsShare, tons: hold.provisionsT, tone: 'info' as const, label: t('fleets.holdProvisions') },
    { key: 'free', share: hold.freeShare, tons: hold.freeT, tone: 'neutral' as const, label: t('fleets.holdFree') },
  ]

  return (
    <div className="mt-3 space-y-1.5" data-testid="hold-breakdown">
      <p className="text-t-caption text-ink-faint">
        {t('fleets.holdMadeOf', { total: formatInt(hold.totalT), word })}
      </p>
      {shares.map((s) => (
        <span key={s.key} className="flex items-center gap-3 text-t-caption text-ink-faint">
          <span className="w-20 shrink-0">{s.label}</span>
          <Bar
            pct={s.share * 100}
            tone={s.tone}
            label={t('fleets.holdShare', { what: s.label, pct: formatPct(s.share) })}
            figure={
              <span className="tabular-nums">
                {t('fleets.holdFigure', { pct: formatPct(s.share), tons: formatInt(s.tons), word })}
              </span>
            }
            className="min-w-0 flex-1"
          />
        </span>
      ))}
    </div>
  )
}
