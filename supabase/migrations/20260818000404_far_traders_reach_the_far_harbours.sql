-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0404 - FAR TRADERS REACH THE FAR HARBOURS  (slice S4 of docs/SEA_CONDITIONS_AND_REGIONS.md: 24 merchant houses with hulls that hold the ocean legs)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: since the merchants' sea light (0397, 0399, 0400) a merchant sails only the seas her hull's wave resistance holds. Every merchant hull is of
--   size 1 to 3 (wave 12 to 39), so the harbours behind an ocean leg lost every merchant call: in the planner's simulation on the cached world, lit,
--   16 harbours (AMB BND CPT DIL GAL HAG HOB KOL MAK OLD PLO POR STG SYD TER TID) go from 142 merchant stops to none. None of them has a house of
--   its own whose fleet starts there. Their markets stand still and a player who gets there meets no traffic.
--
-- WHAT THIS FILE DOES (data only: no function is written, no rule moves, no switch is touched):
--   1. Six hull classes that exist since 0366 get ONE merchant loadout each (public.npc_loadouts, data/npc-loadouts.json): taforeia, retour, nao,
--      hourque (size 4, trade, wave 51) and indiaman, naucarr (size 5, trade, wave 63). The pattern is two suits of sails, a crow's nest, deal
--      planking (wave +3) and a sheet anchor (wave +3): 57 on a size-4 hull, 69 on a size-5 one. 57 holds every sea but the open Pacific (70),
--      which stays the players' prize, as the design says.
--   2. 24 houses are founded through public.npc_found (the one way a merchant is made: 0097, 0105, 0341), one fleet of one hull each: 20 of size
--      4 and 4 of size 5, as the design counts them. THEIR HOMES ARE THE FAR HARBOURS THEMSELVES, not the seven European yards the design named:
--      the planner (public.npc_plan) plans a merchant from her loop's first stop and every loop it offers returns there, so a house homed at the
--      harbour calls there every lap whatever the market says; a Lisbon house would call at Ambon only if Ambon happened to rank among her six
--      trade candidates. 15 harbours get one house, the nine that had the most calls a second one of another flag (CPT STG GAL MAK SYD DIL KOL
--      OLD TER). Her first loop is home, the nearest harbour the world remembers a course to that her hull holds both ways, and home (the same course back);
--      the planner re-plans her at her first lap start as it does every merchant.
--   3. PORT ROYAL GETS NO HOUSE. Its legs ask wave 12: the sea does not close it. It is a pirate home, and while the pirates bite no merchant's
--      planner offers a pirate home but her own (0341, docs/WORLD_POWERS.md 7.6); its merchants are the pirates' own, founded from the hoard by
--      public.pirate_found. A crown house living in the pirates' home would break that rule, so none is founded here.
--   4. npc_fleet_max rises by 24 (861 to 885 on prod). The design counted "861 and 837 founded: room for 24"; the pirate merchants (0341) have
--      taken berths since, and a fleet beyond the ceiling in roster order lies paused. The room the others had is unchanged.
--
-- WHERE THE GOLD COMES FROM: nowhere new. public.npc_found pays a house its starting money through public.founding_credit (0234): while the economy
--   is closed (prod), her country's capital pays it from its purse (public.capital_pays: Lisbon for 8 houses, Amsterdam 7, Seville 3, London 3,
--   Marseille 3), calling its realm if short. Each house: capital 40,000 (size 4) or 60,000 (size 5), plus the tuition of her skills, which she
--   pays at once to her home harbour. In all 1,040,000 d. of capital move from five capitals to 24 houses; the world total is unchanged. The
--   self-assert refuses the file if, closed, one ducat of theirs came from nowhere. Hulls and gear are endowed, as every merchant's are (0097, 0126).
--
-- LOCKS: inserts (players, fleets, ships, routes, npc_houses, npc_fleets, ledger), row writes on the five capitals' purses and the homes' purses,
--   one knob. No function, no switch. TIME: 0.4 s for the 24 foundings on the cached world, the file under 1 s. Expected on prod: 2.5 to 7 s
--   (6 to 18 times). The first cut took 30 s here: it asked public.npc_known_legs for every harbour a home has a leg to, to find the way back;
--   this cut sails the same course back. BUDGET: statement_timeout 30 s, lock_timeout 5 s; the self-assert fails if the foundings took more than 25 s.
-- NEWS: this file posts its own UPDATE row, public.news_update('0404', ...) (0347's law).
-- ROLLBACK (forward, owner only): scripts/ops/harness/far-traders/rollback-0404.sql, a draft: the 24 fleets taken off the roster (they lie paused
--   and stop sailing at their next tend). The houses, their money and the ledger stay: nothing is deleted and nothing is minted or burnt.
-- SELF-ASSERT: at the end of this file, on its own 24 houses only.
-- VERSION: 0404 = 0403 + 1.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '30s';
set local lock_timeout = '5s';

-- ── 0. THE GUARD ──
do $g$
begin
  if exists (select 1 from public.npc_loadouts where class_code = 'taforeia') then
    raise exception '0404 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.npc_found(jsonb)') is null or to_regprocedure('public.npc_sea_shut(numeric,uuid,jsonb)') is null
     or to_regprocedure('public.npc_known_legs(uuid)') is null or to_regprocedure('public.founding_credit(uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.pirate_home(uuid)') is null or to_regprocedure('public.news_update(text,text,text)') is null
     or to_regclass('public.npc_course_zones_memo') is null then
    raise exception '0404 refuses: the founding path (0097), the merchants'' sea rule (0397), the capital''s payment (0234), the pirate homes (0341) or the news (0347) are not in this world';
  end if;
  if (select count(*) from public.ship_classes c join public.class_profile cp on cp.class_code = c.code
       where (c.code, cp.size, c.wave) in (('taforeia', 4, 51), ('retour', 4, 51), ('nao', 4, 51), ('hourque', 4, 51), ('indiaman', 5, 63), ('naucarr', 5, 63))) <> 6 then
    raise exception '0404 refuses: the six hull classes of 0366 are not what its loadouts were measured on';
  end if;
