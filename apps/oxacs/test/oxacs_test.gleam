import gleeunit
import oxacs

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn build_plan_rejects_offline_device_test() {
  let device =
    oxacs.Device(
      id: "cpe-1",
      serial_number: "SN-1",
      vendor_profile: "huawei_v1",
      status: oxacs.Offline,
    )

  assert oxacs.build_plan(device, oxacs.ActivateCpe)
    == Error(oxacs.DeviceOffline)
}

pub fn build_wifi_plan_is_deterministic_test() {
  let device =
    oxacs.Device(
      id: "cpe-1",
      serial_number: "SN-1",
      vendor_profile: "huawei_v1",
      status: oxacs.Online,
    )

  let first = oxacs.build_plan(device, oxacs.UpdateWifi(ssid: "OXION-NOC"))
  let second = oxacs.build_plan(device, oxacs.UpdateWifi(ssid: "OXION-NOC"))

  assert first == second
}

pub fn build_plan_rejects_empty_wifi_ssid_test() {
  let device =
    oxacs.Device(
      id: "cpe-2",
      serial_number: "SN-2",
      vendor_profile: "zte_v1",
      status: oxacs.Online,
    )

  assert oxacs.build_plan(device, oxacs.UpdateWifi(ssid: ""))
    == Error(oxacs.EmptySsid)
}

pub fn built_plan_stays_within_default_step_budget_test() {
  let device =
    oxacs.Device(
      id: "cpe-3",
      serial_number: "SN-3",
      vendor_profile: "zlt_v1",
      status: oxacs.Provisioning,
    )

  let plan = case
    oxacs.build_plan(device, oxacs.ChangeWanProfile(profile_id: "pppoe-50m"))
  {
    Ok(plan) -> plan
    Error(_) -> panic
  }

  assert oxacs.within_step_budget(plan)
  assert oxacs.max_cycles_per_session() == 4
  assert oxacs.max_steps_per_session() == 64
}
