// Import the necessary macros and types.
#[macro_use]
extern crate napi_derive;

use napi::bindgen_prelude::Either;
use std::cmp::Ordering;

/// A Node.js–exposed AVL tree that supports number or string keys and values.
///
/// The AVL tree is a self-balancing binary search tree that supports insertion,
/// bulk insertion, search by key, removal by key, and dumping the tree contents (in-order traversal).
#[napi]
pub struct AVLTree {
  root: Option<Box<Node>>,
}

#[napi]
impl AVLTree {
  /// Creates a new, empty AVL tree.
  ///
  ///
  /// # Returns
  ///
  /// A new instance of AVLTree with no nodes.
  ///
  ///
  #[napi(constructor)]
  pub fn new() -> Self {
    Self { root: None }
  }

  /// Inserts a single node with the specified key and value into the AVL tree.
  ///
  ///
  /// If a node with the same key already exists, its value is updated to the provided value.
  ///
  ///
  /// # Parameters
  ///
  /// - key: A number or a string that represents the key.
  /// - value: A number or a string that represents the value.
  ///
  ///
  /// # Example (TypeScript)
  ///
  ///
  /// ```ts
  /// const tree = new AvlTree();
  /// tree.insert(42, "The answer");
  /// ```
  ///
  ///
  #[napi]
  pub fn insert(&mut self, key: Either<i32, String>, value: Either<i32, String>) {
    // Convert the Either values into our internal KeyValue type.
    let key: KeyValue = key.into();
    let value: KeyValue = value.into();
    self.root = Self::insert_node(self.root.take(), key, value);
  }

  /// Inserts multiple nodes at once into the AVL tree.
  ///
  ///
  /// Accepts an array of objects where each object has a key and value property.
  /// This is useful for bulk insertion.
  ///
  ///
  /// # Parameters
  ///
  /// - nodes: An array of key/value pairs, where each pair is represented by an object
  ///            with properties key and value. Each key and value can be a number or a string.
  ///
  ///
  /// # Example (TypeScript)
  ///
  ///
  /// ```ts
  /// tree.bulkInsert([
  ///   { key: 10, value: "ten" },
  ///   { key: 20, value: "twenty" }
  /// ]);
  /// ```
  ///
  ///
  #[napi]
  pub fn bulk_insert(&mut self, nodes: Vec<NodeEntry>) {
    for node in nodes {
      self.insert(node.key, node.value);
    }
  }

  /// Searches for a node in the AVL tree by its key.
  ///
  ///
  /// If a node with the specified key exists, returns its associated value.
  /// Otherwise, returns null.
  ///
  ///
  /// # Parameters
  ///
  /// - key: The key to search for (number or string).
  ///
  ///
  /// # Returns
  ///
  /// The value associated with the key if found, or null if no such node exists.
  ///
  ///
  /// # Example (TypeScript)
  ///
  ///
  /// ```ts
  /// const value = tree.search("myKey");
  /// if (value !== null) {
  ///   console.log("Found:", value);
  /// } else {
  ///   console.log("Not found");
  /// }
  /// ```
  ///
  ///
  #[napi]
  pub fn search(&self, key: Either<i32, String>) -> Option<Either<i32, String>> {
    let key: KeyValue = key.into();
    Self::search_node(&self.root, &key).map(|val| match val {
      KeyValue::Number(n) => Either::A(n),
      KeyValue::String(s) => Either::B(s),
    })
  }

  /// Returns a string representing all nodes in the AVL tree using in-order traversal.
  ///
  ///
  /// The returned string lists the nodes in sorted order by key. Each node is represented
  /// by its key and value.
  ///
  ///
  /// # Returns
  ///
  /// A string that contains the representation of all nodes in the tree.
  ///
  ///
  /// # Example (TypeScript)
  ///
  ///
  /// ```ts
  /// console.log(tree.dump());
  /// // Might output: "{ key: 5, value: 'five' }, { key: 10, value: 'ten' }, { key: 15, value: 'fifteen' }"
  /// ```
  ///
  ///
  #[napi]
  pub fn dump(&self) -> String {
    let mut entries = Vec::new();
    Self::traverse_in_order(&self.root, &mut entries);
    entries.join(", ")
  }

