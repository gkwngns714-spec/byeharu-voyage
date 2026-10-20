import { useState } from 'react'
import { Bar, Button, Figure, Note, Row, Segmented, Sheet, SheetSection } from '../../components/ui'
import { cmdChangeCountry, type Refusal } from '../../lib/rpc'
import { HullCountry } from '../../live/HullCountry'
import { NationPicker } from '../../live/NationPicker'
import { useAuthStore } from '../../store/authStore'
import { useWorld } from '../../live/worldStore'
import { formatInt } from '../../lib/format'
import type { LevelTrack } from '../../lib/rpc'
import { useShellState } from '../../app/shellState'
import { APPEARANCES, readAppearance, writeAppearance, type Appearance } from './appearance'

// PROFILE (in Cabin) — docs/UI_DIRECTION.md §6:
//
//   Casa de Aveiro · Portugal · since 9 Sep
//   Trading     ▔▔▔▔▔▔▔▔▔▔ 1
//   Exploration ▔▔▔▔▔▔▔▔▔▔ 1               ← levels live here, as Bars
//   Appearance  [Dark ◆][Light][Auto]
//   [Sign out]
//
// ── WHAT §2 ITEM 18 COUNTED, AND WHERE EACH THING WENT ─────────────────────────────────────────
//   `This world` (mode, phase, port count, good count, `9,600x`)   → deleted. Developer telemetry
//                on a player screen; the mode and the compression are on the console at boot
//                (supabase.ts), which is where a diagnostic belongs.
//   `Not in the game yet` (three bullets of unbuilt features)       → deleted. A roadmap is this
//                repository's, not the player's — the bullets are in git history and
//                docs/OWNER_REQUESTS.md, where a to-do list lives.
//   `Session` card (a sentence, a ⓘ, `Sign out`, `No account…`)     → one row at the foot: the
//                account it signs out of, or the reason it cannot.
//   `The house` card (company, nation, level, founded, lying at)     → the one house line. "Lying
//                at" is where her fleet is, and FLEETS says so; `company_level` is read by no
//                rule and printed nowhere now.
//   Rank's `Levels` card (the three tracks, 0069)                    → HERE, as Bars — the hand-off
//                from the RANK rebuild (PR #44), which cut them because §6 sends them to this
//                screen. A track that admits it is empty is not printed as a track: see `Track`.
//
// ── SIGN-OUT KEEPS ITS REASON ──────────────────────────────────────────────────────────────────
// In local mode `authStore.signOut()` opens with `if (!supabase) return`, so the button used to be
// enabled and inert — the one option that teaches a player their taps may mean nothing. It stays
// DISABLED with the reason beside it, and the reason is the one thing a player must not learn by
// losing a save: this house lives in this browser and clearing its storage ends it.

export function ProfileScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const player = useWorld((s) => s.player)
  const user = useAuthStore((s) => s.user)
  const authMode = useAuthStore((s) => s.mode)
  const signOut = useAuthStore((s) => s.signOut)
  const { nowMs } = useShellState()
  const [busy, setBusy] = useState(false)
  const [appearance, setAppearance] = useState<Appearance>(readAppearance)

  const choose = (pref: Appearance) => {
    writeAppearance(pref)
    setAppearance(pref)
  }

  return (
    <Sheet title="Profile" data-testid="profile">
      <SheetSection surface>
        {player ? (
          <Row
            data-testid="house-line"
            hairline={false}
            label={
              <span className="text-t-body text-ink">
                {[player.company_name, player.nation_name ?? player.nation, `since ${founded(player.founded_at, nowMs)}`]
                  .filter(Boolean)
                  .join(' · ')}
              </span>
            }
          />
        ) : (
          <Row
            label="No company yet. Start one to play."
            tone="muted"
            hairline={false}
          />
        )}
      </SheetSection>

      {player && player.nation && (
        <CountrySection nation={player.nation} changeAt={player.nation_change_at} nowMs={nowMs} />
      )}

      {player && (
        <SheetSection heading="Levels" surface data-testid="levels">
          <Track name="Trading" track={player.levels.trading} />
          <Track name="Exploration" track={player.levels.exploration} />
          {/* COMBAT READS NOTHING AND IS NOT DRAWN AS A TRACK. 0069 serves it with `playable:
              false` on purpose — there is no fighting at sea in this game yet (0035) — and a bar
              at level 1 of an unbuilt track would make it look built. The server's flag decides:
              the day it flips, this row becomes the third bar with no edit here. Until then the
              row says what it waits on, once, in the player's words. */}
          {player.levels.combat.playable ? (
            <Track name="Combat" track={player.levels.combat} last />
          ) : (
            <Row
              data-testid="combat-waits"
              label="Combat"
              tone="muted"
              hairline={false}
              value={<span className="text-t-caption text-ink-faint">no fighting at sea yet</span>}
            />
          )}
        </SheetSection>
      )}

      <SheetSection heading="Appearance">
        <Segmented
          segments={APPEARANCES}
          value={appearance}
          onChange={choose}
          label="Appearance"
          className="w-fit"
        />
      </SheetSection>

      <SheetSection surface>
        {authMode === 'local' ? (
          <Row
            tone="muted"
            hairline={false}
            label="Not signed in — this game lives in this browser, and clearing its storage ends it."
            value={
              <Button variant="secondary" disabled data-testid="sign-out">
                Sign out
              </Button>
            }
          />
        ) : (
          <Row
            hairline={false}
            label={<span className="text-ink-muted">{user?.email ?? 'Signed in'}</span>}
            value={
              <Button
                variant="secondary"
                busy={busy}
                busyLabel="Signing out…"
                data-testid="sign-out"
                onClick={async () => {
                  setBusy(true)
                  await signOut()
                  setBusy(false)
                }}
              >
                Sign out
              </Button>
            }
          />
        )}
      </SheetSection>
    </Sheet>
  )
}

