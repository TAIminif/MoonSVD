///|
test "numeric radices, scaled values and 64-bit exactness" {
  let root = read_tree("<x><address>0xFFFFffffFFFFFFFF</address><size>64</size><block>4K</block></x>")
  assert_eq(root.num("address").unwrap(), 18446744073709551615UL)
  assert_eq(root.num("block").unwrap(), 4096UL)
  assert_eq(root.small("size", 64), Some(64))
  assert_eq(number("#10111", root, "bits"), 23UL)
  assert_eq(number("0b110", root, "bits"), 6UL)
}

///|
test "reject malformed and overflowing numeric values" {
  let root = read_tree("<x/>")
  for input in ["", "0x", "-1", "#10x", "0b102", "18446744073709551616", "1099511627776T"] {
    try number(input, root, "test") catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("unexpected numeric success for \{input}")
    }
  }
  try checked_add(1UL, 18446744073709551615UL, root) catch {
    Invalid(_, _, _) => ()
  } noraise {
    _ => fail("expected checked addition overflow")
  }
  try checked_mul(2UL, 18446744073709551615UL, root) catch {
    Invalid(_, _, _) => ()
  } noraise {
    _ => fail("expected checked multiplication overflow")
  }
}
