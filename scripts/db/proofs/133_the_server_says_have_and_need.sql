-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 133 - THE SERVER SAYS HAVE AND NEED  (migration 0433; docs/dev-log/2026-11-15-short-server.md; the owner, 2026-11-15: "too much word should
--   be shorter. for example wave 24. just tell me what i have, and what is required.")
--
--   On a probe company of this world and on pure calls, everything rolled back by proof.mjs's transaction. EVERY MARKER FAILS BEFORE 0433: a refusal
--   said a sentence ("more Pepper than the hold will take"), a raid said "Your lookout saw them first.", the news said "Update: {title}", a best sale
--   whose full load passed her purse was "No money", and a room ladder served no level.
--
-- @pass HN_REFUSAL     a real BUY she cannot pay for is refused at the door with its code and figures as before, and its words are `Money have / need` from those figures; Supplies, Hold, Crew, Range and a closed sea say the same
-- @pass HN_REPORTS     a real company's fleet fought on 120 days through voyage.fight: every line short (no "lookout", "you are", "close quarters"), every sentence one of the short ones; a battle's line and a day's line short
-- @pass HN_NEWS        the eight news templates are the short ones and name the same words as before; this file's update is posted; the six long update titles are short
-- @pass HN_BEST_SALE   at a small purse, a good whose full load passes it is offered at the most she can pay for (cost within her purse), with have (her purse) and need (above it)
-- @pass HN_ROOM_LEVEL  world.house_room serves each ladder's level: Trading for fleets, the greater of Seamanship and Command for ships
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_prt   uuid := (select id from public.nations where code = 'PRT');
  c_ua    constant uuid := '00000000-0433-4000-8000-00000000000a';
  c_seed  constant uuid := '00000000-0433-4000-8000-0000000000f1';
  v_a     uuid;
  v_f     uuid;
  v_good  text;
  v_r     jsonb;
  v_x     jsonb;
  v_line  text;
  v_n     int := 0;
  v_d     int;
  v_rr    numeric;
  v_other record;
  v_purse bigint;
  v_card  jsonb;
  v_ok    int := 0;
  v_seen  int := 0;
  z       record;
begin
  execute $f$
    create function pg_temp.as_house(p_uid uuid) returns void language sql as $b$
      select set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true),
             set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
    $b$
  $f$;
  if to_regprocedure('cmd.refusal_line(text,jsonb)') is null then
    raise exception 'PROOF 133 FAIL: 0433 is not in this world';
  end if;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_ua, 'Casa Curta 0433', v_prt, 1, false) returning id into v_a;
  v_f := public.form_fleet(v_a, 'Curta 0433', v_lis);
  perform public.commission_ship(v_a, v_f, 'barca', 'Uno 0433', true, true);
  perform pg_temp.as_house(c_ua);

  -- ── HN_REFUSAL ──
  select g.code into v_good
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and public.port_offers(v_lis, g.id)
   order by world.mid_price(v_lis, g.id, null) desc nulls last, g.code limit 1;
  if v_good is null then
    raise exception 'PROOF 133 FAIL: Lisbon sells nothing in this world';
  end if;
  v_r := cmd.issue(v_f, 'BUY ' || v_good || ' 2');
  if coalesce((v_r->>'ok')::boolean, true) or v_r->>'error_code' not in ('E_INSUFFICIENT_FUNDS', 'E_NOT_ENOUGH_DUCATS')
     or jsonb_typeof(v_r->'figures') is distinct from 'object' or v_r->'figures'->>'unit' <> 'ducats'
     or v_r->>'error_message' is distinct from cmd.refusal_line(v_r->>'error_code', v_r->'figures')
     or v_r->>'error_message' !~ '^Money [0-9,.]+ / [0-9,.]+$' then
    raise exception 'PROOF 133 FAIL: a BUY she cannot pay for is not refused Money have / need: %', v_r;
  end if;
  if cmd.refusal('E_ENDURANCE', 'Gaivota carries 2.9 days of stores', cmd.figures(2.9, 33, 'days'))->>'sentence' <> 'Supplies 2.9 / 33 days'
     or cmd.refusal('E_HOLD_FULL', 'more Pepper than the hold will take', cmd.figures(120, 150, 't'))->>'sentence' <> 'Hold 120 / 150 t'
     or cmd.refusal('E_CREW_MAX', 'x', cmd.figures(8, 8, 'crew'))->>'sentence' <> 'Crew 8 / 8'
     or cmd.refusal('E_OUT_OF_REACH', 'x', cmd.figures(300, 450, 'miles'))->>'sentence' <> 'Range 300 / 450 miles'
     or cmd.refusal('E_NOT_ENOUGH_REPUTATION', 'Needs 300 Reputation: you have 60', cmd.figures(60, 300, 'reputation'))->>'sentence' <> 'Reputation 60 / 300'
     or cmd.refusal('E_NOT_DOCKED', 'Uno is not in port')->>'sentence' <> 'Uno is not in port' then
    raise exception 'PROOF 133 FAIL: a refusal''s words are not have / need';
  end if;
  select zz.code, zz.name, zz.title_min, zz.wave_min into z from public.sea_zones zz where zz.title_min > 1 and zz.wave_min > 1 order by zz.ord limit 1;
  if z.code is not null then
    v_x := public.sea_refusal(1, z.wave_min - 1, array[z.code]);
    if v_x->>'sentence' <> format('%s closed. Title 1 / %s. Waves %s / %s.', z.name, z.title_min, z.wave_min - 1, z.wave_min)
       or v_x->>'code' <> 'E_SEA_CLOSED' or (v_x->'figures'->>'needs_title')::int <> z.title_min then
      raise exception 'PROOF 133 FAIL: a closed sea is not have / need: %', v_x;
    end if;
  end if;
  raise notice 'PASS: HN_REFUSAL — BUY % refused %: "%" (figures %); Supplies, Hold, Crew, Range, Reputation and a closed sea say have / need',
    v_good, v_r->>'error_code', v_r->>'error_message', v_r->'figures';

  -- ── HN_REPORTS ──
  foreach v_rr in array array[3, 8, 16, 40]::numeric[] loop
    for v_d in 1 .. 30 loop
      v_x := voyage.fight(c_seed, v_d, v_f, v_rr);
      v_n := v_n + 1;
      if v_x->>'sentence' not in ('They stood off.', 'Slipped away.', 'Paid; let pass.', 'Ran; got clear.', 'They broke off.', 'Surrendered; plundered.',
                                  'Thrown back.', 'Paid off.', 'Plundered.') then
        raise exception 'PROOF 133 FAIL: a raid''s sentence is not a short one: %', v_x->>'sentence';
      end if;
      for v_line in select jsonb_array_elements_text(v_x->'rounds') loop
        if v_line ~* '(lookout|you are|close quarters|they come alongside|did not close|shot(s)? |for [0-9]+% damage|range —)' then
          raise exception 'PROOF 133 FAIL: a raid''s line is a long one: %', v_line;
        end if;
      end loop;
    end loop;
  end loop;
  if public.battle_words('{"outcome": "NO_FIGHT"}'::jsonb, '[]'::jsonb)->'lines'->>0 <> 'No fight.'
     or public.battle_words('{"outcome": "RANSOM", "rounds_fought": 0}'::jsonb, '[]'::jsonb)->'lines'->>0 <> 'She paid terms.'
     or voyage.report_line(2, 'CALM', '{"delay_hours": 6}'::jsonb) <> 'Day 2. Becalmed: 6 hours lost.'
     or voyage.report_line(5, 'PIRATES', '{"prose": "Thrown back.", "crew_lost": 3}'::jsonb) <> 'Day 5. Pirates. Thrown back. Crew −3.' then
    raise exception 'PROOF 133 FAIL: a battle or a day is not told short';
  end if;
  raise notice 'PASS: HN_REPORTS — % raid days of a real fleet, every sentence and line short; a battle and a day told short', v_n;

  -- ── HN_NEWS ──
  if (select string_agg(k.kind || '=' || k.en, ' | ' order by k.kind) from public.news_kinds k
       where k.kind in ('UPDATE', 'NEW_HARBOUR', 'RELATIONS', 'BIG_SALE', 'BIG_BUY', 'PRICE_SPIKE', 'PIRATES', 'CAPITAL_GIFT'))
     <> 'BIG_BUY={company} bought {qty} {good}: {n} · {city} | BIG_SALE={company} sold {qty} {good}: {n} · {city} | CAPITAL_GIFT={capital} → {company}: {n} | NEW_HARBOUR=New port: {city} | PIRATES={company} raided: {n} | PRICE_SPIKE={good} {p} · {city} | RELATIONS={a}–{b}: {stance} | UPDATE={title}'
     or exists (select 1 from public.news_kinds k
                 where (select array_agg(m[1] order by m[1]) from regexp_matches(k.en, '\{([a-z_]+)\}', 'g') m)
                       is distinct from (select array_agg(m[1] order by m[1]) from regexp_matches(k.ko, '\{([a-z_]+)\}', 'g') m))
     or (select w.detail->'words'->'title'->>'en' from public.world_news w where w.key = 'update:0433') is distinct from 'Shorter words'
     or exists (select 1 from public.world_news w where w.kind = 'UPDATE' and w.key in ('update:0375', 'update:0413', 'update:0422', 'update:0423', 'update:0425', 'update:0426')
                   and length(w.detail->'words'->'title'->>'en') > 40) then
    raise exception 'PROOF 133 FAIL: the news is not in short headlines';
  end if;
  raise notice 'PASS: HN_NEWS — eight short templates naming the same words in both languages; update 0433 posted; the long update titles short';

  -- ── HN_BEST_SALE ── the nearest other harbour that sells goods, bought there and sailed to first (no tray Max: the full load is her hold's)
  select p.id, p.code into v_other
    from public.ports p, public.ports hb
   where hb.id = v_lis and p.kind = 'HARBOUR' and p.id <> hb.id
     and exists (select 1 from public.port_goods pg where pg.port_id = p.id and public.port_offers(p.id, pg.good_id))
   order by voyage.gc_distance_nm(hb.lat, hb.lon, p.lat, p.lon), p.code limit 1;
  foreach v_purse in array array[2000, 8000, 30000, 120000]::bigint[] loop
    update public.players set ducats = v_purse where id = v_a;
    v_x := world.best_sales(v_f, v_other.id);
    for v_card in select e from jsonb_array_elements(v_x->'goods') e loop
      if jsonb_typeof(v_card->'need') = 'number' then
        v_seen := v_seen + 1;
        if (v_card->>'have')::numeric <> v_purse or (v_card->>'need')::numeric <= v_purse then
          raise exception 'PROOF 133 FAIL: a card''s have / need is not her purse against more: % (purse %)', v_card, v_purse;
        end if;
        if v_card->>'port' is not null then
          if (v_card->>'cost')::numeric > v_purse or (v_card->>'units')::numeric < 1 or coalesce((v_card->>'short')::boolean, false) then
            raise exception 'PROOF 133 FAIL: the sale at the most she can pay for is not within her purse: % (purse %)', v_card, v_purse;
          end if;
          v_ok := v_ok + 1;
        elsif not (v_card->>'short')::boolean then
          raise exception 'PROOF 133 FAIL: a card with no sale named is not short: %', v_card;
        end if;
      elsif v_card->>'port' is not null and (v_card->>'cost')::numeric > v_purse then
        raise exception 'PROOF 133 FAIL: a sale beyond her purse is named with no need: %', v_card;
      end if;
    end loop;
    exit when v_ok > 0;
  end loop;
  if v_ok = 0 then
    raise exception 'PROOF 133 FAIL: at no purse was a good offered at the most she can pay for (% cards with a need)', v_seen;
  end if;
  raise notice 'PASS: HN_BEST_SALE — from % at a purse of %: % card(s) sized to her purse with have / need (% with a need)', v_other.code, v_purse, v_ok, v_seen;

  -- ── HN_ROOM_LEVEL ──
  v_x := world.house_room();
  if not (v_x->>'company')::boolean
     or (v_x->'fleets'->>'level')::int is distinct from (public.player_progress(v_a)->'trading'->>'level')::int
     or (v_x->'ships'->>'level')::int is distinct from greatest(public.skill_level(v_a, 'SEAMANSHIP'), public.skill_level(v_a, 'COMMAND')) then
    raise exception 'PROOF 133 FAIL: the room does not serve each ladder''s level: %', v_x;
  end if;
  raise notice 'PASS: HN_ROOM_LEVEL — fleets.level % (Trading), ships.level % (Seamanship or Command)', v_x->'fleets'->>'level', v_x->'ships'->>'level';
  perform pg_temp.as_house(null);
end
$$;
