import { HullCountry } from '../../live/HullCountry'
import { Bar, Card, Clip, GroupHeading, Note, Row, Skeleton, StatCell } from '../../components/ui'
import { regardBandWord } from '../../domain/port'
import { formatInt } from '../../lib/format'
import { properName, useT } from '../../lib/i18n'
import type { LevelsView } from '../../lib/rpc'
import { LevelTiles, LevelTray } from '../../live/LevelTiles'
import { useLevels } from './useLevels'

// THE COMPANY'S LEVELS, ON THE YOU PAGE — the one place they stand (2026-11-16).
//
// They had two: the You page drew three track bars and the other levels as small tiles, and the Trade desk had a whole Levels
// face (owner, 2026-11-06: *"first create a tab on command - levels. This page will show you all the info."*) drawing the same
// tiles in full. The owner, 2026-11-16: *"in trade, there are city invest report and levels, which aren't that related to
// trade. they should have separate tab like map you stats etc."* — so the Levels face MOVED here, to the page that was already
// the levels' home (row 181: "my level … levels etc."), and the desk's face is gone. Nothing was copied:
//   · the tiles are the Levels face's, every level `level_skills` serves (the three tracks among them, so the three bars that
//     repeated them are gone); a pressed tile opens that level in the tray: her experience, what raises it, what levels give,
//     the experience table (LevelTiles.tsx).
//   · seamanship, the title and what the next one opens, whether levels act yet, and the countries' regard: the face's own
//     blocks, moved.
//   · each hull's level stands on her row in Your ships (YouScreen.tsx `Ships`), each captain's in her own tray — the face's
//     two lists of them would have been a second list of the same hulls and captains on one page.
//   · the face's "Room" block is the room line at the top of this page (`RoomLine`, world.house_room) — one answer to "how many
//     fleets and ships may I have".
//
// ONE READ, NO SUM: `world.levels()` (0325). Nothing here works out a level, a threshold or a room: the bars are fills of
// served figures. `bite` (levels_bite) is the truth about whether a hull's or a captain's level acts yet.

type Ready = Extract<LevelsView, { company: true }>

/** The levels card. The level pressed is the page's (`picked`), because its tray is a sibling of the page's split, not inside
 *  the side column: the side is sticky (its own stacking layer), and a tray inside it stood UNDER the page's header, which took
 *  the press meant for its close button at 1,280 (tests/levels.tiles.spec.ts). The captains' tray stands the same way. */
export function YouLevels({ picked, onPick }: { picked: string | null; onPick: (code: string) => void }) {
  const t = useT()
  const read = useLevels()
  const v = read.view
  return (
    <Card title={t('you.levels')} data-testid="levels">
      {!v ? (
        read.loading ? <Skeleton className="h-[200px] w-full" /> : <Note tone="danger">{t('command.lvFailed')}</Note>
      ) : !v.company ? (
        <Note tone="neutral">{t('command.lvNoCompany')}</Note>
      ) : (
        <div data-testid="you-levels">
          <LevelTiles card={v.level_skills} selected={picked} onSelect={onPick} />
          <Company v={v} />
          {/* 2026-11-22 (P0): dark, the line said "ship and captain levels: counted only, no effect yet", a builder's note on a
              player's page. It stands only once they work. */}
          {v.bite && (
            <Note tone="success" data-testid="levels-bite">
              {t('command.lvLit')}
            </Note>
          )}
          <Countries v={v} />
        </div>
      )}
    </Card>
  )
}

/** A pressed level, in the tray over the page (her experience, what raises it, what levels give, the table). */
export function YouLevelTray({ picked, onClose }: { picked: string | null; onClose: () => void }) {
  const v = useLevels().view
  if (!v || !v.company) return null
  return <LevelTray card={v.level_skills} code={picked} onClose={onClose} />
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
  const sea = v.skills.seamanship
  return (
    <>
      <div className="mt-2 min-w-0 py-2" data-testid="levels-seamanship">
        <StatCell look="stacked" label={t('command.lvSeamanship')} value={sea.level} format={(n) => `${formatInt(n)} ${t('command.lvOf', { max: sea.max })}`} />
        <Bar value={sea.level} of={sea.max} label={t('you.levelOf', { name: t('command.lvSeamanship') })} tone="accent" className="mt-1" />
        <span className="mt-1 block text-t-caption text-ink-faint">{t('command.lvSkillNote')}</span>
      </div>
      <div className="min-w-0 border-t border-edge py-2" data-testid="levels-title">
        <Words label={t('command.lvTitle')} value={`${v.title.name ? properName('title', v.title.name, v.title.name) : ''} ${t('command.lvLevel', { n: v.title.level })}`.trim()} />
        <span className="mt-1 block text-t-caption text-ink-faint">
          {v.title.next
            ? t('command.lvTitleNext', {
                name: properName('title', v.title.next.name, v.title.next.name),
                tracks: t('command.goalTracks', { a: v.tracks.trading.level, b: v.tracks.exploration.level, n: v.title.next.level }),
              })
            : t('command.lvTitleTop')}
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

function Countries({ v }: { v: Ready }) {
  const t = useT()
  const rows = v.regard
  return (
    <section data-testid="levels-regard">
      <GroupHeading className="mt-3">{t('command.lvRegard')}</GroupHeading>
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
