import { useState } from 'react'
import { Button, Card, Notice, PageHeader, Screen } from '../../components/ui'
import { cmdFoundHouse } from '../../lib/rpc'
import type { Refusal } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'

// SIGN THE BOOK — the first thing a captain on a real server ever sees, and until 2026-08-20 it
// did not exist.
//
// ── WHY THERE WAS NOTHING HERE ─────────────────────────────────────────────────────────────────
// Local mode founds its one captain during boot (localDb.ts calls `public.new_house()` as the
// superuser it is), so no screen was ever needed and none was ever missed. On a real project that
// function is revoked from every client role — permanently and correctly, because it takes a uid
// and a client holding it could found a house on somebody else's account. So a signed-in player
// arrived at an empty world with nothing to press. Migration 0011 gave the server side
// (`cmd.found_house(name)`, which takes NO uid and reads auth.uid() itself); this is the door.
//
// ── IT ASKS FOR ONE THING ──────────────────────────────────────────────────────────────────────
// A name. Not a nation, not a starting port, not a ship: DESIGN K.1 opens every captain the same
// way — one Barca called Gaivota, alongside at Lisboa, 8,000 ducats — and the server is what
// decides that, not this form. A screen that offered choices the chain does not honour would be
// lying about the game.
//
// ── AND IT VALIDATES NOTHING ───────────────────────────────────────────────────────────────────
// No length check, no "name taken" check, no trimming rules. `public.players` already carries
// `unique` and `check (length(btrim(company_name)) between 3 and 24)`, and 0011 turns each of those
// into a refusal with a sentence. Re-implementing them here would be a second authority that drifts
// the first time the constraint changes — so the button simply asks, and prints what comes back.

export function SignTheBook() {
  const refresh = useWorld((s) => s.refresh)
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  const sign = async () => {
    setBusy(true)
    setRefusal(null)
    const r = await cmdFoundHouse(name)
    if (r.ok) {
      // The house exists now; the read is what makes it appear. Nothing here writes to the store.
      await refresh()
      return
    }
    setRefusal(r.refusal)
    setBusy(false)
  }

  return (
    <Screen>
      <PageHeader
        eyebrow="The register"
        title="Sign the book"
        subtitle="Every captain begins the same way."
        explain="One Barca — Gaivota — alongside at Lisbon, and 8,000 ducats to trade with. The port, the ship and the purse are the server's to decide (DESIGN K.1); the name is yours."
      />

      <Card>
        <label htmlFor="house-name" className="block text-sm text-ink-muted">
          What will your house trade as?
        </label>
        <input
          id="house-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && name.trim() && !busy) void sign()
          }}
          placeholder="Casa de Aveiro"
          autoComplete="off"
          autoFocus
          className="mt-2 min-h-11 w-full rounded-md border border-edge bg-surface-2 px-3 py-3 font-serif text-lg text-ink outline-none placeholder:text-ink-faint focus:border-accent/60"
        />
        <p className="mt-2 text-xs text-ink-faint">
          Three to twenty-four letters, and no two houses may trade under the same name.
        </p>

        {/* A refusal is DATA (DESIGN F.5): a code, a sentence, and at least one fix. It is printed
            as it arrives — this screen does not translate server errors into its own words. */}
        {refusal && (
          <Notice tone="danger" className="mt-3">
            <span className="font-mono text-[11px] uppercase tracking-wider">{refusal.code}</span>
            <span className="mt-1 block text-sm">{refusal.sentence}</span>
          </Notice>
        )}
        {refusal && refusal.fixes.length > 0 && (
          <ul className="mt-2 space-y-1">
            {refusal.fixes.slice(0, 4).map((fix) => (
              <li key={fix} className="font-mono text-[11px] text-ink-faint">
                {fix}
              </li>
            ))}
          </ul>
        )}

        <div className="mt-4">
          <Button variant="primary" disabled={busy || name.trim().length === 0} onClick={() => void sign()}>
            {busy ? 'Signing…' : 'Sign the book'}
          </Button>
        </div>
      </Card>
    </Screen>
  )
}
