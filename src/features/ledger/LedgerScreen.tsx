import { TabPlaceholder } from '../../app/TabPlaceholder'

export function LedgerScreen() {
  return (
    <TabPlaceholder
      eyebrow="Record"
      title="Ledger"
      subtitle="Everything that happened, in the order it happened."
      icon="ledger"
      summary="The running account of the voyage: what was bought, what was sold, what it cost to get there, and what is left."
      willHold={[
        'Cash, debts and net worth',
        'Voyage log: departures, arrivals, weather, incidents',
        'Trade entries with profit and loss per transaction',
        'Running costs: wages, dues, provisions, repairs',
      ]}
    />
  )
}
