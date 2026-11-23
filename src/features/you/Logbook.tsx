import { useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { Card, Flag, Icon, MasteryRing, Ring, Segmented, Skeleton, goodIcon, categoryLabel, masteredTone, type IconName } from '../../components/ui'
import { useMasteryLevels } from '../../live/goodsMastery'
import { Portrait } from '../../components/ui/Portrait'
import { ShipArtIcon } from '../../live/battle/ShipArt'
import { shipTierOf } from '../../chart'
import { formatInt } from '../../lib/format'
import { properName, useLocale, useT, type Locale, type TKey } from '../../lib/i18n'
import type { LogbookView } from '../../lib/rpc'
import { nationWordOf, useWorld } from '../../live/worldStore'
import { tabWord } from '../../app/navTabs'
import { readyLogbook, useLogbook } from './useLogbook'

// THE LOGBOOK (0478, roadmap 2026-11-23 slice 9: "The logbook: discovery and collections"; RS3's collection log, Uncharted Waters'
// discoveries). A page of counts drawn as collection grids: five rings for the totals, then one collection at a time, each set a card
// with its ring and a grid of slots. A slot she has is lit (a harbour by its country's flag, a good by its own mark, a hull by her
// picture, a captain by his face); one she has not is its silhouette. Few words: the rings and the slots say it.
//
// ONE READ, NOTHING WORKED OUT: `world.logbook()` serves every count, every list in order and what she has seen. Dark it serves
// {on: false} and nothing here is drawn, the door on You included. Names come from the world the client already holds (ports, goods,
// ship classes) in the viewer's language; a code the client does not know is drawn by its code.

type Ready = Extract<LogbookView, { company: true }>
type Collection = 'harbours' | 'goods' | 'hulls' | 'captains'

/** The logbook page's route: the one spelling every door to it uses. */
export const LOGBOOK_ROUTE = '/logbook'

const TOTALS: readonly { key: keyof Ready['totals']; icon: IconName; word: TKey }[] = [
  { key: 'harbours', icon: 'anchor', word: 'logbook.harbours' },
  { key: 'goods', icon: 'crate', word: 'logbook.goods' },
  { key: 'seas', icon: 'waves', word: 'logbook.seas' },
  { key: 'hulls', icon: 'ship', word: 'logbook.hulls' },
  { key: 'captains', icon: 'person', word: 'logbook.captains' },
]

const fill = (n: number, of: number) => (of > 0 ? (100 * n) / of : 0)

/** The five totals (and the sets) as rings: her count in the ring's middle, of how many under it. */
function TotalRings({ v, size }: { v: Ready; size: number }) {
  const t = useT()
  const cells: { key: string; icon: IconName; word: string; n: number; of: number }[] = [
    ...TOTALS.map((x) => ({ key: x.key, icon: x.icon, word: t(x.word), n: v.totals[x.key].n, of: v.totals[x.key].of })),
    { key: 'sets', icon: 'laurel', word: t('logbook.sets'), n: v.sets.done, of: v.sets.of },
  ]
  return (
    <span className="grid grid-cols-3 gap-x-1 gap-y-3 sm:grid-cols-6" data-testid="logbook-totals">
      {cells.map((c) => (
        <span key={c.key} className="flex min-w-0 flex-col items-center gap-1" data-testid={`logbook-total-${c.key}`} data-n={c.n} data-of={c.of}>
          <Ring pct={fill(c.n, c.of)} size={size} label={t('logbook.ring', { what: c.word, n: formatInt(c.n), of: formatInt(c.of) })}>
            <span className={c.n > 0 ? 'text-accent' : 'text-ink-faint'}>
              <Icon name={c.icon} size={Math.round(size * 0.45)} />
            </span>
          </Ring>
          <span className="text-t-title leading-none tabular-nums text-ink">{formatInt(c.n)}</span>
          <span className="text-t-caption leading-none tabular-nums text-ink-muted">/ {formatInt(c.of)}</span>
          <span className="max-w-full truncate text-t-caption text-ink-muted">{c.word}</span>
        </span>
      ))}
    </span>
  )
}

/** THE DOOR ON YOU: the totals as rings; the card is one press to the page. Dark (or no company): nothing at all. */
export function LogbookDoor() {
  const t = useT()
  const locale = useLocale()
  const v = readyLogbook(useLogbook().view)
  if (!v) return null
  return (
    <Card icon="compass" title={t('logbook.title')} aside={<span className="text-ink-muted"><Icon name="chevron" size={16} /></span>} data-testid="you-logbook">
      <Link to={LOGBOOK_ROUTE} className="-m-1 block min-h-11 rounded-control p-1 hover:bg-surface-2" aria-label={tabWord(locale, LOGBOOK_ROUTE)} data-testid="you-logbook-door">
        <TotalRings v={v} size={36} />
      </Link>
    </Card>
  )
}

/** THE PAGE'S BODY: the totals, the choice of collection, and its sets. */
export function LogbookBody() {
  const t = useT()
  const read = useLogbook()
  const v = readyLogbook(read.view)
  const [shown, setShown] = useState<Collection>('harbours')
  if (!v) {
    return <Card data-testid="logbook">{read.loading ? <Skeleton className="h-[200px] w-full" /> : null}</Card>
  }
  return (
    <div className="flex min-w-0 flex-col gap-3" data-testid="logbook">
      <Card>
        <TotalRings v={v} size={52} />
      </Card>
      <Segmented<Collection>
        label={t('logbook.title')}
        fill
        value={shown}
        onChange={setShown}
        segments={[
          { id: 'harbours', label: t('logbook.harbours') },
          { id: 'goods', label: t('logbook.goods') },
          { id: 'hulls', label: t('logbook.hulls') },
          { id: 'captains', label: t('logbook.captains') },
        ]}
      />
      {shown === 'harbours' && <HarbourSets v={v} />}
      {shown === 'goods' && <GoodSets v={v} />}
      {shown === 'hulls' && <HullSets v={v} />}
      {shown === 'captains' && <CaptainSet v={v} />}
    </div>
  )
}

/** One set: its ring with her count, its name, Done or what finishing it pays; then its slots. */
function SetCard({
  code,
  name,
  n,
  of,
  done,
  reward,
  children,
}: {
  code: string
  name: string
  n: number
  of: number
  done?: boolean
  reward?: string | null
  children: ReactNode
}) {
  const t = useT()
  return (
    <Card compact data-testid="logbook-set" data-code={code} data-n={n} data-of={of} data-done={done ? 'true' : 'false'}>
      <div className="mb-2 flex items-center gap-3">
        <Ring pct={fill(n, of)} size={44} label={t('logbook.ring', { what: name, n: formatInt(n), of: formatInt(of) })} className={done ? 'bv-level-pop' : ''}>
          {done ? (
            <span className="text-accent">
              <Icon name="laurel" size={20} />
            </span>
          ) : (
            <span className="text-t-label font-semibold tabular-nums text-ink">{formatInt(n)}</span>
          )}
        </Ring>
        <div className="min-w-0 flex-1">
          <p className="truncate text-t-label font-semibold text-ink">{name}</p>
          <p className="text-t-caption tabular-nums text-ink-muted">
            {t('logbook.of', { n: formatInt(n), of: formatInt(of) })}
            {done ? <span className="ml-2 font-semibold text-accent">{t('logbook.done')}</span> : null}
          </p>
          {!done && reward ? <p className="text-t-caption text-ink-faint">{reward}</p> : null}
        </div>
      </div>
      <div className="grid grid-cols-[repeat(auto-fill,minmax(2.5rem,1fr))] gap-1">{children}</div>
    </Card>
  )
}

/** One slot: lit when she has it, a silhouette when not. Its name is its tooltip and its accessible name. 0479: a good's slot carries
 *  her mastery level (`data-level`) when she has sold it and the ladder is lit. */
function Slot({ seen, name, level, children }: { seen: boolean; name: string; level?: number; children: ReactNode }) {
  return (
    <span
      role="img"
      aria-label={name}
      title={name}
      data-testid="logbook-slot"
      data-seen={seen ? 'true' : 'false'}
      data-level={level}
      className={`flex aspect-square items-center justify-center overflow-hidden rounded-control ${
        seen ? 'bg-accent-soft text-accent ring-1 ring-accent/40' : 'bg-surface-2 text-ink-faint'
      }`}
    >
      <span className={seen ? '' : 'opacity-35 [filter:grayscale(1)_brightness(0.4)]'} aria-hidden="true">
        {children}
      </span>
    </span>
  )
}

const pctWord = (share: number) => formatInt(Math.round(share * 100))

function HarbourSets({ v }: { v: Ready }) {
  const t = useT()
  const locale = useLocale()
  const portByCode = useWorld((s) => s.portByCode)
  const seen = new Set(v.seen.harbours)
  const seas = new Set(v.seen.seas)
  const reward = t('logbook.reward', { rep: formatInt(v.reward.rep), pct: pctWord(v.reward.region_cut) })
  return (
    <>
      <Card compact data-testid="logbook-seas" data-n={v.totals.seas.n} data-of={v.totals.seas.of}>
        <div className="mb-2 flex items-center gap-2 text-t-label font-semibold text-ink">
          <span className="text-accent">
            <Icon name="waves" size={18} />
          </span>
          {t('logbook.seas')}
          <span className="font-normal tabular-nums text-ink-muted">{t('logbook.of', { n: formatInt(v.totals.seas.n), of: formatInt(v.totals.seas.of) })}</span>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {v.seas.map((s) => {
            const name = properName('sea', s.name, s.name, locale)
            const lit = seas.has(s.code)
            return (
              <span
                key={s.code}
                role="img"
                aria-label={name}
                title={name}
                data-testid="logbook-sea"
                data-seen={lit ? 'true' : 'false'}
                className={`h-3 w-3 rounded-full ${lit ? 'bg-accent' : 'bg-surface-2 ring-1 ring-ink-faint/30'}`}
              />
            )
          })}
        </div>
      </Card>
      {v.regions.map((r) => (
        <SetCard key={r.code} code={r.code} name={properName('region', r.code, r.name, locale)} n={r.n} of={r.of} done={r.done} reward={reward}>
          {r.harbours.map((code) => {
            const p = portByCode[code]
            const lit = seen.has(code)
            const name = p?.name ?? code
            return (
              <Slot key={code} seen={lit} name={name}>
                {lit && p?.nation ? <Flag code={p.nation} name={nationWordOf(p.nation)} size="title" /> : <Icon name="anchor" size={20} />}
              </Slot>
            )
          })}
        </SetCard>
      ))}
    </>
  )
}

function GoodSets({ v }: { v: Ready }) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  // 0479 (goods mastery, roadmap slice 11): a good she has sold wears its mastery level as a ring round its mark (dark: no ring)
  const mastery = useMasteryLevels()
  const seen = new Set(v.seen.goods)
  const reward = t('logbook.rewardKind', { rep: formatInt(v.reward.rep), pct: pctWord(v.reward.kind_cut) })
  return (
    <>
      {v.kinds.map((k) => (
        <SetCard key={k.code} code={k.code} name={categoryLabel(k.code)} n={k.n} of={k.of} done={k.done} reward={reward}>
          {k.goods.map((code) => {
            const name = goodByCode[code]?.name ?? code
            const m = seen.has(code) ? mastery.of(code) : null
            const mark = <Icon name={goodIcon(code, k.code)} size={m ? 18 : 22} />
            return (
              <Slot
                key={code}
                seen={seen.has(code)}
                name={m ? `${name} · ${t('mastery.up', { n: m.level })}` : name}
                level={m ? m.level : undefined}
              >
                {m ? (
                  <MasteryRing level={m.level} top={mastery.top} size={34} label={t('mastery.ring', { good: name, n: m.level, top: mastery.top })}>
                    <span className={masteredTone(m.level >= mastery.top, 'text-accent')}>{mark}</span>
                  </MasteryRing>
                ) : (
                  mark
                )}
              </Slot>
            )
          })}
        </SetCard>
      ))}
    </>
  )
}