end
$g$;

-- ── 1. THE LOADOUT of a far trader, one pattern a class (data/npc-loadouts.json) ──
insert into public.npc_loadouts (class_code, pattern, item_code, qty)
select c.code, 0, i.item, i.qty
  from unnest(array['taforeia', 'retour', 'nao', 'hourque', 'indiaman', 'naucarr']) c(code)
 cross join (values ('suit-of-sails', 2), ('crows-nest', 1), ('deal-planking', 1), ('sheet-anchor', 1)) i(item, qty);

-- ── 2. THE ROSTER: 24 houses, their homes, flags and hulls ──
create temp table roster_0404 (ord int primary key, home text, nation text, ink text, class text, company text, alt text, master text, ship text,
                               player_id uuid, to_code text, nm numeric) on commit drop;
insert into roster_0404 (ord, home, nation, ink, class, company, alt, master, ship) values
  ( 1, 'AMB', 'NLD', 'nld', 'retour',   'Kamer Ambon',           'Kamer Ambon II',         'Opperkoopman Steven van der Hagen', 'Gelderland'),
  ( 2, 'BND', 'NLD', 'nld', 'retour',   'Kamer Banda',           'Kamer Banda II',         'Opperkoopman Pieter Verhoeff',      'Hollandia'),
  ( 3, 'CPT', 'NLD', 'nld', 'retour',   'Kaapse Kamer',          'Kaapse Kamer II',        'Schipper Jan Harmensz',             'Drommedaris'),
  ( 4, 'CPT', 'PRT', 'prt', 'taforeia', 'Casa do Cabo',          'Casa do Cabo II',        'Capitão Bartolomeu Pais',           'São Brás'),
  ( 5, 'DIL', 'PRT', 'prt', 'taforeia', 'Casa de Timor',         'Casa de Timor II',       'Capitão Rui de Brito',              'Santa Cruz'),
  ( 6, 'DIL', 'NLD', 'nld', 'retour',   'Kamer Timor',           'Kamer Timor II',         'Schipper Apollonius Schotte',       'Zeelandia'),
  ( 7, 'GAL', 'PRT', 'prt', 'taforeia', 'Casa de Gale',          'Casa de Gale II',        'Capitão Lourenço de Almeida',       'Santa Catarina'),
  ( 8, 'GAL', 'NLD', 'nld', 'retour',   'Kamer Galle',           'Kamer Galle II',         'Schipper Willem Coster',            'Utrecht'),
  ( 9, 'HAG', 'ESP', 'esp', 'nao',      'Casa de las Marianas',  'Casa de Marianas II',    'Maestre Diego de Sanvitores',       'San Damián'),
  (10, 'HOB', 'ENG', 'eng', 'indiaman', 'Derwent Company',       'Derwent Company II',     'Captain John Hayes',                'Duke of Clarence'),
  (11, 'KOL', 'PRT', 'prt', 'taforeia', 'Casa de Coulão',        'Casa de Coulao II',      'Capitão Duarte Pacheco',            'São Tomé'),
  (12, 'KOL', 'FRA', 'eng', 'hourque',  'Comptoir du Malabar',   'Comptoir du Malabar II', 'Capitaine François Martin',         'Saint-Louis'),
  (13, 'MAK', 'NLD', 'nld', 'retour',   'Kamer Makassar',        'Kamer Makassar II',      'Schipper Cornelis Speelman',        'Tertholen'),
  (14, 'MAK', 'PRT', 'prt', 'taforeia', 'Casa de Macáçar',       'Casa de Macacar II',     'Capitão Francisco Vieira',          'São João Baptista'),
  (15, 'OLD', 'PRT', 'prt', 'taforeia', 'Casa de Goa Velha',     'Casa de Goa Velha II',   'Capitão Afonso de Noronha',         'Bom Jesus'),
  (16, 'OLD', 'PRT', 'prt', 'naucarr',  'Carreira da Índia',     'Carreira da India II',   'Capitão-mor João de Castro',        'Cinco Chagas'),
  (17, 'PLO', 'FRA', 'eng', 'hourque',  'Comptoir Port-Louis',   'Comptoir Port-Louis II', 'Capitaine Bertrand Mahé',           'Le Diligent'),
  (18, 'STG', 'ENG', 'eng', 'indiaman', 'Somers Isles Company',  'Somers Isles Co II',     'Captain Richard Moore',             'Sea Venture'),
  (19, 'STG', 'FRA', 'eng', 'hourque',  'Comptoir des Bermudes', 'Comptoir Bermudes II',   'Capitaine Jean Ribault',            'La Trinité'),
  (20, 'SYD', 'ENG', 'eng', 'indiaman', 'Port Jackson Company',  'Port Jackson Co II',     'Captain Arthur Hunter',             'Sirius'),
  (21, 'SYD', 'NLD', 'nld', 'retour',   'Kamer Nieuw-Holland',   'Kamer Nieuw-Holland II', 'Schipper Abel Visscher',            'Heemskerck'),
  (22, 'TER', 'PRT', 'prt', 'taforeia', 'Casa de Ternate',       'Casa de Ternate II',     'Capitão António Galvão',            'São Pedro'),
  (23, 'TER', 'ESP', 'esp', 'nao',      'Casa del Maluco',       'Casa del Maluco II',     'Maestre Pedro de Acuña',            'San Felipe'),
  (24, 'TID', 'ESP', 'esp', 'nao',      'Casa de Tidore',        'Casa de Tidore II',      'Maestre Gonzalo Gómez',             'Victoria');

