// NATIONS, REGIONS, GOOD CATEGORIES AND THE KOREAN HULLS IN KOREAN. Nations, regions and categories
// are keyed by their served CODE; hull classes by their served NAME (the historical form the
// server prints). A code or name with no entry prints what the server served.

export const KO_NATIONS: Readonly<Record<string, string>> = {
  PRT: '포르투갈', ESP: '카스티야-에스파냐', ENG: '잉글랜드', FRA: '프랑스', NLD: '네덜란드',
  VEN: '베네치아', GEN: '제노바', OTT: '오스만 제국', HAN: '한자 동맹', DNK: '덴마크-노르웨이',
  SWE: '스웨덴', POL: '폴란드-리투아니아', RUS: '모스크바 대공국', MAR: '모로코', PER: '사파비 페르시아',
  MUG: '무굴 제국', GUJ: '구자라트 술탄국', MLB: '말라바르', MNG: '명', JOS: '조선', JPN: '일본',
  AYU: '아유타야', BAN: '반텐',
}

export const KO_REGIONS: Readonly<Record<string, string>> = {
  ADR: '아드리아해·이오니아해', AEG: '에게해·아나톨리아·흑해', ARA: '아라비아·페르시아만',
  ATL: '대서양 제도', BAL: '발트해·한자', BRI: '브리튼 제도', CAR: '카리브해·스페인령 본토',
  CHI: '중국 연안', EAS: '동아프리카·아프리카의 뿔', EST: '동인도·실론·버마', FRA: '프랑스·저지대',
  IBE: '이베리아', JAP: '일본·류큐', KOR: '조선', LEV: '레반트·이집트', MAG: '마그레브',
  NOR: '북아메리카 대서양 연안', OCE: '오세아니아·태평양', PAC: '태평양 아메리카', SCA: '스칸디나비아·북극',
  SOU: '동남아시아', STH: '남아메리카 대서양 연안', WES: '서지중해', WIA: '서인도', WST: '서아프리카',
}

export const KO_CATEGORIES: Readonly<Record<string, string>> = {
  spice: '향신료', cloth: '직물', metal: '금속', guns: '화기', crafts: '공예품', weapons: '무기',
  gems: '보석', medicine: '약재', books: '서적', art: '미술품', animals: '동물', grain: '곡물',
  food: '식료품', drink: '주류', tobacco: '담배', dye: '염료', 'ship-supplies': '선박 자재',
}

export const KO_HULLS: Readonly<Record<string, string>> = {
  Hyeopseon: '협선', Sangseon: '상선', Byeongseon: '병선', Jounseon: '조운선', Panokseon: '판옥선',
  'Dae-panokseon': '대판옥선', Tamangseon: '탐망선', Bangpaeseon: '방패선', 'Geobukseon (turtle ship)': '거북선',
}
