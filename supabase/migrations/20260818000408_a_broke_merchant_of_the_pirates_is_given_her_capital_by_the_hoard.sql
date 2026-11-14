-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0408 - A BROKE MERCHANT OF THE PIRATES IS GIVEN HER CAPITAL BY THE HOARD  (the gift pass no longer leaves the pirates out; Port Royal pays, through public.pirate_pay)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- WHY (prod, read-only, 2026-11-14 08:26 UTC, head 0407; docs/dev-log/2026-11-14-pirate-gift.md):
--   24 merchant houses sail for the pirates (0341). 14 of them are broke (purse under merchant_broke_pct 20 % of their capital of 250,000), 13 with a
--   purse under 100 d. and laid up. None was ever gifted: 0341 left the pirates out of the capital's gift pass (one line in public.capital_gift_roster,
--   "the hoard pays her founding and nothing after, decided by default"; its dev-log: "routing the gift through pirate_pay (within the cap) is one more
--   hunk if the owner wants a broke pirate merchant refilled"). The owner, 2026-11-14: "do all"; then, of the pirates: "make them trade too".
--   So a broke merchant of the pirates is refilled as every merchant is. DECIDED BY DEFAULT (the owner may reverse it).
--
-- WHAT THIS FILE DOES (three hunks over two bodies; nothing else):
--   1. public.capital_gift_roster: 0341's line goes. A merchant of the pirates is on the roster by the same rule as every merchant: purse under
--      merchant_broke_pct x her capital, no gift in gift_cooldown_hours (24), fewer than gift_max_per_week (3) in seven days, gift_max_per_hour (50) a pass.
--   2. public.capital_gift_one: a merchant house of the pirate power is paid her capital by THE one payer of the hoard, public.pirate_pay (0339), as the
--      moved kind CAPITAL_GIFT: from Port Royal's purse, whole or nothing, inside THE one cap public.pirate_spend_room (pirate_spend_day_pct of the hoard a
--      UTC day), written to the day's spend. Never public.capital_pays for her: no CROWN_CALL from another harbour, nothing outside the cap. Everything
--      after the payment is the pass's own, unchanged: the public.capital_gifts row (which counts her week), the debts she owes paid first
--      (public.port_fee_collect), the news (public.news_gift). Her CAPITAL_GIFT event carries the same payload as every gift's.
--      When the hoard cannot pay her now (the day's room, Port Royal's surplus, its purse busy, or the pirates dark) NOTHING is written and she is counted
--      in gift_waiting: she is asked again at the next pass. No GIFT_WAITING event for her (a busy purse is not news).
--   A company (a player) sailing for the pirates is paid as before (public.capital_pays): untouched.
--
-- NOTHING IS MINTED: the gift is a city paying a house (public.city_pays inside public.pirate_pay), as PIRATE_FOUND is.
-- NO KNOB, NO TABLE, NO NEW WORD (CAPITAL_GIFT is the moved kind every gift uses). No function's signature, grants or volatility move.
-- WHAT IT COSTS THE HOARD: 250,000 a gift. 14 broke houses now: 3,500,000 at most in the first passes (the day's room was 4,788,292 at the read, and
--   the ships' hourly pay comes out of the same room, so the last of them may wait for the next UTC day). At the worst, every one of 24 houses three
--   times a week: 18,000,000 a week of a hoard of 980,000,000. The money goes to the harbours they trade at: the economy stays closed.
-- LOCKS: CREATE OR REPLACE x2 by hunks. TIME: milliseconds; the probe gives ONE broke merchant of the pirates her gift in a rolled-back
--   sub-transaction. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/pirate-gift/rollback-0408.sql, a draft (the three hunks reversed). There is no knob for this
--   rule alone: gift_max_per_week 0 would stop every gift, the crowns' too.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe, which
--   reads only its own rows (the one gift row and the one ledger row it wrote, by her house and this transaction's instant).
-- VERSION: 0408 = 0407 + 1.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.capital_gift_roster(timestamp with time zone,uuid)', 'public.capital_gift_one(timestamp with time zone,uuid)'];
  v_t0        timestamptz := clock_timestamp();
  v_now       timestamptz := now();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_player    uuid;
  v_capital   bigint;
  v_spent     bigint;
  v_r         jsonb;
  v_note      text := 'no broke merchant of the pirates to probe in this world';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)') is null or to_regprocedure('public.pirate_power(uuid)') is null
     or to_regprocedure('public.news_gift(uuid,uuid,bigint,timestamp with time zone)') is null then
    raise exception '0408 refuses: the hoard''s payer (0339) or the gift''s news (0362) is not in this world';
  end if;
  if position('0408' in pg_get_functiondef('public.capital_gift_one(timestamp with time zone,uuid)'::regprocedure)) > 0 then
    raise exception '0408 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0408 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0408
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE HUNKS ──
  create temp table hunk_0408 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0408 values
  (1, c_cut[1],
$h$       and (h.human or not public.pirate_power(pl.nation_id))   -- 0341 (W18): a merchant of the pirates is never gifted: the hoard pays her founding and nothing after (docs/WORLD_POWERS.md 7.4, decided by default)
$h$,
$h$       -- 0408: a merchant of the pirates is on the roster as every merchant is (0341's "never gifted" line stood here): public.capital_gift_one pays her from the hoard, through public.pirate_pay
$h$),
  (2, c_cut[2],
$h$      v_res := public.capital_pays(r.cap_id, r.nation_id, r.player_id, 'CAPITAL_GIFT', r.capital, null, false,
                 jsonb_build_object('kind', 'CAPITAL_GIFT', 'payload', jsonb_build_object(
                   'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth)));
$h$,
$h$      -- 0408: A MERCHANT HOUSE OF THE PIRATES is paid by THE one payer of the hoard, public.pirate_pay (0339): from the pirate capital's purse, whole
      -- or nothing, inside THE one cap public.pirate_spend_room; never by public.capital_pays (no CROWN_CALL, nothing outside the cap). Short of her
      -- whole capital (the day's room, the capital's surplus, its purse busy, the pirates dark) nothing is written and she waits for a later pass.
      -- The rows after the payment are every gift's. A company (a player) sailing for the pirates is paid as before, below.
      if public.pirate_power(r.nation_id) and exists (select 1 from public.npc_houses nh where nh.player_id = r.player_id) then
        if r.cap_id is distinct from public.pirate_capital()
           or public.pirate_pay('CAPITAL_GIFT', r.capital, p_now, p_player := r.player_id) < r.capital then
          raise exception using errcode = 'ZG408', message = 'the hoard cannot pay her now';
        end if;
        perform public.emit_event(r.player_id, 'CAPITAL_GIFT', jsonb_build_object(
          'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth, 'called_from', null));
        v_res := '{}'::jsonb;
      else
      v_res := public.capital_pays(r.cap_id, r.nation_id, r.player_id, 'CAPITAL_GIFT', r.capital, null, false,
                 jsonb_build_object('kind', 'CAPITAL_GIFT', 'payload', jsonb_build_object(
                   'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth)));
      end if;   -- 0408
$h$),
  (3, c_cut[2],
$h$      when others then
        v_fail := v_fail + 1;
$h$,
$h$      when sqlstate 'ZG408' then
        -- 0408: THE HOARD CANNOT PAY HER NOW: no money moved, nothing written (public.pirate_pay's whole or nothing); she is asked again next pass
        v_wait := v_wait + 1;
      when others then
        v_fail := v_fail + 1;
$h$);
  for h in select * from hunk_0408 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0408 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0408 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0408 p where p.fn = h.fn) then
      raise exception '0408 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0408 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0408 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0408 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0408 self-assert FAIL: another function moved';
  end if;

  -- ── 3. THE PROBE: ONE broke merchant house of the pirates, never gifted in eight days, is given her turn in the pass, and it is rolled back.
  --      Read: only her own rows of this instant (the gift row, the ledger row), and the day's one spend row before and after.
  if public.economy_closed() and public.pirates_on() and public.pirate_capital() is not null then
    select nh.player_id, nh.capital into v_player, v_capital
      from public.npc_houses nh join public.players pl on pl.id = nh.player_id and pl.is_npc
     where public.pirate_power(pl.nation_id)
       and pl.ducats < nh.capital * public.wc_num('merchant_broke_pct')
       and not exists (select 1 from public.capital_gifts g where g.player_id = nh.player_id and g.created_at > v_now - interval '8 days')
     order by pl.ducats, nh.roster_ord
     limit 1;
  end if;
  if v_player is not null then
    begin
      if not exists (select 1 from public.capital_gift_roster(v_now, v_player) g) then
        raise exception '0408 self-assert FAIL: a broke merchant of the pirates, never gifted, is not on the gift roster';
      end if;
      v_spent := coalesce((select d.spent from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date), 0);
      v_r := public.capital_gift_one(v_now, v_player);
      if (v_r->>'gifted')::int = 1 and (v_r->>'failed')::int = 0 and (v_r->>'gift_waiting')::int = 0 then
        if (v_r->>'gift_ducats')::bigint <> v_capital
           or (select count(*) from public.capital_gifts g where g.player_id = v_player and g.created_at = v_now
                  and g.port_id = public.pirate_capital() and g.ducats = v_capital and g.called_from is null) <> 1
           or (select count(*) from public.ledger l where l.player_id = v_player and l.kind = 'CAPITAL_GIFT' and l.ducats_delta = v_capital and l.created_at >= v_now) <> 1
           or coalesce((select d.spent from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date), 0) <> v_spent + v_capital
           or exists (select 1 from public.capital_gift_roster(v_now, v_player) g) then
          raise exception '0408 self-assert FAIL: her gift is not one gift row and one ledger row of her capital from the pirate capital, written to the day''s spend, and she off the roster after: %', v_r;
        end if;
        v_note := 'one broke merchant of the pirates was given her capital of ' || v_capital || ' d. by the hoard (one gift row, one ledger row, the day''s spend up by it, off the roster after), rolled back';
      elsif (v_r->>'gifted')::int = 0 and (v_r->>'failed')::int = 0 and (v_r->>'gift_waiting')::int = 1 then
        if exists (select 1 from public.capital_gifts g where g.player_id = v_player and g.created_at = v_now)
           or coalesce((select d.spent from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date), 0) <> v_spent then
          raise exception '0408 self-assert FAIL: the hoard could not pay her and something was written: %', v_r;
        end if;
        v_note := 'one broke merchant of the pirates was on the roster; the hoard could not pay her at this instant (the day''s room, or its purse busy): she waits, nothing written';
      else
        raise exception '0408 self-assert FAIL: her turn in the pass answered %', v_r;
      end if;
      raise exception sqlstate 'BV408';
    exception when sqlstate 'BV408' then null;
    end;
    if exists (select 1 from public.capital_gifts g where g.player_id = v_player and g.created_at = v_now) then
      raise exception '0408 self-assert FAIL: the probe was not rolled back';
    end if;
    if v_note not like 'one broke merchant%' then
      raise exception '0408 self-assert FAIL: the probe did not run to its end';
    end if;
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0408 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0408 self-assert ok: A BROKE MERCHANT OF THE PIRATES IS GIVEN HER CAPITAL BY THE HOARD. Three hunks over two bodies, each once and reversing; grants and volatility unmoved; no other function moved. Probe: %; % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
