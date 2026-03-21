"""Python starter plugin for Oxion Plugin Runner.

Fokus plugin ini: contoh inbound webhook adapter sederhana.
"""

from __future__ import annotations

import hashlib
import hmac
from typing import Any, Dict


def _hmac_sha256_hex(secret: str, raw_body: str) -> str:
    return hmac.new(secret.encode("utf-8"), raw_body.encode("utf-8"), hashlib.sha256).hexdigest()


def inbound_webhook_adapter(input_payload: Dict[str, Any]) -> Dict[str, Any]:
    headers = input_payload.get("headers", {})
    signature = headers.get("x-erp-signature")
    if not signature:
        return {"decision": "rejected", "reason": "missing_signature"}

    config = input_payload.get("config", {})
    secret = config.get("shared_secret", "")
    raw_body = input_payload.get("raw_body", "")

    expected = _hmac_sha256_hex(secret, raw_body)
    if signature != expected:
        return {"decision": "rejected", "reason": "invalid_signature"}

    body = input_payload.get("body", {})
    event = body.get("event")
    tenant_id = input_payload.get("tenant_id")

    if event == "invoice.paid":
        return {
            "decision": "accepted",
            "reason": "mapped_invoice_paid",
            "emit": {
                "topic": f"oxion.billing.invoice_paid.{tenant_id}",
                "payload": {
                    "tenant_id": tenant_id,
                    "service_id": body.get("service_id"),
                    "invoice_id": body.get("invoice_id"),
                    "paid_amount": body.get("paid_amount"),
                    "source": config.get("source_name", "custom_erp"),
                },
            },
        }

    return {"decision": "rejected", "reason": "unsupported_event"}
