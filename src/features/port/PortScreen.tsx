import { TabPlaceholder } from '../../app/TabPlaceholder'

export function PortScreen() {
  return (
    <TabPlaceholder
      eyebrow="Harbour"
      title="Port"
      subtitle="The city you are lying in."
      icon="anchor"
      summary="A real port city: its harbour, its yards, its officials, and whatever the quayside is talking about."
      willHold={[
        'The port you are docked at, with its country and harbour dues',
        'Shipyard: repair, refit, purchase',
        'Provisioning: water, food, crew hire',
        'Harbour news and rumours of prices elsewhere',
      ]}
    />
  )
}
