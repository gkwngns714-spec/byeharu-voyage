import { useMemo, type ReactNode } from 'react'
import { Flag, ListPanel, PageSplit, Row } from '../../components/ui'
import { formatInt } from '../../lib/format'
import type { SnapshotNation } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { portNameOf, useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'
import { useT } from '../../lib/i18n'

// THE NATIONS FACE — the flags this world sails under, and the capital each names, ON THE PAGE (2026-11-02, owner row 267;
// the pattern is Stats', docs/dev-log/2026-11-02-stats-design.md). Rows, not a table: a nation is two facts. The three-letter
// code is not one of them any more — every screen prints the name now (0028's catalogue is why), so the code is a filter word,
// never a column.
//
// GP1 (0187, docs/GREAT_POWERS.md): two groups, in the server's words — the ten GREAT POWERS a company sails for (`great`, the
// flags shown large), then the thirteen LOCAL RULERS, who rule the cities they founded and hold no influence. `great` is the
// server's; nothing here decides it. The two groups are the face's two blocks, so they are its MAIN | SIDE: the great powers
// in the main card (the search on its title line, two columns of rows at 1,440), the local rulers in the side card — the
// tray's column, used. A nation has no detail to open, so its rows are read-only.

const EMPTY: readonly SnapshotNation[] = []

export function NationsFace({ query, search }: { query: string; search: ReactNode }) {
  const t = useT()
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
  const great = rows.filter((n) => n.great)
  const rulers = rows.filter((n) => !n.great)

  const list = (list: SnapshotNation[], size: 'title' | 'body') =>
    list.length === 0 ? (
      <NoAnswer />
    ) : (
      list.map((n) => (
        <Row
          key={n.code}
          mark={<Flag code={n.code} name={n.name} size={size} />}
          label={n.name}
          value={n.capital === null ? t('codex.noCapital') : portNameOf(portByCode, n.capital)}
          tone={n.capital === null ? 'muted' : 'default'}
          hairline={false}
          data-testid="nation-row"
        />
      ))
    )

  return (
    <PageSplit
      data-testid="nation-rows"
      main={
        <ListPanel look="card" columns="fit" title={t('codex.great')} count={formatInt(great.length)} trailing={search} data-testid="nation-great">
          {list(great, 'title')}
        </ListPanel>
      }
      side={
        <ListPanel look="card" title={t('codex.rulers')} count={formatInt(rulers.length)} data-testid="nation-rulers">
          {list(rulers, 'body')}
        </ListPanel>
      }
    />
  )
}