-- ── 3. THE FOUNDING, through public.npc_found ──
create temp table clock_0404 (ms numeric) on commit drop;
do $f$
declare
  r       record;
  v_t0    timestamptz := clock_timestamp();
  v_ord   int;
  v_home  uuid;
  v_wave  numeric;
  v_speed numeric;
  v_leg   record;
  v_back  jsonb;
  v_cap   bigint;
begin
  select greatest((select coalesce(max(h.roster_ord), 0) from public.npc_houses h), (select coalesce(max(f.roster_ord), 0) from public.npc_fleets f)) into v_ord;
  for r in select * from roster_0404 order by ord loop
    select p.id into v_home from public.ports p where p.code = r.home and p.kind = 'HARBOUR';
    select c.wave + 6, c.speed_kn, case when cp.size >= 5 then 60000 else 40000 end into v_wave, v_speed, v_cap
      from public.ship_classes c join public.class_profile cp on cp.class_code = c.code where c.code = r.class;
    -- her first loop: the nearest harbour the world remembers a course to, that her hull holds both ways (the plain rule, no floor)
    -- (the way back is the same course sailed backwards: the same water, as public.npc_known_legs itself remembers a leg both ways)
    select l.to_port, l.code, l.course, l.nm, (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(l.course) with ordinality t(x, i)) as back into v_leg
      from public.npc_known_legs(v_home) l
      join public.ports p on p.id = l.to_port
     where p.kind = 'HARBOUR' and not p.is_ice_closed and not public.pirate_home(p.id)
       and public.npc_sea_shut(v_wave, l.to_port, l.course) is null
       and public.npc_sea_shut(v_wave, v_home, (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(l.course) with ordinality t(x, i))) is null
     order by l.nm, l.to_port
     limit 1;
    if v_home is null or v_leg.to_port is null then
      raise exception '0404 refuses: the world remembers no course out of % and back that a hull of wave % holds', r.home, v_wave;
    end if;
    v_back := v_leg.back;
    update roster_0404 x
       set to_code = v_leg.code, nm = v_leg.nm,
           player_id = public.npc_found(jsonb_build_object(
             'company', r.company, 'alt_company', r.alt, 'nation', r.nation, 'ink', r.ink, 'master', r.master,
             'blurb', format('A far trader of %s: one great hull that holds the ocean legs — under %s.', (select p.name from public.ports p where p.id = v_home), r.master),
             'capital', v_cap, 'patience', 0.30, 'wares', '[]'::jsonb, 'skills', jsonb_build_object('NAVIGATION', 2, 'HAGGLING', 1),
             'roster_ord', v_ord + r.ord,
             'fleets', jsonb_build_array(jsonb_build_object(
               'name', left(r.company, 24), 'roster_ord', v_ord + r.ord, 'home', r.home,
               'days', greatest(2, public.npc_leg_days(v_leg.nm, v_speed)),
               'ships', jsonb_build_array(jsonb_build_object('class', r.class, 'name', r.ship)),
               'officers', '[]'::jsonb,
               'stops', jsonb_build_array(jsonb_build_object('port', r.home, 'course', v_leg.course),
                                          jsonb_build_object('port', v_leg.code, 'course', v_back))))))
     where x.ord = r.ord;
  end loop;
  insert into clock_0404 values (round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end
$f$;

-- their courses in the merchants' memo (0397), where a row is missing: the sampler's own answer, kept
insert into public.npc_course_zones_memo (course_md5, zones)
select distinct on (md5(st.course::text)) md5(st.course::text), public.course_zones(st.course)
  from roster_0404 x
  join public.npc_fleets nf on nf.player_id = x.player_id
  join public.standing_route_stops st on st.route_id = nf.route_id
 where not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(st.course::text))
 order by md5(st.course::text)
