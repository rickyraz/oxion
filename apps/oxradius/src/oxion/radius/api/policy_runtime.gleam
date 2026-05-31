import oxion/radius/api/rlm_rest_request

pub type Decision {
  Allow(reply_message: String)
  Deny(reply_message: String)
}

pub fn authorize(request: rlm_rest_request.AuthorizeRequest) -> Decision {
  let rlm_rest_request.AuthorizeRequest(user_password_present: password, ..) =
    request

  case password {
    True -> Allow(reply_message: "oxRADIUS callback accepted")
    False -> Deny(reply_message: "oxRADIUS callback rejected")
  }
}
