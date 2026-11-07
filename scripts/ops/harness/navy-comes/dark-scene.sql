-- 0333 DARK PARITY SCENE: run by proof-0333.mjs on the world BEFORE the file and AFTER it, rolled back each time, beside the rich-cities, armed-cargo and navy scenes.
-- It covers what 0333 cuts that those do not reach: a company's world.fleets, byte for byte with the clock taken out; a PROBE battle, opened and closed through the real bodies, as a sailing attacker against a merchant, every row it writes;
-- both doors dark; and a free fleet's read while another is held. It names only what existed before 0333.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  c_uid constant uuid := '00000000-0333-4000-8000-0000000000aa';
  v_t   timestamptz := now();
  v_p   uuid;
  v_f   uuid;
  v_m   uuid;
  v_b   uuid;
  v_s   text;
begin
  v_p := public.new_house(c_uid, 'Casa Cena', 'PRT', 'LIS', 'Cena', (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Cena', null, false);
  select id into v_f from public.fleets where player_id = v_p;
  perform cmd.assume_identity(c_uid);
  select string_agg(regexp_replace(e::text, '"(id|version|ready_at|busy_until)": ("[^"]*"|[0-9]+|null)', '', 'g'), '|') into v_s from jsonb_array_elements(world.fleets()) e;
  raise notice 'SCENE: fleets %', md5(regexp_replace(v_s, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '', 'g'));
  raise notice 'SCENE: attack door %', cmd.attack(v_f, v_f) ->> 'error_code';
  raise notice 'SCENE: preview door %', cmd.preview_attack(v_f, v_f) ->> 'error_code';

  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  select nf.fleet_id into v_m from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.status = 'DOCKED' order by nf.roster_ord limit 1;
  update public.fleets set status = 'ANCHORED', port_id = null, lat = 10, lon = -30 where id = v_m;
  v_b := public.battle_open('PROBE', v_f, v_m, v_t);
  raise notice 'SCENE: sides %', (select jsonb_agg(jsonb_build_array(bs.side, bs.arrives_at = bs.joined_at, f.status, f.busy_until - v_t) order by bs.side)
                                     from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id where bs.battle_id = v_b);
  raise notice 'SCENE: resolve early %', public.battle_resolve(v_b, v_t + interval '1 second');
  raise notice 'SCENE: resolve %', public.battle_resolve(v_b, v_t + interval '601 seconds');
  raise notice 'SCENE: retry %', public.battle_resolve(v_b, v_t + interval '602 seconds');
  -- the outcome itself is seeded by the battle's random id, so it differs run to run: its presence is what is compared
  raise notice 'SCENE: closed %', (select jsonb_build_array(b.status, b.kind, b.result ? 'outcome', b.result ? 'navy') from public.battles b where b.id = v_b);
  raise notice 'SCENE: free %', (select jsonb_agg(jsonb_build_array(f.status, f.busy_until) order by f.status) from public.fleets f where f.id in (v_f, v_m));
  raise notice 'SCENE: report %', (select count(*) from public.events e where e.kind = 'BATTLE_REPORT' and e.payload ->> 'battle_id' = v_b::text);
end
$$;
