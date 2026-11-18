///|
fn reply(code : Int, report : Json) -> String {
  let result : Json = { "code": code.to_json(), "report": report }
  result.stringify()
}

///|
fn error_reply(code : Int, message : String) -> String {
  reply(code, { "error": Json::string(message) })
}

///|
#export_name("execute")
pub fn execute(command : String, input : String, other : String) -> String {
  try run_command(command, input, other) catch {
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
    "check" => {
      let findings = device.lint()
      let report : Json = {
        "device": Json::string(device.name),
        "registers": device.registers.length().to_json(),
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
