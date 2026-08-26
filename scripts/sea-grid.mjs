// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA, AS A GRID — and the shortest way through it between any two harbours.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The first version of this generator asked one question of a pair of ports: does the straight
// line between them stay at sea? That is the wrong question, and it showed: Lisbon and Cádiz are
// 188 nm apart and had NO leg between them, because the straight line clips the Algarve. Ships
// went round Cape St Vincent and so should the game.
//
// So the sea is rasterised — the Natural Earth land polygons scan-filled into a 0.25° grid — and a
// route is an A* search over the WATER cells. The result is a path that rounds capes, follows
// coasts and threads gulfs by itself, with no passage authored for any of it. The distance is the
// length of that path, which is exactly what DESIGN §B.3 means by a leg that "MAY EXCEED the
// great-circle figure where the real route detours".
//
// ── WHAT IS STILL AUTHORED, AND WHY ─────────────────────────────────────────────────────────────
// A 0.25° cell is about 15 nm. The Sound is two miles wide, the Bosphorus half of one, and at this
// resolution they are simply land — as are the Malacca narrows, Bab-el-Mandeb, Hormuz and the
// St Lawrence above the estuary. Those are the CHANNELS below: short chains of mid-water points
// whose cells are forced open before the search runs. Each one is a real navigable water, named,
// and the list is the whole of the game's "you may pass here" authority.
//
// A CHANNEL IS NOT ONLY A STRAIT. The section heading is the definition — "the water the map is
// too coarse to draw" — and 0.25° loses three KINDS of water, not one:
//   * a STRAIT or river narrower than a cell (the Sound, the Bosphorus, the Severn, the Hooghly);
//   * a GULF, BAY or ESTUARY whose whole basin scan-fills as land (Edo Bay, the Zuiderzee, the
//     Gulf of Smyrna, the Thermaic Gulf, the Tagus, Manila Bay);
//   * a ROADSTEAD — open ocean a coarse coastline swallowed, where the 110 m polygon bulges
//     seaward of the real shore and a harbour is left with no water at all (Valencia, Safi, the
//     Douro bar).
// All three fail the SAME way, and it is not a labelling failure: public.sea_reaches.snap_nm is
// what voyage.path_refusal grants a course as a LAND-EXEMPT HEAD ALLOWANCE, so a harbour with no
// water of its own buys a corridor across the country it stands in. That is what 0052 measured at
// Bristol and what 0060 measured at thirty-nine more.
//
// EACH ENTRY IS ONE CONTINUOUS WATERWAY, and that is a rule, not a preference. The points of an
// entry are joined by interpolation and every cell between two consecutive points is forced open,
// so a single entry holding TWO unconnected waters draws a canal between them. SIX entries in
// this list already do — measured 2026-08-26, `irrawaddy-sittaung` the worst of them: its leg from
// Yangon [16.8, 96.2] to the Chao Phraya [13.3, 100.6] is 330 nm long and opens 30 land cells, one
// of them 85.6 nm inland in the Tenasserim mountains, so the Gulf of Thailand reaches the Andaman
// Sea in 382 nm instead of the ~2,300 nm round Singapore. `elbe-weser`, `thames-scheldt`,
// `gironde`, `baltic-gulfs` and `gambia-senegal` spill the same way, 31-63 nm inland.
// THEY ARE NOT CLOSED HERE, and the reason is production, not taste: OPENING water can never
// invalidate a voyage already at sea (a course legal over the old raster is still legal over a
// superset of it), while CLOSING water can strand one mid-passage on a path that is now land.
// That needs a migration that deals with the fleets on those courses; see 0060's header.
// EVERYTHING ADDED SINCE IS ONE WATERWAY PER ENTRY. If two waters are not one water, they are
// two entries.
//
// AND THE POINTS OF AN ENTRY MUST LEAVE A FOUR-CONNECTED CHAIN OF CELLS. The interpolation steps
// every 5 nm, which is smaller than a cell almost everywhere — but not at 78°N, where 0.25° of
// longitude is 3.1 nm, and not where a leg runs diagonally across a cell corner. Both leave holes,
// and a hole matters: A* sails eight neighbours, so the water still LOOKS right, but
// build-sea-migration.mjs heals a newly opened cell to its nearest named sea over FOUR, and refuses
// to emit water that answers no sea. Isfjorden, the Zuiderzee, the Min, the Red River, the Trave
// and the Trondheimsfjord all needed extra points for exactly this reason (2026-08-26); when a
// channel is added, run the generator and read the "REACHABLE water with NO sea" refusal as
// "your chain has a gap", not as a raster disagreement.
//
// There is deliberately NO Suez and NO Panama — not cut until 1869 and 1914 — so the Mediterranean
// reaches India round the Cape and the Atlantic reaches the Pacific round the Horn. Those are not
// special cases in the code; they are simply channels nobody opened, and the grid does the rest.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', 'data')

export const CELL_DEG = 0.25
export const COLS = Math.round(360 / CELL_DEG)   // 1440
export const ROWS = Math.round(180 / CELL_DEG)   // 720
const NM_PER_RAD = 3440.065
const rad = (d) => (d * Math.PI) / 180

/** Cell centre → lat/lon and back. Row 0 is the north pole end. */
export const cellLat = (row) => 90 - (row + 0.5) * CELL_DEG
export const cellLon = (col) => -180 + (col + 0.5) * CELL_DEG
export const rowOf = (lat) => Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
export const colOf = (lon) => ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS

