# 2026-11-23 — 0486 choices at sea (dark: `sea_choices_enabled`)

`docs/design/roadmap-2026-11-23.md` slice 16 ("Choices at sea"), on HQ's board (`docs/design/hq-command-2026-11-23.md`). The owner,
2026-11-23: "i want this game to be strategical game, where all the work(activities) are done in HQ - words with graphics. choosing best
options available, finding best options." Slice 16: "a storm, a wreck or a strange sail on a long trip: a choice, with a safe default for a
player who is away. It touches the voyage's exact settle."

## What it does (lit)
- **Set at departure** (`voyage.depart`'s company arm, one hunk → `public.sea_choice_plan`, beside 0477's early sighting): a company's trip
  harbour to harbour of `sea_choices_trip_min_s` (600 real seconds) or more, with no other choice of hers open, meets one event when
  `voyage.rng(voyage, 0, 'sea_choice')` is under `sea_choices_chance` (0.35). The kind is its own draw: a **storm** (40 %), a **wreck**
  (35 %) or a **strange sail** (25 %). One row in `public.sea_choices`; it is shown from a quarter of the trip (`sea_choices_appear_at`).
- **The options** (`public.sea_choice_options`, the one table, pure). Each has its odds `p` of the good end, the coin of the good end and
  of the bad end, the expected coin `ev = p × win + (1 − p) × lose`, and whether it is the safe default. S is the stake: her cargo at cost
  at departure × 0.10, held to 200 .. 20,000. d is the highest danger her legs were frozen at (1-5), g her escort score at departure.

  | Event | Safe default | Second | Third |
  | --- | --- | --- | --- |
  | Storm | Shelter: a sure −0.25 S | Push on: p = 0.90 − 0.08 d; 0, else −0.8 S | — |
  | Wreck | Sail on: 0 | Salvage: p 0.70; +0.8 S, else −0.3 S | Dive: p 0.35; +2.5 S, else −0.5 S |
  | Strange sail | Keep away: 0 | Hail: p = 0.80 − 0.06 d; +0.6 S, else −0.6 S | Chase: p = g / (g + 30), 0.15-0.85; +1.5 S, else −0.8 S |

  So the best move depends on the waters and the guns: a storm in quiet water is worth pushing through, in danger-5 water it is not; a
  strange sail is worth chasing with guns and only hailing without. `public.sea_choice_best` serves the highest expected coin (a tie goes
  to the safe one).
- **The choice**: `cmd.sea_choose(choice, option)` (registered for signed-in companies, the `{ok: false}` envelope). Hers, open, shown,
  her voyage still sailing and before its arrival. She may change it until then. Dark `E_NOT_IN_USE`; closed `E_TOO_LATE`; not hers or not
  shown yet `E_NO_CHOICE`; a wrong option `E_BAD_ORDER`.
- **The end** (`public.sea_choice_result`): the good end when `p` is 1 or `voyage.rng(voyage, 0, 'sea_choice:' || option) < p`. It is a
  pure function of (voyage, option, world secret): no `random()`, no clock. Day 0 and the `sea_choice*` streams are not the hazard's
  (`voyage.hazard_roll` draws days 1.. on `occur`, `kind`, `magnitude`), so no day's draw moves.
- **The settle, at her arrival** (`voyage.settle`'s arrival, one hunk → `public.sea_choice_settle`, in the company-only block beside the
  levels): her option, or the safe default when she chose none. A gain is paid by the harbour she made (`public.city_pays`, `SEA_FIND`, cut
  to what its purse holds); a loss is paid to it (`public.pay_city`, `SEA_LOSS`, cut to what her purse holds). Both are money moved, not
  made (`stats_flow_words` side `moved`), so the closed economy holds. One `SEA_CHOICE` event; the row is settled at the voyage's eta.
  Never raises: a fault is a warning and the row lapses with no coin, and the arrival stands.
- **A voyage that ends without arriving** (sent home dry, diverted) leaves its choice open; her next departure marks it lapsed (no coin).
  Settled and lapsed rows older than `sea_choices_keep_days` (3) are deleted at her next departure.
- **The read** `world.sea_choices()` (STABLE, registered): dark `{on: false}`; lit, signed out or a merchant `{on: true, company: false}`;
  lit, her company `{open: [...], recent: [...]}` (the shown open choices of voyages under way; the 10 newest settled).

