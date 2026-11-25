// ═══════════════════════════════════════════════════════════════════════════════════════════════
// frozenAsserts — the ONE place a FROZEN migration's self-assert is read differently on PGlite
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS EXISTS (2026-10-27). Two self-asserts in files that production applied long ago fail
// for reasons that are not the chain's:
//
//   * 0108 (d5) requires world.route_board() to average <= 400 ms over 10 calls. That is a
//     stopwatch, and on wasm PostgreSQL it decides by the machine: PC gkwng measured 426 and
//     451 ms, so every from-zero replay there (a pruned prefix cache, `npm run build`) died at
//     0108 while CI's runners passed. A wall-clock threshold on shared hardware is a flake
//     (tests/map.lag.spec.ts's header says the same of the client).
//   * 0019 (g) plays the quay's top row BUY -> SAIL -> SELL. The voyage's hazard dice are seeded
//     from its id (0006 voyage.rng), which is gen_random_uuid(), so about one boot in a few dozen
//     rolled a PIRATES / STRIPPED day (0007 voyage.settle empties the hold) and the SELL answered
//     E_NO_CARGO: "the quay predicted 6818 out / 7706 in and the orders moved 6818 / <NULL>"
//     (PR #343, run 40292383876, cold boot; green on re-run). What it proves is that the price
//     OFFERED is the price CHARGED; the sea leaving the cargo alone is another question, and
//     0034/0092/0093/0096 close that door the same way inside their own probes.
//
// 2026-11-07, 0226: the third kind, the CLOCK OF THE DAY. 0226 (g) plants two finished hours at
// `date_trunc('hour', now()) - interval '26 hours'` and expects ONE day row over both (n 8). In UTC
// hour 01 that pair is 23:00 and 00:00, two days, so the day folds into two rows of n 4 and the
// assert fails ("the day folded day … n 4"). From-zero applies that reached 0226 at 01:00, 01:07
// and 01:41 UTC died there (chain-baseline runs of 11-04, 11-05, 11-06), and so would any PGlite
// replay in that hour (10:xx on PC gkwng). The patch moves the pair one hour earlier in UTC hour
// 01 and nowhere else. scripts/ops/harness/frozen-0226/ proves it for all 24 hours.
//
// 2026-11-15, 0266 / 0269 / 0270 / 0272 / 0273 / 0274: the fourth kind, THE PROBE'S OWN EYE. These six
// compare an OLD body against a NEW one by a text digest of the rows each leaves (pg_temp.digest_NNNN).
// The digest sorts a house's ledger rows and events by their JSON text and blanks the uuids only
// AFTERWARDS, on the whole string. A ledger row's text is kind, player_id, created_at, ducats_delta,
// ref_event_id, balance_after: two rows of one house with the same kind and the same amount are
// therefore ordered by ref_event_id, a gen_random_uuid() made inside the probe, and they differ after
// it (balance_after). Each run draws new uuids, so the two rows swap at random and the digests of two
// IDENTICAL runs differ: "0270 self-assert FAIL: the loop leaves different rows" (main, run
// 43708858363, the merchants leg from zero, 2026-11-15; the ledger leg passed on the same commit). It
// needs a tied pair, which the market's dice deal or do not (0270's loop starts two merchants of one
// house twice over, Casa da Índia and Kamer Amsterdam): measured on a world at 0269, 0 failures in 75
// loop runs as dealt, and 17 of 24 applies of the file with every PROVISION made free (two rows of
// amount 0 in one house); patched, 0 of 24 (scripts/ops/harness/frozen-0270/). The patch re-cuts the probe's own temp function at the head of the
// self-assert, from its live text: the two row sets are blanked BEFORE they are sorted. Rows that tie
// are then identical, and every row still counts, so a real difference still fails.
//
// WHY NOT EDIT THE FILES. An applied migration is history (supabase/migrations/README.md §1), and
// editing one moves every prefix-cache key after it, prunes every kept snapshot and sends CI from
// zero — the owner's law is that a pull request's CI never does that. So the files stay byte for
// byte, and the APPLIER reads these two asserts differently instead:
//
//   * Only text inside the file's LAST `do $$ … $$` block (the self-assert) may be touched, and
//     only a self-assert's PROBE, which rolls itself back: the database a patched file leaves
//     behind is the one the unpatched file leaves behind. Snapshots, images and their keys are
//     unchanged (the prefix key and fingerprintChain() hash the FILE, which nobody alters).
//     (The digest patches replace a pg_temp function the file itself created for its probe: it
//     dies with the session and is in no snapshot's content digest, which reads no pg_ schema.)
//   * Every patch names the exact text it replaces, and that text must occur EXACTLY ONCE — a
//     patch that no longer fits is a loud failure, never a silent no-op.
//   * Each patch keeps the assert able to fail.
//   * Production applies the files as written, through `supabase db push`, which never reads this
//     module; 0108's 400 ms holds there. CI's from-zero applies on real PostgreSQL (the nightly net,
//     chain-baseline) read this same list through scripts/ci/patch-frozen-asserts.mjs, in the
//     runner's working copy only, restored before anything hashes the files.
//
// This is not a place for new migrations' problems: a migration that is not yet applied anywhere
// is fixed in its own file. A patch belongs here only when the file is frozen (<= prod head).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface FrozenAssertPatch {
  /** The migration's full filename. */
  file: string
  /** Exact text inside the file's final `do $$` block; must occur exactly once in the file. */
  find: string
  /** What the applier executes in its place. */
  replace: string
  /** One line, for the log and the reader. */
  why: string
}

