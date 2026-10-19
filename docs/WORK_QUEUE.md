# WORK QUEUE: the owner's live list (rewritten clean 2026-10-18 ~14:05 UTC)

Standing orders: keep working and never stop; never ask (decide, record it as "decided by default", and the owner may reverse it); give a 10-minute status; make it clean; CI fast and never from scratch; close finished shells and worktrees; use Fable where efficient.

Owner 2026-10-18 ~13:55: **"so fix and do everything"**.

Deploys go through `~/bin/bv-deploy.sh <pr>` only, which merges only after the push lands. Migrations deploy in strict number order.

Prod head: **0204**.

## HAND-OFF: the owner moved to another PC, 2026-10-19 ~03:25 UTC
On the old PC, every agent, timer and worktree was stopped. Nothing runs there. Prod head **0204**, with the fight lit and arrivals at ~2.8 s.

Resume in this order:
1. **#257 `fix-acceptance`** (main's Acceptance has been red since 2026-10-18 14:33). The fixes are pushed:
   - route.stopface (the Edit control in RouteFold/deskView);
   - map.marks spec;
   - map.noblink layers (index.css);
   - select-specs;
   - the flags screenshots.

   It also brings back a `pull_request` trigger on acceptance.yml, ON PURPOSE: it runs only the selected specs and doesn't block, and it is the root-cause fix. The agent was stopped mid-step. Read ALL its checks, confirm `map.noblink` truly passes at ≤ 7 layers, then merge, then confirm main's Acceptance goes green.
2. **0205 `osn-arrivals-fast`**, WIP pushed (f63df10) and NOT ready. Read `docs/dev-log/2026-10-19-arrivals-fast.md` § HAND-OFF. Knob-only 16 → 8 hurt the laps (33 → 51 % ≤ 0). Finish "trade loops first", re-run the paired sim, and ship only if both arrivals and laps hold.
3. The owner decides: insurance (proposal below), and pirates / zones / dungeons.

## In progress, in priority and deploy order
| # | Item | Owner's words | State |
|---|---|---|---|
| 0 | **The owner's fleet Gaivota is stuck.** Plan line 29 `SAIL MTY` (14,015 nm) was refused by his Navigation reach (1,700 nm); lines 30–32 are frozen and Skip does nothing. Fix: a failed plan cancels its own lines and the queue frees; the desk checks reach at plan time; multi-leg passages within reach; unblock Gaivota | "Gaivota stopped at order 29 and will not skip it … what is this?" | building (`osn-plan-reach`), slice 1 first |
| 1 | **0182 re-plan batches**: waiting merchants re-checked about every 10 min; reconcile back under its 60 s budget (it was 57.4 s and 62.0 s) | "why once an hour? can it be faster?" | building (`osn-replan-batches`) |
| 2 | **Remove the 0180 sinks** (surplus hand-over, ship building, the knob). Famous gear unobtainable until the owner sets its sources | "no need to hand in surplus… no they don't need to build ships"; "famous gear … later" | building (`osn-merchant-redesign`, slice 1) |
| 3 | **A merchant's route always pays**, by design. The named case is Comptoir Chastellain at −15 a lap; 55 % of laps are still ≤ 0 | "why is there a route that has no profit? this is design defect" | building (`osn-merchant-redesign`, slice 2) |
| 4 | **Black map blinks at DPR 2** (the owner's laptop; #197 was proven only at DPR 1) | "black blinks that is too disturbing" | NOT reproduced on his PC: 0 black frames in 20k+ frames (Chrome 155, Edge, DPR 2; tile memory 142 MB of 546 MB, 0 OOM). **Owner 2026-10-19: it was an OLD build in an unrefreshed tab; now fine.** Adding a "New version, refresh" banner (`osn-new-version-banner`). Fixing the one real waste found, the daylight mask re-rastered every frame (`osn-daylight-raster`) |
| 5 | **Flags:** a France flag that reads (royal blue with gold lilies); flags at every zoom; the flag snug before the name; clearer on ships. City names black in daylight, with a dark pulsing city marker | "flag is too far"; "france flag looks shit"; "make the city name in light touching zone black…" | building (`osn-flags-2`) |
| 6 | **COMMAND desk → a real trading terminal:** three panes, a big chart, a Best-trade ticket, no bare "—", no native scrollbars | "what about the command tab? … like stock trading screen … stylish" | building (`osn-desk-terminal`) |
| 7 | **Automatic fight:** rounds decided by range, accuracy, attack, armour, boarding and sighting; armour also against shoals; a battle report. Lands dark, then lit with a check | "lets do a automatic fight, so that range and accuracy is an important factor"; "shoals and damage too" | building (`osn-auto-fight`) |
| 9 | **7 great powers** like UWO: Portugal, Spain, England (Europe); Ottoman, Mughal (Islamic); Ming, Japan (Asia), decided by default. The other 16 become minor city rulers. 3–4 home cities each; the rest contested; existing state migrated | "make it 7 big power like uncharted island, spread mainly on europe and asia, as well as islamic region" | design + build (`osn-seven-powers`) |
| 8 | `docs/OWNER_REQUESTS.md` brought up to date from the audit (`docs/OWNER_AUDIT_2026-10-18.md`) | "you leaving out things that i say?" | Fable agent (`osn-ledger-1018`) |

## Proposed, awaiting the owner
- **Insurance (owner idea, 2026-10-19):** port underwriters paid from city purses; a premium priced from the voyage's danger; payout on cargo loss with a 10 % deductible; NPC houses insure in place of the free refound. Proposed v1 in chat; build when the owner says.

## Owner decisions on record (2026-10-18)
- **Combat:** automatic fight, no battle board. Pirates and zones: ideas given (danger zones, pirate havens with bosses and famous-gear loot, pirate fleets, escort contracts); the owner hasn't chosen.
- **16 companies:** LEAVE them.
- **Money growth:** leave it for now.
- **Rejected:** the merchant surplus hand-over, merchant ship building, and the 157,500 hull-skill tuition (one-off in 0167; never repeated).
- **Docks:** leave as is.
- **Route-length gate** (Navigation reach, 0107): the owner's own rule (row 113, 2026-10-10).

## Done and live today (2026-10-18)
- 0170–0177 and D3/D5/D8: the COMMAND desk, with PORT deleted.
- 0172: city purses in the millions. 0173: distance pricing. 0174: circulation.
- 0178: skills on. 0179: captains on.
- 0180: BUY lines priced live. 0181: no empty laps; REPAIR only when due.
- Flags (#198); CI 79 → 11 min (#215); flaky specs (#216); from-zero chain (#212); proof 12 (#203).
- Cleanup: 64 merged or closed branches deleted; 25 orphan folders, 90 logs and 5 stale previews removed.
