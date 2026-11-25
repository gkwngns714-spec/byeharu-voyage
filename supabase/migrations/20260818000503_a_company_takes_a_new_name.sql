-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: one row, public.news_update('0503', ...): a company may be renamed once for free, and a name follows one rule.
-- 0503 - A COMPANY TAKES A NEW NAME  (no switch: the rule and the door are in use as soon as this is applied)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (docs/design/owner-spec-2026-11-25.md): "COMPANY NAME - you can change it. When creating the account for
--   the first time, it will ask you to assign a company name. It should not overlap with any other names (countries, trade goods,
--   and with other player info, no special characters). After that you can change your name again for free (1st time), but later
--   if you want to, you will have to pay (real money currency - not decided yet)."
--   The plan: docs/design/owner-spec-plan-2026-11-25.md, slice A1 `company-name` (rows 1, 3, 4).
--
-- WHAT:
--   public.company_name_refusal(name, player)   THE ONE RULE OF A COMPANY'S NAME, read by founding and by renaming. Null: the name
--                                may be taken. Else {code, sentence}:
--                                  E_BAD_NAME    not 3 to 24 characters; or not letters (of any script) and digits with one space
--                                                between words (no special characters, no space at an end, no two spaces together)
--                                  E_NAME_TAKEN  whatever the case of its letters: a country's name (public.nations, and the
--                                                countries the harbours lie in), a place's name (public.ports: a city or a place at sea), a trade good's name
--                                                or code (public.goods), or another company's name (public.players; `player` is the
--                                                company that asks, so her own name in another case is hers to take)
--   public.company_rename_free(renames)         MAY SHE RENAME WITHOUT PAYING: true while she has renamed 0 times. The one place
--                                the free count is written.
--   public.rename_company(player, name), cmd.rename_company(name)   THE DOOR. Her name again: nothing changes, nothing is counted.
--                                Her free rename used: refused (E_RENAME_PAID, "not available yet") until the owner decides the
--                                payment. NO PAYMENT CODE IS IN THIS FILE: no coin, no price, no purchase. Else the rule judges;
--                                the name is written, players.renames goes up by one, one event COMPANY_RENAMED {from, to}.
--   cmd.found_house              (1 hunk) asks the rule before the house is made, and answers with the rule's own sentence.
--   world.player                 (1 hunk) serves `renames` and `rename_free` beside the name.
--   public.client_rpc_entry_points   (1 hunk) the door is in the client registry.
--   public.players.renames       int not null default 0: how many times she has renamed. Everyone starts at 0 (one free rename).
--   players_company_name_lower_key   a unique index on lower(company_name) over the companies of players (not the merchants'
--                                houses, whose rows no door here writes). BUILT ONLY IF no two such names are equal but for case
--                                at this moment; otherwise it is left out, said in the notice, and the rule stands in the
--                                function alone (a race of two presses could then pass two names equal but for case).
-- EXISTING NAMES STAY. No row of public.players is rewritten but by the column's default; a name the rule would refuse today is
--   kept, and its company may keep it for ever. The table's own constraints (unique, 3 to 24) stand as they were.
-- THE LETTERS are written as ranges of code points, so the answer is the same on every server whatever its locale: Latin, Greek,
--   Cyrillic, Armenian, Hebrew, Arabic, the Indian scripts, Thai, Georgian, Hangul, kana and Chinese characters. Digits are 0-9.
--   An accent written as a separate mark is refused: the client sends the name composed (NFC).
-- NOT CHANGED: any knob (none is added); public.new_house; cmd.rename_fleet; cmd.change_country; any coin; the ledger.
-- ROWS: one column (a default, no table rewrite), at most one index on a small table. No table, no cron, no beat step. 0 new rows a
--   minute; one event row a rename (at most one a company until payment is decided).
-- budget: no table, no cron job, no autovacuum or fillfactor change.
-- LOCKS: ALTER TABLE public.players ADD COLUMN (a moment, ACCESS EXCLUSIVE); CREATE UNIQUE INDEX on public.players (writes wait while
--   it builds: one small table); CREATE FUNCTION x4; CREATE OR REPLACE x3 by hunks. TIME: a second or two. BUDGET: statement_timeout
--   60 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): a migration reversing the three hunks (OLD texts below verbatim), dropping the four functions and
--   the index; the column may stay (nothing else reads it).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the door for `authenticated` alone, every other new function for no client and not service_role; no knob moved;
--   every company's renames 0. THE RULE, asked with no row at all: lengths, special characters, spaces, scripts. THE PROBE (rolled
--   back by a raised sentinel; its own three companies' rows alone): it reads NO live company, market or dice. Its names are made
--   free before they are used (a suffix no company holds, whatever companies the world has), and the country, city and good it
--   tries are the first single-word names of the static tables. Founding refuses a country, a city, a good, a taken name in
--   another case and a special character, then founds; renaming refuses the same, renames once (no coin moves, one event, the old
--   name free again), and refuses the second with E_RENAME_PAID. Nothing in it reads the clock.
-- VERSION: 0503 (0497 a-wreck-can-sell, 0498 jobs-never-lose, 0499 to 0501 and 0502 no-ruinous-run come first; none of them hunks
--   cmd.found_house; this file's hunks keep their OLD lines, so a hunk of theirs on world.player or the registry still finds its own).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['cmd.found_house(text,text)', 'world.player()', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.company_name_refusal(text,uuid)', 'public.company_rename_free(integer)',
                                    'public.rename_company(uuid,text)', 'cmd.rename_company(text)'];
  c_door   constant text := 'cmd.rename_company(text)';
  c_a      constant uuid := '00000000-0503-4000-8000-000000000001';
  c_b      constant uuid := '00000000-0503-4000-8000-000000000002';
  c_c      constant uuid := '00000000-0503-4000-8000-000000000003';
  c_d      constant uuid := '00000000-0503-4000-8000-000000000004';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_index     boolean := false;
  v_lived     boolean := false;
  v_a         uuid;
  v_b         uuid;
  v_c         uuid;
  v_r         jsonb;
  v_w         jsonb;
  v_names     text[];
  v_na        text;
  v_nb        text;
  v_nc        text;
  v_nd        text;
  v_ne        text;
  v_nation    text;
  v_city      text;
  v_good      text;
  v_purse     bigint;
  v_led       bigint;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.company_name_refusal(text,uuid)') is not null or to_regprocedure('cmd.rename_company(text)') is not null
     or exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'players' and c.column_name = 'renames') then
    raise exception '0503 refuses: it has been applied once';
  end if;
  if to_regprocedure('cmd.found_house(text,text)') is null or to_regprocedure('world.player()') is null
     or to_regprocedure('public.client_rpc_entry_points()') is null or to_regprocedure('cmd.refuse(text,text,jsonb)') is null
     or to_regprocedure('cmd.refused_envelope(text,text)') is null or to_regprocedure('public.emit_event(uuid,text,jsonb)') is null
     or to_regprocedure('public.current_player_id()') is null or to_regprocedure('public.news_update(text,text,text)') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0503 refuses: a function this file calls or hunks is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE COUNT, AND THE INDEX WHERE IT CAN STAND ──
  alter table public.players add column renames integer not null default 0;
  comment on column public.players.renames is
    '0503: how many times this company has taken a new name (public.rename_company). 0: her one free rename is unused (public.company_rename_free).';
  if not exists (select 1 from public.players p where not p.is_npc group by lower(p.company_name) having count(*) > 1) then
    create unique index players_company_name_lower_key on public.players (lower(company_name)) where not is_npc;
    v_index := true;
  end if;

  -- ── 3. THE RULE AND THE DOOR ──
  execute $f$
