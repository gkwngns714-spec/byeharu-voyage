// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CATALOGUE — every RPC the client may call, named once
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Both backends are built FROM this table, not beside it: the local one turns a row into
// `select world.market($1::uuid) as result`, the cloud one turns the same row into
// `supabase.schema('world').rpc('market', { p_port })`. Adding an RPC therefore cannot mean
// "adding it in two places and hoping", and a parameter cannot be named one thing over the wire
// and another in SQL.
//
// The argument NAMES are PostgREST's contract (it calls functions by named argument), and the
// TYPES are Postgres's: a bare `$1` carrying null gives "could not determine data type of
// parameter", so every parameter is cast at the call site.
//
// NOT LISTED HERE, deliberately:
//   * `public.new_house()` and `cmd.assume_identity()` — server-only, revoked from every client
//     role by 0004/0008. The local adapter calls them as the superuser it is; a browser talking to
//     Supabase must never be able to.
//   * `voyage.settle()` — every read RPC settles first (D.2). A client-callable settle would be a
//     second way to advance time.
//   * the `tick_*` functions — those are the world's clock, not a player's verb.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface RpcArg {
  /** PostgREST calls functions by named argument; this is that name. */
  readonly name: string
  /** The Postgres type to cast to in a local call. */
  readonly type: string
}

export interface RpcSpec {
  readonly schema: 'world' | 'cmd'
  readonly fn: string
  readonly args: readonly RpcArg[]
  /** A verb that CHANGES the world. A preview does not: it is the same act rolled back. When one
   *  of these succeeds, `backend.call` drops the live answers in `src/store/resourceCache.ts`, so
   *  the next read of a price, a shed or a town hall asks the server again. */
  readonly mutates?: true
  /** SESSION-kept cache entries this verb also changes, by RPC-name prefix (a hire changes the
   *  officer roster, a study the skill book). Finite entries are dropped by `mutates` already. */
  readonly invalidates?: readonly string[]
}

