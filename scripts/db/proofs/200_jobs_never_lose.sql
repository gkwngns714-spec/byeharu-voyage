-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 200 - JOBS NEVER LOSE  (migration 0497, dark: jobs_wait_enabled; docs/dev-log/2026-11-25-jobs-never-lose.md)
--
--   A fixed job that sells, and the Best job, start a run only when the server's own quote of it leaves a profit; otherwise the job
--   waits (not stopped) and is asked again 10 minutes on. A card is priced for the units its sale's harbour takes today. The HQ board
--   ranks a trade card by its day's coin an hour. Rolled back by proof.mjs. (198 is left free for 0495.)
--
-- @pass JW_DARK     dark: the cards pass untouched, a losing fixed run is still planned BUY ALL, the board's score is the trip's
-- @pass JW_WAIT     lit: a fixed run whose sale has fallen is not started by the tick: no order, not stopped, asked again 600 s on, her row says "prices low" and when
-- @pass JW_NO_LOOP  a waiting job is not due and not quoted again by the next tick: its last word and its next_at stand
-- @pass JW_RESUME   the price back and her time come, the tick starts her by itself; her row waits no more
-- @pass JW_THERE    a run whose sale turned bad after she sailed still sells on arrival: nothing stays aboard
-- @pass JW_HOME     a bring-home is exempt: with the sale's harbour glutted its plan still buys and stores
-- @pass JW_OSAKA    a card for more units than its sale's harbour takes today (5,000,000 coin at Setubal: armillary spheres to Osaka) is cut to that allowance for the Best plan, the board and world.actions; its profit is the smaller load's
-- @pass JW_BOARD    lit: a trade card's coin an hour is its day's (public.run_day), never above the one trip's rate; its profit is still the trip's; the moves are ranked by it
-- @pass JW_COST     the board dark and lit, and the cut of twelve cards, in ms (printed; fails only if the lit board is over 1 s slower than the dark)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0497-4000-8000-0000000002a1';
  v_a    uuid;
  v_fa   uuid;
  v_lis  uuid;
  v_set  uuid;
  v_bs   jsonb;
  v_c    jsonb;
  v_big  jsonb;
  v_fit  jsonb;
  v_p    jsonb;
  v_w    jsonb;
  v_b    jsonb;
  v_b0   jsonb;
  v_o    jsonb;
  v_r    jsonb;
  v_j    public.fleet_jobs%rowtype;
  v_dest uuid;
  v_gid  uuid;
  v_stock numeric;
  v_left numeric;
  v_at   timestamptz;
  v_t    timestamptz;
  v_ms0  numeric;
  v_ms1  numeric;
  v_ms2  numeric;
  k      int;
