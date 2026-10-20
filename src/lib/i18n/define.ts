// THE SHAPE OF A DICTIONARY. One file per screen or domain under ./dict, each written as
//
//   export const authDict = defineDict({
//     en: { title: 'Start your company', fleets: { one: '{n} fleet', other: '{n} fleets' } },
//     ko: { title: '회사 설립', fleets: { one: '선단 {n}개', other: '선단 {n}개' } },
//   })
//
// The `ko` half is typed FROM the `en` half: a missing key, an extra key, or a plural written as a
// plain string fails `tsc` (mapped type + the excess-property check on a fresh literal). So the two
// languages cannot drift apart quietly; tests/i18n.keys.spec.ts checks the same thing at run time.

/** A plural: `one` when n === 1, else `other`. Korean usually writes both the same. */
export interface Plural {
  readonly one: string
  readonly other: string
}

export type Msg = string | Plural

export type Mirror<E> = { readonly [K in keyof E]: E[K] extends string ? string : Plural }

export interface Dict<E extends Record<string, Msg>> {
  readonly en: E
  readonly ko: Mirror<E>
}

export function defineDict<const E extends Record<string, Msg>>(d: { en: E; ko: Mirror<E> }): Dict<E> {
  return d
}
