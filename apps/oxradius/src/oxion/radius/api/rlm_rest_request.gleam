import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option
import gleam/result
import gleam/string
import oxion/radius/session/types as session_types

pub type AuthorizeRequest {
  AuthorizeRequest(
    username: String,
    user_password_present: Bool,
    nas_ip_address: option.Option(String),
    nas_port: option.Option(String),
    acct_session_id: option.Option(String),
  )
}

pub type AccountingRequest {
  AccountingRequest(
    tenant_id: String,
    service_id: String,
    username: option.Option(String),
    acct_status_type: session_types.AccountingStatus,
    acct_session_id: option.Option(String),
    framed_ip: option.Option(String),
    nas_ip_address: option.Option(String),
    nas_identifier: option.Option(String),
    active_profile_id: option.Option(String),
    event_epoch_seconds: Int,
  )
}

pub type PostAuthRequest {
  PostAuthRequest(
    username: option.Option(String),
    reply_message: option.Option(String),
    module_failure_message: option.Option(String),
  )
}

pub type ParseError {
  InvalidJson
  InvalidShape
  MissingUsername
  InvalidAccountingStatus(String)
}

const default_tenant_id = "tenant_default"

const default_service_id = "service_unknown"

const default_event_epoch_seconds = 0

pub fn parse_authorize(body: String) -> Result(AuthorizeRequest, ParseError) {
  case json.parse(body, compact_authorize_decoder()) {
    Ok(request) -> Ok(request)
    Error(_) ->
      case json.parse(body, native_authorize_decoder()) {
        Ok(request) -> Ok(request)
        Error(_) -> Error(InvalidShape)
      }
  }
}

pub fn parse_accounting(body: String) -> Result(AccountingRequest, ParseError) {
  case json.parse(body, compact_accounting_decoder()) {
    Ok(request) -> Ok(request)
    Error(_) ->
      case json.parse(body, native_accounting_decoder()) {
        Ok(request) -> Ok(request)
        Error(_) -> Error(InvalidShape)
      }
  }
}

pub fn parse_post_auth(body: String) -> Result(PostAuthRequest, ParseError) {
  case json.parse(body, compact_post_auth_decoder()) {
    Ok(request) -> Ok(request)
    Error(_) ->
      case json.parse(body, native_post_auth_decoder()) {
        Ok(request) -> Ok(request)
        Error(_) -> Error(InvalidShape)
      }
  }
}

fn compact_authorize_decoder() -> decode.Decoder(AuthorizeRequest) {
  {
    use username <- decode.field("username", decode.string)
    use password <- decode.optional_field("password_present", "", decode.string)
    use nas_ip <- decode.optional_field("nas_ip_address", "", decode.string)
    use nas_port <- decode.optional_field("nas_port", "", decode.string)
    use session_id <- decode.optional_field(
      "acct_session_id",
      "",
      decode.string,
    )
    case non_empty(username) {
      option.None ->
        decode.failure(
          AuthorizeRequest("", False, option.None, option.None, option.None),
          expected: "username",
        )
      option.Some(username) ->
        decode.success(AuthorizeRequest(
          username: username,
          user_password_present: has_value(password),
          nas_ip_address: non_empty(nas_ip),
          nas_port: non_empty(nas_port),
          acct_session_id: non_empty(session_id),
        ))
    }
  }
}

fn native_authorize_decoder() -> decode.Decoder(AuthorizeRequest) {
  {
    use username <- decode.field("User-Name", attr_value_decoder())
    use password <- optional_radius_attr_string("User-Password")
    use nas_ip <- optional_radius_attr_string("NAS-IP-Address")
    use nas_port <- optional_radius_attr_string("NAS-Port")
    use session_id <- optional_radius_attr_string("Acct-Session-Id")
    decode.success(AuthorizeRequest(
      username: username,
      user_password_present: has_value(password),
      nas_ip_address: non_empty(nas_ip),
      nas_port: non_empty(nas_port),
      acct_session_id: non_empty(session_id),
    ))
  }
}

fn compact_accounting_decoder() -> decode.Decoder(AccountingRequest) {
  {
    use username <- decode.optional_field("username", "", decode.string)
    use acct_status <- decode.field("acct_status_type", decode.string)
    use session_id <- decode.optional_field(
      "acct_session_id",
      "",
      decode.string,
    )
    use framed_ip <- decode.optional_field(
      "framed_ip_address",
      "",
      decode.string,
    )
    use nas_ip <- decode.optional_field("nas_ip_address", "", decode.string)
    use nas_identifier <- decode.optional_field(
      "nas_identifier",
      "",
      decode.string,
    )
    use profile_id <- decode.optional_field(
      "active_profile_id",
      "",
      decode.string,
    )
    use event_time <- decode.optional_field(
      "event_epoch_seconds",
      "",
      decode.string,
    )
    accounting_from_values(
      username,
      acct_status,
      session_id,
      framed_ip,
      nas_ip,
      nas_identifier,
      profile_id,
      event_time,
    )
  }
}

