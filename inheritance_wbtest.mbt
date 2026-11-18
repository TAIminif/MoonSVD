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
  assert_eq(peripheral.children, ["A.ORIG", "B.NEW"])
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
  for body in [
    "<peripheral derivedFrom=\"Z\"><name>A</name></peripheral>",
    "<peripheral derivedFrom=\"B\"><name>A</name></peripheral><peripheral derivedFrom=\"A\"><name>B</name></peripheral>",
  ] {
    let engine = Resolver::new(read_schema(prefix + body + suffix))
    try engine.resolve("A") catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected bad reference to fail")
    }
  }
}
