# Tween Protected Commerce — End-to-End Implementation Specification

Status: Proposed  
Last updated: 2026-08-22  
Owners: Commerce, Tween Pay, Jean, Tween App, Risk and Operations

Implementation progress:

- Foundation started on 2026-08-22.
- Jean protected-order attributes and first-class fulfilment/event models implemented.
- Tween Pay protected-payment state machine and double-entry ledger primitives implemented.
- Funding rail is the in-app Tween wallet (Tween Pay is the payment company): the buyer's
  wallet is debited into a protected-funds ledger hold; release credits the seller's
  business wallet and recognises commission. No external PSP adapter/webhooks are needed
  for the MVP. `provider_transactions` / `provider_webhook_receipts` are intentionally
  omitted until an external licensed provider is contracted.
- Tween Pay internal protected-payments API (`/api/v1/internal/protected_payments/*`),
  transactional outbox to Jean, signed callback consumer, and scheduled release worker
  implemented and spec'd.
- Jean structured offers / counteroffers / acceptance, change orders, disputes, first-class
  fulfilments, delivery confirmation, service submission, milestones, pickup one-time-code
  handover and Matrix offer/order/payment events implemented and tested.
- Jean workers: pending-offer expiry and seller no-show auto-refund (`ExpirePendingOffersJob`,
  `AutoCancelStaleOrdersJob`) wired into Solid Queue `config/recurring.yml`.
- Flutter client: protected-order fields + status card, offer cards with accept/counter in
  the commerce chat, "Protected deal" composer, fund/confirm-delivery/submit-work/dispute
  actions, pickup code generation/confirmation, and service milestone submit/accept UI.
- E2E coverage: Tween Pay request specs exercise the full internal-API lifecycle over HTTP
  (create→fund→schedule→release→refund→dispute→split-resolve); a Jean cross-service journey
  test drives offer→accept→fund→ship→deliver→confirm→signed Tween Pay callback→released,
  plus refund-callback, bad-signature and idempotency cases.
- Provider adapters, external provider contracts, multi-leg milestone scheduling and full
  client flows for milestone bundles remain pending (see Rollout Plan phases 2–5).

## 1. Purpose

This document defines how Tween will implement protected marketplace payments across:

1. Storefront purchases completed through cart and checkout.
2. Marketplace deals negotiated and closed inside a conversation.
3. Artisan and service bookings, including deposits and milestones.

The customer-facing product is **Tween Buyer Protection**. The technical and legal description is **delayed marketplace settlement**. Tween must not claim that it operates an escrow service unless the selected licensed payment provider and Nigerian legal counsel approve that terminology and funds-flow model.

The core promise is:

> The buyer pays before fulfilment, but the seller's proceeds are released only after the agreed delivery or service conditions are satisfied.

## 2. Product principles

- A direct P2P transfer is immediate and is not protected.
- Protection applies only to a structured Tween order accepted by both parties.
- Free-form chat messages never become financial instructions by themselves.
- Jean is authoritative for commerce orders, offers and fulfilment.
- Tween Pay is authoritative for money, ledger entries, settlement, refunds and provider reconciliation.
- Matrix events communicate authoritative backend state; clients cannot create or override financial state.
- The licensed provider or banking partner holds or safeguards money. Tween must not simulate held funds with an ordinary application balance.
- Release and refund operations are idempotent, auditable and initiated only by trusted backend workers.

## 3. Terminology

| Term | Meaning |
|---|---|
| Protected order | An order eligible for Tween Buyer Protection |
| Protected payment | The buyer's payment associated with a protected order |
| Settlement hold | The period between confirmed funding and seller release |
| Release | Moving seller proceeds to the seller's payable balance or provider subaccount |
| Payout | Moving released proceeds to the seller's bank account |
| Inspection period | Time available to report a fulfilment problem before automatic release |
| Structured offer | Versioned terms proposed inside a conversation |
| Change order | An accepted amendment to a service scope, price or deadline |
| Milestone | A separately reviewable and releasable portion of a service order |

Customer interfaces use “Payment protected”, “Payment secured”, “Pending release”, “Buyer Protection” and “Payment released”. They do not say “Tween holds your money in escrow”.

## 4. Supported commerce modes

