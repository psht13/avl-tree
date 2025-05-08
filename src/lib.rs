#[macro_use]
extern crate napi_derive;

use std::cmp::Ordering;

/// A Node.js–exposed AVL tree that supports integer keys and string values.
///
/// The AVL tree is a self-balancing binary search tree that supports insertion,
/// search by key, removal by key, and dumping the tree contents (in-order traversal).
#[napi]
pub struct AVLTree {
    root: Option<Box<Node>>,
}

#[napi]
impl AVLTree {
    /// Creates a new, empty AVL tree.
    ///
    /// This constructor initializes an empty AVL tree with no nodes.
    ///
    /// # Returns
    ///
    /// A new instance of AVLTree with no nodes.
    #[napi(constructor)]
    pub fn new() -> Self {
        Self { root: None }
    }

    /// Inserts a node with the specified key and value into the AVL tree.
    ///
    /// If a node with the same key already exists, its value is updated.
    ///
    /// # Parameters
    ///
    /// - key: The key (integer) to insert.
    /// - value: The value (string) to insert.
    ///
    /// # Example (TypeScript)
    ///
    /// ```ts
    /// const tree = new AvlTree();
    /// tree.insert(42, "The answer");
    /// ```
    #[napi]
    pub fn insert(&mut self, key: i32, value: String) {
        self.root = Self::insert_node(self.root.take(), key, value);
    }

    /// Searches for a node in the AVL tree by its key.
    ///
    /// Returns the associated value if the key exists, otherwise returns null.
    ///
    /// # Parameters
    ///
    /// - key: The key (integer) to search for.
    ///
    /// # Returns
    ///
    /// The value associated with the key if found, or null if not found.
    ///
    /// # Example (TypeScript)
    ///
    /// ```ts
    /// const value = tree.find(42);
    /// if (value !== null) {
    ///   console.log("Found:", value);
    /// } else {
    ///   console.log("Not found");
    /// }
    /// ```
    #[napi]
    pub fn find(&self, key: i32) -> Option<&str> {
        Self::search_node(&self.root, key).map(|s| s.as_str())
    }

    /// Returns a string representing all nodes in the AVL tree using in-order traversal.
    ///
    /// The returned string lists the nodes in sorted order by key. Each node is represented
    /// by its key and value.
    ///
    /// # Returns
    ///
    /// A string containing the representation of all nodes in the tree.
    ///
    /// # Example (TypeScript)
    ///
    /// ```ts
    /// console.log(tree.dump());
    /// // Might output: "{ key: 5, value: 'five' }, { key: 10, value: 'ten' }, { key: 15, value: 'fifteen' }"
    /// ```
    #[napi]
    pub fn dump(&self) -> String {
        let mut entries = Vec::new();
        Self::traverse_in_order(&self.root, &mut entries);
        entries.join(", ")
    }

    /// Removes a node from the AVL tree by its key.
    ///
    /// If a node with the specified key exists, it is removed and the associated value is returned.
    /// If no such node exists, null is returned.
    ///
    /// # Parameters
    ///
    /// - key: The key (integer) to remove.
    ///
    /// # Returns
    ///
    /// The value associated with the removed node if removal was successful, or null otherwise.
    ///
    /// # Example (TypeScript)
    ///
    /// ```ts
    /// const removedValue = tree.remove(42);
    /// if (removedValue !== null) {
    ///   console.log("Removed:", removedValue);
    /// } else {
    ///   console.log("Key not found");
    /// }
    /// ```
    #[napi]
    pub fn remove(&mut self, key: i32) -> Option<String> {
        let (new_root, removed) = Self::remove_node(self.root.take(), key);
        self.root = new_root;
        removed
    }

    /// Checks if a node with the specified key exists in the AVL tree.
    ///
    /// # Parameters
    ///
    /// - key: The key (integer) to check.
    ///
    /// # Returns
    ///
    /// `true` if a node with the specified key exists, `false` otherwise.
    ///
    /// # Example (TypeScript)
    ///
    /// ```ts
    /// const tree = new AvlTree();
    /// tree.insert(42, "The answer");
    ///
    /// if (tree.has(42)) {
    ///   console.log("Key exists in the tree");
    /// } else {
    ///   console.log("Key not found");
    /// }
    /// ```
    #[napi]
    pub fn has(&self, key: i32) -> bool {
        Self::search_node(&self.root, key).is_some()
    }

