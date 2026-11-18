///|
/// An input error with enough source context to locate it in the SVD.
pub suberror SvdError {
  Invalid(Int32, Int32, String)
}

///|
pub fn SvdError::message(self : SvdError) -> String {
  let Invalid(line, column, detail) = self
  "line \{line}, column \{column}: \{detail}"
}

///|
priv struct Node {
  name : String
  attributes : Map[String, String]
  children : Array[Node]
  content : StringBuilder
  line : Int32
  column : Int32
}

///|
fn Node::invalid(self : Node, detail : String) -> SvdError {
  Invalid(self.line, self.column, detail)
}

///|
fn new_node(element : @xml.XmlElement, at : @xml.SourcePosition) -> Node {
  let attributes = Map([])
  for attribute in element.attributes {
    attributes[attribute.name] = attribute.value
  }
  {
    name: element.name,
    attributes,
    children: [],
    content: StringBuilder(),
    line: at.line,
    column: at.column,
  }
}

///|
fn attach_node(
  stack : Array[Node],
  root : Node?,
  node : Node,
) -> Node? raise SvdError {
  match stack.last() {
    Some(parent) => {
      parent.children.push(node)
      root
    }
    None =>
      match root {
        None => Some(node)
        Some(_) => raise node.invalid("multiple XML root elements")
      }
  }
}

///|
fn read_tree(input : String) -> Node raise SvdError {
  if input.length() > 8_388_608 {
    raise Invalid(1, 1, "input exceeds 8,388,608 UTF-16 code units")
  }
  let reader = @xml.Reader::from_string(input)
  let stack : Array[Node] = []
  let mut root : Node? = None
  let mut nodes = 0
  for ;; {
    let event = reader.read_event() catch {
      error => raise Invalid(reader.line(), reader.column(), error.to_string())
    }
    let at = event.span.start
    match event.kind {
      Start(element) | Empty(element) => {
        nodes += 1
        if stack.length() >= 64 || nodes > 250_000 {
          raise Invalid(at.line, at.column, "XML depth or node limit exceeded")
        }
        let node = new_node(element, at)
        root = attach_node(stack, root, node)
        if event.kind is Start(_) {
          stack.push(node)
        }
      }
      End(_) => ignore(stack.pop())
      Text(value) | CData(value) =>
        if stack.last() is Some(node) {
          node.content.write_string(value)
        }
      DocType(_) => raise Invalid(at.line, at.column, "DTD is disabled")
      Eof =>
        match root {
          Some(node) if stack.is_empty() => return node
          _ =>
            raise Invalid(at.line, at.column, "expected complete XML document")
        }
      Decl(..) | PI(..) | Comment(_) => ()
    }
  } nobreak {
    abort("unreachable XML loop")
  }
}

///|
fn Node::child(self : Node, tag : String) -> Node? raise SvdError {
  let mut result = None
  for item in self.children {
    if item.name == tag {
      if result is Some(_) {
        raise item.invalid("duplicate <\{tag}>")
      }
      result = Some(item)
    }
  }
  result
}

///|
fn Node::text(self : Node) -> String raise SvdError {
  if !self.children.is_empty() {
    raise self.invalid("expected simple text in <\{self.name}>")
  }
  self.content.to_string().trim().to_owned()
}

///|
fn Node::property(self : Node, tag : String) -> String? raise SvdError {
  match self.child(tag) {
    Some(node) => Some(node.text())
    None => None
  }
}

///|
fn Node::required(self : Node, tag : String) -> Node raise SvdError {
  match self.child(tag) {
    Some(node) => node
    None => raise self.invalid("missing <\{tag}> in <\{self.name}>")
  }
}
