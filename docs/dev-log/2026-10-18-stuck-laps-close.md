# 2026-10-18 — a stuck merchant lap is answered on the first clear — `osn-0150-laps-close` (migration 0150, deployed; drafted as 0152)

**The defect.** 0142 said a merchant stuck on an `E_ENDURANCE` SAIL would recover with no data
change: the hourly upkeep re-plans her after her third cleared failed order, and that re-plan raises
her stores preset. On prod the open merchant laps older than 6 h went 369 (14:52 UTC) to 391 (15:12),
after a reconcile that succeeded.

**What the 391 were (prod, read-only, head 0148, ~15:15 UTC).**

| state | laps | |
|---|---|---|
| DOCKED, failed `SAIL` `E_ENDURANCE` at the head of the queue | 270 | 251 never re-planned since 0142 |
| UNABLE_TO_SAIL, durability 0 | 88 | the tow, 0151 |
| SAILING, re-planned after 0142 | 33 | released; 0142's re-plan works when it comes |

Four causes overlap inside the 270:

1. **The re-plan never comes.** `npc_tend_route` counts a lap's clears by its `NPC_CLEARED`
   events. `npc_compact` deletes events older than `npc_retention_hours` (6). The hourly pass runs
   out of its 60 s budget (each run takes 66–71 s) and clears about 120 merchants an hour, so it
   reaches a stuck one every two or three hours. 251 of the 270 held fewer than three clears in
   that window. Take "Carrera Guayaquil": she showed `n = 4` at 10:07, which re-planned her with the
   pre-0142 planner (that planner raised no preset). The compactor then deleted the earlier events,
   so she showed `n = 2` at 15:07 and was not re-planned. A clear without a re-plan cannot help
   either. Her stop had already been rendered and her cursor had moved on, so
   `cmd.run_standing_route`'s sail-on branch enqueued only `SAIL TO …`, with no PROVISION. The SAIL
   was refused again, every hour.
2. **The casks hold the wrong store.** `cmd.do_provision` topped up the total of water and food
   and split the top-up by the drink/eat ratio. FOUL_WATER (0059) takes only water. A merchant comes
   in with spare food and short water, the spare food counts as room, and she gets
   `E_HOLD_FULL "the casks are already full"` while her water is short. In 143 of the 270, water and
   food were more than a day apart.
3. **The hold has no room for the casks.** In 41 of the 270, the cargo the at-profit SELL refused
   left no room for the leg's stores. The cut-loss waits for two closed laps, and the lap can never
   close.
4. **The planner counts the days short.** It measures with the reach table's nm plus 1 day; the
   SAIL measures the course itself, which is 2–7 % longer on long legs. 19 laps were refused by more
   than that day.

**The fix (0150).** It goes in the four bodies that make these decisions. Each is cut by a hunk
that is asserted to occur once, reversed back to its pre-image, and leaves the ACL unchanged:

- `npc_tend_route`: when the head of the queue is a SAIL refused `E_ENDURANCE`, the clear that
  releases it re-plans her at once. The third-clear rule still applies to every other refusal.
- `public.stores_topup` is the one top-up rule, and both of `cmd.do_provision`'s passes call it.
  It raises each store to the days asked, the shorter store first, and never fills past the hold.
  When water and food are in step it gives the same result as the old split. That is asserted
  over every crewed hull in the world in both modes, and checked read-only against prod's 1,822
  hull×mode rows: 0 differ, 0 pass the hold, 0 get fewer days.
- `public.sail_refused_days` reads the SAIL's own `need` figure. `npc_plan` keeps the preset of the
  loop she stays on at least that high.
- `public.npc_casks_blocked` tells `npc_leg_lines` when to write the cut-loss for room: `SELL <good>
  ALL` at the quay's bid, for every good aboard. It applies only when her SAIL was refused for
  endurance and a hull carrying cargo cannot stow the leg's casks.

The probes: a merchant of the migration's own is put on a stuck lap of each cause (PRESET, ROOM,
CASKS). One `npc_tend_route` step puts her to sea, and settling the voyage closes the lap at her
stop 0. Each probe was mutation-checked: with its fix reverted, the probe fails. With the
`npc_tend_route` change reverted, PRESET fails with prod's exact pattern, a lone `SAIL TO LIS`
refused again. One step takes 150–190 ms (PGlite).