    // --- Internal AVL tree functions ---

    fn insert_node(node: Option<Box<Node>>, key: i32, value: String) -> Option<Box<Node>> {
        if let Some(mut n) = node {
            match key.cmp(&n.key) {
                Ordering::Less => {
                    n.left = Self::insert_node(n.left.take(), key, value);
                }
                Ordering::Greater => {
                    n.right = Self::insert_node(n.right.take(), key, value);
                }
                Ordering::Equal => {
                    n.value = value; // No need to clone, directly replace value.
                    return Some(n);
                }
            }
            n.update_height();
            Some(Self::balance(n))
        } else {
            Some(Box::new(Node::new(key, value)))
        }
    }

    fn search_node(node: &Option<Box<Node>>, key: i32) -> Option<&String> {
        let mut current = node.as_ref();
        while let Some(n) = current {
            match key.cmp(&n.key) {
                Ordering::Less => current = n.left.as_ref(),
                Ordering::Greater => current = n.right.as_ref(),
                Ordering::Equal => return Some(&n.value),
            }
        }
        None
    }

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

    fn rotate_right(mut y: Box<Node>) -> Box<Node> {
        let mut x = y.left.take().unwrap();
        y.left = x.right.take();
        y.update_height();
        x.right = Some(y);
        x.update_height();
        x
    }

    fn rotate_left(mut x: Box<Node>) -> Box<Node> {
        let mut y = x.right.take().unwrap();
        x.right = y.left.take();
        x.update_height();
        y.left = Some(x);
        y.update_height();
        y
    }

    fn traverse_in_order(node: &Option<Box<Node>>, entries: &mut Vec<String>) {
        if let Some(n) = node {
            Self::traverse_in_order(&n.left, entries);
            entries.push(format!("{{ key: {}, value: '{}' }}", n.key, n.value));
            Self::traverse_in_order(&n.right, entries);
        }
    }

    fn remove_node(node: Option<Box<Node>>, key: i32) -> (Option<Box<Node>>, Option<String>) {
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
                    if n.left.is_none() {
                        return (n.right.take(), removed_value);
                    } else if n.right.is_none() {
                        return (n.left.take(), removed_value);
                    } else {
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

/// A node in the AVL tree.
///
/// Each node contains a key, a value, and pointers to its left and right children. It also
/// tracks its height to ensure the tree remains balanced.
struct Node {
    key: i32,
    value: String,
    height: i32,
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

impl Node {
    /// Creates a new node with the specified key and value.
    ///
    /// # Parameters
    ///
    /// - key: The key (integer) for the node.
    /// - value: The value (string) for the node.
    ///
    fn new(key: i32, value: String) -> Self {
        Self {
            key,
            value,
            height: 1,
            left: None,
            right: None,
        }
    }

    /// Returns the height of a node.
    ///
    /// # Parameters
    ///
    /// - node: A reference to the node whose height we want to obtain.
    ///
    /// # Returns
    ///
    /// The height of the node.
    fn height(node: &Option<Box<Node>>) -> i32 {
        node.as_ref().map_or(0, |n| n.height)
    }

    /// Updates the height of the current node.
    ///
    /// The height is calculated as 1 plus the maximum height of the left and right subtrees.
    fn update_height(&mut self) {
        self.height = 1 + i32::max(Self::height(&self.left), Self::height(&self.right));
    }

    /// Computes the balance factor of the node.
    ///
    /// The balance factor is the difference between the height of the left and right subtrees.
    /// If it is greater than 1, the node is left-heavy, and if it is less than -1, the node is
    /// right-heavy.
    fn balance_factor(&self) -> i32 {
        Self::height(&self.left) - Self::height(&self.right)
    }
}