  /// Removes a node from the AVL tree by its key.
  ///
  ///
  /// If a node with the specified key exists, it is removed from the tree and its associated
  /// value is returned. If no such node exists, null is returned.
  ///
  ///
  /// # Parameters
  ///
  /// - key: A number or a string that represents the key of the node to be removed.
  ///
  ///
  /// # Returns
  ///
  /// The value associated with the removed node if removal was successful, or null otherwise.
  ///
  ///
  /// # Example (TypeScript)
  ///
  ///
  /// ```ts
  /// const removedValue = tree.remove(42);
  /// if (removedValue !== null) {
  ///   console.log("Removed:", removedValue);
  /// } else {
  ///   console.log("Key not found");
  /// }
  /// ```
  ///
  ///
  #[napi]
  pub fn remove(&mut self, key: Either<i32, String>) -> Option<Either<i32, String>> {
    let key: KeyValue = key.into();
    let (new_root, removed) = Self::remove_node(self.root.take(), &key);
    self.root = new_root;
    removed.map(|val| match val {
      KeyValue::Number(n) => Either::A(n),
      KeyValue::String(s) => Either::B(s),
    })
  }

  // --- Internal AVL tree functions ---

  // Recursive insertion function.
  fn insert_node(
    node: Option<Box<Node>>,
    key: KeyValue,
    value: KeyValue,
  ) -> Option<Box<Node>> {
    if let Some(mut n) = node {
      match key.cmp(&n.key) {
        Ordering::Less => {
          n.left = Self::insert_node(n.left.take(), key, value);
        }
        Ordering::Greater => {
          n.right = Self::insert_node(n.right.take(), key, value);
        }
        Ordering::Equal => {
          // If the key exists, update its value (hash table–like behavior).
          n.value = value;
          return Some(n);
        }
      }
      n.update_height();
      Some(Self::balance(n))
    } else {
      Some(Box::new(Node::new(key, value)))
    }
  }

  // Recursive search function.
  fn search_node(node: &Option<Box<Node>>, key: &KeyValue) -> Option<KeyValue> {
    if let Some(n) = node {
      match key.cmp(&n.key) {
        Ordering::Less => Self::search_node(&n.left, key),
        Ordering::Greater => Self::search_node(&n.right, key),
        Ordering::Equal => Some(n.value.clone()),
      }
    } else {
      None
    }
  }

  // Balances a subtree rooted at the given node.
  fn balance(mut node: Box<Node>) -> Box<Node> {
    let balance_factor = node.balance_factor();

    if balance_factor > 1 {
      if node.left.as_ref().unwrap().balance_factor() < 0 {
        node.left = Some(Self::rotate_left(node.left.take().unwrap()));
      }
      Self::rotate_right(node)
    } else if balance_factor < -1 {
      if node.right.as_ref().unwrap().balance_factor() > 0 {
        node.right = Some(Self::rotate_right(node.right.take().unwrap()));
      }
      Self::rotate_left(node)
    } else {
      node
    }
  }

  // Performs a right rotation.
  fn rotate_right(mut y: Box<Node>) -> Box<Node> {
    let mut x = y.left.take().unwrap();
    y.left = x.right.take();
    y.update_height();
    x.right = Some(y);
    x.update_height();
    x
  }

  // Performs a left rotation.
  fn rotate_left(mut x: Box<Node>) -> Box<Node> {
    let mut y = x.right.take().unwrap();
    x.right = y.left.take();
    x.update_height();
    y.left = Some(x);
    y.update_height();
    y
  }

  // Recursive in-order traversal helper.
  fn traverse_in_order(node: &Option<Box<Node>>, entries: &mut Vec<String>) {
    if let Some(n) = node {
      Self::traverse_in_order(&n.left, entries);
      entries.push(format!("{{ key: {:?}, value: {:?} }}", n.key, n.value));
      Self::traverse_in_order(&n.right, entries);
    }
  }

