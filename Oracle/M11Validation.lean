import Lean.Data.Json
import NEARLean.Concrete.Hex
import NEARLean.Concrete.State

namespace NEARLean.M11Validation

open Lean
open NEARLean.Concrete

structure CorpusRecord where
  key : String
  value : Option String
  deriving FromJson

structure CorpusAction where
  kind : String
  caller : Option Nat
  sender : Option Nat
  receiver : Option Nat
  amount : Option Nat
  deriving FromJson

structure CorpusChunk where
  index : Nat
  action : CorpusAction
  changes : List CorpusRecord
  stateChangesBorsh : String
  serializedOutcome : String
  receiptId : String
  stateRoot : String
  deriving FromJson

structure NearcoreVectors where
  accountV1 : String
  dataReceipt : String
  executionOutcome : String
  receiptId : String
  deriving FromJson

structure Corpus where
  schemaVersion : Nat
  nearcoreCommit : String
  protocolVersion : Nat
  seed : Nat
  chunkCount : Nat
  initialRecords : List CorpusRecord
  chunks : List CorpusChunk
  nearcoreVectors : NearcoreVectors
  deriving FromJson

private def require (condition : Bool) (message : String) : Except String Unit :=
  if condition then .ok () else .error message

private def decode (name value : String) : Except String Bytes :=
  match Hex.decode value with
  | some bytes => .ok bytes
  | none => .error s!"{name} is not valid hexadecimal"

private def decodeRecord (record : CorpusRecord) : Except String (Bytes × Bytes) := do
  let key ← decode "record key" record.key
  let value ← match record.value with
    | some encoded => decode "record value" encoded
    | none => throw "initial record has no value"
  return (key, value)

private def decodeChange (record : CorpusRecord) : Except String StateChange := do
  let key ← decode "change key" record.key
  let value ← record.value.mapM (decode "change value")
  return { key, value }

private def accountId (index : Nat) : AccountId := [97, UInt8.ofNat (65 + index)]

private def counterId : AccountId := "counter".toUTF8.toList

private def initialState : State := {
  world := {
    accounts := (List.range 16).map (fun index =>
      (accountId index, { Account.initial with balance := 100000 })) ++ [
        (counterId, {
          balance := 100
          locked := 0
          storage := [(NativeStorage.counter, [])]
          contract := some NativeContract.counterId
        })]
    block := (WorldState.initial RuntimeConfig.default).block
  }
}

private def inputAt (index : Nat) : Input :=
  if index % 5 = 0 then
    .functionCall (accountId (index / 5 % 16)) counterId
      NativeMethod.increment [] 0 100
  else
    let sender := index % 16
    let receiver := (sender + index % 15 + 1) % 16
    .transfer (accountId sender) (accountId receiver) (index % 7 + 1)

private def validateAction (index : Nat) (action : CorpusAction) : Bool :=
  if index % 5 = 0 then
    action.kind == "increment" && action.caller == some (index / 5 % 16)
  else
    let sender := index % 16
    let receiver := (sender + index % 15 + 1) % 16
    action.kind == "transfer" && action.sender == some sender &&
      action.receiver == some receiver && action.amount == some (index % 7 + 1)

private def validateVectors (vectors : NearcoreVectors) : Except String Unit := do
  let account := AccountV1.borsh {
    amount := 123
    locked := 45
    codeHash := List.replicate 32 7
    storageUsage := 99
  }
  require (Hex.encode account == vectors.accountV1) "nearcore AccountV1 encoding mismatch"
  let receipt := DataReceipt.borsh {
    predecessorId := "alice".toUTF8.toList
    receiverId := "bob".toUTF8.toList
    receiptId := List.replicate 32 3
    dataId := List.replicate 32 4
    data := some [5, 6]
  }
  require (Hex.encode receipt == vectors.dataReceipt) "nearcore data-receipt encoding mismatch"
  let outcome := ExecutionOutcome.borsh {
    logs := ["log".toUTF8.toList]
    receiptIds := [List.replicate 32 3]
    gasBurnt := 7
    tokensBurnt := 11
    executorId := "bob".toUTF8.toList
    status := .value [8, 9]
  }
  require (Hex.encode outcome == vectors.executionOutcome)
    "nearcore execution-outcome encoding mismatch"
  let receiptId := createReceiptIdFromTransaction (List.replicate 32 1) 9
  require (Hex.encode receiptId == vectors.receiptId) "nearcore receipt-ID derivation mismatch"

private def validateNegativeVectors : Except String Unit := do
  require (Hex.decode "0").isNone "odd-length hexadecimal was accepted"
  require (Hex.decode "gg").isNone "non-hexadecimal input was accepted"

private def validateChunks (corpus : Corpus) : Except String Unit := do
  require (corpus.schemaVersion == 1) "unsupported concrete corpus schema"
  require (corpus.nearcoreCommit == "5af9ca74631e6cf0dae33e77d1a632e94d2952ce")
    "concrete corpus nearcore commit mismatch"
  require (corpus.protocolVersion == 86) "concrete corpus protocol mismatch"
  require (corpus.chunkCount == 1000 && corpus.chunks.length == 1000)
    "concrete corpus does not contain 1,000 chunks"
  let initialRecords ← corpus.initialRecords.mapM decodeRecord
  require (initialState.records == initialRecords) "concrete genesis records mismatch"
  let _ ← corpus.chunks.foldlM (fun (state : State) (expected : CorpusChunk) => do
    require (expected.index < 1000) "chunk index is out of range"
    require (validateAction expected.index expected.action) s!"chunk {expected.index} action mismatch"
    let chunk := applyChunk RuntimeConfig.default expected.index state (inputAt expected.index)
    let output ← match chunk.serializedOutcome with
      | some value => pure value
      | none => throw s!"chunk {expected.index} unexpectedly failed"
    let expectedChanges ← expected.changes.mapM decodeChange
    require (chunk.changes == expectedChanges) s!"chunk {expected.index} state changes differ"
    require (Hex.encode (stateChangesBorsh chunk.changes) == expected.stateChangesBorsh)
      s!"chunk {expected.index} state-change bytes differ"
    require (Hex.encode output == expected.serializedOutcome)
      s!"chunk {expected.index} outcome bytes differ"
    let transactionHash := Concrete.hash s!"transaction:{expected.index}".toUTF8.toList
    let receiptId := createReceiptIdFromTransaction transactionHash (expected.index + 1)
    require (Hex.encode receiptId == expected.receiptId)
      s!"chunk {expected.index} receipt ID differs"
    require (Hex.encode chunk.stateRoot == expected.stateRoot)
      s!"chunk {expected.index} state root differs"
    return chunk.after) initialState
  pure ()

def validate (source : String) : Except String Unit := do
  let json ← Json.parse source
  let corpus : Corpus ← fromJson? json
  validateNegativeVectors
  validateVectors corpus.nearcoreVectors
  validateChunks corpus

end NEARLean.M11Validation

def main : IO UInt32 := do
  let source ← IO.FS.readFile "concrete/synthetic-chunks.json"
  match NEARLean.M11Validation.validate source with
  | .error message => throw <| IO.userError message
  | .ok () =>
      IO.println "{\"schemaVersion\":1,\"observationLevel\":\"L7\",\"chunks\":1000,\"rootsMatched\":1000,\"serializationVectors\":4,\"negativeVectors\":2,\"refinementTheorems\":1}"
      return 0
