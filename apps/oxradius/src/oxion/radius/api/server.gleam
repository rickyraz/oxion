import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/result
import gleam/string
import mist
import oxion/radius/api/router
import wisp/wisp_mist

@external(erlang, "oxion_radius_env_ffi", "getenv")
fn getenv(name: String) -> Result(String, Nil)

pub fn main() -> Nil {
  start_from_env()
  process.sleep_forever()
}

pub fn start_from_env() -> Nil {
  let token = env_or("OXRADIUS_RLM_REST_TOKEN", "test-token")
  let port =
    env_or("OXRADIUS_HTTP_PORT", "8088")
    |> int.parse
    |> result.unwrap(8088)
  let bind = env_or("OXRADIUS_HTTP_BIND", "127.0.0.1")

  case start(port, bind, token) {
    Ok(_) -> Nil
    Error(_) -> io.println("failed to start oxRADIUS Policy API")
  }
}

pub fn start(port: Int, bind: String, token: String) {
  fn(request) { router.handle(request, token) }
  |> wisp_mist.handler("oxradius-policy-api-dev-secret")
  |> mist.new
  |> mist.port(port)
  |> mist.bind(bind)
  |> mist.start
}

fn env_or(name: String, fallback: String) -> String {
  case getenv(name) {
    Error(_) -> fallback
    Ok(value) ->
      case string.is_empty(value) {
        True -> fallback
        False -> value
      }
  }
}
