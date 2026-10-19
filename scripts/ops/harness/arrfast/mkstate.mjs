// mkstate.mjs — .arrwork/state.json (the read-only prod export) → .arrwork/prod-state.json
import { readFileSync, writeFileSync } from 'node:fs'
const t = readFileSync('.arrwork/state.json', 'utf8')
const j = JSON.parse(t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1)).rows[0].j
writeFileSync('.arrwork/prod-state.json', JSON.stringify(j))
console.log(j.at, Object.keys(j))
