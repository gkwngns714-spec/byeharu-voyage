import { worldLevels, type LevelsView } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'

/** The ONE levels read (`world.levels()`, 0325), cached by name: the You page's levels card and its ships' rows share it, as
 *  the Trade tab's goal card and the yard do. */
export function useLevels() {
  return useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
}