const UUID_RE = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

/** The row text the six digests sort, as the files write it, and the same text with its uuids blanked first. */
export function digestRow(alias: 'l' | 'e', table: 'ledger' | 'events'): { was: string; now: string } {
  const was = `(to_jsonb(${alias}) - 'id')::text as x from public.${table} ${alias}`
  return { was, now: `regexp_replace((to_jsonb(${alias}) - 'id')::text, '${UUID_RE}', 'U', 'g') as x from public.${table} ${alias}` }
}

/**
 * 0266–0274's probe digest sorts ledger rows and events by a text that still holds the uuids the probe
 * itself drew (header, "the fourth kind"). At the head of the self-assert the temp function is re-cut
 * from its own live text: both row sets blanked before the sort. A body that is not the one this was
 * written against raises — never a silent no-op.
 */
function digestSortsBlankedRows(file: string, n: string, args: string): FrozenAssertPatch {
  const find = `  select * into v_b from before_${n};\n`
  const ledger = digestRow('l', 'ledger')
  const events = digestRow('e', 'events')
  const grows = ledger.now.length - ledger.was.length + (events.now.length - events.was.length)
  return {
    file,
    find,
    replace:
      `  -- src/lib/db/frozenAsserts.ts: pg_temp.digest_${n} sorts its ledger rows and events AFTER their uuids are blanked\n` +
      '  declare\n' +
      `    v_fz_was text := pg_get_functiondef('pg_temp.digest_${n}(${args})'::regprocedure);\n` +
      '    v_fz     text;\n' +
      '  begin\n' +
      `    v_fz := replace(replace(v_fz_was, $fz$${ledger.was}$fz$,\n` +
      `                                      $fz$${ledger.now}$fz$),\n` +
      `                    $fz$${events.was}$fz$,\n` +
      `                    $fz$${events.now}$fz$);\n` +
      `    if length(v_fz) <> length(v_fz_was) + ${grows} then\n` +
      `      raise exception '${n} frozen-assert patch FAIL: pg_temp.digest_${n} is not the body the patch was written against (% characters added, ${grows} expected)', length(v_fz) - length(v_fz_was);\n` +
      '    end if;\n' +
      '    execute v_fz;\n' +
      '  end;\n' +
      find,
    why:
      `${n}: the probe's digest sorts a house's ledger rows and events by text that still holds the uuids the probe drew ` +
      '(ref_event_id stands before balance_after), so two rows of one kind and one amount swap at random and two identical runs ' +
      'digest differently; the temp digest is re-cut at the head of the self-assert to blank the uuids before the sort',
  }
}

/**
 * 0154's probe holds the arrival voyage.arrival_at predicts to the eta voyage.settle writes. They part, by 0125's
 * rule and not by a fault, when a FAIR_WIND falls on a day that ends at or near the arrival: the wind is rolled at that
 * day's end, so the eta it writes lies BEFORE the instant it is known, and arrival_at answers that instant (its floor).
 * The weather is drawn from the voyage's random id. An arrival that is not the eta must now be that floor, worked by
 * hand from the settled days, to the millisecond; any other difference fails as written.
 */
