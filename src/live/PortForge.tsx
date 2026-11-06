import { useState } from 'react'
import {
  Button,
  Clip,
  Figure,
  GoodClassMark,
  GoodKind,
  Note,
  Row,
  Segmented,
  Tray,
  goodClassRow,
  type TrayDetent,
} from '../components/ui'
import { useWorld } from './worldStore'
import { formatInt } from '../lib/format'
import { cmdForgeGood, type FleetView, type ForgeRecipe, type ForgeView, type Refusal } from '../lib/rpc'
import { useT, t as tNow } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FORGE — where raw goods become a crafted trade good (0281), as a field of tiles.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner's City page: the Forge is "using raw materials + recipes, produce foods, goods,
// weapons for trading." That is the GOODS economy — public.goods_recipes (0280) — not the
// workshop's fittings (0068/city Port), and not the future corp item forge. Nothing here reads
// item_recipes or item_storage.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// Whether every ingredient is ashore, what the product's recipe is, whether a fleet of yours lies
// here. All three come down the wire from `world.goods_forge(port)`, because all three are rules
// `cmd.forge_good` enforces. A recipe short of materials still SHOWS, muted, with the shortfall in
// its tray: hiding it would make the catalogue look smaller than it is.
//
// ── THE RECIPES COLUMN (2026-11-06, owner: *"right side is recipes"*) ──────────────────────────
// This is the right column of the HQ's Production page (PortProduction.tsx), which owns the one read and the one open tray. There are
// 287 recipes, one tier on the glass at a time; a press on a tier selects, and only the rows under it change. In a tier, what the
// server says can be made now stands first (`can_forge`), so it is not lost among the ones short of goods.

/** One group per product tier, in the served order (the query orders by tier, then name). */
function groupsByTier(recipes: readonly ForgeRecipe[]): [number, ForgeRecipe[]][] {
  const groups = new Map<number, ForgeRecipe[]>()
  for (const r of recipes) {
    const group = groups.get(r.tier)
    if (group) group.push(r)
    else groups.set(r.tier, [r])
  }
  return [...groups.entries()]
}

/** What is missing for one batch, in the server's own figures — a rendering of served numbers,
 *  never a re-derivation of `can_forge` (which the server sends). */
function shortfall(recipe: ForgeRecipe): string | null {
  const short = recipe.ingredients.filter((i) => i.have < i.qty)
  if (short.length === 0) return null
  return short.map((i) => `${i.name} ${formatInt(i.have)}/${formatInt(i.qty)}`).join(' · ')
}

export function PortForge({
  portId,
  fleet,
  view,
  open: openProduct,
  onOpen,
  onClose,
}: {
  portId: string
  /** A fleet of yours lying here, or null: storage is only reachable from one (0070). */
  fleet: FleetView | null
  view: ForgeView
  /** The product whose tray stands open. The page owns it: one tray at a time, moves and recipes alike. */
  open: string | null
  onOpen: (product: string) => void
  onClose: () => void
}) {
  const t = useT()
  const [tier, setTier] = useState<number | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)
  // A recipe names its goods by CODE and serves no class: the premium class (0294) is read off the
  // served catalogue by that code, the lookup every other list makes for a name and a category.
  const goodByCode = useWorld((s) => s.goodByCode)

  const forge = (recipe: ForgeRecipe) => {
    if (!fleet || sending) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdForgeGood(portId, recipe.product_id, 1)
      setSending(false)
      if (r.ok) {
        onClose()
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  const groups = groupsByTier(view.recipes)
  const shown = groups.find(([group]) => group === tier) ?? groups[0]
  // Read off the fresh answer, never a kept object: the have/need figures follow the world's re-read.
  const open = view.recipes.find((r) => r.product === openProduct) ?? null
  const short = open ? shortfall(open) : null

  return (
    <div data-testid="port-forge">
      {!fleet && (
        <Note tone="warning" className="mb-3">
          {t('city.forgeNoFleet')}
        </Note>
      )}

      {groups.length === 0 && <Note tone="neutral">{t('city.forgeNone')}</Note>}

      {shown && (
        <>
          <Segmented<string>
            fill
            className="mb-3"
            label={t('city.recipes')}
            segments={groups.map(([group]) => ({ id: String(group), label: t('city.forgeTier', { n: formatInt(group) }) }))}
            value={String(shown[0])}
            onChange={(id) => setTier(Number(id))}
          />
          <div data-testid={`forge-tier-${shown[0]}`}>
            {[...shown[1]]
              .sort((a, b) => Number(b.can_forge) - Number(a.can_forge))
              .map((recipe, i) => (
                <Row
                  key={recipe.product}
                  {...goodClassRow(goodByCode[recipe.product]?.class)}
                  // THE CONTROL CARRIES THE PRODUCT'S NAME (1-2 plain words), never the whole recipe (audit row 39): the ingredients are
                  // listed in the tray this row opens, and the tray's title is the product's name.
                  label={
                    <span className="flex min-w-0 items-center gap-x-1.5">
                      <Clip className="text-t-body">{recipe.name}</Clip>
                      {goodByCode[recipe.product]?.class != null && <GoodKind goodClass={goodByCode[recipe.product]?.class} classWord={false} />}
                    </span>
                  }
                  tone={recipe.can_forge ? 'default' : 'muted'}
                  chevron
                  hairline={i < shown[1].length - 1}
                  onClick={() => {
                    setRefusal(null)
                    setDetent('half')
                    onOpen(recipe.product)
                  }}
                  data-testid={`forge-product-${recipe.product}`}
                />
              ))}
          </div>
        </>
      )}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
          title={open.name}
          data-testid="forge-tray"
          action={
            fleet !== null ? (
              <Button
                variant="primary"
                className="w-full"
                disabled={!open.can_forge}
                busy={sending}
                busyLabel={t('city.forgeMaking')}
                onClick={() => forge(open)}
                data-testid={`forge-make-${open.product}`}
              >
                {t('city.forgeMake', { name: open.name })}
              </Button>
            ) : undefined
          }
        >
          {goodByCode[open.product]?.class != null && (
            <Row label={t('codex.class')} value={<GoodClassMark goodClass={goodByCode[open.product]?.class} withWord />} data-testid="forge-class-row" />
          )}
          {open.ingredients.map((i, idx) => (
            <Row
              key={i.good}
              {...goodClassRow(goodByCode[i.good]?.class)}
              label={<>{i.name} <GoodKind compact goodClass={goodByCode[i.good]?.class} /></>}
              value={
                <Figure
                  value={formatInt(i.have)}
                  unit={tNow('city.forgeOf', { n: formatInt(i.qty) })}
                  tone={i.have < i.qty ? 'warning' : 'ink'}
                />
              }
              hairline={idx < open.ingredients.length - 1}
            />
          ))}
          {short !== null && <Note tone="warning">{t('yard.missing', { list: short })}</Note>}
          {refusal && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </div>
  )
}
