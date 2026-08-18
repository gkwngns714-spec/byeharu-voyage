import { TabPlaceholder } from '../../app/TabPlaceholder'

// COMMAND — the only tab that issues orders. Every order composed here becomes ONE Postgres RPC;
// the client never writes a table and never decides an outcome.

export function CommandScreen() {
  return (
    <TabPlaceholder
      eyebrow="Orders"
      title="Command"
      subtitle="Write the order. The sea answers later."
      icon="compass"
      summary="Every order in this game is given here, in words: choose a fleet, choose what it should do, confirm. Nothing else in the app issues an order."
      willHold={[
        'Order composer: fleet, action, destination, cargo, quantity',
        'Standing orders and their next step',
        'Outstanding orders awaiting the server tick',
        'Rejected orders, with the reason the server gave',
      ]}
      note={
        <p className="text-sm text-ink-muted">
          One authority: an order is composed here and executed by an RPC. No other screen may
          acquire a command button.
        </p>
      }
    />
  )
}
