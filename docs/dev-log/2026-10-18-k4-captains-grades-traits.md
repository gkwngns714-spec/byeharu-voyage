# 2026-10-18 — 0156: K4, a captain has a grade, a kit and a tongue — `osn-k4-captains`

`docs/SKILLS_AND_CAPTAINS.md` §4.1, §4.2, §4.9, §6.2 / §8 row K4 (D10, D14, D15 decided by default; the
owner may reverse any — each is data). **Not deployed; dark.** Migration 0156 (the coordinator's numbering: K2 = 0154, K3 = 0155,
which deploy first). Written and proven on 0153 (main b04a1d2).

- **Data, one authority** (the ships/gear pattern):
  - `data/officers.json` is now THE roster of the 105 people. It held 43; the 8 of 0015 and the 12 of
    0098 (whose `lesser_officers` in `data/npc-houses.json` stay that shipped generator's input) were
    copied in from the applied chain — and production's 63 digest equals the chain's
    (`8953cf47…`, read-only `db query --linked`, 2026-10-18) — plus 42 new captains, two per new job
    (one C or B, one A or S), 16 nations and 3 of no crown. Authored by a Fable helper, validated by the
    generator. One name is plausible rather than documented (Hajji Ghulam Husayn, Animal trader A).
  - `data/captains.json`: grades (C/B/A/S 2/4 · 3/6 · 4/8 · 5/10, floors 4 / 5.5 / 7 / 8.5), foci,
    11 effects (the four LIVE ones flagged), 25 traits, 20 languages and the language rules.
  - `scripts/build-captains.mjs` → `data/captains.generated.json`: every captain's grade (D10's floors —
    today's 63 fall 18 / 17 / 20 / 8, exactly the plan), her ten-trait kit (job at her value, up to 3 more
    of her focus, the rest, all at 60 %, order md5(code:trait)), her languages (home's; A +1, S +2: her
    nation's, then her region's, then the world's most spoken), and every harbour's language.
  - `scripts/db/world-guard.mjs` re-runs the generator (= file = database) and holds `public.officers`
    and the six catalogue tables to the data, both directions; positive control: a bent captain trait.
  - `scripts/build-inn-0073.mjs` deleted: it regenerated shipped 0073 from `data/officers.json`, which
    now holds 105 — re-running it would have edited a shipped migration (the normalise-goods landmine).
- **0156**: ten server-only tables; the four-value `specialty` CHECK becomes a FOREIGN KEY to
  `public.traits` (NOT VALID → VALIDATE; ACCESS EXCLUSIVE on `officers`, retried, held to commit — deploy
  with the clock unwound); 42 captains; `world.captain_card` (the ONE card builder),
  `public.trait_in_use` (the ONE "does this trait work today"), `public.trait_effect_words`; hunks in
  `world.inn` and `world.officers` (each guest / captain = card || the old object; `v_read` derived from
  `trait_in_use` — the same four, same order, asserted).
- **Proof** (on the cached 0152 world, PGlite): the 63 unmoved column for column; the mirror for all
  105; every fleet × the four live jobs `fleet_officer_bonus` = pre-image; every captain of today × every
  harbour in exactly the same room; `world.inn` (60 harbours) and `world.officers` serve the 63 key for
  key as before plus the card; every new captain is in some inn within 24 h; the average inn 5.00, the
  fullest 13; the two re-cuts reverse; no new entry point; 0 client write grants. Timing (notice):
  `world.inn` over 60 harbours ~207-365 → ~440-580 ms (more captains to roll and a card each; one inn
  read ≈ 7-10 ms); `world.officers` ~2 → ~30-40 ms.
- **Not here, said plainly**: no `crew_effects` cap yet (it lands with its reader, `public.crew_pct`, K5 —
  a number nothing reads would be a second truth beside `officer_bonus_cap_pct`); no cabins, seats,
  levels, homesickness, promotion or language effect (K5–K8); the merchant sheet still prints a
  merchant officer's job as the lower-cased code (merchants hold only the four live jobs; it moves to the
  card when K5 seats them).
- **Client**: the Inn tile reads `S · Navigator`; its tray prints Grade, Job, every known trait with the
  server's line (and *Not in use yet.* / *Works when combat arrives.*), and *Speaks …*; the client's
  `SPECIALTY_DOES` words are gone. The Codex Captains face: grade on the tile, Grade / Role / Job filters
  from the served values, the same card in the tray. `docs/WORDS.md`: captain, grade, job, traits,
  languages.
- **CI**: `scripts/db/world-guard.mjs` is no longer "chain machinery" in `select-specs.mjs`'s growth rule —
  it is in no snapshot's key, so an edit to it no longer forces a from-zero disposable chain (new
  positive control: da37072 → growth deferred). `tests/captains.catalogue.spec.ts` (pure) and
  `tests/captains.codex.spec.ts` (browser) are new.
- **Not the owner's** (found, not changed): the roster gives `ALBUQUERQ` and `GARCIAORTA` home `GOA`,
  which is Genoa — Old Goa is `OLD`. Moving their homes would change who is in which inn today, so it is
  left for the owner.