### 4.1 Storefront checkout

```text
Product → Cart → Checkout → Pay → Payment protected
        → Fulfilment → Delivery → Inspection → Release → Payout
```

The checkout creates a normal `CommerceOrder` with `source = storefront`. Existing inventory reservation, shipping and pricing logic remains in Jean.

### 4.2 Conversation-led product deal

```text
Negotiation → Structured offer → Counteroffer or acceptance
            → CommerceOrder(source=conversation) → Pay
            → Fulfilment → Delivery → Inspection → Release
```

The chat is the negotiation surface. An accepted structured offer—not the chat transcript—defines the binding order terms.

The payment menu exposes two distinct actions:

- **Send money** — immediate P2P transfer, no Buyer Protection.
- **Create protected deal** — structured order with delayed seller settlement.

Before a direct transfer related to a sale, show:

> Direct payments are released immediately and are not covered by Tween Buyer Protection.

### 4.3 Artisan or service booking

```text
Job discussion → Quote → Acceptance → Protected funding
               → Work or milestones → Customer review
               → Release → Warranty period (if offered)
```

Service orders use `ServiceFulfilment` and optional milestones rather than shipment delivery.

The first release should support:

- One optional non-refundable call-out or booking fee.
- One protected completion payment.

Arbitrary milestone schedules and split releases follow after the single-completion flow is stable.

## 5. System ownership

| System | Owns |
|---|---|
| Tween App | Offer composer, checkout, payment UI, fulfilment evidence, delivery confirmation, disputes and status rendering |
| Jean | Listings, conversations, offers, orders, order terms, fulfilment, eligibility and commerce policy |
| Tween Pay | Payment collection, provider adapter, immutable ledger, settlement holds, release, refund, payout and reconciliation |
| Matrix homeserver | Delivery of structured room events and push notifications |
| Licensed provider/bank | Custody or safeguarding, collection, seller accounts and external settlement |
| Operations console | KYC review, disputes, risk holds, reconciliation exceptions and manual actions |

Jean must never calculate available seller funds. Tween Pay must never infer order completion from a client event.

## 6. Authoritative state machines

### 6.1 Commerce order

Extend `CommerceOrder` without replacing its existing lifecycle immediately.

```text
draft
awaiting_acceptance
pending_payment
paid
processing
fulfilled
completed
cancelled
refunded
partially_refunded
```

Add separate fields instead of packing protected-payment state into `status`:

```text
source: storefront | conversation | service_booking
protection_status: not_eligible | eligible | active | completed | void
fulfilment_type: shipment | local_delivery | pickup | service
terms_version
accepted_offer_id
```

### 6.2 Protected payment

Tween Pay owns this state machine:

```text
created
payment_pending
funded
release_scheduled
release_processing
released

refund_pending
refunded
partially_refunded

disputed
under_review
resolved_buyer
resolved_seller
resolved_split

payment_failed
release_failed
cancelled
```

Rules:

- Only a verified provider result or webhook can establish `funded`.
- `funded` money cannot be presented as seller-available funds.
- Opening a dispute cancels any scheduled release atomically.
- `released` and fully `refunded` are mutually exclusive terminal outcomes.
- Partial resolution must preserve `released + refunded + remaining = funded`.
- Release workers lock the payment row and recheck all conditions before calling the provider.

### 6.3 Shipment fulfilment

```text
unfulfilled → preparing → shipped → delivered → accepted
                         ↘ failed
```

“Shipped” requires a carrier/tracking record or seller delivery declaration. “Delivered” comes from an integrated logistics webhook, buyer confirmation, or an approved manual operation—not from the seller alone.

### 6.4 Pickup fulfilment

```text
scheduled → ready → handover_pending → handed_over → accepted
```

Handover confirmation may use a buyer-generated one-time code or QR challenge. The code is short-lived, hashed at rest and single use.

### 6.5 Service fulfilment

```text
scheduled → in_progress → submitted → inspection → accepted
                        ↘ revision_requested
                        ↘ disputed
```

Completion evidence can include photos, documents, receipts, test results and customer sign-off. Evidence is append-only after submission.

## 7. Structured offers and service quotes

### 7.1 Offer fields

Create `CommerceOffer` with:

