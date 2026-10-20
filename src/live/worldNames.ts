// THE WORLD'S NAMES IN THE VIEWER'S LANGUAGE — the one place served proper nouns are re-spelled.
//
// The server names every port, good, nation and hull in English (or in its historical form). The
// store keeps that SERVED copy untouched and publishes a named copy for the locale in force, so
// every screen that already reads `port.name` / `good.name` (and `portNameOf`, `nationNameOf`)
// prints Korean without a second lookup of its own. On a language switch the store re-derives the
// named copy from the served one; nothing is ever translated twice or translated back.
import { properName, type Locale } from '../lib/i18n'
import type { MarketView, WorldSnapshot } from '../lib/rpc'

export function namedSnapshot(served: WorldSnapshot, locale: Locale): WorldSnapshot {
  if (locale === 'en') return served
  return {
    ...served,
    ports: served.ports.map((p) => ({ ...p, name: properName('port', p.name, p.name, locale) })),
    goods: served.goods.map((g) => ({ ...g, name: properName('good', g.code, g.name, locale) })),
    nations: served.nations.map((n) => ({ ...n, name: properName('nation', n.code, n.name, locale) })),
    ship_classes: served.ship_classes.map((c) => ({ ...c, name: properName('hull', c.name, c.name, locale) })),
  }
}

export function namedMarket(served: MarketView, locale: Locale): MarketView {
  if (locale === 'en') return served
  return {
    ...served,
    port: served.port && { ...served.port, name: properName('port', served.port.name, served.port.name, locale) },
    goods: served.goods.map((g) => ({ ...g, name: properName('good', g.code, g.name, locale) })),
  }
}
