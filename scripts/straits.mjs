// ═══════════════════════════════════════════════════════════════════════════════════════════════
// straits.mjs — THE REAL STRAITS, PINNED PASSABLE (0446, owner row 352)
//
// 0440 and 0441 took every course off the land. Four real straits closed with them and nothing said
// so: Messina to Zakynthos went from 291 nm to 630, round Sicily. This is the list that would have
// said so. Each row names a strait a ship of the period could pass, a harbour on each side of it, the
// box of water the course between them must run through, and how far over the straight line between
// the two roadsteads the course may be.
//
// tests/sea.straits.spec.ts holds the built world to it (the course the browser's course author plots:
// the search, then the re-sailing off the coast mask). scripts/build-straits.mjs holds the rows whose
// `id` is a channel it opens, and migration 0446 asserts them on the server's own law.
//
// `within` is the ratio measured on 2026-11-15 plus a few per cent, so a roadstead may move a little.
// A row is only ever removed by a slice that says, in its dev-log, why that strait may close.
//
// NOT ON THE LIST, and why (docs/dev-log/2026-11-16-straits.md):
//   * the Kanmon strait (Shimonoseki to Osaka is 562 nm round Kyushu): closed in the raster before 0440
//     too; narrower than the chart's pixel, so it would be a river carve. Its own slice.
//   * Moon Sound (Riga to Tallinn): the old 164 nm course ran across mainland Estonia; the sound is shoal
//     and narrower than the course author's grid.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** `box`: [south, north, west, east]. `id`: the charted channel (scripts/sea-grid.mjs) that opens it, when one does. */
export const STRAIT_PASSES = [
  { id: 'messina', name: 'the Strait of Messina', a: 'MES', b: 'ZAK', box: [37.9, 38.35, 15.5, 15.75], within: 1.2 },
  { id: 'messina', name: 'the Strait of Messina', a: 'NAP', b: 'ZAK', box: [37.9, 38.35, 15.5, 15.75], within: 1.3 },
  { id: 'great-belt', name: 'the Great Belt', a: 'LUB', b: 'BER', box: [55.4, 55.8, 10.7, 11.0], within: 1.3 },
  { id: 'bangka', name: 'the Bangka strait', a: 'BNT', b: 'LGA', box: [-3.0, -2.0, 105.0, 106.1], within: 1.15 },
  { id: 'surabaya', name: 'the western fairway of Surabaya', a: 'JAK', b: 'SUR', box: [-7.2, -6.95, 112.5, 112.8], within: 1.1 },
  { name: 'the Strait of Bonifacio', a: 'BAR', b: 'NAP', box: [41.15, 41.45, 8.9, 9.6], within: 1.08 },
  { name: 'the Strait of Gibraltar', a: 'CAD', b: 'MLG', box: [35.8, 36.15, -5.9, -5.2], within: 1.35 },
  { name: 'the Strait of Dover', a: 'CLS', b: 'PTH', box: [50.8, 51.25, 1.0, 1.9], within: 1.1 },
  { name: 'the English Channel', a: 'PLY', b: 'PTH', box: [49.5, 51.0, -4.5, -1.0], within: 1.1 },
  { name: 'the Bosporus', a: 'IST', b: 'TRA', box: [40.95, 41.3, 28.9, 29.3], within: 1.2 },
  { name: 'the Dardanelles', a: 'IST', b: 'IZM', box: [39.9, 40.45, 26.0, 26.8], within: 1.5 },
  { name: 'the Corfu channels', a: 'COR', b: 'PAT', box: [39.3, 39.9, 19.8, 20.3], within: 1.08 },
  { name: 'the Sound', a: 'COP', b: 'LUB', box: [55.3, 56.1, 12.4, 13.0], within: 1.17 },
  { name: 'the Sound', a: 'BER', b: 'GDA', box: [55.3, 56.1, 12.4, 13.0], within: 1.25 },
  { name: 'the Irish Sea', a: 'DUB', b: 'BRS', box: [51.5, 53.5, -6.5, -4.5], within: 1.4 },
  { name: 'the North Channel', a: 'DUB', b: 'BER', box: [54.8, 55.5, -6.3, -5.0], within: 1.4 },
  { name: 'the Minch', a: 'DUB', b: 'TOR', box: [57.2, 58.6, -6.8, -5.2], within: 1.12 },
  { name: 'the Bab-el-Mandeb', a: 'ADE', b: 'MOC', box: [12.2, 13.1, 43.0, 43.7], within: 1.22 },
  { name: 'the Strait of Hormuz', a: 'MUS', b: 'MAN', box: [25.8, 26.9, 55.8, 57.0], within: 1.17 },
  { name: 'the Palk strait', a: 'JAF', b: 'CHE', box: [9.6, 10.6, 79.5, 80.5], within: 1.1 },
  { name: 'the Strait of Malacca', a: 'BAN', b: 'MAL', box: [2.0, 4.5, 99.0, 102.0], within: 1.15 },
  { name: 'the Singapore strait', a: 'MAL', b: 'LGA', box: [0.6, 1.45, 103.2, 104.6], within: 1.1 },
  { name: 'the Sunda strait', a: 'BNT', b: 'FRE', box: [-6.4, -5.7, 105.3, 106.0], within: 1.12 },
  { name: 'the Bali and Lombok straits', a: 'SUR', b: 'FRE', box: [-9.2, -8.0, 114.3, 116.2], within: 1.17 },
  { name: 'the Torres strait', a: 'DAR', b: 'SYD', box: [-11.0, -9.8, 141.5, 143.5], within: 1.48 },
  { name: 'the Bass strait', a: 'SYD', b: 'FRE', box: [-40.6, -38.8, 143.5, 148.5], within: 1.27 },
  { name: 'the Cook strait', a: 'WLG', b: 'SYD', box: [-41.6, -40.5, 173.8, 175.2], within: 1.08 },
  { name: 'the Taiwan strait', a: 'XIA', b: 'TAI', box: [22.5, 25.5, 118.0, 121.0], within: 1.08 },
  { name: 'the Taiwan strait', a: 'FUZ', b: 'HON', box: [22.5, 25.5, 118.0, 121.0], within: 1.12 },
  { name: 'the Korea strait', a: 'BUS', b: 'FUK', box: [33.5, 35.2, 128.5, 130.5], within: 1.08 },
  { name: 'the Korea strait', a: 'NAG', b: 'ULS', box: [33.5, 35.2, 128.5, 130.5], within: 1.1 },
  { name: 'the Tsugaru strait', a: 'MAT', b: 'TOK', box: [41.1, 41.8, 140.2, 141.5], within: 1.33 },
  { name: 'the Kii channel', a: 'OSA', b: 'TOK', box: [33.5, 34.4, 134.6, 135.3], within: 1.3 },
  { name: 'the Strait of Magellan', a: 'BUE', b: 'VLP', box: [-54.0, -52.3, -74.5, -68.3], within: 4.7 },
  { name: 'the Florida strait', a: 'HAV', b: 'STA', box: [23.5, 26.5, -81.5, -79.3], within: 1.25 },
  { name: 'the Yucatan channel', a: 'VER', b: 'POR', box: [21.0, 22.2, -86.8, -85.0], within: 1.16 },
  { name: 'the Windward passage', a: 'POR', b: 'NEW', box: [19.5, 20.4, -74.6, -73.4], within: 1.12 },
  { name: 'the Mona passage', a: 'SGO', b: 'SAN', box: [17.8, 18.7, -68.4, -67.2], within: 1.1 },
]

/** Does a course run through a box? Sampled every nautical mile (never across the antimeridian: no box lies on it). */
export function courseInBox(course, [south, north, west, east], gcNm) {
  for (let i = 0; i + 1 < course.length; i++) {
    const [p, q] = [course[i], course[i + 1]]
    if (Math.abs(q[1] - p[1]) > 180) continue
    const n = Math.max(1, Math.ceil(gcNm(p[0], p[1], q[0], q[1])))
    for (let t = 0; t <= n; t++) {
      const la = p[0] + ((q[0] - p[0]) * t) / n
      const lo = p[1] + ((q[1] - p[1]) * t) / n
      if (la >= south && la <= north && lo >= west && lo <= east) return true
    }
  }
  return false
}
