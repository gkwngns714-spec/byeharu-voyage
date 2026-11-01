import { useState } from 'react'
import {
  ActCell,
  ActPair,
  Bar,
  Button,
  CargoBar,
  Figure,
  GoodKind,
  Note,
  Row,
  SheetSection,
  Stepper,
  Tray,
  goodClassRow,
  type TrayDetent,
  Clip,
} from '../components/ui'
import { fleetHoldTotal, fleetHoldUsed } from '../domain/fleet'
import { findVerb, moveEstimate, orderText } from '../domain/order'
import { formatInt, formatOfTotal, formatTons, formatUnits } from '../lib/format'
import type { FleetView, Refusal, StoredGood, WarehouseView } from '../lib/rpc'
import { useOrderPreview } from './useOrderPreview'
import { useStorage } from './useStorage'
import { useWorld } from './worldStore'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// STORAGE — what this port is keeping for you (0070), drawn like the trade board.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"make a storage, where i can buy trade goods and then store it. The storage is not
// shared between cities, an independeant building."* Then, 2026-09-13 (rows 87 and 88): *"there
// is warehourse and there is store. unify."* and *"on your ship, make it like trading graphic,
// where i can put, or pull? whatever that is most necessary."*
//
// ── ONE WORD (row 87) ──────────────────────────────────────────────────────────────────────────
// Storage. The tab, the building row on the Town face, the heading, the act. The server's name for
// the building (0067: `Warehouse`) and its RPC (`world.warehouse`) are the wire's words and stay;
// docs/WORDS.md bans the two old ones in player text and tests/words.spec.ts holds the ban.
//
// ── THE TRADE BOARD'S SHAPE (row 88) ──────────────────────────────────────────────────────────
// It was two lists — "In the warehouse" and "On your ship" — each a chevron row that opened a
// tray with ONE button moving ALL of it. Now ONE row per good you have here, on either side, with
// the two acts as two cells where the ledger has its two prices: `Put in storage` carries the
// count on board, `Take on board` the count in storage, and a cell with nothing to move is dead
// and says why on its own face (`ActCell`, the ledger's own cell, promoted). A press opens the one
// Tray with a `Stepper` for the COUNT, the ship's `CargoBar`, and one button for that count.
// Nothing in the list moves when a cell is pressed (the tray is `fixed`; owner row 15).
//
// ── WHAT IS SERVED, AND WHAT IS NOT ────────────────────────────────────────────────────────────
// `world.warehouse` serves both sides in one read (they could disagree if asked separately), the
// space, and `tuns` per stored line. `STORE <good> <n>` / `TAKE <good> <n>` take a COUNT (0070 §5:
// "a good, then a quantity or ALL", proven by its own self-assert with `STORE … 10`), so the
// tray previews the exact line through `cmd.preview` (`useOrderPreview`) and reads the verb's
// estimate (`moveEstimate`): `qty` is what would ACTUALLY move — a TAKE takes what fits and
// leaves the rest — and the button says so before the press. NOTHING serves "tons on board
// after": `world.warehouse` carries no hold figure and the STORE/TAKE estimate carries none, so
// the `CargoBar` is drawn WITHOUT `after` rather than with `used ± n × bulk` worked out here
// (the seven-answers defect). The `Cargo space` row is the trade tray's own line, same arithmetic
// over the same served `bulk`, so a count can be read against the bar.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// How big the storage is, how full, whether a cargo fits, how much a hold has room for. All are
// `cmd.do_store` / `cmd.do_take`'s rules and all arrive answered or refused.
//
// `StorageRow` and `MoveTray` are private: no second screen draws a port's storage (§7B q3).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

type Move = 'put' | 'take'

/** One good as this face sees it — on either side, or both. */
interface Line {
  code: string
  name: string
  bulk: number
  stored: StoredGood | null
  aboard: StoredGood | null
}

/** Both served lists folded into one row per good, by name. */
function linesOf(view: WarehouseView): Line[] {
  const byCode = new Map<string, Line>()
  for (const g of view.stored) byCode.set(g.good, { code: g.good, name: g.name, bulk: g.bulk, stored: g, aboard: null })
  for (const g of view.aboard) {
    const line = byCode.get(g.good)
    if (line) line.aboard = g
    else byCode.set(g.good, { code: g.good, name: g.name, bulk: g.bulk, stored: null, aboard: g })
  }
  return [...byCode.values()].sort((a, b) => a.name.localeCompare(b.name))
}

/** Tons a served line takes: the server's own `tuns` for a stored line; a hold line carries
 *  `bulk` and no `tuns` (0070), so it is the one fold OnBoard.tsx makes too. */
