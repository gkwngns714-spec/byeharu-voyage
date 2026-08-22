import { useState } from 'react'
import {
  Button,
  Card,
  CardHeader,
  Screen,
  StatRow,
  PageHeader,
  SectionLabel,
  fineClass,
} from '../../components/ui'
import { useAuthStore } from '../../store/authStore'
import { portNameOf, useWorld } from '../../live/worldStore'
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
// and reputation are not served: `snapshot()` carries no player row (README §4). Preferences
// have nowhere to persist to for the same reason. Those are named at the foot of the screen as
// things the game does not keep yet — not drawn as empty fields, and not itemised as server work,
// which is my backlog and not the player's reading.
//
// ── THE SESSION CARD HAS TWO SHAPES, BECAUSE THERE ARE TWO KINDS OF SESSION (2026-08-22) ────────
// In local mode this card printed `Email —`, `User id —`, `Signed in —` and an ENABLED "Sign out"
// that did nothing at all: `authStore.signOut()` opens with `if (!supabase) return`, so the click
// had no navigation, no state change, no message and no console line behind it.
//
// Three ways out, and the choice is not mine — docs/UI_DIRECTION.md §4 rule 5 already decided it:
// "Unavailable is shown with its reason — never hidden, never silently disabled." So the control
// STAYS, DISABLED, with the reason printed beside it. Hiding it would leave a player who cannot
// find sign-out unable to tell whether the game has it; a dead enabled button is worse than both,
// because it teaches that a tap can mean nothing.
//
// And three dashes are not an honest reading of "there is no account". Local mode gets the true
// sentence instead: the world lives in this browser and nobody signed in to reach it. The mode is
// read from authStore, not from the world store — authStore answers "may this player see the
// game" and the world store answers "where does the game live" (rpc/init.ts:15-18 keeps them
// apart on purpose), and sign-out is a question about the first one.