  // Recursive removal function.
  // Returns a tuple containing the new subtree root and an Option with the removed value.
  fn remove_node(
    node: Option<Box<Node>>,
    key: &KeyValue,
  ) -> (Option<Box<Node>>, Option<KeyValue>) {
    if let Some(mut n) = node {
      let removed = match key.cmp(&n.key) {
        Ordering::Less => {
          let (new_left, rem) = Self::remove_node(n.left.take(), key);
          n.left = new_left;
          rem
        }
        Ordering::Greater => {
          let (new_right, rem) = Self::remove_node(n.right.take(), key);
          n.right = new_right;
          rem
        }
        Ordering::Equal => {
          let removed_value = Some(n.value.clone());
          // Node with only one child or no child.
          if n.left.is_none() {
            return (n.right.take(), removed_value);
          } else if n.right.is_none() {
            return (n.left.take(), removed_value);
          } else {
            // Node with two children:
            // Get the in-order successor (smallest in the right subtree).
            let (new_right, min_node) = Self::remove_min(n.right.take().unwrap());
            n.right = new_right;
            n.key = min_node.key;
            n.value = min_node.value;
            removed_value
          }
        }
      };
      n.update_height();
      (Some(Self::balance(n)), removed)
    } else {
      (None, None)
    }
  }

  // Helper function to remove the smallest node in the subtree.
  // Returns a tuple of the new subtree root and the removed minimum node.
  fn remove_min(mut node: Box<Node>) -> (Option<Box<Node>>, Box<Node>) {
    if node.left.is_none() {
      return (node.right.take(), node);
    } else {
      let (new_left, min_node) = Self::remove_min(node.left.take().unwrap());
      node.left = new_left;
      node.update_height();
      (Some(Self::balance(node)), min_node)
    }
  }
}

/// A single node in the AVL tree.
struct Node {
  key: KeyValue,
  value: KeyValue,
  height: i32,
  left: Option<Box<Node>>,
  right: Option<Box<Node>>,
}

impl Node {
  /// Creates a new node with the specified key and value.
  ///
  ///
  /// # Parameters
  ///
  /// - key: The key for the node.
  /// - value: The value for the node.
  ///
  ///
  fn new(key: KeyValue, value: KeyValue) -> Self {
    Self {
      key,
      value,
      height: 1,
      left: None,
      right: None,
    }
  }

  /// Returns the height of a node, or 0 if the node is None.
  ///
  ///
  fn height(node: &Option<Box<Node>>) -> i32 {
    node.as_ref().map_or(0, |n| n.height)
  }

  /// Updates this node's height based on the heights of its children.
  ///
  ///
  fn update_height(&mut self) {
    self.height = 1 + i32::max(Self::height(&self.left), Self::height(&self.right));
  }

  /// Computes the balance factor of the node (left height minus right height).
  ///
  ///
  fn balance_factor(&self) -> i32 {
    Self::height(&self.left) - Self::height(&self.right)
  }
}

/// The internal representation for keys and values in our tree.
///
/// Both keys and values can be either a number or a string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyValue {
  Number(i32),
  String(String),
}

// Implement ordering for KeyValue so that the tree can compare keys.
impl PartialOrd for KeyValue {
  fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
    Some(self.cmp(other))
  }
}

impl Ord for KeyValue {
  fn cmp(&self, other: &Self) -> Ordering {
    match (self, other) {
      (KeyValue::Number(a), KeyValue::Number(b)) => a.cmp(b),
      (KeyValue::String(a), KeyValue::String(b)) => a.cmp(b),
      // Define an arbitrary ordering between numbers and strings:
      (KeyValue::Number(_), KeyValue::String(_)) => Ordering::Less,
      (KeyValue::String(_), KeyValue::Number(_)) => Ordering::Greater,
    }
  }
}

// Allow converting from Either<i32, String> (which napi understands) into KeyValue.
impl From<Either<i32, String>> for KeyValue {
  fn from(e: Either<i32, String>) -> Self {
    match e {
      Either::A(n) => KeyValue::Number(n),
      Either::B(s) => KeyValue::String(s),
    }
  }
}

/// A helper struct to represent a key/value pair for bulk insertion.
///
/// This struct is annotated with #[napi(object)] so that you can pass an array
/// of such objects from Node.js.
#[napi(object)]
pub struct NodeEntry {
  /// The key for the node, as a number or string.
  pub key: Either<i32, String>,
  /// The value for the node, as a number or string.
  pub value: Either<i32, String>,
}
