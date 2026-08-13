(module
  (type (;0;) (func (param i64)))
  (type (;1;) (func (param i64) (result i64)))
  (type (;2;) (func (param i64 i64)))
  (type (;3;) (func (param i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
  (type (;4;) (func (param i64 i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
  (type (;5;) (func (param i64 i64) (result i64)))
  (type (;6;) (func))
  (import "env" "input" (func (;0;) (type 0)))
  (import "env" "current_account_id" (func (;1;) (type 0)))
  (import "env" "register_len" (func (;2;) (type 1)))
  (import "env" "read_register" (func (;3;) (type 2)))
  (import "env" "value_return" (func (;4;) (type 2)))
  (import "env" "promise_create" (func (;5;) (type 3)))
  (import "env" "promise_then" (func (;6;) (type 4)))
  (import "env" "promise_return" (func (;7;) (type 0)))
  (import "env" "promise_result" (func (;8;) (type 5)))
  (memory (;0;) 1)
  (export "memory" (memory 0))
  (export "call_then" (func 9))
  (export "echo" (func 10))
  (export "callback" (func 11))
  (func (;9;) (type 6)
    (local i64 i64 i64 i64)
    i64.const 0
    call 0
    i64.const 0
    call 2
    local.set 0
    i64.const 0
    i64.const 64
    call 3
    local.get 0
    i64.const 64
    i64.const 4
    i64.const 0
    i64.const 0
    i64.const 0
    i64.const 32
    i64.const 30000000000000
    call 5
    local.set 2
    i64.const 1
    call 1
    i64.const 1
    call 2
    local.set 1
    i64.const 1
    i64.const 128
    call 3
    local.get 2
    local.get 1
    i64.const 128
    i64.const 8
    i64.const 8
    i64.const 0
    i64.const 0
    i64.const 32
    i64.const 30000000000000
    call 6
    local.set 3
    local.get 3
    call 7
  )
  (func (;10;) (type 6)
    i64.const 1
    i64.const 24
    call 4
  )
  (func (;11;) (type 6)
    (local i64 i64)
    i64.const 0
    i64.const 0
    call 8
    local.set 0
    local.get 0
    i64.const 1
    i64.eq
    if ;; label = @1
      i64.const 0
      call 2
      local.set 1
      i64.const 0
      i64.const 256
      call 3
      local.get 1
      i64.const 256
      call 4
    end
  )
  (data (;0;) (i32.const 0) "echo")
  (data (;1;) (i32.const 8) "callback")
  (data (;2;) (i32.const 24) "\07")
)
