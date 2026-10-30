import { useState } from 'react'
import {
  Button,
  Figure,
  Icon,
  Note,
  Row,
  SheetSection,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../components/ui'
import { useForge } from './useForge'
import { useWorld } from './worldStore'
import { formatInt } from '../lib/format'
import { cmdForgeGood, type FleetView, type ForgeRecipe, type Refusal } from '../lib/rpc'
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
// ── THE LIST SCROLLS INSIDE THE SHEET ─────────────────────────────────────────────────────────
// The City page's own law (CityFace.tsx): the document never scrolls; a long list is read inside
// the full-screen Sheet. There are 287 recipes, grouped by the product's tier, and the sheet is
// what scrolls — never the page behind it.

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
}: {
  portId: string
  /** A fleet of yours lying here, or null — storage is only reachable from one (0070). */
  fleet: FleetView | null
}) {
  const t = useT()
  const { view, loading } = useForge(portId)
  const [open, setOpen] = useState<ForgeRecipe | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)

  const forge = (recipe: ForgeRecipe) => {
    if (!fleet || sending) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdForgeGood(portId, recipe.product_id, 1)
      setSending(false)
      if (r.ok) {
        setOpen(null)
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  if (loading && !view) return <Note tone="neutral">{t('city.forgeLoading')}</Note>
  if (!view) return <Note tone="neutral">{t('city.forgeNone')}</Note>

  const short = open ? shortfall(open) : null

  return (
    <div data-testid="port-forge">
      {!fleet && (
        <Note tone="warning" className="mb-3">
          {t('city.forgeNoFleet')}
        </Note>
      )}

      {view.recipes.length === 0 && <Note tone="neutral">{t('city.forgeNone')}</Note>}

      {groupsByTier(view.recipes).map(([tier, recipes]) => (
        <SheetSection key={tier} heading={t('city.forgeTier', { n: formatInt(tier) })} data-testid={`forge-tier-${tier}`}>
          <TileField>
            {recipes.map((recipe) => (
              <Tile
                key={recipe.product}
                mark={<Icon name="mallet" size={20} />}
                name={recipe.name}
                meta={recipe.ingredients.map((i) => i.name).join(' · ')}
                state={recipe.can_forge ? 'rest' : 'muted'}
                tap="whole"
                onClick={() => {
                  setRefusal(null)
                  setDetent('half')
                  setOpen(recipe)
                }}
                data-testid={`forge-product-${recipe.product}`}
              />
            ))}
          </TileField>
        </SheetSection>
      ))}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
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
          {open.ingredients.map((i, idx) => (
            <Row
              key={i.good}
              label={i.name}
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