## What the player sees (client, lit only; dark nothing new is drawn)
- **HQ, first of all: the decision card** (`features/city/board/SeaChoiceCard.tsx`). The event's glyph and word (Storm, Wreck, Strange
  sail), her ship's whole name and the trip, and **Closes** with the clock to her arrival. One button an option: its glyph and word, its
  odds as a bar (the good end's share, green for a gain, red for a sure loss, grey for nothing; the rest of the track is the bad end), the
  coin of each end, and **Expected +470**. The best by expected coin wears a trophy and **Best**; the safe default wears a shield and
  **Safe**; her pick is ringed and wears **Chosen**. Under the options, while she has not chosen: **Default · Shelter**. One press chooses.
- **While away** (0481's card at the top of HQ) gets one line a choice settled since she last pressed OK: the event's glyph, her ship, the
  option as a chip (a helm for hers, a shield for the default; green when it came good, red when not), and the coin.
- **The arrival card**: one line, "Wreck · Dive (Default) −2,500" (`live/ArrivalChoice.tsx`), from the `SEA_CHOICE` event written in the
  same act as the voyage report. History says it too (`headline.ts`).
- The read is asked when HQ opens, when a fleet of hers acts, after a press, and once a minute while a trip of hers is under way (the
  event shows at a quarter of the trip); never on the beat (`live/useSeaChoices.ts`).
- Words, EN and KO (`hq.ts`, `codes.ts`, `feed.ts`, `history.ts`): a row in `docs/WORDS.md`.

## Measured
- **Local chain (PGlite).**
  - The self-assert: ~190 ms (dark nothing set; lit an event set, her pick settled at her arrival to the ducat, the default on a trip left
    alone, a short trip sets nothing, an ended voyage's choice lapses, the door, the read, signed out).
  - Proof 189 (5 markers), 0.7 s:
    - **The settle is unchanged:** the same voyage (Lisbon to Tórshavn, 6 sea days) settled dark, lit, and lit day by day gives
      byte-identical `voyage_events`; the choice's end is the same in one call and day by day.
    - **The odds are honest:** over 2,000 voyages every option's good ends are within 0.04 of its served odds; 34.5 % met an event
      (0.35); kinds storm 788, wreck 730, sail 482 of 2,000.
    - **A loss larger than her purse** takes what she has (purse 100, loss 1,250: −100 moved, −1,250 on the record).
    - **Too late:** a pick at her arrival is refused `E_TOO_LATE`; before the event is shown, `E_NO_CHOICE`.
    - **Cost:** a lit departure (`voyage.depart` whole) 19 ms; a lit arrival (`voyage.settle` whole, 6 days, the settle included) 17 ms;
      a dark arrival's probe 0.01 ms; the read 0.16 ms.
- **Prod (`before-0486`, the one read, 2026-11-23 13:18 UTC).**
  - The gate, in the same statement: beat mean 128 ms over 5 minutes (296 beats), 767 MB, 0 sessions waiting on the disk.
  - Head 20260818000485; no `sea_choices_*` knob, table, function or money word; each hunk's anchor once in prod's live body and its new
    text nowhere; the three bodies' md5 equal the chain's at 0485 (`voyage.depart` a3325126, `voyage.settle` d3536479,
    `client_rpc_entry_points` 9a8d24c3).
  - The companies' trips: 19 companies; 7 voyages ended in the last 24 hours or sailing now, all 7 harbour to harbour and all 7 of
    600 s or more (median 3,093 s, p90 3,317 s). Lit, that is about 0.35 × 7 ≈ 2-3 events a day today.
  - The purses and the closed economy are lit (`city_treasury_enabled`, `economy_closed` true): a gain is paid by the city's purse.

## Load
- **One new table** (`public.sea_choices`): at most one open row a company; settled rows kept 3 days and deleted at her next departure;
  a row goes with its voyage. A few hundred rows at the very most.
- **No cron job, no step on the arrivals beat.** Dark: one knob read at a company's departure and at a company's arrival (a merchant's
  arrival never reaches the hunk). Lit: one insert at an eligible departure; one primary-key probe at a company's arrival; a settle writes
  the row, one event, one ledger row and one treasury row. At prod's rate today: about 3 settles a day.

## Decided by default (the owner may reverse)
- **Money only.** The ends move coin through the city purse, not goods or time: a delay would move the voyage's eta, and goods would
  change a hold mid-voyage; both touch the exact settle. Coin settles at the arrival and leaves every day's draw as it was.
- **The deadline is her arrival.** The event shows at a quarter of the trip; she may choose (and change her mind) until she makes port;
  then her pick, or the safe default, is settled in the arrival itself. No tick is needed.
- **The safe defaults:** Shelter (a small sure loss) for a storm; Sail on and Keep away (nothing) for a wreck and a strange sail.
- **The table, the stake and the odds** as above; the chance 0.35 a long trip, 600 real seconds or more; one open choice a company.
- **A gain is cut to the city's purse, a loss to hers** (the full figure is kept on the record).
- **A voyage that ends without arriving** lapses its choice with no coin.

## Prod checks
- Before: `scripts/ops/harness/sea-choices/before-0486.sql` (done, the one read).
- After (and 30 minutes after lighting): `scripts/ops/harness/sea-choices/after-0486.sql`.