const FAMILY_WORD: Readonly<Record<string, TKey>> = {
  Western: 'logbook.famWestern',
  'East Asian': 'logbook.famEastAsian',
  'Indian Ocean': 'logbook.famIndian',
  Mediterranean: 'logbook.famMed',
}

function familyWord(t: ReturnType<typeof useT>, family: string): string {
  const k = FAMILY_WORD[family]
  return k ? t(k) : family
}

function hullName(locale: Locale, name: string): string {
  return properName('hull', name, name, locale)
}

function HullSets({ v }: { v: Ready }) {
  const t = useT()
  const locale = useLocale()
  const classes = useWorld((s) => s.snapshot?.ship_classes)
  const byCode = new Map((classes ?? []).map((c) => [c.code, c]))
  const seen = new Set(v.seen.hulls)
  return (
    <>
      {v.families.map((f) => (
        <SetCard key={f.code} code={f.code} name={familyWord(t, f.code)} n={f.n} of={f.of}>
          {f.hulls.map((code) => {
            const c = byCode.get(code)
            const lit = seen.has(code)
            return (
              <Slot key={code} seen={lit} name={c ? hullName(locale, c.name) : code}>
                <ShipArtIcon family={lit ? 'yours' : 'merchant'} tier={shipTierOf(c?.tier ?? 1)} width={36} fit />
              </Slot>
            )
          })}
        </SetCard>
      ))}
    </>
  )
}

function CaptainSet({ v }: { v: Ready }) {
  const t = useT()
  const seen = new Set(v.seen.captains)
  return (
    <SetCard code="captains" name={t('logbook.captains')} n={v.totals.captains.n} of={v.totals.captains.of}>
      {v.captains.map((c) => {
        const lit = seen.has(c.code)
        return (
          <Slot key={c.code} seen={lit} name={c.name}>
            <Portrait role={null} tint={lit ? 'var(--color-accent)' : 'var(--color-ink-faint)'} seed={c.code} size={34} label={c.name} />
          </Slot>
        )
      })}
    </SetCard>
  )
}
