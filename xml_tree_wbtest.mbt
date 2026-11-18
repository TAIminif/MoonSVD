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
  for
    input in [
      "<device><name></device>", "<device/><device/>", "<!DOCTYPE device [<!ENTITY demo \"x\">]><device>&demo;</device>",
      "",
    ] {
    try read_tree(input) catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected malformed or prohibited XML")
    }
  }
}

///|
test "XML duplicate and nested scalar elements fail" {
  for
    input in [
      "<device><name>A</name><name>B</name></device>", "<device><name><b>A</b></name></device>",
    ] {
    let root = read_tree(input)
    try root.property("name") catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected a scalar XML error")
    }
  }
}