function tonsOf(g: StoredGood): number {
  return g.tuns ?? g.qty * g.bulk
}

export function PortStorage({
  portId,
  fleet,
}: {
  portId: string
  /** A fleet of yours in this port, or null — storage is only reachable from a docked ship. */
  fleet: FleetView | null
}) {
  const t = useT()
  const { view, loading } = useStorage(portId, fleet?.id ?? null)
  const [held, setHeld] = useState<{ code: string; move: Move } | null>(null)

  if (loading && !view) return <Note tone="neutral">{t('inn.loading')}</Note>
  if (!view) return <Note tone="neutral">{t('inn.noStorage')}</Note>

  const free = Math.max(0, view.cap - view.used)
  const lines = linesOf(view)
  // The world is re-read every few seconds; a line the re-read emptied on both sides is gone
  // from the list, and its tray goes with it rather than standing over nothing.
  const open = held && fleet ? (lines.find((l) => l.code === held.code) ?? null) : null

  return (
    <div data-testid="port-storage">
      {/* HOW FULL, AS A BAR. Storage's limit is SPACE, and space is the one thing a number alone
          reads badly — 340 of 450 means nothing until you see how much of the bar is left. The
          figure is the share WITH its whole (docs/WORDS.md law 2): "0 / 450 tons". */}
      <Row
        label={t('inn.space')}
        value={<Figure value={formatOfTotal(view.used, view.cap)} unit="tons" size="figure" />}
        hairline={false}
        data-testid="storage-space"
      />
      <Bar
        pct={view.cap > 0 ? (view.used / view.cap) * 100 : 0}
        tone={free > 0 ? 'accent' : 'warning'}
        label={t('inn.howFull')}
        figure={<Figure value={formatInt(free)} unit={t('inn.tonsFree')} />}
      />

      <SheetSection heading={t('inn.yourGoods')}>
        {lines.length === 0 ? (
          <Row
            label={t(fleet ? 'inn.nothingBoth' : 'inn.nothing')}
            tone="muted"
            hairline={false}
          />
        ) : (
          lines.map((line, i) => (
            <StorageRow
              key={line.code}
              line={line}
              docked={fleet !== null}
              selected={held?.code === line.code ? held.move : null}
              onPress={(move) => setHeld({ code: line.code, move })}
              hairline={i < lines.length - 1}
            />
          ))
        )}
      </SheetSection>

      {open && fleet && held && (
        <MoveTray key={`${open.code}:${held.move}`} line={open} move={held.move} fleet={fleet} onClose={() => setHeld(null)} />
      )}
    </div>
  )
}

/** One good, its two sides as a caption, and its two acts as the two cells. */
function StorageRow({
  line,
  docked,
  selected,
  onPress,
  hairline,
}: {
  line: Line
  docked: boolean
  selected: Move | null
  onPress: (move: Move) => void
  hairline: boolean
}) {
  const t = useT()
  // the premium class (0294), off the served catalogue by the line's code — as the name's own lookup is
  const goodClass = useWorld((s) => s.goodByCode[line.code]?.class)
  const stored = line.stored ? Math.floor(line.stored.qty) : 0
  const aboard = line.aboard ? Math.floor(line.aboard.qty) : 0
  const caption = [
    line.stored ? t('inn.inStorageLine', { units: formatUnits(stored), tons: formatTons(tonsOf(line.stored), 1) }) : null,
    line.aboard ? t('inn.onBoardLine', { units: formatUnits(aboard), tons: formatTons(tonsOf(line.aboard), 1) }) : null,
  ]
    .filter(Boolean)
    .join(' · ')
  return (
    <Row
      {...goodClassRow(goodClass)}
      label={
        <span className="flex min-w-0 items-center gap-x-1.5">
          <Clip className="text-t-body">{line.name}</Clip>
          <GoodKind compact goodClass={goodClass} />
        </span>
      }
      value={
        <ActPair>
          <ActCell
            label={t('inn.put')}
            figure={<Figure value={formatUnits(aboard)} />}
            onPress={() => onPress('put')}
            dead={!docked ? t('inn.noShip') : aboard > 0 ? null : t('inn.noneOnBoard')}
            selected={selected === 'put'}
            data-testid={`storage-put-${line.code}`}
          />
          <ActCell
            label={t('inn.take')}
            figure={<Figure value={formatUnits(stored)} />}
            onPress={() => onPress('take')}
            dead={!docked ? t('inn.noShip') : stored > 0 ? null : t('inn.noneStored')}
            selected={selected === 'take'}
            data-testid={`storage-take-${line.code}`}
          />
        </ActPair>
      }
      hairline={hairline}
      under="label"
      pair
      data-testid="storage-row"
    >
      <span className="block text-t-caption text-ink-faint">{caption}</span>
    </Row>
  )
}

