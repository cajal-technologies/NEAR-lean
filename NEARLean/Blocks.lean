import NEARLean.Receipts

/-!
# Single-shard block scheduling

Each block processes local receipts, then receipts delayed from earlier blocks,
then new incoming receipts. Receipts created during execution become delayed work for the
next block. The scheduler advances an explicit block context after every block.
-/

namespace NEARLean

inductive ReceiptSource where
  | local
  | incoming
  | delayed
  deriving BEq, DecidableEq, Repr

structure ProcessedReceipt where
  source : ReceiptSource
  receiptId : ReceiptId
  deriving BEq, Repr

structure BlockOutcome where
  blockHeight : Nat
  outcome : ReceiptOutcome
  deriving BEq, Repr

structure ProducedBlock where
  height : Nat
  processed : List ProcessedReceipt
  outcomes : List BlockOutcome
  delayedCount : Nat
  postponedCount : Nat
  deriving BEq, Repr

structure BlockScheduler where
  config : RuntimeConfig
  machine : ReceiptMachine
  localReceipts : List Receipt := []
  incomingReceipts : List Receipt := []
  delayedReceipts : List Receipt := []
  maxReceiptsPerBlock : Nat
  blocks : List ProducedBlock := []
  deriving BEq, Repr

def BlockScheduler.allReceiptIds (state : BlockScheduler) : List ReceiptId :=
  state.localReceipts.map (·.receiptId) ++
    state.incomingReceipts.map (·.receiptId) ++
    state.delayedReceipts.map (·.receiptId) ++
    state.machine.postponed.map (·.receiptId) ++
    state.machine.completed.map (·.receipt.receiptId)

def BlockScheduler.SchedulingInvariant (state : BlockScheduler) : Prop :=
  (state.delayedReceipts.map (·.receiptId)).Nodup ∧
    (state.machine.postponed.map (·.receiptId)).Nodup ∧
    (state.delayedReceipts.map (·.receiptId) ++
      state.machine.postponed.map (·.receiptId)).Nodup

def BlockScheduler.WellFormed (state : BlockScheduler) : Prop :=
  state.machine.world.WellFormed state.config ∧
    state.allReceiptIds.Nodup ∧
    state.allReceiptIds.all (· < state.machine.nextReceiptId) = true ∧
    (state.machine.receivedData.map fun entry => (entry.receiverId, entry.dataId)).Nodup ∧
    state.SchedulingInvariant

instance BlockScheduler.instDecidableWellFormed
    (state : BlockScheduler) : Decidable state.WellFormed := by
  unfold BlockScheduler.WellFormed BlockScheduler.SchedulingInvariant
  infer_instance

def BlockScheduler.init
    (config : RuntimeConfig)
    (world : WorldState)
    (maxReceiptsPerBlock : Nat) : BlockScheduler := {
  config := config
  machine := ReceiptMachine.init world
  maxReceiptsPerBlock := maxReceiptsPerBlock
}

theorem BlockScheduler.init_wellFormed
    (config : RuntimeConfig)
    (world : WorldState)
    (maxReceiptsPerBlock : Nat)
    (worldValid : world.WellFormed config) :
    (BlockScheduler.init config world maxReceiptsPerBlock).WellFormed := by
  exact ⟨worldValid, List.Pairwise.nil, rfl, List.Pairwise.nil,
    List.Pairwise.nil, List.Pairwise.nil, List.Pairwise.nil⟩

def BlockScheduler.commit
    (before candidate : BlockScheduler) : BlockScheduler :=
  if candidate.WellFormed then candidate else before

def BlockScheduler.enqueueCandidate
    (source : ReceiptSource)
    (state : BlockScheduler)
    (transaction : Transaction) : BlockScheduler :=
  let receipt := transaction.toReceipt state.machine.nextReceiptId
  let machine := { state.machine with nextReceiptId := state.machine.nextReceiptId + 1 }
  match source with
  | .local => {
      state with machine := machine, localReceipts := state.localReceipts ++ [receipt] }
  | .incoming => {
      state with machine := machine, incomingReceipts := state.incomingReceipts ++ [receipt] }
  | .delayed => {
      state with machine := machine, delayedReceipts := state.delayedReceipts ++ [receipt] }

def BlockScheduler.enqueue
    (source : ReceiptSource)
    (state : BlockScheduler)
    (transaction : Transaction) : BlockScheduler :=
  state.commit (state.enqueueCandidate source transaction)

def BlockScheduler.submit
    (state : BlockScheduler) (transaction : Transaction) : BlockScheduler :=
  state.enqueue .local transaction

