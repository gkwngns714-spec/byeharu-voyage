import { test } from '@playwright/test'

// KOREAN IS PAUSED (owner 2026-11-24: "you don't need to do korean wording right now, we can do this
// later after once everything is built"). THE ONE FLAG: set it to `false` and every Korean browser
// leg, locale loop and Korean-wording sweep comes back. While it is `true` those tests are NOT
// REGISTERED (they do not exist in `playwright test --list`; no skip, so the CI floors still hold).
// What was paused and how to list the keys that need Korean: docs/KOREAN_LATER.md.
export const KOREAN_PAUSED = true

/** The browser locales a spec loops over. */
export const LOCALES: readonly ('en-US' | 'ko-KR')[] = KOREAN_PAUSED ? ['en-US'] : ['en-US', 'ko-KR']
/** The same, as the game's own language codes. */
export const LANGS: readonly ('en' | 'ko')[] = KOREAN_PAUSED ? ['en'] : ['en', 'ko']
/** For a block that exists only in Korean: `for (const locale of KO_ONLY) { ... }`. Empty while paused. */
export const KO_ONLY: readonly 'ko-KR'[] = KOREAN_PAUSED ? [] : ['ko-KR']

/** `test.describe` / `test` for a block that exists only in Korean: not registered while paused (no skip, so `--list` and the run agree). */
export const koreanDescribe = (KOREAN_PAUSED ? () => undefined : test.describe) as typeof test.describe
export const koreanTest = (KOREAN_PAUSED ? () => undefined : test) as typeof test
