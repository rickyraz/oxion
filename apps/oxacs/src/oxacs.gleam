import gleam/list

pub type DeviceStatus {
  Online
  Offline
  Provisioning
  ErrorState
}

pub type Device {
  Device(
    id: String,
    serial_number: String,
    vendor_profile: String,
    status: DeviceStatus,
  )
}

pub type Intent {
  ActivateCpe
  UpdateWifi(ssid: String)
  ChangeWanProfile(profile_id: String)
  UpgradeFirmware(version: String)
}

pub type PlanStep {
  EnsureOnline
  SetParameter(path: String, value: String)
  Commit
}

pub type Plan {
  Plan(plan_id: String, device_id: String, steps: List(PlanStep))
}

pub type PlanError {
  DeviceOffline
  EmptySsid
  EmptyProfile
  EmptyFirmwareVersion
}

/// Builds deterministic execution steps for a CPE intent.
pub fn build_plan(device: Device, intent: Intent) -> Result(Plan, PlanError) {
  let Device(
    id: device_id,
    serial_number: _serial_number,
    vendor_profile: _vendor_profile,
    status: status,
  ) = device

  case status {
    Offline -> Error(DeviceOffline)
    _ -> build_online_plan(device_id, intent)
  }
}

fn build_online_plan(
  device_id: String,
  intent: Intent,
) -> Result(Plan, PlanError) {
  case intent {
    ActivateCpe ->
      Ok(
        Plan(
          plan_id: fingerprint(device_id, "activate"),
          device_id: device_id,
          steps: [EnsureOnline, Commit],
        ),
      )

    UpdateWifi(ssid) ->
      case ssid == "" {
        True -> Error(EmptySsid)
        False ->
          Ok(
            Plan(
              plan_id: fingerprint(device_id, "wifi:" <> ssid),
              device_id: device_id,
              steps: [
                EnsureOnline,
                SetParameter(path: "Device.WiFi.SSID.1.SSID", value: ssid),
                Commit,
              ],
            ),
          )
      }

    ChangeWanProfile(profile_id) ->
      case profile_id == "" {
        True -> Error(EmptyProfile)
        False ->
          Ok(
            Plan(
              plan_id: fingerprint(device_id, "wan:" <> profile_id),
              device_id: device_id,
              steps: [
                EnsureOnline,
                SetParameter(path: "Device.WAN.Profile", value: profile_id),
                Commit,
              ],
            ),
          )
      }

    UpgradeFirmware(version) ->
      case version == "" {
        True -> Error(EmptyFirmwareVersion)
        False ->
          Ok(
            Plan(
              plan_id: fingerprint(device_id, "fw:" <> version),
              device_id: device_id,
              steps: [
                EnsureOnline,
                SetParameter(
                  path: "Device.ManagementServer.DownloadVersion",
                  value: version,
                ),
                Commit,
              ],
            ),
          )
      }
  }
}

pub fn max_cycles_per_session() -> Int {
  4
}

pub fn max_steps_per_session() -> Int {
  64
}

pub fn within_step_budget(plan: Plan) -> Bool {
  let Plan(plan_id: _plan_id, device_id: _device_id, steps: steps) = plan
  list.length(steps) <= max_steps_per_session()
}

fn fingerprint(device_id: String, action_identity: String) -> String {
  device_id <> ":" <> action_identity
}
