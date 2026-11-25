import { Bar, Countdown, Icon, KEEP_WORDS_CLASS, Portrait } from '../../../components/ui'
import { useT } from '../../../lib/i18n'
import { ShipPicture } from '../../../live/ShipPicture'
import { actionWord, figureWord, rateWords, stateWord, type ActionNames, type WorkerRow as Row } from './workerRows'

// ONE WORKER, ONE ROW, ONE FIXED HEIGHT (docs/design/hq-corp-2026-11-24.md C1, C2; slice H1): her picture (her ship with her
// captain's face, or the party's pick), her name, her action in a few words, a progress bar to the next completion with its clock,
// COIN AN HOUR AND XP AN HOUR AS world.workers() SERVES THEM (0496), a counted job's runs left, and her state. A rate the server does
// not serve is not drawn (`basis` none: a fixed run before two whole runs of hers; the Best run), and none is worked out here. Her
// job's tally since she was away is While away's, said once there; the party's terms are her sheet's. The whole row is ONE press: an
// idle worker's opens Assign (the gold edge, "you may act"); any other opens her sheet. The row is the same height idle, working and
// stopped, so a press never re-flows the list.
// 0499: A JOB WHOSE CODE HAS A FIX wears that press's word where an idle row wears Assign ("Repair 736", "Assign", "Storage"), and
// the row's one press does it (WorkerFix.tsx hands both in: `pill`, `onPress`). The row keeps its height.

/** The row's height, on a phone and from `lg`: every state's. */
const HEIGHT = 'h-[104px] lg:h-[72px]'

const TONE = { idle: 'var(--color-accent)', stopped: 'var(--color-danger)', working: 'var(--color-info)' } as const
const DOT = { idle: 'bg-accent', stopped: 'bg-danger', working: 'bg-success' } as const

/** Where the bar stands between its two served stamps, 0 to 100. */
function fillOf(bar: Row['bar'], nowMs: number): number {
  if (!bar) return 0
  return Math.max(0, Math.min(100, ((nowMs - bar.fromMs) / (bar.toMs - bar.fromMs)) * 100))
}

export function WorkerRow({ row, names, nowMs, onPress, pill, fixCost }: { row: Row; names: ActionNames; nowMs: number; onPress: (row: Row) => void; pill?: string; fixCost?: number | null }) {
  const t = useT()
  const idle = row.state === 'idle'
  const act = idle && row.assignable
  const name = row.name ?? t('corp.party')
  const state = t(stateWord(row))
  const rate = rateWords(row.rates, t)
  const left = row.figures.find((f) => f.key === 'left') ?? null
  return (
    <button
      type="button"
      onClick={() => onPress(row)}
      className={`flex w-full flex-col justify-center gap-2 rounded-tile bg-surface px-3 text-left transition hover:bg-surface-2 lg:flex-row lg:items-center lg:gap-4 ${HEIGHT} ${idle ? 'ring-1 ring-inset ring-accent' : ''}`}
      data-testid="corp-worker"
      data-worker={row.id}
      data-kind={row.kind}
      data-state={row.state}
      data-waiting={row.waiting}
      data-wait={row.wait?.code}
      data-action={row.action.kind}
      data-fix={pill ? (row.fix ?? undefined) : undefined}
      data-fix-cost={pill && fixCost != null ? fixCost : undefined}
    >
      <span className="flex min-w-0 items-center gap-3 lg:w-[28rem] lg:shrink-0">
        <span className="relative flex shrink-0">
          {row.kind === 'fleet' ? (
            <ShipPicture code={row.hull} tone={TONE[row.state]} />
          ) : (
            <span className="flex h-10 w-14 items-center justify-center rounded-chip bg-surface-2 text-accent">
              <Icon name="pick" size={24} />
            </span>
          )}
          {row.captain && (
            <span className="absolute -bottom-1 -right-1" title={row.captain.name} data-testid="corp-worker-captain">
              <Portrait role={null} tint="var(--color-surface-2)" seed={row.captain.code} grade={row.captain.grade} size={22} />
            </span>
          )}
        </span>
        <span className="flex min-w-0 flex-1 flex-col">
          <span className={`${KEEP_WORDS_CLASS} text-t-body font-medium leading-tight text-ink`} data-testid="corp-worker-name">
            {name}
          </span>
          <span className="break-words text-t-caption leading-tight text-ink-muted" data-testid="corp-worker-action">
            {actionWord(row.action, t, names)}
          </span>
        </span>
        {pill ? (
          <span className="flex min-h-11 shrink-0 items-center whitespace-nowrap rounded-control bg-accent px-4 text-t-body font-medium tabular-nums text-bg" data-testid="corp-worker-fix">
            {pill}
          </span>
        ) : act ? (
          <span className="flex min-h-11 shrink-0 items-center rounded-control bg-accent px-4 text-t-body font-medium text-bg" data-testid="corp-worker-assign">
            {t('corp.assign')}
          </span>
        ) : (
          <span className="flex min-h-11 shrink-0 items-center gap-1.5 text-t-caption text-ink-muted" data-testid="corp-worker-state">
            <span className={`h-2 w-2 rounded-full ${row.waiting ? 'bg-ink-faint' : DOT[row.state]}`} aria-hidden="true" />
            {state}
          </span>
        )}
      </span>
      {/* the bar's line stands in every state, empty or not, so the row is one height */}
      <span className="flex min-h-5 min-w-0 items-center gap-3 lg:flex-1">
        <span className="min-w-0 flex-1" data-testid="corp-worker-bar" data-on={row.bar !== null} data-fill={fillOf(row.bar, nowMs).toFixed(2)}>
          <Bar pct={fillOf(row.bar, nowMs)} tone={row.state === 'stopped' ? 'danger' : 'accent'} label={name} />
        </span>
        <span className="w-14 shrink-0 text-right text-t-caption tabular-nums text-ink-muted" data-testid="corp-worker-clock">
          {/* under way: the clock to her arrival; waiting for a price (0497): the clock to the server's next ask, as served */}
          {row.bar ? <Countdown untilMs={row.bar.toMs} nowMs={nowMs} /> : row.wait && row.wait.retryMs > nowMs ? <span data-testid="corp-worker-retry"><Countdown untilMs={row.wait.retryMs} nowMs={nowMs} /></span> : null}
        </span>
        <span
          className="flex shrink-0 items-center justify-end gap-3 text-t-caption tabular-nums text-ink lg:w-52"
          data-testid="corp-worker-figures"
          data-basis={row.rates?.basis}
          data-per-hour={row.rates?.perHour ?? undefined}
          data-xp-hour={row.rates?.xpPerHour ?? undefined}
          data-items-hour={row.rates?.itemsPerHour ?? undefined}
        >
          {left && (
            <span title={t(figureWord(left).word)} data-figure="left">
              {t('corp.leftN', { n: figureWord(left).text })}
            </span>
          )}
          {rate.coin !== null && (
            <span className={(row.rates?.perHour ?? 0) < 0 ? 'text-danger' : 'text-success'} data-testid="corp-worker-rate">
              {rate.coin}
            </span>
          )}
          {rate.goods !== null && <span data-testid="corp-worker-goods">{rate.goods}</span>}
          {rate.xp !== null && (
            <span className="text-ink-muted" data-testid="corp-worker-xp">
              {rate.xp}
            </span>
          )}
        </span>
      </span>
    </button>
  )
}
