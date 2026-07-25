use std::hint::black_box;
use std::time::Duration;

use criterion::{criterion_group, criterion_main, BatchSize, BenchmarkId, Criterion, Throughput};

#[path = "../src/tree.rs"]
#[allow(dead_code, unused_imports)]
mod tree;

use tree::Tree;

const SIZES: [usize; 3] = [1_000, 10_000, 100_000];
const SEED: u64 = 0x4d59_5df4_d0f3_3173;

fn shuffled_keys(size: usize) -> Vec<i32> {
    let mut keys: Vec<_> = (0..size as i32).collect();
    let mut state = SEED;

    for index in (1..keys.len()).rev() {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        keys.swap(index, (state as usize) % (index + 1));
    }

    keys
}

fn pairs(keys: &[i32]) -> Vec<(i32, String)> {
    keys.iter()
        .map(|&key| (key, format!("value-{key}")))
        .collect()
}

fn build_tree(entries: Vec<(i32, String)>) -> Tree {
    let mut tree = Tree::new();
    for (key, value) in entries {
        tree.insert(key, value);
    }
    tree
}

fn insertion_benchmarks(c: &mut Criterion) {
    let mut group = c.benchmark_group("insert");
    group.sample_size(20);
    group.warm_up_time(Duration::from_millis(250));
    group.measurement_time(Duration::from_millis(750));

    for size in SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let random = pairs(&shuffled_keys(size));
        group.bench_with_input(BenchmarkId::new("random", size), &random, |b, input| {
            b.iter_batched(
                || input.clone(),
                |entries| black_box(build_tree(entries)),
                BatchSize::LargeInput,
            );
        });

        let ascending = pairs(&(0..size as i32).collect::<Vec<_>>());
        group.bench_with_input(
            BenchmarkId::new("ascending", size),
            &ascending,
            |b, input| {
                b.iter_batched(
                    || input.clone(),
                    |entries| black_box(build_tree(entries)),
                    BatchSize::LargeInput,
                );
            },
        );

        let descending = pairs(&(0..size as i32).rev().collect::<Vec<_>>());
        group.bench_with_input(
            BenchmarkId::new("descending", size),
            &descending,
            |b, input| {
                b.iter_batched(
                    || input.clone(),
                    |entries| black_box(build_tree(entries)),
                    BatchSize::LargeInput,
                );
            },
        );
    }

    group.finish();
}

fn lookup_benchmarks(c: &mut Criterion) {
    let mut group = c.benchmark_group("lookup");
    group.sample_size(30);
    group.warm_up_time(Duration::from_millis(250));
    group.measurement_time(Duration::from_millis(750));

    for size in SIZES {
        let keys = shuffled_keys(size);
        let tree = build_tree(pairs(&keys));
        let missing: Vec<_> = (size as i32..(size * 2) as i32).collect();
        group.throughput(Throughput::Elements(size as u64));

        group.bench_with_input(BenchmarkId::new("successful", size), &keys, |b, input| {
            b.iter(|| {
                for &key in input {
                    black_box(tree.find(black_box(key)));
                }
            });
        });

        group.bench_with_input(BenchmarkId::new("missing", size), &missing, |b, input| {
            b.iter(|| {
                for &key in input {
                    black_box(tree.find(black_box(key)));
                }
            });
        });
    }

    group.finish();
}

fn duplicate_update_benchmarks(c: &mut Criterion) {
    let mut group = c.benchmark_group("duplicate_update");
    group.sample_size(20);
    group.warm_up_time(Duration::from_millis(250));
    group.measurement_time(Duration::from_millis(750));

    for size in SIZES {
        let keys = shuffled_keys(size);
        let initial = pairs(&keys);
        let updates: Vec<_> = keys
            .iter()
            .map(|&key| (key, format!("replacement-{key}")))
            .collect();
        group.throughput(Throughput::Elements(size as u64));

        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            &(initial, updates),
            |b, (initial, updates)| {
                b.iter_batched(
                    || (build_tree(initial.clone()), updates.clone()),
                    |(mut tree, updates)| {
                        for (key, value) in updates {
                            tree.insert(black_box(key), value);
                        }
                        black_box(tree);
                    },
                    BatchSize::LargeInput,
                );
            },
        );
    }

    group.finish();
}

