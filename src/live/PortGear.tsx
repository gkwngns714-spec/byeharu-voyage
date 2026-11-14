import { useState } from 'react'
import { Button, Figure, Icon, Note, Row, Tile, TileField, Tray, type TrayDetent } from '../components/ui'
import { formatDucats } from '../lib/format'
import { cmdBuyStarter, worldStarterGear } from '../lib/rpc'
import type { FleetView, Refusal, StarterGear, StarterPiece, StarterState } from '../lib/rpc'
import { useT, type TKey } from '../lib/i18n'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// GEAR — the starter pieces every harbour sells (0425), bought and fitted in one press.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-15: *"and in port, there should be a beginner's gear for ships."* Three plain pieces, one for each rack a
// new hull has a place in, at a low price paid to the city. Every figure and every state here is the server's
// (`world.starter_gear`): the price, the effects in its own words, and for each ship of the fleet whether a piece is fitted,
// can go on, has its rack full, or has no place at all. Nothing is judged here: Deck, Hands and the purse are judged at the
// press (`cmd.buy_starter`), and its refusal is printed as served.
//
// THE SHAPE: the three pieces as a tile field (two abreast on a phone, the face's whole catalogue on one glass); a press opens
// the piece's tray, which reads what it gives, its price and one row a ship with that ship's own act at the right edge.

const STATE_WORD: Record<Exclude<StarterState, 'open'>, TKey> = {
  fitted: 'town.g_fitted',
  full: 'town.g_full',
  no_place: 'town.g_noPlace',
}

export function PortGear({ fleet }: { fleet: FleetView | null }) {
  const t = useT()
  const fleetId = fleet?.id ?? null
  const read = useServedRead<StarterGear>(`starter-gear:${fleetId ?? '-'}`, () => worldStarterGear(fleetId), { name: 'worldStarterGear' })
  const view = read.view
  const [open, setOpen] = useState<StarterPiece | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')

  if (!view) return <Note tone="neutral">{t('town.g_loading')}</Note>

  return (
    <div data-testid="port-gear">
      <p className="mb-3 text-t-label text-ink-muted">{t('town.g_intro')}</p>
      {!fleet ? (
        <Note tone="neutral" className="mb-3">{t('town.g_noFleet')}</Note>
      ) : !view.here ? (
        <Note tone="warning" className="mb-3">{t('town.g_notHere')}</Note>
      ) : null}
      {view.purse !== null && (
        <Row label={t('town.g_purse')} value={<Figure value={formatDucats(view.purse)} />} hairline={false} data-testid="gear-purse" />
      )}
      <TileField>
        {view.items.map((piece) => (
          <Tile
            key={piece.code}
            mark={<Icon name="ship" size={20} />}
            name={piece.name}
            meta={piece.effects.join(' · ')}
            tap="whole"
            onClick={() => {
              setDetent('half')
              setOpen(piece)
            }}
            figure={<Figure value={formatDucats(piece.price)} />}
            data-testid={`gear-${piece.code}`}
          />
        ))}
      </TileField>
      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="gear-tray"
        >
          <PieceTray piece={open} view={view} fleet={fleet} />
        </Tray>
      )}
    </div>
  )
}

/** One piece: what it gives, its price, and one row a ship with that ship's act. */
function PieceTray({ piece, view, fleet }: { piece: StarterPiece; view: StarterGear; fleet: FleetView | null }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const [busy, setBusy] = useState<string | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  const buy = (shipId: string) => {
    if (!fleet || busy) return
    setBusy(shipId)
    setRefusal(null)
    void (async () => {
      const r = await cmdBuyStarter(fleet.id, shipId, piece.code)
      if (r.ok) await refresh()
      else setRefusal(r.refusal)
      setBusy(null)
    })()
  }

  return (
    <div data-testid={`gear-tray-${piece.code}`}>
      <Row label={t('yard.gives')}>
        <span className="block break-words text-t-label text-ink">{piece.effects.join(' · ')}</span>
      </Row>
      <Row label={t('town.g_price')} value={<Figure value={formatDucats(piece.price)} />} />
      <Row label={t('town.g_rack')} value={<span className="text-t-label text-ink">{piece.word}</span>} />
      <p className="my-2 break-words text-t-caption text-ink-faint">{piece.note}</p>
      {view.ships.length > 0 && (
        <>
          <h3 className="mt-3 text-t-label font-semibold text-ink">{t('town.g_ships')}</h3>
          {view.ships.map((ship, i) => {
            const state = ship.pieces[piece.code] ?? 'no_place'
            return (
              <Row
                key={ship.id}
                label={ship.name}
                wholeName
                end
                hairline={i < view.ships.length - 1}
                value={
                  state === 'open' && view.here ? (
                    <Button
                      variant="primary"
                      size="sm"
                      busy={busy === ship.id}
                      busyLabel={t('town.g_buying')}
                      disabled={busy !== null}
                      onClick={() => buy(ship.id)}
                      data-testid={`gear-buy-${piece.code}-${i}`}
                    >
                      {`${t('town.g_buy')} ${formatDucats(piece.price)}`}
                    </Button>
                  ) : (
                    <span className={`text-t-label ${state === 'fitted' ? 'text-success' : 'text-ink-faint'}`}>
                      {state === 'open' ? '' : t(STATE_WORD[state])}
                    </span>
                  )
                }
                data-testid={`gear-ship-${i}`}
              >
                <span className="text-t-caption text-ink-faint">{ship.class}</span>
              </Row>
            )
          })}
        </>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}
