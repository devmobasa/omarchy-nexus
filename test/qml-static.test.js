// Static QML checks for the failure class qmllint does not catch at exit
// level: a JS model qualifier used without its import (a runtime
// ReferenceError), and a root-level property set twice (a scene-load
// failure that takes the whole panel down). Both bit the ui/ split once.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const root = path.resolve(__dirname, '..')
const files = []
for (const dir of ['.', 'ui', 'state']) {
  for (const name of fs.readdirSync(path.join(root, dir))) {
    if (name.endsWith('.qml')) files.push(path.join(dir, name))
  }
}
assert.ok(files.length >= 3, 'the QML inventory is discoverable')

for (const relative of files) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8')

  const imports = new Set()
  for (const match of source.matchAll(/import\s+"[^"]+"\s+as\s+(\w+)/g)) {
    imports.add(match[1])
  }
  for (const match of source.matchAll(/\b(Nexus[A-Z]\w*Model|NexusModel|NexusSettingsRows)\b(?=\.)/g)) {
    assert.ok(imports.has(match[1]),
      `${relative} uses ${match[1]} without importing it`)
  }

  const rootLevelKeys = {}
  const lines = source.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^    ([a-zA-Z][\w.]*):/)
    if (!match || lines[i].trim().startsWith('//')) continue
    const key = match[1]
    if (key === 'anchors') continue
    assert.equal(rootLevelKeys[key], undefined,
      `${relative} sets root-level '${key}' twice (lines ${rootLevelKeys[key]} and ${i + 1})`)
    rootLevelKeys[key] = i + 1
  }
}

console.log('ok - nexus qml static checks')
