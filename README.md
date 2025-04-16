# avl-tree-rust

**avl-tree-rust** is a high-performance native AVL tree library for Node.js. Written in Rust and exposed through N-API, this library offers efficient self-balancing tree operations such as insertion, removal, search, and in-order traversal. It supports both numbers and strings as keys and values.

> **Note:** This library is designed for Node.js environments only and has not been tested in browsers.

## Features

- **Native Performance:** Leverages Rust's speed for fast tree operations.
- **Self-Balancing:** Automatically rebalances to guarantee efficient operations.
- **Flexible Data Types:** Supports keys and values as either numbers or strings.
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
const AvlTree = require('avl-tree-rust');
// OR using ES Modules
import AvlTree from 'avl-tree-rust';

// Create a new AVL tree instance
const tree = new AvlTree();

// Insert nodes
tree.insert(10, 'ten');
tree.insert(5, 'five');
tree.insert(15, 'fifteen');

// Check if a key exists
if (tree.has(10)) {
  console.log('Key 10 exists in the tree');
}

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
// "{ key: Number(10), value: String("ten") }, { key: Number(15), value: String("fifteen") }"
```

## License

MIT License

## Author

Pavlo Yurchenko  
[pashtet.gm@gmail.com](mailto:pashtet.gm@gmail.com)

---
