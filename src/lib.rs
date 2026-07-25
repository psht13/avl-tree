#![deny(unsafe_code)]

pub mod tree;

use tree::Tree;

#[cfg(not(test))]
use napi_derive::napi;

/// A Node.js AVL tree with signed 32-bit integer keys and string values.
#[cfg_attr(not(test), napi)]
#[cfg_attr(test, allow(dead_code))]
pub struct AVLTree {
    tree: Tree,
}

#[cfg(not(test))]
#[napi]
impl AVLTree {
    /// Creates an empty tree in constant time.
    #[napi(constructor)]
    pub fn new() -> Self {
        Self { tree: Tree::new() }
    }

    /// Inserts a key/value pair, replacing the value when the key already exists.
    ///
    /// Runs in `O(log n)` time.
    #[napi]
    pub fn insert(&mut self, key: i32, value: String) {
        self.tree.insert(key, value);
    }

    /// Returns the value for `key`, or `null` in JavaScript when absent.
    ///
    /// Runs in `O(log n)` time.
    #[napi]
    pub fn find(&self, key: i32) -> Option<&str> {
        self.tree.find(key)
    }

    /// Removes `key` and returns its value, or `null` in JavaScript when absent.
    ///
    /// Runs in `O(log n)` time.
    #[napi]
    pub fn remove(&mut self, key: i32) -> Option<String> {
        self.tree.remove(key)
    }

    /// Reports whether `key` exists in `O(log n)` time.
    #[napi]
    pub fn has(&self, key: i32) -> bool {
        self.tree.has(key)
    }

    /// Returns the legacy in-order debug representation in `O(n)` time.
    #[napi]
    pub fn dump(&self) -> String {
        self.tree.dump()
    }
}

#[cfg(not(test))]
impl Default for AVLTree {
    fn default() -> Self {
        Self::new()
    }
}
