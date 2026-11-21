# 2026-11-22: Pirates raid companies too (migration 0464, dark)

The owner, 2026-11-22: "make this game a proper game". That settles the open decision in `docs/design/content-plan-2026-11.md` 5.6, row 1.
Built as designed there (5.3 item 1, 5.4 row A). **It ships DARK**: the switch `raid_companies_enabled` is false, so the migration changes
nothing for live play. Lighting it is the owner's call.

## What was built

- **One body, `public.raid_target`, two hunks** (each once, each reverses). The live body is 0427's with 0432's two hunks; nothing after 0432 touches it.
  - Hunk 1 (its declarations): reads the three knobs.
  - Hunk 2 (its `where` and `order by`): dark, 0432's order to the row (the world's merchants first, then a company's ship, nearest within each).
    Lit, the nearest ship in reach wins whoever owns her; a company whose title is under `raid_company_title_min` is passed over; a company's
    miles are multiplied by `raid_company_weight` for the order only (reach is unchanged).
- **Three knobs (new):**

  | Knob | Value | What it does |
  |---|---|---|
  | `raid_companies_enabled` | **false** | The switch. false = today's rule (0432). true = nearest wins. |
  | `raid_company_title_min` | 3 (Master) | Lit: a company under this title is passed over (the beginner's peace). 1 = nobody is passed over. |
  | `raid_company_weight` | 1 | Lit: a company's miles x this. 2 = looked at as if twice as far (rarer); 0.5 = likelier. |

- **No client change.** A company's ship set upon already gets the battle card, Fight / Run / Pay, her standing order and her `BATTLE_REPORT`
  (0427, 0439, 0453). The arrival card's raid line (`fight.raidLine`) and the Raid words exist in EN and KO.
- **No news row** (`-- news: none`): nothing changes until the switch is lit.

## Measured (local cached chain at 0462 + 0464)

- Migration self-assert: ok in **79 ms** (budget 30 s). Two hunks once each and reversing; no other function moved; grants, volatility,
  definer, search path, owner of `raid_target` unmoved; knobs as above. Dark is today: up to 4 hunting pirates of the world choose the same
  ship after the hunks as before (the local world has none hunting; prod has). The probe (rolled back): a pirate and an Apprentice company at
  one point in the South Pacific: dark, the company is chosen (no merchant there, as today); lit, she is passed over; lit with title 1, chosen.
- **Proof 167**: 6/6 (RC_KNOBS, RC_DARK, RC_PEACE, RC_NEAREST, RC_WEIGHT, RC_STRIKE). Scene: a pirate at her haunt, the world's merchant 60 nm
  north, a new company's ship 15 nm north. Dark: the merchant. Lit: the Apprentice is passed over (the merchant; with no merchant, nobody).
  Lit, title 1: the company. Weight 3 (45 < 60): the company; weight 5 (75 > 60): the merchant. Lit, `public.tick_pirates` opens the RAID on
  the company's ship, not the merchant.
- Proofs 128 and 133 assert 0432's order with the switch at its default (false); they are unchanged and still hold.
- `raid_target` md5 after 0464 (local): `b360c71247f1402f6db88f1381125237` (in `after-0464.sql`).
- Prod: **not read by me** (one reader at a time). The before-check is `scripts/ops/harness/raid-companies/before-0464.sql` for the lead. It also
  measures the "before": raids in 48 h, raids on a company's ship (0 of 2,339 on 2026-11-16), company hours at sea, companies at or over Master.

## Decided by default (the owner may reverse any)

1. **Dark first.** The switch ships false; the owner lights it (`raid_companies_enabled` true).
2. **Nearest wins** when lit (the design's 5.6), the same rule for a merchant, a crown cargo ship and a company.
3. **The beginner's peace at Master (title 3)**: `public.title_level`, the lower of Trading and Exploration. A title that reads null is not
   passed over (only a merchant's reads null).
4. **Weight 1.** It changes only the order among ships in reach, never the reach.
5. **Not changed:** how many raids the pirates open (at most 2 a minute), the fight, the peace after a fight (5 min), ransom size, insurance,
   Evasion; a voyage day's raid (`public.fight_sides`, 0357) keeps its own rule (the design's "Honest limits", second point).

## Load

- **Dark: 0 rows a minute.** No table, job, index or cron.
- **Lit: about 0 extra rows a minute.** The pirates open no more raids than today (at most `pirate_strikes_per_run` 2 a minute; about 49 an hour
  on prod). A raid that lands on a company instead of a merchant writes, beyond a merchant's raid, her `BATTLE_REPORT` event and at most
  2 `level_book` + 1 `level_xp` rows: **at most 4 extra rows a raid on a company**. By the design's division (one raid in about 18 hours at sea
  per ship) and prod's handful of companies at sea, that is well under 1 extra row a minute.
- CPU, lit: `public.title_level` once per company in a pirate's sieve (at most 8 pirates asked a minute, 19 companies on prod).

## After lighting (the owner's switch)

30-minute after-check: `scripts/ops/harness/raid/after-check.sh <start> <end>` (beat, jobs, stuck raids), and `after-0464.sql` for raids on
companies in the hour and that none was under Master. Rollback: `raid_companies_enabled` false (0432's order, to the row).
