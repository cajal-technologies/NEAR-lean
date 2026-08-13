(module
  (import "env" "input" (func $input (param i64)))
  (import "env" "current_account_id" (func $current_account_id (param i64)))
  (import "env" "register_len" (func $register_len (param i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "promise_create"
    (func $promise_create
      (param i64 i64 i64 i64 i64 i64 i64 i64)
      (result i64)))
  (import "env" "promise_then"
    (func $promise_then
      (param i64 i64 i64 i64 i64 i64 i64 i64 i64)
      (result i64)))
  (import "env" "promise_return" (func $promise_return (param i64)))
  (import "env" "promise_result" (func $promise_result (param i64 i64) (result i64)))

  (memory (export "memory") 1)
  (data (i32.const 0) "echo")
  (data (i32.const 8) "callback")
  (data (i32.const 24) "\07")

  (func (export "call_then") (local $target_len i64) (local $self_len i64)
    (local $promise i64) (local $callback i64)
    i64.const 0
    call $input
    i64.const 0
    call $register_len
    local.set $target_len
    i64.const 0
    i64.const 64
    call $read_register
    local.get $target_len
    i64.const 64
    i64.const 4
    i64.const 0
    i64.const 0
    i64.const 0
    i64.const 32
    i64.const 30000000000000
    call $promise_create
    local.set $promise
    i64.const 1
    call $current_account_id
    i64.const 1
    call $register_len
    local.set $self_len
    i64.const 1
    i64.const 128
    call $read_register
    local.get $promise
    local.get $self_len
    i64.const 128
    i64.const 8
    i64.const 8
    i64.const 0
    i64.const 0
    i64.const 32
    i64.const 30000000000000
    call $promise_then
    local.set $callback
    local.get $callback
    call $promise_return)

  (func (export "echo")
    i64.const 1
    i64.const 24
    call $value_return)

  (func (export "callback") (local $status i64) (local $length i64)
    i64.const 0
    i64.const 0
    call $promise_result
    local.set $status
    local.get $status
    i64.const 1
    i64.eq
    if
      i64.const 0
      call $register_len
      local.set $length
      i64.const 0
      i64.const 256
      call $read_register
      local.get $length
      i64.const 256
      call $value_return
    end))
