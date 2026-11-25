-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 205 - A COMPANY TAKES A NEW NAME  (migration 0503; docs/dev-log/2026-11-25-company-name.md)
--
--   The owner, 2026-11-25: a company's name is asked at the founding, overlaps no other name (countries, trade goods, other
--   companies; no special characters), may be changed once for free, and after that only for a payment that is not decided yet.
--   Played through the real doors (cmd.found_house, cmd.rename_company, world.player). Rolled back by proof.mjs.
--   TIME-PROOF: no step reads the clock, a day, an hour or a wait. WORLD-PROOF: every company it reads is its own; its names are
--   made free first (a suffix no company holds), and the country, place and good it tries are read from the static tables.
--
-- @pass CN_RULE     the rule alone: 3 to 24 characters; letters of any script and digits with one space between words; every special character, odd space and stray mark refused
-- @pass CN_TAKEN    a country's, a place's, a trade good's and another company's name are refused in any case, each in its own words; her own name in another case is hers
-- @pass CN_FOUND    founding asks the rule: each bad name is refused with the rule's sentence and makes no company; a good name founds one with her free rename unused
-- @pass CN_RENAME   the free rename: the name is written once, the count is 1, one event, no coin moves, world.player serves it, and the name she left is free for another
-- @pass CN_PAID     the next rename is refused in plain words (E_RENAME_PAID) whatever the name, and changes nothing; her own name again is still no rename
-- @pass CN_OLD      a name that stood before the rule and breaks it is kept as it is, and its company still has her one free rename to a name the rule takes
-- @pass CN_DOORS    the door is for a signed-in player alone and takes no player id; the rule, the count and the core are for no client and not service_role
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a constant uuid := '00000000-0503-4000-8000-0000000002a1';
  c_b constant uuid := '00000000-0503-4000-8000-0000000002b1';
  c_o constant uuid := '00000000-0503-4000-8000-0000000002c1';
  c_old constant text := 'Casa-Velha & C. 205';
  v_names text[];
  v_na text; v_nb text; v_nc text; v_nd text;
  v_nation text; v_place text; v_good text; v_code text;
  v_a uuid; v_b uuid; v_o uuid;
  v_r jsonb; v_w jsonb; x record;
  v_purse bigint; v_led bigint; v_n int := 0;
