'use strict';

const assert = require('node:assert/strict');
const { describe, it } = require('node:test');
const { pathToFileURL } = require('node:url');
const path = require('node:path');

const AvlTree = require('..');

describe('module loading', () => {
  it('exports the constructor through CommonJS', () => {
    assert.equal(typeof AvlTree, 'function');
    assert.equal(AvlTree.name, 'AvlTree');
  });

  it('exports the same constructor as an ESM default import', async () => {
    const entry = pathToFileURL(path.join(__dirname, '..', 'index.js'));
    const imported = await import(entry.href);

    assert.equal(imported.default, AvlTree);
  });
});

describe('public contract', () => {
  it('supports empty-tree operations', () => {
    const tree = new AvlTree();

    assert.equal(tree.find(1), null);
    assert.equal(tree.remove(1), null);
    assert.equal(tree.has(1), false);
    assert.equal(tree.dump(), '');
  });

  it('inserts, finds, replaces, checks, removes, and dumps values', () => {
    const tree = new AvlTree();

    assert.equal(tree.insert(2, 'two'), undefined);
    tree.insert(1, 'one');
    tree.insert(3, 'three');
    tree.insert(2, 'TWO');

    assert.equal(tree.find(2), 'TWO');
    assert.equal(tree.find(9), null);
    assert.equal(tree.has(1), true);
    assert.equal(tree.has(9), false);
    assert.equal(tree.dump(), [
      "{ key: 1, value: 'one' }",
      "{ key: 2, value: 'TWO' }",
      "{ key: 3, value: 'three' }",
    ].join(', '));
    assert.equal(tree.remove(2), 'TWO');
    assert.equal(tree.remove(2), null);
    assert.equal(
      tree.dump(),
      "{ key: 1, value: 'one' }, { key: 3, value: 'three' }"
    );
  });

  it('keeps instances independent', () => {
    const first = new AvlTree();
    const second = new AvlTree();

    first.insert(1, 'first');
    second.insert(1, 'second');

    assert.equal(first.find(1), 'first');
    assert.equal(second.find(1), 'second');
  });

  it('returns copied JavaScript strings that survive later mutations', () => {
    const tree = new AvlTree();
    tree.insert(1, 'original');

    const found = tree.find(1);
    tree.insert(1, 'replacement');
    tree.remove(1);

    assert.equal(found, 'original');
  });

  it('supports the signed 32-bit boundaries', () => {
    const tree = new AvlTree();
    tree.insert(-2147483648, 'minimum');
    tree.insert(2147483647, 'maximum');

    assert.equal(tree.find(-2147483648), 'minimum');
    assert.equal(tree.find(2147483647), 'maximum');
    assert.equal(
      tree.dump(),
      "{ key: -2147483648, value: 'minimum' }, { key: 2147483647, value: 'maximum' }"
    );
  });

  it('preserves the legacy debug format for ambiguous string contents', () => {
    const tree = new AvlTree();
    tree.insert(1, "quotes: ' and \"");
    tree.insert(2, 'commas, braces { }');
    tree.insert(3, 'Привіт 🌳');
    tree.insert(4, '');

    assert.equal(
      tree.dump(),
      "{ key: 1, value: 'quotes: ' and \"' }, { key: 2, value: 'commas, braces { }' }, { key: 3, value: 'Привіт 🌳' }, { key: 4, value: '' }"
    );
  });
});

describe('observed NAPI input conversion', () => {
  it('converts JavaScript numbers with Node-API int32 semantics', () => {
    const cases = [
      [1.9, 1],
      [-1.9, -1],
      [NaN, 0],
      [Infinity, 0],
      [-Infinity, 0],
      [2147483648, -2147483648],
      [-2147483649, 2147483647],
    ];

    for (const [input, converted] of cases) {
      const tree = new AvlTree();
      tree.insert(input, 'value');
      assert.equal(tree.find(converted), 'value');
    }
  });

  it('rejects non-number keys', () => {
    const tree = new AvlTree();

    assert.throws(
      () => tree.insert('1', 'value'),
      (error) =>
        error.code === 'NumberExpected' &&
        error.message.includes('rust type `i32`')
    );
  });

  it('rejects non-string values', () => {
    for (const value of [123, null, undefined, {}, true]) {
      const tree = new AvlTree();
      assert.throws(
        () => tree.insert(1, value),
        (error) => error.code === 'StringExpected'
      );
    }
  });

  it('rejects missing required arguments and ignores extra arguments', () => {
    const tree = new AvlTree();

    assert.throws(() => tree.insert(), { code: 'NumberExpected' });
    assert.throws(() => tree.insert(1), { code: 'StringExpected' });
    assert.throws(() => tree.find(), { code: 'NumberExpected' });
    assert.throws(() => tree.remove(), { code: 'NumberExpected' });
    assert.throws(() => tree.has(), { code: 'NumberExpected' });

    assert.equal(tree.insert(1, 'one', 'ignored'), undefined);
    assert.equal(tree.find(1, 'ignored'), 'one');
    assert.equal(tree.remove(1, 'ignored'), 'one');
  });
});
