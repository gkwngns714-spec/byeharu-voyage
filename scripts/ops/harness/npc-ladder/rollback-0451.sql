-- 0451 ROLLBACK (forward, OWNER ONLY, a DRAFT). NOT a prod check and NOT a migration yet: to use depth 3, strip the guard line below, give the file
-- the next number and deploy it as any migration. Three depths; take the shallowest that answers the trouble.
--
-- (1) THE QUICK STOP, one row, no migration:
--       update public.world_config set value = 'false'::jsonb where key = 'npc_ladder_enabled';
--     Nobody is re-rated any more (public.npc_ladder_pass answers {} after one knob read; public.pirate_reborn's call answers false). A fleet
--     stays the hulls she is. A CARGO ship's refit is 0328's body again, so every cargo ship turns back to public.cargo_class() (the navire) at
--     her next idle minute at home, free, with no pace (one hull out and one in each: about 100 ships as they come home).
--
-- (2) THE FLEETS BACK AS THEY WERE, with the switch left ON and by the ladder's own hand (two a kind a minute, in harbour only): make every
--     rung the hulls the kind had before 0451, and give the eight Dread fleets their old lead ship. Run as one new migration:
--       begin;
--       delete from public.npc_ladder_hulls where kind in ('NAVY', 'CARGO');
--       insert into public.npc_ladder_hulls (kind, rung, line, class, n)
--       select l.kind, l.rung, '*', case l.kind when 'NAVY' then public.wc_text('navy_ship_class') else public.cargo_class() end, 1
--         from public.npc_ladder l where l.kind in ('NAVY', 'CARGO');
--       delete from public.npc_ladder_hulls where kind = 'PIRATE';
--       insert into public.npc_ladder_hulls (kind, rung, line, class, n)
--       select 'PIRATE', l.rung, '*', public.wc_text('pirate_ship_class'), 1 from public.npc_ladder l where l.kind = 'PIRATE';   -- 0339's ships: one xebec each
--       update public.pirate_roster_hulls h set class = case when (select p.code from public.pirate_roster r join public.ports p on p.id = r.hub_port where r.ord = h.ord) = 'FLO'
--                                                           then 'korsan' else 'galeoncete' end
--        where h.class = 'kalyon';   -- 0414's rows: the korsan led Flores's squadrons, the galeoncete the others'
--       commit;
--     public.npc_fleet_rungs then no longer matches what the rule wants, so the pass and the cargo ships' own refits re-rate every changed
--     fleet back (about 155 fleets, one to three hours). The self-assert of 0451 that a rung above is a bigger lead ship is 0451's own and
--     does not run again.
--
-- (3) THE CODE OUT (only after (1), and after (2) if the hulls must go back): the three hunks reversed, the functions and tables dropped.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  x     record;
  v_def text;
begin
  if (select w.value from public.world_config w where w.key = 'npc_ladder_enabled') is distinct from 'false'::jsonb then
    raise exception '0451 rollback refuses: set npc_ladder_enabled false first (depth 1), and let the cargo ships turn back';
  end if;
  create temp table rb_0451 (fn text, ord int, old text, new text) on commit drop;
  insert into rb_0451 values
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end
$h$,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end
         -- 0451: the navy and pirate fleets in harbour are re-rated to their rung, a few a minute (public.npc_ladder_pass, which never raises and has its own switch), never behind a trade's locks, as they are
         || case when current_setting('byeharu.pirate_traded', true) is distinct from 'on' then public.npc_ladder_pass(p_now) else '{}'::jsonb end
$h$),
  ('public.pirate_reborn(uuid,timestamp with time zone)', 1,
$h$  perform public.fleet_mend(p_fleet);
  perform public.fleet_book_refit(p_fleet, $h$,
$h$  perform public.npc_ladder_refit(p_fleet, p_now);   -- 0451: she is reborn as her rung (public.npc_hulls_wanted): her hold is lost and every hull is at 0, so this is the moment; the refit paid above was her old hulls'
  perform public.fleet_mend(p_fleet);
  perform public.fleet_book_refit(p_fleet, $h$),
  ('public.cargo_hull(uuid)', 1,
$h$begin
  select x.* into s from public.ships x where x.fleet_id = p_fleet and x.is_flagship;
$h$,
$h$begin
  if public.npc_ladder_on() and public.cargo_armed_on() then
    return public.npc_ladder_refit(p_fleet, now());   -- 0451: lit (and the cargo ships armed, 0328's switch), her hull is her rung's (public.npc_hulls_wanted: Small, Medium or Large of her country's line), by the one re-rating; else 0328's body below
  end if;
  select x.* into s from public.ships x where x.fleet_id = p_fleet and x.is_flagship;
$h$);
  for x in select * from rb_0451 order by fn, ord desc loop
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
      raise exception '0451 rollback FAIL: hunk % of % is not in the live body once', x.ord, x.fn;
    end if;
    execute replace(v_def, x.new, x.old);
  end loop;
  drop function public.npc_ladder_pass(timestamptz);
  drop function public.npc_ladder_refit(uuid, timestamptz);
  drop function public.npc_ladder_take(text, timestamptz);
  drop function public.npc_hulls_sig(uuid);
  drop function public.npc_hulls_wanted(uuid);
  drop function public.npc_rung_of(uuid);
  drop function public.npc_rung_rule(text, integer, integer);
  drop function public.npc_ladder_line(uuid);
  drop function public.npc_ladder_kind(uuid);
  drop function public.npc_ladder_on();
  drop table public.npc_fleet_rungs;
  drop table public.npc_ladder_clock;
  drop table public.npc_ladder_hulls;
  drop table public.npc_ladder;
  delete from public.world_config where key in ('npc_ladder_enabled', 'npc_ladder_per_minute', 'npc_ladder_looks_per_run');
  drop table rb_0451;
end $r$;