begin
  select array_agg(c.nm order by c.i) into v_names
    from (select i, format('Casa Prova 205 %s', i) as nm from generate_series(1, 5000) i
           where not exists (select 1 from public.players p where lower(p.company_name) = lower(format('Casa Prova 205 %s', i)))
           order by i limit 4) c;
  v_na := v_names[1]; v_nb := v_names[2]; v_nc := v_names[3]; v_nd := v_names[4];
  select n.name into v_nation from public.nations n where n.name ~ '^[A-Za-z]{3,24}$' order by n.code limit 1;
  select q.name into v_place from public.ports q
   where q.name ~ '^[A-Za-z]{3,24}$' and not exists (select 1 from public.nations n where lower(n.name) = lower(q.name))
     and not exists (select 1 from public.ports c where lower(c.country) = lower(q.name)) order by q.code limit 1;
  select g.name into v_good from public.goods g
   where g.name ~ '^[A-Za-z]{3,24}$' and not exists (select 1 from public.nations n where lower(n.name) = lower(g.name))
     and not exists (select 1 from public.ports q where lower(q.name) = lower(g.name) or lower(q.country) = lower(g.name)) order by g.code limit 1;
  if v_nd is null or v_nation is null or v_place is null or v_good is null then
    raise exception 'CN_RULE: the scene cannot be set (names %, country %, place %, good %)', v_names, v_nation, v_place, v_good;
  end if;

  -- CN_RULE
  for x in
    select * from (values
      ('ab'), (''), (repeat('a', 25)), ('A*B'), ('Casa-Nova'), ('Casa_Nova'), ('O''Brien'), ('Casa.Nova'), ('Casa, Nova'), ('Casa & Nova'),
      ('Casa <b>'), ('Casa "Nova"'), ('Casa/Nova'), ('Casa' || chr(92) || 'Nova'), ('Casa (Nova)'), ('Casa Nova!'), ('Casa@Nova'), ('Casa#1'), ('100% Casa'),
      ('Casa  Nova'), (' Casa Nova'), ('Casa Nova '), ('Casa' || chr(9) || 'Nova'), ('Casa' || chr(10) || 'Nova'),
      ('Casa' || chr(160) || 'Nova'), ('Casa' || chr(8203) || 'Nova'), ('Casa' || chr(8239) || 'Nova'), ('Casa' || chr(12288) || 'Nova'),
      (repeat(chr(12644), 3)), ('Casa' || chr(4447) || 'Nova'), ('Casa' || chr(8206) || 'Nova'), ('Casa ' || chr(9733)), ('Casa ' || chr(128674)), ('Cafe' || chr(769) || ' Nova'),
      ('Casa' || chr(215) || 'Nova'), ('Casa' || chr(8212) || 'Nova'), ('Casa' || chr(12290)), ('Casa' || chr(65281))
    ) t(nm)
  loop
    v_n := v_n + 1;
    if public.company_name_refusal(x.nm, null)->>'code' is distinct from 'E_BAD_NAME' or coalesce(public.company_name_refusal(x.nm, null)->>'sentence', '') = '' then
      raise exception 'CN_RULE: "%" is not refused as E_BAD_NAME: %', x.nm, public.company_name_refusal(x.nm, null);
    end if;
  end loop;
  for x in
    select * from (values
      (v_na), ('abc'), (repeat('a', 24)), ('Casa 1 2 3'), ('Casa Vaiv' || chr(233) || 'm 205'), ('Balc' || chr(227) || 'o 205'),
      (chr(54620) || chr(44544) || ' ' || chr(54924) || chr(49324) || ' 205'),   -- Hangul
      (chr(1050) || chr(1086) || chr(1084) || chr(1087) || ' 205'),              -- Cyrillic
      (chr(21830) || chr(20250) || ' 205'),                                      -- Chinese characters
      (chr(12363) || chr(12356) || chr(12375) || chr(12419) || ' 205'),          -- hiragana
      (chr(917) || chr(964) || chr(945) || chr(953) || ' 205'),                  -- Greek
      (chr(1588) || chr(1585) || chr(1603) || chr(1577) || ' 205')               -- Arabic
    ) t(nm)
  loop
    if exists (select 1 from public.players p where lower(p.company_name) = lower(x.nm)) then
      continue;   -- a company of this world holds it: not this proof's to judge
    end if;
    if public.company_name_refusal(x.nm, null) is not null then
      raise exception 'CN_RULE: "%" is refused though it is letters, digits and single spaces: %', x.nm, public.company_name_refusal(x.nm, null);
    end if;
  end loop;
  raise notice 'PASS: CN_RULE — % names with a special character, an odd space, a stray mark or a bad length refused; Latin with accents, Hangul, Cyrillic, Chinese, kana, Greek and Arabic letters with digits and single spaces pass', v_n;

  -- CN_TAKEN
  v_a := public.new_house(c_a, v_na, 'PRT');
  if public.company_name_refusal(upper(v_nation), null) ->> 'sentence' not like '%country%' or public.company_name_refusal(lower(v_nation), null) ->> 'code' <> 'E_NAME_TAKEN'
     or public.company_name_refusal(upper(v_place), null) ->> 'sentence' not like '%place%' or public.company_name_refusal(lower(v_place), null) ->> 'code' <> 'E_NAME_TAKEN'
     or public.company_name_refusal(upper(v_good), null) ->> 'sentence' not like '%trade good%' or public.company_name_refusal(lower(v_good), null) ->> 'code' <> 'E_NAME_TAKEN'
     or public.company_name_refusal(upper(v_na), null) ->> 'sentence' not like '%company%' or public.company_name_refusal(lower(v_na), null) ->> 'code' <> 'E_NAME_TAKEN'
     or public.company_name_refusal(upper(v_na), v_a) is not null then
    raise exception 'CN_TAKEN: a country (%), a place (%), a good (%) or a company (%) is not refused in every case in its own words, or her own name is refused to her', v_nation, v_place, v_good, v_na;
  end if;
  -- a good is taken by its code too (its words with spaces), where the code is not its name
  select replace(g.code, '-', ' ') into v_code from public.goods g
   where replace(lower(g.code), '-', ' ') <> lower(g.name) and g.code ~ '^[a-z]+(-[a-z]+)*$' and char_length(g.code) between 3 and 24
     and not exists (select 1 from public.nations n where lower(n.name) = replace(g.code, '-', ' '))
     and not exists (select 1 from public.ports q where lower(q.name) = replace(g.code, '-', ' ') or lower(q.country) = replace(g.code, '-', ' '))
   order by g.code limit 1;
  if v_code is not null and public.company_name_refusal(initcap(v_code), null) ->> 'sentence' not like '%trade good%' then
    raise exception 'CN_TAKEN: a good''s code (%) is not refused', v_code;
  end if;
  raise notice 'PASS: CN_TAKEN — country %, place %, good % and company "%" refused in upper and lower case, each named as what it is; her own name in capitals is hers', v_nation, v_place, v_good, v_na;

  -- CN_FOUND
  perform cmd.assume_identity(c_b);
  v_n := 0;
  for x in
    select * from (values (upper(v_na), 'E_NAME_TAKEN'), ('  ' || lower(v_na) || ' ', 'E_NAME_TAKEN'), (upper(v_nation), 'E_NAME_TAKEN'), (lower(v_place), 'E_NAME_TAKEN'),
                          (upper(v_good), 'E_NAME_TAKEN'), ('A*B', 'E_BAD_NAME'), ('ab', 'E_BAD_NAME'), ('Casa  Prova', 'E_BAD_NAME'), (c_old, 'E_BAD_NAME')) t(nm, code)
  loop
    v_n := v_n + 1;
    v_r := cmd.found_house(x.nm, 'PRT');
    if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' is distinct from x.code
       or v_r ->> 'error_message' is distinct from public.company_name_refusal(btrim(x.nm), null) ->> 'sentence'
       or jsonb_array_length(v_r -> 'fixes') < 1 or exists (select 1 from public.players p where p.auth_uid = c_b) then
      raise exception 'CN_FOUND: founding as "%" is not refused as % with the rule''s sentence and a fix: %', x.nm, x.code, v_r;
    end if;
  end loop;
  v_r := cmd.found_house('  ' || v_nb || ' ', 'PRT');
  select p.id into v_b from public.players p where p.auth_uid = c_b;
  v_w := world.player() -> 'player';
  if not (v_r ->> 'ok')::boolean or v_b is null or v_w ->> 'company_name' <> v_nb or (v_w ->> 'renames')::int <> 0 or (v_w ->> 'rename_free')::boolean is not true
     or (select count(*) from public.fleets f where f.player_id = v_b) < 1 then
    raise exception 'CN_FOUND: "%" did not found a company with a fleet and her free rename unused: % / %', v_nb, v_r, v_w - 'reputation' - 'levels';
  end if;
  raise notice 'PASS: CN_FOUND — % bad names refused at the founding with the rule''s own sentence, no company made; "%" founded one (a fleet, renames 0, rename_free true)', v_n, v_nb;

  -- CN_RENAME
  perform cmd.assume_identity(c_a);
  select p.ducats into v_purse from public.players p where p.id = v_a;
  select count(*) into v_led from public.ledger l where l.player_id = v_a;
  for x in
    select * from (values (upper(v_nb), 'E_NAME_TAKEN'), (lower(v_nation), 'E_NAME_TAKEN'), (upper(v_place), 'E_NAME_TAKEN'), (lower(v_good), 'E_NAME_TAKEN'),
                          ('A*B', 'E_BAD_NAME'), ('ab', 'E_BAD_NAME'), (repeat('b', 25), 'E_BAD_NAME'), (c_old, 'E_BAD_NAME')) t(nm, code)
  loop
    v_r := cmd.rename_company(x.nm);
    if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' is distinct from x.code or coalesce(v_r ->> 'error_message', '') = ''
       or (select p.company_name || '/' || p.renames from public.players p where p.id = v_a) <> v_na || '/0' then
      raise exception 'CN_RENAME: renaming to "%" is not refused as %, or it changed her: %', x.nm, x.code, v_r;
    end if;
  end loop;
  v_r := cmd.rename_company(' ' || v_na || ' ');
  if not (v_r ->> 'ok')::boolean or (v_r ->> 'changed')::boolean or (select p.renames from public.players p where p.id = v_a) <> 0 then
    raise exception 'CN_RENAME: her own name again changed or counted something: %', v_r;
  end if;
  v_r := cmd.rename_company('  ' || v_nc || ' ');
  v_w := world.player() -> 'player';
  if not (v_r ->> 'ok')::boolean or not (v_r ->> 'changed')::boolean or v_r ->> 'from' <> v_na or v_r ->> 'to' <> v_nc or (v_r ->> 'renames')::int <> 1 or (v_r ->> 'rename_free')::boolean
     or v_w ->> 'company_name' <> v_nc or (v_w ->> 'renames')::int <> 1 or (v_w ->> 'rename_free')::boolean
     or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'COMPANY_RENAMED') <> 1
     or (select e.payload from public.events e where e.player_id = v_a and e.kind = 'COMPANY_RENAMED') <> jsonb_build_object('from', v_na, 'to', v_nc)
     or (select p.ducats from public.players p where p.id = v_a) <> v_purse or (select count(*) from public.ledger l where l.player_id = v_a) <> v_led then
    raise exception 'CN_RENAME: the free rename did not write the name once, count 1, leave one event and move no coin: % / %', v_r, v_w - 'reputation' - 'levels';
  end if;
  -- the name she left is free: company B takes it with HER free rename
  perform cmd.assume_identity(c_b);
  v_r := cmd.rename_company(v_na);
  if not (v_r ->> 'ok')::boolean or (select p.company_name || '/' || p.renames from public.players p where p.id = v_b) <> v_na || '/1' then
    raise exception 'CN_RENAME: the name a company left could not be taken by another: %', v_r;
  end if;
  raise notice 'PASS: CN_RENAME — 8 bad names refused and her own name again counted nothing; "%" became "%" (renames 1, one COMPANY_RENAMED event, the purse unmoved, no ledger row), and another company took the name she left', v_na, v_nc;

  -- CN_PAID
  perform cmd.assume_identity(c_a);
  for x in select * from (values (v_nd), (upper(v_nc)), ('A*B'), (v_nation)) t(nm) loop
    v_r := cmd.rename_company(x.nm);
    if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' is distinct from 'E_RENAME_PAID'
       or v_r ->> 'error_message' <> 'Your free rename is used. Another rename is not available yet.'
       or (select p.company_name || '/' || p.renames from public.players p where p.id = v_a) <> v_nc || '/1' then
      raise exception 'CN_PAID: a second rename (to "%") is not refused as E_RENAME_PAID, or it changed her: %', x.nm, v_r;
    end if;
  end loop;
  v_r := cmd.rename_company(v_nc);
  if not (v_r ->> 'ok')::boolean or (v_r ->> 'changed')::boolean or (v_r ->> 'rename_free')::boolean
     or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'COMPANY_RENAMED') <> 1
     or (select p.ducats from public.players p where p.id = v_a) <> v_purse then
    raise exception 'CN_PAID: her own name again is refused, or a refused rename wrote something: %', v_r;
  end if;
  raise notice 'PASS: CN_PAID — four second renames refused "Your free rename is used. Another rename is not available yet." (E_RENAME_PAID); name, count, events and purse unmoved; her own name again is ok and no rename';

  -- CN_OLD: a name from before the rule (written by the server's own maker, which the rule does not judge)
  v_o := public.new_house(c_o, c_old, 'PRT');
  perform cmd.assume_identity(c_o);
  v_w := world.player() -> 'player';
  if public.company_name_refusal(c_old, null) ->> 'code' <> 'E_BAD_NAME' or v_w ->> 'company_name' <> c_old or (v_w ->> 'rename_free')::boolean is not true then
    raise exception 'CN_OLD: the old name is not kept as it is with her free rename: %', v_w - 'reputation' - 'levels';
  end if;
  v_r := cmd.rename_company(c_old);
  if not (v_r ->> 'ok')::boolean or (v_r ->> 'changed')::boolean then
    raise exception 'CN_OLD: her old name again is refused: %', v_r;
  end if;
  v_r := cmd.rename_company(v_nd);
  if not (v_r ->> 'ok')::boolean or (select p.company_name from public.players p where p.id = v_o) <> v_nd then
    raise exception 'CN_OLD: the company with an old name could not use her free rename: %', v_r;
  end if;
  raise notice 'PASS: CN_OLD — "%" (special characters, from before the rule) is served and kept untouched, and her one free rename took her to "%"', c_old, v_nd;

  -- CN_DOORS
  if not has_function_privilege('authenticated', 'cmd.rename_company(text)', 'execute')
     or has_function_privilege('anon', 'cmd.rename_company(text)', 'execute') or has_function_privilege('service_role', 'cmd.rename_company(text)', 'execute')
     or exists (select 1 from unnest(array['public.company_name_refusal(text,uuid)', 'public.company_rename_free(integer)', 'public.rename_company(uuid,text)']) q
                 where has_function_privilege('authenticated', q::regprocedure, 'execute') or has_function_privilege('anon', q::regprocedure, 'execute')
                    or has_function_privilege('service_role', q::regprocedure, 'execute'))
     or pg_get_function_identity_arguments('cmd.rename_company(text)'::regprocedure) <> 'p_name text'
     or (select count(*) from public.client_rpc_entry_points() e where e.schema_name = 'cmd' and e.function_name = 'rename_company' and e.fn is not null) <> 1 then
    raise exception 'CN_DOORS: the grants are not the contract';
  end if;
  perform cmd.assume_identity('00000000-0503-4000-8000-0000000002d1'::uuid);
  v_r := cmd.rename_company(v_names[1] || ' x');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_NO_HOUSE' then
    raise exception 'CN_DOORS: an account with no company is not refused: %', v_r;
  end if;
  raise notice 'PASS: CN_DOORS — cmd.rename_company(p_name) is for authenticated alone (not anon, not service_role) and takes no player id; the rule, the count and the core are for no client; an account with no company is refused (E_NO_HOUSE)';
end $p$;
