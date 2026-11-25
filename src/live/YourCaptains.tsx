import { Fragment, useState } from 'react'
import { Button, Clip, Empty, Facts, FactsLine, ListHeading, Note, Row, Tray } from '../components/ui'
import { cmdCaptainTraitsSet, cmdPromoteCaptain } from '../lib/rpc'
import type { Refusal, YourCaptain } from '../lib/rpc'
import { formatInt } from '../lib/format'
import type { YourCaptainsFace } from './useYourCaptains'
import { CaptainStats } from './CaptainStats'
import { CaptainSkills } from './CaptainSkills'
import { CaptainAshore, CaptainDismiss, CaptainPlacesLine, CaptainUpgrades, CaptainWorks } from './CaptainLand'
import { useWorld } from './worldStore'
import { t as tl } from '../lib/i18n'
import { ROLE_ORDER, jobWord, roleKeyWord, roleOf, roleRank, roleWord, traitWorks } from './captainWords'
import { CaptainPortrait, LevelRing, LevelRings, TraitChips } from './captainLook'
import { levelsThatMatter } from './captainMarks'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// YOUR CAPTAINS — levels, homesickness and the traits each one uses (0160, docs/SKILLS_AND_CAPTAINS.md K6).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, row 62: *"3 kinds of levels - exploration, tradingm, combat"*; row 70: *"surgeon could be a
// healer where captains may be homesick"*; row 61: *"S … 5 skill slots, with 10 skills"*. Everything here
// is `world.captains` — her grade NOW, the traits she knows and the ones she uses, her cabin, three level
// bars (the level in force, out of the next level's points) with the server's sentence when your
// company's level caps her, and the homesick line. Nothing is computed but a bar's fill.
//
// CHOOSING TRAITS is cmd.captain_traits_set: the player ticks up to her `slots` among the traits she knows,
// and the server says yes or why not. Offered only while `can_change` (ashore, or her ship docked) — the
// server refuses E_NOT_IN_PORT otherwise, and its refusal is printed if the two disagree.
//
// TWO PARTS, ONE FACE (the sheets-grow slice, 2026-11-02). The roster was a field of `OfficerTile`s inside its own section, with its
// tray inside that section too. The YOU screen now stands on the glass as figures over ONE list panel (docs/dev-log/2026-11-02-
// sheets-grow.md): the captains are ROWS of that panel — the Codex's captain row, the same shape the Inn and the Codex print — and
// the tray is a SIBLING of the panel, never inside the scroller that cuts it. `useYourCaptains` (useYourCaptains.ts) is the one read
// and the one open captain; `CaptainRows` goes in the panel's body, `CaptainTray` beside the panel. `OfficerTile` is untouched: the
// Codex and a merchant's sheet still draw it.

/** The roster as the rows of a list panel — or the one row that says there is nobody to list. */
export function CaptainRows({ face }: { face: YourCaptainsFace }) {
  const { captains, press, places, honor } = face
  if (captains.length === 0) {
    // nobody hired yet: a drawn tricorne over the one line (visual pass 2), not a grey sentence alone
    return (
      <Empty icon="captain" className="my-1" data-testid="your-captains-none">
        {tl('books.noCaptains')}
      </Empty>
    )
  }
  // THE ROSTER STANDS BY ROLE (owner row 66: "role based on combat, exploration, trading … combat close, long range"): one heading
  // a role, in the roster's own order, her rows under it, best grade first. A role nobody fills keeps its heading and says so,
  // because what a roster is FOR is seeing which seat is empty. Grouping is presentation: the role is the served card's.
  const groups = new Map<string, YourCaptain[]>(ROLE_ORDER.map((r) => [r, []]))
  for (const c of captains) {
    const role = roleOf(c) ?? ''
    groups.set(role, [...(groups.get(role) ?? []), c])
  }
  const ordered = [...groups.entries()]
    .filter(([role, list]) => role !== '' || list.length > 0)
    .sort(([a], [b]) => roleRank(a) - roleRank(b))
  return (
    <>
      {/* 0529, 0530: absent while dark */}
      <CaptainPlacesLine places={places} honor={honor} />
      {ordered.map(([role, list]) => (
        <Fragment key={role}>
          <ListHeading data-testid="captain-role" data-role={role} data-count={list.length}>
            {role === '' ? tl('books.captains') : roleKeyWord(role)}
          </ListHeading>
          {list.length === 0 && <Row label={tl('books.roleEmpty')} tone="muted" hairline={false} data-testid="captain-role-empty" />}
          {[...list]
            .sort((a, b) => (b.grade_ord ?? 0) - (a.grade_ord ?? 0) || a.name.localeCompare(b.name))
            .map((c, i) => {
              // muted when her job is one nothing reads yet
              const job = c.traits?.[0]
              const takesEffect = job ? traitWorks(job) : false
              // VISUAL SLICE 6 (2026-11-23): her plate (role hat, tongue tint, grade in the corner); under her name, her two levels that
              // matter as rings, then her job and her ship. The rings stand on line 2, not beside the name: at 320 a name's longest word
              // ("Bartholomäus") and two rings do not fit one line. The cabin and her job's per cent are on her sheet.
              return (
                <Row
                  key={c.code}
                  mark={<CaptainPortrait captain={c} />}
                  label={<Clip>{c.name}</Clip>}
                  tone={takesEffect ? 'default' : 'muted'}
                  chevron
                  onClick={() => press(c.code)}
                  hairline={i < list.length - 1}
                  data-testid="your-captain"
                >
                  <FactsLine>
                    <LevelRings captain={c} size={20} />
                    <Facts items={[jobWord(c.job_word), c.ship ?? tl('books.ashore')]} />
                  </FactsLine>
                </Row>
              )
            })}
        </Fragment>
      ))}
    </>
  )
}

