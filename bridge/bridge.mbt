///|
fn reply(code : Int32, report : Json) -> String {
  let result : Json = { "code": Json(code), "report": report }
  result.stringify()
}

///|
fn error_reply(code : Int32, message : String) -> String {
  reply(code, { "error": Json::string(message) })
}

///|
fn parse_address(raw : String) -> UInt64? {
  if raw.length() > 128 {
    return None
  }
  try @string.parse_uint64(raw[:]) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
#export_name("execute")
pub fn execute(command : String, input : String, other : String) -> String {
  run_command(command, input, other) catch {
    error => error_reply(2, error.message())
  }
}

///|
fn run_command(
  command : String,
  input : String,
  other : String,
) -> String raise @svd.SvdError {
  let device = @svd.parse(input)
  match command {
    "inspect" => reply(0, device.json())
    "lookup" =>
      match device.find(other) {
        Some(register) => reply(0, register.json())
        None => error_reply(1, "register '\{other}' was not found")
      }
    "at" => {
      let address = match parse_address(other) {
        Some(address) => address
        None =>
          return error_reply(
            2, "expected an unsigned 64-bit address (at most 128 characters)",
          )
      }
      let registers = device.at(address)
      let report : Json = {
        "device": Json::string(device.name),
        "address": Json::string("0x" + address.to_string(radix=16)),
        "registers": Json::array(registers.map(@svd.Register::json)),
      }
      reply(if registers.is_empty() { 1 } else { 0 }, report)
    }
    "check" => {
      let findings = device.lint()
      let report : Json = {
        "device": Json::string(device.name),
        "registers": Json(device.registers.length()),
        "findings": Json::array(findings.map(@svd.Diagnostic::json)),
      }
      reply(if findings.is_empty() { 0 } else { 1 }, report)
    }
    "diff" => {
      let next = @svd.parse(other)
      let changes = device.diff(next)
      let report : Json = {
        "before": Json::string(device.name),
        "after": Json::string(next.name),
        "changes": Json::array(changes.map(@svd.Change::json)),
      }
      reply(if changes.is_empty() { 0 } else { 1 }, report)
    }
    _ => error_reply(2, "unknown command '\{command}'")
  }
}
