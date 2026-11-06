# The HQ's Production page: storage, cargo and recipes on one page (client only)

Owner, 2026-11-06: *"On HQ, merge storage and forge. left side is storage, center is cargo, right side is recipes. i should be able
to move cargo - storage. then once the production is made on right, i should also move from recipe - cargo. get it?"* And the same day:
name the tab Production (생산). The columns keep Storage, Cargo, Recipes.

## What the server already gave

| move | verb | since |
|---|---|---|
| cargo to storage | `STORE <good> <n>` (`cmd.do_store`) | 0070 |
| storage to cargo | `TAKE <good> <n>` (`cmd.do_take`) | 0070 |
| recipe: inputs out of storage, product into storage | `cmd.forge_good` | 0281 |
| finished good to cargo | the same `TAKE`: the forge lands its product in storage | 0070 + 0281 |

So there is **no migration**, and no second path. Port, room, ownership, locks and refusals are the verbs' own, unchanged.

**Nothing is ever "in production".** `cmd.forge_good` is instant: no job row, no timer. `forge_jobs` in docs/CORP_STORAGE_FORGE.md was
designed for the item forge and never built. A section that can never fill is not drawn. If the owner wants timed production, that
is a new server slice.

**What Finished means:** a stored good that a recipe here makes. The server keeps no mark of how a stored good got there, so a made good
that was bought and stored reads as Finished too.

## What changed

- `src/live/PortProduction.tsx`: the page. One `world.warehouse` read feeds Storage and Cargo; one `world.goods_forge` read feeds Recipes.
- `src/live/PortForge.tsx`: now the Recipes column: tiers on a segmented control, recipes as rows, the ones you can make first in a tier.
- `src/live/PortStorage.tsx` and `src/live/forgeGroups.ts`: deleted. The HQ's Storage and Forge tiles and their faces: deleted.
- The desk's Storage tab and the Town row are now doors to `/city?port=<code>&place=production` (`productionHref`, the one link). A saved
  `warehouse` desk face falls to the first face.
- `PageThree` (`components/ui/Card.tsx`): three columns from 1,024 px, one below. `Row end`: an act stands at the row's right edge, so a list's
  cells make one straight column; figure rows keep the owner's hug.
- The fleet picker is the command draft's one selection, shown only when two or more fleets lie here. Storage stays on screen while another
  fleet's cargo is asked for.

## Seen and measured (canary world, headless, DPR 2)

- A real press on a throwaway build with the ingredients planted: Forge Silk Cloth, the tray closed, Finished showed 1 unit, Take on board, Cargo
  showed 1 unit, storage space and the cargo bar followed. The hook was reverted before the final build.
- 1440, 1280, 1024: three across, no sideways scroll. 390: one column under the fixed control, no sideways scroll.
- Second fleet pressed: 0 frames with storage blank, Storage and Recipes boxes unchanged.
- A press on a cell: every box unchanged from the press to 1.5 s after.

## What is not proven

- Never driven on production. Two docked fleets were seen in the canary only through a planted empty fleet.
- The browser spec cannot press Forge: no harbour sells all three inputs of a recipe in the starter world. `tests/rpc.forge.spec.ts` holds that
  seam (forge, then `TAKE` through `cmd.issue`, the rest stays ashore, no money moves).
- Tier 1 is 180 recipes, so the Recipes column is long (about 9,600 px) and the page scrolls.