```text
offer_id
conversation_id
proposer_user_id
recipient_user_id
offer_type: product | service
version
status: draft | proposed | accepted | declined | expired | superseded
currency
subtotal_cents
delivery_fee_cents
buyer_fee_cents
discount_cents
total_cents
commission_cents
seller_proceeds_cents
expires_at
terms_json
accepted_at
accepted_by_user_id
```

`terms_json` is schema-versioned and contains product snapshots, condition, quantity, delivery method, service scope, materials, deadlines, warranty and cancellation terms.

### 7.2 Versioning

- Proposed offers are immutable.
- Editing creates a new version and supersedes the previous version.
- A counteroffer is a new version proposed by the other party.
- Acceptance uses optimistic locking and an idempotency key.
- Acceptance fails if the offer expired, was superseded or its inventory is unavailable.
- Accepted terms are copied into immutable order snapshots.

### 7.3 Service-specific terms

Service quotes additionally contain:

```text
scope
location
scheduled_start_at
expected_duration
labour_cents
materials_cents
materials_purchased_by: buyer | artisan
callout_fee_cents
callout_fee_refundable
completion_criteria
warranty_days
cancellation_policy_id
```

### 7.4 Change orders

Unexpected service work uses `CommerceChangeOrder`:

```text
change_order_id
order_id
proposer_user_id
scope_delta
amount_delta_cents
deadline_delta
status
accepted_at
```

No price or scope change takes effect until the customer accepts it. If additional funding is required, acceptance creates a new protected-payment increment before work continues.

## 8. Data model

### 8.1 Jean additions

- `commerce_offers`
- `commerce_change_orders`
- `commerce_fulfillments`
- `commerce_fulfillment_events`
- `commerce_service_milestones`
- `commerce_disputes` (case metadata; financial freeze remains in Tween Pay)
- `commerce_dispute_evidence`
- New protected-commerce columns on `commerce_orders`

Do not continue storing fulfilments solely in `CommerceOrder.metadata`. Migrate existing metadata records into first-class fulfilment rows and retain a compatibility serializer during rollout.

### 8.2 Tween Pay additions

- `protected_payments`
- `protected_payment_events`
- `ledger_accounts`
- `ledger_transactions`
- `ledger_entries`
- `provider_transactions`
- `provider_webhook_receipts`
- `settlement_releases`
- `refunds`
- `seller_payout_accounts`
- `seller_payouts`
- `reconciliation_runs`
- `reconciliation_exceptions`

All monetary columns use integer minor units and an explicit ISO currency. Never use floating-point values for ledger operations.

### 8.3 Protected payment fields

```text
protected_payment_id
order_id
buyer_user_id
seller_user_id
merchant_id
currency
gross_amount_cents
seller_proceeds_cents
commission_cents
provider_fee_cents
released_amount_cents
refunded_amount_cents
status
provider
provider_payment_reference
provider_hold_reference
release_at
funded_at
disputed_at
released_at
refunded_at
idempotency_key
lock_version
```

## 9. Ledger

Use double-entry accounting. Every ledger transaction balances to zero and is immutable after posting.

Example for a NGN 10,000 payment with NGN 500 commission:

```text
Funding confirmed
Dr Provider clearing       10,000
Cr Protected funds         10,000

Release approved
Dr Protected funds         10,000
Cr Seller payable           9,500
Cr Commission revenue         500

Seller payout
Dr Seller payable           9,500
Cr Provider clearing        9,500
```

Refunds reverse protected funds; chargebacks post to a separate chargeback receivable/reserve account. Never edit prior ledger entries to “fix” reconciliation.

## 10. APIs

### 10.1 Jean public commerce API

```http
POST /api/v1/commerce/conversations/:id/offers
GET  /api/v1/commerce/conversations/:id/offers
POST /api/v1/commerce/offers/:id/counter
POST /api/v1/commerce/offers/:id/accept
POST /api/v1/commerce/offers/:id/decline

GET  /api/v1/commerce/orders/:id
POST /api/v1/commerce/orders/:id/fulfillments
POST /api/v1/commerce/orders/:id/confirm_delivery
POST /api/v1/commerce/orders/:id/service_submission
POST /api/v1/commerce/orders/:id/change_orders
POST /api/v1/commerce/change_orders/:id/accept

POST /api/v1/commerce/orders/:id/disputes
POST /api/v1/commerce/disputes/:id/evidence
GET  /api/v1/commerce/disputes/:id
```