export function gcNm(lat1, lon1, lat2, lon2) {
  const dLat = rad(lat2 - lat1)
  const dLon = rad(lon2 - lon1)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2
  return 2 * NM_PER_RAD * Math.asin(Math.min(1, Math.sqrt(a)))
}

// ── THE CHANNELS — the water the map is too coarse to draw ─────────────────────────────────────
export const CHANNELS = [
  { id: 'danish-straits', name: 'the Danish Straits', points: [[57.6, 10.6], [57.0, 11.3], [56.1, 12.6], [55.6, 12.9], [55.3, 13.5], [55.2, 15.0]] },
  { id: 'turkish-straits', name: 'the Dardanelles and the Bosphorus', points: [[39.9, 25.8], [40.1, 26.2], [40.4, 26.8], [40.7, 28.2], [41.0, 29.0], [41.3, 29.3], [41.6, 30.0]] },
  { id: 'kerch', name: 'the Strait of Kerch', points: [[44.8, 36.4], [45.1, 36.5], [45.4, 36.7]] },
  { id: 'bab-el-mandeb', name: 'the Bab-el-Mandeb', points: [[12.3, 44.0], [12.6, 43.4], [13.2, 42.9], [15.0, 41.5], [17.5, 40.0], [20.0, 38.5], [24.0, 36.0], [27.0, 34.5]] },
  // Without this spur, Suez's nearest raster water is the MEDITERRANEAN, 72 nm north across the
  // isthmus — measured 2026-08-23, when suez->alexandria routed at 261 nm: a Suez Canal, three
  // centuries early. The gulf is 12-17 nm wide, under this raster's resolution, so it is a channel
  // like every other narrow water; the isthmus itself stays land and the two seas stay unjoined.
  { id: 'gulf-of-suez', name: 'the Gulf of Suez', points: [[27.0, 34.5], [27.8, 33.8], [28.5, 33.3], [29.2, 32.9], [29.9, 32.6]] },
  { id: 'hormuz', name: 'the Strait of Hormuz', points: [[24.8, 57.4], [25.8, 56.8], [26.3, 56.5], [26.4, 55.5], [26.4, 54.5], [27.2, 52.0], [28.6, 49.9], [29.6, 48.9], [30.0, 48.6]] },
  // Extended 2026-08-26 to the HEAD of the gulf. It used to stop at 21.4°N, 60 nm short of
  // Khambhat, which then snapped 57.77 nm across Gujarat to find water. Cambay at the gulf head
  // was the paramount port of western India until its bore-swept channels silted in the 17th
  // century — Duarte Barbosa's "Cambaieta", where the Gujarat trade to Hormuz, Aden and Malacca
  // was laden. The gulf is real open water the whole way.
  { id: 'khambhat', name: 'the Gulf of Khambhat', points: [[20.6, 71.8], [21.0, 72.0], [21.4, 72.3], [21.8, 72.45], [22.1, 72.55], [22.31, 72.62]] },
  // The Tapti is NOT the Gulf of Khambhat — a second waterway, so a second entry (see the header).
  // Surat was the Mughal empire's imperial port and the English and Dutch factory town; East
  // Indiamen lay in Swally Hole off the bar and worked the Tapti up to the city.
  { id: 'tapti', name: 'the Swally Roads and the Tapti', points: [[21.15, 72.35], [21.15, 72.6], [21.21, 72.84]] },
  { id: 'hooghly', name: 'the Hooghly approach', points: [[20.5, 88.3], [21.2, 88.2], [21.8, 88.1], [22.4, 88.2], [22.9, 88.4]] },
  { id: 'malacca', name: 'the Strait of Malacca', points: [[6.0, 95.6], [5.8, 96.0], [5.4, 96.8], [4.8, 98.0], [4.2, 98.8], [3.0, 100.5], [2.0, 102.0], [1.5, 103.0], [1.3, 103.6], [1.2, 104.3], [1.2, 104.8]] },
  { id: 'sunda', name: 'the Sunda Strait', points: [[-5.2, 105.8], [-5.7, 105.7], [-6.0, 105.6], [-6.4, 105.4], [-7.0, 105.2]] },
  { id: 'seto', name: 'the Kii and Bungo channels', points: [[32.9, 132.4], [33.3, 132.2], [33.7, 132.5], [34.0, 133.0], [34.3, 133.8], [34.5, 134.6], [34.3, 135.0], [33.8, 135.2]] },
  // Extended 2026-08-26 up the Northern Dvina to the city itself. It stopped at the bar and
  // Arkhangelsk snapped 22.76 nm over the delta. Arkhangelsk was Russia's ONLY sea port from 1584
  // to 1703: the Muscovy Company's ships, and the Dutch fleets after them, came in over the bar
  // and lay at the town, 30 miles up the Dvina.
  { id: 'white-sea', name: 'the Gorlo of the White Sea and the Northern Dvina', points: [[68.8, 41.5], [67.8, 41.2], [66.8, 41.0], [66.0, 40.4], [65.6, 39.8], [64.9, 39.8], [64.8, 40.1], [64.65, 40.35], [64.54, 40.54]] },
  { id: 'saint-lawrence', name: 'the River of Saint Lawrence', points: [[49.2, -64.5], [49.0, -65.5], [48.8, -66.5], [48.6, -67.6], [48.3, -68.8], [47.9, -69.6], [47.4, -70.2], [46.9, -70.9], [46.8, -71.2]] },
  { id: 'gironde', name: 'the Gironde and the Loire', points: [[45.6, -1.3], [45.4, -1.0], [45.0, -0.7], [44.9, -0.6], [47.2, -2.4], [47.3, -2.1], [47.2, -1.7]] },
  { id: 'thames-scheldt', name: 'the Thames and the Scheldt', points: [[51.5, 1.4], [51.5, 0.8], [51.5, 0.2], [51.5, -0.1], [51.6, 3.4], [51.4, 3.6], [51.3, 4.0], [51.2, 4.4]] },
  // Without this, Bristol's nearest raster water is LYME BAY — 64.8 nm away, on the far side of
  // Devon, in the English Channel (measured 2026-08-25; DEV_LOG D22 logged the same 65 nm snap and
  // flagged the fix for this worktree). The Severn estuary narrows below one cell above Barry, so
  // the whole Bristol Channel east of 4°W scan-fills as land and John Cabot's home port answers
  // the wrong sea from the wrong side of a peninsula. The water is real and was sailed: square
  // riggers worked the channel to King Road and warped seven miles up the Avon to the quay.
  { id: 'severn', name: 'the Bristol Channel and the Avon', points: [[51.4, -4.1], [51.4, -3.6], [51.4, -3.1], [51.5, -2.8], [51.5, -2.7], [51.45, -2.6]] },
  { id: 'elbe-weser', name: 'the Elbe and the Weser', points: [[54.0, 8.2], [53.9, 8.7], [53.7, 9.2], [53.5, 9.9], [53.5, 8.6], [53.2, 8.5]] },
  { id: 'guadalquivir', name: 'the Guadalquivir', points: [[36.8, -6.4], [37.0, -6.3], [37.2, -6.1], [37.4, -6.0]] },
  { id: 'pearl-river', name: 'the Pearl River', points: [[22.0, 114.0], [22.3, 113.8], [22.7, 113.6], [23.1, 113.3]] },
  { id: 'yangtze', name: 'the Yangtze and the Grand Canal mouth', points: [[31.2, 122.4], [31.4, 121.9], [31.5, 121.3], [32.0, 120.4]] },
  { id: 'irrawaddy-sittaung', name: 'the Yangon and Chao Phraya rivers', points: [[16.3, 96.3], [16.6, 96.2], [16.8, 96.2], [13.3, 100.6], [13.6, 100.6], [14.4, 100.6]] },
  { id: 'shatt-al-arab', name: 'the Shatt al-Arab', points: [[29.9, 48.7], [30.2, 48.5], [30.5, 47.9]] },
  { id: 'rio-de-la-plata', name: 'the Río de la Plata', points: [[-35.5, -56.0], [-35.0, -57.0], [-34.7, -58.0], [-34.6, -58.4]] },
  { id: 'amazon-para', name: 'the Pará and the Amazon mouth', points: [[-0.5, -47.5], [-1.0, -48.0], [-1.4, -48.5]] },
  { id: 'gambia-senegal', name: 'the Gambia and Senegal mouths', points: [[13.5, -16.8], [13.4, -16.5], [16.0, -16.6], [16.0, -16.4]] },
  { id: 'baltic-gulfs', name: 'the Gulf of Finland and the Gulf of Riga', points: [[59.5, 22.0], [59.6, 23.5], [59.5, 24.8], [57.8, 22.5], [57.5, 23.5], [56.9, 24.0]] },

  // ── ADDED 2026-08-26 (migration 0060) — the thirty-nine harbours left snapping over land ──────
  // 0052 fixed Bristol and measured the rest: 40 places still snapped more than 20 nm to sailable
  // water, thirteen of them more than 30 nm, and snap_nm is a LAND-EXEMPT head allowance, not a
  // label. Each entry below is ONE continuous waterway, ends at or beside a cell that is already
  // water, and names the water a ship of the period actually worked. The measured before → after
  // is in 0060's header.

  // NORTHERN EUROPE
  // The Marsdiep and the Zuiderzee. Amsterdam snapped 35.47 nm and Hoorn 32.76 nm — both across
  // North Holland to the open North Sea. Texel Roads inside the Marsdiep is where every VOC fleet
  // made up and took its departure; Hoorn was a VOC chamber on the Zuiderzee's west shore. The
  // channel stops at the Pampus shoal off Amsterdam, which is where a deep-laden East Indiaman
  // stopped too — she was floated over it on camels.
  { id: 'zuiderzee', name: 'the Marsdiep and the Zuiderzee', points: [[53.15, 4.65], [53.05, 4.85], [53.0, 4.95], [52.85, 5.0], [52.65, 5.07], [52.45, 5.1], [52.37, 5.1]] },
  // The Maasmond. Rotterdam snapped 25.52 nm over South Holland. Before the Nieuwe Waterweg (1872)
  // her seagoing traffic came in by the Maasmond at Den Briel and lay in the Brielse Maas.
  { id: 'maasmond', name: 'the Maasmond at Den Briel', points: [[51.9, 3.7], [51.9, 3.95], [51.9, 4.2]] },
  // The Bay of Lübeck, AND NO FURTHER. Lübeck snapped 21.68 nm over Holstein. Head of the
  // Hanseatic League: cogs and later fluyts came into the bay and lay at Travemünde, and the last
  // twelve miles up the Trave to the city quays were a river passage.
  // The channel stops at Travemünde, and that is a MEASURED refusal, not fastidiousness. Carried
  // on to Lübeck's own cell (53.875, -/+10.625) it put sailable water 22 nm from Hamburg's, and the
  // straightener exempts a tail of snap + one cell diagonal (27.5 nm at Hamburg): the neck of
  // Holstein disappeared and Hamburg→Tallinn fell from 991.5 nm round Denmark to 611.0 nm straight
  // over Schleswig — a Kiel Canal (1895), three centuries early, measured 2026-08-26. Stopping at
  // Travemünde leaves 36.6 nm of Holstein between the two waters, which no allowance covers.
  { id: 'trave', name: 'the Bay of Lubeck and Travemunde', points: [[54.15, 11.1], [54.05, 10.9], [53.95, 10.88]] },
  // The Pillau gat and the Frisches Haff. Königsberg snapped 24.70 nm. A Hanseatic Kontor and
  // Prussia's grain and timber port: ships entered by the Pillau gat, crossed the Haff and lay in
  // the Pregel at the town.
  { id: 'pillau', name: 'the Pillau gat, the Frisches Haff and the Pregel', points: [[54.7, 19.7], [54.64, 19.9], [54.7, 20.2], [54.72, 20.5]] },
  // The Firth of Forth. Leith snapped 20.24 nm inland. The Forth is eight kilometres wide at Leith
  // and was Scotland's chief east-coast sea road; Leith was Edinburgh's port and the Scottish
  // staple for the Baltic and Low Countries trades.
  { id: 'forth', name: 'the Firth of Forth', points: [[56.05, -2.7], [56.05, -3.0], [56.05, -3.2]] },
  // The Baie de Seine and the Seine mouth. Le Havre snapped 20.55 nm. Le Havre-de-Grace (1517) was
  // Normandy's ocean port at the river mouth and the departure of the French Newfoundland and
  // Guinea trades; the estuary above it carried Rouen's traffic.
  { id: 'seine', name: 'the Baie de Seine and the Seine mouth', points: [[49.6, -0.4], [49.55, -0.1], [49.49, 0.11]] },
  // The Abra of Bilbao. Bilbao snapped 22.05 nm over the Basque coast. Biscayan iron and Castilian
  // wool went out through the Abra and up the Nervion; the wool fleets to Bruges sailed from it.
  { id: 'abra-de-bilbao', name: 'the Abra of Bilbao', points: [[43.55, -2.93], [43.35, -2.93]] },
  // The Trondheimsleia and the Trondheimsfjord. Trondheim snapped 45.98 nm across Norway. Nidaros
  // was Norway's medieval capital and archiepiscopal see; the fjord is sixty miles of deep water
  // and carried the town's fish, timber and — from 1644 — the Roros copper.
  // The point at [63.45, 10.15] is not decoration: without it the chain steps DIAGONALLY from
  // (63.625, 10.125) to (63.375, 10.375), and build-sea-migration.mjs heals a newly opened cell to
  // its nearest named sea over FOUR neighbours. A diagonal-only link is sailable (A* takes eight)
  // but nameless, and the generator refuses to emit water that answers no sea.
  { id: 'trondheimsfjord', name: 'the Trondheimsleia and the Trondheimsfjord', points: [[63.65, 8.6], [63.65, 9.1], [63.65, 9.6], [63.6, 10.0], [63.45, 10.15], [63.44, 10.4]] },
  // Isfjorden. Longyearbyen snapped 67.68 nm — the worst in the world — right across Spitsbergen.
  // Isfjorden is the island's largest fjord system and was worked from the 1610s: English and
  // Dutch whalers used Trygghamna (Safe Haven) inside it, and Pomor hunters wintered in the fjord.
  { id: 'isfjorden', name: 'Isfjorden and Adventfjorden', points: [[78.15, 12.6], [78.15, 12.9], [78.15, 13.15], [78.15, 13.4], [78.16, 13.65], [78.17, 13.9], [78.18, 14.15], [78.2, 14.4], [78.22, 14.65], [78.24, 14.9], [78.25, 15.15], [78.24, 15.4], [78.22, 15.63]] },
  // The mouth of Nuup Kangerlua. Nuuk snapped 21.05 nm. Godthaab is 1728, but the Davis Strait was
  // Basque, Dutch and English whaling water from the 1610s and the west-Greenland fjord mouths
  // were their anchorages. This opens the fjord MOUTH only, not the ice-choked head.
  { id: 'godthaab-fjord', name: 'the mouth of Nuup Kangerlua', points: [[64.15, -52.4], [64.15, -52.1]] },

  // IBERIA, THE MEDITERRANEAN AND MOROCCO
  // The Tagus. Lisbon — the capital of the Portuguese seaborne empire — snapped 23.30 nm over
  // Estremadura. The Carreira da India took its departure from Belem, ten miles inside the bar,
  // and the whole India fleet lay in the Mar da Palha above the city.
  { id: 'tagus', name: 'the Tagus', points: [[38.68, -9.6], [38.68, -9.35], [38.7, -9.14]] },
  // The roads off the Douro bar. Porto snapped 23.34 nm: the 110 m coastline bulges 12 nm seaward
  // of the real shore here, so the port-wine fleets that lay outside the bar waiting for water to
  // cross it were standing on dry land.
  { id: 'douro-roads', name: 'the roads off the Douro bar', points: [[41.14, -9.1], [41.14, -8.85]] },
  // The Sado. Setubal snapped 26.17 nm. St Ubes salt loaded the Dutch, Hanseatic and English salt
  // fleets for the Baltic and the Newfoundland fishery all through the 16th-18th centuries.
  { id: 'sado', name: 'the Sado and the roads of Setubal', points: [[38.2, -9.1], [38.4, -9.0], [38.5, -8.9]] },
  // The roads of Valencia. Valencia snapped 24.11 nm — a roadstead case, not a strait: there was
  // no mole at El Grau until 1792, so Aragon's Mediterranean trade lay in the open roads off the
  // beach. Those roads are open Mediterranean the coarse coastline swallowed.
  { id: 'valencia-roads', name: 'the roads of Valencia', points: [[39.42, 0.15], [39.42, -0.15]] },
  // The roads of Safi. Safi snapped 21.98 nm. Asfi was Morocco's chief Atlantic port — Portuguese
  // 1488-1541 — and shipped Marrakesh's sugar, copper and hides from an open roadstead.
  { id: 'safi-roads', name: 'the roads of Safi', points: [[32.35, -9.6], [32.35, -9.35]] },
  // The Gulf of Patras. Patras snapped 47.21 nm across the Peloponnese. Lepanto (1571) was fought
  // in this gulf by four hundred galleys; Patras shipped currants to England and Holland.
  { id: 'patras', name: 'the Gulf of Patras', points: [[38.25, 20.95], [38.25, 21.25], [38.25, 21.5], [38.25, 21.73]] },
  // The Gulf of Smyrna. Izmir snapped 40.29 nm over Anatolia. Smyrna was the greatest Levant port
  // of the 17th-18th centuries — English Levant Company, French Echelles, Dutch and Venetian
  // factories — and whole fleets lay in the gulf.
  { id: 'izmir', name: 'the Gulf of Smyrna', points: [[38.6, 26.2], [38.6, 26.6], [38.5, 26.9], [38.43, 27.14]] },
  // The Thermaic Gulf. Thessaloniki snapped 31.06 nm over Macedonia. Salonica was the Ottoman
  // empire's second port and the gulf below it is twenty miles of open water.
  { id: 'thermaic', name: 'the Thermaic Gulf', points: [[40.1, 22.87], [40.35, 22.9], [40.55, 22.92], [40.64, 22.94]] },

  // WEST AFRICA
  // The Lagos bar and lagoon. Lagos snapped 20.13 nm. Eko's bar was notorious and ships lay in the
  // roads outside it to lighter through, but the lagoon behind was worked from the 16th century.
  { id: 'lagos-bar', name: 'the Lagos bar and lagoon', points: [[6.2, 3.38], [6.46, 3.39]] },
  // The Cross River. Calabar snapped 34.68 nm. Old Calabar was one of the two great Bight of
  // Biafra slaving ports; Bristol and Liverpool ships of 200-300 tons worked fifty miles up the
  // estuary to Duke Town and Creek Town and lay there for months.
  { id: 'cross-river', name: 'the Cross River and Old Calabar', points: [[4.4, 8.3], [4.65, 8.3], [4.85, 8.32], [4.95, 8.32]] },
  // The roads of Luanda. Luanda snapped 24.71 nm — another coarse-coast roadstead. Luanda (1576)
  // was the capital of Portuguese Angola and the largest slave-embarkation port in the Atlantic;
  // the Brazil fleets lay in the bay behind the Ilha do Cabo.
  { id: 'luanda-roads', name: 'the roads of Luanda', points: [[-8.8, 12.9], [-8.82, 13.1], [-8.84, 13.23]] },

  // THE AMERICAS
  // The Gulf of Cariaco. Cumana snapped 25.65 nm. Cumana (1515) is the oldest continuously
  // occupied European settlement on the American mainland, and the Araya salt pans across this
  // gulf drew Dutch salt fleets by the hundred in 1600-1605.
  { id: 'cariaco', name: 'the Gulf of Cariaco', points: [[10.5, -64.6], [10.48, -64.4], [10.45, -64.17]] },
  // The James River. Jamestown snapped 31.75 nm across Virginia. The 1607 fleet anchored at
  // Jamestown itself, and the tobacco ships loaded at plantation wharves sixty miles up the James.
  { id: 'james-river', name: 'the James River', points: [[37.15, -76.15], [37.05, -76.35], [37.13, -76.6], [37.21, -76.78]] },

  // SOUTH AND SOUTH-EAST ASIA
  // The Mergui Archipelago. Myeik snapped 28.13 nm. Mergui was Siam's Andaman-side port and the
  // sea end of the overland road to Ayutthaya; English country traders lay among these islands in
  // the 1680s.
  { id: 'mergui', name: 'the Mergui Archipelago', points: [[12.44, 97.9], [12.44, 98.2], [12.44, 98.45], [12.44, 98.6]] },
  // The Red River. Hanoi snapped 58.68 nm — second worst in the world — across Tonkin. The VOC
  // held a factory at Ke Cho (Hanoi) from 1637 and the English EIC from 1672; ships came in by the
  // Ba Lat mouth, big hulls lying at Domea while yachts and country craft worked up to the city.
  // The same shape as the Hooghly entry above, and the same length of river.
  { id: 'red-river', name: 'the Red River to Ke Cho', points: [[20.4, 106.65], [20.5, 106.4], [20.6, 106.35], [20.6, 106.1], [20.7, 105.95], [20.8, 105.95], [21.02, 105.84]] },

  // CHINA, KOREA AND JAPAN
  // The Min. Fuzhou snapped 32.77 nm — and to the WRONG SEA, the East China Sea, while the port
  // declares the Taiwan Strait. Foochow was the official terminus of the Ryukyu tribute trade with
  // a Ryukyuan hostel from 1472; junks lay at the Pagoda Anchorage below the city.
  { id: 'min-river', name: 'the Min and the Pagoda Anchorage', points: [[25.95, 119.85], [26.05, 119.85], [26.03, 119.63], [26.02, 119.45], [26.08, 119.29]] },
  // Quanzhou Bay. Quanzhou snapped 23.11 nm. Zaitun was, to Marco Polo and Ibn Battuta, the
  // greatest port in the world; its bay carried the Song and Yuan South Seas trade.
  { id: 'quanzhou-bay', name: 'Quanzhou Bay', points: [[24.7, 118.9], [24.85, 118.7], [24.91, 118.59]] },
  // Amoy harbour. Xiamen snapped 26.74 nm. Amoy was the great Fujian junk-trade port, Zheng
  // Chenggong's base, and the East India Company's Fujian station from 1676.
  { id: 'amoy', name: 'Amoy harbour and the Jiulong', points: [[24.25, 118.35], [24.4, 118.15], [24.48, 118.08]] },
  // The Yong. Ningbo snapped 22.40 nm. Mingzhou was the Song and Ming port for the Japan trade and
  // the Portuguese "Liampo" of the 1540s; junks lay at Zhenhai and worked the river to the city.
  { id: 'yong-river', name: 'the Yong and the Zhenhai approach', points: [[30.1, 121.9], [30.0, 121.8], [29.9, 121.6]] },
  // The Taedong. Nampo snapped 25.40 nm. The estuary was the sea road to Pyongyang, worked by
  // Korean coastal craft and by the junk trade; the treaty port itself is 1897, so this is the
  // weakest justification in the list and it opens the ESTUARY only, not the river to the capital.
  { id: 'taedong', name: 'the Taedong estuary', points: [[38.7, 124.9], [38.65, 125.15], [38.73, 125.4]] },
  // The Flying Fish Channel. Incheon snapped 24.02 nm. Jemulpo as a treaty port is 1883, so this
  // is weak too; what is not weak is Gyeonggi Bay itself, the sea approach to the Korean capital,
  // island-studded but navigable and used by Chinese and Korean shipping. The ESTUARY only.
  { id: 'gyeonggi-bay', name: 'the Flying Fish Channel', points: [[37.4, 126.15], [37.4, 126.4]] },
  // Manila Bay. Manila snapped 24.67 nm. This is the Manila Galleon's home water, entered by the
  // Boca Chica and Boca Grande at Corregidor; the bay is thirty miles across.
  { id: 'manila-bay', name: 'Manila Bay', points: [[14.4, 120.5], [14.5, 120.75], [14.58, 120.9]] },
  // The Uraga Channel and Edo Bay. Tokyo snapped 47.69 nm across the Kanto plain. Edo Bay carried
  // the entire coastal trade of Japan — the Higaki-kaisen and Taru-kaisen from Osaka, and the rice
  // of the north — and Uraga was its customs station from 1720.
  { id: 'edo-bay', name: 'the Uraga Channel and Edo Bay', points: [[34.9, 139.85], [35.15, 139.75], [35.4, 139.85], [35.6, 139.85]] },
  // Osaka Bay. Osaka snapped 26.49 nm and Sakai 21.11 nm. Osaka was the kitchen of Japan and Sakai
  // its older free port; the bay is entered from the Kii Channel through the Tomogashima Strait,
  // which the `seto` entry already reaches. The channel stops at the bay head, where the kaisen
  // stopped and the river craft took over.
  { id: 'osaka-bay', name: 'Osaka Bay', points: [[34.4, 135.1], [34.5, 135.25], [34.65, 135.4]] },
  // Kinko Bay. Kagoshima snapped 22.29 nm. This was the Shimazu domain's own water: Xavier landed
  // here in 1549 and it was the base of the Satsuma trade with the Ryukyus and China.
  { id: 'kagoshima-bay', name: 'Kinko Bay', points: [[31.05, 130.4], [31.2, 130.6], [31.4, 130.6], [31.6, 130.56]] },
]

