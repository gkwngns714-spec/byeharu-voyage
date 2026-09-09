import { useState } from 'react'
import {
  Bar,
  Button,
  Chip,
  Corner,
  Field,
  FieldButton,
  Figure,
  Hint,
  Icon,
  Nav,
  Note,
  Row,
  Segmented,
  Sheet,
  SheetSection,
  Stepper,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'

// THE GALLERY — every primitive, in every state, on one page at 390×844.
//
// ── WHY IT IS A ROUTE AND NOT A THROWAWAY FILE ─────────────────────────────────────────────────
// Two jobs, and only a mounted page does either:
//   1. It is the only way to SEE whether the twelve read as one system. Step 2 changes no screen,
//      so without this page the new set is never rendered anywhere and the first look at it would
//      be halfway through step 4, with a screen's worth of other changes mixed in.
//   2. tests/primitives.geometry.spec.ts measures the primitives HERE — 52px rows, 44px targets,
//      the tray's three detents, and the tile field standing still while a tray opens. A geometry
//      proof needs a mount point, and pointing it at a screen would mean measuring the primitives
//      through whatever that screen happens to compose.
//
// IT IS DELIBERATELY OUTSIDE `RequireAuth` AND `AppShell` (src/app/App.tsx). Two consequences,
// both wanted: it renders instantly with no world to boot, so the geometry spec costs seconds
// rather than the 78s cold chain every other browser spec pays; and it does not skip on a cloud
// build, which is the state appReady.fixture warns is otherwise invisible.
//
// NOTHING HERE READS THE STORE. Every figure on this page is a literal, and that is the point: a
// gallery that needed a world would be a screen.

const GOODS = [
  { name: 'Aniseed', buy: 78, sell: 72, low: 62, high: 94, stock: 3 },
  { name: 'Pepper', buy: 149, sell: 137, low: 113, high: 170, stock: 5 },
  { name: 'Muslin', buy: 512, sell: 486, low: 430, high: 610, stock: 1 },
  { name: 'Amber', buy: 1204, sell: 1150, low: 980, high: 1400, stock: 6 },
]

export function GalleryScreen() {
  const [detent, setDetent] = useState<TrayDetent>('closed')
  const [inline, setInline] = useState<TrayDetent>('closed')
  const [face, setFace] = useState('trade')
  const [filter, setFilter] = useState('')
  const [qty, setQty] = useState(20)
  const [picked, setPicked] = useState('Aniseed')

  return (
    <div className="bv-sea h-dvh" data-testid="gallery">
      <Sheet
        title="Primitives"
        trailing={<Chip on>Step 2</Chip>}
      >
        <SheetSection heading="Figure">
          <div className="flex flex-wrap items-baseline gap-4">
            <Figure value="8,000" unit="d." size="hero" />
            <Figure value="78" unit="d./t" size="figure" />
            <Figure value="15.0" unit="days" tone="success" />
            <Figure value="4" unit="/ 60 t" tone="muted" />
            <Figure value="0" unit="kn" tone="faint" />
            <Figure value="1.9" unit="d" tone="info" />
            <Figure value="−320" unit="d." tone="danger" />
          </div>
        </SheetSection>

        <SheetSection heading="Row">
          <Row mark={<Icon name="anchor" size={20} />} label="Lisbon" value={<Figure value="0" unit="nm" />} data-testid="gallery-row" />
          <Row label="Market tax" value={<Figure value="3.0" unit="%" />} data-testid="gallery-row" />
          <Row
            label="Gaivota"
            value={<Figure value="1.9" unit="d" tone="info" />}
            chevron
            onClick={() => setDetent('peek')}
            data-testid="gallery-row"
          />
          <Row label="Warehouse" tone="muted" value="tier 5" hairline={false} data-testid="gallery-row" />
        </SheetSection>

        <SheetSection heading="Bar">
          <div className="flex flex-col gap-3">
            <Bar pct={62} label="hull" figure={<Figure value="62" unit="%" />} />
            <Bar pct={18} tone="warning" label="stores" figure={<Figure value="2.1" unit="d" />} />
            <Bar pct={92} tone="danger" label="hold" figure={<Figure value="55" unit="/ 60 t" />} />
            <Bar value={4} of={6} tone="success" label="stock" figure={<Figure value="4" unit="/ 6" />} />
            <Bar value={2} of={5} tone="neutral" label="tries" />
          </div>
        </SheetSection>

        <SheetSection heading="Tile" trailing={<Chip on={filter !== ''} onClick={() => setFilter('')}>Clear</Chip>}>
          <Field
            placeholder="Filter goods"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            onClear={() => setFilter('')}
          />
          <TileField className="mt-2" data-testid="gallery-field">
            {GOODS.map((g) => (
              <Tile
                key={g.name}
                data-testid="gallery-tile"
                mark={<Icon name="spice" size={20} />}
                name={g.name}
                meta="spice"
                state={picked === g.name ? 'selected' : 'rest'}
                tap="head"
                onClick={() => {
                  setPicked(g.name)
                  setDetent('peek')
                }}
                figure={<Figure value={g.buy} />}
                second={<Figure value={g.sell} tone="muted" />}
                bar={<Bar value={g.stock} of={6} tone="neutral" label="stock" />}
              />
            ))}
            <Tile name="Ivory" meta="no rule reads this yet" state="muted" data-testid="gallery-tile" />
            <Tile
              name="Sail"
              meta="set a course"
              mark={<Icon name="compass" size={20} />}
              tap="whole"
              onClick={() => setDetent('half')}
              data-testid="gallery-tile"
            />
          </TileField>
        </SheetSection>

        <SheetSection heading="Chip and Segmented">
          <Segmented
            label="Port faces"
            value={face}
            onChange={setFace}
            segments={[
              { id: 'trade', label: 'Trade' },
              { id: 'town', label: 'Town' },
              { id: 'store', label: 'Store' },
              { id: 'craft', label: 'Craft' },
              { id: 'inn', label: 'Inn' },
            ]}
          />
          <div className="mt-2 flex flex-wrap gap-2">
            <Chip on>All</Chip>
            <Chip>Trade</Chip>
            <Chip>Voyage</Chip>
            <Chip>
              <Icon name="coin" size={16} />
              Crew
            </Chip>
          </div>
        </SheetSection>

        <SheetSection heading="Button">
          <div className="flex flex-wrap gap-2">
            <Button variant="primary">Buy 20 t</Button>
            <Button variant="secondary">Discard</Button>
            <Button variant="quiet">Sign out</Button>
            <Button variant="destructive">Clear queue</Button>
            <Button variant="primary" disabled>
              Issue
            </Button>
            <Button variant="secondary" busy busyLabel="Sending…">
              Send
            </Button>
            <Button variant="secondary" size="icon" aria-label="Close">
              <Icon name="close" size={20} />
            </Button>
          </div>
          {/* The 36px size, fenced: it is an IN-ROW secondary action and the only thing in this
              game allowed under the 44px floor, so the geometry spec skips this box by name
              rather than carrying a list of ids. */}
          <div className="mt-2 flex flex-wrap gap-2" data-targets="36">
            <Button variant="secondary" size="sm">
              Take aboard
            </Button>
            <Button variant="quiet" size="sm">
              Land it here
            </Button>
          </div>
        </SheetSection>

        <SheetSection heading="Field and Stepper">
          <FieldButton value="Lisbon" onClick={() => setDetent('full')} />
          <div className="mt-3">
            <Stepper
              label="tuns of aniseed"
              value={qty}
              onChange={setQty}
              max={120}
              cap={40}
              unit="t"
              presets={[
                { label: 'Max', value: 40 },
                { label: '10', value: 10 },
                { label: 'None', value: 0 },
              ]}
            />
          </div>
        </SheetSection>

        <SheetSection heading="Note">
          <div className="flex flex-col gap-2">
            <Note tone="accent" action={<Button variant="quiet">OK</Button>}>
              The world was rebuilt from the first migration.
            </Note>
            <Note tone="warning">She is at sea. Crew are signed on in port.</Note>
            <Note
              tone="danger"
              code="E_HOLD_FULL"
              figure={<Bar pct={100} tone="danger" label="hold" figure={<Figure value="60" unit="/ 60 t" />} />}
              action={<Button variant="secondary">Sell 20 t</Button>}
            >
              The hold is full.
            </Note>
            <Note tone="success">Fair on — 30% off the cut, 2 days.</Note>
            <Note tone="info">Gaivota is at sea, 1.9 days out.</Note>
            <Note>Nothing is on at this quay.</Note>
          </div>
        </SheetSection>

        <SheetSection heading="Hint">
          <Hint>Water and food take the same tuns as cargo.</Hint>
          <Hint more="A price moves as the quay's stock moves. What you pay is the buy side of the spread, with the port's cut and the market tax already inside it — there is no second figure to add.">
            The price already carries the cut.
          </Hint>
        </SheetSection>

        <SheetSection heading="Corner">
          <div className="relative h-40 overflow-hidden rounded-tile bg-sea-2">
            <Corner slot="top-left" label="1 fleet" mark={<Icon name="ship" size={18} />} defaultOpen>
              <Row label="Gaivota" value={<Figure value="15" unit="d" />} hairline={false} />
            </Corner>
            <Corner slot="top-right" label="Zoom" mark={<Icon name="plus" size={18} />} />
            <Corner slot="bottom-right" label="Cádiz" mark={<Icon name="anchor" size={18} />} />
          </div>
        </SheetSection>

        <SheetSection heading="Nav">
          <div className="overflow-hidden rounded-tile">
            <Nav
              current="port"
              items={[
                { id: 'command', label: 'Command', icon: 'compass', href: '#' },
                { id: 'fleets', label: 'Fleets', icon: 'ship', href: '#' },
                { id: 'port', label: 'Port', icon: 'anchor', href: '#' },
                { id: 'market', label: 'Market', icon: 'scales', href: '#' },
                { id: 'map', label: 'Map', icon: 'chart', href: '#' },
                { id: 'cabin', label: 'Cabin', icon: 'profile' },
              ]}
            />
          </div>
        </SheetSection>

        <SheetSection heading="Tray">
          <div className="flex flex-wrap gap-2">
            <Chip on={detent === 'peek'} onClick={() => setDetent('peek')} data-testid="tray-peek">
              Peek
            </Chip>
            <Chip on={detent === 'half'} onClick={() => setDetent('half')} data-testid="tray-half">
              Half
            </Chip>
            <Chip on={detent === 'full'} onClick={() => setDetent('full')} data-testid="tray-full">
              Full
            </Chip>
            <Chip on={detent === 'closed'} onClick={() => setDetent('closed')} data-testid="tray-shut">
              Closed
            </Chip>
          </div>
          <div className="mt-3">
            <Chip on={inline !== 'closed'} onClick={() => setInline(inline === 'closed' ? 'peek' : 'closed')} data-testid="tray-inline">
              Inline tray
            </Chip>
          </div>
          {inline !== 'closed' && (
            <div className="mt-3">
              <Tray
                mode="inline"
                detent={inline}
                onDetentChange={setInline}
                title="Aniseed · buy"
                data-testid="demo-tray-inline"
              >
                <Row label="on the quay" value={<Figure value="120" unit="/ 400 t" />} hairline={false} />
              </Tray>
            </div>
          )}
        </SheetSection>
      </Sheet>

      <Tray
        detent={detent}
        onDetentChange={setDetent}
        title={`${picked} · buy`}
        data-testid="demo-tray"
        action={
          <Button variant="primary" className="w-full">
            Buy {qty} t · {(qty * 78).toLocaleString()}
          </Button>
        }
      >
        <Stepper label="tuns" value={qty} onChange={setQty} max={120} cap={40} unit="t" />
        <Row label="costs" value={<Figure value={(qty * 78).toLocaleString()} unit="d." />} />
        <Row label="the hold stops you at" value={<Figure value="40" unit="t" tone="warning" />} />
        <Row label="Bargain" value={<Figure value="45" unit="%" />} hairline={false} />
      </Tray>
    </div>
  )
}
