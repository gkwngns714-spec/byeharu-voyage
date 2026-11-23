import { Chip, Icon, Note } from '../../../components/ui'
import { useT } from '../../../lib/i18n'
import type { ShipRole, ShipRolesView } from '../../../lib/rpc'
import { setShipRole, useRoleEdits } from '../../../live/useShipRoles'
import { ROLE_ICON, ROLE_WORD, ROLES } from './jobMarks'

// 0485 (docs/design/roadmap-2026-11-23.md slice 17): A HULL'S ROLE, ON HER FLEET'S ROW. Each hull of the fleet: the three roles as chips
// (a shield, the speed glyph, the hold); the one on is her role (press it again: no role). One press sets it. The best role for her new
// hull (the server's pick) wears a star. A hull at sea, or one with no slot free, shows her chips dimmed: the press is the server's to
// refuse, and its refusal stands under the row in its own words. Nothing shows while she has no slot and no hull with a role.

type Lit = Extract<ShipRolesView, { company: true }>

export function RoleControl({ fleet, roles }: { fleet: string; roles: Lit }) {
  const t = useT()
  const pending = useRoleEdits((s) => s.pending)
  const refused = useRoleEdits((s) => s.refused)
  const hulls = roles.hulls.filter((h) => h.fleet === fleet)
  if (hulls.length === 0 || (roles.slots === 0 && roles.used === 0)) return null
  const free = roles.used < roles.slots
  const press = (ship: string, on: ShipRole | null, r: ShipRole) => {
    if (pending !== null) return
    void setShipRole(ship, on === r ? null : r)
  }
  return (
    <div className="flex flex-col gap-1" data-testid="hq-role-control" data-fleet={fleet}>
      {hulls.map((h) => {
        const open = h.can && (h.role !== null || free)
        const refusal = refused[h.ship] ?? null
        return (
          <div key={h.ship} className="flex flex-col gap-1" data-testid="hq-role-hull" data-ship={h.ship} data-role={h.role ?? ''}>
            <div className="flex flex-wrap items-center gap-2" role="group" aria-label={`${t('hq.role')} · ${h.name}`}>
              {hulls.length > 1 && <span className="min-w-0 break-words text-t-caption text-ink-muted">{h.name}</span>}
              {ROLES.map((r) => {
                const best = roles.pick.ship === h.ship && roles.pick.role === r && h.role === null
                return (
                  <Chip
                    key={r}
                    on={h.role === r}
                    onClick={() => press(h.ship, h.role, r)}
                    className={open ? '' : 'opacity-60'}
                    data-testid={`hq-role-set-${r}`}
                    data-best={best || undefined}
                  >
                    <Icon name={ROLE_ICON[r]} size={16} aria-hidden />
                    {t(ROLE_WORD[r])}
                    {best && <Icon name="trophy" size={12} className="text-accent" aria-label={t('hq.roleBest')} />}
                  </Chip>
                )
              })}
            </div>
            {refusal && (
              <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="hq-role-refusal">
                {refusal.sentence}
              </Note>
            )}
          </div>
        )
      })}
    </div>
  )
}
