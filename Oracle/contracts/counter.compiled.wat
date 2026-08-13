(module
  (type (;0;) (func (param i64 i64 i64) (result i64)))
  (type (;1;) (func (param i64 i64 i64 i64 i64) (result i64)))
  (type (;2;) (func (param i64) (result i64)))
  (type (;3;) (func (param i64 i64)))
  (type (;4;) (func))
  (import "env" "storage_read" (func (;0;) (type 0)))
  (import "env" "storage_write" (func (;1;) (type 1)))
  (import "env" "register_len" (func (;2;) (type 2)))
  (import "env" "read_register" (func (;3;) (type 3)))
  (import "env" "value_return" (func (;4;) (type 3)))
  (import "env" "log_utf8" (func (;5;) (type 3)))
  (memory (;0;) 1)
  (export "memory" (memory 0))
  (export "init" (func 6))
  (export "increment" (func 7))
  (export "get" (func 8))
  (export "trap" (func 9))
  (func (;6;) (type 4)
    i64.const 1
    i64.const 0
    i64.const 0
    i64.const 16
    i64.const 0
    call 1
    drop
  )
  (func (;7;) (type 4)
    (local i64)
    i64.const 1
    i64.const 0
    i64.const 0
    call 0
    drop
    i64.const 0
    call 2
    local.set 0
    i64.const 0
    i64.const 32
    call 3
    i32.const 32
    local.get 0
    i32.wrap_i64
    i32.add
    i32.const 0
    i32.store8
    i64.const 1
    i64.const 0
    local.get 0
    i64.const 1
    i64.add
    i64.const 32
    i64.const 1
    call 1
    drop
    local.get 0
    i64.const 1
    i64.add
    i64.const 32
    call 4
    i64.const 1
    i64.const 0
    call 5
  )
  (func (;8;) (type 4)
    (local i64)
    i64.const 1
    i64.const 0
    i64.const 0
    call 0
    drop
    i64.const 0
    call 2
    local.set 0
    i64.const 0
    i64.const 32
    call 3
    local.get 0
    i64.const 32
    call 4
  )
  (func (;9;) (type 4)
    unreachable
  )
  (data (;0;) (i32.const 0) "\01")
)
