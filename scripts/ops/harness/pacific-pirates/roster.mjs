// roster.mjs: THE PIRATES' ROSTER OF 0410, AS DATA. Deterministic: no dice, no clock. One block is ten ships in six fleets:
// three lone small ships, one lone xebec, a pair of xebecs, and a squadron (a lead ship and three xebecs). The pair and the squadron of a
// hub's FIRST block sail for one house (a house of two fleets); Pitcairn's second block too. Every other fleet is a house of its own.
export const HUBS = [
  { code: 'PTC', ground: 'PACIFIC', ground_name: 'Pacific Ocean', ground_ko: '태평양', ships: 50, base: 1000, lead: 'galeoncete', reach: 3100 },
  { code: 'MWY', ground: 'PACIFIC', ground_name: 'Pacific Ocean', ground_ko: '태평양', ships: 20, base: 2000, lead: 'galeoncete', reach: 2500 },
  { code: 'TDC', ground: 'SOUTH_ATLANTIC', ground_name: 'South Atlantic Ocean', ground_ko: '남대서양', ships: 40, base: 3000, lead: 'galeoncete', reach: 2400 },
  { code: 'FLO', ground: 'NORTH_ATLANTIC', ground_name: 'North Atlantic Ocean', ground_ko: '북대서양', ships: 40, base: 4000, lead: 'korsan', reach: 2400 },
  { code: 'DGA', ground: 'INDIAN', ground_name: 'Indian Ocean', ground_ko: '인도양', ships: 30, base: 5000, lead: 'galeoncete', reach: 2400 },
]
const ADJ = [['Black', '검은'], ['Red', '붉은'], ['Grey', '잿빛'], ['White', '흰'], ['Golden', '금빛'], ['Iron', '무쇠'], ['Silent', '고요한'], ['Laughing', '웃는'], ['Drowned', '물에 잠긴'], ['Hungry', '굶주린'], ['Crooked', '굽은'], ['Lucky', '운 좋은']]
const NOUN = [['Gull', '갈매기'], ['Shark', '상어'], ['Lantern', '등불'], ['Anchor', '닻'], ['Squall', '돌풍'], ['Heron', '왜가리'], ['Cutlass', '칼'], ['Tide', '밀물'], ['Albatross', '신천옹'], ['Reef', '암초'], ['Marlin', '청새치'], ['Wake', '물결']]
const ROMAN = ['I', 'II', 'III']
export function roster() {
  const rows = []; let k = 0
  for (const h of HUBS) {
    const blocks = h.ships / 10
    let ord = h.base; let house = 0
    for (let b = 0; b < blocks; b++) {
      const shared = b === 0 || (h.code === 'PTC' && b === 1)
      const fleets = [[['brigantin', 1]], [['fusta', 1]], [['brigantin', 1]], [['xebec', 1]], [['xebec', 2]], [[h.lead, 1], ['xebec', 3]]]
      let sharedName = null, sharedHouse = 0, sharedN = 0
      fleets.forEach((hulls, i) => {
        const inShared = shared && i >= 4
        let name
        if (inShared && sharedName) name = sharedName
        else { const a = ADJ[k % ADJ.length], n = NOUN[(Math.floor(k / ADJ.length) * 5 + k) % NOUN.length]; k++; name = [`${a[0]} ${n[0]}`, `${a[1]} ${n[1]}`]; house++ }
        if (inShared && !sharedName) { sharedName = name; sharedHouse = house }
        const hs = inShared ? sharedHouse : house
        const suffix = inShared ? ` ${ROMAN[sharedN++]}` : ''
        rows.push({ ord: ++ord, hub: h.code, house: hs, house_name: `The ${name[0]}`, house_ko: name[1], fleet_name: `${name[0]}${suffix}`, fleet_ko: `${name[1]}${suffix}`, hulls })
      })
    }
  }
  const names = new Set(rows.map((r) => r.fleet_name)); if (names.size !== rows.length) throw new Error('fleet names collide')
  return rows
}
if (process.argv[1]?.endsWith('roster.mjs')) {
  const r = roster(); const by = {}
  for (const x of r) { by[x.hub] ??= { fleets: 0, ships: 0, houses: new Set() }; by[x.hub].fleets++; by[x.hub].ships += x.hulls.reduce((s, y) => s + y[1], 0); by[x.hub].houses.add(x.house) }
  for (const [c, v] of Object.entries(by)) console.log(c, v.fleets, 'fleets', v.ships, 'ships', v.houses.size, 'houses')
  console.log(r.length, 'fleets;', r.slice(0, 7).map((x) => `${x.ord} ${x.fleet_name}/${x.fleet_ko} h${x.house}`).join(' | '))
}
