// Lists every English dictionary key that has no Korean entry (docs/KOREAN_LATER.md).
//   node scripts/i18n-missing-korean.mjs          one `section.key  English text` line per gap, then a count
//   node scripts/i18n-missing-korean.mjs --count  the count only
import { createServer } from 'vite'

const server = await createServer({ server: { middlewareMode: true }, appType: 'custom', logLevel: 'silent' })
try {
  const { DICT } = await server.ssrLoadModule('/src/lib/i18n/index.ts')
  const gaps = []
  for (const [section, d] of Object.entries(DICT))
    for (const [key, msg] of Object.entries(d.en))
      if (!(key in d.ko)) gaps.push([`${section}.${key}`, typeof msg === 'string' ? msg : msg.other])
  if (!process.argv.includes('--count')) for (const [id, text] of gaps) console.log(`${id}  ${text}`)
  console.log(`${gaps.length} English keys have no Korean entry`)
} finally {
  await server.close()
}
