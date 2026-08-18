import { TabPlaceholder } from '../../app/TabPlaceholder'

export function FleetsScreen() {
  return (
    <TabPlaceholder
      eyebrow="Assets"
      title="Fleets"
      subtitle="What you own, and the state it is in."
      icon="ship"
      summary="The roster: every ship, the fleet it sails with, what is in its hold, and how sound it is."
      willHold={[
        'Fleet list with each fleet’s position and current voyage',
        'Ship detail: rig, tonnage, hull condition, crew',
        'Hold manifest per ship, and the fleet-wide total',
        'Crew wages, provisions and water remaining',
      ]}
    />
  )
}
