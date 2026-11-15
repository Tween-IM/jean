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

## Operational controls completed in the follow-up

- Payment-account lookup, KYC reset and card issuance from current reviewed
  provider quotes, with explicit charge confirmation and verified customer identity.
- Card freeze/unfreeze/termination, provider refresh and persistent command
  receipts. Unknown issuance uses the original provider reference for reconciliation;
  queued provider operations are shown as accepted until confirmed.
- Authenticated document evidence viewing with an exact storage-host allowlist,
  public-IP validation, bounded downloads and an audit tied to the document version.
  Approval requires the reviewing staff member's evidence-view audit; expired
  documents cannot be approved. Evidence and identity numbers stay out of lists.
- Pocket/stash refunds and individual movement reversals conserve funds between
  the savings account and its own active wallet. Reversals cannot be repeated.
- Savings rule/schedule pause and resume, local review/content/report moderation,
  and commerce dispute settlement through the existing protected-payment service.
  Unknown settlement outcomes retain the original request for safe reconciliation.

## Deployment prerequisites and remaining boundaries

Run Tween Pay's new savings-reversal migration. Configure
`IDENTITY_DOCUMENT_ALLOWED_HOSTS` on Tween Pay with the exact HTTPS storage hosts
used for customer uploads. Evidence access fails closed without this allowlist.
Card issuance requires a configured Clover integration and an active reviewed
issuance quote; the UI offers no speculative or unpriced issuance option.

General MAS client/provider/session management, advanced Synapse maintenance and
business provisioning remain engineering-console workflows. Existing commerce
forms remain within the shared design. No production financial/compliance actions
were used to validate this work.

Verification: existing admin regression tests, new drawer/brand checks, payment
API contracts, asset compilation and Rails autoload checks. Test data only.
