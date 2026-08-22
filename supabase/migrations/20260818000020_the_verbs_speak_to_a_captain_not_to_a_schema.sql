-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0020 — THE VERBS SPEAK TO A CAPTAIN, NOT TO A SCHEMA
--        cmd.verb_schema()'s `help` strings become sentences a player can read. Nothing else in
--        the grammar moves — and that is asserted, not promised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- These strings used to be developer notes that nothing rendered. They are now printed straight
-- onto the COMMAND tab's verb cards, which makes every one of them player-facing copy — and two of
-- them were not written to be:
--
--   SAIL  "Send a fleet to sea along the authored leg graph."
--         "authored" and "leg graph" are schema words. `public.legs` is a table; a captain sails a
--         sea road. A player has no way to know the sentence is about `legs.distance_nm`, and no
--         reason to want to.
--   SELL  "... ALL and HALF are read when the order RUNS, not when it is typed."
--         THE GAME NO LONGER HAS TYPING. Orders are composed by tapping — `validate.ts` was deleted
--         and the Command tab became a picker (src/features/command/README.md). The sentence
--         describes an interface that does not exist, which is worse than jargon: it is false.
--         The property it is about is real and worth saying, so it is said about the world instead:
--         what is aboard when she arrives is what goes ashore.
--
-- The rest are re-cut in the same pass, because a screen that prints eight sentences in two
-- registers reads as a bug. Numbers that were already player-visible (the ten-tun step, the x2.5
-- crew rate, the 100 per cent repair) are kept — they are facts a trader acts on. What goes is the
-- vocabulary of the schema.
--
-- ── SUPERSEDES 0008:160 — AND ONLY ITS PROSE ────────────────────────────────────────────────────
-- The grammar is the contract between `cmd.parse` (0008:207), the tap-builder
-- (src/features/command) and every order ever queued. This file does not touch it: same eight
-- verbs, same argument names, types, keywords, defaults, `required` and `repeat` flags, in the same
-- order. The self-assert below proves that by capturing the LIVE schema before the replacement,
-- stripping `help` from both, and requiring the remainder to be EQUAL — which is a stronger claim
-- than a sentence in this header, and the only kind worth making about a re-cut function
-- (docs/NO_SPAGHETTI.md §3).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   * It does not touch `cmd.fixes()` or any refusal sentence. Those are a different surface with
--     their own contract (§F.5's code + sentence + fixes) and re-cutting them blind, in a file
--     about help text, is how a slice stops being one thing.
--   * It does not add a `help` string for a verb that has none. Eight in, eight out.
--
-- Depends ONLY on: 0008 (cmd.verb_schema), 0018 (the EXECUTE lockdown — `create or replace` keeps
--                  the ACL, and the assert re-reads it rather than assuming so).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGE, captured before the replacement so the no-op can be PROVEN rather than claimed.
-- A temporary table, dropped at the foot of this file: it is scaffolding for one assert, not schema.
create temporary table verb_schema_before_0020 as
  select cmd.verb_schema() as js;

create or replace function cmd.verb_schema()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Served to the tap-builder so the pad and any other surface share ONE grammar (DESIGN F.4).
  -- Tapping through these arguments assembles exactly the string cmd.parse reads.
  --
  -- 0020: every `help` here is printed to a player on the Command tab's verb cards. It is copy.
  -- It says what the order DOES and what it will cost; it never names a table, a column, a
  -- migration or a section of the design document, and it never describes typing, because there
  -- is none.
  select '[
    {"verb":"SAIL","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"dest","type":"port","required":true,"keyword":"TO"},
       {"name":"via","type":"port","required":false,"repeat":true,"keyword":"VIA"}],
     "help":"Put to sea for another port. She takes the sea road between them, which is longer than the line on the map, and you can name ports to call at on the way."},
    {"verb":"BUY","args":[
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"qty","required":true},
       {"name":"limit","type":"price","required":false,"keyword":"AT","op":"<="}],
     "help":"Take cargo aboard. A big order is filled ten tuns at a time and each ten costs a little more than the last, so the price you are shown is the price of the first ten. Name a top price and she buys only what she can get under it."},
    {"verb":"SELL","args":[
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"qty","required":true},
       {"name":"limit","type":"price","required":false,"keyword":"AT","op":">="}],
     "help":"Sell out of the hold, ten tuns at a time, each ten fetching a little less than the last. ALL and HALF are counted when she reaches the quay, so whatever is aboard on arrival is what goes ashore. Name a floor price and she sells only above it."},
    {"verb":"PROVISION","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"mode","type":"enum","values":["FULL","DAYS"],"required":false,"default":"FULL"},
       {"name":"days","type":"number","required":false}],
     "help":"Take on water and food. FULL fills her stores to the brim; ask for a number of days instead and she carries only that, leaving the rest of the hold for cargo."},
    {"verb":"HIRE","args":[
       {"name":"count","type":"number","required":true},
       {"name":"fleet","type":"fleet","required":false}],
     "help":"Sign on hands. A port has only so many idle men; once they are taken the rest want two and a half times the wage."},
    {"verb":"REPAIR","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"to_pct","type":"number","required":false,"keyword":"TO","default":100}],
     "help":"Put her in the yard. It takes days at anchor and she cannot sail until the work is done. Ask for less than sound and she is out sooner and cheaper."},
    {"verb":"CANCEL","args":[
       {"name":"index","type":"number","required":false}],
     "help":"Drop one order that has not run yet — say which one, or leave it and the next one goes."},
    {"verb":"CLEAR","args":[
       {"name":"all","type":"flag","required":false}],
     "help":"Drop every order still waiting. CLEAR ALL also turns a fleet already at sea for home."}
  ]'::jsonb
