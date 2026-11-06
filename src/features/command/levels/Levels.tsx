import type { ReactNode } from 'react'
import { Bar, Clip, FactsLine, Note, Row, ScrollPane, Skeleton, StatCell } from '../../../components/ui'
import { regardBandWord } from '../../../domain/port'
import { formatInt } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import { worldLevels, type CaptainLevel, type LevelCut, type LevelsView, type YourCaptain } from '../../../lib/rpc'
import { useServedRead } from '../../../live/useServedRead'
import { useYourCaptains } from '../../../live/useYourCaptains'
import type { DeskLayout } from '../DeskFrame'

// LEVELS — one page with every level of the company (owner, 2026-11-06: *"first create a tab on command - levels. This page will
// show you all the info."*, docs/dev-log/2026-11-06-the-levels-page.md).
//
// ONE READ, NO SUM: `world.levels()` (0325) serves the tracks with where each next level begins, the title, the room, every hull's
// level, and regard while it is lit. The captains are the existing `world.captains` (the You tab's own read). Nothing here works out a
// level, a threshold or a room: the bars are fills of served figures. `bite` (levels_bite) is the truth about whether a hull's or a
// captain's level acts yet; while it is false the page says so and shows what each one counts as.
//
// THE PRESS LAW: the page has no control, so nothing moves under a finger. The parts stand in the desk's panes (wide) or one under
// the other (phone); the lists scroll inside themselves.

type Ready = Extract<LevelsView, { company: true }>

/** How far a level's bar is filled: points since this level began, over the span to the next. A top level is full. */
const fill = (c: Pick<LevelCut, 'points' | 'from' | 'next_at'>): number =>
  c.next_at === null || c.next_at <= c.from ? 100 : Math.max(0, Math.min(100, ((c.points - c.from) / (c.next_at - c.from)) * 100))

export function Levels({ layout }: { layout: DeskLayout }) {
  const t = useT()
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const captains = useYourCaptains().captains
  const v = read.view

  if (!v) {
    return layout({
      testid: 'desk-levels',
      list: read.loading ? <Skeleton className="h-[200px] w-full" /> : <Note tone="danger">{t('command.lvFailed')}</Note>,
      main: read.loading ? <Skeleton className="h-[160px] w-full" /> : null,
    })
  }
  if (!v.company) {
    return layout({ testid: 'desk-levels', list: <Note tone="neutral">{t('command.lvNoCompany')}</Note>, main: null })
  }
  return layout({
    testid: 'desk-levels',
    list: <Company v={v} />,
    main: (
      <>
        <Note tone={v.bite ? 'success' : 'neutral'} data-testid="levels-bite">
          {v.bite ? t('command.lvLit') : t('command.lvDark')}
        </Note>
        <HullRows v={v} />
        <CaptainRows captains={captains} />
      </>
    ),
    side: (
      <div className="bv-scroll h-full min-h-0 overflow-y-auto p-4 min-[90rem]:p-5">
        <Room v={v} />
        <Countries v={v} />
      </div>
    ),
    order: ['list', 'side', 'main'],
  })
}

/** One ladder: its name and level, the bar to the next, and the line under it. */
function Track({ name, level, cut, line, testid, children }: { name: string; level: number; cut: LevelCut; line?: string; testid: string; children?: ReactNode }) {
  const t = useT()
  const toNext = cut.next_at === null ? t('command.lvTop') : t('command.lvToNext', { n: formatInt(Math.ceil(cut.next_at - cut.points)), next: level + 1 })
  return (
    <div className="min-w-0 py-2" data-testid={testid}>
      <StatCell look="stacked" label={name} value={level} format={formatInt} />
      <Bar pct={fill(cut)} label={t('you.levelOf', { name })} tone="accent" className="mt-1" />
      <span className="mt-1 block text-t-caption text-ink-faint">{[t('command.lvPoints', { n: formatInt(cut.points) }), toNext, line].filter(Boolean).join(' · ')}</span>
      {children}
    </div>
  )
}

/** A label over a word figure (StatCell's value is a counting number). */
function Words({ label, value }: { label: string; value: string }) {
  return (
    <>
      <span className="block text-t-body text-ink-muted">{label}</span>
      <span className="block text-t-card text-ink">{value}</span>
    </>
  )
}

