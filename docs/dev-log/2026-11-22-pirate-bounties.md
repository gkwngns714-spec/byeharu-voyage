# 2026-11-22: Bounties on named pirates (migration 0471, dark)

The owner, 2026-11-22: "make this game a proper game". Plan P2, the last item of `docs/design/playable-2026-11-22.md`: "bounties on named
pirates". **It ships DARK**: the switch `pirate_bounties_enabled` is false, so the migration changes nothing for live play. Lighting it is
the owner's call.

## What a player sees, lit

- **Rank › Bounties** (a new face, offered only while the server says it is on): every named pirate still free, by her bounty now:
  "Black Ruy of Port Royal · 34,500", under it "Hunts Caribbean Sea · 6 ships taken · Posted at Kingston". Her name rings her on the map.
  Beside the list, the last bounties collected ("Casa Lobo · +41,000") and the rule and the rates in one line.
- **The map**: a named pirate's sheet (tap her hull) is titled with her name and opens with her bounty, the ships she took (the last one
  named) and the harbour that posts it.
- **The fight**: the battle card and the battle screen end with "Bounty claimed +17,000" and her name when this fight paid one; the
  arrival card comes up with the same line. The money is a ledger row, kind PIRATE_BOUNTY ("Pirate bounty" / "해적 현상금").
- Korean: her name is composed from three served parts in each language ("포트로열의 검은 루이"); no English inside a Korean line.

## The design (one authority per concept)

| Concept | Authority |
|---|---|
| Who a named pirate is | a row of `public.pirate_bounties` over one of the Brethren's ships (`public.pirate_ships`, at work). Her ship, cruise, raids, rebirth: unchanged |
| The fight | the one battle, `public.battle_resolve`: kind RAID (she struck) or ATTACK (a company struck her). Engine unchanged |
| "Beaten" | `public.bounty_beaten(kind, fight, pirate)`. RAID: DRIVEN_OFF, or she broke off or ran, and the company did not run, slip or stand off. ATTACK: boarded or paid off (0340's regard rule). Either: every hull of hers at 0 |
| "A ship taken" | a RAID of hers ending PLUNDERED or RANSOM, on anybody's ship |
| The size | `public.bounty_value(named_at, taken, now)` |
| The money | `public.city_pays` from the posting harbour to the company, kind PIRATE_BOUNTY (moved). The poster is `public.bounty_poster`: the nearest harbour with a purse that the pirates do not hold, one holding the whole cap first |
| Writes | `public.bounty_close` (takes, claims; called by battle_resolve) and `public.bounty_step` (names, lapses, trims; called by tick_pirates). Neither raises |
| The read | `world.pirate_bounties()`, stable, registered. Dark `{"on": false}` |

Hunks (each once, each reverses): `battle_resolve` 2 (the ATTACK and RAID arms add the close's answer to the spoils, so the attacker's
report and `battles.result` carry it), `raid_close` 1 (the raided company's report carries it), `tick_pirates` 1 (the step, lit, after the
strikes), `client_rpc_entry_points` 1 (at its `pirate_ship_card` line; 0469 cuts it at `houses_week`, 0467 at `land_repeat`). 0468, 0469 and
0470 touch none of the other three bodies.

## The rates and the sizes (decided by default; every one a knob)

| Knob | Value | Meaning |
|---|---|---|
| `pirate_bounties_enabled` | **false** | the switch (lit needs the pirates lit too: `public.pirates_on`) |
| `bounty_named` | 4 | named pirates standing at once |
| `bounty_base` | 15,000 | a bounty when she is named |
| `bounty_per_hour` | 500 | each whole real hour she is free |
| `bounty_per_ship` | 2,000 | each ship she takes |
| `bounty_cap` | 60,000 | never more |
| `bounty_respawn_hours` | 6 | a beaten (or lapsed) slot is named again after this |
| `bounty_keep_days` | 14 | a closed bounty stays on the board this long |

**Economy.** The play-test (`content-plan-2026-11.md` 5.1): a trip pays 800 to 13,400, about 4,700 on average. A fresh bounty (15,000) is
one good trip; production's pace (read 2026-11-22: 2,828 raids in 24 h, 930 won by the pirates over 116 hunting, so a pirate takes about
8 ships a day) puts a day-old named pirate near 15,000 + 12,000 + 16,000 = 43,000, three good trips, and at the cap of 60,000 within two
days. The worst case out of the harbours' purses is 4 x 60,000 every 6 hours = 960,000 a day, moved (not made) into companies. Nothing is
paid while the city purses are dark (the pirates are dark then too).

Who can collect today: production's 24 h had 0 raids on a company's ship (`raid_companies_enabled` is lit, but no company at sea stood at
Master or over in reach). An ATTACK on her (attacks are lit) is the other road.

