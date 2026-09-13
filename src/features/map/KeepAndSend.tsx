import { Bar, Button, Chip, Figure, Icon, Row } from '../../components/ui'
import { formatFixed, formatVoyageDays } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import type { SendFlow } from './useSendFleet'

// KEEP — how many days of stores she sails under, drawn as a figure, a bar and two presses.
//
// The owner, row 45: *"it will show how i can set my cargo/provision ratio"*, and row 46's law:
// `▁▁▁▂ 2.9 / 33 days`, never a paragraph. The figure is the target the standing order keeps her
// at; the bar under it is what she carries NOW against that target (both served: `endurance_days`,
// 0016, and the days this tray holds); `−` and `+` move the target and nothing else.
//
// THE `KEEP & SEND` LABEL AND ITS ⓘ ARE GONE (§2 item 20). The control's name is the figure's
// name, and the sentence that explained why a chip also sent her is moot: a chip SETS the days now,
// and the one press that sends is the tray's pinned action, named for what it does.
//
// NOT A `Stepper`, deliberately. A Stepper's track spans WHAT IS THERE — a stock, the berths, the
// tuns — and its ceiling is a served figure. Nothing is "there" for a target depth: the old control
// carried no ceiling on purpose, because what a hold can carry is `cmd.do_provision`'s to judge and
// a max typed here would be that rule restated. So the bar is the have-over-keep ratio and the
// presses are the two icon buttons, which is exactly the sketch in §6.
//
// THE `None` CHIP IS CUT. It sailed her under no standing order; with the days as the one control
// there is nothing for it to set, and §6 cuts it. A fleet under no order is cleared on FLEETS.
export function KeepAndSend({ fleet: f, flow }: { fleet: FleetView; flow: SendFlow }) {
  const keep = flow.daysOf(f)
  const have = f.endurance_days
  const presets = flow.presets

  if (presets === null) {
    return <Row tone="muted" hairline={false} label="Reading her standing orders…" data-testid="map-send-keep" />
  }

  return (
    <div className="pb-2" data-testid="map-send-keep">
      {presets.length > 0 && (
        <div className="flex flex-wrap gap-2 py-2">
          {presets.map((p) => (
            <Chip
              key={p.id}
              on={p.days === keep}
              onClick={() => flow.setDays(f, p.days)}
              data-testid="map-send-keep-preset"
            >
              {`${p.name} · ${formatVoyageDays(p.days, 0)}`}
            </Chip>
          ))}
        </div>
      )}
      <div data-testid="map-send-ratio">
        <Row
          hairline={false}
          label={
            <span className="flex items-baseline gap-2">
              Keep
              <Figure value={<span data-testid="map-send-ratio-figures">{keep}</span>} unit="days" size="figure" />
            </span>
          }
          value={
            <span className="flex gap-2">
              <Button
                variant="secondary"
                size="icon"
                aria-label={`fewer days of supplies for ${f.name}`}
                onClick={() => flow.nudge(f, -1)}
                data-testid="map-send-ratio-less"
              >
                <Icon name="minus" size={20} />
              </Button>
              <Button
                variant="secondary"
                size="icon"
                aria-label={`more days of supplies for ${f.name}`}
                onClick={() => flow.nudge(f, 1)}
                data-testid="map-send-ratio-more"
              >
                <Icon name="plus" size={20} />
              </Button>
            </span>
          }
        >
          <Bar
            pct={Math.min(1, have / keep) * 100}
            tone={have >= keep ? 'success' : 'accent'}
            label={`supplies, ${formatFixed(have, 1)} of ${keep} days`}
            className="mt-1"
            figure={<span className="text-t-caption text-ink-faint">{`${formatFixed(have, 1)} now`}</span>}
          />
        </Row>
      </div>
    </div>
  )
}
