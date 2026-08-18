import { TabPlaceholder } from '../../app/TabPlaceholder'

export function MarketScreen() {
  return (
    <TabPlaceholder
      eyebrow="Trade"
      title="Market"
      subtitle="What things fetch, here and elsewhere."
      icon="scales"
      summary="The price table for this port, beside what you last saw quoted in the ports you have visited — the spread is the whole game."
      willHold={[
        'Goods table: bid, ask, stock and the spread, in this port',
        'Remembered quotes from other ports, with how stale each one is',
        'Profit per ton on the routes you can actually sail',
        'Buy and sell composed here, executed as an order on Command',
      ]}
    />
  )
}
