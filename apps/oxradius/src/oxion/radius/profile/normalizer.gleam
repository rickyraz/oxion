import gleam/list
import gleam/order
import gleam/string
import oxion/radius/vendor/types

pub fn normalize_attributes(
  attributes: List(types.RadiusAttribute),
) -> List(types.RadiusAttribute) {
  dedupe_sorted(sort_attributes(attributes, []), [])
}

fn sort_attributes(
  remaining: List(types.RadiusAttribute),
  sorted: List(types.RadiusAttribute),
) -> List(types.RadiusAttribute) {
  case remaining {
    [] -> sorted
    [attribute, ..rest] ->
      sort_attributes(rest, insert_attribute(attribute, sorted))
  }
}

fn insert_attribute(
  attribute: types.RadiusAttribute,
  sorted: List(types.RadiusAttribute),
) -> List(types.RadiusAttribute) {
  case sorted {
    [] -> [attribute]
    [head, ..tail] ->
      case attribute_before(attribute, head) {
        True -> [attribute, head, ..tail]
        False -> [head, ..insert_attribute(attribute, tail)]
      }
  }
}

fn attribute_before(
  a: types.RadiusAttribute,
  b: types.RadiusAttribute,
) -> Bool {
  let types.RadiusAttribute(name: a_name, value: a_value) = a
  let types.RadiusAttribute(name: b_name, value: b_value) = b

  case string.compare(a_name, b_name) {
    order.Lt -> True
    order.Eq ->
      case string.compare(a_value, b_value) {
        order.Lt -> True
        _ -> False
      }
    _ -> False
  }
}

fn dedupe_sorted(
  remaining: List(types.RadiusAttribute),
  acc: List(types.RadiusAttribute),
) -> List(types.RadiusAttribute) {
  case remaining {
    [] -> list.reverse(acc)
    [item, ..rest] ->
      case acc {
        [last, ..] ->
          case item == last {
            True -> dedupe_sorted(rest, acc)
            False -> dedupe_sorted(rest, [item, ..acc])
          }
        [] -> dedupe_sorted(rest, [item, ..acc])
      }
  }
}
