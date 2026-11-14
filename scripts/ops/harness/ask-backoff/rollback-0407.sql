-- 0407 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). FIRST, WITH NO FILE: npc_ask_job_ms 0 stops the waiting-asks job at once; npc_ask_broke_under 0 lifts the broke
-- rule. This draft takes the back-off itself away: public.npc_waiting_queue, public.npc_plan and public.tick_waiting_asks go back to their bodies before
-- 0407 (the seven hunks reversed; each hunk's NEW text must occur once, else it refuses: a later file re-cut those lines and the draft is stale), the knob
-- npc_ask_broke_under goes, and every merchant is due npc_replan_every_minutes after her last ask again. npc_fleets.refused is left in place and unread
-- (dropping a column is not needed to undo the rule). npc_ask_job_ms is left as the owner has it: at the old rule the line asks for about 20,000.
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
  create temp table back_0407 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0407 values
  (1, 'public.npc_waiting_queue(timestamp with time zone)',
$h$    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.players pl on pl.id = sr.player_id   -- 0407: her house's purse, read live
$h$,
$h$    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
$h$),
  (2, 'public.npc_waiting_queue(timestamp with time zone)',
$h$                      public.wc_int('npc_replan_within_minutes') as w_min,
                      public.wc_int('npc_ask_broke_under') as broke) w   -- 0407
$h$,
$h$                      public.wc_int('npc_replan_within_minutes') as w_min) w
$h$),
  (3, 'public.npc_waiting_queue(timestamp with time zone)',
$h$         -- 0407: THE DUE RULE BACKS OFF. Refused once she is due in npc_replan_every_minutes; refused again, in twice that, then four times,
         -- and never more than npc_replan_within_minutes less one npc_replan_every_minutes (the job reaches her before the hourly reconcile
         -- calls her overdue). A house with no purse to buy a parcel (under npc_ask_broke_under) waits that longest at once.
         a.asked + make_interval(mins => case when pl.ducats < w.broke then greatest(w.e_min, w.w_min - w.e_min)
                                              else least(w.e_min * power(2, least(greatest(nf.refused, 1) - 1, 10))::int,
                                                         greatest(w.e_min, w.w_min - w.e_min)) end),
$h$,
$h$         a.asked + make_interval(mins => w.e_min),
$h$),
  (4, 'public.npc_plan(timestamp with time zone,uuid)',
$h$      -- 0407: THE COUNT OF HER REFUSALS IN A ROW (npc_fleets.refused; public.npc_waiting_queue backs her next ask off by it) is written here
      -- and nowhere else: back to nothing where a loop pays at her lap start, one more where she is laid up or kept laid up just below.
      if v_pays and v_choose then
        update public.npc_fleets set refused = 0 where fleet_id = r.fleet_id and refused <> 0;
      end if;
      if not v_pays and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then
        v_waiting := v_waiting + 1;
        update public.npc_fleets set refused = refused + 1 where fleet_id = r.fleet_id;   -- 0407
$h$,
$h$      if not v_pays and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then
        v_waiting := v_waiting + 1;
$h$),
  (5, 'public.tick_waiting_asks(boolean,uuid)',
$h$  v_wait_ms numeric := 0;
  v_quay_ms numeric := 0;    -- 0407: the wait for the quay itself, apart from the open step's work
  v_quay_max numeric := 0;   -- 0407
begin
$h$,
$h$  v_wait_ms numeric := 0;
begin
$h$),
  (6, 'public.tick_waiting_asks(boolean,uuid)',
$h$    -- 0407: the quay asked for here, to time the wait for it apart (0269's way in public.tick_lap_starts); public.waiting_ask_open asks for
    -- it again first thing: the same lock in the same transaction, granted at once. The wait is not work: not in open_ms, not in v_spent.
    v_t := clock_timestamp();
    perform public.hold_the_quay();
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_quay_ms := v_quay_ms + v_ms;
    v_quay_max := greatest(v_quay_max, v_ms);
    v_t := clock_timestamp();
    begin
      v_b := public.waiting_ask_open(v_f, v_stamp);
$h$,
$h$    v_t := clock_timestamp();
    begin
      v_b := public.waiting_ask_open(v_f, v_stamp);
$h$),
  (7, 'public.tick_waiting_asks(boolean,uuid)',
$h$'wait_ms', round(v_wait_ms),
                    'quay_ms', round(v_quay_ms), 'quay_ms_max', round(v_quay_max),   -- 0407
$h$,
$h$'wait_ms', round(v_wait_ms),
$h$);
  -- a use before what it reads: the due line (3) before its join and knob (1, 2); the quay's timing and receipt (7, 6) before their variables (5): the
  -- body is whole at every step
  for h in select * from back_0407 order by case ord when 3 then 0 when 7 then 5 when 5 then 7 else ord end loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception 'rollback 0407 refuses: hunk % of % occurs % time(s) in the live body, not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  delete from public.world_config where key = 'npc_ask_broke_under';
  if exists (select 1 from unnest(array['public.npc_waiting_queue(timestamp with time zone)', 'public.npc_plan(timestamp with time zone,uuid)',
                                        'public.tick_waiting_asks(boolean,uuid)']) f where position('0407' in pg_get_functiondef(f::regprocedure)) > 0) then
    raise exception 'rollback 0407 FAIL: something of 0407 is left in the three bodies';
  end if;
  raise notice 'rollback 0407 ok: the seven hunks reversed; every laid-up merchant is due npc_replan_every_minutes after her last ask again';
end $r$;
