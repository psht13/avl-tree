# avl-tree-rust

**avl-tree-rust** is a high-performance native AVL tree library for Node.js. Written in Rust and exposed through N-API, this library offers efficient self-balancing tree operations such as insertion, removal, search, and in-order traversal. It supports both numbers and strings as keys and values, and even provides bulk insertion for added convenience.

> **Note:** This library is designed for Node.js environments only and has not been tested in browsers.

## Features

- **Native Performance:** Leverages Rust’s speed for fast tree operations.
- **Self-Balancing:** Automatically rebalances to guarantee efficient operations.
- **Flexible Data Types:** Supports keys and values as either numbers or strings.
- **Bulk Insertion:** Insert multiple key/value pairs in a single call.
- **In-Order Traversal:** Retrieve a sorted string representation of the tree contents.
- **Removal:** Remove nodes by key while preserving AVL balance.

## Prerequisites

- [Node.js](https://nodejs.org/) (v12 or higher recommended)

## Installation

Install via npm:

```bash
npm install avl-tree-rust
```

## Usage Example

Below is a simple example demonstrating how to use **avl-tree-rust** in your Node.js project:

```js
// Import the AVL tree class from the package
import AvlTree from 'avl-tree-rust';

// Create a new AVL tree instance
const tree = new AvlTree();

// Insert nodes individually
tree.insert(10, 'ten');
tree.insert(5, 'five');
tree.insert(15, 'fifteen');

// Bulk insert nodes
tree.bulkInsert([
  { key: 7, value: 'seven' },
  { key: 12, value: 'twelve' },
]);

// Search for a node by key
const result = tree.search(10);
if (result !== null) {
  console.log('Found:', result);
} else {
  console.log('Not found');
}

// Remove a node by key
const removed = tree.remove(5);
if (removed !== null) {
  console.log('Removed:', removed);
} else {
  console.log('Key not found for removal');
}

// Dump the tree (in-order traversal)
console.log('Tree dump:', tree.dump());
// Example output:
// "{ key: Number(7), value: String("seven") }, { key: Number(10), value: String("ten") }, { key: Number(12), value: String("twelve") }, { key: Number(15), value: String("fifteen") }"
```

## API Reference

### `new()`

**Constructor**  
Creates a new, empty AVL tree.

---

### `insert(key, value)`

**Inserts a single node with the specified key and value.**

#### Parameters:

- `key`: A number or a string representing the key.
- `value`: A number or a string representing the value.

If a node with the same key already exists, its value is updated.

---

### `bulkInsert(nodes)`

**Inserts multiple nodes at once.**

#### Parameters:

- `nodes`: An array of objects where each object has a `key` and `value` property (both can be numbers or strings).

---

### `search(key)`

**Searches for a node by its key and returns the associated value if found; otherwise, returns `null`.**

#### Parameters:

- `key`: A number or string to search for.

---

### `remove(key)`

**Removes a node from the tree by its key and returns its associated value.**

#### Parameters:

- `key`: A number or a string representing the key of the node to be removed.

If the node exists, it is removed and its value is returned; if not, `null` is returned.

---

### `dump()`

**Returns a string representing all nodes in the tree (via in-order traversal), displaying nodes sorted by key.**

---

## License

MIT License

## Author

Pavlo Yurchenko  
[pashtet.gm@gmail.com](mailto:pashtet.gm@gmail.com)

---