fn native_accounting_decoder() -> decode.Decoder(AccountingRequest) {
  {
    use username <- optional_radius_attr_string("User-Name")
    use acct_status <- decode.field("Acct-Status-Type", attr_value_decoder())
    use session_id <- optional_radius_attr_string("Acct-Session-Id")
    use framed_ip <- optional_radius_attr_string("Framed-IP-Address")
    use nas_ip <- optional_radius_attr_string("NAS-IP-Address")
    use nas_identifier <- optional_radius_attr_string("NAS-Identifier")
    use profile_id <- optional_radius_attr_string("Filter-Id")
    use event_time <- optional_radius_attr_string("Event-Timestamp")
    accounting_from_values(
      username,
      acct_status,
      session_id,
      framed_ip,
      nas_ip,
      nas_identifier,
      profile_id,
      event_time,
    )
  }
}

fn compact_post_auth_decoder() -> decode.Decoder(PostAuthRequest) {
  {
    use username <- decode.optional_field("username", "", decode.string)
    use reply <- decode.optional_field("reply_message", "", decode.string)
    use failure <- decode.optional_field(
      "module_failure_message",
      "",
      decode.string,
    )
    decode.success(PostAuthRequest(
      username: non_empty(username),
      reply_message: non_empty(reply),
      module_failure_message: non_empty(failure),
    ))
  }
}

fn native_post_auth_decoder() -> decode.Decoder(PostAuthRequest) {
  {
    use username <- optional_radius_attr_string("User-Name")
    use reply <- optional_radius_attr_string("Reply-Message")
    use failure <- optional_radius_attr_string("Module-Failure-Message")
    decode.success(PostAuthRequest(
      username: non_empty(username),
      reply_message: non_empty(reply),
      module_failure_message: non_empty(failure),
    ))
  }
}

fn accounting_from_values(
  username: String,
  acct_status: String,
  session_id: String,
  framed_ip: String,
  nas_ip: String,
  nas_identifier: String,
  profile_id: String,
  event_time: String,
) -> decode.Decoder(AccountingRequest) {
  case accounting_status(acct_status) {
    Error(_) ->
      decode.failure(
        AccountingRequest(
          tenant_id: default_tenant_id,
          service_id: default_service_id,
          username: option.None,
          acct_status_type: session_types.AccountingStart,
          acct_session_id: option.None,
          framed_ip: option.None,
          nas_ip_address: option.None,
          nas_identifier: option.None,
          active_profile_id: option.None,
          event_epoch_seconds: default_event_epoch_seconds,
        ),
        expected: "Acct-Status-Type",
      )
    Ok(status) ->
      decode.success(AccountingRequest(
        tenant_id: default_tenant_id,
        service_id: default_service_id,
        username: non_empty(username),
        acct_status_type: status,
        acct_session_id: non_empty(session_id),
        framed_ip: non_empty(framed_ip),
        nas_ip_address: non_empty(nas_ip),
        nas_identifier: non_empty(nas_identifier),
        active_profile_id: non_empty(profile_id),
        event_epoch_seconds: parse_epoch(event_time),
      ))
  }
}

fn optional_radius_attr_string(
  name: String,
  next: fn(String) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  decode.optional_field(name, "", attr_value_decoder(), next)
}

fn attr_value_decoder() {
  {
    use value <- decode.field("value", first_string_decoder())
    decode.success(value)
  }
}

fn first_string_decoder() {
  {
    use value <- decode.field(0, decode.string)
    decode.success(value)
  }
}

fn accounting_status(
  value: String,
) -> Result(session_types.AccountingStatus, ParseError) {
  case value {
    "Start" | "Accounting-Start" -> Ok(session_types.AccountingStart)
    "Interim-Update" | "Alive" -> Ok(session_types.AccountingInterimUpdate)
    "Stop" | "Accounting-Stop" -> Ok(session_types.AccountingStop)
    other -> Error(InvalidAccountingStatus(other))
  }
}

fn parse_epoch(value: String) -> Int {
  value
  |> int.parse
  |> result.unwrap(default_event_epoch_seconds)
}

fn has_value(value: String) -> Bool {
  case non_empty(value) {
    option.Some(_) -> True
    option.None -> False
  }
}

fn non_empty(value: String) -> option.Option(String) {
  case string.trim(value) {
    "" -> option.None
    trimmed -> option.Some(trimmed)
  }
}
