-- 0437 ROLLBACK (forward, OWNER ONLY, a DRAFT: run as one new migration if 0437 must come out). Each hunk reversed (its new text back to its old),
-- then public.cargo_ship_state dropped (after the two readers no longer name it). No data is touched: laid-up ships stay laid up (0326's law).
do $r$
declare
  x record;
  v_def text;
begin
  create temp table rb_0437 (fn text, ord int, old text, new text) on commit drop;
  insert into rb_0437 values
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$  v_home  jsonb;
begin
$h$,
$h$  v_home  jsonb;
  v_sur   boolean;   -- 0437: her ord is over her country's share
begin
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$  v_left := coalesce(v_left, 0);
$h$,
$h$  v_left := coalesce(v_left, 0);
  v_sur := v_lit and c.ord > public.convoy_ships_of(c.nation_id);   -- 0437: a surplus ship: she comes home now and lays up there (public.cargo_ships_retire)
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 3,
$h$      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$,
$h$      if v_sur then
        return 'IDLE';   -- 0437: a surplus ship idle at home waits for the retire; she is never sent off to a new home first
      end if;
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 4,
$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
$h$,
$h$    -- 0437: A SURPLUS SHIP COMES HOME NOW (owner 2026-11-15: "you still haven't reduce the numbers right"). Her ord is over her country's share, so she
    -- takes no new load and lays up at home. Here, after this city's delivery above, she drops the rest of her circuit and sails ONE leg straight home
    -- with whatever is left aboard (before 0437 she sailed the whole circuit first, up to 37 legs). At home the lap closes as before (HOME: the rest is
    -- RETURNED to the port it was loaded at, her home), so no gold is lost. No course home: she goes on by the circuit, whose last leg is home.
    if v_sur then
      if f.ready_at is not null and f.ready_at > p_now then
        return 'IN_PORT';
      end if;
      v_home := public.cargo_circuit_plan(c.nation_id, f.port_id, c.home_port_id) #> '{legs,0}';
      if v_home is not null then
        perform public.cargo_upkeep(p_fleet, f.port_id);   -- 0328: this leg too, as every leg
        perform voyage.depart(p_fleet, voyage.segments_from_course(v_home -> 'course'), f.port_id, c.home_port_id, p_now);
        return case when exists (select 1 from public.cargo_ship_aboard(p_fleet)) then 'RECALLED' else 'HOMEWARD' end;   -- 0437: RECALLED with gold aboard; empty, 0430's word
      end if;
    end if;
    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
$h$),
  ('world.cargo_ship_card(uuid)', 1,
$h$  w record;
begin
$h$,
$h$  w record;
  v_state text := public.cargo_ship_state(p_fleet);   -- 0437: LOADED, RETURNING, HOME or LAID_UP
begin
$h$),
  ('world.cargo_ship_card(uuid)', 2,
$h$    'funds', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$,
$h$    'funds', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
    'state', v_state,   -- 0437: with nothing on board the card says this word, not 0 gold
$h$),
  ('world.cargo_ship_card(uuid)', 3,
$h$                      where l.circuit_id = c.circuit_id and l.ord > c.leg order by l.ord limit 5) x),
    'stops_left', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = c.circuit_id and l.ord > c.leg),
$h$,
$h$                      where l.circuit_id = c.circuit_id and l.ord > c.leg and v_state = 'LOADED' and c.ord <= public.convoy_ships_of(c.nation_id) order by l.ord limit 5) x),
    'stops_left', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = c.circuit_id and l.ord > c.leg
                    and v_state = 'LOADED' and c.ord <= public.convoy_ships_of(c.nation_id)),   -- 0437: a ship going home (empty, or over her share) has no circuit ahead
$h$),
  ('world.stats_fleet(uuid)', 1,
$h$      'aboard', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$,
$h$      'state', public.cargo_ship_state(p_fleet),   -- 0437: LOADED, RETURNING, HOME or LAID_UP; the page says the word when nothing is on board
      'aboard', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$),
  ('public.stats_fleet_list_rows(text,timestamp with time zone)', 1,
$h$from public.cargo_ships c where p_kind = 'CARGO'),
$h$,
$h$from public.cargo_ships c where p_kind = 'CARGO' and c.laid_up_at is null),   -- 0437: a retired (laid-up) cargo ship is out of the fleet
$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1,
$h$           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id
$h$,
$h$           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id and c.laid_up_at is null   -- 0437: a retired (laid-up) cargo ship is out of the fleet's count
$h$);
  for x in select distinct r.fn from rb_0437 r loop
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'', '');
    declare y record; begin
      for y in select * from rb_0437 r where r.fn = x.fn order by r.ord desc loop
        if (length(v_def) - length(replace(v_def, y.new, ''))) / length(y.new) <> 1 then
          raise exception 'rollback-0437: hunk % of % is not in the live body once', y.ord, y.fn;
        end if;
        v_def := replace(v_def, y.new, y.old);
      end loop;
    end;
    execute v_def;
  end loop;
  drop function public.cargo_ship_state(uuid);
  raise notice 'rollback-0437 ok: % hunks reversed, public.cargo_ship_state dropped', (select count(*) from rb_0437);
end $r$;
