import { useState } from 'react'
import {
  Button,
  Card,
  CardRow,
  Chip,
  Figure,
  ListPanel,
  PageSplit,
  Row,
  SeriesChart,
  Sheet,
  StatCard,
  StatCell,
  StatStrip,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { COIN, formatDucats, formatInt, formatPctChange } from '../../lib/format'

// THE PAGE, IN THE GALLERY — the pattern every screen takes in its turn (2026-11-02, owner row 267).
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now everything is
// on left, too packed."* — screenLayout.ts "THE PAGE", Card.tsx, docs/dev-log/2026-11-02-stats-design.md. This page is the pattern with
// literal figures: a stat strip, a MAIN | SIDE split whose side is the tray's column, two cards across, a card list with its rows in
// columns, and a tray that slides over the side. The next slice (Codex, History, Rank, Routes, HQ, Fleets, the Map) copies THIS
// composition; tests/primitives.geometry.spec.ts measures it here — the strip's 24-px figures, a card's padding at each glass, the
// split's 840 | 416 at 1,440 (792 | 384 at 1,280, 584 | 352 at 1,024), a list row's 52 / 60 px, and the tray standing over the side
// column — without the 78 s cold boot of a screen. Like the gallery it is outside `RequireAuth` and `AppShell` and reads no store.

const GOODS = [
  ['Aniseed', 78.2, 0.031],
  ['Pepper', 149, -0.012],
  ['Muslin', 512, 0.004],
  ['Amber', 1204, 0.12],
  ['Silk', 333, -0.021],
  ['Saffron', 2210, 0.0],
  ['Tin', 61.4, 0.008],
  ['Porcelain', 880, -0.034],
] as const

export function PageGalleryScreen() {
  const [detent, setDetent] = useState<TrayDetent>('closed')
  return (
    <div className="bv-sea h-dvh" data-testid="gallery-page">
      <Sheet title="The page" layout="page" trailing={<Chip on>Stats first</Chip>}>
        <StatStrip aria-label="Right now" data-testid="gallery-strip">
          <StatCard label="Money" value={40000} format={formatDucats} tone="accent" data-testid="gallery-stat" />
          <StatCard label="At sea" value={3} format={formatInt} data-testid="gallery-stat" />
          <StatCard label="Recent trades" value={12} format={formatInt} data-testid="gallery-stat" />
          <StatCard label="World money" value={131367515} format={formatDucats} data-testid="gallery-stat" />
        </StatStrip>

        <PageSplit
          data-testid="gallery-split"
          sideFirst
          main={
            <>
              <CardRow>
                <Card title="Who holds it" data-testid="gallery-card">
                  <StatCell look="stacked" label="Players" value={1062515} format={formatDucats} />
                  <div className="mt-3">
                    <StatCell look="line" label="Merchant purses" value={130305000} format={formatDucats} data-testid="gallery-line" />
                    <StatCell look="line" label="City purses" value={0} format={formatDucats} data-testid="gallery-line" />
                  </div>
                </Card>
                <Card title="World money" data-testid="gallery-card">
                  <SeriesChart
                    points={[0, 1, 2, 3, 4, 5, 6, 7].map((h) => ({ atMs: Date.UTC(2026, 9, 25, h), value: [26_061_000, 26_100_000, 25_990_000, 26_300_000, 26_250_000, 26_400_000, 26_350_000, 26_500_000][h] }))}
                    format={formatDucats}
                    label="world money, eight hours"
                    height={176}
                  />
                </Card>
              </CardRow>
              <ListPanel look="card" columns="fit" title="Every good" count={String(GOODS.length)} data-testid="gallery-list">
                {GOODS.map(([name, price, move]) => (
                  <Row key={name} label={name} value={<Figure value={String(price)} unit={COIN} />} hairline={false} data-testid="gallery-list-row">
                    <span className="text-t-caption text-ink-faint">{formatPctChange(move)}</span>
                  </Row>
                ))}
              </ListPanel>
            </>
          }
          side={
            <Card title="Money log" data-testid="gallery-side-card">
              <StatCell look="line" label="Casa de Aveiro" value={40000} format={formatDucats} />
              <StatCell look="line" label="Rosenkrantz & Søn" value={112000} format={formatDucats} />
              <div className="mt-4">
                <Button variant="secondary" onClick={() => setDetent('full')} data-testid="gallery-page-open">
                  Open tray
                </Button>
              </div>
            </Card>
          }
        />
        {detent !== 'closed' && (
          <Tray detent={detent} onDetentChange={setDetent} title="Large chart" data-testid="gallery-page-tray">
            <p className="text-t-label text-ink-muted">A docked tray opened inside a page stands over the side column.</p>
          </Tray>
        )}
      </Sheet>
    </div>
  )
}
