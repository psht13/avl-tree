use std::collections::BTreeMap;
use std::mem::size_of;

use proptest::prelude::*;

use super::{Node, Tree};

fn validate_node(
    node: &Option<Box<Node>>,
    lower: Option<i32>,
    upper: Option<i32>,
    entries: &mut Vec<(i32, String)>,
) -> (i32, usize) {
    let Some(node) = node else {
        return (0, 0);
    };

    if let Some(lower) = lower {
        assert!(node.key > lower, "{} is not greater than {lower}", node.key);
    }
    if let Some(upper) = upper {
        assert!(node.key < upper, "{} is not less than {upper}", node.key);
    }

    let (left_height, left_count) = validate_node(&node.left, lower, Some(node.key), entries);
    entries.push((node.key, node.value.clone()));
    let (right_height, right_count) = validate_node(&node.right, Some(node.key), upper, entries);

    let expected_height = 1 + left_height.max(right_height);
    assert_eq!(
        node.height, expected_height,
        "incorrect stored height at key {}",
        node.key
    );
    assert!(
        (-1..=1).contains(&(left_height - right_height)),
        "unbalanced node at key {}",
        node.key
    );

    (expected_height, left_count + right_count + 1)
}

fn assert_valid(tree: &Tree) -> Vec<(i32, String)> {
    let mut entries = Vec::new();
    let (_, count) = validate_node(&tree.root, None, None, &mut entries);

    assert_eq!(count, entries.len());
    assert_eq!(count, tree.len);
    assert_eq!(tree.len(), tree.len);
    assert_eq!(tree.is_empty(), tree.len == 0);
    assert!(
        entries.windows(2).all(|pair| pair[0].0 < pair[1].0),
        "in-order traversal is not strictly ordered"
    );

    entries
}

fn assert_matches_model(tree: &Tree, model: &BTreeMap<i32, String>) {
    let entries = assert_valid(tree);
    let expected: Vec<_> = model
        .iter()
        .map(|(&key, value)| (key, value.clone()))
        .collect();

    assert_eq!(entries, expected);
    for (&key, value) in model {
        assert_eq!(tree.find(key), Some(value.as_str()));
        assert!(tree.has(key));
    }
}

#[test]
fn empty_tree_behavior() {
    let mut tree = Tree::new();
    let default_tree = Tree::default();

    assert_eq!(tree.find(1), None);
    assert!(!tree.has(1));
    assert_eq!(tree.remove(1), None);
    assert_eq!(tree.dump(), "");
    assert!(assert_valid(&tree).is_empty());
    assert!(default_tree.is_empty());
}

#[test]
fn one_insertion_and_duplicate_replacement() {
    let mut tree = Tree::new();

    tree.insert(7, "first".to_owned());
    assert_eq!(tree.find(7), Some("first"));
    assert_eq!(tree.dump(), "{ key: 7, value: 'first' }");

    tree.insert(7, "replacement".to_owned());
    assert_eq!(tree.find(7), Some("replacement"));
    assert_eq!(tree.len(), 1);
    assert_eq!(assert_valid(&tree), vec![(7, "replacement".to_owned())]);
}

#[test]
fn find_and_has_hits_and_misses() {
    let mut tree = Tree::new();
    tree.insert(10, "ten".to_owned());

    assert_eq!(tree.find(10), Some("ten"));
    assert_eq!(tree.find(11), None);
    assert!(tree.has(10));
    assert!(!tree.has(11));
    assert_valid(&tree);
}

#[test]
fn missing_removal_preserves_tree() {
    let mut tree = Tree::new();
    for key in [4, 2, 6, 1, 3, 5, 7] {
        tree.insert(key, key.to_string());
    }
    let before = tree.dump();

    assert_eq!(tree.remove(99), None);
    assert_eq!(tree.dump(), before);
    assert_valid(&tree);
}