function Company({ v }: { v: Ready }) {
  const t = useT()
  const { trading, exploration, combat } = v.tracks
  const sea = v.skills.seamanship
  return (
    <>
      <Track name={t('command.lvTrading')} level={trading.level} cut={trading} line={t('command.lvTurnover', { n: formatInt(trading.turnover) })} testid="levels-trading" />
      <Track
        name={t('command.lvExploration')}
        level={exploration.level}
        cut={exploration}
        line={t('command.lvPorts', { ports: formatInt(exploration.ports_reached), nm: formatInt(exploration.nm_sailed) })}
        testid="levels-exploration"
      />
      {combat.playable ? (
        <Track name={t('command.lvCombat')} level={combat.level} cut={combat} testid="levels-combat" />
      ) : (
        <div className="py-2" data-testid="levels-combat">
          <Words label={t('command.lvCombat')} value={t('command.lvCombatDark')} />
        </div>
      )}
      <div className="min-w-0 py-2" data-testid="levels-seamanship">
        <StatCell look="stacked" label={t('command.lvSeamanship')} value={sea.level} format={(n) => `${formatInt(n)} ${t('command.lvOf', { max: sea.max })}`} />
        <Bar value={sea.level} of={sea.max} label={t('you.levelOf', { name: t('command.lvSeamanship') })} tone="accent" className="mt-1" />
        <span className="mt-1 block text-t-caption text-ink-faint">{t('command.lvSkillNote')}</span>
      </div>
      <div className="min-w-0 border-t border-edge py-2" data-testid="levels-title">
        <Words label={t('command.lvTitle')} value={`${v.title.name ?? ''} ${t('command.lvLevel', { n: v.title.level })}`.trim()} />
        <span className="mt-1 block text-t-caption text-ink-faint">
          {v.title.next ? t('command.lvTitleNext', { name: v.title.next.name, n: v.title.next.level }) : t('command.lvTitleTop')}
        </span>
        {v.title.next && v.title.next.opens.length > 0 && (
          <span className="mt-1 block text-t-caption text-ink-muted" data-testid="levels-opens">
            {t(v.title.seas_bite ? 'command.lvOpens' : 'command.lvOpensDark', { what: v.title.next.opens.join(', ') })}
          </span>
        )}
      </div>
    </>
  )
}

function Room({ v }: { v: Ready }) {
  const t = useT()
  return (
    <section data-testid="levels-room">
      <h3 className="mb-1 text-t-caption font-semibold text-ink-faint">{t('command.lvRoom')}</h3>
      <Row label={t('command.lvFleets')} value={t('command.lvFleetsOf', { used: formatInt(v.room.fleets), max: formatInt(v.room.fleet_max) })} />
      <Row label={t('command.lvShipsPer')} value={formatInt(v.room.fleet_ship_max)} hairline={false} />
      <span className="block pb-3 text-t-caption text-ink-faint">{v.room.counted ? t('command.lvRoomNoteCounted') : t('command.lvRoomNote')}</span>
    </section>
  )
}

function Countries({ v }: { v: Ready }) {
  const t = useT()
  const rows = v.regard
  return (
    <section data-testid="levels-regard">
      <h3 className="mb-1 mt-2 text-t-caption font-semibold text-ink-faint">{t('command.lvRegard')}</h3>
      {rows === null ? (
        <span className="block text-t-caption text-ink-faint">{t('command.lvRegardDark')}</span>
      ) : (
        rows.map((r, i) => (
          <Row
            key={r.code}
            label={<Clip>{`${r.flag} ${r.name}`}</Clip>}
            value={`${regardBandWord(r.band)} ${formatInt(r.score)}`}
            hairline={i < rows.length - 1}
            data-testid="levels-country"
          />
        ))
      )}
    </section>
  )
}

function HullRows({ v }: { v: Ready }) {
  const t = useT()
  return (
    <section className="mt-3" data-testid="levels-ships">
      <h3 className="mb-1 text-t-caption font-semibold text-ink-faint">{t('command.lvShips')}</h3>
      {v.ships.length === 0 ? (
        <Note tone="neutral">{t('command.lvNoShips')}</Note>
      ) : (
        <ScrollPane className="max-h-[16rem] lg:max-h-none">
          {v.ships.map((s, i) => (
            <Row
              key={s.id}
              label={<Clip>{s.name}</Clip>}
              value={t('command.lvLevel', { n: s.level })}
              hairline={i < v.ships.length - 1}
              data-testid="levels-ship"
            >
              <Bar pct={fill(s)} label={s.name} tone="accent" className="mt-1" />
              <FactsLine>
                <span>
                  {[s.class, s.fleet, s.flagship ? t('command.lvFlagship') : null, s.in_force < s.level ? t('command.lvActsAs', { n: s.in_force }) : null]
                    .filter(Boolean)
                    .join(' · ')}
                </span>
              </FactsLine>
            </Row>
          ))}
        </ScrollPane>
      )}
    </section>
  )
}

function CaptainRows({ captains }: { captains: readonly YourCaptain[] }) {
  const t = useT()
  const word = (l: CaptainLevel) => `${l.word} ${l.own}${l.level < l.own ? ` (${t('command.lvActsAs', { n: l.level })})` : ''}`
  return (
    <section className="mt-4" data-testid="levels-captains">
      <h3 className="mb-1 text-t-caption font-semibold text-ink-faint">{t('command.lvCaptains')}</h3>
      {captains.length === 0 ? (
        <Note tone="neutral">{t('command.lvNoCaptains')}</Note>
      ) : (
        <ScrollPane className="max-h-[16rem] lg:max-h-none">
          {captains.map((c, i) => (
            <Row key={c.code} label={<Clip>{c.name}</Clip>} value={c.grade ?? ''} hairline={i < captains.length - 1} data-testid="levels-captain">
              <FactsLine>
                <span>{c.levels.map(word).join(' · ')}</span>
              </FactsLine>
              {c.levels
                .filter((l) => l.cap_line)
                .map((l) => (
                  <span key={l.track} className="block text-t-caption text-ink-faint">
                    {l.cap_line}
                  </span>
                ))}
            </Row>
          ))}
        </ScrollPane>
      )}
    </section>
  )
}