fn topology_removal_benchmarks(c: &mut Criterion) {
    const BATCH: usize = 4_096;

    fn trees(entries: &[(i32, &str)]) -> Vec<Tree> {
        (0..BATCH)
            .map(|_| {
                let mut tree = Tree::new();
                for &(key, value) in entries {
                    tree.insert(key, value.to_owned());
                }
                tree
            })
            .collect()
    }

    let mut group = c.benchmark_group("remove_topology");
    group.throughput(Throughput::Elements(BATCH as u64));
    group.sample_size(20);
    group.warm_up_time(Duration::from_millis(250));
    group.measurement_time(Duration::from_millis(750));

    for (name, entries, key) in [
        ("leaf", &[(2, "two"), (1, "one"), (3, "three")][..], 1),
        ("one_child", &[(2, "two"), (1, "one")][..], 2),
        (
            "two_children",
            &[(2, "two"), (1, "one"), (3, "three")][..],
            2,
        ),
    ] {
        group.bench_function(name, |b| {
            b.iter_batched(
                || trees(entries),
                |mut trees| {
                    for tree in &mut trees {
                        black_box(tree.remove(black_box(key)));
                    }
                },
                BatchSize::LargeInput,
            );
        });
    }

    group.finish();
}

fn missing_removal_benchmarks(c: &mut Criterion) {
    let mut group = c.benchmark_group("remove_missing");
    group.sample_size(20);
    group.warm_up_time(Duration::from_millis(250));
    group.measurement_time(Duration::from_millis(750));

    for size in SIZES {
        let tree_entries = pairs(&shuffled_keys(size));
        let missing: Vec<_> = (size as i32..(size * 2) as i32).collect();
        group.throughput(Throughput::Elements(size as u64));

        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            &(tree_entries, missing),
            |b, (tree_entries, missing)| {
                b.iter_batched(
                    || build_tree(tree_entries.clone()),
                    |mut tree| {
                        for &key in missing {
                            black_box(tree.remove(black_box(key)));
                        }
                    },
                    BatchSize::LargeInput,
                );
            },
        );
    }

    group.finish();
}

fn mixed_workload_benchmarks(c: &mut Criterion) {
    let mut group = c.benchmark_group("mixed");
    group.sample_size(20);
    group.warm_up_time(Duration::from_millis(250));
    group.measurement_time(Duration::from_millis(750));

    for size in SIZES {
        let keys = shuffled_keys(size);
        let initial = pairs(&keys);
        group.throughput(Throughput::Elements(size as u64));

        group.bench_with_input(
            BenchmarkId::new("read_heavy", size),
            &(initial.clone(), keys.clone()),
            |b, (initial, keys)| {
                b.iter_batched(
                    || build_tree(initial.clone()),
                    |mut tree| {
                        for (index, &key) in keys.iter().enumerate() {
                            if index % 10 == 0 {
                                tree.insert(key, format!("updated-{index}"));
                            } else {
                                black_box(tree.find(black_box(key)));
                            }
                        }
                        black_box(tree);
                    },
                    BatchSize::LargeInput,
                );
            },
        );

        group.bench_with_input(
            BenchmarkId::new("balanced_mutation", size),
            &(initial, keys),
            |b, (initial, keys)| {
                b.iter_batched(
                    || build_tree(initial.clone()),
                    |mut tree| {
                        for (index, &key) in keys.iter().enumerate() {
                            if index % 2 == 0 {
                                black_box(tree.find(black_box(key)));
                            } else {
                                black_box(tree.remove(black_box(key)));
                                tree.insert(key, format!("reinserted-{index}"));
                            }
                        }
                        black_box(tree);
                    },
                    BatchSize::LargeInput,
                );
            },
        );
    }

    group.finish();
}

fn dump_benchmarks(c: &mut Criterion) {
    let mut group = c.benchmark_group("dump");
    group.sample_size(20);
    group.warm_up_time(Duration::from_millis(250));
    group.measurement_time(Duration::from_millis(750));

    for size in SIZES {
        let tree = build_tree(pairs(&shuffled_keys(size)));
        group.throughput(Throughput::Elements(size as u64));
        group.bench_with_input(BenchmarkId::from_parameter(size), &tree, |b, tree| {
            b.iter(|| black_box(tree.dump()));
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    insertion_benchmarks,
    lookup_benchmarks,
    duplicate_update_benchmarks,
    topology_removal_benchmarks,
    missing_removal_benchmarks,
    mixed_workload_benchmarks,
    dump_benchmarks,
);
criterion_main!(benches);
