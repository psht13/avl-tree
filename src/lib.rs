#[macro_use]
extern crate napi_derive;

#[napi]
pub struct AVLTree {
    root: Option<Box<Node>>,
}

#[napi] 
impl AVLTree {
    #[napi(constructor)]
    pub fn new() -> Self {
        Self { root: None }
    }

    #[napi]
    pub fn insert(&mut self, value: i32) {
        self.root = Self::insert_node(self.root.take(), value);
    }

    #[napi]
    pub fn contains(&self, value: i32) -> bool {
        Self::contains_node(&self.root, value)
    }

    // Internal recursive function for insertion
    fn insert_node(node: Option<Box<Node>>, value: i32) -> Option<Box<Node>> {
        if let Some(mut n) = node {
            if value < n.value {
                n.left = Self::insert_node(n.left.take(), value);
            } else if value > n.value {
                n.right = Self::insert_node(n.right.take(), value);
            } else {
                // Duplicate values are not allowed in AVL trees
                return Some(n);
            }
            
            n.update_height();
            Some(Self::balance(n))
        } else {
            Some(Box::new(Node::new(value)))
        }
    }

    // Internal recursive function to check if a value exists
    fn contains_node(node: &Option<Box<Node>>, value: i32) -> bool {
        if let Some(n) = node {
            if value == n.value {
                true
            } else if value < n.value {
                Self::contains_node(&n.left, value)
            } else {
                Self::contains_node(&n.right, value)
            }
        } else {
            false
        }
    }

    // Balances a subtree rooted at the given node
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

    // Performs a right rotation
    fn rotate_right(mut y: Box<Node>) -> Box<Node> {
        let mut x = y.left.take().unwrap();
        y.left = x.right.take();
        y.update_height();
        x.right = Some(y);
        x.update_height();
        x
    }

    // Performs a left rotation
    fn rotate_left(mut x: Box<Node>) -> Box<Node> {
        let mut y = x.right.take().unwrap();
        x.right = y.left.take();
        x.update_height();
        y.left = Some(x);
        y.update_height();
        y
    }
}

struct Node {
    value: i32,
    height: i32,
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

impl Node {
    fn new(value: i32) -> Self {
        Self {
            value,
            height: 1,
            left: None,
            right: None,
        }
    }

    fn height(node: &Option<Box<Node>>) -> i32 {
        node.as_ref().map_or(0, |n| n.height)
    }

    fn update_height(&mut self) {
        self.height = 1 + i32::max(Self::height(&self.left), Self::height(&self.right));
    }

    fn balance_factor(&self) -> i32 {
        Self::height(&self.left) - Self::height(&self.right)
    }
}