// ── THE ICE — the water the age of sail could never use ────────────────────────────────────────
// The inverse authority of CHANNELS: named waters CLOSED by hand. The raster models land, not
// pack ice, so without this the Arctic reads as open water and the router discovers the polar
// passages — the first thing the ocean-road pass found (2026-08-23) was Arkhangelsk — Nampo,
// 6,396 nm along the Siberian coast: the Northeast Passage, first actually sailed by
// Nordenskiöld in 1878-79. So these waters are ice, whatever the season:
//   * the Siberian arctic east of Novaya Zemlya — the Kara, Laptev, East Siberian and Chukchi seas;
//   * the Canadian arctic and northern Baffin Bay — the Northwest Passage, probed at its mouth by
//     Frobisher and Davis in the 1570s-80s and not forced until Amundsen in 1903-06;
//   * the Antarctic pack, south of 60°S, the whole way round — see that entry's own note.
// The Barents Sea and the White Sea road to Arkhangelsk stay open (the Muscovy Company sailed them
// from 1553), as do Svalbard's whaling grounds and the Davis Strait up to Nuuk.
//
// A closure names ONE parallel and the longitudes it spans. `latAbove` closes everything poleward
// of that parallel to the NORTH; `latBelow` everything poleward of it to the SOUTH. Exactly one of
// the two, so a closure always has a side. The southern form used to be a `cells.fill(0)` loop of
// its own inside scripts/build-sea-migration.mjs — the same concept said twice, in two files, one
// of them a generator, which is the second authority docs/NO_SPAGHETTI.md forbids. Since
// 2026-08-25 it is an ICE row like any other and the generator reads THIS list for both poles.
export const ICE = [
  { id: 'northeast-passage', name: 'the Siberian arctic', latAbove: 66.5, lonFrom: 60, lonTo: 180 },
  { id: 'northwest-passage', name: 'the Canadian arctic', latAbove: 66.5, lonFrom: -180, lonTo: -60 },
  // 60°S is where the period stops, and the dates are the argument, not the taste. The
  // southernmost land anyone had seen by the end of this game's century was South Georgia (54°S,
  // Antonio de la Roché, 1675); the South Shetlands at 62°S were not sighted until William Smith
  // in 1819, the Antarctic Circle not crossed until Cook in 1773, the continent itself not seen
  // until 1820. Everything the age of sail actually worked lies north of this line and stays open:
  // Cape Horn at 55.98°S and the Drake Passage under it — Veracruz→Acapulco and Buenos Aires→
  // Callao both round it through 55.63°S, measured 2026-08-25, unchanged by this closure; the
  // Roaring Forties and Furious Fifties of the Brouwer route, which Rio de Janeiro→Manila rides
  // at 43.9°S; and the sub-Antarctic sealing and whaling grounds about South Georgia. South of
  // 60°S is pack ice, and no hull in this world was built for it.
  { id: 'antarctic-pack', name: 'the Antarctic pack', latBelow: -60, lonFrom: -180, lonTo: 180 },
]

