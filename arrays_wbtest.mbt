///|
test "array indices support defaults, numeric ranges and names" {
  let at = read_tree("<x/>")
  let numbered = expand_instances("CH[%s]", Some(3UL), Some(4UL), Some("2-4"), at)
  assert_eq(numbered.map(item => item.name), ["CH[2]", "CH[3]", "CH[4]"])
  assert_eq(numbered.map(item => item.offset), [0UL, 4UL, 8UL])
  let letters = expand_instances("PORT%s", Some(3UL), Some(16UL), Some("A-B,DEBUG"), at)
  assert_eq(letters.map(item => item.name), ["PORTA", "PORTB", "PORTDEBUG"])
  let defaulted = expand_instances("R%s", Some(2UL), Some(2UL), None, at)
  assert_eq(defaulted.map(item => item.name), ["R0", "R1"])
}

///|
test "array definitions fail before expanding invalid indices" {
  let at = read_tree("<x/>")
  for values in ["A,A", "A", "1-4000000", "B-A", "A,,B"] {
    try expand_instances("R%s", Some(2UL), Some(2UL), Some(values), at) catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid dimIndex \{values}")
    }
  }
}