#[test]
fn removes_leaf_and_non_root_nodes_with_each_child_shape() {
    let mut leaf_tree = Tree::new();
    for key in [4, 2, 6, 1, 3, 5, 7] {
        leaf_tree.insert(key, key.to_string());
    }
    assert_eq!(leaf_tree.remove(1), Some("1".to_owned()));
    assert_eq!(leaf_tree.find(1), None);
    assert_valid(&leaf_tree);

    let mut left_child_tree = Tree::new();
    for key in [10, 5, 15, 3] {
        left_child_tree.insert(key, key.to_string());
    }
    assert_eq!(left_child_tree.remove(5), Some("5".to_owned()));
    assert_eq!(left_child_tree.find(3), Some("3"));
    assert_valid(&left_child_tree);

    let mut right_child_tree = Tree::new();
    for key in [10, 5, 15, 7] {
        right_child_tree.insert(key, key.to_string());
    }
    assert_eq!(right_child_tree.remove(5), Some("5".to_owned()));
    assert_eq!(right_child_tree.find(7), Some("7"));
    assert_valid(&right_child_tree);

    let mut two_child_tree = Tree::new();
    for key in [10, 5, 15, 3, 7, 6, 8] {
        two_child_tree.insert(key, key.to_string());
    }
    assert_eq!(two_child_tree.remove(5), Some("5".to_owned()));
    assert_eq!(two_child_tree.find(5), None);
    assert_valid(&two_child_tree);
}

#[test]
fn removes_root_with_each_child_shape() {
    let mut leaf = Tree::new();
    leaf.insert(1, "leaf".to_owned());
    assert_eq!(leaf.remove(1), Some("leaf".to_owned()));
    assert!(assert_valid(&leaf).is_empty());

    let mut left = Tree::new();
    left.insert(2, "root".to_owned());
    left.insert(1, "left".to_owned());
    assert_eq!(left.remove(2), Some("root".to_owned()));
    assert_eq!(left.find(1), Some("left"));
    assert_valid(&left);

    let mut right = Tree::new();
    right.insert(1, "root".to_owned());
    right.insert(2, "right".to_owned());
    assert_eq!(right.remove(1), Some("root".to_owned()));
    assert_eq!(right.find(2), Some("right"));
    assert_valid(&right);

    let mut two_children = Tree::new();
    for key in [2, 1, 3] {
        two_children.insert(key, key.to_string());
    }
    assert_eq!(two_children.remove(2), Some("2".to_owned()));
    assert_eq!(two_children.find(2), None);
    assert_valid(&two_children);
}

fn assert_rotation(order: [i32; 3], expected_root: i32) {
    let mut tree = Tree::new();
    for key in order {
        tree.insert(key, key.to_string());
    }

    assert_eq!(tree.root.as_ref().map(|node| node.key), Some(expected_root));
    assert_valid(&tree);
}

#[test]
fn performs_all_four_insertion_rotations() {
    assert_rotation([3, 2, 1], 2);
    assert_rotation([1, 2, 3], 2);
    assert_rotation([3, 1, 2], 2);
    assert_rotation([1, 3, 2], 2);
}

#[test]
fn rebalances_after_deletion() {
    let mut tree = Tree::new();
    for key in [9, 5, 10, 0, 6, 11, -1, 1, 2] {
        tree.insert(key, key.to_string());
    }
    let root_before = tree.root.as_ref().map(|node| node.key);

    assert_eq!(tree.remove(10), Some("10".to_owned()));
    assert_ne!(tree.root.as_ref().map(|node| node.key), root_before);
    assert_valid(&tree);

    for key in [11, 9, 6, 5, 2, 1, 0, -1] {
        tree.remove(key);
        assert_valid(&tree);
    }
}

#[test]
fn supports_i32_boundaries() {
    let mut tree = Tree::new();
    tree.insert(i32::MIN, "minimum".to_owned());
    tree.insert(0, "zero".to_owned());
    tree.insert(i32::MAX, "maximum".to_owned());

    assert_eq!(tree.find(i32::MIN), Some("minimum"));
    assert_eq!(tree.find(i32::MAX), Some("maximum"));
    assert_eq!(tree.remove(i32::MIN), Some("minimum".to_owned()));
    assert_eq!(tree.remove(i32::MAX), Some("maximum".to_owned()));
    assert_valid(&tree);
}

