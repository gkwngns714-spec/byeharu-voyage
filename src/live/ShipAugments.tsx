import { useState } from 'react'
import { Button, Note, Clip } from '../components/ui'
import { cmdAugmentFitting } from '../lib/rpc'
import type { Refusal, ShipRack, ShipSet } from '../lib/rpc'
import { useWorld } from './worldStore'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HER SETS AND HER PERKS (0163, docs/SHIPS_AND_SKILLS.md S16 — §6.6 perks, §6.7 sets).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// SET PROGRESS: each line whose pieces she carries (`ship.sets`, world.ship_set_card) — the set's name,
// pieces of 4, and every bonus with whether it is in force, in the server's words. Drawn only when served.
//
// PERKS: every fitting that carries a perk prints the server's words; on one of YOUR ships, docked, a
// fitting the server offers perks for (`perk_options`, world.ship_racks) gets the perk picker — the player
// CHOOSES a perk and a rank (no lottery, §6.6); the press is cmd.augment_fitting and the server's refusal
// (kits, skill, workshop, rack) is printed as served. Nothing here decides what fits or what it costs.

export function ShipAugments({
  shipId,
  racks,
  sets,
  docked,
}: {
  /** One of YOUR ships: her id (the press names it). Null for a merchant's hull — read-only. */
  shipId: string | null
  racks: readonly ShipRack[] | undefined
  sets: readonly ShipSet[] | undefined
  /** One of YOUR ships, docked: the picker is drawn. Omitted for a merchant's hull or at sea. */
  docked?: boolean
}) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const [open, setOpen] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [done, setDone] = useState<string | null>(null)
  const canAugment = shipId !== null && docked === true
  const units = (racks ?? []).flatMap((r) => r.fitted).filter((u) => (u.perks?.length ?? 0) > 0 || (canAugment && (u.perk_options?.length ?? 0) > 0))
  if ((sets?.length ?? 0) === 0 && units.length === 0) return null

  const augment = (item: string, perk: string, rank: number) => {
    if (busy || shipId === null) return
    setBusy(true)
    setRefusal(null)
    setDone(null)
    void (async () => {
      const r = await cmdAugmentFitting(shipId, item, perk, rank)
      setBusy(false)
      if (r.ok) {
        setOpen(null)
        setDone(r.value.sentence)
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  return (
    <section data-testid="ship-augments">
      {(sets ?? []).map((s) => (
        <div key={s.line} className="pt-4" data-testid={`ship-set-${s.line}`}>
          <div className="flex items-baseline justify-between pb-1.5">
            <h3 className="text-t-caption uppercase tracking-wider text-ink-faint">{t('yard.set', { name: s.name })}</h3>
            <span className="text-t-caption tabular-nums text-ink-faint">{t('yard.pieces', { n: s.pieces, of: s.of })}</span>
          </div>
          <ul className="flex flex-col gap-0.5">
            {s.bonuses.map((b) => (
              <li key={`${b.pieces}-${b.words}`} className={`text-t-label ${b.in_force ? 'text-accent' : 'text-ink-faint'}`}>
                {t('yard.piecesBonus', { n: b.pieces, words: b.words })}
              </li>
            ))}
          </ul>
        </div>
      ))}
      {units.length > 0 && (
        <div className="pt-4">
          <h3 className="pb-2 text-t-caption uppercase tracking-wider text-ink-faint">{t('yard.perks')}</h3>
          <ul className="flex flex-col gap-1.5">
            {units.map((u, i) => {
              const key = `${u.code}-${i}`
              return (
                <li key={key} className="rounded-control bg-surface-2 px-3 py-1.5" data-testid={`perk-unit-${u.code}`}>
                  <div className="flex items-center justify-between gap-3">
                    <Clip className="text-t-label text-ink">{u.name}</Clip>
                    {canAugment && (u.perk_options?.length ?? 0) > 0 && (
                      <Button variant="quiet" size="sm" disabled={busy} onClick={() => setOpen(open === key ? null : key)}
                        data-testid={`perk-open-${u.code}`}>
                        {t('yard.augment')}
                      </Button>
                    )}
                  </div>
                  {(u.perks ?? []).map((p) => (
                    <div key={p.code} className="text-t-caption text-accent">{p.words}</div>
                  ))}
                  {open === key && (
                    <div className="mt-2 flex flex-col gap-1.5" data-testid={`perk-pick-${u.code}`}>
                      {(u.perk_options ?? []).map((o) => (
                        <div key={o.code}>
                          <div className="text-t-caption text-ink-faint">{`${o.word} · ${o.kit}`}</div>
                          <div className="flex flex-wrap gap-1">
                            {o.ranks.map((words, r) => (
                              <Button key={words} variant="secondary" size="sm" disabled={busy}
                                onClick={() => augment(u.code, o.code, r + 1)} data-testid={`perk-pick-${o.code}-${r + 1}`}>
                                {words}
                              </Button>
                            ))}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </li>
              )
            })}
          </ul>
        </div>
      )}
      {done && <Note tone="success" className="mt-2">{done}</Note>}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2">
          {refusal.sentence}
        </Note>
      )}
    </section>
  )
}
