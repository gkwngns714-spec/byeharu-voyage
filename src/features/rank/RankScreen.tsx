import { TabPlaceholder } from '../../app/TabPlaceholder'

export function RankScreen() {
  return (
    <TabPlaceholder
      eyebrow="Standings"
      title="Rank"
      subtitle="Where you stand among the captains."
      icon="wreath"
      summary="Standings computed by the server from the same ledger everyone is judged by — never from anything the client reports."
      willHold={[
        'Standing by net worth, and by ports first reached',
        'Your position, and the captains immediately above and below you',
        'Season boundaries and when the table was last settled',
      ]}
    />
  )
}