/** The tray a press on a row opens. Mount it BESIDE the panel, never inside the scroller that holds the rows. */
export function CaptainTray({ face }: { face: YourCaptainsFace }) {
  const { shown, detent, move } = face
  if (shown === null) return null
  return (
    <Tray detent={detent} onDetentChange={move} title={shown.name} data-testid="your-captain-tray">
      <CaptainSheet key={shown.code} captain={shown} face={face} />
    </Tray>
  )
}

function CaptainSheet({ captain, face }: { captain: YourCaptain; face: YourCaptainsFace }) {
  const refresh = useWorld((s) => s.refresh)
  const [chosen, setChosen] = useState<readonly string[]>(captain.active)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const slots = captain.slots ?? 0
  const toggle = (code: string) =>
    setChosen((was) => (was.includes(code) ? was.filter((c) => c !== code) : [...was, code]))
  const changed = chosen.length !== captain.active.length || chosen.some((c) => !captain.active.includes(c))
  const matter = levelsThatMatter(captain)

  const save = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdCaptainTraitsSet(captain.code, chosen)
      setBusy(false)
      if (r.ok) await refresh()
      else setRefusal(r.refusal)
    })()
  }

  return (
    <div data-testid="captain-sheet">
      {/* HER PLATE (visual slice 6): the portrait, her job, her role and where she sits, in place of four label-and-value rows */}
      <div className="flex items-center gap-3 pb-3 pt-1" data-testid="captain-plate">
        <CaptainPortrait captain={captain} size={64} />
        <div className="min-w-0 flex-1">
          <span className="block break-words text-t-body">{jobWord(captain.job_word)}</span>
          <span className="block break-words text-t-label text-ink-muted" data-testid="captain-role-word">{roleWord(captain)}</span>
          <span className="block break-words text-t-caption text-ink-faint">
            {captain.ship ? `${captain.ship} · ${captain.cabin_word ?? ''}` : tl('books.ashore')}
          </span>
        </div>
      </div>
      {/* HER LEVELS AS RINGS, the two that matter first; a level her company's caps holds back says so under them */}
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 pb-2" data-testid="captain-levels">
        {[...matter, ...captain.levels.filter((l) => !matter.includes(l))].map((l) => (
          <LevelRing key={l.track} level={l} size={40} />
        ))}
      </div>
      {captain.levels.flatMap((l) =>
        l.cap_line ? [<span key={l.track} className="block text-t-caption text-ink-faint" data-testid={`captain-cap-${l.track}`}>{l.cap_line}</span>] : [],
      )}
      {/* 0527 to 0534: her works, her place ashore and her land expedition; each block absent while its switch is dark */}
      <CaptainWorks captain={captain} />
      <CaptainAshore captain={captain} />
      {captain.homesick && <Row label={captain.homesick.line} tone="accent" data-testid="captain-homesick" />}

      {/* HER TRAITS AS CHIPS: a glyph and a figure each, lit gold where she uses it; a press chooses while she may change them */}
      <h4 className="pb-1 pt-4 text-t-caption text-ink-faint">{tl('books.traits', { n: chosen.length, slots })}</h4>
      <TraitChips traits={captain.traits} chosen={chosen} onToggle={captain.can_change ? toggle : undefined} testPrefix="captain-trait" />
      {captain.can_change ? (
        <div className="pb-3 pt-2">
          <Button variant="primary" className="w-full" disabled={!changed || busy} busy={busy} busyLabel={tl('books.saving')} onClick={save}
            data-testid="captain-traits-save">
            {tl('books.useTraits')}
          </Button>
        </div>
      ) : (
        <Row label={tl('books.traitsInPort')} tone="muted" hairline={false} />
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}

      <CaptainStats code={captain.code} />

      {captain.promote && <Promote captain={captain} />}

      <CaptainSkills code={captain.code} />
      <CaptainUpgrades captain={captain} honor={face.honor} />
      <CaptainDismiss captain={captain} places={face.places} />
    </div>
  )
}

/** 0162: her next promotion, in the server's words, and the one button. The server decides; its refusal
 *  (level, items here, in port) is printed as it comes. */
function Promote({ captain }: { captain: YourCaptain }) {
  const refresh = useWorld((s) => s.refresh)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const p = captain.promote!
  const press = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdPromoteCaptain(captain.code)
      setBusy(false)
      if (r.ok) await refresh()
      else setRefusal(r.refusal)
    })()
  }
  return (
    <div className="pt-4" data-testid="captain-promote">
      <Row label={p.line} value={p.items_here === null ? undefined : tl('books.itemsHere', { n: formatInt(p.items_here), need: formatInt(p.items_needed) })} />
      <Button variant="secondary" className="w-full" disabled={busy} busy={busy} busyLabel={tl('books.promoting')} onClick={press}
        data-testid="captain-promote-press">
        {tl('books.promote', { to: p.to })}
      </Button>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}
