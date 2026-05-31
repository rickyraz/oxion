import gleam/http
import oxion/radius/accounting/materializer
import oxion/radius/accounting/radacct
import oxion/radius/api/auth
import oxion/radius/api/policy_runtime
import oxion/radius/api/rlm_rest_request
import oxion/radius/api/rlm_rest_response
import wisp

pub fn handle(request: wisp.Request, token: String) -> wisp.Response {
  case request.method, request.path {
    http.Get, "/health" -> json_ok("{\"status\":\"ok\"}")

    http.Post, "/v1/policy/authorize" ->
      protected(request, token, handle_authorize)

    http.Post, "/v1/policy/accounting" ->
      protected(request, token, handle_accounting)

    http.Post, "/v1/policy/post-auth" ->
      protected(request, token, handle_post_auth)

    _, _ -> wisp.json_response(rlm_rest_response.error_body("not_found"), 404)
  }
}

fn protected(
  request: wisp.Request,
  token: String,
  next: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  case auth.authorize_request(request, token) {
    Ok(_) -> next(request)
    Error(_) ->
      wisp.json_response(rlm_rest_response.error_body("unauthorized"), 401)
  }
}

fn handle_authorize(request: wisp.Request) -> wisp.Response {
  wisp.require_string_body(request, fn(body) {
    case rlm_rest_request.parse_authorize(body) {
      Error(_) ->
        wisp.json_response(rlm_rest_response.error_body("invalid_request"), 400)
      Ok(parsed) -> {
        let decision = policy_runtime.authorize(parsed)
        wisp.json_response(
          rlm_rest_response.authorize_body(decision),
          rlm_rest_response.authorize_status(decision),
        )
      }
    }
  })
}

fn handle_accounting(request: wisp.Request) -> wisp.Response {
  wisp.require_string_body(request, fn(body) {
    case rlm_rest_request.parse_accounting(body) {
      Error(_) ->
        wisp.json_response(rlm_rest_response.error_body("invalid_request"), 400)
      Ok(parsed) -> {
        let _write = radacct.from_accounting_request(parsed)
        let _record = materializer.to_accounting_record(parsed)
        let _session = materializer.to_active_session(parsed)
        json_ok(rlm_rest_response.accounting_ack_body())
      }
    }
  })
}

fn handle_post_auth(request: wisp.Request) -> wisp.Response {
  wisp.require_string_body(request, fn(body) {
    case rlm_rest_request.parse_post_auth(body) {
      Error(_) ->
        wisp.json_response(rlm_rest_response.error_body("invalid_request"), 400)
      Ok(_) -> json_ok(rlm_rest_response.post_auth_ack_body())
    }
  })
}

fn json_ok(body: String) -> wisp.Response {
  wisp.json_response(body, 200)
}