Every mutating endpoint accepts `Idempotency-Key`. Jean authorizes participants from Matrix/TEP identity and never trusts user IDs supplied in the request body.

### 10.2 Tween Pay protected-payment API

Jean calls authenticated internal endpoints:

```http
POST /api/v1/internal/protected_payments
GET  /api/v1/internal/protected_payments/:id
POST /api/v1/internal/protected_payments/:id/schedule_release
POST /api/v1/internal/protected_payments/:id/cancel_release
POST /api/v1/internal/protected_payments/:id/refund
POST /api/v1/internal/protected_payments/:id/open_dispute
POST /api/v1/internal/protected_payments/:id/resolve_dispute
```

Mobile clients receive checkout/payment-session data through Jean but cannot invoke internal release, refund or dispute-resolution endpoints.

### 10.3 Service-to-service security

- Short-lived service credentials or signed JWTs with audience restrictions.
- TLS for all traffic; mTLS when infrastructure supports it.
- Request timestamp and nonce for high-risk operations.
- Idempotency key scoped to endpoint and actor.
- Constant-time signature comparison.
- Structured audit log containing actor, reason, before state and after state.

## 11. Provider integration

The selected provider must contractually support marketplace collection, delayed/manual settlement, seller onboarding, refunds, webhooks, reconciliation and chargeback handling.

Paystack split payments divide settlement and must not be assumed to provide a protected hold. Product and legal teams must obtain written provider approval for the intended funds flow.

> **MVP decision (2026-08-22):** Tween Pay is itself a licensed payment company and the
> funding rail is the in-app Tween wallet. No external PSP is required for the MVP:
> funding debits the buyer's wallet into the `protected_funds` ledger liability; release
> credits the seller's business wallet and recognises `commission_revenue`. The ledger
> `wallet_pool` account mirrors the aggregate wallet float. An external licensed provider
> (with its own `provider_transactions` / `provider_webhook_receipts` tables and adapter)
> is still the Phase 0–2 launch-gate consideration for custody language, but is not a
> code prerequisite for the in-app wallet flow.

Provider adapters implement a common interface:

```text
create_payment
verify_payment
create_seller_account
release_funds
refund_funds
get_transaction
get_balance
verify_webhook
```

Provider webhooks are stored before processing. Duplicate delivery returns success without repeating the transition. Unknown references enter an exception queue.

## 12. End-to-end flows

### 12.1 Storefront product purchase

1. Buyer checks out in Tween App.
2. Jean calculates immutable totals, reserves inventory and creates `pending_payment` order.
3. Jean requests a protected payment from Tween Pay.
4. Tween Pay creates a provider payment session.
5. Buyer pays through the provider-supported method.
6. Provider webhook confirms funding.
7. Tween Pay posts ledger entries and marks payment `funded`.
8. Tween Pay notifies Jean through a signed idempotent callback.
9. Jean marks order `paid`, commits inventory and publishes Matrix status.
10. Seller fulfils the order.
11. Delivery confirmation starts the inspection timer.
12. If no dispute exists when the timer expires, Jean requests release.
13. Tween Pay revalidates state, releases seller proceeds and records commission.
14. Seller payout follows provider settlement rules.

### 12.2 Conversation product deal

1. Buyer and seller negotiate in a commerce conversation.
2. One participant creates a structured offer.
3. Jean publishes an interactive offer card.
4. Counteroffers create immutable versions.
5. Acceptance creates a `source=conversation` order.
6. Buyer funds the protected payment.
7. The remaining flow converges with storefront fulfilment and settlement.

### 12.3 Artisan service

1. Customer describes the job in conversation.
2. Artisan sends a structured service quote.
3. Customer accepts terms and funds the protected component.
4. Any call-out fee follows the accepted cancellation policy.
5. Artisan begins and records work progress.
6. Unexpected scope uses a change order.
7. Artisan submits completion evidence.
8. Customer approves, requests revision or opens a dispute.
9. Approval or inspection timeout schedules release.
10. Tween Pay releases the protected completion amount.

