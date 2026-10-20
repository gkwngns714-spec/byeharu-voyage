// The single import surface for the game's two languages (English, 한국어). See ./translate for how a
// string is read, ./define for how a dictionary is written, ./names for proper nouns.
export { LOCALES, getLocale, setLocale, subscribeLocale, localeTag, type Locale } from './locale'
export { defineDict, type Msg, type Plural, type Dict } from './define'
export { t, tFor, translate, translateMaybe, wordTable, type T, type TKey, type TVars } from './translate'
export { useLocale, useT } from './react'
export { DICT } from './dict'
export { koPortName, koNationName, koGoodName, koCategoryName, koCultureName, koRegionName, properName, type NameKind } from './names'
