import gleeunit
import oxion/radius/coa/result

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn result_reason_test() {
  result.reason(result.IdempotentSkip("already_applied"))
}
