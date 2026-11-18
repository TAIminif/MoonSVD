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
  assert_eq(diagnostics.map(item => item.code), ["reset-width", "field-overlap", "field-range", "alternate-register", "register-overlap"])
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