### 12.4 Cancellation

- Before funding: cancel without financial action.
- Funded but not accepted/started: full refund unless an explicit eligible call-out fee applies.
- Materials already purchased: manual or policy-based review of approved, evidenced costs.
- Partially completed milestones: release accepted milestones and refund the remainder.
- Seller no-show or missed fulfilment deadline: automatic cancellation/refund subject to policy.

## 13. Delivery confirmation and release policy

Release must not depend exclusively on buyer action.

Recommended MVP policy:

- Seller has 48 hours to accept/start fulfilment unless the offer states otherwise.
- Integrated carrier delivery starts a 24-hour inspection period.
- Buyer confirmation starts or completes the inspection period according to risk policy.
- No dispute at deadline schedules automatic release.
- Opening a dispute atomically freezes release.
- Seller self-declaration alone cannot establish delivery.
- Manual release requires two-person approval above the configured risk threshold.

Policy durations are configuration records, versioned and copied onto each order so later policy changes do not alter existing deals.

## 14. Disputes

Supported reasons:

- Item not received.
- Item materially different from accepted terms.
- Damaged, counterfeit, prohibited or wrong-quantity item.
- Service not started or not completed.
- Materially deficient workmanship.
- Unapproved additional charges.

Opening a dispute records the payment snapshot, accepted terms, listing snapshot, chat event references, fulfilment chronology and evidence. Evidence uploads use signed URLs, malware scanning, content limits and retention policy.

Resolution outcomes:

- Full refund to buyer.
- Full release to seller.
- Split resolution.
- Revision/reperformance window for services.

Operations actions require reason codes and immutable audit records. The resolver cannot be the same operator who performed a prior manual release/refund action on the case.

## 15. Matrix events and realtime UI

Jean publishes backend-owned events as `m.room.message` with structured Tween `msgtype` values when they should trigger normal push, unread and room-ordering behavior.

```text
m.tween.commerce.offer
m.tween.commerce.offer.updated
m.tween.commerce.order.created
m.tween.commerce.payment.funded
m.tween.commerce.fulfilment.updated
m.tween.commerce.delivery.confirmed
m.tween.commerce.inspection.started
m.tween.commerce.dispute.opened
m.tween.commerce.payment.released
m.tween.commerce.payment.refunded
```

Silent protocol events may update an existing card but must not render as “User sent a … event”. Financial cards always reconcile against Jean/Tween Pay on open; Matrix is not the financial database.

## 16. Client experience

### Buyer

- Clear distinction between direct payment and protected deal.
- Exact total, fees and protection terms before payment.
- Persistent order card in chat and Orders.
- Delivery confirmation and visible inspection deadline.
- “Report a problem” action while eligible.
- Plain-language refund/release status.

### Seller or artisan

- Required identity and payout onboarding before accepting protected deals.
- Net proceeds and expected release date shown before acceptance.
- Fulfilment deadline and evidence requirements.
- Status separating “payment secured” from “available to withdraw”.
- Change-order flow for additional service work.

## 17. Notifications

Push, in-app and optional Convert messages are generated for:

- Offer received, accepted, declined or expiring.
- Funding confirmed or failed.
- Fulfilment deadline approaching.
- Shipped, delivered or service submitted.
- Inspection deadline approaching.
- Dispute opened or updated.
- Payment released, refunded or payout failed.

Notifications carry order IDs, not sensitive financial details. Delivery webhooks determine final notification state where applicable.

## 18. Security, fraud and compliance

- Seller KYC and verified payout ownership are mandatory before release.
- Risk rules inspect account age, device, velocity, value, category, dispute history and linked identities.
- Prohibited goods/services are blocked before funding.
- High-risk orders use longer inspection or manual release.
- Release destination cannot change after funding without enhanced verification and a cooling-off period.
- Provider secrets remain in Tween Pay only.
- Sensitive logs are redacted.
- Admin access uses least privilege, MFA and auditable reason codes.
- Legal/provider approval is a launch gate for terminology, custody, safeguarding, refunds and chargeback ownership.

## 19. Reliability and reconciliation

