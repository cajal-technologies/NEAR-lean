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

private def funded (amount : Balance) : Account :=
  { Account.initial with balance := amount }

private def runTransferScenarios (config : RuntimeConfig) : IO Unit := do
  for amount in List.range 100 do
    let chain ← expectInit <| NearChain.init config [([1], funded amount), ([2], Account.initial)]
    let (chain, result) := chain.transfer [1] [2] amount
    let _ ← expectOk result
    assertEqual (some 0) (chain.balance? [1])
    assertEqual (some amount) (chain.balance? [2])

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

  runTransferScenarios config
  IO.println "100 transfer scenarios and Milestone 2-4 API tests passed"
