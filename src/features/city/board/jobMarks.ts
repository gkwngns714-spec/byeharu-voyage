import type { IconName, NeedTone } from '../../../components/ui'
import type { MoveKind } from '../../../domain/hq'
import type { TKey } from '../../../lib/i18n'
import type { FleetJobKind, FleetJobRow, ShipRole } from '../../../lib/rpc'
import type { FleetJob } from './useBoard'

// A FLEET'S JOB AS A MARK (docs/design/hq-command-2026-11-23.md): the tone of her ship (blue at sea, green on a route, gold idle — "you may
// act" — red stuck) and its word, which is the mark's accessible name. One table for the bridge and the fleet rows.

export const FLEET_JOB_TONE: Record<FleetJob, string> = {
  trip: 'var(--color-info)',
  route: 'var(--color-success)',
  idle: 'var(--color-accent)',
  busy: 'var(--color-ink-muted)',
  stuck: 'var(--color-danger)',
}

export const FLEET_JOB_WORD: Record<FleetJob, TKey> = { trip: 'hq.atSea', route: 'hq.atSea', idle: 'hq.idle', busy: 'hq.inPort', stuck: 'hq.stuck' }

/** Each kind of move's glyph (the card's disc and its filter chip). */
export const KIND_ICON: Record<MoveKind, IconName> = { trade: 'scales', request: 'crate', contract: 'pact', yard: 'mallet', role: 'helm', land: 'pick', crew: 'captain', invest: 'invest' }

// 0481: A STANDING JOB AS A MARK: its kind's glyph (the best run a trophy, a fixed route the route, the Land haul the pick), in the tone of
// its state (working green, waiting muted, stopped red). One table for the fleet rows, the cards' Repeat and the away card.

export const JOB_ICON: Record<FleetJobKind, IconName> = { best: 'trophy', fixed: 'route', land: 'pick' }

export const JOB_KIND_WORD: Record<FleetJobKind, TKey> = { best: 'hq.jobBest', fixed: 'hq.jobFixed', land: 'hq.jobLand' }

export const JOB_STATE_TONE: Record<FleetJobRow['state'], NeedTone> = { working: 'success', waiting: 'muted', stopped: 'danger' }

export const JOB_STATE_WORD: Record<FleetJobRow['state'], TKey> = { working: 'hq.jobWorking', waiting: 'hq.jobWaiting', stopped: 'hq.jobStopped' }

// 0485: A HULL'S ROLE AS A MARK: a guard the shield, a fast hull the speed glyph, a big cargo the hold. One table for the fleet rows, the
// board's role card, the yard's next role and the goal card.

export const ROLE_ICON: Record<ShipRole, IconName> = { guard: 'shield', fast: 'speed', hold: 'hold' }

export const ROLE_WORD: Record<ShipRole, TKey> = { guard: 'hq.roleGuard', fast: 'hq.roleFast', hold: 'hq.roleHold' }

export const ROLES: readonly ShipRole[] = ['guard', 'fast', 'hold']
