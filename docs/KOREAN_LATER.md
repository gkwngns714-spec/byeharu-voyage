# Korean wording: paused (owner, 2026-11-24)

"You don't need to do korean wording right now, we can do this later after once everything is built."

Builders write ENGLISH labels only. Existing Korean stays exactly as it is, so a Korean player keeps everything translated today.

## What was paused

- **The type gate.** `src/lib/i18n/define.ts`: a `ko` entry is optional per key (`Mirror` is `?:`). An extra Korean key with no English one is still a `tsc` error, and a Korean entry that exists must match the plural shape.
- **The fallback.** `translate()` in `src/lib/i18n/translate.ts` reads the English entry when a key has no Korean one. (`translateMaybe`, for served codes, still returns null, and its caller prints the server's English.)
- **The key check.** `tests/i18n.keys.spec.ts`: a missing Korean key is allowed. Every check on Korean entries that exist stays (not empty, placeholders, plural on both sides, no Korean key without an English one). One test proves the fallback.
- **The Korean browser legs and "every X has a Korean word" checks.** All behind ONE file, `tests/korean.paused.ts`:
  - `KOREAN_PAUSED = true` makes `LOCALES` hold only `en-US` and `LANGS` only `en`; the specs loop over those, so the `ko-KR` legs do not exist (not skipped: `playwright test --list` and the run agree, so the CI floors hold).
  - `koreanDescribe` / `koreanTest` register nothing while paused. They wrap the Korean-only blocks: `tests/i18n.ko.spec.ts` (the whole file), the "in Korean" blocks in `city.phone`, `city.nocity`, `captains.sheet`, `crown.ships`, `good.class`, `map.autoroute`, `second.ship`, `yard.order`, `yard.plan`, `yard.sources`, and the completeness checks `gearNames`, `lit.screens` (skill names), `ships.more` (hull names).
  - Specs with a per-run table (`battle.live`, `captains.codex`, `fight.log.page`, `map.seasFilter`, `route.inReach`, `sell.profit`, `yard.order`) filter it through `LOCALES` / `LANGS`.
- **Not touched:** pure-Node specs that pin an existing Korean string (`news.kinds`, `shortWords.server`, `bounty.words` ...). They still pass and still guard what is translated.

## Bring it back

1. Find the gaps: `node scripts/i18n-missing-korean.mjs` lists every English key with no Korean entry (`--count` for the number). Names data (`src/lib/i18n/names/*`: hulls, gear, skills) is checked by the paused specs below.
2. Write the Korean entries, in `src/lib/i18n/dict/*` and `src/lib/i18n/names/*`.
3. Set `KOREAN_PAUSED = false` in `tests/korean.paused.ts`. Every Korean leg, sweep and completeness check is registered again. Run them and fix what they find (a Korean line that no longer fits, an English word on a Korean screen).
4. If you want Korean to be required again, make `Mirror` in `define.ts` non-optional (drop the `?`) and restore the "same keys in English and Korean" test.
5. Restore the "EN and KO" wording of the Words line in `CLAUDE.md`.
