///|
test "inheritance resolves forward and qualified references" {
  let input =
    #|<device><name>Example</name><peripherals>
    #|<peripheral derivedFrom="A"><name>B</name><baseAddress>0x20</baseAddress>
    #|<registers><register derivedFrom="A.ORIG"><name>NEW</name><addressOffset>8</addressOffset></register></registers></peripheral>
    #|<peripheral><name>A</name><baseAddress>0x10</baseAddress><size>16</size>
    #|<registers><register><name>ORIG</name><addressOffset>4</addressOffset><access>read-only</access></register></registers></peripheral>
    #|</peripherals></device>
  let resolver = Resolver::new(read_schema(input))
  let peripheral = resolver.resolve("B")
  assert_eq(peripheral.children.paths, ["A.ORIG", "B.NEW"])
  assert_eq(peripheral.num("size"), Some(16UL))
  assert_eq(peripheral.num("baseAddress"), Some(32UL))
  let register = resolver.resolve("B.NEW")
  assert_eq(register.num("addressOffset"), Some(8UL))
  assert_eq(register.text("access"), Some("read-only"))
}

///|
test "inheritance diagnoses unknown targets and reference cycles" {
  let prefix = "<device><name>D</name><peripherals>"
  let suffix = "</peripherals></device>"
  for
    body in [
      "<peripheral derivedFrom=\"Z\"><name>A</name></peripheral>", "<peripheral derivedFrom=\"B\"><name>A</name></peripheral><peripheral derivedFrom=\"A\"><name>B</name></peripheral>",
    ] {
    let engine = Resolver::new(read_schema(prefix + body + suffix))
    try engine.resolve("A") catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected bad reference to fail")
    }
  }
}

///|
test "derived names resolve a register inherited into the current scope" {
  let input =
    #|<device><name>Device</name><width>32</width><peripherals>
    #|<peripheral><name>A</name><baseAddress>0</baseAddress><registers>
    #|<register><name>ORIG</name><addressOffset>0</addressOffset><access>read-only</access></register>
    #|</registers></peripheral>
    #|<peripheral derivedFrom="A"><name>B</name><baseAddress>8</baseAddress><registers>
    #|<register derivedFrom="ORIG"><name>NEW</name><addressOffset>4</addressOffset></register>
    #|</registers></peripheral>
    #|</peripherals></device>
  let reg = parse(input).find("B.NEW").unwrap()
  assert_eq(reg.address, 12UL)
  assert_eq(reg.access, Some("read-only"))
}

///|
fn inheritance_chain(length : Int32, base_first : Bool) -> String {
  let document = StringBuilder()
  document.write_string("<device><name>D</name><peripherals>")
  for position in 0..<length {
    let index = if base_first { position } else { length - position - 1 }
    if index == 0 {
      document.write_string(
        "<peripheral><name>P0</name><baseAddress>0</baseAddress></peripheral>",
      )
    } else {
      let base = index - 1
      document.write_string(
        "<peripheral derivedFrom=\"P\{base}\"><name>P\{index}</name></peripheral>",
      )
    }
  }
  document.write_string("</peripherals></device>")
  document.to_string()
}

///|
test "inheritance depth is enforced with and without cached bases" {
  for base_first in [true, false] {
    let accepted = parse(inheritance_chain(64, base_first))
    assert_eq(accepted.peripherals.length(), 64)
    try parse(inheritance_chain(65, base_first)) catch {
      Invalid(_, _, detail) =>
        assert_eq(detail, "inheritance depth limit exceeded")
    } noraise {
      _ =>
        fail("expected the same inheritance limit in both declaration orders")
    }
  }
}

///|
test "inherited child tables are shared and overrides consume the merge budget" {
  let input =
    #|<device><name>D</name><peripherals>
    #|<peripheral><name>A</name><registers><register><name>REG</name></register></registers></peripheral>
    #|<peripheral derivedFrom="A"><name>B</name></peripheral>
    #|<peripheral derivedFrom="B"><name>C</name><registers><register><name>REG</name></register></registers></peripheral>
    #|</peripherals></device>
  let resolver = Resolver::new(read_schema(input))
  resolver.remaining_child_slots = 1
  let derived = resolver.resolve("B")
  assert_eq(resolver.child_lookup(derived.children, "REG"), Some("A.REG"))
  assert_eq(resolver.remaining_child_slots, 1)
  try resolver.resolve("C") catch {
    Invalid(_, _, detail) =>
      assert_eq(detail, "SVD inherited children limit exceeded")
  } noraise {
    _ => fail("expected a merged child table to use the budget")
  }
}
