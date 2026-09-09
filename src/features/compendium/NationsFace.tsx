import { useMemo } from 'react'
import { Row } from '../../components/ui'
import type { SnapshotNation } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { portNameOf, useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'

// THE NATIONS FACE — the flags this world sails under, and the capital each names. Rows, not a
// table: a nation is two facts. The three-letter code is not one of them any more — every screen
// prints the name now (0028's catalogue is why), so the code is a filter word, never a column.

const EMPTY: readonly SnapshotNation[] = []

export function NationsFace({ query }: { query: string }) {
  const snapshot = useWorld((s) => s.snapshot)
  const portByCode = useWorld((s) => s.portByCode)
  const nations = snapshot?.nations ?? EMPTY

  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return [...nations]
      .sort((a, b) => a.name.localeCompare(b.name))
      .filter((n) =>
        foldedMatch(needle, n.name, n.code, n.capital === null ? null : portNameOf(portByCode, n.capital)),
      )
  }, [nations, query, portByCode])

  if (rows.length === 0) return <NoAnswer />

  return (
    <div data-testid="nation-rows">
      {rows.map((n, i) => (
        <Row
          key={n.code}
          mark={<span aria-hidden>{n.flag_char}</span>}
          label={n.name}
          value={n.capital === null ? 'no capital named' : portNameOf(portByCode, n.capital)}
          tone={n.capital === null ? 'muted' : 'default'}
          hairline={i < rows.length - 1}
        />
      ))}
    </div>
  )
}
