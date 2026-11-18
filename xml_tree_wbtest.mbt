///|
test "XML keeps attributes, text and authored locations" {
  let root = read_tree(
    "<?xml version=\"1.0\"?>\n<device><name>A &amp; B<![CDATA[ <C>]]></name>\n<register derivedFrom=\"BASE\"/></device>",
  )
  assert_eq(root.name, "device")
  assert_eq(root.line, 2)
  assert_eq(root.property("name"), Some("A & B <C>"))
  let register = root.required("register")
  assert_eq(register.attributes.get("derivedFrom"), Some("BASE"))
  assert_eq(register.line, 3)
}

///|
test "XML failures are typed and DTD is rejected" {
  for input in [
    "<device><name></device>",
    "<device/><device/>",
    "<!DOCTYPE device [<!ENTITY demo \"x\">]><device>&demo;</device>",
    "",
  ] {
    let result = try? read_tree(input)
    assert_true(result is Err(Invalid(_, _, _)))
  }
}

///|
test "XML duplicate and nested scalar elements fail" {
  let repeated = read_tree("<device><name>A</name><name>B</name></device>")
  assert_true((try? repeated.property("name")) is Err(Invalid(_, _, _)))
  let nested = read_tree("<device><name><b>A</b></name></device>")
  assert_true((try? nested.property("name")) is Err(Invalid(_, _, _)))
}