def BlockScheduler.receive
    (state : BlockScheduler) (transaction : Transaction) : BlockScheduler :=
  state.enqueue .incoming transaction

private def sources (source : ReceiptSource) (receipts : List Receipt) :
    List ProcessedReceipt :=
  receipts.map fun receipt => { source := source, receiptId := receipt.receiptId }

private def advanceBlock (world : WorldState) : WorldState :=
  { world with block := {
      world.block with
      height := world.block.height + 1
      timestamp := world.block.timestamp + 1
    }
  }

def BlockScheduler.produceCandidate (state : BlockScheduler) : BlockScheduler :=
  let work := state.localReceipts ++ state.delayedReceipts ++ state.incomingReceipts
  let orderedSources :=
    sources .local state.localReceipts ++
      sources .delayed state.delayedReceipts ++
      sources .incoming state.incomingReceipts
  let processedCount := min state.maxReceiptsPerBlock work.length
  let height := state.machine.world.block.height
  let previousOutcomeCount := state.machine.outcomes.length
  let machine := { state.machine with queued := work }
  let machine := machine.run state.config processedCount
  let newOutcomes := (machine.outcomes.drop previousOutcomeCount).map fun outcome => {
    blockHeight := height
    outcome := outcome
  }
  let delayed := machine.queued
  let machine := { machine with world := advanceBlock machine.world, queued := [] }
  let produced : ProducedBlock := {
    height := height
    processed := orderedSources.take processedCount
    outcomes := newOutcomes
    delayedCount := delayed.length
    postponedCount := machine.postponed.length
  }
  { state with
    machine := machine
    localReceipts := []
    incomingReceipts := []
    delayedReceipts := delayed
    blocks := state.blocks ++ [produced]
  }

def BlockScheduler.produceBlock (state : BlockScheduler) : BlockScheduler :=
  state.commit state.produceCandidate

def BlockScheduler.hasWork (state : BlockScheduler) : Bool :=
  !(state.localReceipts.isEmpty && state.incomingReceipts.isEmpty &&
    state.delayedReceipts.isEmpty)

def BlockScheduler.runUntil : Nat → BlockScheduler → BlockScheduler
  | 0, state => state
  | fuel + 1, state =>
      if state.hasWork then runUntil fuel state.produceBlock else state

def BlockScheduler.outcome? (state : BlockScheduler) (receiptId : ReceiptId) :
    Option BlockOutcome :=
  state.blocks.foldl (fun found block =>
    match found with
    | some outcome => some outcome
    | none => block.outcomes.find? (·.outcome.receiptId = receiptId)) none

theorem BlockScheduler.commit_preserves_wellFormed
    (before candidate : BlockScheduler)
    (beforeValid : before.WellFormed) :
    (before.commit candidate).WellFormed := by
  unfold BlockScheduler.commit
  split
  · assumption
  · exact beforeValid

theorem BlockScheduler.enqueue_preserves_wellFormed
    (source : ReceiptSource)
    (state : BlockScheduler)
    (transaction : Transaction)
    (stateValid : state.WellFormed) :
    (state.enqueue source transaction).WellFormed :=
  BlockScheduler.commit_preserves_wellFormed state
    (state.enqueueCandidate source transaction) stateValid

theorem BlockScheduler.produce_preserves_wellFormed
    (state : BlockScheduler)
    (stateValid : state.WellFormed) :
    state.produceBlock.WellFormed :=
  BlockScheduler.commit_preserves_wellFormed state state.produceCandidate stateValid

theorem BlockScheduler.runUntil_preserves_wellFormed
    (fuel : Nat)
    (state : BlockScheduler)
    (stateValid : state.WellFormed) :
    (state.runUntil fuel).WellFormed := by
  induction fuel generalizing state with
  | zero => exact stateValid
  | succ fuel ih =>
      unfold BlockScheduler.runUntil
      split
      · exact ih state.produceBlock (BlockScheduler.produce_preserves_wellFormed state stateValid)
      · exact stateValid

/-- Delayed and postponed receipt sets stay unique and disjoint after a block. -/
theorem BlockScheduler.delayed_postponed_invariant
    (state : BlockScheduler)
    (stateValid : state.WellFormed) :
    state.produceBlock.SchedulingInvariant :=
  (BlockScheduler.produce_preserves_wellFormed state stateValid).2.2.2.2

/-- Fixed block inputs and bounds determine exactly one next scheduler state. -/
theorem BlockScheduler.production_deterministic
    (state first second : BlockScheduler)
    (firstResult : state.produceBlock = first)
    (secondResult : state.produceBlock = second) :
    first = second := by
  rw [firstResult] at secondResult
  exact secondResult

end NEARLean