function arrivalIsTheEtaOrTheFloor(passage: 'dark_voyage' | 'lit_voyage', settled: 'new' | 'one', arrival: 'arrival_new' | 'arrival'): FrozenAssertPatch {
  const v = `v_pr->'${passage}'->'${settled}'`
  const eta = `(${v}->'voyage'->>'eta')::timestamptz`
  const at = `(v_pr->'${passage}'->>'${arrival}')::timestamptz`
  const find = `     or ${eta} <> ${at}\n`
  return {
    file: '20260818000154_a_skill_is_paid_where_the_game_charges.sql',
    find,
    replace:
      `     -- frozenAsserts: or the floor a late FAIR_WIND leaves (0125: she cannot arrive before the day that blew is over)\n` +
      `     or (${eta} <> ${at}\n` +
      `         and coalesce(abs(extract(epoch from ${at} - (select greatest(${eta}, max(least(\n` +
      `               ${eta} - make_interval(secs => (q.after * 3600 / public.wc_num('time_compression'))::double precision),\n` +
      `               now() - interval '60 days' + make_interval(secs => ((q.d * 24 + q.before) * 3600 / public.wc_num('time_compression'))::double precision))))\n` +
      `             from (select x.d, sum(x.h) over (order by x.d rows between current row and unbounded following) as after,\n` +
      `                          coalesce(sum(x.h) over (order by x.d rows between unbounded preceding and 1 preceding), 0) as before\n` +
      `                     from (select (e->>'day')::int as d, coalesce((e->'payload'->>'delay_hours')::numeric, 0) as h\n` +
      `                             from jsonb_array_elements(${v}->'events') e) x) q))), 1) > 0.001)\n`,
    why:
      `0154 (b, ${passage}): the predicted arrival is not the settled eta when a FAIR_WIND blows on a day that ends at the arrival (0125's floor; the weather is the random voyage id's): ` +
      'PR #869, from zero, 2026-11-25: a wind of 20.93 h on day 50 of 52, 78.5 s apart. A difference must now be exactly that floor, worked from the settled days; anything else fails as written',
  }
}

