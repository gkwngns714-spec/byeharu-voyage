-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 103 - A BROKE MERCHANT OF THE PIRATES IS GIVEN HER CAPITAL BY THE HOARD  (migration 0408; docs/dev-log/2026-11-14-pirate-gift.md)
--
--   The real job founds one merchant of the pirates (proof 47's scene); she is made broke by a moved payment, and the REAL gift pass
--   (public.capital_gift_pass, narrowed to her) is run at chosen instants. Rolled back with proof.mjs's transaction.
--
-- @pass PG_ROSTER  a broke merchant of the pirates is on the capital's gift roster, alone and in the whole pass's roster
-- @pass PG_ROOM    with the day's room at nothing the hoard cannot pay her: gifted 0, waiting 1, failed 0, and nothing written (no gift row, no ledger row, no event, her purse and the day's spend unmoved)
-- @pass PG_PAID    with room she is paid her capital of 250,000 by Port Royal through public.pirate_pay: one gift row, one CAPITAL_GIFT ledger row and event of hers, the same out of Port Royal's purse and into the day's spend, no CROWN_CALL
-- @pass PG_WEEK    the pass's own limits hold for her: nothing an hour after a gift (the cooldown); a second and a third gift a day apart; no fourth inside seven days; a fourth once the first is seven days old
-- @pass PG_CROWN   a broke crown merchant's turn is what it was: on the roster, never failed, and the hoard's spend book does not move for her
-- @pass PG_MONEY   W (purses + companies + funds aboard) is unchanged to the ducat across every gift above
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.w_103() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;
create function pg_temp.spent_103() returns bigint language sql as $f$
  select coalesce(sum(d.spent), 0)::bigint from public.pirate_spend_day d
$f$;

do $p$
declare
  c_uid    constant uuid := '00000000-0103-4000-8000-000000000001';
  v_por    uuid := (select p.id from public.ports p where p.code = 'POR');
  v_t0     timestamptz := now();
  v_t      timestamptz;
  v_rich   uuid;
  v_m      uuid;
  v_home   uuid;
  v_ctl    uuid;
  v_ctl_home uuid;
  v_r      jsonb;
  v_w0     numeric;
  v_s0     bigint;
  v_purse  bigint;
  v_k      int;
