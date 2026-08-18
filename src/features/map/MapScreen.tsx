import { Notice } from '../../components/ui'
import { TabPlaceholder } from '../../app/TabPlaceholder'

// MAP — READ-ONLY, BY DESIGN AND FOREVER.
//
// The chart shows where fleets are and where they are sailing. It accepts no input that changes
// the world: no click-to-move, no drag-a-route, no context menu, no order composed on a marker.
// Orders are written on the Command tab, in words.
//
// This is not a temporary limitation of the skeleton — it is the game's shape. byeharu's map grew
// commands and the movement rules then had to be re-derived on the map's terms; the map became the
// hardest surface in the app because it was doing two jobs. Here it does one: it tells you where
// things are. Any future pull to "just let them tap the port to sail there" adds a second place
// orders come from, and there is exactly one.

export function MapScreen() {
  return (
    <TabPlaceholder
      eyebrow="Chart"
      title="Map"
      subtitle="Where your fleets are, and where they are sailing."
      icon="chart"
      summary="A chart of the real world: real coasts, real port cities, real coordinates, and your fleets drawn on it."
      note={
        <Notice tone="accent" data-testid="map-is-a-view">
          The map is a view, not a controller. It never takes an order — nothing on this chart can
          be clicked to make a fleet do anything. Orders are given on the Command tab.
        </Notice>
      }
      willHold={[
        'World chart with real coastlines and named port cities',
        'Fleet markers at their current position',
        'Track lines from origin to destination, with the leg remaining',
        'A legend and a scale — read-only chrome, no controls',
      ]}
    />
  )
}
