-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0008 — ONE LINE OF WORDS IS THE ONLY WAY IN
--        The §F grammar, parsed once on the server; cmd.issue() as the sole mutating entry point;
--        and refusals that are a code, a sentence AND a fix.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE LAW THIS FILE ENFORCES (DESIGN §F, §F.4) ────────────────────────────────────────────────
--   "There is exactly ONE parser, it runs on the server, and the tap-builder emits the same string
--   the keyboard does ... Submit sends the STRING, not a structured object."
--
--   So `cmd.issue(fleet_id, raw_text, expected_version)` takes TEXT. There is no structured-order
--   RPC beside it and there must never be one: a second entry point taking {verb, args} would be a
--   second grammar, and the tap-builder and the keyboard would drift apart on the first V1 verb.
--   `cmd.verb_schema()` exists so the tap-builder READS the grammar instead of restating it.
--
-- ── AND THE DECISION THAT KEEPS PREVIEW HONEST ──────────────────────────────────────────────────
--   §F.5 wants a live dry-run under the input box. The obvious build is a second copy of every
--   precondition — "docked?", "affordable?", "hold?" — which is the predecessor's exact disease:
--   the same rule written twice, drifting until the preview says yes and the server says no.
--
--   `cmd.preview()` therefore RUNS THE REAL EXECUTOR inside a plpgsql subtransaction and then
--   deliberately raises, discarding every write. There is no second copy of any rule. What the
--   preview reports is literally what the order would have done, because it is what it did.
--
-- ── ONE AUTHORITY PER CONCEPT ───────────────────────────────────────────────────────────────────
--   cmd.fold()          — THE case/diacritic folding. "cadiz" = "Cádiz" in exactly one place.
--   cmd.resolve_port/good/fleet() — THE prefix-unique name resolution, and the ONLY source of
--                         E_NO_SUCH_* / E_AMBIGUOUS.
--   cmd.parse()         — THE grammar. Used by issue AND by preview AND by verb_schema's tests.
--   cmd.fixes()         — THE "→ do this instead" suggestions of §F.5.
--   cmd.issue()         — THE only mutating entry point in the game.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * Folding works: "cadiz", "CADIZ", "Cádiz" and "CAD" all resolve to the same port; "8_000" and
--     "8,000" both parse as 8000.
--   * A prefix that matches more than one port raises E_AMBIGUOUS and NAMES the candidates; an unknown one
--     raises E_NO_SUCH_PORT. Both, so neither is assumed.
--   * Noise words are optional: "SAIL Gaivota Cadiz" parses the same as "SAIL Gaivota TO Cádiz".
--   * cmd.preview() LEAVES NOTHING BEHIND — the purse, the stock and the hold are unchanged after
--     a preview of a BUY that the same call reports as costing real money.
--   * cmd.issue() refuses on a stale version (E_STALE) and on a 13th queued order (E_QUEUE_FULL).
--   * A refusal carries a code, a sentence AND at least one insertable fix.
--   * cmd.cancel() removes a pending order and cmd.clear() empties the queue but spares the active
--     voyage — §F.3's cancellation table, proven rather than described.
--
-- Depends ONLY on: 0001-0007.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── Folding and name resolution (DESIGN §F.1 parsing rules) ────────────────────────────────────
create or replace function cmd.fold(p_text text)
returns text
language sql
immutable
as $$
  -- Case-insensitive, diacritics folded. The predecessor's lesson about ONE authority applies to
  -- string handling too: every comparison in the parser goes through this function, so "Cádiz",
  -- "cadiz" and "CADIZ" cannot come to mean different things in different verbs.
  select btrim(translate(lower(coalesce(p_text, '')),
                         'áàâãäéèêëíìîïóòôõöúùûüçñ',
                         'aaaaaeeeeiiiiooooouuuucn'))
$$;

create or replace function cmd.parse_number(p_text text)
returns numeric
language sql
immutable
as $$
  -- DESIGN F.1: "Numbers accept _ and , separators (200_000)."
  select case when replace(replace(p_text, '_', ''), ',', '') ~ '^[0-9]+(\.[0-9]+)?$'
              then replace(replace(p_text, '_', ''), ',', '')::numeric end
$$;