## Load

- **Dark: 0 rows a minute.** No table rows, no cron, no index use beyond one knob read per closed battle.
- **Lit: about 0.05 rows a minute** (under 0.1 at the worst): 4 names in the first 4 minutes, then at most 16 a day; ~32 take updates a
  day (4 named pirates x ~8); a claim is one update + one ledger row + one treasury_flows row; lapse/trim at most 16 a day. Reads: one
  index probe per closed battle (~2 a minute), one ~16-row scan a pirates run, the read on Rank or a pirate sheet (~250 rows at most).
- No new job, no reschedule. `-- budget:` and `-- retention:` lines in the file (`tests/db.budget.spec.ts`).

## Measured (local cached chain at 0467 + 0471)

- Migration self-assert: ok in 60-110 ms (budget 30 s). Five hunks once each and reversing; no other function moved; grants, volatility,
  definer, search path, owner unmoved; the knobs; PIRATE_BOUNTY moved; the read registered for authenticated alone, stable; the table and
  every writer unreachable by a client. Probe (rolled back): the size (15,000 / 20,000 at 10 h / 21,500 at 1 h + 3 ships / the cap); the
  beaten rule on 14 fight shapes; dark nothing named, taken, claimed or served; lit a pirate named with a poster the pirates do not hold, a
  won raid on her record, a company's win paying 17,000 once from the poster to the company (the poster's PIRATE_BOUNTY flow and the
  company's ledger row), the slot held to the respawn. On production the probe never lays a real pirate up and never writes a live purse.
- **Proof 174**: 8/8 (BT_DARK, BT_NAME, BT_RAID, BT_SUNK, BT_TAKE, BT_ATTACK, BT_RESPAWN, BT_READ), 0.3 s. A real RAID through
  `tick_pirates` and `battle_resolve` (claimed exactly when `bounty_beaten` says so; a won raid on her record), a sinking through
  `battle_resolve` paying 19,000 (15,000 + 2 ships) and said on the company's BATTLE_REPORT and in `battles.result`, the ATTACK arm
  (driven off: nothing; boarded after 3 h: 16,500), the respawn (not at 5 h; at 6 h 1 min another pirate, never the one beaten), the read.
- Bodies after 0471 on the local chain (md5): `battle_resolve` 2ee4d08474e8f9befb383c58af0e2d9c, `raid_close` 906f96baad50185e08f0c7b1a497e20c,
  `tick_pirates` 8591e22b55f7285a2ad412070235e3da (`client_rpc_entry_points` differs on prod by 0469's own hunk).
- Production before (`before-0471.sql`, 2026-11-22, head 0467): every OLD text once, the marker 0; no knob, word or table; md5
  `battle_resolve` 8366bc89ea0dea12204eefeac0091826, `raid_close` 0b6217fe3dd206d30396a42b5c70ba3f, `tick_pirates`
  3b249d50c761392f2e35e68b871cf32c, registry 004a5decd1a3f3b943a67dc004ae53b0; raids 24 h DRIVEN_OFF 888, EVADED 1,010, PLUNDERED 702,
  RANSOM 228; 120 pirates at work, 116 hunting; the poorest non-pirate harbour's surplus -116,748 (hence the poster's "holds the cap first").

## Harness

`scripts/ops/harness/pirate-bounties/`: `before-0471.sql` (the hunks once, the md5s, no knob yet, the raids' measure), `after-0471.sql`
(the new texts once, the knobs, the word, the table empty dark, the read registered and stable; lit, the named, claimed, paid and taken).
Both one read-only statement, catalog and stable functions only.

## After lighting (the owner's switch)

30-minute after-check: `scripts/ops/harness/raid/after-check.sh <start> <end>` (beat, jobs, stuck raids: the claim rides the battle's
close) and `after-0471.sql` (4 named within minutes; claims and paid). Rollback: `pirate_bounties_enabled` false (nothing named, taken,
claimed or served; rows lie inert).

## Decided by default (the owner may reverse any)

1. Dark first; the switch also needs the pirates lit.
2. Only a company's win ends a named pirate; a merchant house or the navy beating her does not (she is reborn at home, still named).
3. "The pirate breaks off" counts as beaten (the order's words); her raid that the company fled or slipped from does not.
4. The bounty is paid by one harbour near her home, from its purse (moved); a purse short of it pays what it holds above its reserve.
5. Sizes as the table; at most 4 at once; a beaten slot waits 6 hours; a pirate just beaten is not named again within a day.
6. The record counts the raids she won in the one battle (0427's); a voyage day's anonymous PIRATES roll is not hers.
7. No news row (dark); a claim is said on the fight's own report, the arrival card and the Rank board.
