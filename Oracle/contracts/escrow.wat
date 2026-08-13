(module
  (import "env" "input" (func $input (param i64)))
  (import "env" "attached_deposit" (func $attached_deposit (param i64)))
  (import "env" "predecessor_account_id" (func $predecessor_account_id (param i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "storage_read" (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_remove" (func $storage_remove (param i64 i64 i64) (result i64)))
  (import "env" "register_len" (func $register_len (param i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "log_utf8" (func $log_utf8 (param i64 i64)))
  (memory (export "memory") 1)
  (data (i32.const 0) "balance")
  (data (i32.const 16) "deposit")
  (data (i32.const 24) "release")
  (func (export "init"))
  (func (export "deposit")
    i64.const 64 call $attached_deposit
    i64.const 7 i64.const 0 i64.const 16 i64.const 64 i64.const 0
    call $storage_write drop
    i64.const 16 i64.const 64 call $value_return
    i64.const 7 i64.const 16 call $log_utf8)
  (func (export "balance") (local $length i64)
    i64.const 7 i64.const 0 i64.const 0 call $storage_read drop
    i64.const 0 call $register_len local.set $length
    i64.const 0 i64.const 64 call $read_register
    local.get $length i64.const 64 call $value_return)
  (func (export "release") (local $length i64)
    i64.const 1 call $predecessor_account_id
    i64.const 0 call $input
    i64.const 0 call $register_len local.set $length
    i64.const 0 i64.const 128 call $read_register
    i64.const 7 i64.const 0 i64.const 2 call $storage_remove drop
    local.get $length i64.const 128 call $value_return
    i64.const 7 i64.const 24 call $log_utf8))
