use near_primitives::account::{Account, AccountContract};
use near_primitives::hash::CryptoHash;
use near_primitives::receipt::{DataReceipt, Receipt, ReceiptEnum, ReceiptV0};
use near_primitives::transaction::{ExecutionMetadata, ExecutionOutcome, ExecutionStatus};
use near_primitives::types::{Balance, Gas};
use near_primitives::utils::create_receipt_id_from_transaction;
use near_store::trie::trie_storage::TrieMemoryPartialStorage;
use near_store::trie::{AccessOptions, Trie};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::io::{self, Read};
use std::sync::Arc;

fn bytes(value: &Value) -> Vec<u8> {
    hex::decode(value.as_str().unwrap()).unwrap()
}

fn root(entries: &BTreeMap<Vec<u8>, Vec<u8>>) -> CryptoHash {
    let storage = Arc::new(TrieMemoryPartialStorage::<false>::default());
    let trie = Trie::new(storage, Trie::EMPTY_ROOT, None);
    trie.update(
        entries.iter().map(|(key, value)| (key.clone(), Some(value.clone()))),
        AccessOptions::DEFAULT,
    )
    .unwrap()
    .new_root
}

fn vectors() -> Value {
    let local_hash = CryptoHash([7; 32]);
    let account = Account::new(
        Balance::from_yoctonear(123),
        Balance::from_yoctonear(45),
        AccountContract::Local(local_hash),
        99,
    );
    let receipt_id = CryptoHash([3; 32]);
    let data_id = CryptoHash([4; 32]);
    let receipt = Receipt::V0(ReceiptV0 {
        predecessor_id: "alice".parse().unwrap(),
        receiver_id: "bob".parse().unwrap(),
        receipt_id,
        receipt: ReceiptEnum::Data(DataReceipt { data_id, data: Some(vec![5, 6]) }),
    });
    let outcome = ExecutionOutcome {
        logs: vec!["log".to_string()],
        receipt_ids: vec![receipt_id],
        gas_burnt: Gas::from_gas(7),
        compute_usage: Some(7),
        tokens_burnt: Balance::from_yoctonear(11),
        executor_id: "bob".parse().unwrap(),
        status: ExecutionStatus::SuccessValue(vec![8, 9]),
        metadata: ExecutionMetadata::V1,
    };
    json!({
        "accountV1": hex::encode(borsh::to_vec(&account).unwrap()),
        "dataReceipt": hex::encode(borsh::to_vec(&receipt).unwrap()),
        "executionOutcome": hex::encode(borsh::to_vec(&outcome).unwrap()),
        "receiptId": hex::encode(create_receipt_id_from_transaction(&CryptoHash([1; 32]), 9).0),
    })
}

fn main() {
    let mut source = String::new();
    io::stdin().read_to_string(&mut source).unwrap();
    let input: Value = serde_json::from_str(&source).unwrap();
    let mut records = BTreeMap::new();
    for record in input["initialRecords"].as_array().unwrap() {
        records.insert(bytes(&record["key"]), bytes(&record["value"]));
    }
    let mut roots = Vec::new();
    for chunk in input["chunks"].as_array().unwrap() {
        for change in chunk["changes"].as_array().unwrap() {
            let key = bytes(&change["key"]);
            if change["value"].is_null() {
                records.remove(&key);
            } else {
                records.insert(key, bytes(&change["value"]));
            }
        }
        roots.push(hex::encode(root(&records).0));
    }
    println!("{}", json!({ "roots": roots, "vectors": vectors() }));
}
