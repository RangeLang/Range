use std::env;

fn main() {
    let n = env::args()
        .nth(1)
        .and_then(|value| value.parse::<i64>().ok())
        .unwrap_or(10_000_000);

    let mut i: i64 = 0;
    let mut acc: i64 = 1;
    while i < n {
        acc = (acc * 1_664_525 + i) % 2_147_483_647;
        i += 1;
    }

    println!("{acc}");
}
