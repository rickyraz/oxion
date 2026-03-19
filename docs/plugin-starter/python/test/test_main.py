from src.main import inbound_webhook_adapter


def test_rejects_missing_signature() -> None:
    result = inbound_webhook_adapter(
        {
            "tenant_id": "tnt_001",
            "headers": {},
            "raw_body": "{}",
            "body": {"event": "invoice.paid"},
            "config": {"shared_secret": "supersecretvalue"},
        }
    )

    assert result["decision"] == "rejected"
    assert result["reason"] == "missing_signature"
