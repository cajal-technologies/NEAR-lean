import NEARLean.AbstractKernel
import NEARLean.Concrete.Borsh
import NEARLean.Crypto.SHA256

namespace NEARLean.Concrete

abbrev Bytes := List UInt8
abbrev CryptoHash := Bytes

def hash (value : Bytes) : CryptoHash := Crypto.SHA256.hash value

def createHashIndex (base : CryptoHash) (blockHeight salt : Nat) : CryptoHash :=
  hash (Borsh.fixed 32 base ++ Borsh.u64 blockHeight ++ Borsh.u64 salt)

def createReceiptIdFromTransaction
    (transactionHash : CryptoHash) (blockHeight : Nat) : CryptoHash :=
  createHashIndex transactionHash blockHeight 0

def createReceiptIdFromReceipt
    (receiptId : CryptoHash) (blockHeight receiptIndex : Nat) : CryptoHash :=
  createHashIndex receiptId blockHeight receiptIndex

namespace TrieKey

def account (accountId : AccountId) : Bytes := 0 :: accountId

def contractCode (accountId : AccountId) : Bytes := 1 :: accountId

def accessKey (accountId keyHandle : Bytes) : Bytes :=
  2 :: accountId ++ 2 :: keyHandle

def contractData (accountId key : Bytes) : Bytes :=
  9 :: accountId ++ 44 :: key

def delayedReceiptIndices : Bytes := [7]

def delayedReceipt (index : Nat) : Bytes := 7 :: Borsh.u64 index

end TrieKey

structure AccountV1 where
  amount : Nat
  locked : Nat
  codeHash : CryptoHash
  storageUsage : Nat
  deriving BEq, Repr

def AccountV1.borsh (account : AccountV1) : Bytes :=
  Borsh.u128 account.amount ++ Borsh.u128 account.locked ++
    Borsh.fixed 32 account.codeHash ++ Borsh.u64 account.storageUsage

structure DataReceipt where
  predecessorId : Bytes
  receiverId : Bytes
  receiptId : CryptoHash
  dataId : CryptoHash
  data : Option Bytes
  deriving BEq, Repr

def DataReceipt.borsh (receipt : DataReceipt) : Bytes :=
  Borsh.bytes receipt.predecessorId ++ Borsh.bytes receipt.receiverId ++
    Borsh.fixed 32 receipt.receiptId ++ [1] ++ Borsh.fixed 32 receipt.dataId ++
    Borsh.option Borsh.bytes receipt.data

inductive SuccessStatus where
  | value (value : Bytes)
  | receiptId (value : CryptoHash)
  deriving BEq, Repr

def SuccessStatus.borsh : SuccessStatus → Bytes
  | SuccessStatus.value bytes => 2 :: Borsh.bytes bytes
  | SuccessStatus.receiptId hashValue => 3 :: Borsh.fixed 32 hashValue

structure ExecutionOutcome where
  logs : List Bytes := []
  receiptIds : List CryptoHash := []
  gasBurnt : Nat := 0
  tokensBurnt : Nat := 0
  executorId : Bytes
  status : SuccessStatus := .value []
  deriving BEq, Repr

def ExecutionOutcome.borsh (outcome : ExecutionOutcome) : Bytes :=
  Borsh.list Borsh.bytes outcome.logs ++
    Borsh.list (Borsh.fixed 32) outcome.receiptIds ++
    Borsh.u64 outcome.gasBurnt ++ Borsh.u128 outcome.tokensBurnt ++
    Borsh.bytes outcome.executorId ++ outcome.status.borsh ++ [0]

end NEARLean.Concrete
