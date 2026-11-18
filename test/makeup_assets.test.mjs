import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, statSync} from 'node:fs';
import {resolve, dirname, relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const assets = resolve(root, 'android/app/src/main/assets/makeup');

test('bundled makeup page resolves its entire local JavaScript import graph', () => {
  const html = readFileSync(resolve(assets, 'index.html'), 'utf8');
  const imports = JSON.parse(html.match(/<script type="importmap">\s*([\s\S]*?)<\/script>/)[1]).imports;
  const visited = new Set();
  function checkModule(file) {
    if (visited.has(file)) return;
    assert.ok(relative(assets, file) && !relative(assets, file).startsWith('..'));
    assert.ok(statSync(file).size > 0, `Missing or empty module: ${file}`);
    visited.add(file);
    const source = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\/|^\s*\/\/.*$/gm, '');
    const declarations = /\b(?:import\s*(?:\(\s*)?|export\s+)(?:[^'";]*?\bfrom\s*)?(['"])([^'"]+)\1/g;
    for (const [, , specifier] of source.matchAll(declarations)) {
      let target;
      if (specifier.startsWith('.')) target = resolve(dirname(file), specifier);
      else {
        const prefix = Object.keys(imports).find(key => key === specifier || key.endsWith('/') && specifier.startsWith(key));
        assert.ok(prefix, `Unmapped dependency: ${specifier}`);
        target = resolve(assets, imports[prefix] + specifier.slice(prefix.length));
      }
      checkModule(target);
    }
  }
  for (const [, src] of html.matchAll(/<script[^>]+src="([^"]+)"/g)) checkModule(resolve(assets, src));
  assert.ok(visited.has(resolve(assets, 'sdk/index.js')));
  assert.ok(visited.has(resolve(assets, 'three/build/three.module.js')));
  assert.ok(visited.has(resolve(assets, 'three/build/three.core.js')));
});

test('Git backup includes both bundled Three.js runtime modules', () => {
  for (const name of ['three.module.js', 'three.core.js']) {
    const file = `android/app/src/main/assets/makeup/three/build/${name}`;
    const result = spawnSync('git', ['check-ignore', '--no-index', '-q', file], {cwd: root, encoding: 'utf8'});
    assert.equal(result.status, 1, `${file} must remain eligible for Git backup: ${result.stderr}`);
  }
});
