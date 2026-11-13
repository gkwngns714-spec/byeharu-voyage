// THE SKILLS' KOREAN NAMES, by the served code (`world.skills().skills[].code`, data/skills.json). 2026-11-14, owner row 318:
// a skill's tile printed the served English name under Korean ("Haggling" in the ship block, every tile of the Academy).
// English prints the served name; a code with no entry here prints the served name too (names/index.ts).
//
// The hull skills are one per country and size (PRT_SMALL … KOR_CAPITAL): the two words are written once each and joined,
// so a country or a size is never spelled two ways.

const COUNTRY: Readonly<Record<string, string>> = {
  PRT: '포르투갈',
  ESP: '에스파냐',
  NLD: '네덜란드',
  ENG: '잉글랜드',
  FRA: '프랑스',
  ITA: '이탈리아',
  OTT: '오스만',
  IND: '인도',
  CHN: '중국',
  JPN: '일본',
  KOR: '조선',
}

const SIZE: Readonly<Record<string, string>> = {
  SMALL: '소형선',
  LIGHT: '경량선',
  MEDIUM: '중형선',
  HEAVY: '대형선',
  CAPITAL: '주력선',
}

const HULL_SKILLS: Record<string, string> = {}
for (const [c, country] of Object.entries(COUNTRY)) for (const [s, size] of Object.entries(SIZE)) HULL_SKILLS[`${c}_${s}`] = `${country} ${size}`

export const KO_SKILLS: Readonly<Record<string, string>> = {
  ...HULL_SKILLS,
  MERCHANT_SHIPS: '상선',
  SHIPS_OF_WAR: '군함',
  EXPLORERS: '탐험선',
  ESCORT_SUPPORT: '호위와 지원',
  ARMED_MERCHANT: '무장 상선',
  PRIVATEERS: '사략선',
  SURVEY_SHIPS: '측량선',
  CONVOY_ESCORTS: '선단 호위함',
  FAMOUS_SHIPS: '이름난 배',
  SEAMANSHIP: '항해술',
  HULL_UPKEEP: '선체 관리',
  DAMAGE_CONTROL: '피해 수습',
  DECK_MANAGEMENT: '갑판 관리',
  HANDLING_SPEC: '조선술 전문',
  CREW_DRILL: '선원 훈련',
  PROVISIONING: '보급',
  NAVIGATION: '항법',
  RIGGING: '삭구',
  LOOKOUTS: '망보기',
  INSTRUMENTS: '항해 기구',
  RIGGING_SPEC: '삭구 전문',
  INSTRUMENT_SPEC: '기구 전문',
  CELESTIAL_NAV: '천문 항법',
  WEATHER_LORE: '날씨 읽기',
  LIGHT_AIR: '미풍 항해',
  ACCOUNTING: '회계',
  HAGGLING: '흥정',
  CARGO_STOWAGE: '화물 적재',
  STOWAGE_SPEC: '적재 전문',
  WHOLESALE: '도매',
  NEGOTIATION: '협상',
  FACTORAGE: '중개 대리',
  PURSERSHIP: '사무장 일',
  BROKERAGE: '중개',
  GUNNERY: '포술',
  GUN_LAYING: '조준',
  LONG_GUNS: '장포',
  SHORT_GUNS: '단포',
  BOARDING: '접현전',
  GUN_DRILL: '포 훈련',
  GUNNERY_SPEC: '포술 전문',
  COMMAND: '지휘',
  FLEET_COMMAND: '선단 지휘',
  LEADERSHIP: '통솔',
  HOSPITALITY: '접대',
  SHIPWRIGHT: '조선',
  REFITTING: '개장',
  AUGMENTATION: '증강',
  SHIPWRIGHT_SPEC: '조선 전문',
  RECRUITING: '모집',
  ETIQUETTE: '예법',
  PATRONAGE: '후원',
}