/** YOUR COMPANY'S COUNTRY (0143, owner 2026-10-17: like Uncharted Waters, a company belongs to a
 *  country and can change it). The flag it sails under, and a change through `cmd.change_country`
 *  — which decides (once every few days, `nation_change_at`) and whose refusal is printed as it
 *  arrives. After a change the house is read again; nothing here writes the store. */
function CountrySection({ nation, changeAt, nowMs }: { nation: string; changeAt: string | null; nowMs: number }) {
  const refresh = useWorld((s) => s.refresh)
  const nationByCode = useWorld((s) => s.nationByCode)
  const [open, setOpen] = useState(false)
  const [pick, setPick] = useState(nation)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const waiting = changeAt !== null && Date.parse(changeAt) > nowMs
  const change = async () => {
    setBusy(true)
    setRefusal(null)
    const r = await cmdChangeCountry(pick)
    if (r.ok) {
      await refresh()
      setOpen(false)
    } else setRefusal(r.refusal)
    setBusy(false)
  }
  return (
    <SheetSection heading="Country" surface data-testid="country">
      <Row
        hairline={open}
        label={<HullCountry nation={nation} />}
        value={
          waiting ? (
            <span className="text-t-caption text-ink-faint" data-testid="country-next">
              {`next change ${new Date(changeAt).toLocaleDateString('en', { month: 'short', day: 'numeric' })}`}
            </span>
          ) : (
            <Button variant="secondary" data-testid="country-change" onClick={() => setOpen((o) => !o)}>
              {open ? 'Keep' : 'Change'}
            </Button>
          )
        }
      />
      {open && !waiting && (
        <div className="mt-3">
          <NationPicker value={pick} onChange={setPick} label="Country" />
          <p className="mt-2 text-t-caption text-ink-muted" data-testid="country-cost">
            The influence your company has given stays with the country it leaves.
          </p>
          {refusal && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-3">
              {refusal.sentence}
            </Note>
          )}
          <div className="mt-3">
            <Button
              variant="primary"
              busy={busy}
              busyLabel="Changing…"
              disabled={pick === nation}
              data-testid="country-confirm"
              onClick={() => void change()}
            >
              {`Sail for ${nationByCode[pick]?.name ?? pick}`}
            </Button>
          </div>
        </div>
      )}
    </SheetSection>
  )
}

/** The cap of the ONE level curve, `public.level_from_points` (0069:111): floored at 1, capped at
 *  20. Mirrored here for DISPLAY ONLY, the way `TIME_COMPRESSION` mirrors a served knob in
 *  src/lib/format/time.ts — the server does not serve the cap, and a bar needs an end. When
 *  `world.snapshot().config` carries it, this constant goes and the bar reads the served value. */
const LEVEL_CAP = 20

/** One level track as §6 draws it: the name, the bar of the ladder, the level as the figure. A
 *  countable Bar (`of`) rather than a percentage: a level is a rung, not a proportion. */
function Track({ name, track, last = false }: { name: string; track: LevelTrack; last?: boolean }) {
  return (
    <Row
      data-testid="level-track"
      label={name}
      value={<Figure value={formatInt(track.level)} />}
      hairline={!last}
    >
      <Bar value={track.level} of={LEVEL_CAP} label={`${name} level`} className="mt-2" />
    </Row>
  )
}

/** "Sep 9", and the year only when it is not this one — the register date, in the player's
 *  calendar rather than the game's. `nowMs` is the shell's clock (shellState), never Date.now(). */
function founded(iso: string, nowMs: number): string {
  const d = new Date(iso)
  if (!Number.isFinite(d.getTime())) return iso.slice(0, 10)
  const sameYear = d.getFullYear() === new Date(nowMs).getFullYear()
  return d.toLocaleDateString('en', { month: 'short', day: 'numeric', ...(sameYear ? {} : { year: 'numeric' }) })
}
