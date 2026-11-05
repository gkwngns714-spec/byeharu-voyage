import { cityKind, type CityKind } from '../domain/port'
import { useWorld } from './worldStore'

/** What a harbour is, by its port CODE: the one reading (`cityKind`) over the world's ports and nations. Null for a code the
 *  world does not hold. Subscribes to the two lookups only, never the whole store. */
export function useCityKinds(): (code: string) => CityKind | null {
  const portByCode = useWorld((s) => s.portByCode)
  const nationByCode = useWorld((s) => s.nationByCode)
  return (code) => {
    const port = portByCode[code]
    return port ? cityKind(port, nationByCode) : null
  }
}
