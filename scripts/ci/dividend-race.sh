#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# dividend-race.sh: the hourly dividend (0495) under TWO SESSIONS, on real PostgreSQL
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WHY: 0495's self-assert and proof 198 run on PGlite, which has ONE session, so two money paths were
# read and never run (docs/dev-log/2026-11-24-dividend-hourly.md, "Not verified"):
#   (a) a holder's purse row (public.players) is held by another session when the hour runs: the
#       hour must not wait for her, must pay the others, and must write the hour against her
#       (port_treasury.coupon_owed) so her next coupon carries it, once;
#   (b) two sessions run the same hour of the same harbour at once: the second must wait on the purse
#       row and then find the hour closed. One payment, not two.
# This runs both, with real sessions (psql), through public.city_coupons: the call public.tick_city
# makes for a harbour. It does not run public.tick_city itself (the tick over the whole world).
#
# WHAT IT TOUCHES: it COMMITS (a second session cannot see uncommitted rows): two probe houses, one
# purse and two share rows at a SEA_PLACE that has none, three knobs lit for the run and put back at
# the end, and the ledger / flow rows of the payments (append-only: they stay). So it REFUSES any
# database that is not on this machine (127.0.0.1 / localhost), and CI runs it AFTER the applied chain
# is kept as a snapshot: nothing it commits is ever restored anywhere. The stack is thrown away after.
# Its hours are ten days ahead, so a cron tick of the real hour finds the probe's hour already closed.
#
# HOW THE SESSIONS ARE STEERED (no sleeps to guess with): every step waits until pg_stat_activity shows
# the other session exactly where it must be (holding in pg_sleep, waiting on the gate's advisory lock,
# or blocked by the first caller: pg_blocking_pids), and is released by ending the session that holds it.
#
# RUNS ONLY WHEN THE DIVIDEND FUNCTIONS EXIST: a chain without 0495 prints SKIPPED and exits 0.
# GREEN is the three "PASS: DIVIDEND_RACE_*" lines (the workflow greps for them), not exit 0.
#   DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres bash scripts/ci/dividend-race.sh
# ═══════════════════════════════════════════════════════════════════════════════════════════════
set -euo pipefail

