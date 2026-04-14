# oxBill Public Spec

**Module:** Billing and Payment (public contract summary)  
**Status in this repository:** public API/spec only  
**Runtime implementation:** private Enterprise Edition (EE) repository

## 1. Related Documents

- [Open-Core Boundary](../architecture/open-core-boundary.md)
- [Master Architecture and Deployment](../architecture/oxion-infra-deployment-spec.md)
- [Platform Services Specification](../architecture/oxion-platform-services-spec.md)
- [Collection Policy Schema](../policies/collection-policy.schema.json)
- [Collection Policy EBNF](../policies/collection-policy-ebnf.md)

## 2. Public Scope

Public repository keeps the contract-level responsibilities for `oxBill`:

- invoice lifecycle contracts
- voucher and redemption contracts
- payment webhook contracts
- collection policy lifecycle contracts
- integration contracts consumed by `oxCore`, `oxRADIUS`, and `oxNOC`

Implementation details for monetization strategy, fraud/collection intelligence, and enterprise connectors are kept in the private EE repository.

## 3. Contract Surface (Public)

### Invoice APIs

- `GET /v1/invoices`
- `POST /v1/invoices`
- `GET /v1/invoices/:id`
- `GET /v1/invoices/:id/pdf`
- `POST /v1/invoices/:id/pay`
- `POST /v1/invoices/:id/cancel`

### Voucher APIs

- `GET /v1/voucher-batches`
- `POST /v1/voucher-batches`
- `GET /v1/voucher-batches/:id`
- `GET /v1/voucher-batches/:id/vouchers`
- `GET /v1/voucher-batches/:id/pdf`
- `POST /v1/vouchers/redeem`
- `GET /v1/vouchers/:code`
- `DELETE /v1/vouchers/:id`

### Collection Policy APIs

- `GET /v1/collection/policies`
- `POST /v1/collection/policies`
- `GET /v1/collection/policies/:id`
- `PUT /v1/collection/policies/:id`
- `POST /v1/collection/policies/:id/simulate`
- `POST /v1/collection/policies/:id/publish`
- `POST /v1/collection/policies/:id/archive`
- `POST /v1/collection/policies/:id/activate`
- `POST /v1/collection/enforce/run`

### Payment Webhooks

- `POST /v1/payments/webhook/midtrans`
- `POST /v1/payments/webhook/xendit`
- `POST /v1/payments/webhook/stripe`
- `POST /v1/payments/webhook/nowpayments`

## 4. Non-Negotiable Behavior

- No hardcoded tenant-specific collection rules in public core.
- Enforcement actions must be idempotent and deterministic.
- Policy lifecycle must follow schema + EBNF contracts.
- Public modules must remain buildable/testable without private EE runtime.

## 5. Data Contract Baseline

Public contract expects at least these entities:

- `invoices`
- `voucher_batches`
- `vouchers`
- `collection_policies`
- `collection_enforcement_log`

Exact private optimizations, indexes, and enterprise-only tables are maintained in EE documentation and migration assets.

## 6. Notes for Contributors

- Changes that affect billing contract must update:
  - this file,
  - policy schema/EBNF when relevant,
  - conformance evidence for touched phase.
- Do not leak private EE implementation details into public repository.
