import { useState } from 'react'
import {
  Button,
  Figure,
  GoodClassMark,
  GoodKind,
  Icon,
  Note,
  Row,
  SheetSection,
  Tile,
  TileField,
  Tray,
  goodClassRow,
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

/** One group per product tier, in the served order — `forgeGroups.ts`'s one fold, shared with the
 *  City page's compact Forge screen (its tier rows carry these same counts). */
import { groupsByTier } from './forgeGroups'

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
  tier,
}: {
  portId: string
  /** A fleet of yours lying here, or null — storage is only reachable from one (0070). */
  fleet: FleetView | null
  /** ONE tier's products only, when the City page's tier row opened this face (CityFace.tsx).
   *  Absent: every tier, as the desk's own caller composes it. */
  tier?: number
}) {
  const t = useT()
  const { view, loading } = useForge(portId)
  const [open, setOpen] = useState<ForgeRecipe | null>(null)
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

      {groupsByTier(view.recipes)
        .filter(([group]) => tier === undefined || group === tier)
        .map(([group, recipes]) => (
        <SheetSection key={group} heading={t('city.forgeTier', { n: formatInt(group) })} data-testid={`forge-tier-${group}`}>
          <TileField>
            {recipes.map((recipe) => (
              <Tile
                key={recipe.product}
                {...goodClassRow(goodByCode[recipe.product]?.class)}
                mark={<Icon name="mallet" size={20} />}
                // THE CONTROL CARRIES THE PRODUCT'S NAME (1-2 plain words), never the whole recipe
                // (audit row 39: "Adire Cloth Indigo · Potash · Raw Cotton"). The ingredients are
                // listed in the tray this tile opens, and the tray's title is the product's name.
                name={recipe.name}
                // the control's text is the product's NAME, never more (tests/city.audit.spec.ts: the tray must contain it):
                // the class is its meter alone, the word its accessible name and the first row of the tray this press opens
                meta={goodByCode[recipe.product]?.class != null ? <GoodKind goodClass={goodByCode[recipe.product]?.class} classWord={false} /> : undefined}
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
