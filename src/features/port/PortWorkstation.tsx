import { useState } from 'react'
import {
  Button,
  Figure,
  Icon,
  Note,
  Row,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { useWorkstation } from '../../live/useWorkstation'
import { useWorld } from '../../live/worldStore'
import { formatInt } from '../../lib/format'
import type { FleetView, Refusal, WorkstationItem } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CRAFT — where trade goods become a fitting (0068), as a field of tiles.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"a workstation where you can create ship related items - sail etc."*
//
// ── WHY IT IS A GRID NOW ───────────────────────────────────────────────────────────────────────
// It was a column of full-width blocks, each with three `DetailRow`s and a sentence: 3,279px, the
// tallest face on the screen, for eleven fittings. §6 makes the faces a `Tile` grid with one
// figure each and the act in a tray. Two abreast, the catalogue is on one screen and the recipe —
// which is what you read AFTER choosing what to make — is one tap down.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// Whether a fitting can be made here, whether her hold carries the materials, what a suit of sails
// is made of. All three come down the wire from `world.workstation(port, fleet)`, because all three
// are rules `cmd.do_make` enforces. A fitting this city is not good enough for still SHOWS, muted,
// with the tier it wants in its tray — hiding it would make the catalogue look smaller than it is.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** What is missing from her hold for one of these, in the server's own numbers. */
function shortfall(item: WorkstationItem): string | null {
  const short = item.recipe.filter((r) => r.aboard !== null && r.aboard < r.qty)
  if (short.length === 0) return null
  return short.map((r) => `${r.name} ${formatInt(r.aboard ?? 0)}/${formatInt(r.qty)}`).join(' · ')
}

export function PortWorkstation({
  portId,
  fleet,
  tier,
}: {
  portId: string
  /** A fleet of yours lying here, or null — her hold is what a fitting is made from. */
  fleet: FleetView | null
  /** This city's workstation tier, from the port's own building row. */
  tier: number
}) {
  const { view, loading } = useWorkstation(portId, fleet?.id ?? null)
  const [open, setOpen] = useState<WorkstationItem | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const issue = useWorld((s) => s.issue)

  const make = (item: WorkstationItem) => {
    if (!fleet || sending) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      // One line through the one door. There is no second way an order comes into being.
      const okay = await issue(fleet.id, `MAKE ${item.code}`, null)
      setSending(false)
      if (okay) setOpen(null)
      else setRefusal(useWorld.getState().refusal)
    })()
  }

  if (loading && !view) return <Note tone="neutral">Loading…</Note>
  if (!view) return <Note tone="neutral">No workshop in this port.</Note>

  const short = open && fleet ? shortfall(open) : null
  const ready = open !== null && open.makeable && fleet !== null && short === null

  return (
    <div data-testid="port-workstation">
      {!fleet && (
        <Note tone="warning" className="mb-3">
          None of your fleets are here. Crafting uses materials from your ship.
        </Note>
      )}

      <TileField>
        {view.items.map((item) => (
          <Tile
            key={item.code}
            mark={<Icon name="mallet" size={20} />}
            name={item.name}
            meta={item.buys}
            state={item.makeable ? 'rest' : 'muted'}
            tap="whole"
            onClick={() => {
              setRefusal(null)
              setDetent('half')
              setOpen(item)
            }}
            /* HOW MANY YOU ALREADY HAVE IN THIS CITY, always — including none. It is the figure a
               player wants before making another, and a zero is an answer rather than an absence
               (which is what §2 item 16 objects to in a printed dash). */
            figure={
              <Figure
                value={formatInt(item.owned_here)}
                unit="here"
                tone={item.owned_here > 0 ? 'ink' : 'faint'}
              />
            }
            data-testid={`fitting-${item.code}`}
          />
        ))}
      </TileField>

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="craft-tray"
          action={
            ready ? (
              <Button
                variant="primary"
                className="w-full"
                busy={sending}
                busyLabel="Crafting…"
                onClick={() => make(open)}
                data-testid={`make-${open.code}`}
              >
                {`Craft ${open.name}`}
              </Button>
            ) : undefined
          }
        >
          {/* DESIGN 1.3, where a player reads it: every fitting buys one stat and spends another,
              so the choice is a choice and not a shopping list. */}
          <Row label="Gives" value={open.buys} />
          <Row label="Uses" value={open.spends} />
          {open.recipe.map((r, i) => (
            <Row
              key={r.name}
              label={r.name}
              value={
                <Figure
                  value={formatInt(r.qty)}
                  unit={r.aboard === null ? undefined : `· ${formatInt(r.aboard)} on board`}
                  tone={r.aboard !== null && r.aboard < r.qty ? 'warning' : 'ink'}
                />
              }
              hairline={i < open.recipe.length - 1}
            />
          ))}
          {!open.makeable && (
            <Note tone="warning">
              {`Needs a level ${formatInt(open.ws_tier)} workshop. This one is level ${formatInt(tier)}.`}
            </Note>
          )}
          {open.makeable && short !== null && <Note tone="warning">{`Missing: ${short}.`}</Note>}
          {refusal && (
            <Note tone="danger" code={refusal.code}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </div>
  )
}