- Use transactional outbox tables for Jean ↔ Tween Pay state propagation.
- Consumers are idempotent and tolerate duplicate/out-of-order events.
- Scheduled release jobs lock records and recheck dispute/refund state.
- Reconcile provider transactions and balances at least daily.
- Alert on funded payments without orders, paid orders without funded payments, negative seller payables, webhook gaps and release mismatches.
- Provide replay tooling for failed outbox/webhook events.
- Never use a Matrix event as proof that a provider operation succeeded.

## 20. Observability

Required metrics:

- Payment funding success rate and latency.
- Funded-to-fulfilment time.
- Delivery-to-release time.
- Release/refund failure rate.
- Dispute rate by category, seller and value band.
- Auto-release versus manual-release ratio.
- Provider webhook delay and duplicate rate.
- Reconciliation exception count and age.
- Seller payout failure rate.

Every request and event carries `trace_id`, `order_id` and `protected_payment_id` where available.

## 21. Testing strategy

### Unit tests

- Every allowed and forbidden state transition.
- Fee, commission, refund and split-resolution calculations.
- Ledger balancing and terminal-state invariants.
- Offer versioning and expiry.
- Release eligibility and policy deadlines.

### Integration tests

- Jean order ↔ Tween Pay payment callbacks.
- Provider webhook signature, duplicate and out-of-order handling.
- Funding, release, refund, payout and reconciliation.
- Matrix publication and client card reconciliation.

### Concurrency and failure tests

- Release racing with dispute creation.
- Refund racing with release.
- Duplicate acceptance/payment submissions.
- Provider timeout after successful operation.
- Worker crash between provider response and local commit.
- Replayed webhook after terminal resolution.

### End-to-end scenarios

- Storefront delivery and successful release.
- Conversation offer/counteroffer/acceptance.
- Pickup code handover.
- Artisan completion and change order.
- Buyer dispute and full refund.
- Split dispute resolution.
- Inactive buyer automatic release.
- Seller no-show automatic refund.

## 22. Rollout plan

### Phase 0 — Provider and legal validation

- Confirm licensed provider funds flow in writing.
- Define merchant of record, custody, safeguarding, refunds and chargeback liability.
- Approve customer terminology and policies.

### Phase 1 — Foundation

- Add protected-payment state machine and double-entry ledger to Tween Pay.
- Add first-class fulfilment rows and protected-order fields to Jean.
- Implement provider sandbox adapter, webhooks, outbox and reconciliation.

### Phase 2 — Storefront pilot

- Enable protected checkout for selected verified sellers/categories.
- Use shipment or integrated local delivery only.
- Operate manual dispute resolution.

### Phase 3 — Conversation product deals

- Add structured offers and counteroffers.
- Convert accepted offers into standard protected orders.
- Add pickup fulfilment.

### Phase 4 — Artisan services

- Add service quotes, completion evidence and change orders.
- Launch booking fee plus completion payment.
- Add milestones after operational validation.

### Phase 5 — Scale and automation

- Automated risk tiers, dispute tooling, logistics integrations and configurable release policies.
- Broader categories and seller cohorts based on measured loss/dispute performance.

## 23. Launch gates

Production launch is blocked until:

- Provider and counsel approve the funds flow and customer language.
- Ledger invariants and reconciliation pass in sandbox and controlled live tests.
- Duplicate webhook and concurrency tests pass.
- Refund and release recovery procedures are rehearsed.
- Operations can freeze, investigate and resolve payments.
- Seller KYC/payout verification is enforced.
- Buyer Protection terms, prohibited items and dispute policy are published.
- Monitoring and on-call runbooks are active.

## 24. External implementation references

- Paystack split payments (settlement splitting, not assumed escrow): https://paystack.com/docs/payments/split-payments/
- Stripe marketplace charge models: https://docs.stripe.com/connect/charges
- Stripe separate charges and transfers: https://docs.stripe.com/connect/separate-charges-and-transfers
- CBN escrow structure guidance: https://www.cbn.gov.ng/out/2020/fmd/cbn%20rule%20book%20volume%202.pdf

These references inform the architecture but do not establish that a particular provider or regulatory model is approved for Tween. Provider contracting and Nigerian legal review remain mandatory launch prerequisites.
