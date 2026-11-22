import { useState } from 'react'
import { useLocation } from 'react-router-dom'
import { Button, FLOAT_CARD_CLASS, glassBesideRailClass } from '../components/ui'
import { gameToday } from '../lib/format'
import { useT } from '../lib/i18n'
import { portNameOf, useWorld } from '../live/worldStore'
import { useShellState } from './shellState'

// THE FIRST-RUN WELCOME (2026-11-22, P0 of docs/design/playable-2026-11-22.md: "No welcome, no goal"). A new player met about
// 20 s of loading and then the Trade desk with 40,000 coins and nothing saying who she is or what to do. One short card says it,
// once: who you are (a trading house in the city her fleet lies in, in the world's year), the goal (the second ship, the goal
// card's own line), and the first press (a good's green line, then Buy & sell, which buys, sails and sells; 2026-11-22 second play-test: "press Buy" bought here and stopped, a dead end).
//
// WHO SEES IT, decided by default: a company that has NEVER TRADED, read from the served `fame.turnover` (the ledger's turnover
// on completed buys and sells; 0 until her first trade), on the Trade tab, where the first press is. Her first trade ends it.
// CLOSED ONCE, KEPT: Start writes a mark in this browser (localStorage, wrapped: blocked storage only means the card may come back
// on the next load). The year is the top bar's own clock (`gameToday`), the city the one her fleet lies at; nothing is invented.
//
// An overlay at the glass's foot, as the arrival card (which a company that never traded has not had yet): fixed, never in the
// flow, nothing under it moves, and nothing scrolls sideways. The browser specs start with the mark set (playwright.config.ts);
// tests/welcome.card.spec.ts clears it.

/** The mark, one per browser: the card says the same thing to every company. */
export const WELCOME_KEY = 'bv:welcome-seen'

function seen(): boolean {
  try {
    return localStorage.getItem(WELCOME_KEY) === '1'
  } catch {
    return false
  }
}

function keep() {
  try {
    localStorage.setItem(WELCOME_KEY, '1')
  } catch {
    // a blocked or full storage: the card simply may show again on the next load
  }
}

export function WelcomeCard() {
  const t = useT()
  const { pathname } = useLocation()
  const { nowMs } = useShellState()
  const [closed, setClosed] = useState(seen)
  const ready = useWorld((s) => s.phase === 'ready')
  const fresh = useWorld((s) => s.player?.fame?.turnover === 0)
  const at = useWorld((s) => s.fleets.find((f) => f.port)?.port ?? null)
  const portByCode = useWorld((s) => s.portByCode)

  if (closed || !ready || !fresh || pathname !== '/command') return null
  const year = gameToday(nowMs).year
  return (
    <div className={`pointer-events-none ${glassBesideRailClass()} bottom-24 z-60 flex justify-center px-4 lg:bottom-10`} data-testid="welcome-card-wrap">
      <div role="dialog" aria-labelledby="welcome-title" data-testid="welcome-card" className={FLOAT_CARD_CLASS}>
        <p id="welcome-title" className="text-t-label font-semibold">
          {t('feed.welcomeTitle')}
        </p>
        <p className="mt-1 break-words text-t-body" data-testid="welcome-who">
          {at ? t('feed.welcomeWho', { city: portNameOf(portByCode, at), year }) : t('feed.welcomeWhoAt', { year })}
        </p>
        <p className="mt-1 break-words text-t-body text-accent" data-testid="welcome-goal">
          {t('feed.welcomeGoal')}
        </p>
        <p className="mt-1 break-words text-t-body" data-testid="welcome-first">
          {t('feed.welcomeFirst')}
        </p>
        <div className="mt-3 flex gap-2">
          <Button
            variant="primary"
            size="sm"
            className="flex-1"
            data-testid="welcome-start"
            onClick={() => {
              keep()
              setClosed(true)
            }}
          >
            {t('feed.welcomeStart')}
          </Button>
        </div>
      </div>
    </div>
  )
}