: "${DB_URL:?DB_URL (the disposable stack) required}"
case "$DB_URL" in
  *@127.0.0.1:*|*@127.0.0.1/*|*@localhost:*|*@localhost/*) ;;
  *) echo "::error title=dividend-race::refusing: DB_URL is not a database on this machine (this test commits rows)"; exit 1 ;;
esac

OUT="$(mktemp -d)"
GATE_KEY=4950495
PURSE=10000000
A_PAID=461384
B_PAID=1000000

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

KNOBS_SAVED=""
cleanup() {
  local rc=$?
  set +e
  q "select count(pg_terminate_backend(pid)) from pg_stat_activity where application_name like 'dvr_%' and pid <> pg_backend_pid()" > /dev/null 2>&1
  if [ -n "$KNOBS_SAVED" ]; then
    q "update public.world_config c set value = s.value
         from jsonb_each('$KNOBS_SAVED'::jsonb) s where c.key = s.key and c.value is distinct from s.value" > /dev/null \
      || echo "::warning title=dividend-race::the three knobs were not put back (the stack is disposable)"
  fi
  wait 2> /dev/null
  rm -rf "$OUT"
  exit "$rc"
}
trap cleanup EXIT

# ── 0. ONLY WHEN THE DIVIDEND FUNCTIONS EXIST ──
have="$(q "select to_regprocedure('public.city_coupon_hour(uuid,timestamptz)') is not null
              and to_regprocedure('public.city_coupons(uuid,timestamptz)') is not null
              and to_regprocedure('public.dividend_hourly_on()') is not null
              and to_regprocedure('public.coupon_day_of(uuid,uuid,numeric)') is not null")"
if [ "$have" != "t" ]; then
  echo "DIVIDEND_RACE SKIPPED: this chain has no hourly dividend (public.city_coupon_hour): nothing to race"
  exit 0
fi
if [ "$(q "select count(*) from public.players where company_name in ('Race 0495 a', 'Race 0495 b')")" != "0" ]; then
  fail "the probe houses are already in this database: it has been used by this test once (use a fresh stack)"
fi

# ── 1. THE SCENE, COMMITTED (0495's own scene: a SEA_PLACE as the city, two houses with no fleet) ──
KNOBS_SAVED="$(q "select jsonb_object_agg(c.key, c.value) from public.world_config c
                   where c.key in ('city_treasury_enabled', 'dividend_hourly_enabled', 'works_coupon_day')")"
[ -n "$KNOBS_SAVED" ] || fail "the three knobs could not be read"

scene="$(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA --single-transaction \
  -c "update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'dividend_hourly_enabled')" \
  -c "update public.world_config set value = to_jsonb(0.018) where key = 'works_coupon_day'" \
  -c "with port as (
        select p.id from public.ports p
         where p.kind = 'SEA_PLACE'
           and not exists (select 1 from public.port_treasury t where t.port_id = p.id)
           and not exists (select 1 from public.city_shares cs where cs.port_id = p.id)
           and not exists (select 1 from public.treasury_flows f where f.port_id = p.id)
         order by p.code limit 1
      ), nat as (   -- a country that does not hold the place: the multiplier of 0148 is 1 for the probes
        select g.nation_id from public.great_powers g, port
         where g.nation_id is distinct from public.port_nation(port.id) order by g.nation_id limit 1
      ), clock as (    -- ten days ahead, on the hour: a cron tick of the real hour finds the hour of this purse closed
        select extract(epoch from date_trunc('hour', now()) + interval '10 days')::bigint as t0
      ), a as (
        insert into public.players (company_name, nation_id, ducats, is_npc)
        select 'Race 0495 a', nat.nation_id, 0, false from nat returning id
      ), b as (
        insert into public.players (company_name, nation_id, ducats, is_npc)
        select 'Race 0495 b', nat.nation_id, 0, false from nat returning id
      ), purse as (   -- the profit of the last hour covers every due below (24,000,000 / 24 = 1,000,000 an hour)
        insert into public.port_treasury (port_id, ducats, reserve, profit, coupon_day, coupon_hour)
        select port.id, $PURSE, 1000, 24000000, public.real_day(to_timestamp(clock.t0)), public.real_hour(to_timestamp(clock.t0)) - 1
          from port, clock returning port_id
      ), sh as (
        insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
        select port.id, 'docks', a.id, 10, $A_PAID, 0, world.game_day(now()) - 1000 from port, a
        union all
        select port.id, 'market', b.id, 30, $B_PAID, 0, world.game_day(now()) - 1000 from port, b
        returning 1
      )
      select port.id || ' ' || a.id || ' ' || b.id || ' ' || clock.t0 || ' ' || (select count(*) from purse) + (select count(*) from sh)
        from port, a, b, clock")" || fail "the scene could not be written"
read -r PORT A B T0 ROWS <<< "$scene" || true
[ -n "${T0:-}" ] && [ "${ROWS:-}" = "3" ] || fail "the scene is not whole (no free SEA_PLACE, or no second country): '$scene'"
echo "scene: harbour $PORT, holder a $A ($A_PAID d.), holder b $B ($B_PAID d.), first hour at epoch $T0"

# what each is due, by the rule's one home (public.coupon_day_of), exactly as public.city_coupon_hour rounds it
read -r DUE_A DUE_A2 DUE_B <<< "$(q "select round(public.coupon_day_of('$PORT', '$A', $A_PAID::numeric) / 24)::bigint || ' '
                                         || round(public.coupon_day_of('$PORT', '$A', $A_PAID::numeric) / 24 * 2)::bigint || ' '
                                         || round(public.coupon_day_of('$PORT', '$B', $B_PAID::numeric) / 24)::bigint")" || true
[ "${DUE_A:-0}" -gt 0 ] && [ "${DUE_B:-0}" -gt 0 ] && [ "${DUE_A2:-0}" -gt "$DUE_A" ] || fail "the dues are not positive: a ${DUE_A:-?}, a with one owed hour ${DUE_A2:-?}, b ${DUE_B:-?}"
echo "due an hour: a $DUE_A d. (with one owed hour: $DUE_A2 d.), b $DUE_B d."

# a's purse | b's purse | the owed hours | what the city's purse fell by | a's DIVIDEND rows | b's | the last paid hour, from T0
state() {
  q "select (select pl.ducats from public.players pl where pl.id = '$A') || ' | ' ||
            (select pl.ducats from public.players pl where pl.id = '$B') || ' | ' ||
            (select t.coupon_owed::text from public.port_treasury t where t.port_id = '$PORT') || ' | ' ||
            ($PURSE - public.treasury_balance('$PORT')) || ' | ' ||
            (select count(*) from public.ledger l where l.player_id = '$A' and l.kind = 'DIVIDEND') || ' | ' ||
            (select count(*) from public.ledger l where l.player_id = '$B' and l.kind = 'DIVIDEND') || ' | ' ||
            (select t.coupon_hour - public.real_hour(to_timestamp($T0)) from public.port_treasury t where t.port_id = '$PORT')"
}
expect_state() {   # <when> <expected>
  local got; got="$(state)"
  [ "$got" = "$2" ] || fail "$1: the money is not where it must be.  expected: $2   got: $got"
  echo "  ok, $1: $got"
}
field() { q "select coalesce(('$1'::jsonb ->> '$2'), 'null')"; }   # one key of an answer of public.city_coupons
run_hour() {   # <hours after T0>: one session, autocommit, never waiting more than 5 s for anything
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA -c "set lock_timeout = '5s'" \
    -c "select public.city_coupons('$PORT', to_timestamp($T0 + 3600 * $1))"
}

expect_state "before any hour" "0 | 0 | {} | 0 | 0 | 0 | -1"

# ── 2. (a) A HOLDER'S ROW IS HELD BY ANOTHER SESSION WHEN THE HOUR RUNS ──
PGAPPNAME=dvr_holder psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q > "$OUT/holder.log" 2>&1 <<SQL &
begin;
select id from public.players where id = '$A' for update;
select pg_sleep(300);
SQL
wait_for "the holder session holds a's row" \
  "select count(*) from pg_stat_activity where application_name = 'dvr_holder' and state = 'active' and wait_event = 'PgSleep'"

r1="$(run_hour 0 2> "$OUT/hour1.err")" || fail "(a) the hour failed or waited for the held holder (lock_timeout 5 s): $(cat "$OUT/hour1.err")"
echo "(a) the hour, a's row held: $r1"
[ "$(q "select count(*) from pg_stat_activity where application_name = 'dvr_holder' and state = 'active' and wait_event = 'PgSleep'")" = "1" ] \
  || fail "(a) the holder session let go of a's row before the hour ended: the hour was not run against a held row"
[ "$(field "$r1" paid)" = "$DUE_B" ] || fail "(a) the hour paid $(field "$r1" paid) d., not b's $DUE_B d. alone"
[ "$(field "$r1" due)" = "$((DUE_A + DUE_B))" ] || fail "(a) the hour's due is $(field "$r1" due) d., not $((DUE_A + DUE_B)) d."
expect_state "(a) a skipped, b paid, the hour written against a" "0 | $DUE_B | {\"$A\": 1} | $DUE_B | 0 | 1 | 0"
echo "PASS: DIVIDEND_RACE_SKIPPED_HOLDER_OWED"

end_session dvr_holder   # her row is free again (her transaction ends without a change)
wait_for "the holder session is gone" "select (count(*) = 0)::int from pg_stat_activity where application_name = 'dvr_holder'"

r2="$(run_hour 1 2> "$OUT/hour2.err")" || fail "(a) the next hour failed: $(cat "$OUT/hour2.err")"
echo "(a) the next hour, a free: $r2"
[ "$(field "$r2" paid)" = "$((DUE_A2 + DUE_B))" ] || fail "(a) the next hour paid $(field "$r2" paid) d., not a's two hours $DUE_A2 d. + b's $DUE_B d."
expect_state "(a) the owed hour paid with the next, and cleared" "$DUE_A2 | $((2 * DUE_B)) | {} | $((DUE_A2 + 2 * DUE_B)) | 1 | 2 | 1"
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
select public.city_coupons('$PORT', to_timestamp($T0 + 7200));
select pg_advisory_lock($GATE_KEY);
commit;
SQL
FIRST=$!
wait_for "the first caller has run the hour and holds its transaction open at the gate" \
  "select count(*) from pg_stat_activity where application_name = 'dvr_first' and wait_event_type = 'Lock' and wait_event = 'advisory'
      and query like 'select pg_advisory_lock%'"
expect_state "(b) the first caller has not committed" "$DUE_A2 | $((2 * DUE_B)) | {} | $((DUE_A2 + 2 * DUE_B)) | 1 | 2 | 1"

PGAPPNAME=dvr_second psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qtA -c "set lock_timeout = '60s'" \
  -c "select public.city_coupons('$PORT', to_timestamp($T0 + 7200))" > "$OUT/second.out" 2> "$OUT/second.err" &
SECOND=$!
wait_for "the second caller of the same hour waits, blocked by the first" \
  "select count(*) from pg_stat_activity s
    where s.application_name = 'dvr_second' and s.wait_event_type = 'Lock'
      and (select f.pid from pg_stat_activity f where f.application_name = 'dvr_first') = any (pg_blocking_pids(s.pid))"
[ ! -s "$OUT/second.out" ] || fail "(b) the second caller answered while the first still held the hour: $(cat "$OUT/second.out")"

end_session dvr_gate   # the gate opens: the first caller commits, then the second goes on
wait "$FIRST"  || fail "(b) the first caller failed: $(cat "$OUT/first.err")"
wait "$SECOND" || fail "(b) the second caller failed: $(cat "$OUT/second.err")"
r3="$(grep -m1 '^{' "$OUT/first.out" || true)"
r4="$(grep -m1 '^{' "$OUT/second.out" || true)"
echo "(b) the first caller: $r3"
echo "(b) the second caller: $r4"
[ -n "$r3" ] && [ -n "$r4" ] || fail "(b) a caller gave no answer"
[ "$(field "$r3" paid)" = "$((DUE_A + DUE_B))" ] || fail "(b) the first caller paid $(field "$r3" paid) d., not $((DUE_A + DUE_B)) d."
[ "$(field "$r4" paid)" = "0" ] && [ "$(field "$r4" cap)" = "null" ] \
  || fail "(b) the second caller did not find the hour closed (it must answer paid 0 with no cap): $r4"
expect_state "(b) the hour paid once" "$((DUE_A2 + DUE_A)) | $((3 * DUE_B)) | {} | $((DUE_A2 + DUE_A + 3 * DUE_B)) | 2 | 3 | 2"
echo "PASS: DIVIDEND_RACE_SAME_HOUR_PAYS_ONCE"

echo "dividend-race: all three passed on $(q "select version()" | cut -d' ' -f1-2), two sessions."
