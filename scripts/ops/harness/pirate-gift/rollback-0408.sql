-- 0408 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). There is no knob for this rule alone (gift_max_per_week 0 would stop every gift, the crowns' too).
-- This draft takes the rule away: public.capital_gift_roster and public.capital_gift_one go back to their bodies before 0408 (the three hunks reversed,
-- last first; each hunk's NEW text must occur once, else it refuses: a later file re-cut those lines and the draft is stale). A merchant of the pirates
-- is then on no gift roster again (0341). The gifts already given stay given: the rows in public.capital_gifts, the ledger and the day's spend are
-- history, and the money is in the houses and the harbours they traded at. Nothing is taken back.
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
  create temp table back_0408 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0408 values
  (1, 'public.capital_gift_roster(timestamp with time zone,uuid)',
$h$       -- 0408: a merchant of the pirates is on the roster as every merchant is (0341's "never gifted" line stood here): public.capital_gift_one pays her from the hoard, through public.pirate_pay
$h$,
$h$       and (h.human or not public.pirate_power(pl.nation_id))   -- 0341 (W18): a merchant of the pirates is never gifted: the hoard pays her founding and nothing after (docs/WORLD_POWERS.md 7.4, decided by default)
$h$),
  (2, 'public.capital_gift_one(timestamp with time zone,uuid)',
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
$h$,
$h$      v_res := public.capital_pays(r.cap_id, r.nation_id, r.player_id, 'CAPITAL_GIFT', r.capital, null, false,
                 jsonb_build_object('kind', 'CAPITAL_GIFT', 'payload', jsonb_build_object(
                   'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth)));
$h$),
  (3, 'public.capital_gift_one(timestamp with time zone,uuid)',
$h$      when sqlstate 'ZG408' then
        -- 0408: THE HOARD CANNOT PAY HER NOW: no money moved, nothing written (public.pirate_pay's whole or nothing); she is asked again next pass
        v_wait := v_wait + 1;
      when others then
        v_fail := v_fail + 1;
$h$,
$h$      when others then
        v_fail := v_fail + 1;
$h$);
  for h in select * from back_0408 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0408 rollback refuses: hunk % of % occurs % time(s), not once: a later file re-cut it and this draft is stale', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  if position('0408' in pg_get_functiondef('public.capital_gift_one(timestamp with time zone,uuid)'::regprocedure)) > 0
     or position('0408' in pg_get_functiondef('public.capital_gift_roster(timestamp with time zone,uuid)'::regprocedure)) > 0 then
    raise exception '0408 rollback FAIL: a line of 0408 is still in a body';
  end if;
  raise notice '0408 rolled back: a merchant of the pirates is on no gift roster again; the gifts given stay given.';
end $r$;
