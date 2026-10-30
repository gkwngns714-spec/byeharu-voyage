// THE TAP-AWAY PLANE — the invisible press target an inline tray stands on (2026-10-30).
//
// A group's panel and the City page's rail both reveal a `Tray mode="inline"` above the bar, and both
// need the same second gesture: press anywhere else and it shuts. That is one recipe, not two — the
// NavBar wrote it first, the City page copied it, and tests/duplication.spec.ts caught the copy at
// 100 % overlap. It lives here now, and both callers ask for it.
//
// It sits BELOW the tray and below the bar (z-10 against the tray's z-20), so both stay pressable: a
// backdrop that swallowed the bar's own taps would be the "a group reveals, it never replaces the
// bar" rule broken by another route. `tabIndex={-1}` keeps it out of the keyboard order — Escape
// (each owner's own listener) is the keyboard's way out.
export function TapAway({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      tabIndex={-1}
      className="absolute inset-x-0 bottom-full z-10 h-screen cursor-default"
      data-testid="tap-away"
    />
  )
}