/** The pressed cell, unfolded: the count, the ship's cargo, the server's answer, one button.
 *  Split so its hooks run only while a cell is open. */
function MoveTray({
  line,
  move,
  fleet,
  onClose,
}: {
  line: Line
  move: Move
  fleet: FleetView
  onClose: () => void
}) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [qty, setQty] = useState<number | null>(null)
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const issue = useWorld((s) => s.issue)
  // A SELECTOR RETURNS A SERVED REFERENCE, never a fresh literal (worldStore rule; React #185).
  const verbs = useWorld((s) => s.snapshot?.verbs)
  const spec = findVerb(verbs ?? [], move === 'put' ? 'STORE' : 'TAKE')

  const source = move === 'put' ? line.aboard : line.stored
  const there = source ? Math.floor(source.qty) : 0
  const chosen = Math.max(0, Math.min(qty ?? there, there))

  // THE LINE, composed once and previewed and issued as the same string. No fleet name on it:
  // STORE and TAKE parse exactly as BUY and SELL do (0070 §5) — a good, then a count — and a
  // leading name would be read as the good.
  const text = spec !== undefined && chosen > 0 ? orderText(spec, { good: line.code, qty: String(chosen) }, null) : null
  const preview = useOrderPreview(fleet.id, text)
  const est = preview.estimate ? moveEstimate(preview.estimate) : null
  const live = text !== null && !sending && preview.refusal === null

  const send = () => {
    if (text === null || !live) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const okay = await issue(fleet.id, text, null)
      setSending(false)
      if (okay) onClose()
      else setRefusal(useWorld.getState().refusal)
    })()
  }

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`${line.name} · ${move === 'put' ? 'put in storage' : 'take on board'}`}
      data-testid="storage-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          busy={sending}
          busyLabel={t('inn.sending')}
          disabled={!live}
          onClick={send}
          data-testid="storage-act"
        >
          {move === 'put' ? t('inn.putN', { units: formatUnits(chosen) }) : t('inn.takeN', { units: formatUnits(chosen) })}
        </Button>
      }
    >
      <Row label={t('inn.inStorage')} value={<Figure value={formatUnits(line.stored ? Math.floor(line.stored.qty) : 0)} size="figure" />} />
      <Row label={t('inn.onBoard')} value={<Figure value={formatUnits(line.aboard ? Math.floor(line.aboard.qty) : 0)} size="figure" />} />

      <div className="py-3">
        <Stepper
          value={chosen}
          onChange={setQty}
          max={there}
          min={there > 0 ? 1 : 0}
          step={1}
          unit={t('trade.unitsUnit')}
          label={t('inn.unitsOf', { name: line.name })}
          presets={there > 0 ? [{ label: t('inn.all'), value: there }] : undefined}
          data-testid="storage-qty"
        />
      </div>

      {/* WHAT IT DOES TO THE SHIP — the trade tray's own line, so the count reads against the bar
          under it. The bar carries no `after`: nothing serves it for a STORE or a TAKE (header). */}
      {chosen > 0 && (
        <Row
          label={t('inn.cargoSpace')}
          tone="muted"
          value={<Figure value={formatTons(chosen * line.bulk, 1)} />}
          hairline={false}
          data-testid="storage-space-needed"
        />
      )}
      <CargoBar used={fleetHoldUsed(fleet)} total={fleetHoldTotal(fleet)} free={fleet.free_hold} className="py-2" />

      {/* THE SERVER'S OWN ANSWER for this count, before the press. A TAKE moves what fits and
          leaves the rest in storage (0070: `fleet_load` returns what fitted) — said in units. */}
      {move === 'take' && est !== null && est.qty !== null && est.qty < chosen && (
        <Note tone="warning" data-testid="storage-fits">
          {t('inn.onlyFit', { units: formatUnits(est.qty) })}
        </Note>
      )}
      {preview.refusal && (
        <Note tone="warning" code={preview.refusal.code} figures={preview.refusal.figures} data-testid="storage-preview-refusal">
          {preview.refusal.sentence}
        </Note>
      )}

      {/* The one rule a player must know about storage, said where it applies and nowhere else. */}
      <Row label={t('inn.pickupHere')} tone="muted" hairline={false} />
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </Tray>
  )
}
