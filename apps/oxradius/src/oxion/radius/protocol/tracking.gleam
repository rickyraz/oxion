pub type ProtocolTrack {
  RadiusClassicUdp
  RadSec
  Radius11Experimental
}

pub type FeatureSupport {
  FeatureSupport(
    requires_tls: Bool,
    uses_md5_authenticator: Bool,
    maturity: String,
  )
}

pub fn features(track: ProtocolTrack) -> FeatureSupport {
  case track {
    RadiusClassicUdp ->
      FeatureSupport(
        requires_tls: False,
        uses_md5_authenticator: True,
        maturity: "stable",
      )
    RadSec ->
      FeatureSupport(
        requires_tls: True,
        uses_md5_authenticator: True,
        maturity: "stable",
      )
    Radius11Experimental ->
      FeatureSupport(
        requires_tls: True,
        uses_md5_authenticator: False,
        maturity: "experimental",
      )
  }
}
