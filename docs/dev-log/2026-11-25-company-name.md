# 2026-11-25 — `company-name`: 0503 (no switch), proof 205

Slice A1 of `docs/design/owner-spec-plan-2026-11-25.md`, from the owner's words in `docs/design/owner-spec-2026-11-25.md`:

> COMPANY NAME – you can change it. When creating the account for the first time, it will ask you to assign a company name. It
> should not overlap with any other names (countries, trade goods, and with other player info, no special characters). After that
> you can change your name again for free (1st time), but later if you want to, you will have to pay (real money currency – not
> decided yet).

Branch `company-name`, off `origin/stack-jobs-never-lose` with `origin/main` merged. Nothing touched production and no prod read
was run by the builder. No knob is added or moved. No payment code of any kind is in the slice.

## What it does

- **One rule**, `public.company_name_refusal(name, player)`, read by founding (`cmd.found_house`, one hunk) and by renaming, and by
  nothing else. A name is 3 to 24 characters; letters of any script and the digits 0-9, with one space between words; no special
  characters. In any case of its letters it may not be a country's name (`public.nations`, and the countries the harbours lie
  in), a place's name (`public.ports`), a trade good's name or code (`public.goods`), or another company's name.
- **The rename**, `cmd.rename_company(name)`: the caller's own company. Her own name again changes and counts nothing. The first
  rename is free. The next is refused in plain words, `E_RENAME_PAID`: "Your free rename is used. Another rename is not available
  yet." A rename writes the name, adds one to `players.renames`, and writes one event `COMPANY_RENAMED {from, to}`. No coin moves.
- **`world.player`** serves `renames` and `rename_free` beside the name (one hunk).
- **Existing names stay.** No name is rewritten; a name the rule would refuse today is kept and served as it is, and its company
  still has her one free rename.
- **Client:** the founding step sends the name trimmed and composed (NFC), stops the field at 24 characters and prints the rule in
  one line; the server's own sentence is printed on a refusal, as before. Profile has a press beside the company's name:
  "Rename (1 free)", then "Rename". It opens a page over Profile (nothing behind it moves). Once the free rename is used the page
  prints the plain sentence and offers no field. History reads "Company renamed {to}."

## Decided by default (the owner may reverse each)

1. **Length 3 to 24 characters**, as the table has always asked.
2. **"Countries" are both lists the game has**: the 24 powers (`public.nations.name`) and the 100 countries the harbours lie in
   (`public.ports.country`).
3. **Place names are refused too** (all 268 rows of `public.ports`, cities and places at sea). The owner named countries and trade
   goods; the plan's own probe list has "LISBON". A company called Lisbon would be read as the city.
4. **A good is refused by its name and by its code** with hyphens read as spaces ("Manila Hemp" and "abaca").
5. **Case does not make a name new**: "LISBON", "lisbon" and "Lisbon" are one name. A company may write her own name in another
   case (it uses her free rename).
6. **Letters are a list of code-point ranges**, so every server answers the same whatever its locale: Latin with accents, Greek,
   Cyrillic, Armenian, Hebrew, Arabic, the Indian scripts, Thai, Georgian, Hangul, kana, Chinese characters. The blank Hangul fillers
   are not letters. Digits are 0-9 only.
   A script not on the list is refused as special characters until it is added.
7. **Fleet names and captains' names are not compared** ("other player info" is read as other companies' names).
8. **The merchants' houses** (rows of `public.players` no account holds) count as companies for "taken", are never renamed, and
   are outside the new index.
9. **The second rename is refused whatever the name**, before the name is judged, so she is not sent to mend a name she cannot use.
10. **News:** one Update row, in English in both languages (Korean later).

## Not done, said plainly

- **No payment.** No price, no purchase, no coin. `public.company_rename_free(renames)` is the one place the free count is
  written; the owner's decision goes there.
- **Look-alike letters are not caught** (a Cyrillic "а" for a Latin "a"). Not asked; it needs its own table.
- **The case-blind index** (`players_company_name_lower_key`, players' companies only) is built only if no two such names are
  equal but for case when the file runs. Otherwise the file says so in its notice and the rule stands in the function alone: two
  presses at the same instant could then pass two names equal but for case. Whether production has such a pair was not read:
  `scripts/ops/harness/company-name/before-0503.sql` prints `case_twins`.

## Measured (local: PGlite, the chain to 0498 then 0503; both engines' variants)

- 0503 applies in about 150 ms; its notice: three hunks once and reversing, four functions, no other function moved, no knob, the
  index built; the probe (rolled back) tried country Ayutthaya, place Acapulco, good Abalone.
- Taken over by a second builder: the letters are written as code-point escapes (no raw character a tool could re-encode), the blank
  Hangul fillers are refused, the probe suffix is one no company name ends in, and the proof is 205 (206 is chart-fog's). Re-run
  after that: 0503, proof 205, proofs 45, 69, 91, and the two specs with rpc.surface, db.budget, news.lint and i18n.
- The self-assert reads no live company, market or dice: its company names are made free first (a suffix no company holds) and
  its country, place and good are the first single-word names of the static tables. No assertion depends on the clock.
- Four mutants, each refused by the file itself: `*` let into the letters; two free renames; "taken" compared by exact case; a
  good's code not compared.
- Proof 205: seven markers green. Proofs 29, 45, 57 and 68 (which found companies or rename fleets) green on the new head.
- `tests/rpc.companyName.spec.ts` (3) and `tests/companyName.spec.ts` (4: Profile at 390, 320 and 1440 px, the founding field)
  green on a served build; `profile.design`, `gates.design`, `names.whole`, `words`, `rpc.surface`, `news.lint`, `db.budget`,
  `i18n.keys` green. `tsc`, `eslint`, `vite build` clean.
- The press is 44 px high at every width; at 320 px it stands under the name so the name is never cut.

## Not verified

- A real Postgres (CI's `disposable-chain`) and production: the file was applied only on PGlite here.
- The full proof run and the full Acceptance suite: CI's.
- Production's names: how many live names the rule would refuse today (they stay), and whether two differ only by case.
  `after-0503.sql` prints `old_names_the_rule_refuses`.
- The founding screen's refusal on the glass: the local world founds its own house, so the door's refusals are proven through
  the server (`rpc.companyName`, proof 205) and the screen's field and hint in the gates gallery.

## Prod checks

Before: `scripts/ops/harness/company-name/before-0503.sql` (expects head 0502, nothing of 0503 there; prints `case_twins`).
After: `scripts/ops/harness/company-name/after-0503.sql` (expects four functions, the door for signed-in players alone,
`over_free` 0 always). Both are one read-only statement and call no function that writes.

## Rollback (forward, owner only)

A migration reversing the three hunks (the OLD texts are in the file verbatim), dropping the four functions and the index. The
column may stay. Names already changed stay changed.
