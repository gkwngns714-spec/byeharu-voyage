-- 0406 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). It reverses 0406's eight hunks: public.npc_plan no longer takes the dock fees from a loop's net and
-- public.npc_leg_lines no longer answers `cost`. Each hunk's NEW text must occur once in the live body (else it refuses: a later file re-cut the same
-- lines and this draft is stale). There is no knob that turns 0406 off short of this: the fee knobs are the owner's and price the charge itself.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  create temp table back_0406 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0406 values
  (1, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
$h$  v_wages   numeric;
  v_cost    numeric := 0;   -- 0406: what the kept parcels cost her here (the buy quotes' totals)
  v_kept    int := 0;
$h$,
$h$  v_wages   numeric;
  v_kept    int := 0;
$h$),
  (2, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
$h$      v_budget := v_budget - q_buy.total;   -- 0129
      v_cost   := v_cost + q_buy.total;     -- 0406
$h$,
$h$      v_budget := v_budget - q_buy.total;   -- 0129
$h$),
  (3, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
$h$  -- 0406: `cost` is what the kept parcels cost her at p_from: her cargo at cost when she makes p_to, the value public.npc_plan asks the dock fee for
  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
                            'nm', v_nm, 'any', v_any, 'cost', v_cost);
$h$,
$h$  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
                            'nm', v_nm, 'any', v_any);
$h$),
  (4, 'public.npc_plan(timestamp with time zone,uuid)',
$h$  v_sea_d   numeric;     -- 0142: the loop's days at sea
  v_fees    numeric;     -- 0406: the dock fees a lap of the loop pays (public.port_fee at every harbour she makes)
$h$,
$h$  v_sea_d   numeric;     -- 0142: the loop's days at sea
$h$),
  (5, 'public.npc_plan(timestamp with time zone,uuid)',
$h$        v_wages  := 0;       -- 0142
        v_fees   := 0;       -- 0406
        v_rep    := false;   -- 0142
$h$,
$h$        v_wages  := 0;       -- 0142
        v_rep    := false;   -- 0142
$h$),
  (6, 'public.npc_plan(timestamp with time zone,uuid)',
$h$            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
            -- 0406: THE DOCK FEE OF THIS LEG'S CALL, asked of THE one fee (public.port_fee, the function public.port_call charges her by):
            -- the harbour she makes, her company, her cargo at cost on arriving (the leg's `cost`). Asked once a leg and kept with it.
            v_leg  := v_leg || jsonb_build_object('fee', public.port_fee(v_to, sr.player_id, coalesce((v_leg->>'cost')::numeric, 0)));
            v_memo := v_memo || jsonb_build_object(v_key, v_leg);
$h$,
$h$            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
            v_memo := v_memo || jsonb_build_object(v_key, v_leg);
$h$),
  (7, 'public.npc_plan(timestamp with time zone,uuid)',
$h$          v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);   -- 0142
          v_fees   := v_fees + coalesce((v_leg->>'fee')::numeric, 0);      -- 0406
$h$,
$h$          v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);   -- 0142
$h$),
  (8, 'public.npc_plan(timestamp with time zone,uuid)',
$h$        -- 0406: LESS THE DOCK FEES THE LOOP PAYS (0237: every harbour she makes charges her, at home too). They never entered this net, so a
        -- loop whose margin was under its fees "paid", was sailed and emptied her purse. The score, the choice, "pays" and the lay-up read v_net.
        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)
                   - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                        v_crew * public.wc_num('food_per_crew_day') * v_sea_d)
                   - v_fees;
$h$,
$h$        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)
                   - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                        v_crew * public.wc_num('food_per_crew_day') * v_sea_d);
$h$);
  for h in select * from back_0406 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception 'rollback 0406 refuses: hunk % of % occurs % time(s) in the live body, not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  if position('0406' in pg_get_functiondef('public.npc_plan(timestamp with time zone,uuid)'::regprocedure)) > 0
     or position('0406' in pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure)) > 0 then
    raise exception 'rollback 0406 FAIL: something of 0406 is left in the two bodies';
  end if;
  raise notice 'rollback 0406 ok: the eight hunks reversed; the planner''s net is 0142''s again and the leg planner answers no cost';
end $r$;
