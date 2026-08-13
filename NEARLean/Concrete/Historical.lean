import Lean.Data.Json
import NEARLean.Concrete.State

namespace NEARLean.Concrete.Historical

open Lean

structure Block where
  height : Nat
  hash : String
  prevHash : String
  prevHeight : Nat
  protocolVersion : Nat
  prevStateRoot : String
  outcomeRoot : String
  chunksIncluded : Nat
  chunkMask : Array Bool
  sourceSha256 : String
  deriving FromJson, Repr

structure ChunkHeader where
  blockHeight : Nat
  blockHash : String
  shardId : Nat
  chunkHash : String
  heightCreated : Nat
  heightIncluded : Nat
  inputStateRoot : String
  outputStateRoot : Option String := none
  outcomeRoot : String
  transactionRoot : String
  gasUsed : Nat
  transactions : Nat
  receipts : Nat
  outcomes : Nat
  stateChanges : Nat
  deriving FromJson, Repr

structure Chunk where
  header : ChunkHeader
  transactions : Array Json
  receipts : Array Json
  outcomes : Array Json
  stateChanges : Array Json
  deriving FromJson

structure Fixture where
  schemaVersion : Nat
  network : String
  protocolVersion : Nat
  preStateKind : String
  blocks : Array Block := #[]
  samples : Array Chunk
  deriving FromJson

def importFixture (source : String) : Except String Fixture := do
  let json ← Json.parse source
  fromJson? json

def Fixture.wellFormed (fixture : Fixture) : Bool :=
  fixture.schemaVersion == 1 && fixture.network == "mainnet" &&
    fixture.protocolVersion == 86 && !fixture.samples.isEmpty &&
    fixture.samples.all fun chunk =>
      chunk.header.heightIncluded == chunk.header.blockHeight &&
        !chunk.header.blockHash.isEmpty && !chunk.header.chunkHash.isEmpty &&
        !chunk.header.inputStateRoot.isEmpty

def Chunk.importedTransactions (chunk : Chunk) : Array Json := chunk.transactions

def Chunk.importedReceipts (chunk : Chunk) : Array Json := chunk.receipts

def Chunk.importedOutcomes (chunk : Chunk) : Array Json := chunk.outcomes

def Chunk.importedPreStateRoot (chunk : Chunk) : String := chunk.header.inputStateRoot

def Chunk.importedStateChanges (chunk : Chunk) : Array Json := chunk.stateChanges

end NEARLean.Concrete.Historical
