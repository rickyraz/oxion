import gleam/json
import oxion/radius/api/policy_runtime

pub fn authorize_body(decision: policy_runtime.Decision) -> String {
  case decision {
    policy_runtime.Allow(reply_message) -> reply_message_body(reply_message)
    policy_runtime.Deny(reply_message) -> reply_message_body(reply_message)
  }
}

pub fn authorize_status(decision: policy_runtime.Decision) -> Int {
  case decision {
    policy_runtime.Allow(_) -> 200
    policy_runtime.Deny(_) -> 401
  }
}

pub fn accounting_ack_body() -> String {
  json.object([
    #("result", json.string("ok")),
    #("action", json.string("accounting_ack")),
  ])
  |> json.to_string
}

pub fn post_auth_ack_body() -> String {
  json.object([
    #("result", json.string("ok")),
    #("action", json.string("post_auth_ack")),
  ])
  |> json.to_string
}

pub fn error_body(reason: String) -> String {
  json.object([#("error", json.string(reason))])
  |> json.to_string
}

fn reply_message_body(message: String) -> String {
  json.object([
    #(
      "Reply-Message",
      json.object([
        #("op", json.string(":=")),
        #("value", json.array([message], of: json.string)),
      ]),
    ),
  ])
  |> json.to_string
}
