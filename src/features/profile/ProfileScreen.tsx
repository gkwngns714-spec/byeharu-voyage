import { useState } from 'react'
import { Button, Card, CardHeader, Screen, StatRow, PageHeader, SectionLabel } from '../../components/ui'
import { useAuthStore } from '../../store/authStore'

// PROFILE — the one tab that is not a placeholder, because the one thing that already works is
// the session. It shows who is signed in and lets them sign out; everything else that belongs to
// an account arrives with the account tables.

export function ProfileScreen() {
  const user = useAuthStore((s) => s.user)
  const signOut = useAuthStore((s) => s.signOut)
  const [busy, setBusy] = useState(false)

  return (
    <Screen>
      <PageHeader eyebrow="Account" title="Profile" subtitle="Who is signed in on this device." />

      <Card>
        <CardHeader title="Session" subtitle="Held by Supabase auth and refreshed automatically." />
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

      <Card>
        <SectionLabel>Will live here</SectionLabel>
        <ul className="space-y-1 text-sm text-ink-muted">
          <li>Captain name and house colours</li>
          <li>Preferences: units, date format, notifications</li>
          <li>Account actions: change password, delete account</li>
        </ul>
      </Card>
    </Screen>
  )
}
