import { useState } from 'react'
import {
  ActCell,
  Bar,
  Button,
  Card,
  CargoBar,
  Clip,
  Figure,
  GoodKind,
  Note,
  PageThree,
  Row,
  Segmented,
  Skeleton,
  Stepper,
  Tray,
  goodClassRow,
  type TrayDetent,
} from '../components/ui'
import { fleetHoldTotal, fleetHoldUsed } from '../domain/fleet'
import { findVerb, moveEstimate, orderText, useCommandDraft } from '../domain/order'
import { hasBuilding } from '../domain/port'
import { formatInt, formatOfTotal, formatTons, formatUnits } from '../lib/format'
import type { FleetView, Refusal, SnapshotPort, StoredGood } from '../lib/rpc'
import { PortForge } from './PortForge'
import { useForge } from './useForge'
import { useOrderPreview } from './useOrderPreview'
import { useStorage } from './useStorage'
import { useWorld } from './worldStore'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PRODUCTION — storage, cargo and recipes on one page of the HQ
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-06: *"On HQ, merge storage and forge. left side is storage, center is cargo, right side is recipes. i should be
// able to move cargo - storage. then once the production is made on right, i should also move from recipe - cargo."* The tab's word is
// Production (owner, the same day); the three columns keep their own: Storage, Cargo, Recipes.
//
// ── THE TWO VERBS ARE THE ONLY MOVERS ──────────────────────────────────────────────────────────
// `STORE <good> <n>` (cargo to storage) and `TAKE <good> <n>` (storage to cargo), 0070's orders, previewed by `cmd.preview` and issued by
// `cmd.issue`. There is no third path. A recipe draws from this city's storage and its product lands there (`cmd.forge_good`, 0281), so
// a Finished line IS a stored line and its move IS a `TAKE`. The forge is instant: no job, no timer, so nothing is "in production".
//
// ── WHAT FINISHED MEANS ────────────────────────────────────────────────────────────────────────
// A stored good that a recipe here makes. The server keeps no mark of how a stored good got there, so a made good bought and stored
// reads as Finished too. Both reads are the server's; nothing is worked out but which served line goes under which heading.
//
// ── ONE READ, THREE COLUMNS ────────────────────────────────────────────────────────────────────
// `world.warehouse` serves storage and cargo in one read, so the two cannot disagree. Picking a fleet is a new subject and its cargo is
// asked for; storage is the same whichever fleet is asked about, so it stays on screen while the answer is on the wire (owner's law:
// a press restructures nothing). The fleet in hand is the command draft's one selection, the one the desk and the Map write.
//
// ── THE COLUMNS ARE ALL MOUNTED ────────────────────────────────────────────────────────────────
// From 1,024 px three across (`PageThree`). Below it one at a time under a fixed segmented control; the others are hidden by CSS, so
// the width is read once, by the stylesheet. The tray is `fixed`, so a press moves nothing in the lists.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// How big the storage is, whether a cargo fits, what a recipe needs. All are the verbs' rules and arrive answered or refused.

type Move = 'put' | 'take'
type Column = 'storage' | 'cargo' | 'recipes'
type Open = { kind: 'move'; code: string; move: Move } | { kind: 'recipe'; product: string }

/** Tons a served line takes: the server's own `tuns` for a stored line; a hold line carries `bulk` and no `tuns` (0070). */
function tonsOf(g: StoredGood): number {
  return g.tuns ?? g.qty * g.bulk
}

