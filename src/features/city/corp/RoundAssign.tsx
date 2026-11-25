import { useState } from 'react'
import { Button, Note, Segmented } from '../../../components/ui'
import { formatFixed, formatInt, formatMiles, formatRealShort } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import type { FleetView } from '../../../lib/rpc'
import { setFleetJob, useJobEdits } from '../../../live/useAwayReport'
import { useRoundQuote, type LitRounds } from '../../../live/useRounds'
import { Foot, FootLine, Step } from './assignParts'
import type { ActionNames } from './workerRows'

// COMBAT AND EXPEDITION ON THE ASSIGN SHEET (owner R3, R5, R6; slide 5). A work of her kind, a sea (served, by the nearest base of each), WHAT A ROUND COSTS there
// (served: stores, crew, ammo, hull; never odds, and no RUN), what she takes, when she stops, and repeat or home. The press sets a job of rounds
// (cmd.set_fleet_job 'round'); the server judges every number and its refusal stands in the foot. A round's yield is not promised.

type Kind = 'combat' | 'sea'
const TAKES = ['crew', 'days', 'ammo'] as const
const STOPS = ['crew', 'days', 'hull', 'rounds'] as const
const TAKE_WORD: Record<(typeof TAKES)[number], TKey> = { crew: 'corp.crew', days: 'corp.days', ammo: 'corp.ammo' }
const STOP_WORD: Record<(typeof STOPS)[number], TKey> = { crew: 'corp.leastCrew', days: 'corp.keepDays', hull: 'corp.hullAt', rounds: 'corp.rounds' }

const num = (s: string | undefined): number | undefined => {
  const v = (s ?? '').trim().replaceAll(',', '')
  return v !== '' && Number.isFinite(Number(v)) ? Number(v) : undefined
}
const numbers = (d: Record<string, string>): Record<string, number> => Object.fromEntries(Object.entries(d).flatMap(([k, v]) => (num(v) === undefined ? [] : [[k, num(v)!]])))

function Box({ word, value, onChange, testid }: { word: string; value: string; onChange: (v: string) => void; testid: string }) {
  return (
    <label className="flex min-w-0 flex-col gap-1 text-t-caption text-ink-muted">
      {word}
      <input
        inputMode="numeric"
        autoComplete="off"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="min-h-11 w-full min-w-0 rounded-control bg-surface px-3 text-base tabular-nums text-ink ring-1 ring-inset ring-edge focus:ring-accent"
        data-testid={testid}
      />
    </label>
  )
}

