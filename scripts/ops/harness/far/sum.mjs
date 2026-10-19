// throwaway: summarise a baseline file: per band the median of per-origin best per-day, and long/short ratios
import { readFileSync } from 'node:fs'
const raw = JSON.parse(readFileSync(process.argv[2], 'utf8'))
const rows = raw[0].jsonb_agg ?? raw[0].x ?? raw
const by = new Map()
for (const r of rows) { if (!by.has(r.ocode)) by.set(r.ocode, {}); by.get(r.ocode)[r.band] = r }
const med = (a) => { const s = a.filter((x) => x != null && isFinite(x)).sort((x, y) => x - y); if (!s.length) return null; const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2 }
const bands = [1, 2, 3, 4, 5]
console.log('origin | ' + bands.map((b) => `band${b} per-day (good, nm)`).join(' | '))
for (const [o, m] of by) console.log(o + ' | ' + bands.map((b) => m[b] ? `${m[b].pday} (${m[b].gcode} ${Math.round(m[b].nm)})` : '-').join(' | '))
const medBand = bands.map((b) => med([...by.values()].map((m) => m[b]?.pday)))
console.log('median per band:', medBand.map((x) => x == null ? '-' : Math.round(x)).join(' / '))
const ratios = (lb, sb) => med([...by.values()].map((m) => (m[sb]?.pday > 0 && m[lb] ? Math.max(...lb.map ? [] : []) : null)))
// long = best of bands 4,5 ; short = band 1
const per = [...by.values()].map((m) => {
  const s = m[1]?.pday; const l = Math.max(m[4]?.pday ?? -Infinity, m[5]?.pday ?? -Infinity); const mid = m[3]?.pday
  return { s, l, mid }
}).filter((x) => x.s > 0 && isFinite(x.l))
console.log('origins compared:', per.length)
console.log('median ratio long(5k+)/short(<1k):', med(per.map((x) => x.l / x.s))?.toFixed(2), ' ratio of medians:', (med(per.map((x) => x.l)) / med(per.map((x) => x.s))).toFixed(2))
console.log('median ratio band3(2.5-5k)/short:', med(per.map((x) => x.mid / x.s))?.toFixed(2))
void ratios
{
  const per2 = [...by.values()].map((m) => ({ s: Math.max(m[1]?.pday ?? -Infinity, m[2]?.pday ?? -Infinity), l: Math.max(m[4]?.pday ?? -Infinity, m[5]?.pday ?? -Infinity), l5: m[5]?.pday, l4: m[4]?.pday, b3: m[3]?.pday })).filter((x) => x.s > 0 && isFinite(x.l))
  console.log('SHORT(<2.5k) vs LONG(5k+): origins', per2.length, '| median short', Math.round(med(per2.map((x) => x.s))), '| median long', Math.round(med(per2.map((x) => x.l))),
    '| median of ratios', med(per2.map((x) => x.l / x.s)).toFixed(2), '| ratio of medians', (med(per2.map((x) => x.l)) / med(per2.map((x) => x.s))).toFixed(2),
    '| 2.5-5k/short', (med(per2.map((x) => x.b3 / x.s))).toFixed(2), '| 5-8k/short', med(per2.map((x) => x.l4 / x.s)).toFixed(2), '| 8k+/short', med(per2.map((x) => x.l5 / x.s)).toFixed(2))
}
