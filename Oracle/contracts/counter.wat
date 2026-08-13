(module
  (import "env" "storage_read"
    (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_write"
    (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "register_len"
    (func $register_len (param i64) (result i64)))
  (import "env" "read_register"
    (func $read_register (param i64 i64)))
  (import "env" "value_return"
    (func $value_return (param i64 i64)))
  (import "env" "log_utf8"
    (func $log_utf8 (param i64 i64)))

  (memory (export "memory") 1)
  (data (i32.const 0) "\01")

  (func (export "init")
    i64.const 1
    i64.const 0
    i64.const 0
    i64.const 16
    i64.const 0
    call $storage_write
    drop)

  (func (export "increment") (local $length i64)
    i64.const 1
    i64.const 0
    i64.const 0
    call $storage_read
    drop
    i64.const 0
    call $register_len
    local.set $length
    i64.const 0
    i64.const 32
    call $read_register
    i32.const 32
    local.get $length
    i32.wrap_i64
    i32.add
    i32.const 0
    i32.store8
    i64.const 1
    i64.const 0
    local.get $length
    i64.const 1
    i64.add
    i64.const 32
    i64.const 1
    call $storage_write
    drop
    local.get $length
    i64.const 1
    i64.add
    i64.const 32
    call $value_return
    i64.const 1
    i64.const 0
    call $log_utf8)

  (func (export "get") (local $length i64)
    i64.const 1
    i64.const 0
    i64.const 0
    call $storage_read
    drop
    i64.const 0
    call $register_len
    local.set $length
    i64.const 0
    i64.const 32
    call $read_register
    local.get $length
    i64.const 32
    call $value_return)

  (func (export "trap")
    unreachable))
