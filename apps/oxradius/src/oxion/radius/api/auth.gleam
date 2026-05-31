import gleam/http/request
import gleam/string
import wisp

pub type AuthError {
  MissingToken
  InvalidToken
}

pub fn authorize_request(
  request_value: wisp.Request,
  expected_token: String,
) -> Result(Nil, AuthError) {
  case string.trim(expected_token) {
    "" -> Error(MissingToken)
    token ->
      case request.get_header(request_value, "authorization") {
        Error(_) -> Error(InvalidToken)
        Ok(value) ->
          case value == "Bearer " <> token {
            True -> Ok(Nil)
            False -> Error(InvalidToken)
          }
      }
  }
}
