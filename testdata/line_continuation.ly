// Test: binary operator at end of line continues expression on next line

func main() {
  // Arithmetic
  let x = 10 +
    20
  assert_eq(x, 30, "plus continuation")

  let y = 100 -
    50
  assert_eq(y, 50, "minus continuation")

  let z = 3 *
    4
  assert_eq(z, 12, "star continuation")

  // Logical operators
  let a = true &&
    true
  assert(a, "and continuation")

  let b = false ||
    true
  assert(b, "or continuation")

  // Comparison
  let c = 5 ==
    5
  assert(c, "eq continuation")

  let d = 5 !=
    6
  assert(d, "neq continuation")

  // Chained multi-line
  let e = 1 +
    2 +
    3 +
    4
  assert_eq(e, 10, "chained continuation")

  // Assignment continuation
  let mut f = 0
  f =
    42
  assert_eq(f, 42, "assign continuation")

  print("PASS")
}