create or replace function cmd.resolve_port(p_text text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_f    text := cmd.fold(p_text);
  v_id   uuid;
  v_n    int;
  v_list text;
begin
  select id into v_id from public.ports where lower(code) = v_f;
  if v_id is not null then return v_id; end if;

  select count(*), min(id::text)::uuid, string_agg(name, ', ' order by name)
    into v_n, v_id, v_list
    from public.ports where cmd.fold(name) like v_f || '%';
  if v_n = 0 then
    raise exception 'E_NO_SUCH_PORT: there is no port called "%"', p_text using errcode = 'P0001';
  elsif v_n > 1 then
    raise exception 'E_AMBIGUOUS: "%" could be %', p_text, v_list using errcode = 'P0001';
  end if;
  return v_id;
end $$;

create or replace function cmd.resolve_good(p_text text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_f    text := cmd.fold(p_text);
  v_id   uuid;
  v_n    int;
  v_list text;
begin
  select id into v_id from public.goods where lower(code) = v_f;
  if v_id is not null then return v_id; end if;

  select count(*), min(id::text)::uuid, string_agg(name, ', ' order by name)
    into v_n, v_id, v_list
    from public.goods where cmd.fold(name) like v_f || '%' or cmd.fold(code) like v_f || '%';
  if v_n = 0 then
    raise exception 'E_NO_SUCH_GOOD: there is no good called "%"', p_text using errcode = 'P0001';
  elsif v_n > 1 then
    raise exception 'E_AMBIGUOUS: "%" could be %', p_text, v_list using errcode = 'P0001';
  end if;
  return v_id;
end $$;

create or replace function cmd.resolve_fleet(p_player uuid, p_text text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_f    text := cmd.fold(p_text);
  v_id   uuid;
  v_n    int;
  v_list text;
begin
  if v_f ~ '^#[0-9]+$' then
    select id into v_id from public.fleets where player_id = p_player
     order by created_at offset (substr(v_f, 2)::int - 1) limit 1;
    if v_id is null then
      raise exception 'E_NO_SUCH_FLEET: you have no fleet %', p_text using errcode = 'P0001';
    end if;
    return v_id;
  end if;
  select count(*), min(id::text)::uuid, string_agg(name, ', ' order by name)
    into v_n, v_id, v_list
    from public.fleets where player_id = p_player and cmd.fold(name) like v_f || '%';
  if v_n = 0 then
    raise exception 'E_NO_SUCH_FLEET: you have no fleet called "%"', p_text using errcode = 'P0001';
  elsif v_n > 1 then
    raise exception 'E_AMBIGUOUS: "%" could be %', p_text, v_list using errcode = 'P0001';
  end if;
  return v_id;
end $$;

-- ── THE grammar (DESIGN §F.1, cut to the eight V0 verbs of §K.1) ───────────────────────────────
create or replace function cmd.verb_schema()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Served to the tap-builder so the mobile pad and the keyboard share ONE grammar (DESIGN F.4).
  -- Tapping through these arguments assembles exactly the string a desktop player would type.
  select '[
    {"verb":"SAIL","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"dest","type":"port","required":true,"keyword":"TO"},
       {"name":"via","type":"port","required":false,"repeat":true,"keyword":"VIA"}],
     "help":"Send a fleet to sea along the authored leg graph."},
    {"verb":"BUY","args":[
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"qty","required":true},
       {"name":"limit","type":"price","required":false,"keyword":"AT","op":"<="}],
     "help":"Buy in 10-tun steps; each step reprices. A limit partially fills."},
    {"verb":"SELL","args":[
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"qty","required":true},
       {"name":"limit","type":"price","required":false,"keyword":"AT","op":">="}],
     "help":"Sell from the hold. ALL and HALF are read when the order RUNS, not when it is typed."},
    {"verb":"PROVISION","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"mode","type":"enum","values":["FULL","DAYS"],"required":false,"default":"FULL"},
       {"name":"days","type":"number","required":false}],
     "help":"Take on water and food. FULL fills to the ship store ratio."},
    {"verb":"HIRE","args":[
       {"name":"count","type":"number","required":true},
       {"name":"fleet","type":"fleet","required":false}],
     "help":"Recruit hands. Beyond the port pool the rate is x2.5."},
    {"verb":"REPAIR","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"to_pct","type":"number","required":false,"keyword":"TO","default":100}],
     "help":"Enter the yard. Takes voyage-time and the fleet is unavailable until it is done."},
    {"verb":"CANCEL","args":[
       {"name":"index","type":"number","required":false}],
     "help":"Cancel a pending order by its queue index, or the whole queue head."},
    {"verb":"CLEAR","args":[
       {"name":"all","type":"flag","required":false}],
     "help":"Drop every pending order. CLEAR ALL also recalls an active voyage."}
  ]'::jsonb
$$;

