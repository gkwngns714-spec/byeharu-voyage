# HISTORY — byeharu-voyage

A chronological record of how this project came to exist and what was actually established at each
step. `DEV_LOG.md` holds decisions; this holds the sequence. Newest section at the bottom, so it reads
forwards.

---

## Day 0 — 2026-08-18

The whole of the following happened in one working session, from an empty directory to a proven server.

### The request

The owner, on the predecessor game `byeharu`:

> "since the combat system, visually and code-wise are not working properly. Therefore i want this game
> to turn into a wording, strategical game, where most of the game played on tabs and commands made on
> a separate tab, and i can follow where my fleets are through map - only visually see where it is
> going and where it is. It is going to be a new game, we will use byeharu core to make a new byeharu.
> This time you will have to make a world map, add real countries, cities, especially harbour - sea
> related cities. It is going to be uncharted island origin (mobile game), similar, but will have
> multiple ships (fleet) to be controlled, invest in cities, rank, etc."

("uncharted island origin" is **Uncharted Waters Origin** / 대항해시대 오리진.)

### The commits, in order

| Commit | What it established |
|---|---|
| `a9001d9` | Empty skeleton. LF-only checkout from the very first commit, before any SQL existed. |
| `7b15b8a` | Decisions D1–D5: new repo not a branch; LF-only; combat designed out; map is an output device. |
| `0a3ca0a` | Toolchain and 8-tab shell carried from byeharu core. Build and lint green. |
| `a099e3f` | The core-reuse audit, the game design, the research — plus D6 and D7, both proven not assumed. |
| `3782e51` | First world dataset — 280 ports assembled by hand. |
| `fe570f6` | Fixed the app white-screening on boot with no cloud project. |
| `da2e03c` | **The V0 server** — 10 migrations, 27/27 proof markers — and the five text screens. |
| `600d0fb` | The map stopped overprinting its own labels. |
| `8d1956e` | The dataset reworked so **every coordinate cites a Wikidata item**. 280 → 214 sourced. |

### What was established, and how it was established

**The pivot is structural, not cosmetic.** `byeharu` is a live multiplayer game carrying 333 migrations
of space-combat schema. Grafting an age-of-sail trading game onto that chain would have been two games
in one schema. So: new repository, new migration chain from 0001, old game untouched and still running.
What crossed over was the **core** — stack, shell, auth, and the discipline — never the schema and never
the combat code.

**Combat was designed out rather than deferred.** There is no battlefield. Danger resolves as one
probability table server-side and is reported as written prose on the Ledger tab. There is no scene to
render, so there is no scene to break.

**The handicap that defined the old project was removed on day one.** The predecessor's own notes said
SQL could not be run locally — no Docker, no CLI, no psql — so every SQL mistake cost a CI round trip.
Here, PGlite was tested rather than assumed:

```
VERSION: PostgreSQL 18.3 (PGlite 0.5.5) on wasm32-unknown-linux-gnu
PLPGSQL RESULT: Lisbon->Malacca = 6310.0 nautical miles
RAISE works: unknown port
```

Real `plpgsql`, real `RAISE`, no Docker. The chain now applies locally in seconds.

**The server was proven, not asserted.** 10 migrations, every one self-asserting, plus four proof files
totalling 27 PASS markers. The first-session proof plays the game: salt bought at Lisboa at 7.02 d./tun,
188 nm to Cádiz at 3.87 knots laden, sold, hides bought, home again — **+530 ducats on 8,000, 6.63%,
with all four orders completing unattended and no tick running.** That is the design's stated
win-feeling — "a ledger that moved while I was away" — demonstrated in SQL.

**The proofs earned their keep immediately.** Two defects died before shipping: `settle()` could dock a
fleet with checkpoints unresolved, so lazy settlement produced 12 voyage events where tick-by-tick
produced 10 — precisely the offline/online divergence the whole time model exists to prevent. And
`ALL`/`HALF` resolved at parse time froze a stale quantity into a queued order.

**Where the server disagreed with the design, the server won and said so.** `BUY sal 60` cannot fit a
60-tun Barca that is also carrying stores, so it refuses with `E_HOLD_FULL` naming the real capacity;
and a laden Barca takes 6.07 minutes to Cádiz, not the 4.7 the design quoted for an empty hull. Both
are recorded in `CHAIN.md` rather than smoothed away.

**The data is checkable years from now.** The first dataset was 280 ports assembled by hand. It was
replaced by 214 whose every coordinate comes from Wikidata P625 (CC0) and stores the item id it came
from. The validator passes eight checks with a worst country-bbox margin of **0.0000°**. An independent
spot-check against reference values for Lisbon, Venice, Malacca, Nagasaki, Busan, Cape Town, Amsterdam
and Istanbul showed a worst deviation of 0.021°. The projection was chosen by measurement: Web Mercator
stretches Longyearbyen 4.81×, Miller 2.16×, equirectangular 1.00×.

**Looking at the screen caught what the toolchain could not.** Build and lint were both green while the
app white-screened on boot — `createClient('', '')` throws at module load, so with no `.env.local` the
whole app died before rendering. A Playwright chromium was installed and every screen screenshotted at
390×844. That found, in addition: three label collisions on the map rendering as `Gaivotaa illa` and
`MarseiLlevante`; a fleets panel eating 60% of a phone screen; an opening map view wasting half the
display on empty Sahara; a Fleets table *clipping* its endurance column rather than scrolling it;
prose values wrapping into ragged right-aligned fragments; and a Market screen burying every price
below the fold, contradicting the design's own opening beat.

**Fixes were made as rules, not as patches.** The map's label collisions were not nudged apart — labels
are now planned as a set, with one priority table and 8-way placement, and a label that cannot fit is
dropped rather than drawn badly. Twenty specs assert no two label boxes intersect at four viewport
sizes. Likewise the boot failure was fixed by giving the auth gate **one** authority field that both
cloud and local mode set, so the two modes cannot drift apart.

### How day 0 ended

Everything above landed green and pushed. Final gates, all run and read rather than assumed:

```
npx playwright test   191 passed, 6 skipped
npm run db:apply      10 migrations, 10 self-assert receipts
npm run db:proof      4 files, 27/27 PASS markers
npm run build         exit 0
npm run lint          exit 0
```

The K.1 first session now runs **through the client seam**, not only in SQL: buy salt at Lisboa, sail
to Cádiz, sell, buy hides, sail home, sell, purse ends above 8,000.

Three defects were fixed as rules rather than patches, which is the part worth keeping. The map's label
collisions became a set-planning algorithm with priority and 8-way placement. The clipped tables turned
out to have one root cause — `w-full` pinning the table to its wrapper, crushing columns to min-content
and still overflowing — so `scrollWidth === clientWidth` read green while the data was simply hidden.
And the boot crash was fixed by giving the auth gate one authority field that both modes set.

One admission is preserved deliberately: the first version of the table-layout spec **passed the broken
code**. It was rewritten to assert the column crush rather than the overflow, and proven non-vacuous by
reverting the fix and watching it fail. A test that passes the bug is worse than no test.

### Open at the end of day 0

- **Rewiring the five screens from fixtures to live RPCs** — the one thing between this repo and a
  playable game. `src/lib/db/README.md` §4 is the field-by-field mapping table written for that job.
  The screens were built as pure presentation specifically so this would be mechanical.
- `@electric-sql/pglite` still sits in devDependencies and must move before any `--omit=dev` deploy.
- The cloud backend is written and typed but has never made a round trip, because there is no project.
- Cloud production, blocked only by Supabase's 2-free-project limit. Not urgent; the game is playable
  locally without it.