#[test]
fn remains_balanced_for_sorted_insertions() {
    let mut ascending = Tree::new();
    let mut descending = Tree::new();

    for key in 0..1_000 {
        ascending.insert(key, key.to_string());
    }
    for key in (0..1_000).rev() {
        descending.insert(key, key.to_string());
    }

    assert_valid(&ascending);
    assert_valid(&descending);
}

#[test]
fn deterministic_mixed_sequence_matches_btree_map() {
    let mut tree = Tree::new();
    let mut model = BTreeMap::new();
    let mut state = 0x4d59_5df4_d0f3_3173_u64;

    for index in 0..5_000 {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let key = ((state % 401) as i32) - 200;

        match state % 4 {
            0 | 1 => {
                let value = format!("value-{index}-{state}");
                tree.insert(key, value.clone());
                model.insert(key, value);
            }
            2 => assert_eq!(tree.remove(key), model.remove(&key)),
            _ => {
                assert_eq!(tree.find(key), model.get(&key).map(String::as_str));
                assert_eq!(tree.has(key), model.contains_key(&key));
            }
        }

        assert_matches_model(&tree, &model);
    }
}

#[test]
fn dump_preserves_exact_legacy_format() {
    let mut tree = Tree::new();
    tree.insert(3, String::new());
    tree.insert(1, "quotes: ' and \"".to_owned());
    tree.insert(2, "commas, braces { }".to_owned());
    tree.insert(4, "Unicode: Привіт 🌳".to_owned());

    assert_eq!(
        tree.dump(),
        "{ key: 1, value: 'quotes: ' and \"' }, { key: 2, value: 'commas, braces { }' }, { key: 3, value: '' }, { key: 4, value: 'Unicode: Привіт 🌳' }"
    );
    assert_valid(&tree);
}

#[test]
fn records_baseline_node_size() {
    eprintln!("size_of::<Node>() = {}", size_of::<Node>());
    assert!(size_of::<Node>() > 0);
}

#[derive(Clone, Debug)]
enum Operation {
    Insert(i32, String),
    Find(i32),
    Has(i32),
    Remove(i32),
}

fn operation_strategy() -> impl Strategy<Value = Operation> {
    prop_oneof![
        5 => ((-64_i32..=64), "[ -~]{0,16}")
            .prop_map(|(key, value)| Operation::Insert(key, value)),
        2 => (-80_i32..=80).prop_map(Operation::Find),
        1 => (-80_i32..=80).prop_map(Operation::Has),
        3 => (-80_i32..=80).prop_map(Operation::Remove),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig {
        cases: 256,
        max_shrink_iters: 10_000,
        ..ProptestConfig::default()
    })]

    #[test]
    fn operation_sequences_match_btree_map(
        operations in prop::collection::vec(operation_strategy(), 1..128)
    ) {
        let mut tree = Tree::new();
        let mut model = BTreeMap::new();

        for operation in operations {
            match operation {
                Operation::Insert(key, value) => {
                    tree.insert(key, value.clone());
                    model.insert(key, value);
                }
                Operation::Find(key) => {
                    prop_assert_eq!(tree.find(key), model.get(&key).map(String::as_str));
                }
                Operation::Has(key) => {
                    prop_assert_eq!(tree.has(key), model.contains_key(&key));
                }
                Operation::Remove(key) => {
                    prop_assert_eq!(tree.remove(key), model.remove(&key));
                }
            }

            let entries = assert_valid(&tree);
            let expected: Vec<_> = model
                .iter()
                .map(|(&key, value)| (key, value.clone()))
                .collect();
            prop_assert_eq!(entries, expected);
        }
    }
}
