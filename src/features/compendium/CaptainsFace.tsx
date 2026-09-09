import { useMemo, useState } from 'react'
import {
  Figure,
  Icon,
  Note,
  Row,
  Skeleton,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { formatInt, formatPctPoints } from '../../lib/format'
import type { Officer } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'

// THE CAPTAINS FACE — every officer in the world, signed or not, in their four callings. Each is
// found at their home port and signs on there (PORT's Inn); nothing here signs anyone.
//
// SPECIALTY AND BONUS ON THE TILE, AND NOTHING ELSE (docs/UI_DIRECTION.md §6). A bonus nothing
// reads is still shown — hiding it would sell a bonus that does nothing — but as a MUTED tile,
// with the reason in the tray rather than as a line of fine print printed fifty times down the
// face. The blurb, the wage, the port and the flag are the tray's.

export function CaptainsFace({ query, answered }: { query: string; answered: boolean }) {
  const roster = useWorld((s) => s.officers)
  const portByCode = useWorld((s) => s.portByCode)
  const nationByCode = useWorld((s) => s.nationByCode)
  const officers = roster?.officers ?? null
  const [open, setOpen] = useState<Officer | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')

  const rows = useMemo(() => {
    if (officers === null) return []
    const needle = fold(query.trim())
    return officers.filter((o) =>
      foldedMatch(
        needle,
        o.name,
        o.specialty,
        o.port === null ? null : portNameOf(portByCode, o.port),
        o.nation === null ? null : nationNameOf(nationByCode, o.nation),
      ),
    )
  }, [officers, query, portByCode, nationByCode])

  if (officers === null) {
    return answered ? (
      <Note tone="warning">The roster could not be read just now. It will be tried again in a moment.</Note>
    ) : (
      <div className="space-y-2">
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-28 w-full" />
      </div>
    )
  }
  if (rows.length === 0) return <NoAnswer />

  return (
    <>
      <TileField>
        {rows.map((o) => (
          <Tile
            key={o.code}
            mark={<Icon name="crew" size={20} />}
            name={o.name}
            /* SIGNED is a fact about the world, not an offer: whose house holds their mark is
               read from the roster and only read. */
            meta={o.hired ? `${o.specialty.toLowerCase()} · signed` : o.specialty.toLowerCase()}
            figure={
              <Figure value={`+${formatPctPoints(o.bonus_pct)}`} tone={o.takes_effect ? 'success' : 'faint'} />
            }
            state={o.takes_effect ? 'rest' : 'muted'}
            tap="whole"
            onClick={() => {
              setDetent('half')
              setOpen(o)
            }}
            data-testid="officer-tile"
          />
        ))}
      </TileField>

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="officer-tray"
        >
          <Row
            label={open.specialty.toLowerCase()}
            value={
              <Figure
                value={`+${formatPctPoints(open.bonus_pct)}`}
                tone={open.takes_effect ? 'success' : 'faint'}
              />
            }
          />
          {/* "signs for" is the server's own phrase (0015's refusal says it word for word). */}
          <Row label="Signs for" value={<Figure value={formatInt(open.wage)} unit="d. a voyage" />} />
          <Row
            label="Port"
            value={open.port === null ? 'none fixed' : portNameOf(portByCode, open.port)}
            tone={open.port === null ? 'muted' : 'default'}
          />
          {open.nation !== null && <Row label="Nation" value={nationNameOf(nationByCode, open.nation)} />}
          {open.hired && (
            <Row label="Serving" value={open.fleet ?? 'ashore'} tone="accent" hairline={false} />
          )}
          <p className="pt-2 text-t-label text-ink-muted">{open.blurb}</p>
          {!open.takes_effect && (
            <Note tone="neutral" className="mt-2">
              No rule reads this specialty yet. The bonus changes nothing.
            </Note>
          )}
        </Tray>
      )}
    </>
  )
}
