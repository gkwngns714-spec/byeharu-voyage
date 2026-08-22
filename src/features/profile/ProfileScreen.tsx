import { useState } from 'react'
import { Button, Card, CardHeader, Screen, StatRow, PageHeader, SectionLabel } from '../../components/ui'
import { useAuthStore } from '../../store/authStore'
import { useWorld } from '../../live/worldStore'
import { formatInt } from '../../lib/format'

// PROFILE — who is signed in, and which world they are signed in TO.
//
// It used to be the session and then a bullet list of things that would live here one day. The
// session half was real; the list was a placeholder wearing a card. What replaced the list is the
// WORLD half, which is equally real and was already in the store: which backend answered, how big
// the world is, and the knobs the server is running the game by. A player debugging "why did my
// purse reset" or "am I on the live server" had nowhere to look, and this is that place.
//
// WHAT IS STILL NOT HERE IS NOT A LAYOUT PROBLEM. The captain's own name, house colours, nation
// and reputation are not served: `world.snapshot()` carries no player row (README §4). Preferences
// have nowhere to persist to for the same reason. Those are named at the foot of the screen as
// server work, not drawn as empty fields.

export function ProfileScreen() {
  const user = useAuthStore((s) => s.user)
  const world = useWorld()
  const signOut = useAuthStore((s) => s.signOut)
  const [busy, setBusy] = useState(false)

  return (
    <Screen>
      <PageHeader eyebrow="Account" title="Profile" explain="Who is signed in on this device." />

      <Card>
        <CardHeader title="Session" explain="Held by Supabase auth and refreshed automatically." />
        <dl className="space-y-2">
          <StatRow label="Email" value={user?.email ?? '—'} plain />
          <StatRow label="User id" value={user?.id ? `${user.id.slice(0, 8)}…` : '—'} />
          <StatRow
            label="Signed in"
            value={user?.last_sign_in_at ? new Date(user.last_sign_in_at).toISOString().slice(0, 16).replace('T', ' ') : '—'}
          />
        </dl>
        <div className="mt-4">
          <Button
            variant="secondary"
            busy={busy}
            busyLabel="Signing out…"
            onClick={async () => {
              setBusy(true)
              await signOut()
              setBusy(false)
            }}
          >
            Sign out
          </Button>
        </div>
      </Card>

      <Card head={<CardHeader flush title="This world" />}>
        <dl className="space-y-2">
          <StatRow
            label="Backend"
            value={world.mode ?? '—'}
            plain
            hint="`local` is a Postgres compiled to WebAssembly, running inside this tab and stored in this browser. `cloud` is the shared Supabase project every captain plays in. The app picks one at boot and nothing branches on it afterwards."
          />
          <StatRow label="World" value={world.phase} plain />
          <StatRow
            label="Ports"
            value={world.snapshot ? formatInt(world.snapshot.ports.length) : '—'}
            hint="Every coordinate came from Wikidata and is stored with the item it came from — none was typed by hand."
          />
          <StatRow
            label="Sea legs"
            value={world.snapshot ? formatInt(world.snapshot.legs.length) : '—'}
          />
          <StatRow
            label="Goods"
            value={world.snapshot ? formatInt(world.snapshot.goods.length) : '—'}
          />
          <StatRow
            label="Time"
            value={
              world.snapshot
                ? `${formatInt(world.snapshot.config.time_compression)}x`
                : '—'
            }
            hint="How much faster the world runs than the clock. One voyage-day is three real minutes at 480x."
          />
        </dl>
      </Card>

      <Card head={<CardHeader flush title="The house" />}>
        {world.player ? (
          <dl className="space-y-2">
            <StatRow label="Company" value={world.player.company_name} plain />
            <StatRow
              label="Nation"
              value={world.player.nation_name ?? world.player.nation ?? '—'}
              plain
            />
            <StatRow label="Company level" value={formatInt(world.player.company_level)} />
            <StatRow
              label="Founded"
              value={world.player.founded_at.slice(0, 10)}
              hint="When this account signed the book (0011)."
            />
            <StatRow
              label="Lying at"
              value={world.player.lying_at ?? 'every fleet at sea'}
              plain
              hint="Where her first fleet lies. There is no home port in this game — a port is a place, not a base — so this is reported as what it is."
            />
          </dl>
        ) : (
          <p className="text-sm text-ink-muted">
            This account keeps no house yet. The register is where one is opened.
          </p>
        )}
      </Card>

      <Card head={<CardHeader flush title="Not yet served" />}>
        <p className="mb-3 text-xs text-ink-muted">
          These are absent because the server has no row for them — not because the screen has no
          room. Each is a migration. (The house&apos;s name, nation and level arrived with 0014 and
          are above.)
        </p>
        <SectionLabel>Waiting on the chain</SectionLabel>
        <ul className="space-y-1 text-sm text-ink-muted">
          <li>· House colours, and a title ladder that moves `title_level`</li>
          <li>· Preferences — units, date format, notifications — which need somewhere to persist</li>
          <li>· Account actions: change password, delete account</li>
        </ul>
      </Card>
    </Screen>
  )
}
