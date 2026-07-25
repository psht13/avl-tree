use std::cmp::Ordering;
use std::fmt::Write;

/// The pure Rust AVL tree core.
pub struct Tree {
    root: Option<Box<Node>>,
    len: usize,
}

impl Tree {
    pub fn new() -> Self {
        Self { root: None, len: 0 }
    }

    pub fn insert(&mut self, key: i32, value: String) {
        let mut inserted = false;
        self.root = Some(Self::insert_node(
            self.root.take(),
            key,
            value,
            &mut inserted,
        ));
        self.len += usize::from(inserted);
    }

    pub fn find(&self, key: i32) -> Option<&str> {
        Self::search_node(&self.root, key).map(String::as_str)
    }

    pub fn remove(&mut self, key: i32) -> Option<String> {
        let (new_root, removed) = Self::remove_node(self.root.take(), key);
        self.root = new_root;
        self.len -= usize::from(removed.is_some());
        removed
    }

    pub fn has(&self, key: i32) -> bool {
        Self::search_node(&self.root, key).is_some()
    }

    pub fn dump(&self) -> String {
        let mut output = String::with_capacity(self.len.saturating_mul(32));
        let mut first = true;
        Self::write_in_order(&self.root, &mut output, &mut first);
        output
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    fn insert_node(
        node: Option<Box<Node>>,
        key: i32,
        value: String,
        inserted: &mut bool,
    ) -> Box<Node> {
        if let Some(mut node) = node {
            match key.cmp(&node.key) {
                Ordering::Less => {
                    node.left = Some(Self::insert_node(node.left.take(), key, value, inserted));
                }
                Ordering::Greater => {
                    node.right = Some(Self::insert_node(node.right.take(), key, value, inserted));
                }
                Ordering::Equal => {
                    node.value = value;
                    return node;
                }
            }

            if *inserted {
                node.update_height();
                Self::balance(node)
            } else {
                node
            }
        } else {
            *inserted = true;
            Box::new(Node::new(key, value))
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

    fn write_in_order(node: &Option<Box<Node>>, output: &mut String, first: &mut bool) {
        if let Some(node) = node {
            Self::write_in_order(&node.left, output, first);
            if *first {
                *first = false;
            } else {
                output.push_str(", ");
            }
            write!(output, "{{ key: {}, value: '{}' }}", node.key, node.value)
                .expect("writing to a String cannot fail");
            Self::write_in_order(&node.right, output, first);
        }
    }

    fn remove_node(node: Option<Box<Node>>, key: i32) -> (Option<Box<Node>>, Option<String>) {
        let Some(mut node) = node else {
            return (None, None);
        };

        match key.cmp(&node.key) {
            Ordering::Less => {
                let (new_left, removed) = Self::remove_node(node.left.take(), key);
                node.left = new_left;
                let Some(removed) = removed else {
                    return (Some(node), None);
                };
                node.update_height();
                (Some(Self::balance(node)), Some(removed))
            }
            Ordering::Greater => {
                let (new_right, removed) = Self::remove_node(node.right.take(), key);
                node.right = new_right;
                let Some(removed) = removed else {
                    return (Some(node), None);
                };
                node.update_height();
                (Some(Self::balance(node)), Some(removed))
            }
            Ordering::Equal => {
                let Node {
                    value, left, right, ..
                } = *node;

                match (left, right) {
                    (None, right) => (right, Some(value)),
                    (left, None) => (left, Some(value)),
                    (Some(left), Some(right)) => {
                        let (new_right, mut successor) = Self::remove_min(right);
                        successor.left = Some(left);
                        successor.right = new_right;
                        successor.update_height();
                        (Some(Self::balance(successor)), Some(value))
                    }
                }
            }
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
