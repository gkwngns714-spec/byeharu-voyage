import { Bar, Countdown, Icon, IconDisc, KEEP_WORDS_CLASS, NeedChip, Note, SheetSection, type BarTone } from '../../../components/ui'
import { useShellState } from '../../../app/shellState'
import { formatDucatsDelta, formatInt } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { SeaChoice, SeaOption } from '../../../lib/rpc'
import { SEA_KIND_ICON, SEA_KIND_WORD, seaOptionIcon, seaOptionWord } from '../../../live/seaChoiceOf'
import { chooseAtSea, useSeaPicks } from '../../../live/useSeaChoices'
import { portNameOf, useWorld } from '../../../live/worldStore'

// 0486 (docs/design/roadmap-2026-11-23.md slice 16): A CHOICE AT SEA, AT THE TOP OF HQ. A storm, a wreck or a strange sail her long trip met:
// the event's glyph and word, her ship's whole name and the trip, and the clock to her arrival (when the safe default applies). Each option
// is one press: its glyph and word, its odds as a bar (the good end's share; the rest of the track is the bad end), the coin of each end
// and the expected coin. The best by expected coin wears the trophy and the word Best; the safe default wears the shield. Her pick is
// ringed. Every figure is the server's (world.sea_choices); a refusal stands under the card in the server's words.

/** The bar's tone: what the good end MEANS (green a gain, red a sure loss, neutral nothing lost). */
function endTone(o: SeaOption): BarTone {
  return o.win > 0 ? 'success' : o.win < 0 ? 'danger' : 'neutral'
}

function OptionRow({ c, o, picked, onPick, busy }: { c: SeaChoice; o: SeaOption; picked: boolean; onPick: () => void; busy: boolean }) {
  const t = useT()
  const word = seaOptionWord(o.key)
  const name = word ? t(word) : o.key
  const best = c.best === o.key
  const pct = Math.round(o.p * 100)
  const sure = o.p >= 1 || o.win === o.lose
  return (
    <button
      type="button"
      onClick={onPick}
      disabled={busy}
      aria-pressed={picked}
      className={`flex min-h-11 w-full min-w-0 flex-col gap-1.5 rounded-tile bg-surface p-3 text-left ${picked ? 'ring-2 ring-accent' : best ? 'ring-1 ring-accent/50' : ''}`}
      data-testid="hq-sea-option"
      data-key={o.key}
      data-best={best || undefined}
      data-safe={o.safe || undefined}
      data-picked={picked || undefined}
    >
      <span className="flex flex-wrap items-center gap-2">
        <Icon name={seaOptionIcon(o.key)} size={18} aria-hidden />
        <span className={`${KEEP_WORDS_CLASS} min-w-0 flex-1 text-t-label text-ink`}>{name}</span>
        {best && (
          <NeedChip icon="trophy" tone="accent">
            {t('hq.seaBest')}
          </NeedChip>
        )}
        {o.safe && (
          <NeedChip icon="shield" tone="info">
            {t('hq.seaSafe')}
          </NeedChip>
        )}
        {picked && (
          <NeedChip icon="helm" tone="success">
            {t('hq.seaPicked')}
          </NeedChip>
        )}
      </span>
      <Bar pct={pct} tone={endTone(o)} label={t('hq.seaOdds', { n: formatInt(pct) })} figure={<span className="text-t-caption tabular-nums text-ink-muted">{formatInt(pct)}%</span>} />
      <span className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 text-t-caption tabular-nums">
        <span className={o.win > 0 ? 'text-success' : o.win < 0 ? 'text-danger' : 'text-ink-muted'} aria-label={t('hq.seaGood', { n: formatDucatsDelta(o.win) })}>
          {formatDucatsDelta(o.win)}
        </span>
        {!sure && (
          <span className={o.lose < 0 ? 'text-danger' : 'text-ink-muted'} aria-label={t('hq.seaBad', { n: formatDucatsDelta(o.lose) })}>
            {formatDucatsDelta(o.lose)}
          </span>
        )}
        <span className="ml-auto text-ink-muted">{t('hq.seaExpected', { n: formatDucatsDelta(o.ev) })}</span>
      </span>
    </button>
  )
}

export function SeaChoiceCard({ c }: { c: SeaChoice }) {
  const t = useT()
  const { nowMs } = useShellState()
  const portByCode = useWorld((s) => s.portByCode)
  // her ship is named only when she has more than one fleet (with one, her worker row has named her)
  const manyFleets = useWorld((s) => s.fleets.length > 1)
  const busy = useSeaPicks((s) => s.pending !== null)
  const refusal = useSeaPicks((s) => s.refused[c.id] ?? null)
  const trip = c.from && c.to ? `${portNameOf(portByCode, c.from)} → ${portNameOf(portByCode, c.to)}` : null
  return (
    <SheetSection
      heading={t(SEA_KIND_WORD[c.kind])}
      trailing={
        <span className="flex items-center gap-1.5 text-t-caption text-ink-muted">
          {t('hq.seaCloses')}
          <Countdown untilMs={Date.parse(c.deadline)} nowMs={nowMs} className="tabular-nums text-info" />
        </span>
      }
      data-testid="hq-sea"
      data-kind={c.kind}
      data-choice={c.id}
    >
      <div className="mb-3 flex items-center gap-3">
        <IconDisc name={SEA_KIND_ICON[c.kind]} tone={c.kind === 'storm' ? 'warning' : c.kind === 'sail' ? 'danger' : 'info'} label={t(SEA_KIND_WORD[c.kind])} />
        <span className="flex min-w-0 flex-col">
          {manyFleets && <span className={`${KEEP_WORDS_CLASS} text-t-label text-ink`}>{c.fleet_name}</span>}
          {trip && <span className={`${KEEP_WORDS_CLASS} text-t-caption text-ink-muted`}>{trip}</span>}
        </span>
      </div>
      <ol className="grid grid-cols-1 gap-2 md:grid-cols-3" data-testid="hq-sea-options">
        {c.options.map((o) => (
          <li key={o.key} className="min-w-0">
            <OptionRow c={c} o={o} picked={c.chosen === o.key} busy={busy} onPick={() => void chooseAtSea(c.id, o.key)} />
          </li>
        ))}
      </ol>
      {!c.chosen && (
        <p className="mt-2 flex items-center gap-1.5 text-t-caption text-ink-muted" data-testid="hq-sea-default">
          <Icon name="shield" size={14} aria-hidden />
          {t('hq.seaDefault')} · {t(seaOptionWord(c.options.find((o) => o.safe)?.key ?? '') ?? 'hq.seaSafe')}
        </p>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="hq-sea-refusal">
          {refusal.sentence}
        </Note>
      )}
    </SheetSection>
  )
}
