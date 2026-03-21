# RADIUS Access-Accept and CoA Examples (Vendor-Neutral)

## 1. Dokumen Terkait

- [Tier-1 Broadband Interop Profile](./oxion-tier1-broadband-interoperability-profile.md)
- [oxRADIUS Spec](./oxradius-spec.md)
- [oxBill Spec](./oxbill-spec.md)

---

## 2. Tujuan

Dokumen ini memberi contoh payload netral untuk:

- `Access-Accept` (initial policy)
- `CoA-Request` (throttle/suspend/restore)

Contoh di sini bersifat referensi implementasi adapter dan tidak mengunci VSA vendor tertentu.

---

## 3. Access-Accept (Session Normal)

```json
{
  "packet_type": "Access-Accept",
  "subscriber": {
    "username": "cust_001",
    "session_mode": "ipoe"
  },
  "attributes": {
    "service_profile_id": "svc_home_100m",
    "download_kbps": 102400,
    "upload_kbps": 102400,
    "session_timeout_sec": 86400,
    "idle_timeout_sec": 1800,
    "acct_interim_interval_sec": 300,
    "policy_tag": "normal",
    "class": "tenant_a:svc_home_100m"
  }
}
```

Makna:

- NAS/BNG membuat session subscriber dengan profile normal.
- `class` atau policy tag dapat dipakai untuk observability/accounting correlation.

---

## 4. CoA-Request (Throttle Overdue)

```json
{
  "packet_type": "CoA-Request",
  "reason": "collection_soft_throttle",
  "session_selector": {
    "username": "cust_001",
    "framed_ip": "10.10.20.5"
  },
  "attributes": {
    "service_profile_id": "bw_4mbps",
    "download_kbps": 4096,
    "upload_kbps": 4096,
    "policy_tag": "throttled_due_overdue"
  },
  "idempotency": {
    "fingerprint": "tnt_a:cust_001:soft_throttle:bw_4mbps"
  }
}
```

Expected result:

- NAS update queue/policer ke profile throttled.
- Jika profile aktif sudah sama, NAS adapter boleh skip (`idempotent_skip`).

---

## 5. CoA-Request (Hard Suspend)

```json
{
  "packet_type": "CoA-Request",
  "reason": "collection_hard_suspend",
  "session_selector": {
    "username": "cust_001"
  },
  "attributes": {
    "access_action": "suspend",
    "policy_tag": "suspended_due_overdue"
  },
  "disconnect_hint": true,
  "idempotency": {
    "fingerprint": "tnt_a:cust_001:hard_suspend"
  }
}
```

Expected result:

- Session dibatasi total sesuai capability NAS (disable/quarantine/disconnect).

---

## 6. CoA-Request (Restore After Paid)

```json
{
  "packet_type": "CoA-Request",
  "reason": "payment_received_restore",
  "session_selector": {
    "username": "cust_001"
  },
  "attributes": {
    "service_profile_id": "svc_home_100m",
    "download_kbps": 102400,
    "upload_kbps": 102400,
    "policy_tag": "normal"
  },
  "idempotency": {
    "fingerprint": "tnt_a:cust_001:restore:svc_home_100m"
  }
}
```

---

## 7. ACK/NAK Handling (Normatif)

Contoh CoA-ACK:

```json
{
  "result": "CoA-ACK",
  "nas": "bng-edge-01",
  "applied_profile": "bw_4mbps",
  "request_fingerprint": "tnt_a:cust_001:soft_throttle:bw_4mbps"
}
```

Contoh CoA-NAK:

```json
{
  "result": "CoA-NAK",
  "nas": "bng-edge-01",
  "error_code": "unsupported_attribute",
  "error_message": "policy_tag is not recognized",
  "request_fingerprint": "tnt_a:cust_001:soft_throttle:bw_4mbps"
}
```

Aturan:

- `ACK` -> tandai enforcement success.
- `NAK` -> catat reason + retry policy terbatas + alert ke ops.
