import type { IconName } from '../../../components/ui'
import type { MoveKind } from '../../../domain/hq'
import type { TKey } from '../../../lib/i18n'
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
export const KIND_ICON: Record<MoveKind, IconName> = { trade: 'scales', request: 'crate', yard: 'mallet', crew: 'captain', invest: 'invest' }