/** The row span an ICE closure covers, from the side it declares. Exactly one side, or it is not
 *  a closure — a row with neither (or both) would silently close the whole globe or nothing. */
export function iceRowFrom(ice) {
  assertOneSide(ice)
  return ice.latBelow === undefined ? 0 : rowOf(ice.latBelow)
}
export function iceRowTo(ice) {
  assertOneSide(ice)
  return ice.latAbove === undefined ? ROWS - 1 : rowOf(ice.latAbove)
}
function assertOneSide(ice) {
  const north = ice.latAbove !== undefined
  const south = ice.latBelow !== undefined
  if (north === south) {
    throw new Error(`ICE "${ice.id}" must declare exactly one of latAbove / latBelow — it has ${north ? 'both' : 'neither'}`)
  }
}

/** Is this cell inside an authored ice closure? The ONE reading of "closed by hand, not by land",
 *  so a generator can tell an ice cell from a land cell without re-deriving the rule. */
export function inIce(lat, lon) {
  const row = rowOf(lat)
  for (const ice of ICE) {
    if (row < iceRowFrom(ice) || row > iceRowTo(ice)) continue
    if (lon >= ice.lonFrom && lon <= ice.lonTo) return ice
  }
  return null
}

// ── the land, scan-filled into the grid ───────────────────────────────────────────────────────
function landPolygons() {
  const fc = JSON.parse(readFileSync(join(DATA, 'world-110m.json'), 'utf8'))
  const polys = []
  for (const f of fc.features) {
    const g = f.geometry
    if (!g) continue
    if (g.type === 'Polygon') polys.push(g.coordinates)
    else if (g.type === 'MultiPolygon') for (const p of g.coordinates) polys.push(p)
  }
  return polys
}

