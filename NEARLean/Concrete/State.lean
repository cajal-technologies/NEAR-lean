import NEARLean.Concrete.Trie

namespace NEARLean.Concrete

structure State where
  world : WorldState
  deriving BEq, Repr

def State.abstract (state : State) : WorldState := state.world

private def accountStorageUsage (accountId : AccountId) (account : Account) : Nat :=
  accountId.length + account.storage.foldl (fun total (entry : StorageKey × StorageValue) =>
    total + entry.1.length + entry.2.length) 0 +
      (account.contract.map List.length).getD 0

private def accountValue (accountId : AccountId) (account : Account) : Bytes :=
  AccountV1.borsh {
    amount := account.balance
    locked := account.locked
    codeHash := (account.contract.map hash).getD (List.replicate 32 0)
    storageUsage := accountStorageUsage accountId account
  }

private def accountRecords (entry : AccountId × Account) : List (Bytes × Bytes) :=
  let accountId := entry.1
  let account := entry.2
  let code := match account.contract with
    | none => []
    | some bytes => [(TrieKey.contractCode accountId, bytes)]
  let storage := account.storage.map fun item =>
    (TrieKey.contractData accountId item.1, item.2)
  (TrieKey.account accountId, accountValue accountId account) :: code ++ storage

def State.records (state : State) : List (Bytes × Bytes) :=
  state.world.accounts.flatMap accountRecords

def State.root (state : State) : CryptoHash := Trie.root state.records

structure StateChange where
  key : Bytes
  value : Option Bytes
  deriving BEq, Repr

private def lookupRecord (key : Bytes) : List (Bytes × Bytes) → Option Bytes
  | [] => none
  | entry :: rest => if entry.1 = key then some entry.2 else lookupRecord key rest

def stateChanges (before after : State) : List StateChange :=
  let oldRecords := before.records
  let newRecords := after.records
  let updates := newRecords.filterMap fun entry =>
    if lookupRecord entry.1 oldRecords = some entry.2 then none
    else some { key := entry.1, value := some entry.2 }
  let removals := oldRecords.filterMap fun entry =>
    if (lookupRecord entry.1 newRecords).isSome then none
    else some { key := entry.1, value := none }
  updates ++ removals

def StateChange.borsh (change : StateChange) : Bytes :=
  Borsh.bytes change.key ++ Borsh.option Borsh.bytes change.value

def stateChangesBorsh (changes : List StateChange) : Bytes :=
  Borsh.list StateChange.borsh changes

def executorId : Input → AccountId
  | .createAccount _ accountId _ => accountId
  | .transfer _ receiver _ => receiver
  | .deployContract _ accountId _ => accountId
  | .functionCall _ receiver _ _ _ _ => receiver

def outputOutcome (input : Input) (output : Output) : ExecutionOutcome := {
  logs := output.logs
  gasBurnt := output.gasBurnt
  executorId := executorId input
  status := .value output.returnValue
}

def concreteStep
    (config : RuntimeConfig)
    (state : State)
    (input : Input) : State × Except RuntimeError Output :=
  let result := NEARLean.step config state.world input
  ({ world := result.1 }, result.2)

def observe
    (result : State × Except RuntimeError Output) :
    WorldState × Except RuntimeError Output :=
  (result.1.abstract, result.2)

theorem concreteStep_refines_abstract
    (config : RuntimeConfig) (state : State) (input : Input) :
    observe (concreteStep config state input) =
      NEARLean.step config state.abstract input := by
  rfl

structure Chunk where
  index : Nat
  input : Input
  before : State
  after : State
  result : Except RuntimeError Output
  changes : List StateChange
  serializedOutcome : Option Bytes
  stateRoot : CryptoHash
  deriving Repr

def applyChunk
    (config : RuntimeConfig) (index : Nat) (before : State) (input : Input) : Chunk :=
  let stepped := concreteStep config before input
  let after := stepped.1
  let serializedOutcome := stepped.2.toOption.map fun output =>
    (outputOutcome input output).borsh
  {
    index
    input
    before
    after
    result := stepped.2
    changes := stateChanges before after
    serializedOutcome
    stateRoot := after.root
  }

end NEARLean.Concrete