export const FROZEN_ASSERT_PATCHES: readonly FrozenAssertPatch[] = [
  {
    file: '20260818000019_the_quay_names_the_port_that_pays.sql',
    find: '    v_played   := world.trade_routes(v_lis, v_fleet, 1, null);\n',
    replace:
      "    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';\n" +
      '    v_played   := world.trade_routes(v_lis, v_fleet, 1, null);\n',
    why: '0019 (g): no hazard on the probe voyage (random voyage id -> PIRATES/STRIPPED -> E_NO_CARGO); inside the rolled-back probe',
  },
  {
    file: '20260818000108_the_board_prints_what_a_lane_asks_of_you.sql',
    find: '    if v_ms > 400 then\n',
    replace: '    if v_ms > 1200 then\n',
    why: '0108 (d5): 400 ms -> 1,200 ms a call on PGlite (426/451 ms measured on a slower PC); real Postgres keeps 400',
  },
  arrivalIsTheEtaOrTheFloor('dark_voyage', 'new', 'arrival_new'),
  arrivalIsTheEtaOrTheFloor('lit_voyage', 'one', 'arrival'),
  {
    file: '20260818000315_merchants_answer_requests.sql',
    find: '  v_res  jsonb;\nbegin\n  v_res := cmd.enqueue(p_player, jsonb_set(cmd.parse(p_player, p_fleet, v_line)',
    replace:
      '  v_res  jsonb;\nbegin\n' +
      '  delete from public.trade_daily where player_id = p_player and qty < 1000000;\n' +
      '  v_res := cmd.enqueue(p_player, jsonb_set(cmd.parse(p_player, p_fleet, v_line)',
    why: "0315 (e): the probe's sales run through the drawn good's daily cap (0.35 x stock_target; the good is drawn from the game day, a minute here) -> E_DAILY_CAP on some minutes; each probe sale now starts with a fresh allowance, inside the rolled-back probe; step (h)'s spent allowance (1e8) is kept",
  },
  {
    file: '20260818000315_merchants_answer_requests.sql',
    find: '    -- (c) THE FLOOR IS KEPT: sale price plus bonus under her floor, no delivery, the line refused as it always was\n',
    replace:
      '    -- frozenAsserts: the bid (c) and (d) set their floors by is read here, of the three units the budget pays for, not before (a) and (b) sold eight\n' +
      "    v_bid := (select q.avg_price from world.quote(v_port, v_good, 3, 'sell', null, v_f1) q);\n" +
      '    -- (c) THE FLOOR IS KEPT: sale price plus bonus under her floor, no delivery, the line refused as it always was\n',
    why: "0315 (c), (d): the floors are set by a bid read before (a) and (b) sold eight units; where the drawn good (the game day's draw) is thin, those sales move its bid by more than the half bonus that separates (d)'s floor from it, so the bonus no longer lifts the sale -> E_PRICE_LIMIT (chain-baseline run 45538163401, Barley Flour; locally Rice Flour at a stock of 44, 105.80 -> 93.57). The bid is read again before (c) as the answering door reads it, inside the rolled-back probe; (c)'s refusal and (d)'s lift are the file's own",
  },
  {
    file: '20260818000226_a_price_is_kept_for_years_both_ways.sql',
    find: "    v_h0 := date_trunc('hour', now()) - interval '26 hours';\n",
    replace:
      "    v_h0 := date_trunc('hour', now()) - interval '26 hours'" +
      " - case when extract(hour from now() at time zone 'UTC') = 1 then interval '1 hour' else interval '0' end;\n",
    why: "0226 (g): the probe's planted pair is 26 h back; in UTC hour 01 that is 23:00 and 00:00, two days, so the day folds into two rows of n 4 and the assert fails; one hour earlier in UTC hour 01 only, inside the rolled-back probe",
  },
  {
    file: '20260818000367_an_armada_sails_as_one.sql',
    find: '    update public.ships set durability = durability * 0.5 where fleet_id = v_f2;   -- the second fleet is the slower now\n',
    replace:
      '    update public.ships set roll_speed = 1 where fleet_id in (v_f1, v_f2);\n' +
      '    update public.ships set durability = durability * 0.5 where fleet_id = v_f2;   -- the second fleet is the slower now\n',
    why: "0367 (b): the probe halves the second fleet's hull to make her the slower, but each flagship rolls her own speed and hull from her id (0276: 1.000 to 1.200 here), and a halved hull that rolled 1.2 still sails at 0.84 of her speed: 0.84 x 1.2 = 1.008, so a first fleet that rolled 1.000 against a second that rolled both near 1.2 is not the faster and the assert raises. Rare (0 of 8,000 pairs measured; the same step at 0.6 of a hull, proof 68's, 15 of 8,000), but it is the dice and not the chain; the two speed rolls are made equal first, inside the rolled-back probe, so the worn hull alone decides (at most 0.84 against 1)",
  },
  {
    file: '20260818000466_requests_a_ship_can_carry.sql',
    find: "    v_city := (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open');\n",
    replace:
      '    -- frozenAsserts: the probe harbour is the first, LIS first, whose two jobs today post (tried in a rolled-back block)\n' +
      "    for x in select p.id from public.ports p where p.kind = 'HARBOUR' order by (p.id = v_port) desc, p.code loop\n" +
      '      begin\n' +
      '        v_n := public.hold_request_post(x.id, now());\n' +
      '        v_n := v_n + public.hold_request_post(x.id, now());\n' +
      "        raise exception sqlstate 'BV467';\n" +
      "      exception when sqlstate 'BV467' then null;\n" +
      '      end;\n' +
      '      if v_n = 2 then v_port := x.id; exit; end if;\n' +
      '    end loop;\n' +
      "    v_city := (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open');\n",
    why: "0466 (8): the probe's two hold jobs at LIS are drawn from the game day (4 real hours); on about 1 game day in 10 there (12 of 120 measured) the drawn good is dear or its allowance thin, the lot falls under hold_request_units_min and the writer posts nothing (main, run 45180194236, the growth test from zero, 2026-11-23 14:41 UTC). The probe now runs at the first harbour, LIS first, whose two posts land today, tried in a rolled-back block; if none does, it stays at LIS and fails as written",
  },
  {
    file: '20260818000473_a_job_says_where_to_buy.sql',
    find: "    v_open := (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open' and t.size = 'hold');\n",
    replace:
      '    -- frozenAsserts: the probe harbour is the first, LIS first, whose two jobs today post (tried in a rolled-back block)\n' +
      "    for x in select p.id from public.ports p where p.kind = 'HARBOUR' order by (p.id = v_port) desc, p.code loop\n" +
      '      begin\n' +
      "        v_open := (select count(*) from public.trade_contracts t where t.port_id = x.id and t.status = 'open' and t.size = 'hold');\n" +
      "        update public.world_config set value = to_jsonb(v_open + 2) where key = 'hold_request_open_max';\n" +
      "        v_now := public.clock_start('game_day', world.game_day()) + interval '1 second';\n" +
      '        v_n := public.hold_request_post(x.id, v_now);\n' +
      '        v_n := v_n + public.hold_request_post(x.id, v_now);\n' +
      "        raise exception sqlstate 'BV474';\n" +
      "      exception when sqlstate 'BV474' then null;\n" +
      '      end;\n' +
      '      if v_n = 2 then v_port := x.id; exit; end if;\n' +
      '    end loop;\n' +
      "    v_open := (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open' and t.size = 'hold');\n",
    why: "0473 (7): 0466's dice again. The probe's two hold jobs at LIS are drawn from the game day (4 real hours); v_now is the day's first second, so the hour of day moves nothing, but on 14 of 240 game days measured there a drawn good is dear or thin, the lot falls under hold_request_units_min and the writer posts nothing (main, run 45529660879, from zero, 2026-11-25 02:46 UTC; game days 623208, 623242, 623274 and 623292 fail locally as written and pass patched). The probe now runs at the first harbour, LIS first, whose two posts land today, tried in a rolled-back block; if none does, it stays at LIS and fails as written",
  },
  digestSortsBlankedRows('20260818000266_a_lap_starts_in_its_own_job.sql', '0266', 'uuid,uuid,uuid'),
  digestSortsBlankedRows('20260818000269_the_quay_writes_down_its_long_holds.sql', '0269', 'uuid,uuid,uuid'),
  digestSortsBlankedRows('20260818000270_the_clear_replans_her_lines_before_the_quay.sql', '0270', 'uuid,uuid,uuid'),
  digestSortsBlankedRows('20260818000272_a_crew_shortage_is_paid_from_the_hold.sql', '0272', 'uuid,uuid,uuid'),
  digestSortsBlankedRows('20260818000273_a_sale_is_the_whole_stack.sql', '0273', 'uuid,uuid,uuid,bigint'),
  digestSortsBlankedRows('20260818000274_the_clear_acts_before_the_quay.sql', '0274', 'uuid,uuid,uuid'),
]

