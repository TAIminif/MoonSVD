///|
test "index declarations through nested clusters and fields" {
  let schema = read_schema(
    "<device><name>Demo</name><peripherals><peripheral><name>T</name><registers><cluster><name>G</name><register><name>R</name><fields><field><name>B</name></field></fields></register></cluster></registers></peripheral></peripherals></device>",
  )
  assert_eq(schema.device.name, "device")
  assert_eq(schema.name, "Demo")
  assert_eq(schema.roots, ["T"])
  let field = schema.declarations.get("T.G.R.B").unwrap()
  assert_eq(field.path, "T.G.R.B")
  assert_eq(field.scope, "T.G.R")
  assert_eq(field.name, "B")
  assert_eq(field.node.name, "field")
  assert_eq(schema.declarations.get("T.G").unwrap().children, ["T.G.R"])
}

///|
test "schema rejects missing roots and duplicate siblings" {
  for
    input in [
      "<x/>", "<device><name>D</name><peripherals/></device>", "<device><name>D</name><peripherals><peripheral><name>P</name></peripheral><peripheral><name>P</name></peripheral></peripherals></device>",
    ] {
    try read_schema(input) catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid CMSIS-SVD structure")
    }
  }
}

///|
test "device names support punctuation independently from declaration paths" {
  for name in ["Chip 2.0", "芯片 2.0"] {
    let input = "<device><name>\{name}</name><size>32</size><peripherals>" +
      "<peripheral><name>P</name><baseAddress>0</baseAddress><registers>" +
      "<register><name>R</name><addressOffset>0</addressOffset></register>" +
      "</registers></peripheral></peripherals></device>"
    let device = parse(input)
    assert_eq(device.name, name)
    assert_eq(device.find("P.R").unwrap().address, 0UL)
    try
      parse(input.replace_all(old="<name>P</name>", new="<name>P.0</name>"))
    catch {
      Invalid(_, _, detail) =>
        assert_eq(detail, "expected a nonempty local identifier without '.'")
    } noraise {
      _ => fail("expected a dotted peripheral identifier to fail")
    }
  }
}