on conflict (course_md5) do nothing;

-- ── 4. A BERTH FOR EACH: the ceiling rises by what was founded ──
update public.world_config set value = to_jsonb((value #>> '{}')::int + 24) where key = 'npc_fleet_max';

-- ── 5. THE SELF-ASSERT (its own 24 houses only) ──
do $m$
declare
  v_ms   numeric := (select ms from clock_0404);
  v_bad  text;
  v_cap  bigint;
  v_led  bigint;
  v_flow bigint;
begin
  if v_ms > 25000 then
    raise exception '0404 self-assert FAIL: the foundings took % ms (budget 25,000)', v_ms;
  end if;
  if (select count(*) from roster_0404 x join public.npc_houses h on h.player_id = x.player_id
       join public.ports p on p.id = h.home_port_id and p.code = x.home) <> 24
     or (select count(distinct x.home) from roster_0404 x) <> 15 then
    raise exception '0404 self-assert FAIL: not 24 houses at 15 homes';
  end if;
  -- one fleet of one hull of her class, at her home; her wave is the class''s and her kit''s; her purse is her capital; her loop is open to her
  select string_agg(x.company, ', ') into v_bad
    from roster_0404 x
    left join public.npc_fleets nf on nf.player_id = x.player_id
   where (select count(*) from public.npc_fleets f where f.player_id = x.player_id) <> 1
      or (select count(*) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = nf.fleet_id and c.code = x.class) <> 1
      or (select count(*) from public.ships s where s.player_id = x.player_id) <> 1
      or public.fleet_wave(nf.fleet_id) is distinct from (select c.wave + 6 from public.ship_classes c where c.code = x.class)
      or public.fleet_wave(nf.fleet_id) < 57
      or (select pl.ducats from public.players pl where pl.id = x.player_id) is distinct from (select h.capital from public.npc_houses h where h.player_id = x.player_id)
      or (select p.code from public.standing_route_stops st join public.ports p on p.id = st.port_id where st.route_id = nf.route_id and st.ord = 0) is distinct from x.home
      or (select count(*) from public.standing_route_stops st where st.route_id = nf.route_id) <> 2
      or public.npc_loop_sea_shut(nf.fleet_id,
           (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord) from public.standing_route_stops st where st.route_id = nf.route_id))
      or exists (select 1 from public.standing_route_stops st where st.route_id = nf.route_id
                  and not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(st.course::text)));
  if v_bad is not null then
    raise exception '0404 self-assert FAIL: not one hull of her class at wave 57 or more, her capital in her purse and an open loop from home: %', v_bad;
  end if;
  if (select count(*) from roster_0404 x join public.class_profile cp on cp.class_code = x.class where cp.size = 4) <> 20
     or (select count(*) from roster_0404 x join public.class_profile cp on cp.class_code = x.class where cp.size = 5) <> 4 then
    raise exception '0404 self-assert FAIL: not 20 hulls of size 4 and 4 of size 5';
  end if;
  if exists (select 1 from roster_0404 x join public.ports p on p.code = x.home where public.pirate_home(p.id)) then
    raise exception '0404 self-assert FAIL: a house is homed in a pirate home';
  end if;
  if public.wc_int('npc_fleet_max') < (select count(*) from public.npc_fleets) then
    raise exception '0404 self-assert FAIL: npc_fleet_max (%) is under the % fleets on the roster: some would never sail',
      public.wc_int('npc_fleet_max'), (select count(*) from public.npc_fleets);
  end if;
  -- THE GOLD: closed (and the purses lit), every ducat these houses hold or paid came out of a city''s purse and every ducat they paid went into
  -- one: their ledger and the cities'' flows that name them sum to nothing. Open, a founding is a plain credit, as 0105''s were.
  select coalesce(sum(h.capital), 0) into v_cap from roster_0404 x join public.npc_houses h on h.player_id = x.player_id;
  select coalesce(sum(l.ducats_delta), 0) into v_led from public.ledger l where l.player_id in (select x.player_id from roster_0404 x);
  select coalesce(sum(f.ducats), 0) into v_flow from public.treasury_flows f where f.player_id in (select x.player_id from roster_0404 x);
  if v_led <> v_cap or v_cap <> 20 * 40000 + 4 * 60000 then
    raise exception '0404 self-assert FAIL: the houses'' ledger sums to %, their capital to %', v_led, v_cap;
  end if;
  if public.economy_closed() and public.city_treasury_on() and v_led + v_flow <> 0 then
    raise exception '0404 self-assert FAIL: the economy is closed and % d. of the houses'' % did not come from a city''s purse (flows %)', v_led + v_flow, v_led, v_flow;
  end if;

  perform public.news_update('0404', 'Far traders now sail from the far harbours', '먼 항구에 원양 상단이 다닙니다');

  raise notice '0404 self-assert ok: FAR TRADERS REACH THE FAR HARBOURS. 24 houses at 15 homes, 20 hulls of size 4 (wave 57) and 4 of size 5 (wave 69), every first loop open to her hull: %. Capital % d. (closed %: cities'' flows %). npc_fleet_max %, fleets %. Foundings % ms.',
    (select string_agg(x.home || '-' || x.to_code, ' ' order by x.ord) from roster_0404 x), v_cap, public.economy_closed() and public.city_treasury_on(), v_flow,
    public.wc_int('npc_fleet_max'), (select count(*) from public.npc_fleets), v_ms;
end
$m$;
