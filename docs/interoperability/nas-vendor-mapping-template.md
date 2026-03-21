# NAS Vendor Mapping Template (Cisco / Juniper / vBNG)

## 1. Dokumen Terkait

- [Tier-1 Broadband Interop Profile](oxion-tier1-broadband-interoperability-profile.md)
- [RADIUS Access-Accept and CoA Examples](radius-access-coa-examples.md)
- [oxRADIUS Spec](../modules/oxradius-spec.md)

---

## 2. Tujuan

Template ini dipakai untuk memetakan policy internal Oxion ke format enforcement tiap NAS/BNG vendor.

Prinsip:

- Core policy tetap vendor-agnostic.
- Mapping detail dikunci di adapter profile.

---

## 3. Template Mapping (Isi per Vendor)

```yaml
vendor_profile_id: "<vendor>-<model>-<version>"
vendor: "cisco|juniper|vbng"
model_family: "<asr|ncs|mx|whitebox>"
software_version: "<string>"
session_mode_support:
  ipoe: true
  pppoe: true

attribute_mapping:
  service_profile_id:
    target: "<vendor_field_or_attr>"
    required: true
  download_kbps:
    target: "<vendor_qos_down_attr>"
    required: true
  upload_kbps:
    target: "<vendor_qos_up_attr>"
    required: true
  policy_tag:
    target: "<vendor_policy_tag_attr>"
    required: false
  access_action:
    target: "<vendor_suspend_or_acl_attr>"
    required: false

coa_capabilities:
  supports_qos_update_without_disconnect: true
  supports_suspend_action: true
  supports_restore_action: true
  supports_session_selector_username: true
  supports_session_selector_framed_ip: true

idempotency:
  compare_active_profile_before_coa: true
  skip_if_same_profile: true

fallback_rules:
  - when: "vendor_attr_not_supported"
    action: "use_standard_attr_set"
  - when: "coa_nak_unsupported_attribute"
    action: "drop_optional_attr_and_retry_once"

observability:
  emit_vendor_apply_metric: true
  emit_vendor_error_reason: true
```

---

## 4. Contoh Ringkas per Vendor

## Cisco BNG (Contoh)

```yaml
vendor_profile_id: "cisco-asr9k-iosxr7"
vendor: "cisco"
model_family: "asr"
software_version: "iosxr7.x"
attribute_mapping:
  service_profile_id: { target: "cisco_avpair.service_profile", required: true }
  download_kbps: { target: "cisco_avpair.qos_down", required: true }
  upload_kbps: { target: "cisco_avpair.qos_up", required: true }
  policy_tag: { target: "class", required: false }
```

## Juniper MX BNG (Contoh)

```yaml
vendor_profile_id: "juniper-mx-junos23"
vendor: "juniper"
model_family: "mx"
software_version: "junos23.x"
attribute_mapping:
  service_profile_id: { target: "dynamic_profile.name", required: true }
  download_kbps: { target: "dynamic_profile.policer_down", required: true }
  upload_kbps: { target: "dynamic_profile.policer_up", required: true }
  policy_tag: { target: "class", required: false }
```

## Disaggregated vBNG (Contoh)

```yaml
vendor_profile_id: "vbng-generic-api-v1"
vendor: "vbng"
model_family: "whitebox"
software_version: "api-v1"
attribute_mapping:
  service_profile_id: { target: "api.policy.profile_id", required: true }
  download_kbps: { target: "api.policy.down_kbps", required: true }
  upload_kbps: { target: "api.policy.up_kbps", required: true }
  access_action: { target: "api.policy.access_action", required: false }
```

---

## 5. Checklist Validasi Mapping

- Mapping initial `Access-Accept` bisa apply profile normal.
- CoA throttle apply tanpa disconnect paksa (jika vendor support).
- CoA suspend bekerja konsisten.
- Restore kembali ke profile asli.
- Idempotent skip berjalan saat target profile sama.
- NAK reason diterjemahkan ke error code internal Oxion.
