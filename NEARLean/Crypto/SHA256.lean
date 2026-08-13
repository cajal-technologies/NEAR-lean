namespace NEARLean.Crypto.SHA256

private def rotr (value : UInt32) (count : Nat) : UInt32 :=
  (value >>> UInt32.ofNat count) ||| (value <<< UInt32.ofNat (32 - count))

private def choose (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ ((~~~ x) &&& z)

private def majority (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)

private def bigSigma0 (x : UInt32) : UInt32 := rotr x 2 ^^^ rotr x 13 ^^^ rotr x 22
private def bigSigma1 (x : UInt32) : UInt32 := rotr x 6 ^^^ rotr x 11 ^^^ rotr x 25
private def smallSigma0 (x : UInt32) : UInt32 := rotr x 7 ^^^ rotr x 18 ^^^ (x >>> 3)
private def smallSigma1 (x : UInt32) : UInt32 := rotr x 17 ^^^ rotr x 19 ^^^ (x >>> 10)

private def constants : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

private structure Working where
  a : UInt32
  b : UInt32
  c : UInt32
  d : UInt32
  e : UInt32
  f : UInt32
  g : UInt32
  h : UInt32

private def byteAt (bytes : List UInt8) (index : Nat) : UInt32 :=
  UInt32.ofNat (bytes.getD index 0).toNat

private def wordAt (bytes : List UInt8) (index : Nat) : UInt32 :=
  (byteAt bytes index <<< 24) ||| (byteAt bytes (index + 1) <<< 16) |||
    (byteAt bytes (index + 2) <<< 8) ||| byteAt bytes (index + 3)

private def schedule (block : List UInt8) : Array UInt32 :=
  let first := (List.range 16).foldl
    (fun words index => words.set! index (wordAt block (index * 4)))
    (Array.replicate 64 0)
  (List.range 48).foldl (fun words offset =>
    let index := offset + 16
    words.set! index (smallSigma1 words[index - 2]! + words[index - 7]! +
      smallSigma0 words[index - 15]! + words[index - 16]!)) first

private def compress (state : Working) (block : List UInt8) : Working :=
  let words := schedule block
  let result := (List.range 64).foldl (fun current index =>
    let first := current.h + bigSigma1 current.e + choose current.e current.f current.g +
      constants[index]! + words[index]!
    let second := bigSigma0 current.a + majority current.a current.b current.c
    { a := first + second
      b := current.a
      c := current.b
      d := current.c
      e := current.d + first
      f := current.e
      g := current.f
      h := current.g }) state
  { a := state.a + result.a
    b := state.b + result.b
    c := state.c + result.c
    d := state.d + result.d
    e := state.e + result.e
    f := state.f + result.f
    g := state.g + result.g
    h := state.h + result.h }

private def lengthBytes (length : Nat) : List UInt8 :=
  (List.range 8).reverse.map fun index => UInt8.ofNat (length * 8 / 2 ^ (8 * index) % 256)

private def padded (bytes : List UInt8) : List UInt8 :=
  let withMarker := bytes ++ [0x80]
  let zeroCount := (56 + 64 - withMarker.length % 64) % 64
  withMarker ++ List.replicate zeroCount 0 ++ lengthBytes bytes.length

private def initial : Working := {
  a := 0x6a09e667
  b := 0xbb67ae85
  c := 0x3c6ef372
  d := 0xa54ff53a
  e := 0x510e527f
  f := 0x9b05688c
  g := 0x1f83d9ab
  h := 0x5be0cd19
}

private def wordBytes (word : UInt32) : List UInt8 :=
  [UInt8.ofNat ((word >>> 24).toNat), UInt8.ofNat ((word >>> 16).toNat),
   UInt8.ofNat ((word >>> 8).toNat), UInt8.ofNat word.toNat]

def hash (bytes : List UInt8) : List UInt8 :=
  let input := padded bytes
  let state := (List.range (input.length / 64)).foldl
    (fun current index => compress current (input.drop (index * 64) |>.take 64)) initial
  wordBytes state.a ++ wordBytes state.b ++ wordBytes state.c ++ wordBytes state.d ++
    wordBytes state.e ++ wordBytes state.f ++ wordBytes state.g ++ wordBytes state.h

end NEARLean.Crypto.SHA256
