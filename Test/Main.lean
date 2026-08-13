import NEARLean

open NEARLean

private def assertEqual [BEq α] [Repr α] (expected actual : α) : IO Unit :=
  if expected == actual then
    pure ()
  else
    throw <| IO.userError s!"expected {repr expected}, got {repr actual}"

private def expectOk : Except RuntimeError Output → IO Output
  | .ok output => pure output
  | .error runtimeError =>
      throw <| IO.userError s!"expected success, got {repr runtimeError}"

private def expectInit : Except RuntimeError NearChain → IO NearChain
  | .ok chain => pure chain
  | .error runtimeError =>
      throw <| IO.userError s!"expected valid genesis, got {repr runtimeError}"

private def expectValue [BEq α] [Repr α]
    (expected : α) : Except RuntimeError α → IO Unit
  | .ok actual => assertEqual expected actual
  | .error runtimeError =>
      throw <| IO.userError s!"expected {repr expected}, got {repr runtimeError}"

private def expectInitError
    (expected : RuntimeError) : Except RuntimeError NearChain → IO Unit
  | .error actual => assertEqual expected actual
  | .ok chain => throw <| IO.userError s!"expected {repr expected}, got {repr chain}"

private def expectError
    (expected : RuntimeError)
    (before : NearChain)
    (transition : NearChain × Except RuntimeError Output) : IO Unit := do
  assertEqual before transition.1
  match transition.2 with
  | .error actual => assertEqual expected actual
  | .ok output => throw <| IO.userError s!"expected {repr expected}, got {repr output}"

private def expectEconomicError
    (expected : EconomicError) : Except EconomicError Unit → IO Unit
  | .error actual => assertEqual expected actual
  | .ok _ => throw <| IO.userError s!"expected {repr expected}, got success"

private def expectWasmSuccess
    (result : Except WasmExecution.Error (WasmExecution.Run WasmHost.State)) :
    IO (WasmHost.State × List String) :=
  match result with
  | .ok run => match run.outcome with
    | .success _ store => pure (store.host, run.instructionTrace)
    | .trap message => throw <| IO.userError s!"expected WASM success, trapped: {message}"
  | .error error => throw <| IO.userError s!"expected WASM success, got {repr error}"

private def funded (amount : Balance) : Account :=
  { Account.initial with balance := amount }

private def runTransferScenarios (config : RuntimeConfig) : IO Unit := do
  for amount in List.range 100 do
    let chain ← expectInit <| NearChain.init config [([1], funded amount), ([2], Account.initial)]
    let (chain, result) := chain.transfer [1] [2] amount
    let _ ← expectOk result
    assertEqual (some 0) (chain.balance? [1])
    assertEqual (some amount) (chain.balance? [2])

private def generatedBlocks : Nat → BlockScheduler → BlockScheduler
  | 0, scheduler => scheduler
  | count + 1, scheduler =>
      let transaction : Transaction := {
        signerId := [1]
        receiverId := [2]
        actions := [.transfer [1] [2] 0]
      }
      generatedBlocks count (scheduler.submit transaction).produceBlock

