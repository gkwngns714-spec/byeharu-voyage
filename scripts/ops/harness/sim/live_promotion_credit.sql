CREATE OR REPLACE FUNCTION public.promotion_credit(p_player uuid, p_port uuid, p_focus text, p_points numeric)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0162: THE ONE WRITER of promotion items. A PLAYER's company banks the points of a track; at a port, every
-- whole `promotion_items.points` becomes one item in storage there. A merchant returns at once (O8).
-- Returns the items made.
declare
  v_item text;
  v_per  numeric;
  v_now  numeric;
  v_n    int := 0;
begin
  if p_points is null or p_points <= 0
     or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  select pi.item_code, pi.points into v_item, v_per from public.promotion_items pi where pi.focus = p_focus;
  if v_item is null then
    return 0;
  end if;
  insert into public.promotion_progress (player_id, focus, points) values (p_player, p_focus, p_points)
  on conflict (player_id, focus) do update set points = public.promotion_progress.points + excluded.points
  returning points into v_now;
  if p_port is not null and v_now >= v_per then
    v_n := floor(v_now / v_per)::int;
    update public.promotion_progress set points = points - v_n * v_per where player_id = p_player and focus = p_focus;
    insert into public.player_items (player_id, port_id, item_code, qty) values (p_player, p_port, v_item, v_n)
    on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + excluded.qty;
  end if;
  return v_n;
end $function$
