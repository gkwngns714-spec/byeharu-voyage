import { Icon, Ring, goodIcon, categoryLabel } from '../components/ui'
import { formatInt } from '../lib/format'
import { properName, useLocale, useT } from '../lib/i18n'
import type { LogbookFound, LogbookSale, LogbookSetDone } from '../lib/rpc'
import { portNameOf, useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LOGBOOK ON THE ARRIVAL CARD (0478, roadmap 2026-11-23 slice 9): the "Discovered" moment, "New: Cinnamon · Spice 3 / 22", a set done.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// It prints the server's `logbook` word on the VOYAGE_REPORT and SOLD events (logbookOf.ts) and adds nothing. Dark it is never there.
// THE MOMENT: the harbour's ring fills to her share of its region and pops (the level-up's own `bv-level-pop` and glow), its name large,
// the region's count, a new sea, and what the harbour is known for as the goods' own marks with the first one's name.

const fill = (n: number, of: number) => (of > 0 ? (100 * n) / of : 0)

export function ArrivalFound({ f }: { f: LogbookFound }) {
  const t = useT()
  const locale = useLocale()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const region = f.region ? properName('region', f.region, f.region_name ?? f.region, locale) : null
  const first = f.specialty[0] ? goodByCode[f.specialty[0]] : undefined
  return (
    <div className="relative mt-2 flex items-center gap-3 rounded-control bg-accent-soft p-2" data-testid="arrival-discovered" data-port={f.port} data-n={f.n} data-of={f.of}>
      <span className="bv-level-glow pointer-events-none absolute inset-0 rounded-control" aria-hidden="true" />
      <Ring pct={fill(f.n, f.of)} size={52} label={t('logbook.ring', { what: region ?? portNameOf(portByCode, f.port), n: formatInt(f.n), of: formatInt(f.of) })}>
        <span className="bv-level-pop text-accent">
          <Icon name="anchor" size={24} />
        </span>
      </Ring>
      <div className="min-w-0 flex-1">
        <p className="text-t-caption font-semibold uppercase tracking-wide text-accent">{t('logbook.discovered')}</p>
        <p className="truncate text-t-title font-semibold text-ink">{portNameOf(portByCode, f.port)}</p>
        <p className="flex flex-wrap items-center gap-x-2 text-t-caption tabular-nums text-ink-muted">
          {region ? <span>{`${region} ${t('logbook.of', { n: formatInt(f.n), of: formatInt(f.of) })}`}</span> : null}
          {f.sea_new ? (
            <span className="inline-flex items-center gap-1 text-accent" data-testid="arrival-new-sea">
              <Icon name="waves" size={14} />
              {t('logbook.newSea')}
            </span>
          ) : null}
        </p>
        {f.specialty.length > 0 && (
          <p className="mt-0.5 flex items-center gap-1 text-t-caption text-ink-muted" data-testid="arrival-specialty">
            <span>{t('logbook.knownFor')}</span>
            {f.specialty.map((code) => {
              const g = goodByCode[code]
              return (
                <span key={code} className="text-accent" title={g?.name ?? code}>
                  <Icon name={goodIcon(code, g?.category ?? '')} size={16} />
                </span>
              )
            })}
            {first ? <span className="truncate text-ink">{first.name}</span> : null}
          </p>
        )}
      </div>
    </div>
  )
}

/** "New: Cinnamon · Spice 3 / 22", under the sale that sold it first. */
export function ArrivalNewGood({ s }: { s: LogbookSale }) {
  const t = useT()
  const goodByCode = useWorld((st) => st.goodByCode)
  return (
    <p className="flex items-center gap-1.5 text-t-caption text-accent" data-testid="arrival-new-good" data-good={s.good} data-n={s.n} data-of={s.of}>
      <Icon name={goodIcon(s.good, s.kind)} size={14} />
      <span className="min-w-0 break-words">
        {t('logbook.newGood', { good: goodByCode[s.good]?.name ?? s.good, kind: categoryLabel(s.kind), n: formatInt(s.n), of: formatInt(s.of) })}
      </span>
    </p>
  )
}

/** A set finished on this card: its laurel, its name, the Reputation it paid. */
export function ArrivalSetDone({ s }: { s: LogbookSetDone }) {
  const t = useT()
  const locale = useLocale()
  const name = s.set === 'region' ? properName('region', s.code, s.name, locale) : categoryLabel(s.code)
  return (
    <p className="mt-1 flex items-center gap-1.5 text-t-body text-accent" data-testid="arrival-set-done" data-set={s.set} data-code={s.code} data-rep={s.rep}>
      <span className="bv-level-pop">
        <Icon name="laurel" size={18} />
      </span>
      <span className="min-w-0 flex-1 break-words font-semibold">{t('logbook.setDone', { name })}</span>
      {s.rep > 0 ? <span className="shrink-0 tabular-nums">{t('logbook.setRep', { n: formatInt(s.rep) })}</span> : null}
    </p>
  )
}
