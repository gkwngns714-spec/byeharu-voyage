import { useState } from 'react'
import { Bar, Button, Note, Row, TileField, Tray, type TrayDetent, OfficerTile } from '../components/ui'
import { cmdCaptainTraitsSet, cmdPromoteCaptain, worldCaptains } from '../lib/rpc'
import type { Refusal, YourCaptain } from '../lib/rpc'
import { formatInt } from '../lib/format'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'
import { t as tl } from '../lib/i18n'

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

export function YourCaptains() {
  const { view } = useServedRead('captains', () => worldCaptains(), { name: 'worldCaptains' })
  const [open, setOpen] = useState<string | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const captains = view?.captains ?? []
  const shown = captains.find((c) => c.code === open) ?? null

  return (
    <section className="pt-4" data-testid="your-captains">
      <h3 className="pb-2 text-t-caption uppercase tracking-wider text-ink-faint">{tl('books.captains')}</h3>
      {captains.length === 0 ? (
        <Row label={tl('books.noCaptains')} tone="muted" hairline={false} data-testid="your-captains-none" />
      ) : (
        <TileField>
          {captains.map((c) => (
            <OfficerTile
              key={c.code}
              name={c.name}
              role={c.job_word ?? ''}
              grade={c.grade ?? null}
              bonusPct={c.traits?.[0]?.pct ?? 0}
              homePort={c.ship ? `${c.ship} · ${c.cabin_word ?? ''}` : tl('books.ashore')}
              takesEffect={c.traits?.[0]?.in_use ?? false}
              onClick={() => {
                setDetent('half')
                setOpen(c.code)
              }}
              testId="your-captain"
            />
          ))}
        </TileField>
      )}
      {shown && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={shown.name}
          data-testid="your-captain-tray"
        >
          <CaptainSheet key={shown.code} captain={shown} />
        </Tray>
      )}
    </section>
  )
}

function CaptainSheet({ captain }: { captain: YourCaptain }) {
  const refresh = useWorld((s) => s.refresh)
  const [chosen, setChosen] = useState<readonly string[]>(captain.active)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const slots = captain.slots ?? 0
  const toggle = (code: string) =>
    setChosen((was) => (was.includes(code) ? was.filter((c) => c !== code) : [...was, code]))
  const changed = chosen.length !== captain.active.length || chosen.some((c) => !captain.active.includes(c))

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
      <Row label={tl('books.grade')} value={captain.grade ?? ''} />
      <Row label={tl('books.job')} value={`${captain.job_word ?? ''} · ${captain.focus_word ?? ''}`} />
      <Row label={tl('books.where')} value={captain.ship ? `${captain.ship} · ${captain.cabin_word ?? ''}` : tl('books.ashore')} />
      {captain.homesick && <Row label={captain.homesick.line} tone="accent" data-testid="captain-homesick" />}

      {captain.levels.map((l) => (
        <Row key={l.track} label={l.word} value={`${formatInt(l.level)} / 20`} data-testid={`captain-level-${l.track}`}>
          <Bar pct={l.next_at > 0 ? Math.min(1, l.points / l.next_at) * 100 : 0} tone="accent" label={`${l.word} experience`} className="mt-1" />
          {l.cap_line && <span className="block text-t-caption text-ink-faint">{l.cap_line}</span>}
        </Row>
      ))}

      {captain.promote && <Promote captain={captain} />}

      <h4 className="pb-1 pt-4 text-t-caption text-ink-faint">{tl('books.traits', { n: chosen.length, slots })}</h4>
      {(captain.traits ?? []).map((t) => {
        const on = chosen.includes(t.code)
        // THE SENTENCE IS LINE 2 (2026-11-02), as in the Codex's captain tray (CaptainsFace.tsx): as the row's `value` it
        // stood in a one-line cell beside the name, so "Ship-supplies trader" was left 9 px wide, one letter a line, at 320.
        return (
          <Row
            key={t.code}
            label={t.word}
            tone={on ? 'default' : 'muted'}
            onClick={captain.can_change ? () => toggle(t.code) : undefined}
            data-testid={`captain-trait-${t.code}`}
          >
            <span className="block text-t-body">{t.lines.join(' · ')}</span>
            {on && <span className="block text-t-caption text-accent">{tl('books.inUse')}</span>}
          </Row>
        )
      })}
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