/**
 * THE GRID. One byte per cell: 1 = water, 0 = land.
 * Built by scan-filling each land polygon with the even-odd rule, so holes (the Caspian, inland
 * seas) come out as water without a second pass.
 */
export function buildSeaGrid() {
  const water = new Uint8Array(COLS * ROWS).fill(1)
  for (const rings of landPolygons()) {
    // Row range this polygon can touch.
    let minLat = 90, maxLat = -90
    for (const ring of rings) for (const [, lat] of ring) {
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    }
    const rowFrom = rowOf(maxLat)
    const rowTo = rowOf(minLat)
    for (let row = rowFrom; row <= rowTo; row++) {
      const lat = cellLat(row)
      const xs = []
      for (const ring of rings) {
        for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
          const [x1, y1] = ring[j]
          const [x2, y2] = ring[i]
          if (y1 > lat !== y2 > lat) xs.push(x1 + ((lat - y1) / (y2 - y1)) * (x2 - x1))
        }
      }
      if (xs.length < 2) continue
      xs.sort((a, b) => a - b)
      for (let k = 0; k + 1 < xs.length; k += 2) {
        const from = colOf(xs[k])
        const to = colOf(xs[k + 1])
        const span = to >= from ? to - from : COLS - from + to
        for (let s = 0; s <= span; s++) water[row * COLS + ((from + s) % COLS)] = 0
      }
    }
  }

  // The ice: authored CLOSED water (see ICE above) — the waters the period could not force, at
  // BOTH poles through the one list. `latAbove` runs from the north edge down to that parallel;
  // `latBelow` runs from that parallel down to the south edge.
  for (const ice of ICE) {
    for (let row = iceRowFrom(ice); row <= iceRowTo(ice); row++) {
      for (let col = 0; col < COLS; col++) {
        const lon = cellLon(col)
        if (lon >= ice.lonFrom && lon <= ice.lonTo) water[row * COLS + col] = 0
      }
    }
  }

  // The channels: force their cells — and the cells between consecutive points — open.
  for (const ch of CHANNELS) {
    for (let i = 0; i < ch.points.length; i++) {
      openCell(water, ch.points[i][0], ch.points[i][1])
      if (i + 1 < ch.points.length) {
        const [la, lo] = ch.points[i]
        const [lb, lb2] = ch.points[i + 1]
        const steps = Math.ceil(gcNm(la, lo, lb, lb2) / 5)
        for (let s = 1; s < steps; s++) {
          openCell(water, la + ((lb - la) * s) / steps, lo + ((lb2 - lo) * s) / steps)
        }
      }
    }
  }
  return water
}

