-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 207 - EACH CITY SETS ITS TAX, 0 TO 30 %, AND HOME PAYS HALF  (migration 0505; owner-spec-plan-2026-11-25.md section 6, rows 54-55)
--
--   The owner: "Each city will have its own tax, with 0%~30%. Your own country or the city that has your HQ will provide less tax."
--   0505's self-assert reads world.tax_rate on a sea place. This proof goes through the doors at a real harbour, Lisbon: a company
--   founded by public.new_house (her home is Lisbon by her own FOUNDED event), a mayor who presses cmd.set_tax, and the charge itself,
--   public.profit_tax, on a profit of 10,000 d. No price, stock or dice is read. Rolled back by proof.mjs.
--
-- @pass T30_DARK        dark (as deployed): the mayor's 25 % is refused (E_TAX_BAND) and a company at her home pays what a company of
--                       her country away from home pays
-- @pass T30_NO_MOVE     lighting the switch moves no harbour's rate: world.tax_rate of all of them is equal before and after
-- @pass T30_DIAL        lit: the mayor's 30 % is taken and is the city's rate; 31 % is refused; a stranger pays by it as before
-- @pass T30_HOME_HALF   lit: a foreign company whose home is Lisbon pays 1,500 d. on 10,000 (half of 30 %); the same company before the
--                       switch, and a countryman of hers with another home, pay the stranger's rate
-- @pass T30_NEVER_BOTH  lit: a Portuguese company at home in Lisbon pays what her country already gave her, open (half) and closed
--                       (a quarter): the lower of the two cuts, never one on top of the other
-- ══════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0207-4000-8000-0000000000a1';
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_prt  uuid := public.port_nation(v_lis);
  v_oth  uuid;
  v_home uuid;      -- Portuguese, founded at Lisbon by the real door
  v_fh   uuid;      -- foreign, her home is Lisbon
  v_fa   uuid;      -- foreign, the same country, her home is elsewhere
  v_all0 text;
  v_all1 text;
  v_r    jsonb;
  v_d    jsonb;
  v_str  bigint;
  v_x    bigint;
