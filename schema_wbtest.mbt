///|
test "index declarations through nested clusters and fields" {
  let schema = read_schema("<device><name>Demo</name><peripherals><peripheral><name>T</name><registers><cluster><name>G</name><register><name>R</name><fields><field><name>B</name></field></fields></register></cluster></registers></peripheral></peripherals></device>")
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
  for input in [
    "<x/>",
    "<device><name>D</name><peripherals/></device>",
    "<device><name>D</name><peripherals><peripheral><name>P</name></peripheral><peripheral><name>P</name></peripheral></peripherals></device>",
  ] {
    try read_schema(input) catch {
      Invalid(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid CMSIS-SVD structure")
    }
  }
}