create or replace function cmd.parse(p_player uuid, p_fleet uuid, p_text text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  t      text[];
  n      int;
  i      int := 2;
  v_verb text;
  v_args jsonb := '{}'::jsonb;
  v_fleet uuid := p_fleet;
  v_via  jsonb := '[]'::jsonb;
  v_num  numeric;
  v_tok  text;
begin
  select array_agg(x) into t
    from regexp_split_to_table(btrim(coalesce(p_text, '')), '\s+') x where x <> '';
  if t is null then
    raise exception 'E_PARSE: say something' using errcode = 'P0001';
  end if;
  n := array_length(t, 1);
  v_verb := upper(cmd.fold(t[1]));

  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','CANCEL','CLEAR') then
    raise exception 'E_PARSE: "%" is not a verb this world understands', t[1] using errcode = 'P0001';
  end if;

  -- An optional leading fleet reference, for every verb that acts on a fleet (DESIGN F.1). It is
  -- consumed only if it actually resolves, so "BUY sal 60" is never mistaken for a fleet name.
  if v_verb in ('SAIL','PROVISION','HIRE','REPAIR') and n >= i then
    begin
      v_fleet := cmd.resolve_fleet(p_player, t[i]);
      i := i + 1;
    exception when others then
      null;   -- not a fleet name; leave it for the verb's own arguments
    end;
  end if;

  if v_verb = 'SAIL' then
    -- Keywords TO / VIA are noise-tolerant (DESIGN F.1): omitting them is accepted.
    while i <= n and upper(cmd.fold(t[i])) = 'TO' loop i := i + 1; end loop;
    if i > n then
      raise exception 'E_PARSE: SAIL needs a destination port' using errcode = 'P0001';
    end if;
    v_args := jsonb_build_object('dest', cmd.resolve_port(t[i]));
    i := i + 1;
    while i <= n loop
      if upper(cmd.fold(t[i])) = 'VIA' then i := i + 1; continue; end if;
      v_via := v_via || to_jsonb(cmd.resolve_port(t[i])::text);
      i := i + 1;
    end loop;
    v_args := v_args || jsonb_build_object('via', v_via);

  elsif v_verb in ('BUY','SELL') then
    if i > n then
      raise exception 'E_PARSE: % needs a good', v_verb using errcode = 'P0001';
    end if;
    v_args := jsonb_build_object('good', cmd.resolve_good(t[i]));
    i := i + 1;
    if i > n then
      raise exception 'E_PARSE: % needs a quantity (a number, ALL, HALF or a percentage)', v_verb using errcode = 'P0001';
    end if;
    v_tok := upper(cmd.fold(t[i]));
    if v_tok = 'ALL' then
      v_args := v_args || jsonb_build_object('qty_mode', 'ALL');
    elsif v_tok = 'HALF' then
      v_args := v_args || jsonb_build_object('qty_mode', 'HALF');
    elsif v_tok ~ '^[0-9]+%$' then
      v_args := v_args || jsonb_build_object('qty_mode', 'PCT', 'qty_pct', rtrim(v_tok, '%')::numeric);
    else
      v_num := cmd.parse_number(t[i]);
      if v_num is null or v_num <= 0 then
        raise exception 'E_PARSE: "%" is not a quantity', t[i] using errcode = 'P0001';
      end if;
      v_args := v_args || jsonb_build_object('qty', v_num);
    end if;
    i := i + 1;
    while i <= n loop
      v_tok := upper(cmd.fold(t[i]));
      if v_tok in ('AT', '<=', '>=', 'FOR', 'FROM') then i := i + 1; continue; end if;
      v_num := cmd.parse_number(regexp_replace(t[i], '^[<>]=?', ''));
      if v_num is null then
        raise exception 'E_PARSE: "%" is not a price limit', t[i] using errcode = 'P0001';
      end if;
      v_args := v_args || jsonb_build_object('limit', v_num);
      i := i + 1;
    end loop;

  elsif v_verb = 'PROVISION' then
    v_args := jsonb_build_object('mode', 'FULL');
    while i <= n loop
      v_tok := upper(cmd.fold(t[i]));
      if v_tok = 'FULL' then
        v_args := jsonb_build_object('mode', 'FULL');
      elsif v_tok = 'DAYS' then
        null;   -- noise: the number carries the meaning
      else
        v_num := cmd.parse_number(t[i]);
        if v_num is null then
          raise exception 'E_PARSE: "%" is not a number of days', t[i] using errcode = 'P0001';
        end if;
        v_args := jsonb_build_object('mode', 'DAYS', 'days', v_num);
      end if;
      i := i + 1;
    end loop;

  elsif v_verb = 'HIRE' then
    while i <= n and cmd.parse_number(t[i]) is null loop i := i + 1; end loop;
    if i > n then
      raise exception 'E_PARSE: HIRE needs a number of crew' using errcode = 'P0001';
    end if;
    v_args := jsonb_build_object('count', cmd.parse_number(t[i])::int);

  elsif v_verb = 'REPAIR' then
    v_args := jsonb_build_object('to_pct', 100);
    while i <= n loop
      v_num := cmd.parse_number(t[i]);
      if v_num is not null then v_args := jsonb_build_object('to_pct', v_num); end if;
      i := i + 1;
    end loop;

  elsif v_verb = 'CANCEL' then
    v_args := '{}'::jsonb;
    while i <= n loop
      v_num := cmd.parse_number(t[i]);
      if v_num is not null then v_args := jsonb_build_object('index', v_num::int); end if;
      i := i + 1;
    end loop;

  elsif v_verb = 'CLEAR' then
    v_args := jsonb_build_object('all', (n >= i and upper(cmd.fold(t[i])) = 'ALL'));
  end if;

  return jsonb_build_object('verb', v_verb, 'args', v_args, 'fleet_id', v_fleet);
end $$;

-- ── The fixes of DESIGN §F.5: never a bare code ────────────────────────────────────────────────
create or replace function cmd.fixes(p_code text, p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case p_code
    when 'E_ENDURANCE'         then jsonb_build_array('PROVISION ' || f.name || ' FULL')
    when 'E_HOLD_FULL'         then jsonb_build_array('SELL <good> ALL', 'BUY <good> HALF')
    when 'E_INSUFFICIENT_FUNDS' then jsonb_build_array('SELL <good> ALL', 'BUY <good> HALF')
    when 'E_PRICE_LIMIT'       then jsonb_build_array('SELL <good> ALL', 'BUY <good> <qty>')
    when 'E_NOT_DOCKED'        then jsonb_build_array('CANCEL', 'CLEAR ' || f.name)
    when 'E_CREW_SHORT'        then jsonb_build_array('HIRE 20')
    when 'E_FLAGSHIP_DISABLED' then jsonb_build_array('REPAIR ' || f.name)
    when 'E_NO_ROUTE'          then jsonb_build_array('SAIL ' || f.name || ' TO <a nearer port>')
    when 'E_QUEUE_FULL'        then jsonb_build_array('CLEAR ' || f.name)
    when 'E_DAILY_CAP'         then jsonb_build_array('BUY <good> HALF')
    when 'E_STALE'             then jsonb_build_array('(reload and try again)')
    else '[]'::jsonb
  end
  from public.fleets f where f.id = p_fleet
$$;

create or replace function cmd.queue(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o.id, 'seq', o.seq, 'text', o.raw_text, 'verb', o.verb,
           'status', o.status, 'error_code', o.error_code, 'error_message', o.error_message,
           'result', o.result) order by o.seq), '[]'::jsonb)
    from public.orders o
   where o.fleet_id = p_fleet and o.status in ('pending', 'active', 'failed')
