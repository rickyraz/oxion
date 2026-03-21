import gleam/int
import gleam/list
import oxion/radius/registry/types

pub type RenderError {
  UnsupportedSecretRef(kind: String)
}

pub type RadclientCommand {
  RadclientCommand(
    binary: String,
    arguments: List(String),
    attributes: List(String),
  )
}

pub type PacketFamily {
  Status
  Coa
  Disconnect
}

pub fn render_status_command(
  binary: String,
  endpoint: types.NasEndpoint,
) -> Result(RadclientCommand, RenderError) {
  render_command(binary, endpoint, Status, [])
}

pub fn render_coa_command(
  binary: String,
  endpoint: types.NasEndpoint,
  attributes: List(String),
) -> Result(RadclientCommand, RenderError) {
  render_command(binary, endpoint, Coa, attributes)
}

pub fn render_disconnect_command(
  binary: String,
  endpoint: types.NasEndpoint,
  attributes: List(String),
) -> Result(RadclientCommand, RenderError) {
  render_command(binary, endpoint, Disconnect, attributes)
}

fn render_command(
  binary: String,
  endpoint: types.NasEndpoint,
  family: PacketFamily,
  attributes: List(String),
) -> Result(RadclientCommand, RenderError) {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: _endpoint_id,
    vendor: _vendor,
    transport: _transport,
    coa_host: coa_host,
    coa_port: coa_port,
    secret_ref: secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: _capabilities,
  ) = endpoint

  case secret_ref {
    types.InlineSecret(value) ->
      Ok(RadclientCommand(
        binary: binary,
        arguments: [
          coa_host <> ":" <> int.to_string(coa_port),
          packet_family_name(family),
          value,
        ],
        attributes: base_attributes(family) |> list.append(attributes),
      ))
    types.EnvSecret(_) -> Error(UnsupportedSecretRef(kind: "env_secret"))
    types.VaultSecret(_, _) -> Error(UnsupportedSecretRef(kind: "vault_secret"))
  }
}

fn packet_family_name(family: PacketFamily) -> String {
  case family {
    Status -> "status"
    Coa -> "coa"
    Disconnect -> "disconnect"
  }
}

fn base_attributes(family: PacketFamily) -> List(String) {
  case family {
    Status -> ["Packet-Type := Status-Server", "Message-Authenticator := 0x00"]
    Coa -> []
    Disconnect -> []
  }
}
