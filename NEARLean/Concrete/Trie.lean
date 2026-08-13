import NEARLean.Concrete.Types

namespace NEARLean.Concrete.Trie

open NEARLean.Concrete

abbrev Entry := Bytes × Bytes

structure Digest where
  hash : CryptoHash
  memoryUsage : Nat
  deriving BEq, Repr

def emptyDigest : Digest := { hash := List.replicate 32 0, memoryUsage := 0 }

def nibbles (value : Bytes) : List UInt8 :=
  value.flatMap fun byte => [UInt8.ofNat (byte.toNat / 16), UInt8.ofNat (byte.toNat % 16)]

private def packNibbles : List UInt8 → Bytes
  | first :: second :: rest =>
      UInt8.ofNat (first.toNat * 16 + second.toNat) :: packNibbles rest
  | [first] => [UInt8.ofNat (first.toNat * 16)]
  | [] => []

def encodeNibbles (value : List UInt8) (isLeaf : Bool) : Bytes :=
  let flag := if isLeaf then 32 else 0
  match value.length % 2, value with
  | 1, first :: rest =>
      UInt8.ofNat (flag + 16 + first.toNat) :: packNibbles rest
  | _, _ =>
      UInt8.ofNat flag :: packNibbles value

def commonPrefixLength : List UInt8 → List UInt8 → Nat
  | first :: firstRest, second :: secondRest =>
      if first = second then 1 + commonPrefixLength firstRest secondRest else 0
  | _, _ => 0

def commonPrefixAll : List Entry → Nat
  | [] => 0
  | (key, _) :: rest =>
      rest.foldl (fun count entry => min count (commonPrefixLength key entry.1)) key.length

def valueRef (value : Bytes) : Bytes := Borsh.u32 value.length ++ hash value

def leafBytes (key value : Bytes) (memoryUsage : Nat) : Bytes :=
  [0] ++ Borsh.bytes key ++ valueRef value ++ Borsh.u64 memoryUsage

def extensionBytes (key childHash : Bytes) (memoryUsage : Nat) : Bytes :=
  [3] ++ Borsh.bytes key ++ Borsh.fixed 32 childHash ++ Borsh.u64 memoryUsage

def branchBytes
    (value : Option Bytes)
    (children : List (Nat × Digest))
    (memoryUsage : Nat) : Bytes :=
  let bitmap := children.foldl (fun mask child => mask + 2 ^ child.1) 0
  let childHashes := children.flatMap fun child => Borsh.fixed 32 child.2.hash
  match value with
  | none => [1] ++ Borsh.u16 bitmap ++ childHashes ++ Borsh.u64 memoryUsage
  | some branchValue =>
      [2] ++ valueRef branchValue ++ Borsh.u16 bitmap ++ childHashes ++ Borsh.u64 memoryUsage

private def groupAt (index : Nat) (entries : List Entry) : List Entry :=
  entries.filterMap fun entry => match entry.1 with
    | [] => none
    | first :: rest => if first.toNat = index then some (rest, entry.2) else none

private def branchValue (entries : List Entry) : Option Bytes :=
  (entries.find? fun entry => entry.1.isEmpty).map (·.2)

def digestEntries : Nat → List Entry → Digest
  | 0, _ => emptyDigest
  | _, [] => emptyDigest
  | _, [(key, value)] =>
      let encoded := encodeNibbles key true
      let memoryUsage := 100 + 2 * encoded.length + value.length
      { hash := hash (leafBytes encoded value memoryUsage), memoryUsage }
  | fuel + 1, entries =>
      let prefixLength := commonPrefixAll entries
      if prefixLength > 0 then
        let shared := entries.head!.1.take prefixLength
        let stripped := entries.map fun entry => (entry.1.drop prefixLength, entry.2)
        let child := digestEntries fuel stripped
        let encoded := encodeNibbles shared false
        let memoryUsage := 50 + 2 * encoded.length + child.memoryUsage
        { hash := hash (extensionBytes encoded child.hash memoryUsage), memoryUsage }
      else
        let children := (List.range 16).filterMap fun index =>
          let group := groupAt index entries
          if group.isEmpty then none else some (index, digestEntries fuel group)
        let value := branchValue entries
        let directMemory := 50 + (value.map (fun bytes => 50 + bytes.length)).getD 0
        let memoryUsage := directMemory + children.foldl (fun total child =>
          total + child.2.memoryUsage) 0
        { hash := hash (branchBytes value children memoryUsage), memoryUsage }

def root (entries : List (Bytes × Bytes)) : CryptoHash :=
  let encodedEntries := entries.map fun entry => (nibbles entry.1, entry.2)
  let fuel := encodedEntries.foldl (fun maximum entry => max maximum entry.1.length) 0
  (digestEntries (fuel + 1) encodedEntries).hash

theorem root_deterministic (entries : List Entry) : root entries = root entries := rfl

end NEARLean.Concrete.Trie
