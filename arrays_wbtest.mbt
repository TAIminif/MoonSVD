///|
test "array indices support defaults, numeric ranges and names" {
  let at = read_tree("<x/>")
  let numbered = expand_instances(
    "CH[%s]",
    Some(3UL),
    Some(4UL),
    Some("2-4"),
    at,
  )
  assert_eq(numbered.map(item => item.name), ["CH[2]", "CH[3]", "CH[4]"])
  assert_eq(numbered.map(item => item.offset), [0UL, 4UL, 8UL])
  let letters = expand_instances(
    "PORT%s",
    Some(3UL),
    Some(16UL),
    Some("A-B,DEBUG"),
    at,
  )
  assert_eq(letters.map(item => item.name), ["PORTA", "PORTB", "PORTDEBUG"])
  let defaulted = expand_instances("R%s", Some(2UL), Some(2UL), None, at)
  assert_eq(defaulted.map(item => item.name), ["R0", "R1"])
}

///|
test "array definitions fail before expanding invalid indices" {
  let at = read_tree("<x/>")
  for
    values in [
      "A,A", "A", "1-4000000", "B-A", "A,,B", "18446744073709551614-18446744073709551616",
      "18446744073709551615-18446744073709551614", "0-18446744073709551615",
    ] {
    try expand_instances("R%s", Some(2UL), Some(2UL), Some(values), at) catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid dimIndex \{values}")
    }
  }
}

///|
test "numeric dimIndex labels preserve precision across signed integer boundaries" {
  let at = read_tree("<x/>")
  for
    (indices, names) in [
      ("4294967294-4294967295", ["R4294967294", "R4294967295"]),
      (
        "18446744073709551614-18446744073709551615",
        ["R18446744073709551614", "R18446744073709551615"],
      ),
    ] {
    let result = expand_instances(
      "R%s",
      Some(2UL),
      Some(4UL),
      Some(indices),
      at,
    )
    assert_eq(result.map(item => item.name), names)
    assert_eq(result.map(item => item.offset), [0UL, 4UL])
  }
}

///|
test "SVD bounds names before storing declarations or array instances" {
  let long_name = "A".repeat(256)
  let prefix = "<device><name>D</name><peripherals><peripheral><name>"
  let suffix = "</name><baseAddress>0</baseAddress></peripheral></peripherals></device>"
  assert_eq(parse(prefix + long_name + suffix).peripherals, [long_name])
  try parse(prefix + long_name + "A" + suffix) catch {
    Invalid(_, _, detail) =>
      assert_eq(detail, "SVD local name exceeds 256 UTF-16 code units")
  } noraise {
    _ => fail("expected oversized local identifier to fail")
  }
  let at = read_tree("<x/>")
  try expand_instances("R%s", Some(1UL), Some(1UL), Some(long_name), at) catch {
    Invalid(_, _, detail) =>
      assert_eq(detail, "expanded array name exceeds 256 UTF-16 code units")
  } noraise {
    _ => fail("expected oversized array expansion to fail")
  }
  let budget : NameBudget = { remaining: 3, }
  budget.reserve("A.B", at)
  try budget.reserve("C", at) catch {
    Invalid(_, _, detail) =>
      assert_eq(detail, "SVD cumulative name limit exceeded")
  } noraise {
    _ => fail("expected cumulative name budget to be exhausted")
  }
}
