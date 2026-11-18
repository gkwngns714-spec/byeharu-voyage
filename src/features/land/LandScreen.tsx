import { useState } from 'react'
import { Note, Segmented, Sheet, Skeleton } from '../../components/ui'
import { worldLand, type LandView } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { levelName } from '../../live/levelWords'
import { tabWord } from '../../app/navTabs'
import { useLocale, useT } from '../../lib/i18n'
import { PartyFace } from './PartyFace'
import { SkillFace } from './SkillFace'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LAND TAB (0455; docs/design/land-2026-11.md 6.7; the owner, 2026-11-16: "sending expeditions to land site (mountains), for
// minerals like rs3" ... "this will be a proper MMORPG game, meaning it will be shared with other people - same timeline").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ONE READ, NO SUM. Everything here is `world.land(skill)`: the party and where it is (public.land_progress at the read's instant), the
// skill's level, its jobs as public.land_terms judges each now (open or short, home or far, the passage, a turn, the trip), the home
// Storage, the tools, who else is on the land. No time, haul, level or price is worked out here; the countdown is drawn from the
// served instant, as an arrival's is.
//
// TWO FACES, one strip that wraps (never scrolls sideways): Party (the screen looked at most) and one face a skill (Mining). A new
// skill is a new face from the same SkillFace: it draws whatever jobs the server serves.
//
// THE PRESS LAW: a press never moves the page. Send opens the kit's Tray over the page; Collect and Call home are buttons whose
// place does not change; a refusal is a Note in a place that is always there.
//
// DARK (land_enabled false): the bar has no Land cell; a typed /land prints "Not open yet." and nothing else.

type Face = 'party' | 'mining'

export function LandScreen() {
  const t = useT()
  const locale = useLocale()
  const title = tabWord(locale, '/land')
  const [face, setFace] = useState<Face>('party')
  const read = useServedRead<LandView>('land:mining', () => worldLand('mining'), { name: 'worldLand' })
  const v = read.view
  return (
    <Sheet
      title={title}
      layout="page"
      data-testid="land"
      trailing={
        v && v.enabled && v.company ? (
          <Segmented<Face>
            segments={[
              { id: 'party', label: t('land.party') },
              { id: 'mining', label: levelName(locale, 'mining', 'Mining') },
            ]}
            value={face}
            onChange={setFace}
            label={t('land.faces')}
            columns={2}
          />
        ) : undefined
      }
    >
      {!v ? (
        read.loading ? (
          <Skeleton className="h-[240px] w-full" />
        ) : (
          <Note tone="danger">{t('land.failed')}</Note>
        )
      ) : !v.enabled ? (
        <Note tone="neutral" data-testid="land-dark">
          {t('land.dark')}
        </Note>
      ) : !v.company ? (
        <Note tone="neutral">{t('land.noCompany')}</Note>
      ) : face === 'party' ? (
        <PartyFace v={v} />
      ) : (
        <SkillFace v={v} />
      )}
    </Sheet>
  )
}
