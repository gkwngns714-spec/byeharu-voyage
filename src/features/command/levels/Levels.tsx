import { useState } from 'react'
import { HullCountry } from '../../../live/HullCountry'
import { Bar, Clip, FactsLine, Note, Row, ScrollPane, Skeleton, StatCell, useWide } from '../../../components/ui'
import { regardBandWord } from '../../../domain/port'
import { formatInt } from '../../../lib/format'
import { properName, useT } from '../../../lib/i18n'
import { worldLevels, type CaptainLevel, type LevelCut, type LevelsView, type YourCaptain } from '../../../lib/rpc'
import { LevelDetail, LevelTiles, LevelTray } from './LevelTiles'
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
// 0411: THE COMPANY'S LEVELS ARE TILES (LevelTiles.tsx): every level `level_skills` serves, the three old tracks among them. A
// pressed level shows her experience, what raises it, what levels give and the experience table, all from the same read.
//
// THE PRESS LAW: a press selects and nothing moves under a finger: a pressed level opens in a tray docked over the page (phone) or
// stands in the middle pane (wide). The parts stand in the desk's panes (wide) or one under the other (phone); the lists scroll
// inside themselves.

type Ready = Extract<LevelsView, { company: true }>

/** How far a hull's bar is filled: points since this level began, over the span to the next. A top level is full. */
const fill = (c: Pick<LevelCut, 'points' | 'from' | 'next_at'>): number =>
  c.next_at === null || c.next_at <= c.from ? 100 : Math.max(0, Math.min(100, ((c.points - c.from) / (c.next_at - c.from)) * 100))

export function Levels({ layout }: { layout: DeskLayout }) {
  const t = useT()
  const wide = useWide()
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const captains = useYourCaptains().captains
  const v = read.view
  // the level pressed. A wide glass always shows one (the first, until she presses another); a phone shows one only while its tray is open.
  const [picked, setPicked] = useState<string | null>(null)

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
  const banner = (
    <Note tone={v.bite ? 'success' : 'neutral'} data-testid="levels-bite">
      {v.bite ? t('command.lvLit') : t('command.lvDark')}
    </Note>
  )
  if (!wide) {
    // THE PHONE IS ONE GLASS (tests/onepage.spec.ts): the whole page is one board that takes what the strip and the faces leave and
    // scrolls inside itself, so the desk's own box never grows.
    return layout({
      testid: 'desk-levels',
      list: null,
      mainFill: true,
      main: (
        <ScrollPane className="flex-1">
          <Company v={v} picked={picked} onPick={setPicked} />
          <LevelTray card={v.level_skills} code={picked} onClose={() => setPicked(null)} />
          <Room v={v} />
          <Countries v={v} />
          {banner}
          <HullRows v={v} />
          <CaptainRows captains={captains} />
        </ScrollPane>
      ),
    })
  }
  const shown = v.level_skills.skills.find((s) => s.code === picked) ?? v.level_skills.skills[0]
  return layout({
    testid: 'desk-levels',
    list: <Company v={v} picked={shown?.code ?? null} onPick={setPicked} />,
    main: (
      <>
        {shown && <LevelDetail card={v.level_skills} skill={shown} />}
        <div className="mt-6" />
        {banner}
        <HullRows v={v} />
        <CaptainRows captains={captains} />
      </>
    ),
    side: (
      <ScrollPane className="h-full p-4 min-[90rem]:p-5">
        <Room v={v} />
        <Countries v={v} />
      </ScrollPane>
    ),
  })
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

function Company({ v, picked, onPick }: { v: Ready; picked: string | null; onPick: (code: string) => void }) {
  const t = useT()
  const sea = v.skills.seamanship
  return (
    <>
      <LevelTiles card={v.level_skills} selected={picked} onSelect={onPick} />
      <span className="mt-2 block text-t-caption text-ink-faint" data-testid="levels-vs-skills">
        {t('command.lvVsSkills')}
      </span>
      <div className="min-w-0 py-2" data-testid="levels-seamanship">
        <StatCell look="stacked" label={t('command.lvSeamanship')} value={sea.level} format={(n) => `${formatInt(n)} ${t('command.lvOf', { max: sea.max })}`} />
        <Bar value={sea.level} of={sea.max} label={t('you.levelOf', { name: t('command.lvSeamanship') })} tone="accent" className="mt-1" />
        <span className="mt-1 block text-t-caption text-ink-faint">{t('command.lvSkillNote')}</span>
      </div>
      <div className="min-w-0 border-t border-edge py-2" data-testid="levels-title">
        <Words label={t('command.lvTitle')} value={`${v.title.name ? properName('title', v.title.name, v.title.name) : ''} ${t('command.lvLevel', { n: v.title.level })}`.trim()} />
        <span className="mt-1 block text-t-caption text-ink-faint">
          {v.title.next ? t('command.lvTitleNext', { name: properName('title', v.title.next.name, v.title.next.name), n: v.title.next.level }) : t('command.lvTitleTop')}
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
            // the country's flag and its name in her language, by the game's one nation-flag renderer (HullCountry): found when regard was lit, 0373 — the list was dark until then
            label={<Clip><HullCountry nation={r.code} /></Clip>}
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
