import { useMemo } from 'react'
import { decodeFogCells, liveFogCells, trailsKey, trailsOf, type ChartFog } from '../chart/fog'
import { buildChartModel, mapFleetsOf, mapPortsOf, type FleetOnChart } from '../chart'
import { worldChart, type ChartFogView } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'

/** Her newest arrival (its instant): her served chart can only have moved when one lands. */
const lastArrivalAt = (s: ReturnType<typeof useWorld.getState>): number =>
  s.events.reduce((m, e) => (e.kind === 'VOYAGE_REPORT' ? Math.max(m, Date.parse(e.at) || 0) : m), 0)

/**
 * THE FOG FOR A CHART (0526; src/chart/fog.ts says what it means). The ONE read of `world.chart()`, cached by name
 * (the map and the Trade map share it) and asked again only when an arrival of hers lands, not on the world's beat.
 * Null while it is dark, signed out, or not yet read: the chart is then drawn whole, as it always was.
 * `fleets` are HER fleets as the chart places them: each is an eye, and the part of a voyage she has already
 * sailed is grey before the server writes it at her arrival.
 */
export function useChartFog(fleets: readonly FleetOnChart[], enabled = true): ChartFog | null {
  const trigger = useWorld(lastArrivalAt)
  const view = useServedRead<ChartFogView>(enabled ? 'chart' : null, () => worldChart(), { name: 'worldChart', trigger, freshMs: 10 * 60_000 }).view
  const lit = view && view.on && view.company ? view : null
  const b64 = lit?.cells ?? null
  const served = useMemo(() => decodeFogCells(b64), [b64])
  const sightNm = lit?.sight_nm ?? 0
  const trails = trailsKey(fleets)
  const cells = useMemo(() => liveFogCells(served, trailsOf(trails), sightNm), [served, trails, sightNm])
  const citiesKey = lit ? lit.cities.join(' ') : ''
  const cities = useMemo(() => new Set(citiesKey === '' ? [] : citiesKey.split(' ')), [citiesKey])
  // one eye a fleet, where the chart draws her now
  const eyesKey = fleets.map((f) => `${f.at.lat.toFixed(3)},${f.at.lon.toFixed(3)}`).join(' ')
  const eyes = useMemo(
    () => (eyesKey === '' ? [] : eyesKey.split(' ').map((p) => ({ lat: Number(p.split(',')[0]), lon: Number(p.split(',')[1]) }))),
    [eyesKey],
  )
  return useMemo(() => (lit ? { sightNm, cells, cities, eyes } : null), [lit, sightNm, cells, cities, eyes])
}

const NO_PORTS: readonly never[] = []

/** The fog for a chart that does not draw all her fleets (the Trade map): every fleet of her company is an eye, placed as the
 *  chart places a fleet (`buildChartModel`), from the world's own read. */
export function useCompanyFog(enabled = true): ChartFog | null {
  const fleets = useWorld((s) => s.fleets)
  const ports = useWorld((s) => s.snapshot?.ports ?? NO_PORTS)
  const placed = useMemo(() => buildChartModel(mapFleetsOf(fleets), mapPortsOf(ports), []).fleets, [fleets, ports])
  return useChartFog(placed, enabled)
}
