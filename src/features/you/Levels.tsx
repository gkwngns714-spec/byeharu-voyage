import { Link } from 'react-router-dom'
import { HullCountry } from '../../live/HullCountry'
import { Bar, Card, Clip, GroupHeading, Icon, Note, Ring, Row, Skeleton, StatCell } from '../../components/ui'
import { regardBandWord } from '../../domain/port'
import { formatInt } from '../../lib/format'
import { useLocale, useT } from '../../lib/i18n'
import type { LevelsView } from '../../lib/rpc'
import { LevelTiles, LevelTray, Mark } from '../../live/LevelTiles'
import { levelFill, levelName } from '../../live/levelWords'
import { tabWord } from '../../app/navTabs'
import { useLevels } from './useLevels'

// THE COMPANY'S LEVELS — ONE PAGE (roadmap 2026-11-23, slice 10: "One Skills page, with loud level-ups"; RS3's skills page).
//
// They had two homes and then one: the You page drew three track bars and the other levels as small tiles, and the Trade desk had a
// whole Levels face; 2026-11-16 the face MOVED to You's side column (owner: *"in trade, there are city invest report and levels,
// which aren't that related to trade"*). Slice 10 gives them a PAGE of their own (`/levels`, LevelsScreen.tsx), lit under You, and
// You keeps a DOOR: every level as its mark in a ring with its figure, the whole card one press to the page. Nothing was copied:
//   · the tiles are slice 9's (LevelTiles.tsx), each now with what its next level opens and "fastest way" (one press to the act);
//   · seamanship, the countries' regard: moved here with them; the title stays on You's house plate;
//   · each hull's level stands on her row in Your ships (YouScreen.tsx `Ships`), each captain's in her own tray.
//
// ONE READ, NO SUM: `world.levels()` (0325). Nothing here works out a level, a threshold or a room: the bars are fills of
// served figures. `bite` (levels_bite) is the truth about whether a hull's or a captain's level acts yet.

type Ready = Extract<LevelsView, { company: true }>

/** The levels page's route: the one spelling every door to it uses. */
export const LEVELS_ROUTE = '/levels'

/** THE DOOR ON YOU: every level as its mark in a ring filled to the next, the level under it; the card is one press to the page. */
export function YouLevelsDoor() {
  const t = useT()
  const locale = useLocale()
  const read = useLevels()
  const v = read.view
  return (
    <Card icon="levelUp" title={t('you.levels')} data-testid="levels">
      {!v ? (
        read.loading ? <Skeleton className="h-[120px] w-full" /> : <Note tone="danger">{t('command.lvFailed')}</Note>
      ) : !v.company ? (
        <Note tone="neutral">{t('command.lvNoCompany')}</Note>
      ) : (
        <Link
          to={LEVELS_ROUTE}
          className="-m-1 block rounded-control p-1 hover:bg-surface-2"
          aria-label={tabWord(locale, LEVELS_ROUTE)}
          data-testid="you-levels"
        >
          <span className="grid grid-cols-[repeat(auto-fill,minmax(3rem,1fr))] gap-x-1 gap-y-2">
            {v.level_skills.skills.map((s) => {
              const name = levelName(locale, s.code, s.word)
              return (
                <span key={s.code} className="flex min-w-0 flex-col items-center gap-0.5" data-testid={`you-level-${s.code}`} data-level={s.level}>
                  <Ring pct={levelFill(s)} size={36} tone={s.counted ? 'accent' : 'muted'} label={t('books.levelRing', { track: name, n: formatInt(s.level) })}>
                    <span className={s.counted ? 'text-accent' : 'text-ink-faint'}>
                      <Mark code={s.code} size={18} />
                    </span>
                  </Ring>
                  <span className="text-t-title leading-none tabular-nums text-ink">{formatInt(s.level)}</span>
                </span>
              )
            })}
          </span>
          <span className="mt-2 flex min-h-11 items-center justify-end gap-1 text-t-label text-ink-muted">
            {tabWord(locale, LEVELS_ROUTE)}
            <Icon name="chevron" size={16} />
          </span>
        </Link>
      )}
    </Card>
  )
}

/** THE PAGE'S TILES: every level, Sea and Land, as slice 9's ringed tiles. The level pressed is the page's (`picked`): its tray is a
 *  sibling of the page's split, not inside the side column (the side is sticky, and a tray inside it stood under the page's header). */
export function LevelsCard({ picked, onPick }: { picked: string | null; onPick: (code: string) => void }) {
  const t = useT()
  const read = useLevels()
  const v = read.view
  // no title of its own: the page's title is the same word (one word, said once)
  return (
    <Card data-testid="levels">
      {!v ? (
        read.loading ? <Skeleton className="h-[200px] w-full" /> : <Note tone="danger">{t('command.lvFailed')}</Note>
      ) : !v.company ? (
        <Note tone="neutral">{t('command.lvNoCompany')}</Note>
      ) : (
        <div data-testid="skills-levels">
          <LevelTiles card={v.level_skills} selected={picked} onSelect={onPick} />
        </div>
      )}
    </Card>
  )
}

/** A pressed level, in the tray over the page (her experience, what raises it, what levels give, the table). */
export function LevelsTray({ picked, onClose }: { picked: string | null; onClose: () => void }) {
  const v = useLevels().view
  if (!v || !v.company) return null
  return <LevelTray card={v.level_skills} code={picked} onClose={onClose} />
}

/** Seamanship and the countries' regard: the levels card's other two blocks, moved here with it. */
export function LevelsSide() {
  const v = useLevels().view
  if (!v || !v.company) return null
  return (
    <Card data-testid="levels-more">
      <Company v={v} />
      <Countries v={v} />
    </Card>
  )
}

function Company({ v }: { v: Ready }) {
  const t = useT()
  const sea = v.skills.seamanship
  return (
    <div className="min-w-0 pb-2" data-testid="levels-seamanship">
      <StatCell look="stacked" label={t('command.lvSeamanship')} value={sea.level} format={(n) => `${formatInt(n)} ${t('command.lvOf', { max: sea.max })}`} />
      <Bar value={sea.level} of={sea.max} label={t('you.levelOf', { name: t('command.lvSeamanship') })} tone="accent" className="mt-1" />
    </div>
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
