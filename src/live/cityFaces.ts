// THE FACES OF ONE CITY — which building a face is, and the ONE player word for it (moved 2026-10-18 from
// features/port/portView.ts, docs/COMMAND_DESK.md D5): the COMMAND desk's City face composes this one
// table (PORT's face strip did too, until PORT was deleted in D8), so a building is named once and offered by one rule.

import type { BuildingKind } from '../lib/rpc'
import { t } from '../lib/i18n'

/**
 * THE FACES OF ONE PLACE, EACH DESCRIBED ONCE. Not routes: a port is one screen, and these are its
 * sides. One table drives the strip and this store's own "is that a real face?" guard, so a
 * seventh face is one entry and cannot be half-added.
 *
 * ── TWO FIELDS DIED HERE (docs/UI_DIRECTION.md §7 step 4) ──────────────────────────────────────
 * `title` and `explain` were the panel heading and the ⓘ paragraph of the Card this screen used to
 * be. §6 deletes the card, the heading and the dot: the strip already names the face, and the
 * explain lines were seven paragraphs that answered a question nobody had pressed. A field nothing
 * renders is data the next reader has to disprove, so they go with the thing that printed them
 * (docs/NO_SPAGHETTI.md §5).
 *
 * `label` is what the tab says, and it is now ONE WORD — §6's strip is `[Trade][Town][Storage]
 * [Craft][Inn][Build][Repair]` on a single scrolling row, where the old labels wrapped to two rows
 * at 390px. The ORDER of this array is the order of the strip.
 *
 * ── THE LABEL IS THE BUILDING'S ONE PLAYER WORD (2026-09-13, owner rows 86 and 87) ─────────────
 * *"there is warehourse and there is store. unify."* and *"wtf is shipyard and hull (worst ship)?
 * use easy words."* The server names a building kind once (0067: `Warehouse`, `Shipyard`) and the
 * face strip named it a second time (`Store`, `Shipyard`) — two words for one building, and the
 * owner read both. This table is now the ONE client word map: the Town face's building rows print
 * `label` for a kind that has a face here, so the row a player presses says the same word as the
 * tab it opens. The served `building_kinds.name` is what a building is called on the wire, and it
 * is read only for a kind this table does not name (none today).
 */
export const PORT_FACES = [
  {
    id: 'market',
    // 0067: which BUILDING this face is. `null` means the face is not a building and every
    // harbour turns to it. A face that names a building is offered only where that building
    // STANDS — one rule, read from the rows, replacing PortScreen's hand-written academy check.
    building: 'market',
    get label() {
      return t('town.f_market')
    },
  },
  { id: 'city', building: null, get label() { return t('town.f_city') } },
  // The id stays `warehouse` (it is the served building kind and a persisted byte); the player's
  // word is Storage — owner row 87.
  { id: 'warehouse', building: 'warehouse', get label() { return t('town.f_warehouse') } },
  { id: 'workstation', building: 'workstation', get label() { return t('town.f_workstation') } },
  { id: 'inn', building: 'inn', get label() { return t('town.f_inn') } },
  { id: 'building_yard', building: 'building_yard', get label() { return t('town.f_building_yard') } },
  // 2026-09-09: REPAIR's doorway, moved off COMMAND's grid to the building whose act it is. The
  // label is the ACT, not the building's period name — owner row 86: *"wtf is shipyard"*. The id
  // stays `shipyard` (the served kind); one word, and not the Build face's word.
  { id: 'shipyard', building: 'shipyard', get label() { return t('town.f_shipyard') } },
  // 0131: the academy's face is the SKILLS screen (docs/SHIPS_AND_SKILLS.md §8 S9) — groups of
  // skills and the training queue; the label is what it shows, as Repair and Build are acts.
  { id: 'academy', building: 'academy', get label() { return t('town.f_academy') } },
] as const satisfies readonly {
  id: string
  /** 0067 — the building this face IS, or null for a face that is not one. */
  building: BuildingKind | null
  label: string
}[]

export type PortFace = (typeof PORT_FACES)[number]['id']