begin
  -- THE MARKET IS PINNED (proof.pin_market, scripts/db/market-fixture.mjs: the one authority, this proof's own key) and THE SEA IS
  -- CALMED (hazard_p_max 0, as proofs 04, 11, 157, 184). Which run pays at Lisbon, and whether four times a harbour's stock sinks
  -- it, are facts of the market, and every from-zero apply deals another (with every quay empty, every price at its floor or no
  -- price differing this proof went red, 2026-11-25; so did 0497's own probe on prod's market). A voyage's days are rolled on its
  -- own id. The pinned market is drawn on the authored codes, the same in every world. Every assertion is as it was.
  if (proof.pin_market('00000000-0497-4000-8000-000000000200'::uuid, 'proof-200') ->> 'nonzero')::int < 14000 then
    raise exception 'PROOF 200: the market was not pinned';
  end if;
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  v_a := public.new_house(c_a, 'Casa da Espera 200', 'PRT');
  select f.id, f.port_id into v_fa, v_lis from public.fleets f where f.player_id = v_a;
  v_set := (select p.id from public.ports p where p.code = 'SET');
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'hq_board_enabled', 'assign_home_enabled');
  perform cmd.assume_identity(c_a);
  v_bs := world.best_sales(v_fa, v_lis);
  select g.e into v_c from jsonb_array_elements(v_bs->'goods') g(e)
   where (g.e->>'pays')::boolean and g.e->>'port' is not null and (g.e->>'profit')::numeric > 0 and g.e->>'basis' is distinct from 'on_board'
     and g.e->'near' is distinct from 'false'::jsonb and jsonb_typeof(g.e->'seconds') = 'number'
   order by (g.e->>'profit')::numeric / greatest((g.e->>'seconds')::numeric, 1) desc, g.e->>'good' limit 1;
  v_dest := (select p.id from public.ports p where p.code = v_c->>'port');
  v_gid := (select g.id from public.goods g where g.code = v_c->>'good');
  select pg.stock into v_stock from public.port_goods pg where pg.port_id = v_dest and pg.good_id = v_gid;

  -- ── JW_DARK ──
  v_t := clock_timestamp();
  v_b0 := public.hq_board_for(v_a);
  v_ms0 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
  perform cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_c->>'good', 'buy', 'LIS', 'sell', v_c->>'port'));
  update public.port_goods pg set stock = pg.stock_target * 4 where pg.port_id = v_dest and pg.good_id = v_gid;
  v_p := public.fleet_job_plan(v_fa);
  if public.jobs_wait_on() or public.cards_fit(v_a, v_fa, v_lis, v_bs->'goods', 3, true) is distinct from v_bs->'goods'
     or v_p #>> '{lines,0,text}' is distinct from format('BUY %s ALL', v_c->>'good')
     or exists (select 1 from jsonb_array_elements(v_b0->'moves') m where m->>'kind' = 'trade'
                 and (m->>'score')::numeric <> round((select (g.e->>'profit')::numeric * 3600 / greatest((g.e->>'seconds')::numeric, 1)
                                                         from jsonb_array_elements(v_bs->'goods') g(e)
                                                        where g.e->>'good' = m #>> '{needs,good}' and g.e->>'port' = m #>> '{needs,to}'))) then
    raise exception 'JW_DARK: dark, the cards, a losing plan or the board''s score moved: plan % / board %', left(v_p::text, 300), left((v_b0->'moves')::text, 600);
  end if;
  raise notice 'PASS: JW_DARK — dark: the cards untouched, a run to a glutted harbour still planned (%), the board''s score the trip''s', v_p #>> '{lines,0,text}';

  -- ── JW_WAIT ──
  update public.world_config set value = 'true'::jsonb where key = 'jobs_wait_enabled';
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  v_w := world.workers() #> '{workers,0}';
  if v_j.paused_reason is not null or v_j.runs <> 0 or v_j.next_at < now() + interval '600 seconds' or v_j.last->>'wait' <> 'low'
     or (v_j.last->>'net')::numeric > 0
     or exists (select 1 from public.orders o where o.fleet_id = v_fa) or (select f.status from public.fleets f where f.id = v_fa) <> 'DOCKED'
     or v_w->>'state' <> 'waiting' or v_w #>> '{wait,code}' <> 'low' or v_w #>> '{wait,sentence}' <> 'prices low'
     or (v_w #>> '{wait,retry_at}')::timestamptz <> v_j.next_at or jsonb_typeof(v_w->'stop') <> 'null'
     or (v_w #>> '{progress,to}')::timestamptz <> v_j.next_at then
    raise exception 'JW_WAIT: she did not wait as written: job % / row %', to_jsonb(v_j), v_w;
  end if;
  raise notice 'PASS: JW_WAIT — % to % would leave %: no order, not stopped, asked again at % (% s on); her row: "%"', v_c->>'good', v_c->>'port',
    v_j.last->>'net', v_j.next_at, round(extract(epoch from v_j.next_at - now())), v_w #>> '{wait,sentence}';

  -- ── JW_NO_LOOP ──
  v_at := v_j.next_at;
  call public.tick_fleet_jobs(false);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fa) or v_j.next_at <> v_at or v_j.runs <> 0
     or exists (select 1 from public.orders o where o.fleet_id = v_fa) then
    raise exception 'JW_NO_LOOP: a waiting job was asked again before its time: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: JW_NO_LOOP — two more ticks: not due, not quoted, her next_at stands';

  -- ── JW_RESUME ──
  update public.port_goods pg set stock = v_stock where pg.port_id = v_dest and pg.good_id = v_gid;
  update public.fleet_jobs set next_at = now() - interval '1 second' where fleet_id = v_fa;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if v_j.runs <> 1 or v_j.paused_reason is not null or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING'
     or world.workers() #> '{workers,0,wait}' <> 'null'::jsonb or world.workers() #>> '{workers,0,state}' <> 'working' then
    raise exception 'JW_RESUME: the price back, she did not start by herself: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: JW_RESUME — the price back and her time come: the tick started her (%), her row works', (select string_agg(o.raw_text, ' / ' order by o.seq) from public.orders o where o.fleet_id = v_fa);

  -- ── JW_THERE: the sale falls while she sails; she arrives and sells all the same ──
  update public.port_goods pg set stock = pg.stock_target * 4 where pg.port_id = v_dest and pg.good_id = v_gid;
  for k in 1 .. 12 loop
    exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fa and status = 'SAILING';
    perform world.fleets();
  end loop;
  if (select f.port_id from public.fleets f where f.id = v_fa) is distinct from v_dest or public.fleet_cargo_qty(v_fa, v_c->>'good') >= 1
     or not exists (select 1 from public.orders o where o.fleet_id = v_fa and o.verb = 'SELL' and o.status = 'done') then
    raise exception 'JW_THERE: arrived at a fallen sale she did not sell: aboard %, orders %', public.fleet_cargo_qty(v_fa, v_c->>'good'),
      (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
  end if;
  raise notice 'PASS: JW_THERE — the sale fell while she sailed: she arrived at % and sold, nothing aboard', v_c->>'port';
  update public.port_goods pg set stock = v_stock where pg.port_id = v_dest and pg.good_id = v_gid;

  -- ── JW_HOME: she lies at the sale's harbour, away from home; a bring-home from here, Lisbon glutted of the good ──
  delete from public.fleet_jobs where fleet_id = v_fa;
  select g.code into v_r from (select to_jsonb(g2.code) as code from public.port_goods pg join public.goods g2 on g2.id = pg.good_id
                                where pg.port_id = v_dest and public.port_offers(v_dest, g2.id) and pg.stock > 0 order by pg.stock_target desc, g2.code limit 1) g;
  update public.port_goods pg set stock = pg.stock_target * 4 where pg.port_id = v_lis and pg.good_id = (select g.id from public.goods g where g.code = v_r #>> '{}');
  v_o := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', v_r #>> '{}', 'buy', v_c->>'port', 'end', 'store'));
  v_p := public.fleet_job_plan(v_fa);
  if (v_o->>'ok')::boolean is not true or not (v_p ? 'lines') or v_p ? 'wait'
     or v_p #>> '{lines,0,text}' !~ ('^BUY ' || (v_r #>> '{}') || ' ')
     or (select e->>'text' from jsonb_array_elements(v_p->'lines') with ordinality x(e, i) order by i desc limit 1) !~ '^STORE ' then
    raise exception 'JW_HOME: a bring-home was held back or is not BUY ... STORE: set % / plan %', v_o, left(v_p::text, 400);
  end if;
  raise notice 'PASS: JW_HOME — bring % home from %: planned as before (% ... %)', v_r #>> '{}', v_c->>'port', v_p #>> '{lines,0,text}',
    (select e->>'text' from jsonb_array_elements(v_p->'lines') with ordinality x(e, i) order by i desc limit 1);
  delete from public.fleet_jobs where fleet_id = v_fa;

  -- ── JW_OSAKA: at Setubal with 5,000,000 coin a card is for more units than its sale's harbour takes today ──
  update public.fleets set port_id = v_set where id = v_fa;
  v_bs := world.best_sales(v_fa, v_set);
  select g.e, world.daily_cap_remaining(v_a, p.id, gd.id) into v_big, v_left
    from jsonb_array_elements(v_bs->'goods') g(e)
    join public.ports p on p.code = g.e->>'port' join public.goods gd on gd.code = g.e->>'good'
   where (g.e->>'pays')::boolean and (g.e->>'profit')::numeric > 0 and g.e->>'basis' is distinct from 'on_board' and g.e->'near' is distinct from 'false'::jsonb
     and (jsonb_typeof(g.e->'seconds') = 'number' or jsonb_typeof(g.e->'days') = 'number')
     and world.daily_cap_remaining(v_a, p.id, gd.id) < (g.e->>'units')::numeric
   order by (g.e->>'profit')::numeric / greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) desc, g.e->>'good' limit 1;
  if v_big is null then
    raise exception 'JW_OSAKA: no card at Setubal is for more units than its sale''s harbour takes (the world moved: pick another scene)';
  end if;
  v_fit := public.sale_fit(v_a, v_fa, v_set, v_big);
  if v_fit is not null and ((v_fit->>'units')::numeric > v_left or (v_fit->>'units')::numeric <> floor(v_left)
                            or (v_fit->>'profit')::numeric >= (v_big->>'profit')::numeric or (v_fit->>'cut')::boolean is not true) then
    raise exception 'JW_OSAKA: the card is not cut to the % units its sale''s harbour takes: % from %', v_left, v_fit, v_big;
  end if;
  -- no card any reader uses is for more than its sale's harbour takes: the Best plan, world.actions, the board
  if exists (select 1 from jsonb_array_elements(public.cards_fit(v_a, v_fa, v_set, v_bs->'goods', 12, false)) e
              join public.ports p on p.code = e->>'port' join public.goods gd on gd.code = e->>'good'
             where e->>'basis' is distinct from 'on_board' and (e->>'units')::numeric > world.daily_cap_remaining(v_a, p.id, gd.id)) then
    raise exception 'JW_OSAKA: a fitted card is still for more than its sale''s harbour takes';
  end if;
  perform cmd.set_fleet_job(v_fa, 'best', '{}'::jsonb);
  v_p := public.fleet_job_plan(v_fa);
  if v_p ? 'lines' and (substring(v_p #>> '{lines,0,text}' from '^BUY \S+ ([0-9.]+)$'))::numeric
       > world.daily_cap_remaining(v_a, (select p.id from public.ports p where p.code = v_p #>> '{note,to}'), (select g.id from public.goods g where g.code = v_p #>> '{note,good}')) then
    raise exception 'JW_OSAKA: the Best plan buys more than its sale''s harbour takes: %', left(v_p::text, 400);
  end if;
  v_o := world.actions('fleet:' || v_fa);
  if exists (select 1 from jsonb_array_elements(v_o->'options') e
              join public.ports p on p.code = e->>'sell' join public.goods gd on gd.code = e->>'good'
             where e->>'end' = 'sell' and (e->>'units')::numeric > world.daily_cap_remaining(v_a, p.id, gd.id)) then
    raise exception 'JW_OSAKA: world.actions offers a run of more units than its sale''s harbour takes';
  end if;
  raise notice 'PASS: JW_OSAKA — % to %: the card said % units and +%; its harbour takes % today: % (the Best plan: %)', v_big->>'good', v_big->>'port',
    v_big->>'units', v_big->>'profit', floor(v_left),
    case when v_fit is null then 'left out (no profit in the smaller load)' else format('cut to %s units, +%s', v_fit->>'units', v_fit->>'profit') end,
    coalesce(v_p #>> '{lines,0,text}', v_p->>'wait');
  delete from public.fleet_jobs where fleet_id = v_fa;
  update public.fleets set port_id = v_lis where id = v_fa;

  -- ── JW_BOARD + JW_COST ──
  v_bs := world.best_sales(v_fa, v_lis);
  v_t := clock_timestamp();
  v_b := public.hq_board_for(v_a);
  v_ms1 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
  v_t := clock_timestamp();
  perform public.cards_fit(v_a, v_fa, v_lis, v_bs->'goods', 12, false);
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
  if not exists (select 1 from jsonb_array_elements(v_b->'moves') m where m->>'kind' = 'trade')
     or exists (select 1 from jsonb_array_elements(v_b->'moves') m
                 where m->>'kind' = 'trade' and m #>> '{needs,basis}' is distinct from 'on_board'
                   and (jsonb_typeof(m->'score') <> 'number'
                        or (m->>'score')::numeric > round((m->>'profit')::numeric * 3600 / greatest((m->>'seconds')::numeric, 1))
                        or (m->>'profit')::numeric <= 0))
     -- ranked by it: inside a band the scores do not rise
     or exists (select 1 from (select (m.e->>'band')::int as b, (m.e->>'score')::numeric as s, lag((m.e->>'band')::int) over (order by m.k) as pb,
                                      lag((m.e->>'score')::numeric) over (order by m.k) as ps
                                 from jsonb_array_elements(v_b->'moves') with ordinality m(e, k)) z
                 where z.b = z.pb and z.s > z.ps) then
    raise exception 'JW_BOARD: a trade card has no day''s coin an hour, reads above its one trip, or the moves are not ranked by it: %', left((v_b->'moves')::text, 1500);
  end if;
  raise notice 'PASS: JW_BOARD — % trade cards: %', (select count(*) from jsonb_array_elements(v_b->'moves') m where m->>'kind' = 'trade'),
    (select string_agg(format('%s to %s: the trip +%s (that is %s an hour once), its day %s an hour', m #>> '{needs,good}', m #>> '{needs,to}', m->>'profit',
                              round((m->>'profit')::numeric * 3600 / greatest((m->>'seconds')::numeric, 1)), m->>'score'), '; ')
       from jsonb_array_elements(v_b->'moves') m where m->>'kind' = 'trade');
  if v_ms1 - v_ms0 > 1000 then
    raise exception 'JW_COST: the lit board took % ms against % ms dark', v_ms1, v_ms0;
  end if;
  raise notice 'PASS: JW_COST — the board % ms dark, % ms lit; the cut of twelve cards % ms', v_ms0, v_ms1, v_ms2;
end $p$;
