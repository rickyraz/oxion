import gleam/int
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

pub fn render_status_command(
  binary: String,
  endpoint: types.NasEndpoint,
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
      Ok(
        RadclientCommand(
          binary: binary,
          arguments: [
            coa_host <> ":" <> int.to_string(coa_port),
            "status",
            value,
          ],
          attributes: ["Message-Authenticator := 0x00"],
        ),
      )
    types.EnvSecret(_) -> Error(UnsupportedSecretRef(kind: "env_secret"))
    types.VaultSecret(_, _) -> Error(UnsupportedSecretRef(kind: "vault_secret"))
  }
}