def main : IO Unit := do
  assertEqual "abstract" (SemanticsLayer.label .abstract)
  assertEqual "concrete-compatibility" (SemanticsLayer.label .concreteCompatibility)
  let config := RuntimeConfig.default
  let empty := NearChain.initEmpty config

  assertEqual true (WorldState.WellFormed config empty.state |> decide)
  assertEqual false (AccountId.WellFormed config [] |> decide)
  assertEqual false (Storage.WellFormed config [([1], [2]), ([1], [3])] |> decide)
  expectInitError .invalidInitialState (NearChain.init config [([], Account.initial)])

  let creator ← expectInit <| NearChain.init config [([1], funded 10)]
  let (created, createResult) := creator.createAccount [1] [2] 4
  let _ ← expectOk createResult
  assertEqual (some 6) (created.balance? [1])
  assertEqual (some 4) (created.balance? [2])
  expectError (.accountAlreadyExists [2]) created (created.createAccount [1] [2] 0)
  expectError (.invalidAccountId []) created (created.createAccount [1] [] 0)
  expectError (.insufficientBalance [1]) creator (creator.createAccount [1] [2] 11)
  expectError (.accountNotFound [3]) creator (creator.createAccount [3] [2] 0)

  let chain ← expectInit <| NearChain.init config [([1], funded 10), ([2], Account.initial)]
  let (transferred, transferResult) := chain.transfer [1] [2] 4
  let _ ← expectOk transferResult
  assertEqual (some 6) (transferred.balance? [1])
  assertEqual (some 4) (transferred.balance? [2])
  expectError (.insufficientBalance [1]) chain (chain.transfer [1] [2] 11)
  expectError (.accountNotFound [3]) chain (chain.transfer [1] [3] 1)
  let (selfTransfer, selfResult) := chain.transfer [1] [1] 10
  let _ ← expectOk selfResult
  assertEqual chain selfTransfer

  let overflowChain ← expectInit <| NearChain.init config
    [([1], funded 1), ([2], funded config.maxAccountBalance)]
  expectError (.balanceOverflow [2]) overflowChain (overflowChain.transfer [1] [2] 1)

  let counterGenesis := [([1], funded 10), ([2], Account.initial)]
  let counterChain ← expectInit <| NearChain.init config counterGenesis
  let (counterChain, deployResult) := counterChain.deploy [1] [2] NativeContract.counterId
  let _ ← expectOk deployResult
  expectError (.contractAlreadyDeployed [2]) counterChain
    (counterChain.deploy [1] [2] NativeContract.counterId)
  let (counterChain, incrementResult) := counterChain.call [1] [2] NativeMethod.increment
  let incrementOutput ← expectOk incrementResult
  assertEqual [0] incrementOutput.returnValue
  assertEqual [[1]] incrementOutput.logs
  let (counterChain, secondIncrement) := counterChain.call [1] [2] NativeMethod.increment
  let secondOutput ← expectOk secondIncrement
  assertEqual [0, 0] secondOutput.returnValue
  let (viewedChain, viewResult) := counterChain.view [2] NativeMethod.get
  let viewOutput ← expectOk viewResult
  assertEqual counterChain viewedChain
  assertEqual [0, 0] viewOutput.returnValue
  expectError (.methodNotFound [99]) counterChain
    (counterChain.call [1] [2] [99])
  expectError .invalidGas counterChain
    (counterChain.call [1] [2] NativeMethod.increment [] 0 0)

  let escrowGenesis :=
    [([1], funded 10), ([2], Account.initial), ([3], Account.initial), ([4], Account.initial)]
  let escrowChain ← expectInit <| NearChain.init config escrowGenesis
  let (escrowChain, escrowDeploy) := escrowChain.deploy [1] [2] NativeContract.escrowId
  let _ ← expectOk escrowDeploy
  expectError .depositRequired escrowChain
    (escrowChain.call [1] [2] NativeMethod.deposit)
  let (escrowChain, depositResult) := escrowChain.call [1] [2] NativeMethod.deposit [] 4
  let _ ← expectOk depositResult
  assertEqual (some 6) (escrowChain.balance? [1])
  assertEqual (some 4) (escrowChain.balance? [2])
  expectError .unauthorized escrowChain
    (escrowChain.call [4] [2] NativeMethod.release [3])
  expectError .invalidArguments escrowChain
    (escrowChain.call [1] [2] NativeMethod.release [])
  let (escrowChain, releaseResult) := escrowChain.call [1] [2] NativeMethod.release [3]
  let releaseOutput ← expectOk releaseResult
  assertEqual (some 4) releaseOutput.balance
  assertEqual (some 0) (escrowChain.balance? [2])
  assertEqual (some 4) (escrowChain.balance? [3])
  let (viewedEscrow, balanceView) := escrowChain.view [2] NativeMethod.balance
  let balanceOutput ← expectOk balanceView
  assertEqual escrowChain viewedEscrow
  assertEqual (some 0) balanceOutput.balance

  expectValue [0] counterExample
  expectValue 4 escrowExample

  let receiptWorld := { WorldState.initial config with
    accounts := [([1], funded 10), ([2], asyncAccount), ([3], asyncAccount)] }
  let receiptTransaction : Transaction := {
    signerId := [1]
    receiverId := [2]
    actions := [.functionCall [1] [2] NativeMethod.callThen [3] 0 10]
  }
  let receiptMachine := (ReceiptMachine.init receiptWorld).submit config receiptTransaction
  assertEqual true (receiptMachine.WellFormed config |> decide)
  assertEqual 1 receiptMachine.queued.length
  let receiptMachine := receiptMachine.processOne config
  assertEqual 2 receiptMachine.queued.length
  assertEqual 1 receiptMachine.outcomes.length
  let receiptMachine := receiptMachine.processOne config
  assertEqual 2 receiptMachine.queued.length
  assertEqual 2 receiptMachine.outcomes.length
  let receiptMachine := receiptMachine.processOne config
  assertEqual 1 receiptMachine.queued.length
  assertEqual 1 receiptMachine.postponed.length
  assertEqual 2 receiptMachine.outcomes.length
  let receiptMachine := receiptMachine.processOne config
  assertEqual 0 receiptMachine.queued.length
  assertEqual 0 receiptMachine.postponed.length
  assertEqual 4 receiptMachine.completed.length
  assertEqual true (receiptMachine.WellFormed config |> decide)
  assertEqual crossContractExample receiptMachine.outcomes
  match receiptMachine.outcomes.getLast? with
  | some outcome => assertEqual (ReceiptExecutionStatus.successValue [7]) outcome.status
  | none => throw <| IO.userError "missing callback outcome"

  let failedPromise : ActionReceipt := {
    signerId := [1]
    outputDataReceivers := []
    inputDataIds := [9]
    actions := []
  }
  let receivedFailure : ReceivedData := { receiverId := [2], dataId := 9, data := none }
  let promiseMachine := { ReceiptMachine.init receiptWorld with
    receivedData := [receivedFailure] }
  assertEqual [.failed] (failedPromise.promiseResults promiseMachine [2])

  let failedTransaction : Transaction := {
    signerId := [1]
    receiverId := [3]
    actions := [.transfer [1] [3] 11]
  }
  let failedMachine :=
    (ReceiptMachine.init receiptWorld).submit config failedTransaction |>.processOne config
  assertEqual receiptWorld failedMachine.world
  match failedMachine.completed.getLast? with
  | some completed =>
      assertEqual (ReceiptDisposition.discarded (.insufficientBalance [1]))
        completed.disposition
  | none => throw <| IO.userError "missing discarded receipt"

  let scheduler := BlockScheduler.init config receiptWorld 10
  assertEqual true (scheduler.WellFormed |> decide)
  let scheduler := scheduler.submit receiptTransaction |>.runUntil 3
  assertEqual 3 scheduler.blocks.length
  assertEqual 3 scheduler.machine.world.block.height
  assertEqual 0 scheduler.delayedReceipts.length
  assertEqual 0 scheduler.machine.postponed.length
  assertEqual [0, 1, 2]
    (scheduler.blocks.flatMap (·.outcomes) |>.map (·.blockHeight))
  match scheduler.outcome? 2 with
  | some outcome =>
      assertEqual 2 outcome.blockHeight
      assertEqual (ReceiptExecutionStatus.successValue [7]) outcome.outcome.status
  | none => throw <| IO.userError "missing scheduled callback outcome"

  let emptyTransaction : Transaction := {
    signerId := [1]
    receiverId := [2]
    actions := []
  }
  let ordered := BlockScheduler.init config receiptWorld 10
    |>.enqueue .delayed emptyTransaction
    |>.receive emptyTransaction
    |>.submit emptyTransaction
    |>.produceBlock
  match ordered.blocks.getLast? with
  | some block =>
      assertEqual [.local, .delayed, .incoming] (block.processed.map (·.source))
      assertEqual [2, 0, 1] (block.processed.map (·.receiptId))
  | none => throw <| IO.userError "missing processing-order block"

  let bounded := BlockScheduler.init config receiptWorld 1
    |>.submit emptyTransaction
    |>.submit emptyTransaction
    |>.submit emptyTransaction
    |>.produceBlock
  assertEqual 1 (bounded.blocks.flatMap (·.processed)).length
  assertEqual 2 bounded.delayedReceipts.length

  let zeroBound := BlockScheduler.init config receiptWorld 0
    |>.submit emptyTransaction
    |>.runUntil 5
  assertEqual 5 zeroBound.blocks.length
  assertEqual 1 zeroBound.delayedReceipts.length
  assertEqual 0 zeroBound.machine.outcomes.length

  let replayStart := BlockScheduler.init config receiptWorld 1
  let firstReplay := generatedBlocks 1000 replayStart
  let secondReplay := generatedBlocks 1000 replayStart
  assertEqual firstReplay secondReplay
  assertEqual 1000 firstReplay.blocks.length
  assertEqual 1000 firstReplay.machine.world.block.height

  let counterState : Benchmarks.Counter.State := { value := 4, isolated := 9 }
  let (counterState, counterValue) :=
    Benchmarks.Counter.step counterState (.increment 7)
  assertEqual 5 counterValue
  assertEqual 9 counterState.isolated

  let escrowState : Benchmarks.Escrow.State := {
    owner := 1
    balance := 3
    released := 0
    deposited := 3
  }
  let (unauthorizedEscrow, unauthorizedResult) :=
    Benchmarks.Escrow.step escrowState (.release 2)
  assertEqual escrowState unauthorizedEscrow
  assertEqual Benchmarks.Escrow.Result.unauthorized unauthorizedResult

  let tokenState : Benchmarks.FungibleToken.State := {
    aliceBalance := 7
    bobBalance := 3
    totalSupply := 10
  }
  let transfer : Benchmarks.FungibleToken.Action := {
    caller := Benchmarks.FungibleToken.alice
    receiver := Benchmarks.FungibleToken.bob
    amount := 2
  }
  let (tokenState, tokenResult) := Benchmarks.FungibleToken.step tokenState transfer
  assertEqual Benchmarks.FungibleToken.Result.transferred tokenResult
  assertEqual 10 (tokenState.aliceBalance + tokenState.bobBalance)
  assertEqual Verification.UpgradePolicy.forbidden
    Verification.BlockchainThreatModel.milestoneSix.upgrades

  let economicConfig : EconomicConfig := {
    EconomicConfig.protocol86Sandbox with
    gasPrice := 1
    storagePricePerByte := 2
    maxGas := 100
  }
  let economicInitial : EconomicState := { liquid := 1000 }
  assertEqual true (economicInitial.WellFormed economicConfig |> decide)
  expectEconomicError .prepaidGasExceeded
    (economicInitial.step economicConfig (.lockCall 0 101)).2
  expectEconomicError .insufficientBalance
    (economicInitial.step economicConfig (.lockCall 1001 1)).2
  expectEconomicError .outOfGas
    (economicInitial.step economicConfig (.settleGas 10 11 10)).2
  expectEconomicError .insufficientGasEscrow
    (economicInitial.step economicConfig (.settleGas 10 10 10)).2
  expectEconomicError .insufficientCarriedDeposit
    (economicInitial.step economicConfig (.deliverDeposit 1)).2
  expectEconomicError .insufficientRefund
    (economicInitial.step economicConfig (.claimRefund 1)).2
  expectEconomicError .insufficientStorageStake
    (economicInitial.step economicConfig (.releaseStorage 1)).2
  let economicState := (economicInitial.step economicConfig (.lockCall 10 100)).1
  let economicState := (economicState.step economicConfig (.settleGas 100 60 50)).1
  let economicState := (economicState.step economicConfig (.claimRefund 50)).1
  let economicState := (economicState.step economicConfig (.deliverDeposit 10)).1
  let economicState := (economicState.step economicConfig (.stakeStorage 10)).1
  let economicState := (economicState.step economicConfig (.releaseStorage 10)).1
  assertEqual economicInitial.totalTokens economicState.totalTokens
  assertEqual 60 economicState.gasUsed
  assertEqual 50 economicState.gasBurnt
  assertEqual true (economicState.WellFormed economicConfig |> decide)

  let carriedTransaction : Transaction := {
    signerId := [1]
    receiverId := [2]
    actions := [.functionCall [1] [2] NativeMethod.increment [] 4 10]
  }
  let carriedMachine := (ReceiptMachine.init receiptWorld).submit config carriedTransaction
  assertEqual 4 carriedMachine.carriedBalance

  let (wasmState, initTrace) ← expectWasmSuccess <| WasmHost.runCounter {} "init"
  assertEqual [([1], [])] wasmState.storageEntries
  let (wasmState, incrementTrace) ← expectWasmSuccess <|
    WasmHost.runCounter wasmState "increment"
  assertEqual (some [0]) wasmState.returnData
  assertEqual [[1]] wasmState.logs
  assertEqual [([1], [0])] wasmState.storageEntries
  let (wasmState, getTrace) ← expectWasmSuccess <| WasmHost.runCounter wasmState "get"
  assertEqual (some [0]) wasmState.returnData
  assertEqual [] wasmState.logs
  assertEqual true ("i32.store8" ∈ incrementTrace)
  assertEqual true ("host.0" ∈ incrementTrace)
  assertEqual true ("host.5" ∈ incrementTrace)
  let replay ← expectWasmSuccess <|
    WasmHost.runCounter (.ofStorage [([1], [])]) "increment"
  assertEqual wasmState.storageEntries replay.1.storageEntries
  assertEqual incrementTrace replay.2
  match WasmHost.runCounter wasmState "missing" with
  | .error (.missingExport "missing") => pure ()
  | _ => throw <| IO.userError "expected a missing WASM export error"
  match WasmHost.runCounter wasmState "trap" with
  | .ok { outcome := .trap "unreachable", instructionTrace := trace } =>
      assertEqual true ("unreachable" ∈ trace)
  | _ => throw <| IO.userError "expected an explicit WASM unreachable trap"
  match WasmExecution.decodeAndValidate "not a module" with
  | .error (.decode _) => pure ()
  | _ => throw <| IO.userError "malformed WASM source was not rejected"
  match WasmExecution.decodeAndValidate "(module (func (export \"bad\") local.get 0))" with
  | .error (.invalid _) => pure ()
  | _ => throw <| IO.userError "invalid WASM module was not rejected"
  assertEqual true (initTrace.length > 0)
  assertEqual true (getTrace.length > 0)

  runTransferScenarios config
  IO.println "100 transfer scenarios and Milestone 2-10 API tests passed"
