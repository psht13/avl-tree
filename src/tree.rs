use std::cmp::Ordering;

/// The pure Rust AVL tree core.
pub struct Tree {
    root: Option<Box<Node>>,
}

impl Tree {
    pub fn new() -> Self {
        Self { root: None }
    }

    pub fn insert(&mut self, key: i32, value: String) {
        self.root = Self::insert_node(self.root.take(), key, value);
    }

    pub fn find(&self, key: i32) -> Option<&str> {
        Self::search_node(&self.root, key).map(String::as_str)
    }

    pub fn remove(&mut self, key: i32) -> Option<String> {
        let (new_root, removed) = Self::remove_node(self.root.take(), key);
        self.root = new_root;
        removed
    }

    pub fn has(&self, key: i32) -> bool {
        Self::search_node(&self.root, key).is_some()
    }

    pub fn dump(&self) -> String {
        let mut entries = Vec::new();
        Self::traverse_in_order(&self.root, &mut entries);
        entries.join(", ")
    }

    fn insert_node(node: Option<Box<Node>>, key: i32, value: String) -> Option<Box<Node>> {
        if let Some(mut node) = node {
            match key.cmp(&node.key) {
                Ordering::Less => {
                    node.left = Self::insert_node(node.left.take(), key, value);
                }
                Ordering::Greater => {
                    node.right = Self::insert_node(node.right.take(), key, value);
                }
                Ordering::Equal => {
                    node.value = value;
                    return Some(node);
                }
            }
            node.update_height();
            Some(Self::balance(node))
        } else {
            Some(Box::new(Node::new(key, value)))
        }
    }

    fn search_node(node: &Option<Box<Node>>, key: i32) -> Option<&String> {
        let mut current = node.as_ref();
        while let Some(node) = current {
            match key.cmp(&node.key) {
                Ordering::Less => current = node.left.as_ref(),
                Ordering::Greater => current = node.right.as_ref(),
                Ordering::Equal => return Some(&node.value),
            }
        }
        None
    }

    fn balance(mut node: Box<Node>) -> Box<Node> {
        let balance_factor = node.balance_factor();

        if balance_factor > 1 {
            if node
                .left
                .as_ref()
                .expect("a left-heavy node must have a left child")
                .balance_factor()
                < 0
            {
                let left = node
                    .left
                    .take()
                    .expect("a left-heavy node must have a left child");
                node.left = Some(Self::rotate_left(left));
            }
            Self::rotate_right(node)
        } else if balance_factor < -1 {
            if node
                .right
                .as_ref()
                .expect("a right-heavy node must have a right child")
                .balance_factor()
                > 0
            {
                let right = node
                    .right
                    .take()
                    .expect("a right-heavy node must have a right child");
                node.right = Some(Self::rotate_right(right));
            }
            Self::rotate_left(node)
        } else {
            node
        }
    }

    fn rotate_right(mut root: Box<Node>) -> Box<Node> {
        let mut pivot = root
            .left
            .take()
            .expect("right rotation requires a left child");
        root.left = pivot.right.take();
        root.update_height();
        pivot.right = Some(root);
        pivot.update_height();
        pivot
    }

    fn rotate_left(mut root: Box<Node>) -> Box<Node> {
        let mut pivot = root
            .right
            .take()
            .expect("left rotation requires a right child");
        root.right = pivot.left.take();
        root.update_height();
        pivot.left = Some(root);
        pivot.update_height();
        pivot
    }

    fn traverse_in_order(node: &Option<Box<Node>>, entries: &mut Vec<String>) {
        if let Some(node) = node {
            Self::traverse_in_order(&node.left, entries);
            entries.push(format!("{{ key: {}, value: '{}' }}", node.key, node.value));
            Self::traverse_in_order(&node.right, entries);
        }
    }

    fn remove_node(node: Option<Box<Node>>, key: i32) -> (Option<Box<Node>>, Option<String>) {
        if let Some(mut node) = node {
            let removed = match key.cmp(&node.key) {
                Ordering::Less => {
                    let (new_left, removed) = Self::remove_node(node.left.take(), key);
                    node.left = new_left;
                    removed
                }
                Ordering::Greater => {
                    let (new_right, removed) = Self::remove_node(node.right.take(), key);
                    node.right = new_right;
                    removed
                }
                Ordering::Equal => {
                    let removed_value = Some(node.value.clone());
                    if node.left.is_none() {
                        return (node.right.take(), removed_value);
                    } else if node.right.is_none() {
                        return (node.left.take(), removed_value);
                    } else {
                        let right = node
                            .right
                            .take()
                            .expect("a two-child removal must have a right child");
                        let (new_right, minimum) = Self::remove_min(right);
                        node.right = new_right;
                        node.key = minimum.key;
                        node.value = minimum.value;
                        removed_value
                    }
                }
            };
            node.update_height();
            (Some(Self::balance(node)), removed)
        } else {
            (None, None)
        }
    }

    fn remove_min(mut node: Box<Node>) -> (Option<Box<Node>>, Box<Node>) {
        if node.left.is_none() {
            (node.right.take(), node)
        } else {
            let left = node
                .left
                .take()
                .expect("a non-minimum node must have a left child");
            let (new_left, minimum) = Self::remove_min(left);
            node.left = new_left;
            node.update_height();
            (Some(Self::balance(node)), minimum)
        }
    }
}

impl Default for Tree {
    fn default() -> Self {
        Self::new()
    }
}

struct Node {
    key: i32,
    value: String,
    height: i32,
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

impl Node {
    fn new(key: i32, value: String) -> Self {
        Self {
            key,
            value,
            height: 1,
            left: None,
            right: None,
        }
    }

    fn height(node: &Option<Box<Node>>) -> i32 {
        node.as_ref().map_or(0, |node| node.height)
    }

    fn update_height(&mut self) {
        self.height = 1 + Self::height(&self.left).max(Self::height(&self.right));
    }

    fn balance_factor(&self) -> i32 {
        Self::height(&self.left) - Self::height(&self.right)
    }
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
