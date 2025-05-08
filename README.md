# avl-tree-rust

**avl-tree-rust** is a high-performance native AVL tree library for Node.js, written in Rust and exposed through N-API. This library offers efficient self-balancing tree operations such as insertion, removal, search, and in-order traversal. It supports keys and values as integers and strings, providing flexibility and fast performance.

> **Note:** This library is designed for Node.js environments only and has not been tested in browsers.

> **Platform Compatibility:** The library is primarily built and tested on Linux environments. While it should work on other platforms, compatibility is not guaranteed. If you encounter issues, you can try building from source using `npm run build`.

## Features

- **Native Performance:** Leverages Rust's speed for ultra-fast tree operations, ensuring high performance for large datasets.
- **Self-Balancing:** The AVL tree automatically rebalances after each insert and remove operation to guarantee logarithmic time complexity for lookups, insertions, and deletions.
- **Efficient Memory Management:** Data structures that minimize memory overhead and avoid unnecessary cloning of values.
- **Flexible Data Types:** Supports integer and string types for both keys and values.
- **In-Order Traversal:** Easily retrieve a sorted string representation of the tree contents with in-order traversal.
- **Removal:** Efficiently remove nodes by key while maintaining the AVL tree's balance.

## Prerequisites

To use **avl-tree-rust**, you need the following:

- [Node.js](https://nodejs.org/) (v12 or higher recommended)
- For building from source:

  - Rust toolchain
  - Build essentials (e.g., `build-essential` package on Ubuntu/Debian)

## Installation

To install the library via npm:

```bash
npm install avl-tree-rust
```

If you need to build from source, follow these steps:

```bash
git clone https://github.com/psht13/avl-tree.git
cd avl-tree
npm install
npm run build
```

## Usage Example

Here’s an example demonstrating how to use **avl-tree-rust** in your Node.js project:

```js
// Import the AVL tree class from the package
const AvlTree = require('avl-tree-rust');
// OR using ES Modules
import AvlTree from 'avl-tree-rust';

// Create a new AVL tree instance
const tree = new AvlTree();

// Insert nodes with keys and values
tree.insert(10, 'ten');
tree.insert(5, 'five');
tree.insert(15, 'fifteen');

// Check if a key exists in the tree
if (tree.has(10)) {
  console.log('Key 10 exists in the tree');
}

// Search for a node by its key
const result = tree.find(10);
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

// Dump the tree (in-order traversal) to view all nodes
console.log('Tree dump:', tree.dump());
// Example output:
// "{ key: 10, value: 'ten' }, { key: 15, value: 'fifteen' }"
```

## API Documentation

- **`insert(key: i32, value: String)`**: Inserts a node with the given key and value. If a node with the same key exists, its value is updated.
- **`find(key: i32)`**: Searches for a node by its key. Returns the value if found, or `null` if the key does not exist in the tree.
- **`remove(key: i32)`**: Removes a node by its key. Returns the value of the removed node if successful, or `null` if the key does not exist.
- **`has(key: i32)`**: Checks if a node with the given key exists in the tree. Returns `true` if the key is present, `false` otherwise.
- **`dump()`**: Returns a string representation of all nodes in the tree, sorted by key. This is done using in-order traversal.

## Performance Considerations

The AVL tree implementation for:

- **Fast Lookups**: Search, insert, and remove operations all have logarithmic time complexity due to the self-balancing property of the AVL tree.
- **Efficient Memory Usage**: The tree structure minimizes unnecessary memory allocations, and cloning of values is avoided to ensure good performance.

## License

MIT License

## Author

Pavlo Yurchenko
[pashtet.gm@gmail.com](mailto:pashtet.gm@gmail.com)
