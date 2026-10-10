import { useMemo, useState } from 'react'
import {
  Figure,
  Note,
  Row,
  Skeleton,
  OfficerTile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { COIN, formatInt, formatPctPoints } from '../../lib/format'
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
      <Note tone="warning">Could not load the captains. Retrying shortly.</Note>
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
          // THE TILE is the design system's `OfficerTile` since 2026-10-08 (a merchant's sheet prints
          // the same officer). SIGNED is a fact about the world, not an offer: whose house holds
          // their mark is read from the roster and only read. Home port is new here (0015:63).
          <OfficerTile
            key={o.code}
            name={o.name}
            specialty={o.specialty}
            bonusPct={o.bonus_pct}
            homePort={o.port ? portNameOf(portByCode, o.port) : null}
            signed={o.hired}
            takesEffect={o.takes_effect}
            onClick={() => {
              setDetent('half')
              setOpen(o)
            }}
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
          <Row label="Wage" value={<Figure value={formatInt(open.wage)} unit={`${COIN} per voyage`} />} />
          <Row
            label="Port"
            value={open.port === null ? 'none fixed' : portNameOf(portByCode, open.port)}
            tone={open.port === null ? 'muted' : 'default'}
          />
          {open.nation !== null && <Row label="Nation" value={nationNameOf(nationByCode, open.nation)} />}
          {open.hired && (
            <Row label="Working for" value={open.fleet ?? 'nobody'} tone="accent" hairline={false} />
          )}
          <p className="pt-2 text-t-label text-ink-muted">{open.blurb}</p>
          {!open.takes_effect && (
            <Note tone="neutral" className="mt-2">
              This role has no effect in the game yet. The bonus changes nothing.
            </Note>
          )}
        </Tray>
      )}
    </>
  )
}
