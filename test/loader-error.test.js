'use strict';

const assert = require('node:assert/strict');
const { copyFileSync, mkdtempSync, rmSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { it } = require('node:test');

it('reports the detected platform when no native artifact is available', () => {
  const fixture = mkdtempSync(path.join(os.tmpdir(), 'avl-tree-loader-'));

  try {
    copyFileSync(
      path.join(__dirname, '..', 'index.js'),
      path.join(fixture, 'index.js')
    );
    copyFileSync(
      path.join(__dirname, '..', 'native.js'),
      path.join(fixture, 'native.js')
    );

    const result = spawnSync(
      process.execPath,
      ['-e', `require(${JSON.stringify(path.join(fixture, 'index.js'))})`],
      { encoding: 'utf8' }
    );

    assert.notEqual(result.status, 0);
    assert.match(
      result.stderr,
      new RegExp(
        `Cannot find native binding for ${process.platform}/${process.arch}`
      )
    );
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});
