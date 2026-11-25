# 2026-11-25: `stores-in-hold`: 0508 (dark: 0345's `ship_stores_separate`, true today), proof 210

Stacked on 0498. Server only. Nothing touched production; no knob moved; no production read.

## Measured first (local PGlite, a Barca, full crew, a fixed job, the stores put in the hold by hand)
- `BUY ALL` fills the hold; the SAIL's own stores then have no room and it is refused (E_ENDURANCE) with the cargo aboard.
  Lisbon to Las Palmas stopped on its third run, 409,665 coin down in unsold cargo; Lisbon to Cape Town on its first, at Luanda.

## What is built
- A fixed run and a land haul take their way's stores on first (`PROVISION DAYS n`), then load beside them; the run's quote is cut to it.
- One authority for room: `public.fleet_free_hold`. One for a top-up's size: `public.stores_topup`.
- `public.stores_in_hold_light()` is the one step; `public.stores_in_hold_ready()` is the read before it.

## Who is over her hold on the day, and how they are kept safe
By the rule: every hull whose cargo is within her water and food of her hold (a job's fleet between BUY ALL and its sale, a laden
merchant or crown ship, any full hold in port). The count was not read: `select public.stores_in_hold_ready()` is the lead's.
They keep cargo and stores and load nothing until under. The light gives each laden hull 7 days of grace
(`ships.hold_grace_until`): her top-ups go by her own stores space as before, so no laden run is refused its next sail.
After it, a hull still full of cargo must sell a little before a longer sail.

Not built: the client's hold bar.

## The self-assert's dice (fixed 2026-11-25)
A founding hull's hold is rolled (180 to 190 t, whole tuns); anise is 0.6 t a unit; BUY ALL left a scrap of 0 to 0.4 t, and 0.4 t of water
and food carries a full crew past a 100 nm need. Measured on one world: 1 of 12 runs "found room for a sail's stores". The probe now makes
its good one tun a unit (rolled back), so a full hold has no scrap. 12 of 12 after.
