import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { deriveWorld, PIRATE_POWER } from '../scripts/lib/world-derive.mjs'
import { cityKind } from '../src/domain/port/cityKind'
import { ISLAND_PORTS } from '../src/domain/port/islandPorts'

// THE CITY-KIND LAW (owner order 2026-11-06): every harbour says what it is, from one function. Node only.
const ports = (JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'ports.json'), 'utf8')) as { ports: { id: string; name: string }[] }).ports
// W16 (0338): the pirates found nothing. Their capital is one of their four homes, a city no country founded; the snapshot serves a harbour's HOLDER,
// so the pirate homes are served as the pirates' own here (every other nation's capital stands in the country that founded it).
const pirateHomes = new Set(
  (JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'home-ports.json'), 'utf8')) as { homes: Record<string, string[]> }).homes[PIRATE_POWER],
)
// deriveWorld's declared type names only the ports; the build also derives the nations and each port's nation_code.
interface DPort { id: string; code: string; size_tier: number; nation_code: string | null }
interface DNation { code: string; capital_port_code: string }
const world = deriveWorld() as unknown as { ports: DPort[]; nations: DNation[] }
const nationByCode = Object.fromEntries(world.nations.map((n) => [n.code, { capital: n.capital_port_code }]))
const served = (id: string) => {
  const slug = ports.find((p) => p.id === id)!
  const d = world.ports.find((p) => p.id === id)!
  return { code: d.code as string, name: slug.name, size_tier: d.size_tier as number, nation: (pirateHomes.has(d.code) ? PIRATE_POWER : d.nation_code) as string | null }
}

test('Angra is an island', () => {
  expect(cityKind(served('angra-do-heroismo'), nationByCode).island).toBe(true)
  expect(cityKind(served('angra-do-heroismo'), nationByCode).label).toBe('port.kindIslandTown')
})

test('each nation capital is a Capital, and only they', () => {
  const caps = world.nations.map((n) => n.capital_port_code)
  expect(caps.length).toBeGreaterThan(0)
  const all = world.ports.map((d) => cityKind(served(d.id), nationByCode))
  for (const n of world.nations) {
    const d = world.ports.find((p) => p.code === n.capital_port_code)!
    expect(d, `${n.code}'s capital ${n.capital_port_code} resolves to a port`).toBeTruthy()
    if (n.code === PIRATE_POWER) expect(pirateHomes.has(n.capital_port_code), `${n.code}'s capital is one of its homes`).toBe(true)
    else expect(d.nation_code, `${n.code}'s capital stands in ${n.code}`).toBe(n.code)
    expect(cityKind(served(d.id), nationByCode).capital).toBe(true)
  }
  expect(all.filter((k) => k.capital).length).toBe(new Set(caps).size)
})

test('the island list holds only real port ids, with the name the world serves', () => {
  const byId = new Map(ports.map((p) => [p.id, p.name]))
  for (const [id, name] of Object.entries(ISLAND_PORTS)) expect(byId.get(id), `${id} is a real port`).toBe(name)
  const count = (n: string) => ports.filter((p) => p.name === n).length
  for (const name of Object.values(ISLAND_PORTS)) expect(count(name), `${name} names exactly one port`).toBe(1)
})