begin
  -- ── THE SCENE (proof 47's): purses lit, Port Royal funded by a rich probe founded while the economy is open, then closed, merchants and pirates lit ──
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  v_rich := public.new_house(c_uid, 'Casa Rica 0103', 'PRT', 'LIS', 'Rica', 'barca', 'Rica', 2000000000, false);
  perform public.pay_city(v_rich, v_por, 'TAX', 1000000000);
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'npc_traders_enabled', 'standing_routes_enabled', 'influence_enabled', 'pirates_bite');
  update public.world_config set value = to_jsonb(3) where key = 'gift_max_per_week';
  update public.world_config set value = to_jsonb(24) where key = 'gift_cooldown_hours';
  if not public.pirates_on() or not public.economy_closed() or public.pirate_capital() is distinct from v_por then
    raise exception 'proof 103: the pirates cannot be lit in this world, or their capital is not Port Royal';
  end if;
  v_r := public.tick_pirate_merchants(v_t0);
  v_m := (v_r->>'founded')::uuid;
  if v_m is null or not public.pirate_merchant(v_m) or (select h.capital from public.npc_houses h where h.player_id = v_m) <> 250000 then
    raise exception 'proof 103: no merchant of the pirates was founded: %', v_r;
  end if;
  select h.home_port_id into v_home from public.npc_houses h where h.player_id = v_m;
  v_w0 := pg_temp.w_103();

  -- ── PG_ROSTER ── (her purse to her home, moved: 5,000 d. of 250,000 is under the line of 20 %)
  perform public.pay_city(v_m, v_home, 'TAX', (select pl.ducats - 5000 from public.players pl where pl.id = v_m));
  v_t := v_t0 + interval '4 hours';
  if not exists (select 1 from public.capital_gift_roster(v_t, v_m) g where g.cap_id = v_por and g.capital = 250000)
     or not exists (select 1 from public.capital_gift_roster(v_t) g where g.player_id = v_m) then
    raise exception 'PG_ROSTER: the broke merchant of the pirates is not on the gift roster';
  end if;
  raise notice 'PASS: PG_ROSTER the broke merchant of the pirates (5,000 d. of 250,000) is on the roster, alone and in the whole pass''s, her payer Port Royal';

  -- ── PG_ROOM ── (the day's room at nothing: the knob moved inside this rolled-back proof)
  update public.world_config set value = to_jsonb(0) where key = 'pirate_spend_day_pct';
  v_s0 := pg_temp.spent_103();
  v_r := public.capital_gift_pass(v_t, v_m);
  if (v_r->>'gifted')::int <> 0 or (v_r->>'gift_waiting')::int <> 1 or (v_r->>'failed')::int <> 0
     or exists (select 1 from public.capital_gifts g where g.player_id = v_m)
     or exists (select 1 from public.ledger l where l.player_id = v_m and l.kind = 'CAPITAL_GIFT')
     or exists (select 1 from public.events e where e.player_id = v_m and e.kind in ('CAPITAL_GIFT', 'GIFT_WAITING'))
     or (select pl.ducats from public.players pl where pl.id = v_m) <> 5000
     or pg_temp.spent_103() <> v_s0 or pg_temp.w_103() <> v_w0 then
    raise exception 'PG_ROOM: with no room the pass answered % or wrote something', v_r - 'notes';
  end if;
  update public.world_config set value = to_jsonb(0.005) where key = 'pirate_spend_day_pct';
  raise notice 'PASS: PG_ROOM with the day''s room at nothing: gifted 0, waiting 1, failed 0; no gift row, no ledger row, no event, her purse 5,000 and the spend book unmoved';

  -- ── PG_PAID ──
  v_r := public.capital_gift_pass(v_t, v_m);
  if (v_r->>'gifted')::int <> 1 or (v_r->>'gift_ducats')::bigint <> 250000 or (v_r->>'gift_waiting')::int <> 0 or (v_r->>'failed')::int <> 0
     or (select pl.ducats from public.players pl where pl.id = v_m) <> 255000
     or (select count(*) from public.capital_gifts g where g.player_id = v_m and g.port_id = v_por and g.ducats = 250000 and g.called_from is null and g.created_at = v_t) <> 1
     or (select count(*) from public.ledger l where l.player_id = v_m and l.kind = 'CAPITAL_GIFT' and l.ducats_delta = 250000) <> 1
     or (select count(*) from public.events e where e.player_id = v_m and e.kind = 'CAPITAL_GIFT' and e.payload->>'port' = 'POR' and (e.payload->>'ducats')::bigint = 250000) <> 1
     or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.port_id = v_por and f.kind = 'CAPITAL_GIFT') <> -250000
     or exists (select 1 from public.treasury_flows f where f.kind = 'CAPITAL_GIFT' and f.port_id <> v_por)
     or exists (select 1 from public.treasury_flows f where f.kind = 'CROWN_CALL' and f.created_at >= v_t0)
     or pg_temp.spent_103() <> v_s0 + 250000
     or (select d.spent from public.pirate_spend_day d where d.day = (v_t at time zone 'UTC')::date) < 250000
     or pg_temp.w_103() <> v_w0 then
    raise exception 'PG_PAID: her gift is not 250,000 d. from Port Royal through the hoard''s payer: % (purse %, spend % -> %, W % -> %)', v_r - 'notes',
      (select pl.ducats from public.players pl where pl.id = v_m), v_s0, pg_temp.spent_103(), v_w0, pg_temp.w_103();
  end if;
  raise notice 'PASS: PG_PAID 250,000 d. from Port Royal''s purse to her (purse 5,000 -> 255,000): one gift row, one ledger row, one event, the day''s spend up by it, no CROWN_CALL, W unchanged';

  -- ── PG_WEEK ── (broke again each time, by a moved payment; the pass's own cooldown and week)
  perform public.pay_city(v_m, v_home, 'TAX', 250000);
  v_r := public.capital_gift_pass(v_t + interval '1 hour', v_m);
  if (v_r->>'gifted')::int <> 0 or (v_r->>'gift_waiting')::int <> 0 or exists (select 1 from public.capital_gift_roster(v_t + interval '1 hour', v_m) g) then
    raise exception 'PG_WEEK: an hour after her gift the pass answered %', v_r - 'notes';
  end if;
  for v_k in 1 .. 2 loop
    v_r := public.capital_gift_pass(v_t + make_interval(hours => 25 * v_k), v_m);
    if (v_r->>'gifted')::int <> 1 or (v_r->>'failed')::int <> 0 then
      raise exception 'PG_WEEK: gift % of hers, % hours after the first, answered %', v_k + 1, 25 * v_k, v_r - 'notes';
    end if;
    perform public.pay_city(v_m, v_home, 'TAX', 250000);
  end loop;
  v_r := public.capital_gift_pass(v_t + interval '75 hours', v_m);
  if (v_r->>'gifted')::int <> 0 or (v_r->>'gift_waiting')::int <> 0 or (v_r->>'failed')::int <> 0
     or exists (select 1 from public.capital_gift_roster(v_t + interval '75 hours', v_m) g)
     or (select count(*) from public.capital_gifts g where g.player_id = v_m) <> 3 then
    raise exception 'PG_WEEK: a fourth gift inside seven days: %', v_r - 'notes';
  end if;
  v_r := public.capital_gift_pass(v_t + interval '7 days 1 hour', v_m);
  if (v_r->>'gifted')::int <> 1 or (select count(*) from public.capital_gifts g where g.player_id = v_m) <> 4 then
    raise exception 'PG_WEEK: with her first gift seven days old she was not gifted again: %', v_r - 'notes';
  end if;
  raise notice 'PASS: PG_WEEK nothing an hour after a gift; a second and a third 25 and 50 hours on; no fourth at 75 hours (3 in seven days); a fourth at seven days and an hour';

  -- ── PG_CROWN ── (the control: a crown merchant made broke the same way)
  select h.player_id, h.home_port_id into v_ctl, v_ctl_home
    from public.npc_houses h join public.players pl on pl.id = h.player_id
   where pl.is_npc and not public.pirate_power(pl.nation_id) and pl.ducats > 1000
     and exists (select 1 from public.nations n join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR' where n.id = pl.nation_id)
   order by h.roster_ord limit 1;
  if v_ctl is null then
    raise exception 'PG_CROWN: no crown merchant in this world';
  end if;
  perform public.pay_city(v_ctl, v_ctl_home, 'TAX', (select pl.ducats - 1000 from public.players pl where pl.id = v_ctl));
  select pl.ducats into v_purse from public.players pl where pl.id = v_ctl;
  v_s0 := pg_temp.spent_103();
  if not exists (select 1 from public.capital_gift_roster(v_t, v_ctl) g) then
    raise exception 'PG_CROWN: the broke crown merchant is not on the roster';
  end if;
  v_r := public.capital_gift_pass(v_t, v_ctl);
  if (v_r->>'failed')::int <> 0 or (v_r->>'gifted')::int + (v_r->>'gift_waiting')::int <> 1 or pg_temp.spent_103() <> v_s0
     or ((v_r->>'gifted')::int = 1 and (select count(*) from public.ledger l where l.player_id = v_ctl and l.kind = 'CAPITAL_GIFT' and l.ducats_delta > 0) <> 1)
     or ((v_r->>'gifted')::int = 0 and (select pl.ducats from public.players pl where pl.id = v_ctl) <> v_purse) then
    raise exception 'PG_CROWN: the broke crown merchant''s turn answered % (the hoard''s spend % -> %)', v_r - 'notes', v_s0, pg_temp.spent_103();
  end if;
  raise notice 'PASS: PG_CROWN the broke crown merchant is on the roster and her turn is her capital''s (gifted %, waiting %), never failed; the hoard''s spend book did not move', v_r->>'gifted', v_r->>'gift_waiting';

  -- ── PG_MONEY ──
  if pg_temp.w_103() <> v_w0 then
    raise exception 'PG_MONEY: W % -> %', v_w0, pg_temp.w_103();
  end if;
  raise notice 'PASS: PG_MONEY W % d. unchanged to the ducat across four gifts from the hoard, a refusal, a crown merchant''s turn and every payment that made them broke', v_w0;
end $p$;