export function PortProduction({
  port,
  docked,
}: {
  port: SnapshotPort
  /** Your fleets lying here. Storage is only reachable from one (0070). */
  docked: readonly FleetView[]
}) {
  const t = useT()
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const fleet = docked.find((f) => f.id === draftFleetId) ?? docked[0] ?? null

  const read = useStorage(port.id, fleet?.id ?? null)
  const forge = useForge(port.id)
  // STORAGE STAYS ON SCREEN WHILE ANOTHER FLEET'S CARGO IS ASKED FOR (header). React's own "previous answer" pattern.
  const [kept, setKept] = useState(read.view)
  if (read.view !== null && read.view !== kept) setKept(read.view)
  const shed = read.view ?? (read.loading ? kept : null)

  const [column, setColumn] = useState<Column>('storage')
  const [open, setOpen] = useState<Open | null>(null)

  const stored = shed?.stored ?? []
  const aboard = read.view?.aboard ?? []
  const free = shed ? Math.max(0, shed.cap - shed.used) : 0
  const products = new Set((forge.view?.recipes ?? []).map((r) => r.product))
  const finished = stored.filter((g) => products.has(g.good))
  const held = open?.kind === 'move' ? open : null
  const pickMove = (code: string, move: Move) => setOpen({ kind: 'move', code, move })
  const shown = (id: Column) => (column === id ? 'min-w-0' : 'hidden min-w-0 lg:block')

  // The world is re-read every few seconds; a line the re-read emptied on both sides takes its tray with it.
  const heldStored = held ? stored.find((g) => g.good === held.code) : undefined
  const heldAboard = held ? aboard.find((g) => g.good === held.code) : undefined
  const heldLine = heldStored ?? heldAboard

  return (
    <div className="flex flex-col gap-3" data-testid="port-production">
      <Segmented<Column>
        fill
        className="lg:hidden"
        label={t('city.production')}
        segments={[
          { id: 'storage', label: t('city.storage') },
          { id: 'cargo', label: t('city.cargo') },
          { id: 'recipes', label: t('city.recipes') },
        ]}
        value={column}
        onChange={setColumn}
      />

      <PageThree data-testid="production-columns">
        <div className={shown('storage')}>
          <Card title={t('city.storage')} data-testid="production-storage">
            <div className="@container min-w-0">
              {!hasBuilding(port, 'warehouse') ? (
                <Note tone="neutral">{t('inn.noStorage')}</Note>
              ) : !shed ? (
                read.loading ? <Skeleton className="h-28 w-full" /> : <Note tone="neutral">{t('inn.noStorage')}</Note>
              ) : (
                <>
                  <Row
                    label={t('inn.space')}
                    value={<Figure value={formatOfTotal(shed.used, shed.cap)} unit="tons" size="figure" />}
                    hairline={false}
                    data-testid="storage-space"
                  />
                  <Bar
                    pct={shed.cap > 0 ? (shed.used / shed.cap) * 100 : 0}
                    tone={free > 0 ? 'accent' : 'warning'}
                    label={t('inn.howFull')}
                    figure={<Figure value={formatInt(free)} unit={t('inn.tonsFree')} />}
                  />
                  {stored.length === 0 ? (
                    <Row label={t('inn.nothing')} tone="muted" hairline={false} />
                  ) : (
                    stored.map((g, i) => (
                      <GoodRow
                        key={g.good}
                        good={g}
                        act={t('inn.take')}
                        dead={fleet ? null : t('inn.noShip')}
                        selected={held?.code === g.good && held.move === 'take'}
                        onPress={() => pickMove(g.good, 'take')}
                        hairline={i < stored.length - 1}
                        testid="storage-row"
                        cellTestid={`storage-take-${g.good}`}
                      />
                    ))
                  )}
                </>
              )}
            </div>
          </Card>
        </div>

        <div className={shown('cargo')}>
          <Card title={t('city.cargo')} data-testid="production-cargo">
            <div className="@container min-w-0">
              {fleet === null ? (
                <Note tone="neutral">{t('inn.noShip')}</Note>
              ) : (
                <>
                  {docked.length > 1 ? (
                    <Segmented<string>
                      fill
                      className="mb-3"
                      label={t('command.fleets')}
                      segments={docked.map((f) => ({ id: f.id, label: f.name }))}
                      value={fleet.id}
                      onChange={selectFleet}
                    />
                  ) : (
                    <p className="mb-1 text-t-label text-ink-muted" data-testid="production-fleet">{fleet.name}</p>
                  )}
                  <CargoBar used={fleetHoldUsed(fleet)} total={fleetHoldTotal(fleet)} free={fleet.free_hold} className="py-2" />
                  {read.view === null ? (
                    read.loading ? <Skeleton className="h-28 w-full" /> : null
                  ) : aboard.length === 0 ? (
                    <Row label={t('city.cargoEmpty')} tone="muted" hairline={false} />
                  ) : (
                    aboard.map((g, i) => (
                      <GoodRow
                        key={g.good}
                        good={g}
                        act={t('inn.put')}
                        dead={null}
                        selected={held?.code === g.good && held.move === 'put'}
                        onPress={() => pickMove(g.good, 'put')}
                        hairline={i < aboard.length - 1}
                        testid="cargo-row"
                        cellTestid={`storage-put-${g.good}`}
                      />
                    ))
                  )}
                </>
              )}
            </div>
          </Card>
        </div>

        <div className={shown('recipes')}>
          <Card title={t('city.recipes')} data-testid="production-recipes">
            <div className="@container min-w-0">
              <h3 className="pb-1 text-t-body font-semibold text-ink">{t('city.finished')}</h3>
              {finished.length === 0 ? (
                <Row label={t('city.noneFinished')} tone="muted" hairline={false} />
              ) : (
                finished.map((g, i) => (
                  <GoodRow
                    key={g.good}
                    good={g}
                    act={t('inn.take')}
                    dead={fleet ? null : t('inn.noShip')}
                    selected={held?.code === g.good && held.move === 'take'}
                    onPress={() => pickMove(g.good, 'take')}
                    hairline={i < finished.length - 1}
                    testid="finished-row"
                    cellTestid={`finished-take-${g.good}`}
                  />
                ))
              )}
              <div className="mt-4">
                {forge.view ? (
                  <PortForge
                    portId={port.id}
                    fleet={fleet}
                    view={forge.view}
                    open={open?.kind === 'recipe' ? open.product : null}
                    onOpen={(product) => setOpen({ kind: 'recipe', product })}
                    onClose={() => setOpen(null)}
                  />
                ) : forge.loading ? (
                  <Note tone="neutral">{t('city.forgeLoading')}</Note>
                ) : (
                  <Note tone="neutral">{t('city.forgeNone')}</Note>
                )}
              </div>
            </div>
          </Card>
        </div>
      </PageThree>

      {held && heldLine && fleet && (
        <MoveTray
          key={`${fleet.id}:${held.code}:${held.move}`}
          code={held.code}
          name={heldLine.name}
          bulk={heldLine.bulk}
          inStorage={heldStored ? Math.floor(heldStored.qty) : 0}
          onBoard={heldAboard ? Math.floor(heldAboard.qty) : 0}
          move={held.move}
          fleet={fleet}
          onClose={() => setOpen(null)}
        />
      )}
    </div>
  )
}

