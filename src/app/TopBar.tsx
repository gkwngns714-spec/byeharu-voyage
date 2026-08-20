import { Link } from 'react-router-dom'
import { Icon } from '../components/ui'
import { useWorld } from '../live/worldStore'

// THE TOP BAR — the persistent chrome that says "you are inside a game".
//
// Read off the reference captures (docs/UI_DIRECTION.md §2): every screen in 대항해시대 오리진
// carries the same triad on the left (back · title · help) and the same CURRENCY CLUSTER on the
// right, and neither is ever re-rendered by a screen. That constancy is most of what makes a
// screen feel like part of a game rather than a page in a site.
//
// WHAT THIS BAR DOES NOT DO, and why:
//   · It shows ONE figure, the purse, because the purse is the only number this server actually
//     keeps. The reference shows four currencies; inventing three more here would be decorating
//     the UI with facts the game does not have. When fame lands as a migration it gets a slot.
//   · It carries no back chevron. Eight destinations in a tab rail is a FLAT navigation model —
//     there is nothing to go back FROM — and a chevron that does nothing is worse than no chevron.
//     Screens that open a detail view own their own dismissal.
//
// The purse is deliberately NOT hidden while the world opens: a dash holds the column's width, so
// the bar does not jump by the width of a number the moment the first read lands.

export function TopBar() {
  const ducats = useWorld((s) => s.ducats)
  const busy = useWorld((s) => s.busy)

  return (
    <header className="flex min-h-11 shrink-0 items-center justify-between gap-3 border-b border-hairline bg-panel-head px-4">
      <Link
        to="/profile"
        className="min-w-0 font-mono text-xs uppercase tracking-[0.2em] text-ink-faint transition hover:text-ink"
      >
        Byeharu <span className="text-accent">Voyage</span>
      </Link>

      <div className="flex shrink-0 items-center gap-3">
        {/* The one live indicator. `busy` is a read in flight, and a read IS how time passes in
            this game (AppShell's READ_INTERVAL_MS) — so this dot is the world breathing, not a
            spinner the player is waiting on. It never blocks anything. */}
        <span
          className={`h-1.5 w-1.5 rounded-full transition-opacity ${
            busy ? 'bg-accent opacity-100' : 'bg-ink-faint opacity-25'
          }`}
          aria-hidden="true"
        />

        <span className="flex items-center gap-1.5" data-testid="purse">
          <Icon name="coin" size={14} className="text-accent" />
          <span className="font-mono text-sm text-ink">
            {ducats === null ? '—' : ducats.toLocaleString()}
          </span>
          <span className="font-mono text-[10px] uppercase tracking-wider text-ink-faint">d.</span>
        </span>
      </div>
    </header>
  )
}
