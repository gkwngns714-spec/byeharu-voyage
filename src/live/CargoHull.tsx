import { CARGO_HULL, NAVY_HULL, hullPath } from '../chart'

/** THE CARGO SHIP'S HULL AS A PICTURE: the chart's own path (`hullPath`), as ShipPanel's portrait draws any hull. 0310. */
export function CargoHull({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="-15 -15 30 30" aria-hidden data-testid="cargo-hull">
      <path d={hullPath(CARGO_HULL, 13)} className="stroke-chart-sea" fill="var(--color-cargo-hull)" strokeWidth={0.7} strokeLinejoin="round" />
    </svg>
  )
}

/** 0331: THE NAVY SHIP'S, the same way. */
export function NavyHull({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="-15 -15 30 30" aria-hidden data-testid="navy-hull">
      <path d={hullPath(NAVY_HULL, 13)} className="stroke-chart-sea" fill="var(--color-navy-hull)" strokeWidth={0.7} strokeLinejoin="round" />
    </svg>
  )
}
