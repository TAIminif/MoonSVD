///|
/// Declared restrictions on values written to a register or field.
pub enum WriteConstraint {
  AsRead(Bool)
  Enumerated(Bool)
  Range(UInt64, UInt64)
} derive(Eq)

///|
pub extend WriteConstraint with Eq::{equal, not_equal}

///|
/// Access semantics described by CMSIS-SVD. Read and write actions retain their
/// CMSIS-SVD spelling. The write constraint includes any register default.
pub struct AccessBehavior {
  read_action : String?
  modified_write_values : String?
  write_constraint : WriteConstraint?
}

///|
fn constraint_flag(node : Node) -> Bool raise SvdError {
  match node.text() {
    "true" | "1" => true
    "false" | "0" => false
    _ => raise node.invalid("expected an XML boolean in <\{node.name}>")
  }
}

///|
fn parse_write_constraint(node : Node) -> WriteConstraint raise SvdError {
  if node.children.length() != 1 {
    raise node.invalid("writeConstraint requires exactly one choice")
  }
  let choice = node.children[0]
  match choice.name {
    "writeAsRead" => AsRead(constraint_flag(choice))
    "useEnumeratedValues" => Enumerated(constraint_flag(choice))
    "range" => {
      if choice.children.length() != 2 {
        raise choice.invalid(
          "writeConstraint range requires minimum and maximum",
        )
      }
      let low = choice.required("minimum")
      let high = choice.required("maximum")
      let minimum = number(low.text(), low, "minimum")
      let maximum = number(high.text(), high, "maximum")
      if minimum > maximum {
        raise choice.invalid("writeConstraint minimum exceeds maximum")
      }
      Range(minimum, maximum)
    }
    _ => raise choice.invalid("unknown writeConstraint choice <\{choice.name}>")
  }
}

///|
fn Resolved::behavior(
  self : Resolved,
  default_constraint : WriteConstraint?,
) -> AccessBehavior raise SvdError {
  let read_action = match self.values.get("readAction") {
    None => None
    Some(node) =>
      match node.text() {
        "clear" | "set" | "modify" | "modifyExternal" as value => Some(value)
        value => raise node.invalid("unknown readAction '\{value}'")
      }
  }
  let modified_write_values = match self.values.get("modifiedWriteValues") {
    None => None
    Some(node) =>
      match node.text() {
        "oneToClear"
        | "oneToSet"
        | "oneToToggle"
        | "zeroToClear"
        | "zeroToSet"
        | "zeroToToggle"
        | "clear"
        | "set"
        | "modify" as value => Some(value)
        value => raise node.invalid("unknown modifiedWriteValues '\{value}'")
      }
  }
  let write_constraint = match self.values.get("writeConstraint") {
    Some(node) => Some(parse_write_constraint(node))
    None => default_constraint
  }
  { read_action, modified_write_values, write_constraint, }
}
