# 2026-10-18 — 0155: K3, a passage teaches the skill in training — `osn-k3-sailing-bonus`

`docs/SKILLS_AND_CAPTAINS.md` D6, §3.2 "Bonus training", §8 row K3. **Not deployed; off** (`skill_sp_per_arrival`
ships 0 — the dark switch; D6's figure is 1,000). Stacked on K2 (0154, PR #172); deploy in order. Migration number
provisional (renumber to head + 1 at merge). The two hunked bodies are cut against the chain after 0154
(`voyage.settle` as K2 left it; `world.skills` = prod's 0151 body).

- **Knobs**: `skill_sp_per_arrival` 0, `skill_sp_arrival_min_nm` 300, `skill_sp_day_cap` 10,000 (inserted only where
  absent). **Table** `public.skill_sp_grants (player_id, day, sp)` — a UTC day's bonus; server-only.
- **One reading, one writer**: `public.skill_sp_bonus_today(player)` (per arrival, minimum, cap, today) and
  `public.skill_sp_grant_for(player, sp)`. A merchant leaves at once (no queue, nothing written). With nothing in
  training it says *"No skill in training: the sailing bonus waits for one."*; past the cap *"The sailing bonus is
  spent for today (10,000 / 10,000)."* Otherwise it composes the queue's own chain step: `skill_queue_set_for` with
  the queue as it stands banks the entry in progress, the bonus joins that skill's points, and the same call rebuilds
  the chain — so the queue keeps its one writer.
- **Hunks**: `voyage.settle`'s arrival arm asks for the grant (only while the knob is above 0 and `total_nm` reaches
  the minimum) before the VOYAGE_REPORT, which carries the answer as `training`; `world.skills` serves
  `sailing_bonus` only while the knob is above 0. Off, both are byte-identical to before (proven).
- **Proof** (rolled back, own houses): off, one departure settled by the old and the new body = the same passage,
  report and writes; `world.skills` unmoved for nobody and every human house. On (1,000): a 505 nm arrival moved
  Navigation IV and V each exactly 2,000 s earlier (1,000 SP at 1,800 SP/h) and said so; ten grants fill the day,
  the eleventh arrival credits 0; a passage under the minimum (the plan's "200 nm" — the probe raises the minimum
  past its own passage instead of finding a short leg) writes nothing; an empty queue is told the bonus waits; a
  merchant's arrival writes no grant / skill point / queue / level row; the Academy serves the day's figures.
- **Not in this slice**: the client (Training: *"+1,000 from sailing today · 3,000 / 10,000"*; the report's
  `training.words` line) follows once this is LIVE and the knob is lit. D7 holds: no entry point grants or sells SP.
