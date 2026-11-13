import { Hint, TileChoice, TileGrid } from '../components/ui'
import { useT } from '../lib/i18n'
import { HullCountry } from './HullCountry'
import { useWorld } from './worldStore'

// THE COUNTRY PICKER (0143, owner 2026-10-17: like Uncharted Waters, a company belongs to a country
// and can change it). Since GP1 (0187, docs/GREAT_POWERS.md) it offers the great powers only; since W16 (0338)
// that is `joinable` as the server serves it in `snapshot.nations` - the ten, and the pirates only when the owner sets
// pirates_joinable. The thirteen local rulers, and the pirates until then, are never a choice (cmd.found_house /
// cmd.change_country refuse them, E_MINOR_POWER). `great` stays the Codex's word for a power; it is not this list. Alphabetical,
// as chips — the flag and the name through HullCountry. Two callers: Start your company
// (SignTheBook) and Profile's change of country. It chooses; the server decides (cmd.found_house,
// cmd.change_country) and its refusal is printed by the caller.
const NONE: readonly string[] = []

export function NationPicker({
  value,
  onChange,
  label,
  closed = NONE,
}: {
  value: string
  onChange: (code: string) => void
  /** Names the set for assistive tech. Not painted. */
  label: string
  /** Countries not offered here: those whose capital's sea is closed to a new company while the sea conditions bite
   *  (the server's list, world.sea_conditions `far_powers`; cmd.found_house refuses them). The Start sheet passes it;
   *  a company changing country is offered every one. */
  closed?: readonly string[]
}) {
  const t = useT()
  const nationByCode = useWorld((s) => s.nationByCode)
  const nations = Object.values(nationByCode)
    .filter((n) => n.joinable && !closed.includes(n.code))
    .sort((a, b) => a.name.localeCompare(b.name))
  return (
    <>
    {/* THE POWERS A COMPANY MAY SAIL FOR AS ONE ORDERED GRID (owner, 2026-10-31) — equal cells on fixed column lines,
    alphabetical, never a ragged wall of pills.
    A WORDS GRID (owner, 2026-11-12): in three fixed columns at 320 px "카스티야-에스파냐", "The Netherlands" and "Portugal" stood
    out of their tiles and over their neighbours. Two columns on a phone, three from the desk, and a cell is never narrower
    than its flag and name. */}
    <TileGrid label={label} words={2} wordsWide={3} data-testid="nation-picker">
      {nations.map((n) => (
        <TileChoice key={n.code} on={n.code === value} onClick={() => onChange(n.code)} data-testid={`nation-${n.code}`}>
          <HullCountry nation={n.code} />
        </TileChoice>
      ))}
    </TileGrid>
    {/* WHAT THE SKULL COSTS (0380), said before she picks: the pirate power is at war with every country (public.power_relations), so every
        crown port prices her at the war rate, and no pirate home keeps a yard. The server names the power (`pirate`); the words are one line. */}
    {nationByCode[value]?.pirate && (
      <Hint className="mt-2" data-testid="nation-skull">
        {t('found.skull')}
      </Hint>
    )}
    </>
  )
}
