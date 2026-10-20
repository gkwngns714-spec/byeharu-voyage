import { Bar } from './Bar'
import { Figure } from './Figure'
import { Tile } from './Tile'
import { useT } from '../../lib/i18n'

// ONE OF THE COMPANY'S FOUR SKILLS, AS A TILE WITH ITS LEVEL BAR — moved here from
// features/port/PortAcademy.tsx (2026-10-08) so the Academy and a merchant's sheet print one shape
// (docs/NPC_TRADERS.md §8.3, the word is "Skills", docs/WORDS.md). PURE PROPS.
export function SkillTile({
  code,
  name,
  level,
  max,
  onClick,
}: {
  code: string
  name: string
  level: number
  max: number
  onClick?: () => void
}) {
  const t = useT()
  return (
    <Tile
      name={name}
      state={level > 0 ? 'selected' : 'rest'}
      tap={onClick ? 'whole' : 'none'}
      onClick={onClick}
      figure={<Figure value={`${level}`} unit={`/ ${max}`} />}
      bar={<Bar value={level} of={max} tone={level > 0 ? 'accent' : 'neutral'} label={t('ui.skillLevel', { name, level, max })} />}
      data-testid={`skill-${code}`}
    />
  )
}
