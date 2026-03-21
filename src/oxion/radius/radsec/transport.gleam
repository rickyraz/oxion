import oxion/radius/radsec/certs
import oxion/radius/radsec/types

pub type ConnectionMode {
  Persistent
  Trunked
}

pub type ConnectionTarget {
  ConnectionTarget(host: String, port: Int, mode: ConnectionMode)
}

pub fn prepare(
  config: types.RadSecConfig,
  target: ConnectionTarget,
) -> Result(ConnectionTarget, types.RadSecError) {
  case certs.validate(config) {
    Ok(_) -> Ok(target)
    Error(error) -> Error(error)
  }
}