create function public.company_name_refusal(p_name text, p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0503: THE ONE RULE OF A COMPANY'S NAME (the owner, 2026-11-25), read by cmd.found_house and public.rename_company and by nothing
-- else. p_name is the name as it would be written (the callers trim it); p_player is the company that asks, or null at a founding.
-- Null: the name may be taken. Else {code, sentence}:
--   E_BAD_NAME    not 3 to 24 characters; or anything but letters and digits with ONE space between words
--   E_NAME_TAKEN  whatever the case of its letters: a country's name, a place's name (a city or a place at sea), a trade good's name
--                 or code, another company's
-- THE LETTERS are ranges of code points (the same answer on every server): Latin, Greek, Cyrillic, Armenian, Hebrew, Arabic, the
-- Indian scripts, Thai, Georgian, Hangul, kana, Chinese characters. An accent as a separate mark is not a letter here: a name is
-- sent composed (NFC). Names that stand already are not judged: this is asked only of a name about to be written. Writes nothing.
declare
  c_l constant text := '0-9A-Za-z'
    || '\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02AF'                                  -- Latin with accents
    || '\u0386\u0388-\u03CE\u0400-\u0481\u048A-\u052F'                            -- Greek, Cyrillic
    || '\u0531-\u0556\u0561-\u0587\u05D0-\u05EA\u0620-\u064A\u066E-\u06D3'        -- Armenian, Hebrew, Arabic
    || '\u0900-\u0963\u0971-\u097F\u0980-\u09E3\u0A00-\u0A65\u0A80-\u0AE3\u0B00-\u0B63\u0B80-\u0BE5\u0C00-\u0C63\u0C80-\u0CE3\u0D00-\u0D63\u0D80-\u0DDF'   -- the Indian scripts
    || '\u0E01-\u0E3A\u0E40-\u0E4E\u10A0-\u10FA\u10FC-\u10FF\u1E00-\u1EFF'        -- Thai, Georgian, more Latin
    || '\u1100-\u115E\u1161-\u11FF\u3131-\u3163\u3165-\u318E\uAC00-\uD7A3'                                  -- Hangul (not its blank fillers)
    || '\u3041-\u3096\u30A1-\u30FA\u30FC\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF'  -- kana, Chinese characters
    || '\U00020000-\U0002FA1F';
  v_key constant text := lower(p_name);
begin
  if p_name is null or char_length(p_name) < 3 or char_length(p_name) > 24 then
    return jsonb_build_object('code', 'E_BAD_NAME', 'sentence', 'A company name is 3 to 24 characters.');
  end if;
  if p_name !~ ('^[' || c_l || ']+( [' || c_l || ']+)*$') then
    return jsonb_build_object('code', 'E_BAD_NAME',
                              'sentence', 'A company name is letters and digits, with one space between words. No special characters.');
  end if;
  if exists (select 1 from public.nations n where lower(n.name) = v_key)
     or exists (select 1 from public.ports q where lower(q.country) = v_key) then
    return jsonb_build_object('code', 'E_NAME_TAKEN', 'sentence', format('"%s" is a country''s name. Choose another.', p_name));
  end if;
  if exists (select 1 from public.ports q where lower(q.name) = v_key) then
    return jsonb_build_object('code', 'E_NAME_TAKEN', 'sentence', format('"%s" is a place''s name. Choose another.', p_name));
  end if;
  if exists (select 1 from public.goods g where lower(g.name) = v_key or replace(lower(g.code), '-', ' ') = v_key) then
    return jsonb_build_object('code', 'E_NAME_TAKEN', 'sentence', format('"%s" is a trade good''s name. Choose another.', p_name));
  end if;
  if exists (select 1 from public.players p where lower(p.company_name) = v_key and p.id is distinct from p_player) then
    return jsonb_build_object('code', 'E_NAME_TAKEN', 'sentence', format('Another company already trades as "%s".', p_name));
  end if;
  return null;
end
$body$
  $f$;

  execute $f$
create function public.company_rename_free(p_renames integer)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0503: MAY A COMPANY THAT HAS RENAMED p_renames TIMES RENAME WITHOUT PAYING. The owner: the first time is free. The one place
  -- the count is written; public.rename_company and world.player read it.
  select coalesce(p_renames, 0) < 1
$body$
  $f$;

  execute $f$
create function public.rename_company(p_player uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0503: THE ONE WAY A COMPANY'S NAME CHANGES. Paper: no coin, ship or order moves, and her fleets may be anywhere. Her name again
-- changes nothing and counts nothing. Her free rename used (public.company_rename_free): refused, E_RENAME_PAID, until the owner
-- decides what a later rename costs; nothing here takes a payment. Else public.company_name_refusal judges the name (the same rule
-- as a founding), the table's own constraints stand behind it, the count goes up by one and one event is written.
declare
  v_name text := btrim(coalesce(p_name, ''));
  p      public.players%rowtype;
  v_bad  jsonb;
begin
  select x.* into p from public.players x where x.id = p_player and not x.is_npc for update;
  if p.id is null then
    perform cmd.refuse('E_NO_HOUSE', 'Found a company first.');
  end if;
  if v_name = p.company_name then
    return jsonb_build_object('ok', true, 'from', p.company_name, 'to', p.company_name, 'changed', false,
                              'renames', p.renames, 'rename_free', public.company_rename_free(p.renames));
  end if;
  if not public.company_rename_free(p.renames) then
    perform cmd.refuse('E_RENAME_PAID', 'Your free rename is used. Another rename is not available yet.');
  end if;
  v_bad := public.company_name_refusal(v_name, p.id);
  if v_bad is not null then
    perform cmd.refuse(v_bad->>'code', v_bad->>'sentence');
  end if;
  begin
    update public.players set company_name = v_name, renames = renames + 1 where id = p.id;
  exception
    when unique_violation then
      perform cmd.refuse('E_NAME_TAKEN', format('Another company already trades as "%s".', v_name));
    when check_violation then
      perform cmd.refuse('E_BAD_NAME', 'A company name is 3 to 24 characters.');
  end;
  perform public.emit_event(p.id, 'COMPANY_RENAMED', jsonb_build_object('from', p.company_name, 'to', v_name));
  return jsonb_build_object('ok', true, 'from', p.company_name, 'to', v_name, 'changed', true,
                            'renames', p.renames + 1, 'rename_free', public.company_rename_free(p.renames + 1));
end
$body$
  $f$;

  execute $f$
create function cmd.rename_company(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0503: the caller's company takes a new name. It takes NO player id: the company is the caller's own. The core is
-- public.rename_company.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a company first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.rename_company(v_player, p_name);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  execute format('grant execute on function %s to authenticated', c_door::regprocedure);

  -- ── 4. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0503 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0503 values
  ('cmd.found_house(text,text)', 1,
$h$  -- The constraints on public.players are the authority. Let them bite, and say what they meant.
  begin
$h$,
$h$  -- 0503: THE NAME'S RULE, the one founding and renaming share (public.company_name_refusal): 3 to 24 characters, letters and
  -- digits with one space between words, and not a country's, a city's, a trade good's or another company's name in any case.
  if public.company_name_refusal(v_name, null) is not null then
    return (select jsonb_build_object('ok', false, 'error_code', r.j->>'code', 'error_message', r.j->>'sentence',
                                      'fixes', jsonb_build_array('(choose another name)'))
              from (select public.company_name_refusal(v_name, null) as j) r);
  end if;

  -- The constraints on public.players are the authority. Let them bite, and say what they meant.
  begin
$h$),
  ('world.player()', 1,
$h$      'company_name',  v_row.company_name,
$h$,
$h$      'company_name',  v_row.company_name,
      -- 0503: how many times she has renamed, and whether the next is free (public.company_rename_free)
      'renames',       v_row.renames,
      'rename_free',   public.company_rename_free(v_row.renames),
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'rename_fleet',          'uuid, text'),
$h$,
$h$      ('cmd',         'rename_fleet',          'uuid, text'),
      -- 0503: a company takes a new name (the caller's own; the first is free)
      ('cmd',         'rename_company',        'text'),
$h$);

  for v_h in select h.fn from hunks_0503 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0503 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0503 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0503 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0503 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0503 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the grants, the knobs, the column ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0503 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0503 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = c_door))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0503 self-assert FAIL: the grants are not the contract: the door for authenticated alone, the rest for no client and not service_role';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.schema_name = 'cmd' and e.function_name = 'rename_company' and e.fn is not null) <> 1 then
    raise exception '0503 self-assert FAIL: the door is not in the client registry';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.company_name_refusal(text,uuid)'::regprocedure) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = 'public.company_rename_free(integer)'::regprocedure) <> 'i' then
    raise exception '0503 self-assert FAIL: the rule is not a STABLE read, or the free count not IMMUTABLE';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0503 self-assert FAIL: a knob moved or was added: this file writes none';
  end if;
  if exists (select 1 from public.players p where p.renames <> 0) then
    raise exception '0503 self-assert FAIL: a company does not start with her free rename';
  end if;
  if not public.company_rename_free(0) or public.company_rename_free(1) or public.company_rename_free(2) then
    raise exception '0503 self-assert FAIL: the first rename is not the one free rename';
  end if;

  -- ── 6. SELF-ASSERT: THE RULE, with no row of any company (lengths, special characters, spaces, scripts) ──
  for x in
    select * from (values
      ('ab', 'E_BAD_NAME'), ('', 'E_BAD_NAME'), (repeat('a', 25), 'E_BAD_NAME'),
      ('A*B', 'E_BAD_NAME'), ('Casa-Nova', 'E_BAD_NAME'), ('Casa_Nova', 'E_BAD_NAME'), ('O''Brien', 'E_BAD_NAME'), ('Casa.Nova', 'E_BAD_NAME'),
      ('Casa <b>', 'E_BAD_NAME'), ('Casa' || chr(9) || 'Nova', 'E_BAD_NAME'), ('Casa' || chr(10) || 'Nova', 'E_BAD_NAME'),
      ('Casa  Nova', 'E_BAD_NAME'), (' Casa Nova', 'E_BAD_NAME'), ('Casa Nova ', 'E_BAD_NAME'),
      ('Casa' || chr(160) || 'Nova', 'E_BAD_NAME'),      -- a no-break space
      ('Casa' || chr(8203) || 'Nova', 'E_BAD_NAME'),     -- a zero-width space
      ('Casa' || chr(12288) || 'Nova', 'E_BAD_NAME'),    -- an ideographic space
      ('Casa ' || chr(9733), 'E_BAD_NAME'),              -- a star
      ('Casa ' || chr(128674), 'E_BAD_NAME'),            -- a ship (emoji)
      ('Cafe' || chr(769) || ' Nova', 'E_BAD_NAME'),     -- an accent as a separate mark (the client composes it)
      ('Casa' || chr(215) || 'Nova', 'E_BAD_NAME'),      -- a multiplication sign
      (repeat(chr(12644), 3), 'E_BAD_NAME'),             -- three Hangul fillers (a blank name)
      ('Casa' || chr(4447) || 'Nova', 'E_BAD_NAME'),     -- a Hangul lead filler
      ('Casa' || chr(4448) || 'Nova', 'E_BAD_NAME')      -- a Hangul vowel filler
    ) t(nm, code)
  loop
    if public.company_name_refusal(x.nm, null)->>'code' is distinct from x.code then
      raise exception '0503 self-assert FAIL: the rule did not refuse "%" as %: %', x.nm, x.code, public.company_name_refusal(x.nm, null);
    end if;
  end loop;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own three companies' rows alone; no live company, market or dice is read) ──
  begin
    -- names NO company holds, whatever companies this world has (no company's name ends in the suffix, so any name with it is free)
    select array_agg(c.nm order by c.i) into v_names
      from (select i, 'Casa Nome 0503 ' || i as nm from generate_series(1, 5000) i
             where not exists (select 1 from public.players p where p.company_name like '% 0503 ' || i)
             order by i limit 5) c;
    v_na := v_names[1]; v_nb := v_names[2]; v_nc := v_names[3]; v_nd := v_names[4]; v_ne := v_names[5];
    if v_ne is null then
      raise exception '0503 self-assert FAIL: the probe found no five free names (the fault is the probe''s)';
    end if;
    -- the first single-word country, city and good of the static tables (single-word, so only "taken" can refuse them)
    select n.name into v_nation from public.nations n where n.name ~ '^[A-Za-z]{3,24}$' order by n.code limit 1;
    select q.name into v_city from public.ports q where q.name ~ '^[A-Za-z]{3,24}$' and not exists (select 1 from public.nations n where lower(n.name) = lower(q.name))
                                                    and not exists (select 1 from public.ports c where lower(c.country) = lower(q.name)) order by q.code limit 1;
    select g.name into v_good from public.goods g where g.name ~ '^[A-Za-z]{3,24}$' and not exists (select 1 from public.nations n where lower(n.name) = lower(g.name))
                                                    and not exists (select 1 from public.ports q where lower(q.name) = lower(g.name) or lower(q.country) = lower(g.name)) order by g.code limit 1;
    if v_nation is null or v_city is null or v_good is null then
      raise exception '0503 self-assert FAIL: the static tables hold no single-word country, city or good to try (%, %, %)', v_nation, v_city, v_good;
    end if;

    -- names of other scripts and with accents pass (free names: a suffix no company holds)
    if public.company_name_refusal(v_na, null) is not null
       or public.company_name_refusal('Casa Vaiv' || chr(233) || 'm ' || '0503 ' || split_part(v_na, ' ', 4), null) is not null                 -- e with an acute accent
       or public.company_name_refusal(chr(54620) || chr(44544) || ' ' || chr(54924) || chr(49324) || ' ' || '0503 ' || split_part(v_na, ' ', 4), null) is not null   -- Hangul
       or public.company_name_refusal(chr(1050) || chr(1086) || chr(1084) || ' ' || '0503 ' || split_part(v_na, ' ', 4), null) is not null       -- Cyrillic
       or public.company_name_refusal(chr(21830) || chr(20250) || ' ' || '0503 ' || split_part(v_na, ' ', 4), null) is not null then             -- Chinese characters
      raise exception '0503 self-assert FAIL: the rule refuses a free name of letters, digits and single spaces: % / %', v_na, public.company_name_refusal(v_na, null);
    end if;
    -- a country, a city, a good: taken in any case, each with its own sentence
    if public.company_name_refusal(upper(v_nation), null)->>'sentence' not like '%country%'
       or public.company_name_refusal(lower(v_nation), null)->>'code' is distinct from 'E_NAME_TAKEN'
       or public.company_name_refusal(upper(v_city), null)->>'sentence' not like '%place%'
       or public.company_name_refusal(lower(v_city), null)->>'code' is distinct from 'E_NAME_TAKEN'
       or public.company_name_refusal(upper(v_good), null)->>'sentence' not like '%trade good%'
       or public.company_name_refusal(lower(v_good), null)->>'code' is distinct from 'E_NAME_TAKEN' then
      raise exception '0503 self-assert FAIL: a country (%), a city (%) or a trade good (%) is not refused in every case', v_nation, v_city, v_good;
    end if;

    -- company A stands (the server's own maker; her name was free)
    v_a := public.new_house(c_a, v_na, 'PRT');
    if public.company_name_refusal(upper(v_na), null)->>'code' is distinct from 'E_NAME_TAKEN'
       or public.company_name_refusal(upper(v_na), null)->>'sentence' not like '%company%'
       or public.company_name_refusal(upper(v_na), v_a) is not null then
      raise exception '0503 self-assert FAIL: a taken name in another case is not refused to another company, or is refused to its own';
    end if;

    -- FOUNDING (company B's account): the door refuses with the rule's sentence, makes no company, then founds
    perform cmd.assume_identity(c_b);
    for x in
      select * from (values (upper(v_na), 'E_NAME_TAKEN'), ('  ' || lower(v_na) || ' ', 'E_NAME_TAKEN'), (upper(v_nation), 'E_NAME_TAKEN'),
                            (lower(v_city), 'E_NAME_TAKEN'), (upper(v_good), 'E_NAME_TAKEN'), ('A*B', 'E_BAD_NAME'), ('ab', 'E_BAD_NAME'),
                            ('Casa  Nome', 'E_BAD_NAME')) t(nm, code)
    loop
      v_r := cmd.found_house(x.nm, 'PRT');
      if (v_r->>'ok')::boolean or v_r->>'error_code' is distinct from x.code or coalesce(v_r->>'error_message', '') = ''
         or v_r->>'error_message' is distinct from public.company_name_refusal(btrim(x.nm), null)->>'sentence'
         or exists (select 1 from public.players p where p.auth_uid = c_b) then
        raise exception '0503 self-assert FAIL: founding as "%" was not refused as % with the rule''s sentence: %', x.nm, x.code, v_r;
      end if;
    end loop;
    v_r := cmd.found_house('  ' || v_nb || ' ', 'PRT');
    select p.id into v_b from public.players p where p.auth_uid = c_b;
    if not (v_r->>'ok')::boolean or v_b is null or (select p.company_name from public.players p where p.id = v_b) <> v_nb
       or (select p.renames from public.players p where p.id = v_b) <> 0 then
      raise exception '0503 self-assert FAIL: a free name of letters, digits and single spaces did not found a company: %', v_r;
    end if;
    v_w := world.player()->'player';
    if v_w->>'company_name' <> v_nb or (v_w->>'renames')::int <> 0 or (v_w->>'rename_free')::boolean is not true then
      raise exception '0503 self-assert FAIL: world.player does not serve a new company her free rename: %', v_w - 'reputation' - 'levels';
    end if;

    -- RENAMING (company A): refused names change nothing and count nothing
    perform cmd.assume_identity(c_a);
    select p.ducats into v_purse from public.players p where p.id = v_a;
    select count(*) into v_led from public.ledger l where l.player_id = v_a;
    for x in
      select * from (values (upper(v_nb), 'E_NAME_TAKEN'), (lower(v_nation), 'E_NAME_TAKEN'), (upper(v_city), 'E_NAME_TAKEN'),
                            (lower(v_good), 'E_NAME_TAKEN'), ('A*B', 'E_BAD_NAME'), ('ab', 'E_BAD_NAME'), (repeat('b', 25), 'E_BAD_NAME')) t(nm, code)
    loop
      v_r := cmd.rename_company(x.nm);
      if (v_r->>'ok')::boolean or v_r->>'error_code' is distinct from x.code or coalesce(v_r->>'error_message', '') = ''
         or (select p.company_name || '/' || p.renames from public.players p where p.id = v_a) <> v_na || '/0' then
        raise exception '0503 self-assert FAIL: renaming to "%" was not refused as %, or it changed her: %', x.nm, x.code, v_r;
      end if;
    end loop;
    -- her own name again: nothing changes, nothing is counted, nothing is written
    v_r := cmd.rename_company(' ' || v_na || ' ');
    if not (v_r->>'ok')::boolean or (v_r->>'changed')::boolean or (v_r->>'rename_free')::boolean is not true
       or (select p.renames from public.players p where p.id = v_a) <> 0
       or exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'COMPANY_RENAMED') then
      raise exception '0503 self-assert FAIL: her own name again changed or counted something: %', v_r;
    end if;
    -- THE FREE RENAME: the name is written, the count is 1, one event, no coin, the old name free again
    v_r := cmd.rename_company('  ' || v_nc || ' ');
    v_w := world.player()->'player';
    if not (v_r->>'ok')::boolean or not (v_r->>'changed')::boolean or v_r->>'from' <> v_na or v_r->>'to' <> v_nc
       or (v_r->>'renames')::int <> 1 or (v_r->>'rename_free')::boolean
       or (select p.company_name || '/' || p.renames from public.players p where p.id = v_a) <> v_nc || '/1'
       or v_w->>'company_name' <> v_nc or (v_w->>'renames')::int <> 1 or (v_w->>'rename_free')::boolean
       or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'COMPANY_RENAMED'
                                                  and e.payload = jsonb_build_object('from', v_na, 'to', v_nc)) <> 1
       or (select p.ducats from public.players p where p.id = v_a) <> v_purse
       or (select count(*) from public.ledger l where l.player_id = v_a) <> v_led
       or public.company_name_refusal(v_na, null) is not null then
      raise exception '0503 self-assert FAIL: the free rename did not write the name once, count 1, leave one event, move no coin and free the old name: % / %', v_r, v_w - 'reputation' - 'levels';
    end if;
    -- THE NEXT IS REFUSED IN PLAIN WORDS (payment is not decided): nothing changes, whatever the name
    for x in select * from (values (v_nd), (v_na), (upper(v_nc)), ('A*B')) t(nm) loop
      v_r := cmd.rename_company(x.nm);
      if (v_r->>'ok')::boolean or v_r->>'error_code' is distinct from 'E_RENAME_PAID'
         or v_r->>'error_message' <> 'Your free rename is used. Another rename is not available yet.'
         or (select p.company_name || '/' || p.renames from public.players p where p.id = v_a) <> v_nc || '/1' then
        raise exception '0503 self-assert FAIL: a second rename (to "%") was not refused as E_RENAME_PAID, or it changed her: %', x.nm, v_r;
      end if;
    end loop;
    -- her name again is still no rename (nothing to refuse)
    if not (cmd.rename_company(v_nc)->>'ok')::boolean then
      raise exception '0503 self-assert FAIL: her own name again is refused after her free rename';
    end if;
    if (select count(*) from public.events e where e.player_id = v_a and e.kind = 'COMPANY_RENAMED') <> 1 then
      raise exception '0503 self-assert FAIL: a refused rename wrote an event';
    end if;

    -- company B takes the name A left (it is free), and company C her own name in another case (hers to take)
    perform cmd.assume_identity(c_b);
    v_r := cmd.rename_company(v_na);
    if not (v_r->>'ok')::boolean or (select p.company_name || '/' || p.renames from public.players p where p.id = v_b) <> v_na || '/1' then
      raise exception '0503 self-assert FAIL: a name its company left could not be taken by another: %', v_r;
    end if;
    v_c := public.new_house(c_c, v_ne, 'PRT');
    perform cmd.assume_identity(c_c);
    v_r := cmd.rename_company(upper(v_ne));
    if not (v_r->>'ok')::boolean or not (v_r->>'changed')::boolean or (select p.company_name from public.players p where p.id = v_c) <> upper(v_ne) then
      raise exception '0503 self-assert FAIL: a company could not write her own name in another case: %', v_r;
    end if;

    -- an account with no company: refused, nothing made
    perform cmd.assume_identity(c_d);
    v_r := cmd.rename_company(v_nd);
    if (v_r->>'ok')::boolean or v_r->>'error_code' is distinct from 'E_NO_HOUSE' or exists (select 1 from public.players p where p.auth_uid = c_d) then
      raise exception '0503 self-assert FAIL: an account with no company was not refused: %', v_r;
    end if;
    -- a merchants' house (a row no account holds) is not renamed by the core
    begin
      perform public.rename_company((select p.id from public.players p where p.is_npc order by p.id limit 1), v_nd);
      raise exception '0503 self-assert FAIL: a merchants'' house (or no company at all) took a new name';
    exception when others then
      if sqlerrm !~ '^E_NO_HOUSE:' then raise; end if;
    end;

    -- THE INDEX (where it stands): two companies' names equal but for case cannot both be written, whatever path writes them
    if v_index then
      begin
        update public.players set company_name = lower(v_na) where id = v_c;
        raise exception '0503 self-assert FAIL: the index let two companies hold one name in two cases';
      exception when unique_violation then
        null;
      end;
    end if;

    v_note := format('names tried: country %s, place %s, good %s, each refused in any case; founding and renaming refused 8 and 7 bad names with the rule''s sentence; one free rename (%s to %s: no coin, one event, the old name free again), the next refused E_RENAME_PAID',
                     v_nation, v_city, v_good, v_na, v_nc);
    raise exception using errcode = 'ZX503', message = 'PROBE_ROLLBACK_0503';
  exception when sqlstate 'ZX503' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0503 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid in (c_a, c_b, c_c, c_d)) or exists (select 1 from public.players p where p.renames <> 0) then
    raise exception '0503 self-assert FAIL: the probe left something behind';
  end if;

  -- ── 8. THE NEWS ──
  perform public.news_update('0503', 'Company names: one free rename in Profile. A new name is letters and digits, and not a country, a city, a trade good or another company',
                             'Company names: one free rename in Profile. A new name is letters and digits, and not a country, a city, a trade good or another company');

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0503 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0503 self-assert ok: A COMPANY TAKES A NEW NAME. Three hunks once and reversing; four new functions (the door for authenticated alone); no other function moved; no knob; players.renames 0 for all; the case-blind index %. Probe (rolled back): %. % ms.',
    case when v_index then 'built (no two companies'' names were equal but for case)' else 'NOT BUILT: two companies'' names are equal but for case, so the rule stands in the function alone' end,
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
