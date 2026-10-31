import { TileChoice, TileGrid } from '../components/ui'
import { HullCountry } from './HullCountry'
import { useWorld } from './worldStore'

// THE COUNTRY PICKER (0143, owner 2026-10-17: like Uncharted Waters, a company belongs to a country
// and can change it). Since GP1 (0187, docs/GREAT_POWERS.md) it offers the TEN GREAT POWERS only —
// `great` as the server serves it in `snapshot.nations`; the thirteen local rulers are never a
// choice (cmd.found_house / cmd.change_country refuse them, E_MINOR_POWER). Alphabetical,
// as chips — the flag and the name through HullCountry. Two callers: Start your company
// (SignTheBook) and Profile's change of country. It chooses; the server decides (cmd.found_house,
// cmd.change_country) and its refusal is printed by the caller.
export function NationPicker({
  value,
  onChange,
  label,
}: {
  value: string
  onChange: (code: string) => void
  /** Names the set for assistive tech. Not painted. */
  label: string
}) {
  const nationByCode = useWorld((s) => s.nationByCode)
  const nations = Object.values(nationByCode)
    .filter((n) => n.great)
    .sort((a, b) => a.name.localeCompare(b.name))
  return (
    // THE TEN POWERS AS ONE ORDERED GRID (owner, 2026-10-31) — equal cells on fixed column lines,
    // alphabetical, never a ragged wall of pills.
    <TileGrid label={label} columns={3} data-testid="nation-picker">
      {nations.map((n) => (
        <TileChoice key={n.code} on={n.code === value} onClick={() => onChange(n.code)} data-testid={`nation-${n.code}`}>
          <HullCountry nation={n.code} />
        </TileChoice>
      ))}
    </TileGrid>
  )
}