function openCell(water, lat, lon) {
  water[rowOf(lat) * COLS + colOf(lon)] = 1
}

export const isWater = (water, row, col) => water[row * COLS + ((col % COLS) + COLS) % COLS] === 1

/** The nearest water cell to a coordinate, searched outward. Harbours sit ON the coastline, so a
 *  port's own cell is often land at this resolution; that is expected, not an error. */
export function snapToWater(water, lat, lon, maxRings = 8) {
  const r0 = rowOf(lat)
  const c0 = colOf(lon)
  if (isWater(water, r0, c0)) return { row: r0, col: c0, ringsOut: 0 }
  for (let ring = 1; ring <= maxRings; ring++) {
    for (let dr = -ring; dr <= ring; dr++) {
      for (let dc = -ring; dc <= ring; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue
        const row = r0 + dr
        if (row < 0 || row >= ROWS) continue
        const col = ((c0 + dc) % COLS + COLS) % COLS
        if (isWater(water, row, col)) return { row, col, ringsOut: ring }
      }
    }
  }
  return null
}

// ── A*, over water cells ──────────────────────────────────────────────────────────────────────
const NEIGHBOURS = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]]

/**
 * The shortest navigable path between two coordinates, or null if there is none.
 * Returns { nm, path } where path is the simplified polyline (lat/lon pairs) including both ends.
 *
 * The heuristic is the great circle to the goal, which never overestimates, so the first path A*
 * settles on is the shortest one the grid allows.
 */