const TABLE = {
  worldSnapshot: { schema: 'world', fn: 'snapshot', args: [] },
  worldMarket: { schema: 'world', fn: 'market', args: [{ name: 'p_port', type: 'uuid' }] },
  worldFleets: { schema: 'world', fn: 'fleets', args: [] },
  // 0068 — the workstation face's ONE read: what this city can make, what each costs, whether her
  // hold carries it, and what you already own here. `p_fleet` is optional because the face is
  // readable with no fleet alongside; name her and every recipe line says what is aboard.
  // 0070 — the warehouse face's ONE read: the shed's size, how full it is, what is ashore here and
  // what she is carrying that could join it. Both sides in one read, because the screen's whole job
  // is to move things between them and asking twice would let them disagree by a trade in between.
  worldWarehouse: {
    schema: 'world',
    fn: 'warehouse',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  // 0072 — the building yard's ONE read: what this yard can lay down, what each hull wants, and
  // how much of it is already ashore HERE. It takes no fleet: the materials come out of the city,
  // not out of a hold, which is the whole point of the building.
  // 0073 — who is drinking in this city's inn TODAY. A read with no fleet and no day argument: the
  // day is the world's own (world.game_day()), because an inn that took the day as a parameter
  // could be asked about tomorrow, and being able to look ahead is the same defect as re-rolling.
  worldInn: {
    schema: 'world',
    fn: 'inn',
    args: [{ name: 'p_port', type: 'uuid' }],
  },
  worldBuildingYard: {
    schema: 'world',
    fn: 'building_yard',
    args: [{ name: 'p_port', type: 'uuid' }],
  },
  worldWorkstation: {
    schema: 'world',
    fn: 'workstation',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  // 0281 — the City page's Forge face's ONE read: every crafted trade good with its
  // goods_recipes ingredients, how many of each are ashore HERE, and the server's can_forge
  // verdict. No fleet argument: the ingredients come out of the shed, not a hold (0072's reason).
  worldGoodsForge: {
    schema: 'world',
    fn: 'goods_forge',
    args: [{ name: 'p_port', type: 'uuid' }],
  },
  // 0281 — the Forge's one verb (cmd.forge_good): fleet-gated like cmd.invest, no money moves.
  cmdForgeGood: {
    schema: 'cmd',
    fn: 'forge_good',
    mutates: true,
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_product', type: 'uuid' },
      { name: 'p_qty', type: 'int' },
    ],
  },
  // 0039 — THE FREE SEA. The raster the client's pathfinder proposes over (the same row the
  // server verifies by — one authority, fetched once per session), and one place's sailed
  // distances to everywhere (the SAIL picker's ordering and figures).
  worldSeaRaster: { schema: 'world', fn: 'sea_raster', args: [] },
  worldReach: { schema: 'world', fn: 'reach', args: [{ name: 'p_from', type: 'uuid' }] },
  worldLedger: {
    schema: 'world',
    fn: 'ledger',
    args: [
      { name: 'p_cursor', type: 'timestamptz' },
      { name: 'p_limit', type: 'int' },
    ],
  },
  worldBuyCapacity: {
    schema: 'world',
    fn: 'buy_capacity',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
    ],
  },
  // 0086 — what a crew of N costs per voyage-day at sea, for ANY count: the Inn's caption as its
  // stepper moves. `p_crew` null means the crew aboard now. It is `public.crew_wages`, the sum
  // `voyage.settle` charges, so the client multiplies nothing (docs/NO_SPAGHETTI.md §1).
  worldCrewCost: {
    schema: 'world',
    fn: 'crew_cost',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_crew', type: 'int' },
    ],
  },
  // 0022 — THE BARGAIN. The read and the verb are named here together because they are one feature,
  // and because 0022 grants EXECUTE to `authenticated` on exactly the entry points this catalogue
  // declares (0018's sweep reads it BY NAME). A grant with no row here is a door nobody opens —
  // which is what 0022 shipped as, until this entry.
  //
  // Neither takes a player id: both read `public.current_player_id()` and refuse a fleet that is not
  // yours (E_NOT_YOURS / E_NOT_YOUR_FLEET). That is the same property that makes `cmd.found_house`
  // safe for a browser to hold.
  worldHaggleState: {
    schema: 'world',
    fn: 'haggle_state',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
    ],
  },
  cmdHaggle: {
    schema: 'cmd',
    fn: 'haggle',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
      // LOAD-BEARING, not decoration (0022:470-486): a BUY bargain is gated on the quay HAVING the
      // stock and a SELL one on her CARRYING the cargo, so the side decides which refusal you get.
      { name: 'p_side', type: 'text' },
    ],
  },
  cmdIssue: {
    schema: 'cmd',
    fn: 'issue',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_text', type: 'text' },
      { name: 'p_expected_version', type: 'int' },
      // 0039: a SAIL carries the PROPOSED course ([[lat,lon], …]). The server verifies it against
      // its own raster and measures it itself — a client cannot gain by lying here.
      { name: 'p_path', type: 'jsonb' },
    ],
  },
  cmdPreview: {
    schema: 'cmd',
    fn: 'preview',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_text', type: 'text' },
      { name: 'p_path', type: 'jsonb' },
    ],
  },
  // 0083 — THE MANIFEST: several lines at one quay as one order. `p_lines` is a JSON array of
  // `{side, good, qty}` (ManifestLine), which rides as jsonb exactly as cmdIssue's p_path does.
  // preview_basket runs the verbs and rolls them back; trade_basket commits them in one savepoint
  // and takes the fleet's version like cmd.issue, so a double-tap trades once (E_STALE).
  cmdPreviewBasket: {
    schema: 'cmd',
    fn: 'preview_basket',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_lines', type: 'jsonb' },
    ],
  },
  cmdTradeBasket: {
    schema: 'cmd',
    fn: 'trade_basket',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_lines', type: 'jsonb' },
      { name: 'p_expected_version', type: 'int' },
    ],
  },
  // 0087 — THE REQUEST BOARD. `world.contracts(p_port)` is a READ with no fleet and no player id:
  // a request is a fact about a port, and reading it is what winds the board there (the read is
  // the catch-up). `cmd.preview_fulfil` runs the delivery and rolls it back; `cmd.fulfil` commits
  // it in one savepoint and takes the fleet's version like trade_basket, so a double-tap delivers
  // once (E_STALE). Both refuse a fleet that is not yours with cmd.issue's own E_NO_SUCH_FLEET.
  worldContracts: { schema: 'world', fn: 'contracts', args: [{ name: 'p_port', type: 'uuid' }] },
  cmdPreviewFulfil: {
    schema: 'cmd',
    fn: 'preview_fulfil',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_contract', type: 'uuid' },
    ],
  },
  cmdFulfil: {
    schema: 'cmd',
    fn: 'fulfil',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_contract', type: 'uuid' },
      { name: 'p_expected_version', type: 'int' },
    ],
  },
  cmdCancel: {
    schema: 'cmd',
    fn: 'cancel_at',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_index', type: 'int' },
    ],
  },
  cmdClear: {
    schema: 'cmd',
    fn: 'clear',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_include_active', type: 'boolean' },
    ],
  },
  cmdVerbSchema: { schema: 'cmd', fn: 'verb_schema', args: [] },
  // 0226 — THE chart read: one good at one city over 1d / 1w / 1m / 1y / all, both sides of every point,
  // from the tier the span lives in. Replaced 0013's world.price_history (one port, every good, 12 h).
  worldPriceSeries: {
    schema: 'world',
    fn: 'price_series',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
      { name: 'p_span', type: 'text' },
    ],
  },
  // 0226 — the press that keeps a city's price for a good it does not sell. Identity is the JWT's.
  cmdWatchPrice: {
    schema: 'cmd',
    fn: 'watch_price',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
    ],
  },
  // 0227 — who bought what: a city's recent trades of one good (owner row 211). Names shown, no purses.
  worldCityGoodTrades: {
    schema: 'world',
    fn: 'city_good_trades',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
      { name: 'p_limit', type: 'int' },
    ],
  },
  // Takes NO id — the server reads auth.uid(), so a caller can only ever read their own house.
  worldPlayer: { schema: 'world', fn: 'player', args: [] },
  worldOfficers: { schema: 'world', fn: 'officers', args: [] },
  worldSkills: { schema: 'world', fn: 'skills', args: [] },
  // THE BOARD (0025). `p_limit` bounds the rows returned, never who may be on them — the server
  // decides what a board row may carry (name, nation, standing, and the fames the standing is
  // computed from) and `public.standings` is unreadable to every client role, so a wider limit
  // cannot widen a row. Your own position comes back in `you` even when you are off the board.
  worldStandings: { schema: 'world', fn: 'standings', args: [{ name: 'p_limit', type: 'int' }] },
  // WHAT IS ON AT THE QUAY (0026). Null port = the catalogue of kinds with no port's own running
  // list. Reading it is also what WINDS the calendar where pg_cron is absent, which is 0009's
  // catch-up idiom and the reason this is a read the client makes rather than a job someone runs.
  worldBuffs: { schema: 'world', fn: 'buffs', args: [{ name: 'p_port', type: 'uuid' }] },
  cmdHireOfficer: {
    schema: 'cmd',
    fn: 'hire_officer',
    mutates: true,
    invalidates: ['worldOfficers'],
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  cmdStudySkill: {
    schema: 'cmd',
    fn: 'study_skill',
    mutates: true,
    invalidates: ['worldSkills'],
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  // 0131 — THE SKILLS SCREEN (docs/SHIPS_AND_SKILLS.md §5.1). Enrol where a skill is taught (the fleet
  // names where you are), and set the whole training queue. Neither takes a player id; the server
  // validates the whole queue with the one rule world.skills answers from.
  cmdSkillEnroll: {
    schema: 'cmd',
    fn: 'skill_enroll',
    mutates: true,
    invalidates: ['worldSkills'],
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  cmdSkillQueueSet: {
    schema: 'cmd',
    fn: 'skill_queue_set',
    mutates: true,
    invalidates: ['worldSkills'],
    args: [{ name: 'p_entries', type: 'jsonb' }],
  },
  // 0092 — STANDING ROUTES (docs/TRADE_ROUTES.md, slice 1). One read and four verbs, landed with the
  // migration's catalogue rows and with the face that reads them (COMMAND's RouteFold), because a
  // grant with no catalogue entry is a door nobody opens (0022). None takes a player id. Assign with
  // a null fleet takes the route off its fleet — that is not a fifth verb. A route never trades by
  // itself: it writes its fleet's next orders into the one queue when the queue runs dry in port.
  worldStandingRoutes: { schema: 'world', fn: 'standing_routes', args: [] },
  // 0106 (owner row 115) — EVERY LANE THE WORLD SAILS: her routes and the merchants', with the
  // distance and the earnings to rank them by. A read, consulted rather than played, so it does
  // not ride the shell's beat; ROUTES asks it on mount and on the beat while it is up.
  worldRouteBoard: { schema: 'world', fn: 'route_board', args: [] },
  // 0099 — MERCHANTS (docs/NPC_TRADERS.md §7). Two reads, no player id, dark until the owner's
  // switch: where every merchant fleet is (read on the shell's beat while MAP or PORT is up), and
  // one merchant fleet's card (read at a tap). Neither answers for a player's fleet.
  // 0118 — the ROSTER replaces the window read: every merchant once, then only what moved since.
  worldSeaRoster: { schema: 'world', fn: 'sea_roster', args: [{ name: 'p_since', type: 'timestamptz' }] },
  worldNpcFleetCard: { schema: 'world', fn: 'npc_fleet_card', args: [{ name: 'p_fleet', type: 'uuid' }] },
  // 0213 — INSURANCE: the caller's insured voyages under way and the last ones the insurance paid on.
  // A READ at a face (the desk's Plans), never on the beat. The price itself is `cmd.preview`'s: a SAIL's
  // estimate carries `insurance` (quoted unasked, charged with the word INSURED).
  worldInsurance: { schema: 'world', fn: 'insurance', args: [] },
  // 0121 (owner, 2026-10-15) — ONE FLEET'S TRADING: her newest seven laps, stop by stop, what she
  // bought and sold and where; the lap under way; the last real day. A merchant's (switch on) or the
  // caller's own fleet. A READ, at a tap (the merchant sheet, the voyage tray), never on the beat.
  worldFleetTrades: { schema: 'world', fn: 'fleet_trades', args: [{ name: 'p_fleet', type: 'uuid' }] },
  // 0104 — ONE HARBOUR'S MERCHANTS (owner row 121): which merchant companies this quay concerns and
  // what each one is DOING here, read at a TAP like the card and never on the beat — sea_traffic is
  // the beat's read and it must not grow. A read, no player id, dark until the owner's switch; a
  // player's fleet is never a row.
  worldPortMerchants: { schema: 'world', fn: 'port_merchants', args: [{ name: 'p_port', type: 'uuid' }] },
  // 0122/0123 (owner, 2026-10-15) — THE TOWN HALL: one harbour's purse, its works, who invested, and
  // what you hold there. A READ at a tap (the city's fourth tab), never on the beat. The buy and its
  // dry run take no fleet and no player id: the caller's company buys, only while a fleet of hers
  // lies docked at that harbour (E_NOT_DOCKED) — the read's `you.docked` is the same test.
  worldTownHall: { schema: 'world', fn: 'town_hall', args: [{ name: 'p_port', type: 'uuid' }] },
  // 0278 (the month) — THE CITY'S HISTORY: the months of giving, the current one first, up to 8
  // past. A READ at a tap (the city's sixth tab), never on the beat. The month, the dates and the
  // totals are served; the client computes none of them.
  worldCityHistory: {
    schema: 'world',
    fn: 'city_history',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_months', type: 'int' },
    ],
  },
  cmdPreviewInvest: {
    schema: 'cmd',
    fn: 'preview_invest',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_kind', type: 'text' },
      { name: 'p_shares', type: 'int' },
    ],
  },
  cmdInvest: {
    schema: 'cmd',
    fn: 'invest',
    mutates: true,
    invalidates: ['worldAllegiance'],
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_kind', type: 'text' },
      { name: 'p_shares', type: 'int' },
    ],
  },
  // 0152 — THE TOW: a fleet of yours lying UNABLE_TO_SAIL in a port (every hull at 0) is towed to the
  // nearest harbour with a shipyard and lies docked there, where REPAIR takes it. The dry run is the
  // real tow rolled back — the fee and the harbour printed are the ones charged, or the refusal the
  // press would get (E_NOT_WRECKED, E_TOW_FUNDS with have / need in ducats, …). Not a line of the
  // grammar: a wreck cannot run her queue (cmd.advance stops at a fleet that is not docked).
  cmdPreviewTow: { schema: 'cmd', fn: 'preview_tow', args: [{ name: 'p_fleet', type: 'uuid' }] },
  cmdTow: {
    schema: 'cmd',
    fn: 'tow',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_expected_version', type: 'int' },
    ],
  },
  cmdStandingRouteSave: {
    schema: 'cmd',
    fn: 'standing_route_save',
    mutates: true,
    args: [
      { name: 'p_route', type: 'uuid' },
      { name: 'p_name', type: 'text' },
      { name: 'p_stops', type: 'jsonb' },
      { name: 'p_reserve', type: 'bigint' },
      { name: 'p_losing', type: 'int' },
    ],
  },
  cmdStandingRouteDelete: {
    schema: 'cmd',
    fn: 'standing_route_delete',
    mutates: true,
    args: [{ name: 'p_route', type: 'uuid' }],
  },
  cmdStandingRouteAssign: {
    schema: 'cmd',
    fn: 'standing_route_assign',
    mutates: true,
    args: [
      { name: 'p_route', type: 'uuid' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  cmdStandingRoutePause: {
    schema: 'cmd',
    fn: 'standing_route_pause',
    mutates: true,
    args: [
      { name: 'p_route', type: 'uuid' },
      { name: 'p_paused', type: 'boolean' },
    ],
  },
  // 0039: the helm order at sea — she turns WHERE SHE IS. The destination is a port OR any point
  // of open water, and the proposed onward course rides along (bridged server-side to her true
  // position and verified as water like every other course). Not a verb: it acts on the queue and
  // the voyage NOW, like cancel_at and clear.
  cmdDivert: {
    schema: 'cmd',
    fn: 'divert',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_dest', type: 'uuid' },
      { name: 'p_dest_point', type: 'jsonb' },
      { name: 'p_path', type: 'jsonb' },
    ],
  },
  // The ONE way a signed-in captain gets a house (0011). It takes no uid — the server reads
  // auth.uid() — which is why it is safe for a browser to hold, unlike public.new_house().
  // 0143 (docs/INFLUENCE.md I1): every harbour's flag, and a company's change of country.
  worldAllegiance: { schema: 'world', fn: 'allegiance', args: [] },
  cmdChangeCountry: { schema: 'cmd', fn: 'change_country', mutates: true, invalidates: ['worldAllegiance'], args: [{ name: 'p_nation_code', type: 'text' }] },
  // 0144 (docs/INFLUENCE.md I2): a gift to a city, and its dry run (the Town Hall's Donate).
  cmdDonate: { schema: 'cmd', fn: 'donate', mutates: true, invalidates: ['worldAllegiance'], args: [{ name: 'p_port', type: 'uuid' }, { name: 'p_coin', type: 'bigint' }] },
  cmdPreviewDonate: { schema: 'cmd', fn: 'preview_donate', args: [{ name: 'p_port', type: 'uuid' }, { name: 'p_coin', type: 'bigint' }] },
  // 0147 (docs/INFLUENCE.md I5): the mayor sets the city's profit tax.
  cmdSetTax: { schema: 'cmd', fn: 'set_tax', mutates: true, args: [{ name: 'p_port', type: 'uuid' }, { name: 'p_rate', type: 'numeric' }] },
  // 0148 (docs/INFLUENCE.md I6): Rank's Countries board.
  worldNationStandings: { schema: 'world', fn: 'nation_standings', args: [] },
  // 0157 (docs/SKILLS_AND_CAPTAINS.md K5): seat a captain in a cabin of a ship, move her, or put her
  // ashore (ship null). Only in port — the server refuses E_NOT_IN_PORT otherwise.
  // 0160 (docs/SKILLS_AND_CAPTAINS.md K6): your captains — levels in three tracks, homesickness,
  // traits — and choosing the traits one of them uses (only ashore or in port).
  worldCaptains: { schema: 'world', fn: 'captains', args: [] },
  cmdCaptainTraitsSet: {
    schema: 'cmd',
    fn: 'captain_traits_set',
    mutates: true,
    invalidates: ['worldCaptains'],
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_traits', type: 'text[]' },
    ],
  },
  // 0162 (K8): promote a captain — her ship docked, her level, the items in storage there.
  cmdPromoteCaptain: { schema: 'cmd', fn: 'promote_captain', mutates: true, invalidates: ['worldCaptains'], args: [{ name: 'p_code', type: 'text' }] },
  cmdSeatCaptain: {
    schema: 'cmd',
    fn: 'seat_captain',
    mutates: true,
    invalidates: ['worldCaptains'],
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_ship', type: 'uuid' },
      { name: 'p_seat', type: 'int' },
    ],
  },
  // 0163 (docs/SHIPS_AND_SKILLS.md S16): augment one of your mounted fittings with a perk you choose,
  // paid in kits from the store in this city (a level 3 workshop; the server refuses in its own words).
  cmdAugmentFitting: {
    schema: 'cmd',
    fn: 'augment_fitting',
    mutates: true,
    args: [
      { name: 'p_ship', type: 'uuid' },
      { name: 'p_item', type: 'text' },
      { name: 'p_perk', type: 'text' },
      { name: 'p_rank', type: 'int' },
    ],
  },
  cmdFoundHouse: {
    schema: 'cmd',
    fn: 'found_house',
    mutates: true,
    invalidates: ['worldOfficers', 'worldSkills'],
    args: [
      { name: 'p_company_name', type: 'text' },
      { name: 'p_nation_code', type: 'text' },
    ],
  },
  // 0170 / 0171 — THE COMMAND DESK's three reads (docs/COMMAND_DESK.md §7). A good's estimated price
  // at one city (the server's path and band; the client draws it and multiplies nothing), one good at
  // every city for your fleet (the money through world.quote), and every good once (the watchlist).
  // Asked when the desk opens a good or the list, and at the market's edge — never on the beat.
  worldPriceOutlook: {
    schema: 'world',
    fn: 'price_outlook',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
      { name: 'p_slots', type: 'int' },
      { name: 'p_side', type: 'text' },
    ],
  },
  worldGoodBoard: {
    schema: 'world',
    fn: 'good_board',
    args: [
      { name: 'p_good', type: 'uuid' },
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_from', type: 'uuid' },
      { name: 'p_qty', type: 'numeric' },
    ],
  },
  worldWatchlist: { schema: 'world', fn: 'watchlist', args: [{ name: 'p_fleet', type: 'uuid' }] },
  // 0176 — WHAT YOU HOLD, in every city: the share register's rows, a share's price there now, the dividends
  // collected (docs/COMMAND_DESK.md §3.7). No arguments: the company is the caller's.
  worldHoldings: { schema: 'world', fn: 'holdings', args: [] },
  // 0177 — THE BOOKS: the ledger by game day and kind, each kind under its one word, each day's net
  // (docs/COMMAND_DESK.md §3.8). The window in game days, 1..30.
  worldBooks: { schema: 'world', fn: 'books', args: [{ name: 'p_days', type: 'int' }] },
  // 0185 — WHY THIS PRICE (docs/PRICE_FACTORS.md §5): a good's market price at one city and each term it
  // is made of, as a multiplier. A READ; asked when the good page's city changes and at the market's edge.
  worldPriceWhy: {
    schema: 'world',
    fn: 'price_why',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
    ],
  },
  // 0214 — THE STATS TAB (docs/dev-log/2026-10-20-stats-tab.md): six READS over the rollup public.tick_stats
  // writes every fifteen minutes. The world's money and what moved; every good across every market; every
  // city at YOUR tier (the gate is the server's — a locked city arrives without figures); the merchants'
  // day; your week and the leaderboard (rank and name only). None takes a player id.
  worldStatsOverview: { schema: 'world', fn: 'stats_overview', args: [{ name: 'p_hours', type: 'int' }, { name: 'p_span', type: 'text' }] },
  worldStatsMarkets: { schema: 'world', fn: 'stats_markets', args: [] },
  worldStatsCities: { schema: 'world', fn: 'stats_cities', args: [] },
  worldStatsCity: { schema: 'world', fn: 'stats_city', args: [{ name: 'p_port', type: 'uuid' }, { name: 'p_span', type: 'text' }] },
  worldStatsMerchants: { schema: 'world', fn: 'stats_merchants', args: [{ name: 'p_span', type: 'text' }] },
  worldStatsMe: { schema: 'world', fn: 'stats_me', args: [] },
  // 0224 — THE FIGURES KEEP TO THE SECOND (owner row 200; docs/dev-log/2026-10-26-stats-live.md): the one LIVE read,
  // asked every second while the Stats tab is open. Base row + the journal since the last count; no aggregate scan.
  worldStatsNow: { schema: 'world', fn: 'stats_now', args: [] },
  // 0235 — EVERY COIN THAT MOVES IS TOLD (owner row 219; docs/dev-log/2026-10-26-money-feed.md): both money books'
  // moves after `p_after` (null = no bound), newest first, at most `p_limit` (1…200). Asked every second beside World money.
  worldMoneyFeed: {
    schema: 'world',
    fn: 'money_feed',
    args: [
      { name: 'p_after', type: 'timestamptz' },
      { name: 'p_limit', type: 'int' },
    ],
  },
  // 0215 — THE SEA CONDITIONS (docs/SEA_CONDITIONS_AND_REGIONS.md): every zone with the title and the wave
  // resistance it asks, the caller's title, each of her fleets' wave, and whether the conditions bite yet. A
  // READ, no arguments (the company is the caller's). The Codex "Seas" face and the map's shading (C3) read it.
  worldSeaConditions: { schema: 'world', fn: 'sea_conditions', args: [] },
  // 0175 — A PLAN'S LINES AS ONE (docs/COMMAND_DESK.md §7.4): every line parsed by the one grammar,
  // queued by the one enqueuer, all or none. The plan builder's "Queue it once".
  cmdIssueLines: {
    schema: 'cmd',
    fn: 'issue_lines',
    mutates: true,
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_lines', type: 'jsonb' },
      { name: 'p_expected_version', type: 'int' },
    ],
  },
} as const satisfies Record<string, RpcSpec>

