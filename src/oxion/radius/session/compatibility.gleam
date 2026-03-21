pub type FreeRadiusSchemaVersion {
  FreeRadiusV1
  FreeRadiusV2
  FreeRadiusV3
  UnknownVersion(value: String)
}

pub type PostAuthColumns {
  PostAuthColumns(user_field: String, date_field: String)
}

pub fn from_string(value: String) -> FreeRadiusSchemaVersion {
  case value {
    "1" -> FreeRadiusV1
    "2" -> FreeRadiusV2
    "3" -> FreeRadiusV3
    _ -> UnknownVersion(value: value)
  }
}

pub fn postauth_columns(version: FreeRadiusSchemaVersion) -> PostAuthColumns {
  case version {
    FreeRadiusV1 -> PostAuthColumns(user_field: "user", date_field: "date")
    FreeRadiusV2 | FreeRadiusV3 | UnknownVersion(_) ->
      PostAuthColumns(user_field: "username", date_field: "authdate")
  }
}