$$;

comment on function cmd.verb_schema() is
  'THE grammar, served to the tap-builder. Supersedes 0008:160 in its `help` strings ONLY — the '
  'verbs, arguments, types, keywords and defaults are byte-identical, which 0020 proves by '
  'comparing the pre-image with `help` stripped from both. The help is player-facing copy now: the '
  'Command tab prints it on the verb cards.';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before   jsonb;
  v_after    jsonb := cmd.verb_schema();
  v_g_before jsonb;
  v_g_after  jsonb;
  v_n        int;
  v_bad      text;
  v_changed  int;
  v_shortest int;
  -- The words that have no business in front of a player. `type`/`schema`/`index` are NOT here:
  -- "index" is what CANCEL's own argument is called and the sentence has to be able to say so, and
  -- a blanket ban on ordinary English words is a rule that gets deleted the first time it misfires.
  v_jargon   constant text[] := array[
    'leg graph', 'authored', 'jsonb', 'uuid', 'schema', 'migration', 'rpc',
    'port_goods', 'null', 'boolean', 'enum ', 'typed', 'type it', 'keyboard'];
  w          text;
  f_grammar  boolean := false;
  f_prose    boolean := false;
  f_verbs    boolean := false;
  f_grant    boolean := false;
begin
  select js into v_before from verb_schema_before_0020;
  if v_before is null then
    raise exception '0020 self-assert FAIL: the pre-image of cmd.verb_schema() was not captured, so the no-op below would be comparing nothing with nothing';
  end if;

  -- (a) THE GRAMMAR DID NOT MOVE. Strip `help` from both sides and require the rest to be EQUAL.
  --     This is the whole safety of the file: parse, the tap-builder and every queued order read
  --     these argument names, and a typo here breaks the only way into the game.
  select jsonb_agg(e - 'help' order by ord) into v_g_before
    from jsonb_array_elements(v_before) with ordinality t(e, ord);
  select jsonb_agg(e - 'help' order by ord) into v_g_after
    from jsonb_array_elements(v_after) with ordinality t(e, ord);
  if v_g_before = v_g_after then f_grammar := true; end if;

  -- (b) EIGHT VERBS, EACH WITH HELP. 0008's own assert requires exactly eight; this file may not
  --     quietly gain or lose one, and a verb whose card would print nothing is a blank card.
  select count(*) into v_n from jsonb_array_elements(v_after) e
   where e ? 'help' and length(e->>'help') >= 40;
  if v_n = jsonb_array_length(v_after) and v_n = 8 then f_verbs := true; end if;

  -- (c) THE PROSE ACTUALLY CHANGED, and none of it talks to a developer. Both halves matter: a
  --     file that renamed nothing would pass a jargon sweep vacuously, and the jargon sweep is the
  --     reason the file exists.
  select count(*) into v_changed
    from jsonb_array_elements(v_before) with ordinality b(eb, ord)
    join jsonb_array_elements(v_after)  with ordinality a(ea, ord2) on ord2 = ord
   where eb->>'help' is distinct from ea->>'help';
  v_bad := null;
  foreach w in array v_jargon loop
    select string_agg(format('%s: "%s"', e->>'verb', w), '; ') into v_bad
      from jsonb_array_elements(v_after) e
     where position(w in lower(e->>'help')) > 0;
    exit when v_bad is not null;
  end loop;
  if v_changed >= 2 and v_bad is null then f_prose := true; end if;

  -- (d) `create or replace` keeps a function's ACL — but 0017's own posture assert failed on a
  --     claim that should have been free, so it is re-read rather than assumed. verb_schema is a
  --     declared client entry point (0018), so `authenticated` must still hold it and `anon` must
  --     not, and the lockdown's two authorities must still read zero.
  if has_function_privilege('authenticated', 'cmd.verb_schema()', 'execute')
     and not has_function_privilege('anon', 'cmd.verb_schema()', 'execute')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0 then
    f_grant := true;
  end if;

  if not f_grammar then raise exception '0020 self-assert FAIL: the grammar changed. Before: % / After: %', v_g_before, v_g_after; end if;
  if not f_verbs   then raise exception '0020 self-assert FAIL: % of % verb(s) carry a help sentence of at least 40 characters, and there must be 8 of 8', v_n, jsonb_array_length(v_after); end if;
  if not f_prose   then raise exception '0020 self-assert FAIL: % help string(s) changed and the jargon sweep found %', v_changed, coalesce(v_bad, 'nothing (so it proved nothing)'); end if;
  if not f_grant   then raise exception '0020 self-assert FAIL: the replacement moved cmd.verb_schema()''s grants, or a client write/execute grant appeared'; end if;

  select min(length(e->>'help')) into v_shortest from jsonb_array_elements(v_after) e;

  raise notice '0020 self-assert ok: cmd.verb_schema() still serves exactly 8 verbs whose arguments, types, keywords, defaults and order are BYTE-IDENTICAL to 0008''s — proven against the live pre-image with `help` stripped from both sides, not asserted in prose; all 8 help strings are player-facing sentences (shortest % characters) and % of them were rewritten; a sweep of % developer word(s) — "leg graph", "authored", "typed" among them — found none of them in front of a player; and the re-cut kept its grants, with authenticated still able to call it, anon still unable, 0 client write grants and 0 client-executable writers',
    v_shortest, v_changed, array_length(v_jargon, 1);
end $$;

drop table verb_schema_before_0020;
