use std::collections::BinaryHeap;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut queue: BinaryHeap<u64> = BinaryHeap::new();

    queue.push(3);
    queue.push(1);
    queue.push(5);
    queue.push(4);
    queue.push(2);

    let vec = queue.into_sorted_vec();

    println!("{:?}", vec);

    Ok(())
}