export function findSeaRoute(water, from, to, opts = {}) {
  const limitNm = opts.limitNm ?? Infinity
  const a = snapToWater(water, from.lat, from.lon)
  const b = snapToWater(water, to.lat, to.lon)
  if (!a || !b) return null
  const start = a.row * COLS + a.col
  const goal = b.row * COLS + b.col
  if (start === goal) {
    const nm = gcNm(from.lat, from.lon, to.lat, to.lon)
    return { nm, path: [[from.lat, from.lon], [to.lat, to.lon]] }
  }

  const goalLat = cellLat(b.row)
  const goalLon = cellLon(b.col)
  const g = new Map([[start, 0]])
  const cameFrom = new Map()
  const open = [[gcNm(cellLat(a.row), cellLon(a.col), goalLat, goalLon), start]]
  const closed = new Set()

  const pop = () => {
    // Binary heap would be tidier; a linear scan over a few thousand entries is fast enough and
    // this runs offline. Kept simple on purpose.
    let bestI = 0
    for (let i = 1; i < open.length; i++) if (open[i][0] < open[bestI][0]) bestI = i
    const [, node] = open[bestI]
    open[bestI] = open[open.length - 1]
    open.pop()
    return node
  }

  while (open.length > 0) {
    const current = pop()
    if (closed.has(current)) continue
    closed.add(current)
    if (current === goal) break
    const row = Math.floor(current / COLS)
    const col = current % COLS
    const lat = cellLat(row)
    const lon = cellLon(col)
    const cost = g.get(current)
    if (cost > limitNm) continue
    for (const [dr, dc] of NEIGHBOURS) {
      const nrow = row + dr
      if (nrow < 0 || nrow >= ROWS) continue
      const ncol = ((col + dc) % COLS + COLS) % COLS
      if (!isWater(water, nrow, ncol)) continue
      const next = nrow * COLS + ncol
      if (closed.has(next)) continue
      const step = gcNm(lat, lon, cellLat(nrow), cellLon(ncol))
      const tentative = cost + step
      if (tentative >= (g.get(next) ?? Infinity)) continue
      g.set(next, tentative)
      cameFrom.set(next, current)
      open.push([tentative + gcNm(cellLat(nrow), cellLon(ncol), goalLat, goalLon), next])
    }
  }

  if (!g.has(goal)) return null

  // Walk the path back, then straighten it: the grid's 45° staircase is an artefact of the raster,
  // not of the sea. Line-of-sight simplification replaces runs of cells with the straight leg a
  // ship would actually sail, as long as that straight leg stays in water.
  const cells = []
  for (let node = goal; node !== undefined; node = cameFrom.get(node)) {
    cells.push(node)
    if (node === start) break
  }
  cells.reverse()
  const points = [[from.lat, from.lon], ...cells.map((n) => [cellLat(Math.floor(n / COLS)), cellLon(n % COLS)]), [to.lat, to.lon]]
  const simplified = straighten(water, points)
  let nm = 0
  for (let i = 0; i + 1 < simplified.length; i++) {
    nm += gcNm(simplified[i][0], simplified[i][1], simplified[i + 1][0], simplified[i + 1][1])
  }
  return { nm, path: simplified }
}

/** Is every cell along this straight segment water? The ends are exempt: a harbour is on land. */
function segmentInWater(water, [lat1, lon1], [lat2, lon2], exemptEnds) {
  const nm = gcNm(lat1, lon1, lat2, lon2)
  const steps = Math.max(2, Math.ceil(nm / 8))
  for (let s = 1; s < steps; s++) {
    const f = s / steps
    // Straight in lat/lon is close enough over the short spans this is used on, and it never
    // wraps: the pathfinder's own points are always within a cell or two of each other.
    if (Math.abs(lon2 - lon1) > 180) return false
    const lat = lat1 + (lat2 - lat1) * f
    const lon = lon1 + (lon2 - lon1) * f
    if (exemptEnds && (f * nm < 25 || (1 - f) * nm < 25)) continue
    if (!isWater(water, rowOf(lat), colOf(lon))) return false
  }
  return true
}

function straighten(water, points) {
  const out = [points[0]]
  let i = 0
  while (i < points.length - 1) {
    let j = points.length - 1
    for (; j > i + 1; j--) {
      if (segmentInWater(water, points[i], points[j], i === 0 || j === points.length - 1)) break
    }
    out.push(points[j])
    i = j
  }
  return out
}
