-- 0506 FORWARD ROLLBACK, A DRAFT (owner only). THE QUICK ROLLBACK NEEDS NO FILE: bargain_total_enabled false. To use this one, strip the guard line, give it
-- the next number, add "-- news: none", and withdraw 0506's proof with the same PR. It reverses 0506's 20 hunks and drops what it made.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  if public.wc('bargain_total_enabled') = 'true'::jsonb then
    raise exception '0506 rollback refuses: bargain_total_enabled is lit; the owner darkens it first';
  end if;
  create temp table back_0506 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0506 values
  (1, 'cmd.haggle(uuid,uuid,text)',
$h$  v_player  uuid := coalesce(public.bargain_actor(), public.current_player_id());   -- 0506: a standing job bargains for its own company (public.job_bargain); else the signed-in one, as before
$h$,
$h$  v_player  uuid := public.current_player_id();
$h$),
  (2, 'cmd.haggle(uuid,uuid,text)',
$h$  v_max     int  := public.haggle_attempts_max();   -- 0506 (dark: bargain_total_enabled): 10 lit, haggle_attempts_per_day as before
$h$,
$h$  v_max     int  := public.wc_int('haggle_attempts_per_day');
$h$),
  (3, 'cmd.haggle(uuid,uuid,text)',
$h$  v_step    numeric := public.haggle_step();   -- 0506: lit, 5 % of her TOTAL a win (public.bargain_factor); dark, the share of the spread as before
$h$,
$h$  v_step    numeric := public.wc_num('haggle_concession_step');
$h$),
  (4, 'cmd.haggle(uuid,uuid,text)',
$h$  v_cap     numeric := public.haggle_cap();   -- 0506: lit, every try won (50 %); dark, haggle_concession_max as before
$h$,
$h$  v_cap     numeric := public.wc_num('haggle_concession_max');
$h$),
  (5, 'cmd.haggle(uuid,uuid,text)',
$h$  v_used := coalesce(v_used, 0);
  -- 0506 (dark: nothing): the day's row is one side only (the same-day resale guard)
  if public.bargain_side_refusal(v_player, f.port_id, g.id, v_side) is not null then
    return jsonb_build_object('ok', false, 'error_code', 'E_BARGAIN_SIDE',
      'error_message', public.bargain_side_refusal(v_player, f.port_id, g.id, v_side),
      'fixes', jsonb_build_array('(trade at the price offered)', '(come back tomorrow)', '(bargain over a different good)'));
  end if;
  if v_used >= v_max then
$h$,
$h$  v_used := coalesce(v_used, 0);
  if v_used >= v_max then
$h$),
  (6, 'cmd.haggle(uuid,uuid,text)',
$h$  perform public.bargain_xp(v_player, v_won);   -- 0506 (dark: nothing): a bargain she tried herself is experience in Negotiation
  perform public.emit_event(v_player, 'HAGGLED', jsonb_build_object(
$h$,
$h$  perform public.emit_event(v_player, 'HAGGLED', jsonb_build_object(
$h$),
  (7, 'public.haggle_odds(uuid,uuid,uuid,uuid)',
$h$begin
  -- 0506 (dark: bargain_total_enabled): lit, the chance falls on EVERY try, won or lost: p1 x bargain_decay^(tries spent) (public.bargain_odds)
  if public.bargain_on() then
    return public.bargain_odds(p_player, p_port, p_good, p_fleet);
  end if;
  select greatest(0, h.attempts - h.wins) into v_fails
$h$,
$h$begin
  select greatest(0, h.attempts - h.wins) into v_fails
$h$),
  (8, 'world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)',
$h$      -- 0506 (dark: bargain_total_enabled): lit, a bargain moves her TOTAL (public.bargain_factor in world.quote_priced), never the spread
      v_hag := case when public.bargain_on() then 0 else public.haggle_concession(v_player, p_port, p_good) end;
$h$,
$h$      v_hag := public.haggle_concession(v_player, p_port, p_good);
$h$),
  (9, 'world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)',
$h$  -- 0506 (dark: bargain_total_enabled): lit, HER BARGAIN IS A SHARE OF HER TOTAL (public.bargain_factor: 5 % a win, the resale guard, a
  -- standing job's expected tries), applied here, in the one quote, so every face and the door read the same figure. Nobody else's
  -- quote, the mid and the published price are untouched. (v_unit is free once the walk is done; it holds the factor.)
  if p_fleet is not null and public.bargain_on() then
    v_unit  := public.bargain_factor(p_fleet, p_port, p_good, p_side);
    v_hag_t := v_hag_t + case when p_side = 'buy' then v_total - v_total * v_unit else v_total * v_unit - v_total end;
    v_total := v_total * v_unit;
  end if;
  units     := v_units;
$h$,
$h$  units     := v_units;
$h$),
  (10, 'world.haggle_state(uuid,uuid)',
$h$  v_max    int := public.haggle_attempts_max();   -- 0506 (dark: bargain_total_enabled): 10 lit, haggle_attempts_per_day as before
$h$,
$h$  v_max    int := public.wc_int('haggle_attempts_per_day');
$h$),
  (11, 'world.haggle_state(uuid,uuid)',
$h$    'spent_on', 'the next trade of this good at this port, or the day''s end')
    || public.bargain_state(v_player, p_fleet, f.port_id, p_good);   -- 0506: lit, the key `bargain` (a share of her total); dark, nothing
$h$,
$h$    'spent_on', 'the next trade of this good at this port, or the day''s end');
$h$),
  (12, 'cmd.do_buy(uuid,jsonb)',
$h$  perform public.job_bargain(p_fleet, g.id, 'buy');   -- 0506 (dark: nothing): a standing job makes its tries first, through cmd.haggle
  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$,
$h$  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$),
  (13, 'cmd.do_sell(uuid,jsonb)',
$h$  perform public.job_bargain(p_fleet, g.id, 'sell');   -- 0506 (dark: nothing): a standing job makes its tries first, through cmd.haggle
  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$,
$h$  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$),
  (14, 'public.level_skills_card(uuid,jsonb)',
$h$                where (s.side = 'sea' and (s.lit_by is null or public.wc(s.lit_by) = 'true'::jsonb))   -- 0506: a sea level that waits for its switch (Negotiation)
                   or (s.side = 'land' and public.land_skill_on(s.code))))   -- 0461: and its own switch   -- 0455: a land skill only while land_enabled
$h$,
$h$                where s.side = 'sea' or public.land_skill_on(s.code)))   -- 0461: and its own switch   -- 0455: a land skill only while land_enabled
$h$),
  (15, 'public.fleet_job_set_for(uuid,uuid,text,jsonb)',
$h$  -- 0506 (dark: nothing): the job setting `bargain` (false = this job does not bargain; the default is on)
  if public.bargain_on() then
    v_p := v_p || public.job_bargain_param(p_params);
  end if;
  insert into public.fleet_jobs as j (fleet_id, player_id, kind, params, since, seen_at)
$h$,
$h$  insert into public.fleet_jobs as j (fleet_id, player_id, kind, params, since, seen_at)
$h$),
  (16, 'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)',
$h$    select q.units, public.bargain_first(p_fleet, p_buy, p_good, 'buy', q.total, p_cost) /* 0506 (dark: nothing): a bargain is one trade's */ into v_got, v_buy from$h$,
$h$    select q.units, q.total into v_got, v_buy from$h$),
  (17, 'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)',
$h$        select public.bargain_first(p_fleet, p_buy, p_good, 'buy', q.total, p_cost) /* 0506 (dark: nothing): a bargain is one trade's */ into v_buy from$h$,
$h$        select q.total into v_buy from$h$),
  (18, 'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)',
$h$    select q.units, public.bargain_first(p_fleet, p_sell, p_good, 'sell', q.total, p_gross) /* 0506 (dark: nothing): a bargain is one trade's */ into v_got, v_sale from$h$,
$h$    select q.units, q.total into v_got, v_sale from$h$),
  (19, 'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)',
$h$        select public.bargain_first(p_fleet, p_buy, p_good, 'buy', q.total, p_cost) /* 0506 (dark: nothing): a bargain is one trade's */ into v_cb from$h$,
$h$        select q.total into v_cb from$h$),
  (20, 'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)',
$h$        select public.bargain_first(p_fleet, p_sell, p_good, 'sell', q.total, p_gross) /* 0506 (dark: nothing): a bargain is one trade's */ into v_cs from$h$,
$h$        select q.total into v_cs from$h$);
  for h in select * from back_0506 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0506 rollback refuses: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop function public.bargain_first(uuid,uuid,uuid,text,numeric,numeric);
  drop function public.bargain_state(uuid,uuid,uuid,uuid);
  drop function public.bargain_factor(uuid,uuid,uuid,text);
  drop function public.job_bargain_param(jsonb);
  drop function public.job_bargain(uuid,uuid,text);
  drop function public.job_bargain_tries(uuid);
  drop function public.bargain_xp(uuid,boolean);
  drop function public.bargain_side_refusal(uuid,uuid,uuid,text);
  drop function public.bargain_actor();
  drop function public.bargain_odds(uuid,uuid,uuid,uuid);
  drop function public.bargain_p1(uuid,uuid,uuid,uuid);
  drop function public.haggle_cap();
  drop function public.haggle_step();
  drop function public.haggle_attempts_max();
  drop function public.bargain_on();
  -- the level's steps go; a level anyone has earned in keeps its skill and activity rows (public.level_book is append-only), hidden by lit_by
  delete from public.level_perks where skill = 'negotiation';
  if not exists (select 1 from public.level_xp x where x.skill = 'negotiation') then
    delete from public.level_activities where skill = 'negotiation';
    delete from public.level_skills where code = 'negotiation';
    alter table public.level_skills add constraint level_skills_lit_by_check check (lit_by is null or side = 'land');
  end if;
  delete from public.world_config where key in ('bargain_total_enabled', 'bargain_attempts', 'bargain_step', 'bargain_p1_base', 'bargain_p1_max', 'bargain_decay');
  raise notice '0506 rollback ok: %', (select string_agg(x.fn || ' ' || md5(replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '')), ', ' order by x.fn)
                                       from (select distinct fn from back_0506) x);
end $r$;
