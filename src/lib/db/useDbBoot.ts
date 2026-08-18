// The boot state, as a React subscription. `useSyncExternalStore` rather than a store of our own:
// the boot channel is the authority, and a hook that kept a second copy of it in component state
// would be able to disagree with the thing it is reporting.
//
// A screen showing this must show `failed` as failure — with `error` — and never as a spinner that
// happens to spin forever.

import { useSyncExternalStore } from 'react'
import { bootChannel, type BootChannel, type BootState } from './bootState'

export function useDbBoot(channel: BootChannel = bootChannel): BootState {
  return useSyncExternalStore(channel.subscribe, channel.get, channel.get)
}