export type RpcName = keyof typeof TABLE

/** The catalogue, widened to its contract: every row may now carry `mutates`/`invalidates`, which
 *  `call()` reads after a verb succeeds. `TABLE` still pins the keys and the argument names. */
export const RPCS: Record<RpcName, RpcSpec> = TABLE

/** `world.snapshot()` — for logs and error messages, spelled the way the migration spells it. */
export function rpcLabel(name: RpcName): string {
  const spec: RpcSpec = RPCS[name]
  return `${spec.schema}.${spec.fn}(${spec.args.map((a) => a.name).join(', ')})`
}

/** The SQL a local call runs. One `select`, aliased `result`, so the caller reads one column. */
export function localSql(name: RpcName): string {
  const spec: RpcSpec = RPCS[name]
  const params = spec.args.map((a, i) => `$${i + 1}::${a.type}`).join(', ')
  return `select ${spec.schema}.${spec.fn}(${params}) as result`
}

/** The named-argument object a PostgREST call posts. */
export function namedArgs(name: RpcName, values: readonly unknown[]): Record<string, unknown> {
  const spec: RpcSpec = RPCS[name]
  const out: Record<string, unknown> = {}
  spec.args.forEach((arg, i) => {
    out[arg.name] = values[i] ?? null
  })
  return out
}