export function RoundAssign({ fleet, kind, lit, names, onDone }: { fleet: FleetView; kind: Kind; lit: LitRounds; names: ActionNames; onDone: () => void }) {
  const t = useT()
  const key = `rounds:${fleet.id}:${kind}`
  const pending = useJobEdits((s) => s.pending !== null)
  const refused = useJobEdits((s) => s.refused[key] ?? null)
  const work = lit.works.find((w) => w.kind === kind) ?? null
  const seas = lit.seas ?? []
  const [picked, setBase] = useState<string | null>(null)
  const base = picked ?? seas.find((s) => !s.far && (kind === 'sea' || s.pirates))?.base ?? null
  const [take, setTake] = useState<Record<string, string>>({})
  const [stop, setStop] = useState<Record<string, string>>({})
  const [then, setThen] = useState<'repeat' | 'home'>('repeat')
  const [tried, setTried] = useState<string | null>(null)
  const quote = useRoundQuote(fleet.id, work?.open ? work.work : null, base)
  const terms = quote.stale ? null : (quote.view?.terms ?? null)
  const choice = JSON.stringify([base, take, stop, then])
  const refusal = !pending && tried === choice ? refused : null
  const send = async () => {
    if (!work || base === null) return
    const ok = await setFleetJob(fleet.id, 'round', { work: work.work, base, then, ...numbers(take), stop: numbers(stop) }, key)
    if (ok) onDone()
    else setTried(choice)
  }
  const shut = !work ? t('corp.noWork') : !work.open ? t('corp.needsLevel', { n: formatInt(work.level) }) : seas.length === 0 ? t('corp.mustDock') : kind === 'combat' && terms !== null && terms.guns === 0 ? t('corp.noGuns') : null
  const cells: { word: TKey; text: string; key: string }[] = terms
    ? [
        { key: 'food', word: 'corp.food', text: formatFixed(terms.food, 2) },
        { key: 'water', word: 'corp.water', text: formatFixed(terms.water, 2) },
        { key: 'crew', word: 'corp.crew', text: formatFixed(terms.crew, 2) },
        ...(kind === 'combat' ? [{ key: 'ammo', word: 'corp.ammo' as TKey, text: formatFixed(terms.ammo ?? 0, 2) }, { key: 'hull', word: 'corp.hull' as TKey, text: `${formatFixed((terms.hull ?? 0) * 100, 1)}%` }] : []),
      ]
    : []
  return (
    <div data-testid="round-assign" data-kind={kind} data-work={work?.work} data-base={base ?? undefined}>
      {shut !== null && (
        <Note tone="neutral" data-testid="round-shut">
          {shut}
        </Note>
      )}
      {work?.open && seas.length > 0 && (
        <>
          <Step word={t('corp.sea')}>
            <div className="flex flex-col gap-1" data-testid="round-seas">
              {seas.map((s) => {
                const none = kind === 'combat' && !s.pirates
                return (
                  <button
                    key={s.sea}
                    type="button"
                    aria-pressed={s.base === base}
                    disabled={none || s.far}
                    onClick={() => setBase(s.base)}
                    className={`flex min-h-11 w-full items-center justify-between gap-3 rounded-control px-3 text-left transition ${s.base === base ? 'bg-accent-soft ring-1 ring-inset ring-accent' : 'bg-surface hover:bg-surface-2'} disabled:opacity-45`}
                    data-testid="round-sea"
                    data-base={s.base}
                    data-far={s.far}
                  >
                    <span className="min-w-0 break-words text-t-body text-ink">{s.name}</span>
                    <span className="shrink-0 text-t-caption tabular-nums text-ink-muted">{none ? t('corp.noPirates') : s.nm === 0 ? names.port(s.base) : `${s.far ? t('corp.far') : names.port(s.base)} · ${formatMiles(s.nm)} · ${formatRealShort(s.seconds * 1000)}`}</span>
                  </button>
                )
              })}
            </div>
          </Step>
          <Step word={t('corp.take')}>
            <div className="grid grid-cols-3 gap-2" data-testid="round-take-boxes">
              {TAKES.filter((k) => kind === 'combat' || k !== 'ammo').map((k) => (
                <Box key={k} word={t(TAKE_WORD[k])} value={take[k] ?? ''} onChange={(v) => setTake({ ...take, [k]: v })} testid={`round-take-${k}`} />
              ))}
            </div>
          </Step>
          <Step word={t('corp.stopAt')}>
            <div className="grid grid-cols-2 gap-2" data-testid="round-stop-boxes">
              {STOPS.filter((k) => kind === 'combat' || k !== 'hull').map((k) => (
                <Box key={k} word={t(STOP_WORD[k])} value={stop[k] ?? ''} onChange={(v) => setStop({ ...stop, [k]: v })} testid={`round-stop-${k}`} />
              ))}
            </div>
          </Step>
          <Step word={t('corp.end')}>
            <Segmented<'repeat' | 'home'>
              segments={[
                { id: 'repeat', label: t('corp.repeat') },
                { id: 'home', label: t('corp.goHome') },
              ]}
              value={then}
              onChange={setThen}
              label={t('corp.end')}
              columns={2}
            />
          </Step>
        </>
      )}
      <Foot
        refusal={refusal}
        figures={
          shut !== null ? null : terms ? (
            <div data-testid="round-cost" data-hull={terms.hull} data-crew={terms.crew} data-food={terms.food} data-water={terms.water} data-ammo={terms.ammo}>
              <FootLine word={t('corp.perRound')} figure={<span className="text-t-caption tabular-nums text-ink-muted">{formatRealShort(terms.seconds * 1000)}</span>} />
              <p className="flex flex-wrap gap-x-3 text-t-caption tabular-nums text-ink-muted">
                {cells.map((c) => (
                  <span key={c.key} data-cost={c.key}>{`${t(c.word)} ${c.text}`}</span>
                ))}
              </p>
            </div>
          ) : (
            <FootLine word={t('corp.perRound')} figure={null} />
          )
        }
        press={
          <Button variant="primary" className="w-full" busy={pending} disabled={pending || shut !== null || base === null || terms === null} onClick={() => void send()} data-testid="round-go">
            {t('corp.assign')}
          </Button>
        }
      />
    </div>
  )
}
