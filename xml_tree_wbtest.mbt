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

///|
test "DTD rejection precedes subset parsing and locates the declaration" {
  let input = "<?xml version=\"1.0\"?>\r\n  <!DOCTYPE device [<!ATTLIST bad missing>]><device/>"
  try read_tree(input) catch {
    Invalid(line, column, detail) => {
      assert_eq(line, 2)
      assert_eq(column, 3)
      assert_eq(detail, "DTD is disabled")
    }
  } noraise {
    _ => fail("expected declaration rejection")
  }
}

///|
test "a DOCTYPE word inside comments, CDATA and processing instructions is data" {
  let input = "<!-- <!DOCTYPE ignored> --><?hint <!DOCTYPE ignored>?><device><name><![CDATA[<!DOCTYPE text>]]></name></device>"
  let root = read_tree(input)
  assert_eq(root.property("name"), Some("<!DOCTYPE text>"))
}

///|
fn attribute_list(count : Int32) -> String {
  let attributes = StringBuilder()
  for i in 0..<count {
    attributes.write_string(" a\{i}=\"\"")
  }
  attributes.to_string()
}

///|
test "XML attribute limits run before dependency parsing with source locations" {
  let root = read_tree("<x" + attribute_list(128) + "/>")
  assert_eq(root.attributes.length(), 128)
  let input = "<?xml version=\"1.0\"?>\r\n  <x" + attribute_list(129) + "/>"
  try read_tree(input) catch {
    Invalid(line, column, detail) => {
      assert_eq(line, 2)
      assert_eq(column, 3)
      assert_eq(detail, "XML tag exceeds 128 attributes")
    }
  } noraise {
    _ => fail("expected the XML attribute limit")
  }
  let data = attribute_list(256)
  let input = "<!-- <x" +
    data +
    "/> --><?hint <x" +
    data +
    "/>?><x a='>&quot;=value'><![CDATA[<y" +
    data +
    "/>]]></x>"
  assert_eq(read_tree(input).attributes.get("a"), Some(">\"=value"))
}

///|
test "XML token length limits count UTF-16 units and respect quotes" {
  for quote in ["\"", "'"] {
    let prefix = "<x a=" + quote
    let suffix = quote + "/>"
    let length = 65_536 - prefix.length() - suffix.length()
    let value = ">".repeat(length)
    assert_eq(
      read_tree(prefix + value + suffix).attributes.get("a"),
      Some(value),
    )
    for oversized in [value + ">", "😀".repeat(length / 2 + 1)] {
      try read_tree(prefix + oversized + suffix) catch {
        Invalid(_, _, detail) =>
          assert_eq(detail, "XML tag exceeds 65,536 UTF-16 code units")
      } noraise {
        _ => fail("expected the XML tag length limit")
      }
    }
  }
}
