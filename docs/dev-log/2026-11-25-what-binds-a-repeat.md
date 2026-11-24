# 2026-11-25 — what binds a repeating trade (a measurement; nothing shipped, no knob changed)

Local PGlite only, everything rolled back. `world_config.daily_cap_fraction` was set to 0.35, 0.7 and 1.0 INSIDE the rolled-back
transaction; no migration changes it. It is the owner's knob.

Harness: `scripts/ops/harness/hq-figures/measure-cap.mjs`. **It needs 0497 in the chain** (run it from `jobs-never-lose`): the jobs wait
instead of losing. Three game days of 4 h, the day turned as in `measure-rotation.mjs`. A fresh Barca, 40,000 coin.

- **Waiting Repeat:** the real fixed job, set once, run by the real tick (the better of the two near runs the server ranks first).
- **Rotation, home:** each cycle the best paying card within 30 minutes of sailing, from the server's cut cards
  (`public.cards_fit`); nothing pays where she lies: she sails home, and waits for the day's turn there.

| Allowance | Home | Waiting Repeat | paying runs a day | stopped by | Rotation, home | runs a day | stopped by |
|---|---|---|---|---|---|---|---|
| 0.35 | Lisbon | 3,328/h (quicksilver to Setubal) | 8.0 | price | 20,198/h | 22.0 | price |
| 0.35 | Amsterdam | 562/h (gunpowder to Hoorn) | 1.0 | price | 2,749/h | 9.7 | price |
| 0.35 | Venice | 2,917/h (velvet to Ancona) | 3.7 | price | 13,891/h | 8.0 | price |
| 0.35 | Genoa | 555/h (armour to Toulon) | 1.0 | price | 6,719/h | 15.0 | price |
| 0.35 | Nagasaki | 148/h (Kyoto fans to Goto) | 0.7 | price | 7,467/h | 14.7 | price |
| 0.7 | Lisbon | 3,328/h | 8.0 | price | 21,756/h | 21.0 | price |
| 0.7 | Amsterdam | 562/h | 1.0 | price | 3,351/h | 12.7 | price |
| 0.7 | Venice | 2,917/h | 3.7 | price | 12,642/h | 7.7 | price |
| 0.7 | Genoa | 555/h | 1.0 | price | 11,269/h | 20.7 | price |
| 0.7 | Nagasaki | 148/h | 0.7 | price | 8,813/h | 14.3 | price |
| 1.0 | Lisbon | 3,328/h | 8.0 | price | 23,335/h | 25.7 | price |
| 1.0 | Amsterdam | 562/h | 1.0 | price | 3,770/h | 10.0 | price |
| 1.0 | Venice | 2,917/h | 3.7 | price | 14,920/h | 8.7 | price |
| 1.0 | Genoa | 555/h | 1.0 | price | 11,239/h | 22.7 | price |
| 1.0 | Nagasaki | 148/h | 0.7 | price | 5,844/h | 15.7 | price |

"Stopped by" is what she met every time she had to wait: never the allowance, the quay's stock or her purse. "Price" for the Repeat
is her own run's quote leaving no profit (the quay's walk and the mark of her own sales). For the rotation it also counts a harbour
where no card within 30 minutes pays at all.

| Recovery (quicksilver at Setubal, emptied to half its mark, sale mark put at 0.1000) | after 4 h | 8 h | 12 h | 24 h |
|---|---|---|---|---|
| Stock gap (restock 0.15 a game day, plus the quay's own production) | 0 % | 0 % | 0 % | 0 % |
| Sale mark (`glut_half_life_hours` 15, faded at each day's turn) | 0.0831 | 0.0691 | 0.0574 | 0.0330 |

That one row's stock was whole again at the first turn (its production does it); the mark halves in 15 hours.

## What binds

- **0.35, 0.7, 1.0: the price, at every home, for both ways of working.** At 40,000 coin the waiting Repeat is the same to the coin
  at all three settings: she never reaches the allowance. Her own buying and selling move the price until the next run would not
  pay, and the sale's mark fades over 15 hours while the day turns every 4.
- The rotation gains a little from a larger allowance at some homes (Genoa 6,719 to 11,269/h) and nothing at others (Venice).
- Going home when nothing pays is what made the rotation work: 2,700 to 23,000/h here against 360 to 3,800/h when it stranded itself.

## What this world cannot show

- Other traders: merchants and cities' wants move the same quays. She trades alone here.
- The price drift inside a day, and world events.
- A richer company: at 5,000,000 coin a full hold did reach the allowance in 2 to 5 runs (`2026-11-25-per-hour-honest.md`).
- Three days only; one run of each row (the figures move a little from run to run).
- The rotation is the harness's own loop, not a server job.
