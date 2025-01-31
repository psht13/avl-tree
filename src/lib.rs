// Import the necessary macros and types.
#[macro_use]
extern crate napi_derive;

use napi::bindgen_prelude::Either;
use std::cmp::Ordering;

/// A Node.js–exposed AVL tree.
#[napi]
pub struct AVLTree {
  root: Option<Box<Node>>,
}

#[napi]
impl AVLTree {
  /// Creates a new, empty AVL tree.
  #[napi(constructor)]
  pub fn new() -> Self {
    Self { root: None }
  }

  /// Inserts a single node given a key and value.
  ///
  /// If the key already exists, its associated value is updated.
  #[napi]
  pub fn insert(&mut self, key: Either<i32, String>, value: Either<i32, String>) {
    // Convert the Either values into our internal KeyValue type.
    let key: KeyValue = key.into();
    let value: KeyValue = value.into();
    self.root = Self::insert_node(self.root.take(), key, value);
  }

  /// Inserts multiple nodes at once.
  ///
  /// Accepts an array of key/value pairs.
  #[napi]
  pub fn bulk_insert(&mut self, nodes: Vec<KVPair>) {
    for node in nodes {
      self.insert(node.key, node.value);
    }
  }

  /// Searches for a node by its key.
  ///
  /// Returns the associated value if found; otherwise, returns `null`.
  #[napi]
  pub fn search(&self, key: Either<i32, String>) -> Option<Either<i32, String>> {
    let key: KeyValue = key.into();
    Self::search_node(&self.root, &key).map(|val| match val {
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
  /// Creates a new node with the given key and value.
  fn new(key: KeyValue, value: KeyValue) -> Self {
    Self {
      key,
      value,
      height: 1,
      left: None,
      right: None,
    }
  }

  /// Returns the height of a node (or 0 if `None`).
  fn height(node: &Option<Box<Node>>) -> i32 {
    node.as_ref().map_or(0, |n| n.height)
  }

  /// Updates this node’s height.
  fn update_height(&mut self) {
    self.height = 1 + i32::max(Self::height(&self.left), Self::height(&self.right));
  }

  /// Computes the balance factor of the node.
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
/// This struct is annotated with `#[napi(object)]` so that you can pass an array
/// of such objects from Node.js.
#[napi(object)]
pub struct KVPair {
  pub key: Either<i32, String>,
  pub value: Either<i32, String>,
}
