import { useEffect, useRef } from 'react'

/** THE LAYERS THAT ANSWER Escape, the one opened last on top (2026-11-11, the Fleets page): a page opened from a page (a ship's Move from her fleet's page, a ship's sheet
 *  over it) is left ONE step at a time, as the back press leaves it. Before this every open page heard the key and all of them closed at once, so the keyboard could not
 *  go back to the fleet it came from. */
const backLayers: { close: () => void }[] = []

/** Escape closes this layer while it is the one opened last. `DetailPage` uses it; a tray that stands over a page (a ship's sheet) takes it the same way. */
export function useBackLayer(onClose: () => void): void {
  const close = useRef(onClose)
  useEffect(() => {
    close.current = onClose
  })
  useEffect(() => {
    const layer = { close: () => close.current() }
    backLayers.push(layer)
    const onKey = (e: KeyboardEvent) => {
      // one key, one layer: a layer leaves the list when React unmounts it, after every listener has heard this key
      if (e.key === 'Escape' && backLayers[backLayers.length - 1] === layer) layer.close()
    }
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
      const i = backLayers.indexOf(layer)
      if (i >= 0) backLayers.splice(i, 1)
    }
  }, [])
}