const BY_FILE = new Map<string, FrozenAssertPatch[]>()
for (const p of FROZEN_ASSERT_PATCHES) BY_FILE.set(p.file, [...(BY_FILE.get(p.file) ?? []), p])

/** Where the file's final `do $$` block starts, or -1. */
function lastDoBlock(sql: string): number {
  // `do $$` or a tagged `do $m$` (0315 wraps its whole file in one)
  let at = sql.startsWith('do $$\n') ? 0 : -1
  for (const m of sql.matchAll(/\ndo \$[A-Za-z_]*\$\n/g)) at = Math.max(at, m.index)
  return at
}

/**
 * The SQL the applier executes for `file`: the file's own text, or — for a frozen migration with a
 * patch (or several) above — that text with those self-assert lines replaced. Throws when a patch no longer fits.
 */
export function sqlToApply(file: { name: string; sql: string }): string {
  const patches = BY_FILE.get(file.name)
  if (!patches) return file.sql
  const block = lastDoBlock(file.sql)
  // every patch is placed on the file's OWN text (a patch can never match what another one wrote)
  const placed = patches.map((patch) => {
    const at = file.sql.indexOf(patch.find)
    const again = at === -1 ? -1 : file.sql.indexOf(patch.find, at + 1)
    if (at === -1 || again !== -1 || block === -1 || at < block) {
      throw new Error(
        `FROZEN ASSERT PATCH NO LONGER FITS: ${file.name} — the text it replaces must occur exactly once, ` +
          `inside the file's final do $$ block (found at ${at}, again at ${again}, last do-block at ${block}). ` +
          'A frozen migration changed, or the patch is stale: fix src/lib/db/frozenAsserts.ts.',
      )
    }
    return { at, patch }
  })
  placed.sort((a, b) => b.at - a.at) // from the end, so the earlier places hold
  let sql = file.sql
  for (const { at, patch } of placed) sql = sql.slice(0, at) + patch.replace + sql.slice(at + patch.find.length)
  return sql
}