begin
  if v_lis is null or v_prt is null then
    raise exception 'PROOF 207 FAIL: no Lisbon, or nobody holds it, in this world';
  end if;
  -- a country at peace with Lisbon's holder (no row in power_relations, or one that says peace)
  select g.nation_id into v_oth from public.great_powers g
   where not g.pirate and g.nation_id <> v_prt and public.power_stance(g.nation_id, v_prt) = 'peace' order by g.nation_id limit 1;
  if v_oth is null then
    raise exception 'PROOF 207 FAIL: no country at peace with Lisbon''s holder';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'regard_enabled');

  v_home := public.new_house(c_a, 'Casa da Prova 207', (select n.code from public.nations n where n.id = v_prt));
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 207 foreign home', v_oth, 0, false) returning id into v_fh;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 207 foreign away', v_oth, 0, false) returning id into v_fa;
  perform public.emit_event(v_fh, 'FOUNDED', jsonb_build_object('port', 'LIS'));
  if public.home_port_of(v_home) is distinct from v_lis or public.home_port_of(v_fh) is distinct from v_lis or public.home_port_of(v_fa) is not null then
    raise exception 'PROOF 207 FAIL: the homes are not as this proof needs them';
  end if;
  insert into public.port_mayor (port_id, player_id) values (v_lis, v_home)
  on conflict (port_id) do update set player_id = excluded.player_id, tax_rate = null, tax_set_at = null;
  perform cmd.assume_identity(c_a);

  -- ── DARK ──
  v_r := cmd.set_tax(v_lis, 0.25);
  if v_r->>'error_code' is distinct from 'E_TAX_BAND' or public.profit_tax(v_lis, 10000, v_fh) <> public.profit_tax(v_lis, 10000, v_fa)
     or public.profit_tax(v_lis, 10000, v_fa) <> round(10000 * world.tax_rate(v_lis)) then
    raise exception 'PROOF 207 FAIL: dark, the dial took 25 %%, or home paid less: % / % / %', v_r, public.profit_tax(v_lis, 10000, v_fh), public.profit_tax(v_lis, 10000, v_fa);
  end if;
  v_d := jsonb_build_object('home', public.profit_tax(v_lis, 10000, v_home), 'fh', public.profit_tax(v_lis, 10000, v_fh));
  raise notice 'PASS: T30_DARK - the mayor''s 25 %% refused (E_TAX_BAND); on 10,000 d. a foreign company at home in Lisbon pays % d., as her countryman away from home', v_d->>'fh';

  -- ── THE LIGHT moves nothing ──
  select md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)) into v_all0 from public.ports h where h.kind = 'HARBOUR';
  update public.world_config set value = 'true'::jsonb where key = 'tax_thirty_enabled';
  select md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)) into v_all1 from public.ports h where h.kind = 'HARBOUR';
  if v_all1 is distinct from v_all0 then
    raise exception 'PROOF 207 FAIL: lighting the switch moved a harbour''s rate';
  end if;
  raise notice 'PASS: T30_NO_MOVE - % harbours, the rate of each equal before and after the switch', (select count(*) from public.ports h where h.kind = 'HARBOUR');

  -- ── THE DIAL ──
  v_r := cmd.set_tax(v_lis, 0.31);
  if v_r->>'error_code' is distinct from 'E_TAX_BAND' then
    raise exception 'PROOF 207 FAIL: lit, 31 %% was not refused: %', v_r;
  end if;
  v_r := cmd.set_tax(v_lis, 0.30);
  v_str := public.profit_tax(v_lis, 10000, v_fa);
  if (v_r->>'ok')::boolean is not true or world.tax_rate(v_lis) <> 0.30 or v_str <> 3000 then
    raise exception 'PROOF 207 FAIL: lit, the mayor''s 30 %% is not the city''s rate: % / % / %', v_r, world.tax_rate(v_lis), v_str;
  end if;
  raise notice 'PASS: T30_DIAL - 31 %% refused, 30 %% taken; the city''s rate %; a stranger pays % d. on 10,000', world.tax_rate(v_lis), v_str;

  -- ── HOME PAYS HALF ──
  v_x := public.profit_tax(v_lis, 10000, v_fh);
  if v_x <> 1500 or public.profit_tax(v_lis, 10000, v_fa) <> 3000 then
    raise exception 'PROOF 207 FAIL: lit, home did not pay half: % (her countryman away %)', v_x, public.profit_tax(v_lis, 10000, v_fa);
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'tax_thirty_enabled';
  if public.profit_tax(v_lis, 10000, v_fh) <> 3000 then
    raise exception 'PROOF 207 FAIL: dark again, home still pays less';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'tax_thirty_enabled';
  raise notice 'PASS: T30_HOME_HALF - at 30 %% a foreign company at home in Lisbon pays % d. on 10,000; her countryman away from home 3,000; the switch dark again, she pays 3,000', v_x;

  -- ── NEVER BOTH ──
  v_x := public.profit_tax(v_lis, 10000, v_home);
  if v_x <> 1500 then
    raise exception 'PROOF 207 FAIL: open, a Portuguese company at home pays %, not her country''s half (1,500)', v_x;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
  if public.profit_tax(v_lis, 10000, v_home) <> round(10000 * 0.30 * public.country_factor('home'))
     or public.profit_tax(v_lis, 10000, v_home) > 1500
     or public.profit_tax(v_lis, 10000, v_fh) <> least(1500, round(10000 * least(0.30 * public.country_factor('peace'), greatest(0.30, public.wc_num('tariff_rate_max'))))) then
    raise exception 'PROOF 207 FAIL: closed, the two cuts were stacked or the better one was not taken: home % foreign-home %',
      public.profit_tax(v_lis, 10000, v_home), public.profit_tax(v_lis, 10000, v_fh);
  end if;
  raise notice 'PASS: T30_NEVER_BOTH - a Portuguese company at home in Lisbon pays % d. open (her country''s half, not a quarter) and % d. closed (her country''s own factor, the lower)',
    v_x, public.profit_tax(v_lis, 10000, v_home);
end
$p$;
