import { useState } from 'react'
import { Button, Countdown, Note, Row, SheetSection } from '../../../components/ui'
import { formatDucats, formatFixed, formatInt } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import { cmdArtifactReport, cmdRoundHome, type Refusal, type RoundRun, type RpcResult } from '../../../lib/rpc'
import { carried, litRounds, runOf, salvageOf, useRounds } from '../../../live/useRounds'
import { useWorld } from '../../../live/worldStore'

// A FLEET'S RUN ON HER SHEET AND WHILE AWAY (0518 to 0524): the rounds done and the next one's clock, what a round costs, what she has in hand, the last 20 lines
// of the log, Come home; her artifacts, and Give where she lies in her capital. Every figure is the served one.

const ENDED: Record<string, TKey> = {
  food: 'corp.endFood',
  water: 'corp.endWater',
  crew: 'corp.endCrew',
  ammo: 'corp.endAmmo',
  hull: 'corp.endHull',
  beaten: 'corp.endBeaten',
  rounds: 'corp.endRounds',
  cap: 'corp.endCap',
  called: 'corp.endCalled',
}
const TIER: Record<string, TKey> = { uncommon: 'corp.uncommon', rare: 'corp.rare', very_rare: 'corp.veryRare' }

/** The log: one line a round, the newest first, in a window of one height whatever it holds. */
export function RoundLog({ run }: { run: RoundRun }) {
  const t = useT()
  return (
    <ol className="h-56 overflow-y-auto rounded-control bg-surface px-3 py-1" data-testid="round-log" data-lines={run.log.length}>
      {run.log.length === 0 && <li className="flex h-8 items-center text-t-caption text-ink-faint">{t('corp.noLines')}</li>}
      {[...run.log].reverse().map((l) => (
        <li key={l.r} className="flex h-8 items-center justify-between gap-3 text-t-caption tabular-nums" data-testid="round-log-line" data-round={l.r}>
          <span className={l.won === 0 ? 'text-danger' : 'text-ink'}>
            {t('corp.roundN', { n: formatInt(l.r) })}
            {l.won !== undefined && ` · ${t(l.won === 1 ? 'corp.won' : 'corp.lost')}`}
          </span>
          <span className="flex gap-3 text-ink-muted">
            {l.hull !== undefined && <span>{`${t('corp.hull')} −${formatFixed(l.hull * 100, 1)}%`}</span>}
            <span>{`${t('corp.crew')} −${formatInt(l.crew)}`}</span>
          </span>
        </li>
      ))}
    </ol>
  )
}

/** What a run has in hand, as served; none: null. */
export function RoundTake({ run }: { run: RoundRun }) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  const gold = carried(run, 'gold')
  const rp = carried(run, 'rp')
  const due = carried(run, 'gold_due')
  const parts = salvageOf(run)
  if (!gold && !rp && !due && parts.length === 0) return null
  return (
    <p className="flex flex-wrap gap-x-3 gap-y-1 text-t-caption tabular-nums text-ink-muted" data-testid="round-take">
      {gold ? <span className="text-success">{`${t('corp.gold')} ${formatDucats(gold)}`}</span> : null}
      {due ? <span>{`${t('corp.goldDue')} ${formatDucats(due)}`}</span> : null}
      {rp ? <span>{`${t('corp.reputation')} ${formatInt(rp)}`}</span> : null}
      {parts.length > 0 && <span data-testid="round-wrecks">{`${t('corp.wrecks')}: ${parts.map((p) => `${goodByCode[p.good]?.name ?? p.good} ${formatInt(p.qty)}`).join(', ')}`}</span>}
    </p>
  )
}