$$;

-- ── THE dry run (DESIGN §F.5 layer 3, with no second copy of any rule) ─────────────────────────
create or replace function cmd.preview(p_fleet uuid, p_text text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid;
  v_parsed jsonb;
  v_res    jsonb;
  v_code   text;
  v_msg    text;
  v_out    jsonb;
begin
  select player_id into v_player from public.fleets where id = p_fleet;
  begin
    v_parsed := cmd.parse(v_player, p_fleet, p_text);
  exception when others then
    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    return jsonb_build_object('ok', false, 'error_code', v_code,
                              'error_message', btrim(substr(v_msg, length(v_code) + 2)),
                              'fixes', cmd.fixes(v_code, p_fleet));
  end;

  if v_parsed->>'verb' in ('CANCEL', 'CLEAR') then
    return jsonb_build_object('ok', true, 'parsed', v_parsed, 'immediate', true);
  end if;

  if (select status from public.fleets where id = (v_parsed->>'fleet_id')::uuid) <> 'DOCKED' then
    -- A fleet at sea cannot execute now; the order is legitimately QUEUEABLE, and saying "not
    -- docked" here would refuse the very thing the order queue exists for (DESIGN F.2 BUY).
    return jsonb_build_object('ok', true, 'parsed', v_parsed, 'queued', true);
  end if;

  -- RUN THE REAL THING, then throw the transaction away. The preview and the commit share one
  -- code path by construction, so they cannot disagree.
  begin
    v_res := case v_parsed->>'verb'
               when 'SAIL'      then cmd.do_sail((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'BUY'       then cmd.do_buy((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'SELL'      then cmd.do_sell((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'PROVISION' then cmd.do_provision((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'HIRE'      then cmd.do_hire((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'REPAIR'    then cmd.do_repair((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
             end;
    v_out := jsonb_build_object('ok', true, 'parsed', v_parsed, 'estimate', v_res);
    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm = '__PREVIEW_ROLLBACK__' then
      return v_out;
    end if;
    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    return jsonb_build_object('ok', false, 'parsed', v_parsed, 'error_code', v_code,
                              'error_message', btrim(substr(v_msg, length(v_code) + 2)),
                              'fixes', cmd.fixes(v_code, (v_parsed->>'fleet_id')::uuid));
  end;
end $$;

comment on function cmd.preview(uuid, text) is
  'DESIGN F.5 layer 3, built WITHOUT a second copy of any precondition: it executes the real verb '
  'in a subtransaction and discards it. What it reports is what the order would do, because it is '
  'what the order just did.';

-- ── THE only mutating entry point (DESIGN Appendix 2) ──────────────────────────────────────────
create or replace function cmd.issue(p_fleet uuid, p_text text, p_expected_version int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player  uuid := public.current_player_id();
  f         public.fleets%rowtype;
  v_parsed  jsonb;
  v_seq     int;
  v_depth   int;
  v_order   uuid;
  v_res     jsonb;
  v_code    text;
  v_msg     text;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or v_player is null or f.player_id <> v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;

  -- DESIGN F.3: "Every mutating RPC takes the fleet's version and fails E_STALE on mismatch, so
  -- two devices cannot double-issue."
  if p_expected_version is not null and p_expected_version <> f.version then
    return jsonb_build_object('ok', false, 'error_code', 'E_STALE',
      'error_message', format('This fleet has moved on since you looked (you have version %s, it is at %s).',
                              p_expected_version, f.version),
      'fixes', cmd.fixes('E_STALE', p_fleet), 'queue', cmd.queue(p_fleet));
  end if;

  -- Bring the fleet up to date BEFORE judging the order, so an order is never refused on the
  -- strength of a state the world has already left behind (DESIGN D.2: every read settles first).
  perform voyage.settle(p_fleet);
  select * into f from public.fleets where id = p_fleet;

  begin
    v_parsed := cmd.parse(v_player, p_fleet, p_text);
  exception when others then
    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    return jsonb_build_object('ok', false, 'error_code', v_code,
      'error_message', btrim(substr(v_msg, length(v_code) + 2)),
      'fixes', cmd.fixes(v_code, p_fleet), 'queue', cmd.queue(p_fleet));
  end;

  if v_parsed->>'verb' = 'CANCEL' then
    return cmd.cancel_at((v_parsed->>'fleet_id')::uuid, (v_parsed->'args'->>'index')::int);
  elsif v_parsed->>'verb' = 'CLEAR' then
    return cmd.clear((v_parsed->>'fleet_id')::uuid, coalesce((v_parsed->'args'->>'all')::boolean, false));
  end if;

  select count(*) into v_depth from public.orders
   where fleet_id = (v_parsed->>'fleet_id')::uuid and status in ('pending', 'active');
  if v_depth >= public.wc_int('order_queue_max') then
    return jsonb_build_object('ok', false, 'error_code', 'E_QUEUE_FULL',
      'error_message', format('That fleet already has %s orders waiting; the limit is %s.',
                              v_depth, public.wc_int('order_queue_max')),
      'fixes', cmd.fixes('E_QUEUE_FULL', p_fleet), 'queue', cmd.queue(p_fleet));
  end if;

  select coalesce(max(seq), 0) + 1 into v_seq from public.orders
   where fleet_id = (v_parsed->>'fleet_id')::uuid;

  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args)
  values ((v_parsed->>'fleet_id')::uuid, v_player, v_seq, btrim(p_text),
          v_parsed->>'verb', v_parsed->'args')
  returning id into v_order;

  update public.fleets set version = version + 1 where id = (v_parsed->>'fleet_id')::uuid;

  -- Run whatever the fleet's state now permits. A docked fleet executes immediately; a fleet at
  -- sea simply keeps the order until it lands (DESIGN F.2, F.3).
  perform cmd.advance((v_parsed->>'fleet_id')::uuid);

  select jsonb_build_object('id', o.id, 'seq', o.seq, 'status', o.status,
                            'error_code', o.error_code, 'error_message', o.error_message,
                            'result', o.result)
    into v_res from public.orders o where o.id = v_order;

  return jsonb_build_object(
    'ok', coalesce(v_res->>'status', '') <> 'failed',
    'order', v_res,
    'error_code', v_res->>'error_code',
    'error_message', v_res->>'error_message',
    'fixes', cmd.fixes(coalesce(v_res->>'error_code', ''), (v_parsed->>'fleet_id')::uuid),
    'queue', cmd.queue((v_parsed->>'fleet_id')::uuid),
    'version', (select version from public.fleets where id = (v_parsed->>'fleet_id')::uuid));
end $$;

comment on function cmd.issue(uuid, text, int) is
  'THE only mutating game entry point (DESIGN Appendix 2). It takes a STRING, because the tap '
  'builder and the keyboard must submit the same thing through the same parser (F.4). Do not add a '
  'structured-order sibling: that would be a second grammar.';

-- ── Cancellation (DESIGN §F.3) ─────────────────────────────────────────────────────────────────
create or replace function cmd.cancel_at(p_fleet uuid, p_index int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare o public.orders%rowtype;
begin
  if p_index is null then
    select * into o from public.orders where fleet_id = p_fleet and status = 'pending' order by seq limit 1;
  else
    select * into o from public.orders where fleet_id = p_fleet and status in ('pending', 'active')
     order by seq offset (p_index - 1) limit 1;
  end if;
  if o.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
      'error_message', 'There is no such order in that queue.', 'queue', cmd.queue(p_fleet));
  end if;
  update public.orders set status = 'cancelled' where id = o.id;
  update public.fleets set version = version + 1 where id = p_fleet;
  return jsonb_build_object('ok', true, 'cancelled', o.seq, 'queue', cmd.queue(p_fleet));
end $$;

create or replace function cmd.clear(p_fleet uuid, p_include_active boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_n int;
begin
  -- §F.3: "CLEAR drops every pending order and LEAVES THE ACTIVE ONE RUNNING." Recalling an active
  -- voyage is RECALL, which is not a V0 verb (K.1), so CLEAR ALL reports honestly rather than
  -- half-doing it.
  -- Pending orders AND a failed one. 0007's halt rule stops the fleet while a failed order sits
  -- in its queue, so if CLEAR left it there the fleet would be stopped for good — the deadlock
  -- shape that cost the previous game a live incident. CLEAR is the release.
  update public.orders set status = 'cancelled'
   where fleet_id = p_fleet and status in ('pending', 'failed');
  get diagnostics v_n = row_count;
  update public.fleets set version = version + 1 where id = p_fleet;
  return jsonb_build_object('ok', true, 'cancelled', v_n,
    'active_left_running', not p_include_active
      or (select status from public.fleets where id = p_fleet) = 'SAILING',
    'note', case when p_include_active then 'A voyage already at sea keeps sailing: RECALL arrives in V1.' end,
    'queue', cmd.queue(p_fleet));
end $$;

-- ── Test/tick identity, server-only ────────────────────────────────────────────────────────────
create or replace function cmd.assume_identity(p_auth_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- SERVER-ONLY, and revoked from every client role below. It sets BOTH shapes of the JWT claim
  -- because Supabase's auth.uid() reads `request.jwt.claims`->>'sub' while the 0001 local shim
  -- reads `request.jwt.claim.sub`; setting both means the self-asserts and the proofs run
  -- identically under PGlite and under a real Supabase, with no second code path.
  perform set_config('request.jwt.claim.sub', p_auth_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_auth_uid)::text, true);
end $$;

grant execute on function cmd.issue(uuid, text, int)   to authenticated;
grant execute on function cmd.preview(uuid, text)      to authenticated;
grant execute on function cmd.verb_schema()            to authenticated;
grant execute on function cmd.cancel_at(uuid, int)     to authenticated;
grant execute on function cmd.clear(uuid, boolean)     to authenticated;
grant execute on function cmd.queue(uuid)              to authenticated;
revoke all on function cmd.assume_identity(uuid) from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe constant uuid := '00000000-0008-4000-8000-000000000001';
  v_player uuid; v_fleet uuid; v_ver int;
  v_cad uuid; v_lis uuid; v_sal uuid;
  v_p1 jsonb; v_p2 jsonb; v_p3 jsonb;
  v_prev jsonb; v_iss jsonb; v_stale jsonb; v_full jsonb; v_amb jsonb; v_unk jsonb;
  v_purse0 bigint; v_purse1 bigint; v_stock0 numeric; v_stock1 numeric;
  v_cancel jsonb; v_clear jsonb;
  v_grants int; n int; k int; v_depth int;
  f_fold boolean := false; f_amb boolean := false; f_noise boolean := false;
  f_preview_clean boolean := false; f_stale boolean := false; f_full boolean := false;
  f_fixes boolean := false; f_cancel boolean := false; f_schema boolean := false;
  f_release boolean := false;
begin
  select id into v_cad from public.ports where code = 'CAD';
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_sal from public.goods where code = 'salt';

  -- The grammar is served, and it serves exactly the eight V0 verbs of K.1 — no more, no fewer.
  select count(*) into n from jsonb_array_elements(cmd.verb_schema());
  if n = 8 and (select bool_and(e->>'verb' in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','CANCEL','CLEAR'))
                  from jsonb_array_elements(cmd.verb_schema()) e) then
    f_schema := true;
  end if;

  begin
    v_player := public.new_house(v_probe, 'Casa Verbo', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform cmd.assume_identity(v_probe);

    -- (a) Folding: four spellings, one port. And separators in numbers.
    if cmd.resolve_port('cadiz') = v_cad and cmd.resolve_port('CADIZ') = v_cad
       and cmd.resolve_port('Cádiz') = v_cad and cmd.resolve_port('CAD') = v_cad
       and cmd.parse_number('8_000') = 8000 and cmd.parse_number('8,000') = 8000 then
      f_fold := true;
    end if;

    -- (b) Ambiguity NAMES the candidates; the unknown is refused. Both directions.
    --     The old form of this check named Safi and Sevilla, which was true of a world with twelve
    --     ports in it. With 214 the letter "s" matches dozens, so what is asserted is the RULE: it
    --     refuses, it says E_AMBIGUOUS, and it lists more than one candidate by name.
    begin
      perform cmd.resolve_port('s');
    exception when others then
      if sqlerrm ~ '^E_AMBIGUOUS' and sqlerrm ~ ', ' then f_amb := true; end if;
    end;
    begin
      perform cmd.resolve_port('zzz');
      f_amb := false;   -- an unknown port that resolves silently is the worst outcome of the two
    exception when others then
      if sqlerrm !~ '^E_NO_SUCH_PORT' then f_amb := false; end if;
    end;

    -- (c) Noise words are optional (DESIGN F.1).
    v_p1 := cmd.parse(v_player, v_fleet, 'SAIL Gaivota TO Cádiz');
    v_p2 := cmd.parse(v_player, v_fleet, 'sail gaivota cadiz');
    v_p3 := cmd.parse(v_player, v_fleet, 'BUY salt 8,000');
    if v_p1->'args'->>'dest' = v_p2->'args'->>'dest'
       and v_p1->>'verb' = 'SAIL' and (v_p3->'args'->>'qty')::numeric = 8000 then
      f_noise := true;
    end if;

    -- (d) PREVIEW LEAVES NOTHING BEHIND, while reporting a real cost.
    select ducats into v_purse0 from public.players where id = v_player;
    select stock into v_stock0 from public.port_goods where port_id = v_lis and good_id = v_sal;
    v_prev := cmd.preview(v_fleet, 'BUY salt 40');
    select ducats into v_purse1 from public.players where id = v_player;
    select stock into v_stock1 from public.port_goods where port_id = v_lis and good_id = v_sal;
    if (v_prev->>'ok')::boolean and (v_prev->'estimate'->>'total')::bigint > 0
       and v_purse0 = v_purse1 and v_stock0 = v_stock1 then
      f_preview_clean := true;
    end if;

    -- (e) E_STALE on a version that has moved on.
    select version into v_ver from public.fleets where id = v_fleet;
    v_stale := cmd.issue(v_fleet, 'BUY salt 10', v_ver - 1);
    if (v_stale->>'error_code') = 'E_STALE' then f_stale := true; end if;

    -- (f) A refusal carries a code, a sentence AND a fix.
    v_iss := cmd.issue(v_fleet, 'BUY salt 99999');
    if (v_iss->>'error_code') = 'E_HOLD_FULL'
       and length(coalesce(v_iss->>'error_message', '')) > 10
       and jsonb_array_length(v_iss->'fixes') >= 1 then
      f_fixes := true;
    end if;

    -- (f2) A FAILED ORDER HALTS THE FLEET, AND CLEAR IS THE RELEASE.
    --      0007 makes a failed order block every later advance, which is what §F.3's "it halts, it
    --      never skips" actually requires. That rule is only safe if there is a way out: without
    --      one the fleet is stopped for ever the first time an order is refused. This is that way
    --      out, asserted here because CLEAR lives in this file.
    perform cmd.clear(v_fleet, false);
    perform cmd.issue(v_fleet, 'BUY salt 99999');       -- refused, and recorded as a failed order
    perform cmd.advance(v_fleet);
    if (select count(*) from public.orders where fleet_id = v_fleet and status = 'failed') > 0 then
      perform cmd.clear(v_fleet, false);
      if (select count(*) from public.orders
           where fleet_id = v_fleet and status in ('pending', 'failed')) = 0
         and cmd.advance(v_fleet) >= 0 then
        f_release := true;
      end if;
    end if;

    -- (g) The queue fills at EXACTLY the configured cap and then refuses (DESIGN F.3: maximum 12).
    --     The loop runs until the refusal rather than assuming which iteration produces it: the
    --     first SAIL departs immediately and therefore never joins the queue, and hard-coding
    --     "the 13th" would have quietly tested the wrong number.
    perform cmd.clear(v_fleet, false);
    for k in 1 .. 30 loop
      -- Addressed by CODE. In a 214-port world "Porto" is ambiguous with Portobelo — which is the
      -- resolver doing its job, and not what this check is about. A three-letter code is exact by
      -- construction, so the queue-depth probe tests the queue instead of the parser.
      v_full := cmd.issue(v_fleet, 'SAIL TO CAD');
      exit when (v_full->>'error_code') = 'E_QUEUE_FULL';
    end loop;
    select count(*) into v_depth from public.orders
     where fleet_id = v_fleet and status in ('pending', 'active');
    if (v_full->>'error_code') = 'E_QUEUE_FULL' and v_depth = public.wc_int('order_queue_max') then
      f_full := true;
    end if;

    -- (h) CANCEL removes one pending order; CLEAR empties the rest and leaves the voyage running.
    v_cancel := cmd.cancel_at(v_fleet, null);
    v_clear  := cmd.clear(v_fleet, false);
    if (v_cancel->>'ok')::boolean and (v_clear->>'cancelled')::int > 0
       and (select count(*) from public.orders where fleet_id = v_fleet and status = 'pending') = 0
       and (select status from public.fleets where id = v_fleet) = 'SAILING' then
      f_cancel := true;
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  if not f_schema then raise exception '0008 self-assert FAIL: verb_schema() does not serve exactly the 8 V0 verbs (got %)', n; end if;
  if not f_fold  then raise exception '0008 self-assert FAIL: folding failed — cadiz/CADIZ/Cádiz/CAD did not all resolve to one port, or 8_000 / 8,000 did not parse'; end if;
  if not f_amb   then raise exception '0008 self-assert FAIL: an ambiguous prefix did not raise E_AMBIGUOUS listing several candidates, or an unknown port did not raise E_NO_SUCH_PORT'; end if;
  if not f_noise then raise exception '0008 self-assert FAIL: "sail gaivota cadiz" did not parse the same as "SAIL Gaivota TO Cádiz"'; end if;
  if not f_preview_clean then
    raise exception '0008 self-assert FAIL: preview left a trace (purse % -> %, stock % -> %) or reported no cost: %',
      v_purse0, v_purse1, v_stock0, v_stock1, v_prev;
  end if;
  if not f_stale then raise exception '0008 self-assert FAIL: a stale version was accepted: %', v_stale; end if;
  if not f_fixes then raise exception '0008 self-assert FAIL: a refusal did not carry a code, a sentence and a fix: %', v_iss; end if;
  if not f_full  then
    raise exception '0008 self-assert FAIL: the queue did not stop at % orders (depth %, last answer %)',
      public.wc_int('order_queue_max'), v_depth, v_full;
  end if;
  if not f_release then
    raise exception '0008 self-assert FAIL: CLEAR did not release a fleet halted by a failed order — that is a fleet stopped for ever';
  end if;
  if not f_cancel then raise exception '0008 self-assert FAIL: CANCEL/CLEAR did not empty the queue while leaving the voyage running (cancel %, clear %)', v_cancel, v_clear; end if;

  select count(*) into n from public.orders;
  if n <> 0 then raise exception '0008 self-assert FAIL: % order row(s) survived the probe subtransaction', n; end if;
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then raise exception '0008 self-assert FAIL: the command surface minted % client write grant(s)', v_grants; end if;

  raise notice '0008 self-assert ok: verb_schema serves exactly the 8 V0 verbs; cadiz/CADIZ/Cádiz/CAD all resolve to one port and 8_000 = 8,000 = 8000; "s" raises E_AMBIGUOUS listing every port it could be while "zzz" raises E_NO_SUCH_PORT; noise words TO/VIA are optional; preview of BUY salt 40 estimated % d. and left the purse at % and the stock at % untouched; a failed order halts the fleet until CLEAR releases it; E_STALE, E_QUEUE_FULL once % orders are waiting, and a refusal carrying code + sentence + % fix(es); CANCEL and CLEAR emptied the queue with the voyage still at sea; 0 client write grants',
    (v_prev->'estimate'->>'total'), v_purse1, v_stock1, v_depth, jsonb_array_length(v_iss->'fixes');
end $$;
