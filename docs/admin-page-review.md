# Dashboard page review — November 15, 2026

This pass adopts the app's official Tween mark and shared table, form, detail,
pagination and confirmation components. Commerce domain forms and state machines
are retained; no financial or compliance actions were executed in production.

## Reviewed surfaces

- Overview, People, person tabs, account editing, sign-in and MFA.
- Orders and fulfillment, sourcing, stores, products/SKUs, merchants, categories.
- Import monitor, imported store/product lists and their curation detail forms.
- Mini-app list/detail/create/edit, app review/appeal queue and review detail.
- OAuth application list/detail and administration activity.
- Every connected resource list/detail now uses explicit presentation metadata,
  descriptive titles, customer context, date formatting and status filters.
- Detail links progressively open an accessible native-dialog side panel, with
  loading/error states, Escape/backdrop close, focus restoration and full-page
  fallback. Turbo confirmations use a shared confirmation dialog.

## Operational coverage added

Read surfaces for cards, customer verification, identity-document metadata,
risk/AML screening, protected payments, refunds, payment links, savings schedules,
rules and activity, exchange rates, rate alerts, recipients, agents, webhook
attempts and backend administration activity. Local read queues cover commerce
disputes, payouts, reviews, warehouses/shipping profiles and social content/reports.

The payment API independently enforces each resource permission. Card responses
contain only masked endings and operational metadata, never PAN/CVV/provider
secrets. Verification responses exclude identity numbers, provider payloads and
document-storage credentials. Lists resolve customers and account names rather
than presenting foreign keys as the primary content.

## Boundaries and remaining work

This is not a claim that all missing workflows are finished. Card issuance,
provider-changing card actions, evidence-file review, identity-document approval,
pocket/stash reversal and advanced dispute settlement need dedicated validated
staff service contracts. This push adds no speculative controls for them.
Document review currently exposes metadata and outcomes, not sensitive evidence.
Existing approved commerce actions remain available through their domain forms.
Detail pages retain their existing rich business forms within shared components;
further page-specific interaction polish remains appropriate after visual review.

Verification: existing admin regression tests, new drawer/brand checks, payment
API contracts, asset compilation and Rails autoload checks. Test data only.
