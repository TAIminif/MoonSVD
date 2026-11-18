///|
test "JSON retains an address above the JavaScript integer precision limit" {
  let input =
    #|<device><name>D</name><width>32</width><peripherals>
    #|<peripheral><name>P</name><baseAddress>0x20000000000001</baseAddress>
    #|<registers><register><name>R</name><addressOffset>0</addressOffset>
    #|</register></registers></peripheral></peripherals></device>
  let device = @moonsvd.parse(input)
  let emitted = device.json().stringify()
  assert_true(emitted.contains("\"address\":\"0x20000000000001\""))
  assert_true(emitted.contains("\"path\":\"P.R\""))
}