export function ProfileScreen() {
  const user = useAuthStore((s) => s.user)
  // FIELDS, NOT THE STORE (worldStore.ts rule 4). This screen prints five facts and used to
  // re-render on every write to any of them plus every unrelated one.
  const mode = useWorld((s) => s.mode)
  const phase = useWorld((s) => s.phase)
  const snapshot = useWorld((s) => s.snapshot)
  const player = useWorld((s) => s.player)
  const portByCode = useWorld((s) => s.portByCode)
  const authMode = useAuthStore((s) => s.mode)
  const signOut = useAuthStore((s) => s.signOut)
  const [busy, setBusy] = useState(false)

  return (
    <Screen>
      {/* "Who is signed in on this device" was true of cloud mode and false of local mode, where
          nobody is signed in at all — and this screen is reached by both. */}
      <PageHeader
        eyebrow="Account"
        title="Profile"
        explain="Who you are, which world you are playing in, and what the game does not keep yet."
      />

      {authMode === 'local' ? (
        <Card>
          <CardHeader
            title="Session"
            explain="Nothing is held anywhere but this browser: no account, no server, no password."
          />
          <p className="text-sm text-ink-muted">
            There is no account on this device. This copy of the game keeps its whole world inside
            this browser and opens straight onto it, so there is nobody to sign in as. Your house,
            your purse and your ledger are in this browser&apos;s storage — clearing it is the only
            thing that ends this session, and it ends the house with it.
          </p>
          <div className="mt-4">
            {/* DISABLED WITH ITS REASON, not hidden (docs/UI_DIRECTION.md §4 rule 5). It was
                enabled and inert, which is the one option that teaches a player their taps may
                mean nothing. The reason sits under the control, not in the paragraph above it,
                so it is read by someone who reached for the button rather than the prose. */}
            <Button variant="secondary" disabled>
              Sign out
            </Button>
            <p className={fineClass('mt-1')}>
              Nothing to sign out of — there is no account behind this world.
            </p>
          </div>
        </Card>
      ) : (
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
      )}

      <Card head={<CardHeader flush title="This world" />}>
        <dl className="space-y-2">
          {/* The backticks were markdown, rendered raw on a player's screen — the same leak as a
              migration number, one layer down. This card is the diagnostic one and the two words
              LOCAL and CLOUD are the answer to "where did my purse go", so they stay; what is
              explained behind the dot is now what they MEAN rather than how they are built. */}
          <StatRow
            label="Where this world is"
            value={mode ?? '—'}
            plain
            hint="Local means the whole game — world, prices, your house — is running inside this browser tab and is stored on this device only. Cloud means the shared world every captain plays in, kept on a server. The game picks one when it starts and never changes it."
          />
          <StatRow label="World" value={phase} plain />
          <StatRow
            label="Ports"
            value={snapshot ? formatInt(snapshot.ports.length) : '—'}
            hint="Every coordinate came from Wikidata and is stored with the item it came from — none was typed by hand."
          />
          <StatRow
            label="Sea legs"
            value={snapshot ? formatInt(snapshot.legs.length) : '—'}
          />
          <StatRow
            label="Goods"
            value={snapshot ? formatInt(snapshot.goods.length) : '—'}
          />
          <StatRow
            label="Time"
            value={
              snapshot
                ? `${formatInt(snapshot.config.time_compression)}x`
                : '—'
            }
            hint="How much faster the world runs than the clock. One voyage-day is three real minutes at 480x."
          />
        </dl>
      </Card>

      <Card head={<CardHeader flush title="The house" />}>
        {player ? (
          <dl className="space-y-2">
            <StatRow label="Company" value={player.company_name} plain />
            <StatRow
              label="Nation"
              value={player.nation_name ?? player.nation ?? '—'}
              plain
            />
            <StatRow label="Company level" value={formatInt(player.company_level)} />
            <StatRow
              label="Founded"
              value={player.founded_at.slice(0, 10)}
              /* "(0011)" named the migration that writes this date. A captain has no use for it. */
              hint="The day this house signed the register."
            />
            <StatRow
              label="Lying at"
              /* IT WAS PRINTING THE CODE — "Lying at LIS" — while every other screen in the game
                 said "Lisbon". `portNameOf` is the one translation (worldStore.ts); this screen
                 does not write an eighth copy of it. The code survives as the fallback, which is
                 the honest answer for a port this snapshot does not carry. */
              value={
                player.lying_at ? portNameOf(portByCode, player.lying_at) : 'every fleet at sea'
              }
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

      {/* THE HONESTY STAYS, THE BACKLOG GOES (2026-08-22). This card was headed "Not yet served"
          over a list headed "Waiting on the chain", and its first line read "House colours, and a
          title ladder that moves `title_level`" — a column name, in markdown backticks, on a
          player's screen. It was written when this whole screen was a placeholder and it was the
          honest thing then; it is a to-do list now.

          A player still needs to know these things are missing, or an empty Profile reads as one
          that failed. What they never needed is that each is a migration, that `title_level` is
          the column a title ladder would move, or that the house's own name and nation arrived
          with 0014. That is provenance, it belongs to this repository, and it stays here:

            · `players.title_level` exists (0014) and nothing writes to it — a ladder of titles is
              its own migration, and house colours have no column at all
            · preferences need a per-player settings table before a screen can offer one
            · change-password / delete-account are Supabase auth calls, and in local mode there is
              no account for them to act on (see the session card above) */}
      <Card head={<CardHeader flush title="Not in the game yet" />}>
        <p className="mb-3 text-xs text-ink-muted">
          These are missing because the game does not keep them yet — not because this screen ran
          out of room for them. They are named here so an empty space is not mistaken for a fault.
        </p>
        <SectionLabel>Still to come</SectionLabel>
        <ul className="space-y-1 text-sm text-ink-muted">
          <li>· A house&apos;s own colours, and a ladder of titles to climb</li>
          <li>· Your own settings — units, dates, what you are told about</li>
          <li>· Changing your password, and closing your account</li>
        </ul>
      </Card>
    </Screen>
  )
}