**Release estimate (prod, read-only).** All 271 docked `E_ENDURANCE` laps at the time of the
estimate reach their passage's need under 0150's arithmetic. 63 of them first need the cut-loss
for room. 6 have a purse under 500 d. and may still be refused `E_INSUFFICIENT_FUNDS` for their
stores. The 88 wrecks wait for the tow. The rate is bounded by the hour's 60 s budget, so they drain
over a few passes, not in one.

**Not done.** The third-clear count still reads events the compactor ages out, but no other
refusal holds a merchant today. A merchant who cannot pay for her stores (2 refused so today, up to
6 at risk) is not helped.

**Deployed, then CI red on a fresh chain (2026-10-17 ~16:10 UTC).** The file went to prod
renumbered as 0150 and its self-assert passed there. Stuck laps fell from 391 to 345 after the
16:07 pass. PR #168's disposable-chain then failed on a fresh chain:
`CASKS — she reached her stop 0 and the lap did not close (fleet SAILING at <NULL>)`.

The cause was the probe, not the fix. The probe settled the voyage once, at the eta it read before
sailing. `voyage.settle` resolves the sea-days, and a STORM or a foul wind can delay the voyage:
`voyage.recompute_eta` moves the eta later, and the arrival check (`p_now >= v.eta`) then fails.
Which days draw what depends on the voyage, so the result changes from one world to another. Prod
and local PGlite drew no delay; CI did.

The probe now re-reads the eta and settles again until the voyage is in, at most 12 times, and
raises if she is still at sea. Only the self-assert changed. The function bodies are identical to
prod's: each hunk's new text occurs once in prod's live body, and the three new helpers' bodies
are verbatim in the file.

Simulating a delay (a stale eta one day early) reproduces CI's failure with the old probe and
passes with the new one. The branch is rebased onto main (0149 K0, 0151 K1), so 0151 applies after
0150.

**Second red: the apply-proof would not run an out-of-order file.** With 0150 placed between
main's 0149 and 0151/0152, the disposable-chain job failed in 13 s: "the base chain is not a prefix
of this chain ... refusing to rebuild from zero on a PR". No saved snapshot can be a prefix of a
chain that has a file inserted before its last one. That is the same situation as an edited old
migration, which is the no-from-zero rule's one exemption, but the selector did not count it.

`scripts/ci/select-specs.mjs` now counts it: an added migration whose version sorts before the
base chain's newest file sets `growth.run` (from-zero allowed, and logged). Its 5 self-test
controls still hold, and on this PR it reports
`20260818000150_…: added before the base chain's newest file (20260818000152)`.

**Third red: the ROOM probe tested the world, not the fix (2026-10-17 ~17:50 UTC).** On the fresh
chain the disposable-chain job failed with `ROOM — one step did not put her to sea`. The order list
shows that the cut-loss was written and executed (`done SELL tortoiseshell ALL`). The `SELL … ALL AT
>= …` refusals before it are the ordinary at-profit SELL.

The probe filled the whole hold with "the first good by id FNC bids for". Ids are random per world,
so CI drew tortoiseshell. I forced that good locally, and the step sold 21 of 1,416 units: the quay
would take no more, her endurance stayed at 3.1 days against a 12-day preset, and she was still
blocked.

The probe now owns its precondition. Her one hull holds a small parcel (her preset's water, in
tons) of the first good by code that FNC takes whole today (its quote and her daily cap), plus spare
food, leaving room for only half her preset's water. The cut-loss clears that room in one sale. It
passes on the full chain 0149 → 0156, and is still red when `npc_casks_blocked` is disabled. The
function bodies are still identical to prod's.

**Prod, read-only, ~17:55 UTC.** 0150 is working there. The 17:07 pass cleared 99 E_ENDURANCE
merchants, and 89 of them are now at sea or have moved on. 162 docked laps are still waiting. Most
of those were last re-planned at 16:07, before 0150 was live. The hourly budget (66–67 s against 60)
reaches about 100 of them per hour, and a re-plan moves a route to the back of the roster.

Two slower paths seen there are real, but neither is a deadlock:

1. **Stores slow her down.** `voyage.ship_speed` counts water and food in the hold's fill
   (`load_speed_penalty` 0.25). Provisioning makes her slower, so the need can come out just above
   the preset's +1 day. "Watari Mogadishu": preset 84, need 85.2. The next clear raises the preset
   again.
2. **A shallow quay sells the cut-loss in parts.** A quay that takes little of a good sells the
   parcel one chunk per pass. Also, `order_queue_max` = 12 drops the trailing SELL lines first, and
   those are the cut-loss lines.
