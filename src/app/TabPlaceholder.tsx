import type { ReactNode } from 'react'
import { EmptyState, Icon, PageHeader, Screen, SectionLabel, type IconName } from '../components/ui'

// THE ONE "this tab has no content yet" surface.
//
// Eight tabs shipped empty on day one. Writing the same header + empty card eight times would put
// eight copies of one decision in the repo, and the day the empty state changes, seven of them
// would be missed. So the shell owns the shape and each feature screen supplies only its own
// words: what the tab is, and the named things that will live on it.
//
// It is TEMPORARY BY CONSTRUCTION: a screen stops calling this the moment it has real content, and
// when the last caller is gone this file is deleted. It is not a design-system primitive and does
// not belong in components/ui.

export function TabPlaceholder({
  eyebrow,
  title,
  subtitle,
  icon,
  summary,
  willHold,
  note,
}: {
  eyebrow: string
  title: string
  subtitle: string
  icon: IconName
  /** One sentence: what this tab is FOR. */
  summary: ReactNode
  /** The named things that will live here. Concrete nouns, not "features". */
  willHold: readonly string[]
  /** Optional standing rule about this tab that must be visible even while it is empty. */
  note?: ReactNode
}) {
  return (
    <Screen>
      <PageHeader eyebrow={eyebrow} title={title} subtitle={subtitle} />
      <EmptyState
        data-testid={`placeholder-${title.toLowerCase()}`}
        icon={<Icon name={icon} size={28} />}
        title="Nothing here yet"
        body={
          <div className="space-y-3 text-left">
            <p>{summary}</p>
            {note}
            <div>
              <SectionLabel>Will live here</SectionLabel>
              <ul className="space-y-1">
                {willHold.map((item) => (
                  <li key={item} className="flex gap-2 text-sm text-ink-muted">
                    <span aria-hidden className="font-mono text-ink-faint">
                      ·
                    </span>
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            </div>
            <p className="font-mono text-xs uppercase tracking-wider text-ink-faint">
              Skeleton only — no server call is wired to this tab.
            </p>
          </div>
        }
      />
    </Screen>
  )
}
