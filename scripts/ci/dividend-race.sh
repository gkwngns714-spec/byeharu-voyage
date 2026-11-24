#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════════════
# dividend-race.sh: the hourly dividend (0495) under TWO SESSIONS, on real PostgreSQL
# ══════════════════════════════════════════════════════════════════════════════════════
# WHY: 0495's self-assert and proof 198 run on PGlite, which has ONE session, so two money paths were
# read and never run (docs/dev-log/2026-11-24-dividend-hourly.md, "Not verified"):
#   (a) a player's purse row (public.players) is held by another session when the hour runs: the
#       hour must not wait for her, must pay the others, and must leave her coin where it was (her
#       row's drip_left and `accrued`, unmarked for this hour) so nothing is lost: the next hour pays
#       her, and an arrival collects all the rest, once;
#   (b) two sessions run the same hour at once: one payment, not two. The second caller does not
#       wait (it skips the rows the first holds) and pays nothing; a third, after the first has
#       committed, finds the hour paid.
# This runs both, with real sessions (psql), through public.city_coupon_hour: the call
# public.tick_city makes once a run while dividend_hourly_enabled is lit. It does not run
# public.tick_city itself (the tick over the whole world), and it does not need the switch: the
# function is called directly, and the rows are marked as a lit day's coupon marks them.
#
# WHAT IT TOUCHES: it COMMITS (a second session cannot see uncommitted rows): two probe players and
# two share rows at a SEA_PLACE that has none, and the ledger rows of the payments (append-only: they
# stay). No knob, no city purse. So it REFUSES any database that is not on this machine (127.0.0.1 /
# localhost), and CI runs it AFTER the applied chain is kept as a snapshot: nothing it commits is
# ever restored anywhere. The stack is thrown away after.
# Its hours are ten days ahead; the stack's own tick never pays them out (the switch is dark there).
#
# HOW THE SESSIONS ARE STEERED (no sleeps to guess with): every step waits until pg_stat_activity shows
# the other session exactly where it must be (holding in pg_sleep, or waiting on the gate's advisory
# lock), and is released by ending the session that holds it.
#
# RUNS ONLY WHEN THE DIVIDEND FUNCTIONS EXIST: a chain without 0495 prints SKIPPED and exits 0.
# GREEN is the three "PASS: DIVIDEND_RACE_*" lines (the workflow greps for them), not exit 0.
#   DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres bash scripts/ci/dividend-race.sh
# ══════════════════════════════════════════════════════════════════════════════════════
set -euo pipefail