export function RoundCard({ fleet, nowMs }: { fleet: string; nowMs: number }) {
  const t = useT()
  const lit = litRounds(useRounds(null).view)
  const refresh = useWorld((s) => s.refresh)
  const view = useWorld((s) => s.fleets.find((f) => f.id === fleet) ?? null)
  const [busy, setBusy] = useState<'home' | 'give' | null>(null)
  const [refused, setRefused] = useState<Refusal | null>(null)
  const run = runOf(lit, fleet)
  const kept = lit?.artifacts?.kept.filter((a) => a.fleet === fleet) ?? []
  if (!lit || (!run && kept.length === 0)) return null
  const press = async (kind: 'home' | 'give', door: () => Promise<RpcResult<unknown>>) => {
    setBusy(kind)
    setRefused(null)
    const r = await door()
    if (r.ok) await refresh()
    else setRefused(r.refusal)
    setBusy(null)
  }
  return (
    <SheetSection heading={t('corp.rounds')} trailing={run ? <span className="text-t-caption text-ink-muted">{run.sea}</span> : undefined}>
      <div className="flex flex-col gap-2" data-testid="round-card" data-state={run?.state} data-rounds={run?.rounds}>
        {run && (
          <>
            <Row
              label={t(run.kind === 'combat' ? 'corp.combat' : 'corp.expedition')}
              value={
                <span className="flex items-center gap-3 tabular-nums">
                  <span data-testid="round-count">{`${formatInt(run.rounds)}${run.most !== null ? ` / ${formatInt(run.most)}` : ''}`}</span>
                  {run.state === 'out' && run.next_at ? <Countdown untilMs={Date.parse(run.next_at)} nowMs={nowMs} /> : <span className="text-ink-muted">{t(run.state === 'home' && run.ended && ENDED[run.ended] ? ENDED[run.ended] : 'corp.endCalled')}</span>}
                </span>
              }
            />
            <RoundTake run={run} />
            <RoundLog run={run} />
            {run.state === 'out' && (
              <Button variant="secondary" className="w-full" busy={busy === 'home'} disabled={busy !== null} onClick={() => void press('home', () => cmdRoundHome(fleet))} data-testid="round-home">
                {t('corp.comeHome')}
              </Button>
            )}
          </>
        )}
        {kept.length > 0 && (
          <div className="flex flex-col gap-2" data-testid="round-artifacts">
            <span className="text-t-caption text-ink-muted">{t('corp.artifacts')}</span>
            {kept.map((a) => {
              const worth = lit.artifacts?.tiers.find((x) => x.tier === a.tier)
              return <Row key={a.tier} label={`${t(TIER[a.tier])} ×${formatInt(a.qty)}`} value={worth ? <span className="tabular-nums">{`${formatDucats(worth.gold)} · ${t('corp.reputation')} ${formatInt(worth.rp)}`}</span> : undefined} />
            })}
            {/* the server says where they are taken; she must lie in a harbour */}
            <Button variant="primary" className="w-full" busy={busy === 'give'} disabled={busy !== null || view?.status !== 'DOCKED'} onClick={() => void press('give', () => cmdArtifactReport(fleet))} data-testid="round-give">
              {t('corp.giveArtifacts')}
            </Button>
          </div>
        )}
        <div className="min-h-6">
          {refused && (
            <Note tone="danger" code={refused.code} figures={refused.figures} data-testid="round-refusal">
              {refused.sentence}
            </Note>
          )}
        </div>
      </div>
    </SheetSection>
  )
}

/** While away: each fleet whose job is rounds, what her run gave and its log. One read, asked only while such a job stands. */
export function RoundsAway({ fleet }: { fleet: string }) {
  const run = runOf(litRounds(useRounds(null).view), fleet)
  const t = useT()
  const [open, setOpen] = useState(false)
  if (!run) return null
  return (
    <div className="flex flex-col gap-1 pl-8" data-testid="rounds-away" data-fleet={fleet}>
      <button type="button" aria-expanded={open} onClick={() => setOpen(!open)} className="flex min-h-11 w-full items-center justify-between gap-3 text-left text-t-caption text-ink-muted" data-testid="rounds-away-open">
        <span className="tabular-nums">{`${run.sea} · ${t('corp.roundsN', { n: formatInt(run.rounds) })}${run.state === 'home' && run.ended && ENDED[run.ended] ? ` · ${t(ENDED[run.ended])}` : ''}`}</span>
        <span>{t('corp.log')}</span>
      </button>
      <RoundTake run={run} />
      {open && <RoundLog run={run} />}
    </div>
  )
}
