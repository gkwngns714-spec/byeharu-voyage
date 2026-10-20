// sum.mjs <bands.json>... — one line per file: the median over origins of the best per-day profit in each
// band (<1k, 1–2.5k, 2.5–5k, 5–10k, 10k+ nm), and the median of per-origin ratios of each band to the
// short band (<1k). The target of the 2026-10-20 plan: long ≈ 1.3–1.5 × short per day.
import { readFileSync } from 'node:fs'
const med = (a) => { const s = a.filter((x) => x != null && isFinite(x)).sort((x, y) => x - y); if (!s.length) return null; const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2 }
const bands = [1, 2, 3, 4, 5]
const names = ['<1k', '1–2.5k', '2.5–5k', '5–10k', '10k+']
console.log('file | ' + names.map((n) => `median ${n}/day`).join(' | ') + ' | ' + names.slice(1).map((n) => `${n} ÷ <1k`).join(' | ') + ' | origins')
for (const f of process.argv.slice(2)) {
  const raw = JSON.parse(readFileSync(f, 'utf8'))
  const rows = raw[0]?.x ?? raw[0]?.jsonb_agg ?? raw
  const by = new Map()
  for (const r of rows) { if (!by.has(r.ocode)) by.set(r.ocode, {}); by.get(r.ocode)[r.band] = r }
  const medBand = bands.map((b) => med([...by.values()].map((m) => m[b]?.pday)))
  const ratios = bands.slice(1).map((b) => med([...by.values()].filter((m) => m[1]?.pday > 0 && m[b]).map((m) => m[b].pday / m[1].pday)))
  console.log(f.split(/[\\/]/).pop().padEnd(12) + ' | ' + medBand.map((x) => x == null ? '-' : Math.round(x).toLocaleString('en')).join(' | ') + ' | ' + ratios.map((x) => x == null ? '-' : x.toFixed(2)).join(' | ') + ' | ' + by.size)
  if (process.env.DETAIL) for (const [o, m] of by) console.log('  ' + o + ' | ' + bands.map((b) => m[b] ? `${m[b].pday} (${m[b].gcode} ${Math.round(m[b].nm)} nm ×${m[b].haul})` : '-').join(' | '))
}
