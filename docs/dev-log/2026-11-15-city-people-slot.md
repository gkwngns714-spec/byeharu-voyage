# 2026-11-15 · city-people-slot · 0434 THE CITY PEOPLE CHART TELLS THE RIGHT TIME

The queue's known bug: "stats_city_people slot dating (frozen fn, needs a new migration)".

## The defect

The Stats city page's People chart is drawn from `world.stats_city_people(port)` (0305). Its `series` dates each logged population step as
`to_timestamp(l.slot * 600)`: a step was 600 s long when 0305 was written.

0413 (a day lasts an hour) changed the step. The writer, `public.population_tick`, now stamps a row with
`public.clock_count('population_slot', now)`: counted on from the anchor `public.clock_set` wrote at the seam, at the new length
`population_slot_seconds` (3,000 s). The one inverse of that counter is `public.clock_start('population_slot', slot)`. 0413 moved the writer
and every other reader onto the counter; it missed this reader, because 0305 had the 600 as a literal inside a body, not a knob.

So past the seam, the reader serves `slot x 600` where the truth is `anchor epoch + (slot - anchor count) x 3,000`:

- the newest point is dated far in the past (about 19 hours one day after the seam, 4 hours more for every 5 real hours);
- the chart's span is squeezed to a fifth (a step 3,000 s long is drawn 600 s long).

Seen in the local chain world (proof 135): the step holding 16:24 local time was dated 15:43 by the fix, and would have been dated 00:40 by
the 0305 body.

Steps logged before the seam were and are dated right (the anchor's `start` + (slot - count) x `was` 600 = slot x 600).

Nothing else carries the literal: `grep "\* 600"` over the chain finds only 0305 and the writer's pre-image in 0413's hunk.
`public.town_hall_people` counts slots and never turns one into an instant.

## The fix

One hunk in `world.stats_city_people`: `to_timestamp(l.slot * 600)` -> `public.clock_start('population_slot', l.slot)`. It is STABLE
and owned by the definer, so the reader stays STABLE SECURITY DEFINER with its grants. The JSON shape is the same, and the client is
untouched. No table, knob, cron job or other function moves. `-- news: none` (decided by default): a chart's dates are corrected, and nothing a
player does changes.

## Proof

- 0434's self-assert: the hunk occurs once and reverses; grants, volatility and owner are unmoved; no other function moved. A rolled-back
  probe plants two steps for London past its newest. Each point's `at` counts back, through `clock_count`, to its own slot, and the two stand
  `population_slot_seconds` apart. Locally: "two planted steps dated 07:33 and 08:23 UTC, counted back to their slots, 3000 s apart; 40 ms".
- Proof 135, on the real writer, 3/3. `CP_STEP_DATED`: two ticks, each point counts back to the writer's slot, and the step holding now()
  is dated inside the last step. `CP_STEP_LENGTH`: 3,000 s apart. `CP_BEFORE_SEAM`: a step from before the anchor is still dated by the old
  length. Every marker fails on the 0305 body.
- `printed to the whole second`: an anchored step can begin on a fraction of a second (the anchor's start is re-timed about the seam). `at` is
  printed to the second, so the checks count `at + 1 s`, which is still inside the 3,000 s step.

## Load

None. It is a read, with one `world_config` key lookup a point, over at most `population_log_slots` (144) rows.