: "${DB_URL:?DB_URL (the disposable stack) required}"
case "$DB_URL" in
  *@127.0.0.1:*|*@127.0.0.1/*|*@localhost:*|*@localhost/*) ;;
  *) echo "::error title=dividend-race::refusing: DB_URL is not a database on this machine (this test commits rows)"; exit 1 ;;
esac

OUT="$(mktemp -d)"
GATE_KEY=4950495
A_PAID=461384     # a: the owner's holding; a day's coupon of 8,305 d. marked, 346 d. an hour
A_LEFT=8305
A_HOUR=346
B_PAID=1000000    # b: a day's coupon of 18,000 d. marked, 750 d. an hour
B_LEFT=18000
B_HOUR=750

q() { psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA -c "$1"; }

sessions() {
  q "select application_name || ' pid ' || pid || ' ' || state || ' ' || coalesce(wait_event_type, '-') || '/' || coalesce(wait_event, '-') || ' : ' || left(query, 90)
       from pg_stat_activity where application_name like 'dvr_%' order by application_name" || true
}

fail() {
  echo "::error title=dividend-race FAILED::$1"
  echo "FAIL: $1"
  echo "--- the test's sessions:"; sessions
  for f in "$OUT"/*; do [ -f "$f" ] && { echo "--- $(basename "$f"):"; cat "$f"; }; done
  exit 1
}

# wait_for "<what>" "<sql that answers 1 when it is so>": up to 30 s, then FAIL.
wait_for() {
  local i
  for i in $(seq 1 150); do
    if [ "$(q "$2")" = "1" ]; then return 0; fi
    sleep 0.2
  done
  fail "never happened in 30 s: $1"
}

end_session() { q "select count(pg_terminate_backend(pid)) from pg_stat_activity where application_name = '$1'" > /dev/null; }

cleanup() {
  local rc=$?
  set +e
  q "select count(pg_terminate_backend(pid)) from pg_stat_activity where application_name like 'dvr_%' and pid <> pg_backend_pid()" > /dev/null 2>&1
  wait 2> /dev/null
  rm -rf "$OUT"
  exit "$rc"
}
trap cleanup EXIT

# ── 0. ONLY WHEN THE DIVIDEND FUNCTIONS EXIST ──
have="$(q "select to_regprocedure('public.city_coupon_hour(timestamptz)') is not null
              and to_regprocedure('public.collect_coupons(uuid,uuid,uuid)') is not null
              and to_regprocedure('public.real_hour(timestamptz)') is not null
              and exists (select 1 from information_schema.columns c
                           where c.table_schema = 'public' and c.table_name = 'city_shares' and c.column_name = 'drip_left')")"
if [ "$have" != "t" ]; then
  echo "DIVIDEND_RACE SKIPPED: this chain has no hourly dividend (public.city_coupon_hour): nothing to race"
  exit 0
fi
if [ "$(q "select count(*) from public.players where company_name in ('Race 0495 a', 'Race 0495 b')")" != "0" ]; then
  fail "the probe houses are already in this database: it has been used by this test once (use a fresh stack)"
fi
if [ "$(q "select count(*) from public.city_shares where drip_left <> 0")" != "0" ]; then
  fail "a share row of this database already has a pay-out left: the test would pay real rows (use a fresh stack)"
fi

# ── 1. THE SCENE, COMMITTED (two PLAYERS with no fleet; their rows marked as a lit day's coupon marks them) ──
scene="$(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA --single-transaction \
  -c "with port as (
        select p.id from public.ports p
         where p.kind = 'SEA_PLACE'
           and not exists (select 1 from public.city_shares cs where cs.port_id = p.id)
         order by p.code limit 1
      ), nat as (
        select g.nation_id from public.great_powers g order by g.nation_id limit 1
      ), clock as (    -- ten days ahead, on the hour
        select extract(epoch from date_trunc('hour', now()) + interval '10 days')::bigint as t0
      ), a as (
        insert into public.players (company_name, nation_id, ducats, is_npc)
        select 'Race 0495 a', nat.nation_id, 0, false from nat returning id
      ), b as (
        insert into public.players (company_name, nation_id, ducats, is_npc)
        select 'Race 0495 b', nat.nation_id, 0, false from nat returning id
      ), sh as (
        insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day, drip_left, drip_hour, drip_at)
        select port.id, 'docks', a.id, 10, $A_PAID, $A_LEFT, world.game_day(now()), $A_LEFT, $A_HOUR, public.real_hour(to_timestamp(clock.t0)) - 1
          from port, a, clock
        union all
        select port.id, 'market', b.id, 30, $B_PAID, $B_LEFT, world.game_day(now()), $B_LEFT, $B_HOUR, public.real_hour(to_timestamp(clock.t0)) - 1
          from port, b, clock
        returning 1
      )
      select port.id || ' ' || a.id || ' ' || b.id || ' ' || clock.t0 || ' ' || (select count(*) from sh)
        from port, a, b, clock")" || fail "the scene could not be written"
read -r PORT A B T0 ROWS <<< "$scene" || true
[ -n "${T0:-}" ] && [ "${ROWS:-}" = "2" ] || fail "the scene is not whole (no free SEA_PLACE, or no country): '$scene'"
echo "scene: place $PORT, player a $A ($A_LEFT d. to pay out, $A_HOUR an hour), player b $B ($B_LEFT d., $B_HOUR an hour), first hour at epoch $T0"

# a's purse | b's purse | a's pay-out left | b's | a's accrued | a's DIVIDEND rows | b's | a's last paid hour, from T0 | b's
state() {
  q "select (select pl.ducats from public.players pl where pl.id = '$A') || ' | ' ||
            (select pl.ducats from public.players pl where pl.id = '$B') || ' | ' ||
            (select cs.drip_left from public.city_shares cs where cs.player_id = '$A') || ' | ' ||
            (select cs.drip_left from public.city_shares cs where cs.player_id = '$B') || ' | ' ||
            (select cs.accrued from public.city_shares cs where cs.player_id = '$A') || ' | ' ||
            (select count(*) from public.ledger l where l.player_id = '$A' and l.kind = 'DIVIDEND') || ' | ' ||
            (select count(*) from public.ledger l where l.player_id = '$B' and l.kind = 'DIVIDEND') || ' | ' ||
            (select cs.drip_at - public.real_hour(to_timestamp($T0)) from public.city_shares cs where cs.player_id = '$A') || ' | ' ||
            (select cs.drip_at - public.real_hour(to_timestamp($T0)) from public.city_shares cs where cs.player_id = '$B')"
}
expect_state() {   # <when> <expected>
  local got; got="$(state)"
  [ "$got" = "$2" ] || fail "$1: the money is not where it must be.  expected: $2   got: $got"
  echo "  ok, $1: $got"
}
field() { q "select coalesce(('$1'::jsonb ->> '$2'), 'null')"; }   # one key of an answer of public.city_coupon_hour
run_hour() {   # <hours after T0>: one session, autocommit, never waiting more than 5 s for anything
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA -c "set lock_timeout = '5s'" \
    -c "select public.city_coupon_hour(to_timestamp($T0 + 3600 * $1))"
}

expect_state "before any hour" "0 | 0 | $A_LEFT | $B_LEFT | $A_LEFT | 0 | 0 | -1 | -1"

# ── 2. (a) A PLAYER'S ROW IS HELD BY ANOTHER SESSION WHEN THE HOUR RUNS ──
PGAPPNAME=dvr_holder psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q > "$OUT/holder.log" 2>&1 <<SQL &
begin;
select id from public.players where id = '$A' for update;
select pg_sleep(300);
SQL
wait_for "the holder session holds a's row" \
  "select count(*) from pg_stat_activity where application_name = 'dvr_holder' and state = 'active' and wait_event = 'PgSleep'"

r1="$(run_hour 0 2> "$OUT/hour1.err")" || fail "(a) the hour failed or waited for the held player (lock_timeout 5 s): $(cat "$OUT/hour1.err")"
echo "(a) the hour, a's row held: $r1"
[ "$(q "select count(*) from pg_stat_activity where application_name = 'dvr_holder' and state = 'active' and wait_event = 'PgSleep'")" = "1" ] \
  || fail "(a) the holder session let go of a's row before the hour ended: the hour was not run against a held row"
[ "$(field "$r1" paid)" = "$B_HOUR" ] || fail "(a) the hour paid $(field "$r1" paid) d., not b's $B_HOUR d. alone"
[ "$(field "$r1" holders)" = "1" ] || fail "(a) the hour paid $(field "$r1" holders) players, not b alone"
expect_state "(a) a skipped and nothing of hers moved, b paid" \
  "0 | $B_HOUR | $A_LEFT | $((B_LEFT - B_HOUR)) | $A_LEFT | 0 | 1 | -1 | 0"
echo "PASS: DIVIDEND_RACE_SKIPPED_HOLDER_OWED"

end_session dvr_holder   # her row is free again (her transaction ends without a change)
wait_for "the holder session is gone" "select (count(*) = 0)::int from pg_stat_activity where application_name = 'dvr_holder'"

r2="$(run_hour 1 2> "$OUT/hour2.err")" || fail "(a) the next hour failed: $(cat "$OUT/hour2.err")"
echo "(a) the next hour, a free: $r2"
[ "$(field "$r2" paid)" = "$((A_HOUR + B_HOUR))" ] || fail "(a) the next hour paid $(field "$r2" paid) d., not a's $A_HOUR d. + b's $B_HOUR d."
expect_state "(a) the next hour paid her; the missed hour's coin is still hers, set aside" \
  "$A_HOUR | $((2 * B_HOUR)) | $((A_LEFT - A_HOUR)) | $((B_LEFT - 2 * B_HOUR)) | $((A_LEFT - A_HOUR)) | 1 | 2 | 1 | 1"
# an arrival collects all that is left, the missed hour with it, once: she then holds the whole coupon and not a coin more
got="$(q "select public.collect_coupons('$A', '$PORT', null)")"
[ "$got" = "$((A_LEFT - A_HOUR))" ] || fail "(a) the arrival collected $got d., not the $((A_LEFT - A_HOUR)) d. left"
expect_state "(a) the arrival collected the rest: the whole coupon is hers, once" \
  "$A_LEFT | $((2 * B_HOUR)) | $((A_LEFT - A_HOUR)) | $((B_LEFT - 2 * B_HOUR)) | 0 | 2 | 2 | 1 | 1"
echo "PASS: DIVIDEND_RACE_OWED_HOUR_PAID_ONCE"

# ── 3. (b) TWO SESSIONS RUN THE SAME HOUR AT ONCE ──
# the gate: a session-level advisory lock the first caller waits for AFTER it has paid, so its transaction stays open
PGAPPNAME=dvr_gate psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q > "$OUT/gate.log" 2>&1 <<SQL &
select pg_advisory_lock($GATE_KEY);
select pg_sleep(300);
SQL
wait_for "the gate is shut" \
  "select count(*) from pg_stat_activity where application_name = 'dvr_gate' and state = 'active' and wait_event = 'PgSleep'"

PGAPPNAME=dvr_first psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA > "$OUT/first.out" 2> "$OUT/first.err" <<SQL &
begin;
select public.city_coupon_hour(to_timestamp($T0 + 7200));
select pg_advisory_lock($GATE_KEY);
commit;
SQL
FIRST=$!
wait_for "the first caller has run the hour and holds its transaction open at the gate" \
  "select count(*) from pg_stat_activity where application_name = 'dvr_first' and wait_event_type = 'Lock' and wait_event = 'advisory'
      and query like 'select pg_advisory_lock%'"
expect_state "(b) the first caller has not committed" \
  "$A_LEFT | $((2 * B_HOUR)) | $((A_LEFT - A_HOUR)) | $((B_LEFT - 2 * B_HOUR)) | 0 | 2 | 2 | 1 | 1"

# the second caller of the same hour, while the first still holds the rows: it must not wait, and must pay nothing
r4="$(PGAPPNAME=dvr_second psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA -c "set lock_timeout = '5s'" \
  -c "select public.city_coupon_hour(to_timestamp($T0 + 7200))" 2> "$OUT/second.err")" \
  || fail "(b) the second caller failed or waited (lock_timeout 5 s): $(cat "$OUT/second.err")"
echo "(b) the second caller, the first still open: $r4"
[ "$(q "select count(*) from pg_stat_activity where application_name = 'dvr_first' and wait_event_type = 'Lock' and wait_event = 'advisory'")" = "1" ] \
  || fail "(b) the first caller ended before the second answered: the two did not overlap"
[ "$(field "$r4" paid)" = "0" ] || fail "(b) the second caller paid $(field "$r4" paid) d. while the first held the hour"

end_session dvr_gate   # the gate opens: the first caller commits
wait "$FIRST" || fail "(b) the first caller failed: $(cat "$OUT/first.err")"
r3="$(grep -m1 '^{' "$OUT/first.out" || true)"
echo "(b) the first caller: $r3"
[ -n "$r3" ] || fail "(b) the first caller gave no answer"
[ "$(field "$r3" paid)" = "$B_HOUR" ] || fail "(b) the first caller paid $(field "$r3" paid) d., not b's $B_HOUR d. (a has nothing left)"
r5="$(run_hour 2 2> "$OUT/third.err")" || fail "(b) the third caller failed: $(cat "$OUT/third.err")"
echo "(b) a third caller of the same hour, after the commit: $r5"
[ "$(field "$r5" paid)" = "0" ] || fail "(b) the third caller paid $(field "$r5" paid) d.: the hour was paid twice"
expect_state "(b) the hour paid once (a's mark cleared: an arrival had collected it all)" \
  "$A_LEFT | $((3 * B_HOUR)) | 0 | $((B_LEFT - 3 * B_HOUR)) | 0 | 2 | 3 | 2 | 2"
echo "PASS: DIVIDEND_RACE_SAME_HOUR_PAYS_ONCE"

echo "dividend-race: all three passed on $(q "select version()" | cut -d' ' -f1-2), two sessions."
