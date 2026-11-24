import { useState } from 'react'
import { useLocation } from 'react-router-dom'
import { Button, FLOAT_CARD_CLASS, Icon, Ring, Skyline, glassBesideRailClass, skylineOf } from '../components/ui'
import { hullTierOf } from '../chart'
import { ShipArtIcon } from '../live/battle/ShipArt'
import { useSecondShipGoal } from '../live/useSecondShipGoal'
import { gameToday } from '../lib/format'
import { useT } from '../lib/i18n'
import { portNameOf, useWorld } from '../live/worldStore'
import { HOME_TAB } from './navTabs'
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
//
// FEWER WORDS, A PICTURE (2026-11-23, the visual overhaul's slice 10). The card was a title and three sentences. Now it opens on a
// picture of where she is: her city's skyline (`Skyline`, the regional picture `skylineOf` picks from the served culture, the Map
// tray's own) with her ship on its water (the battle stage's and the Codex key's drawing, `ShipArtIcon`, at her flagship's served
// tier, seen from above as on the chart). Under it one short line (her house, the city, the year), the goal as a RING around a ship (how far along the second ship is:
// her purse against the Order's price while the yard takes orders, else the materials stored; `useSecondShipGoal`, the very reading
// the goal card prints, so the two never disagree), and the one instruction the card exists to give, the first press. The word
// "Welcome" went: the picture says it.

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
  const fleet = useWorld((s) => s.fleets.find((f) => f.port) ?? null)
  const portByCode = useWorld((s) => s.portByCode)
  const goal = useSecondShipGoal(nowMs)

  if (closed || !ready || !fresh || pathname !== HOME_TAB) return null
  const year = gameToday(nowMs).year
  const at = fleet?.port ?? null
  const flagship = fleet?.ships.find((s) => s.is_flagship) ?? fleet?.ships[0]
  const goalWords = goal?.words ?? t('feed.welcomeGoal')
  return (
    <div className={`pointer-events-none ${glassBesideRailClass()} bottom-24 z-60 flex justify-center px-4 lg:bottom-10`} data-testid="welcome-card-wrap">
      <div role="dialog" aria-labelledby="welcome-who" data-testid="welcome-card" className={`${FLOAT_CARD_CLASS} overflow-hidden p-0!`}>
        {/* the picture: her city at dusk, her ship on its water (decoration: the line under it says where) */}
        <div className="relative" data-testid="welcome-picture">
          <Skyline kind={skylineOf(at ? portByCode[at]?.culture : null)} height={72} />
          <span className="absolute bottom-0 left-4" aria-hidden>
            <ShipArtIcon family="yours" tier={hullTierOf(flagship?.class_code ?? null) ?? 1} width={64} fit />
          </span>
        </div>
        <div className="p-4 pt-3">
          <p id="welcome-who" className="break-words text-t-body font-semibold" data-testid="welcome-who">
            {at ? t('feed.welcomeWho', { city: portNameOf(portByCode, at), year }) : t('feed.welcomeWhoAt', { year })}
          </p>
          {/* the goal as a ring you can feel fill, its line beside it */}
          <div className="mt-2 flex items-center gap-3">
            <Ring pct={goal?.pct ?? 0} size={40} label={goalWords} data-testid="welcome-ring">
              <Icon name="ship" size={20} className="text-accent" />
            </Ring>
            <p className="min-w-0 break-words text-t-body text-accent" data-testid="welcome-goal" data-pct={goal ? Math.round(goal.pct) : undefined}>
              {goalWords}
            </p>
          </div>
          <p className="mt-2 break-words text-t-label text-ink-dim" data-testid="welcome-first">
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
    </div>
  )
}