/** One good in a column: its name, the tons it takes, and the one act that moves it to the other side. */
function GoodRow({
  good,
  act,
  dead,
  selected,
  onPress,
  hairline,
  testid,
  cellTestid,
}: {
  good: StoredGood
  act: string
  dead: string | null
  selected: boolean
  onPress: () => void
  hairline: boolean
  testid: string
  cellTestid: string
}) {
  // the premium class (0294), off the served catalogue by the line's code, as the name's own lookup is
  const goodClass = useWorld((s) => s.goodByCode[good.good]?.class)
  return (
    <Row
      {...goodClassRow(goodClass)}
      label={
        <span className="flex min-w-0 items-center gap-x-1.5">
          <Clip className="text-t-body">{good.name}</Clip>
          <GoodKind compact goodClass={goodClass} />
        </span>
      }
      value={
        <ActCell
          label={act}
          figure={<Figure value={formatUnits(Math.floor(good.qty))} />}
          onPress={onPress}
          dead={dead}
          selected={selected}
          data-testid={cellTestid}
        />
      }
      hairline={hairline}
      under="label"
      end
      data-testid={testid}
    >
      <span className="block text-t-caption text-ink-faint">{formatTons(tonsOf(good), 1)}</span>
    </Row>
  )
}

/** The pressed cell, unfolded: the count, the ship's cargo, the server's answer, one button. Split so its hooks run only while a cell
 *  is open. NOTHING serves "tons on board after" for a STORE or a TAKE, so the `CargoBar` carries no `after` and the `Cargo space` row
 *  is the trade tray's own line, for reading a count against the bar. */
function MoveTray({
  code,
  name,
  bulk,
  inStorage,
  onBoard,
  move,
  fleet,
  onClose,
}: {
  code: string
  name: string
  bulk: number
  inStorage: number
  onBoard: number
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

  const there = move === 'put' ? onBoard : inStorage
  const chosen = Math.max(0, Math.min(qty ?? there, there))

  // THE LINE, composed once and previewed and issued as the same string. No fleet name on it: STORE and TAKE parse exactly as BUY and
  // SELL do (0070 §5), a good, then a count, and a leading name would be read as the good.
  const text = spec !== undefined && chosen > 0 ? orderText(spec, { good: code, qty: String(chosen) }, null) : null
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
      title={`${name} · ${t(move === 'put' ? 'inn.put' : 'inn.take')}`}
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
      <Row label={t('inn.inStorage')} value={<Figure value={formatUnits(inStorage)} size="figure" />} />
      <Row label={t('inn.onBoard')} value={<Figure value={formatUnits(onBoard)} size="figure" />} />

      <div className="py-3">
        <Stepper
          value={chosen}
          onChange={setQty}
          max={there}
          min={there > 0 ? 1 : 0}
          step={1}
          unit={t('trade.unitsUnit')}
          label={t('inn.unitsOf', { name })}
          presets={there > 0 ? [{ label: t('inn.all'), value: there }] : undefined}
          data-testid="storage-qty"
        />
      </div>

      {chosen > 0 && (
        <Row
          label={t('inn.cargoSpace')}
          tone="muted"
          value={<Figure value={formatTons(chosen * bulk, 1)} />}
          hairline={false}
          data-testid="storage-space-needed"
        />
      )}
      <CargoBar used={fleetHoldUsed(fleet)} total={fleetHoldTotal(fleet)} free={fleet.free_hold} className="py-2" />

      {/* THE SERVER'S OWN ANSWER for this count, before the press. A TAKE moves what fits and leaves the rest in storage (0070:
          `fleet_load` returns what fitted), said in units. */}
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
