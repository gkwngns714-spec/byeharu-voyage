import { useMemo, type ReactNode } from 'react'
import { Flag, ListPanel, Row } from '../../components/ui'
import { formatInt } from '../../lib/format'
import type { SnapshotNation } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { portNameOf, useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'
import { useT } from '../../lib/i18n'

// THE NATIONS FACE — the flags this world sails under, and the capital each names, ON THE GLASS (the unfold
// slice, 2026-11-02). Rows, not a table: a nation is two facts. The three-letter code is not one of them any
// more — every screen prints the name now (0028's catalogue is why), so the code is a filter word, never a column.
//
// GP1 (0187, docs/GREAT_POWERS.md): two groups, in the server's words — the ten GREAT POWERS a
// company sails for (`great`, the flags shown large), then the thirteen LOCAL RULERS, who rule the
// cities they founded and hold no influence. `great` is the server's; nothing here decides it.
// A nation has no detail to open, so its rows are read-only and stand at their text line.

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

  const groups: [string, string, SnapshotNation[], 'title' | 'body'][] = [
    [t('codex.great'), 'nation-great', rows.filter((n) => n.great), 'title'],
    [t('codex.rulers'), 'nation-rulers', rows.filter((n) => !n.great), 'body'],
  ]
  return (
    <ListPanel title={t('codex.countNations', { n: formatInt(rows.length), count: rows.length })} trailing={search} data-testid="codex-list">
      {rows.length === 0 ? (
        <NoAnswer />
      ) : (
        <div data-testid="nation-rows">
          {groups
            .filter(([, , list]) => list.length > 0)
            .map(([heading, testId, list, size]) => (
              <div key={testId} data-testid={testId}>
                <span className="block pt-2 text-t-caption font-semibold text-ink-muted">{heading}</span>
                {list.map((n, i) => (
                  <Row
                    key={n.code}
                    mark={<Flag code={n.code} name={n.name} size={size} />}
                    label={n.name}
                    value={n.capital === null ? t('codex.noCapital') : portNameOf(portByCode, n.capital)}
                    tone={n.capital === null ? 'muted' : 'default'}
                    hairline={i < list.length - 1}
                    data-testid="nation-row"
                  />
                ))}
              </div>
            ))}
        </div>
      )}
    </ListPanel>
  )
}
