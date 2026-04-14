import oxion/radius/coa/response

pub type RetryPolicy {
  RetryPolicy(max_attempts: Int, backoff_ms: List(Int))
}

pub type RetryPolicyError {
  InvalidMaxAttempts
  EmptyBackoffSchedule
}

pub fn validate(policy: RetryPolicy) -> Result(Nil, RetryPolicyError) {
  let RetryPolicy(max_attempts: max_attempts, backoff_ms: backoff_ms) = policy

  case max_attempts > 0 {
    False -> Error(InvalidMaxAttempts)
    True ->
      case backoff_ms {
        [] -> Error(EmptyBackoffSchedule)
        _ -> Ok(Nil)
      }
  }
}

pub fn is_retryable(response_value: response.CoaResponse) -> Bool {
  case response_value {
    response.Timeout -> True
    response.TransportError(_) -> True
    _ -> False
  }
}

pub fn retry_delay(policy: RetryPolicy, retry_index: Int) -> Int {
  let RetryPolicy(max_attempts: _max_attempts, backoff_ms: backoff_ms) = policy

  case nth(backoff_ms, retry_index) {
    Ok(delay) -> delay
    Error(_) -> last_or_zero(backoff_ms)
  }
}

fn nth(items: List(Int), index: Int) -> Result(Int, Nil) {
  case items, index {
    [item, ..], 0 -> Ok(item)
    [_, ..rest], _ -> nth(rest, index - 1)
    [], _ -> Error(Nil)
  }
}

fn last_or_zero(items: List(Int)) -> Int {
  case items {
    [] -> 0
    [item] -> item
    [_, ..rest] -> last_or_zero(rest)
  }
}
