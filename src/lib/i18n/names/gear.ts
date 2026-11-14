// THE GEAR'S KOREAN WORDS, by the served code (0425, the Gear face: owner row 345, "every word in EN and KO"). The server serves an
// item's name, its note and its rack's word in English (public.item_kinds, public.gear_racks); English prints them as served, and
// Korean prints the entry here (a code with no entry prints the served word: names/index.ts). tests/gearNames.spec.ts fails when a
// starter piece (scripts/build-gear.mjs STARTER) or a rack (data/gear.json) has no entry.

/** The starter pieces (0425), by item code. */
export const KO_GEAR: Readonly<Record<string, string>> = {
  'starter-guns': '초보 대포',
  'starter-sails': '초보 돛',
  'starter-planking': '초보 외판',
}

/** Each starter piece's note, by item code. */
export const KO_GEAR_NOTES: Readonly<Record<string, string>> = {
  'starter-guns': '부두에서 산 낡은 철포 몇 문: 해적에게 응사할 만큼만.',
  'starter-sails': '중고 범포로 만든 수수한 돛: 맨 활대보다 조금 빠릅니다.',
  'starter-planking': '선체의 가장 낡은 곳에 덧댄 얇은 가문비 판자: 조금 튼튼하고 조금 느립니다.',
}

/** The gear racks (public.gear_racks, data/gear.json), by rack code. */
export const KO_RACKS: Readonly<Record<string, string>> = {
  high: '상단',
  mid: '중단',
  low: '하단',
  refit: '개조',
  flourish: '장식',
  kit: '키트',
}
