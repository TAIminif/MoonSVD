///|
test "lint reports distinct input faults including bad ranges and missing aliases" {
  let input =
    #|<device><name>D</name><size>16</size><peripherals>
    #|<peripheral><name>P</name><baseAddress>0x1000</baseAddress><registers>
    #|<register><name>R</name><addressOffset>0</addressOffset><resetValue>0x1ffff</resetValue><fields>
    #|<field><name>A</name><bitOffset>0</bitOffset><bitWidth>4</bitWidth></field>
    #|<field><name>B</name><bitOffset>1</bitOffset><bitWidth>1</bitWidth></field>
    #|<field><name>C</name><bitOffset>15</bitOffset><bitWidth>2</bitWidth></field>
    #|</fields></register><register><name>S</name><addressOffset>1</addressOffset>
    #|<alternateRegister>NOPE</alternateRegister></register></registers></peripheral></peripherals></device>
  let device = @moonsvd.parse(input)
  let diagnostics = device.lint()
  assert_eq(diagnostics.map(item => item.code), [
    "reset-width", "field-overlap", "field-range", "alternate-register", "register-overlap",
  ])
  assert_eq(diagnostics[2].path, "P.R.C")
  assert_true(diagnostics[2].line > 0)
}

///|
test "an authored alternate register and a peripheral alias do not collide" {
  let input =
    #|<device><name>D</name><size>32</size><peripherals>
    #|<peripheral><name>P</name><baseAddress>0x1000</baseAddress><registers>
    #|<register><name>R</name><addressOffset>0</addressOffset></register>
    #|<register><name>ALT_R</name><addressOffset>0</addressOffset><alternateRegister>R</alternateRegister></register>
    #|</registers></peripheral>
    #|<peripheral derivedFrom="P"><name>Q</name><baseAddress>0x1000</baseAddress></peripheral>
    #|</peripherals></device>
  let device = @moonsvd.parse(input)
  assert_eq(device.lint().length(), 0)
}

///|
test "split read and write views are allowed but a second write view conflicts" {
  let prefix =
    #|<device><name>Split</name><width>32</width><peripherals>
    #|<peripheral><name>P</name><baseAddress>0</baseAddress><registers>
    #|<register><name>A_RD</name><addressOffset>0</addressOffset><access>read-only</access></register>
    #|<register><name>B_WR</name><addressOffset>0</addressOffset><access>write-only</access></register>
  let end = "</registers></peripheral></peripherals></device>"
  assert_true(@moonsvd.parse(prefix + end).lint().is_empty())
  let extra = "<register><name>C_WR</name><addressOffset>0</addressOffset><access>write-only</access></register>"
  let findings = @moonsvd.parse(prefix + extra + end).lint()
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].path, "P.C_WR")
  assert_true(findings[0].message.contains("P.B_WR"))
}
