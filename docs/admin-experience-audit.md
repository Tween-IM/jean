# Tween staff workspace: experience audit and implementation

Reviewed 16 November 2026. The organising unit is a staff task and a customer, rather than a backend service or database table.

## Research and decisions

- [Shopify information architecture](https://github.com/Shopify/polaris-react-archive/blob/main/polaris.shopify.com/content/foundations/information-architecture.mdx): records have one canonical home, reached through contextual links. People is that home for Tween accounts; financial access and identity history are profile sections.
- [Carbon navigation](https://www.carbondesignsystem.com/building-blocks/core/components/ui-shell-left-panel/guidelines): keep navigation shallow. Stable primary areas stay visible; only the selected area's secondary destinations are expanded. Deeper workflow variants use tabs.
- [Carbon disclosure patterns](https://www.carbondesignsystem.com/building-blocks/core/patterns/disclosures): filters are a compact toolbar with a separate apply/reset panel, rather than a permanent wall of controls.
- [Carbon pagination](https://www.carbondesignsystem.com/building-blocks/core/components/pagination/guidelines): results have a range, total, current page, previous/next and a bounded density choice. Filtering resets the page; pagination preserves filters.
- [WAI-ARIA combobox pattern](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/): search and selection need explicit keyboard, expanded, selected and active-option semantics. Custom select popups retain native form values and validation.
- [Lucide](https://lucide.dev/guide/static): all dashboard icons come from the pinned `lucide-static` package. Only required SVG assets are vendored; no icon-font payload or remote runtime. SVG source and ISC licence are retained in `app/assets/images/admin/icons`.

## Canonical structure

| Primary area | Staff purpose | Destinations |
| --- | --- | --- |
| Overview | Decide what needs attention | Operational overview and contextual queue links |
| People | Understand and support one person | One directory; Profile, Commerce, Apps & access, Compliance, Payments, Messaging and Identity sections; business records |
| Commerce | Operate stores and fulfil orders | Orders, Sourcing, Stores, Products, Merchants, Categories, Imports, Disputes, Payouts, Reviews, Warehouses, Shipping profiles |
| Money | Investigate financial records | Wallets, Transactions, Cards, Pending transfers, Payment links, Protected payments, Refunds, Bank accounts, Bills, Savings, Exchange rates, Recipients and Agents |
| Trust & safety | Review evidence and recorded risk | Monitoring, Review cases (identity/screening/documents tabs), Risk assessments, message/content reports |
| Community | Moderate community surfaces | Rooms, Feed posts, Stories |
| Mini-apps | Manage distribution and review | Apps, Review queue, OAuth clients |
| Settings | Operate platform integrations | API keys, Webhooks (endpoint/delivery tabs), Notifications, one Activity log (workspace/financial streams) |

A keyboard page finder provides direct access to all permitted destinations. Permissions filter both navigation and actions; the backend independently enforces live actor permissions.

The Payment accounts and Customer KYC status directories redirect to People. Legacy detail URLs resolve the person's Matrix ID into the canonical profile. Existing financial commands remain available in Payments; current verification status and retained attempts appear together in Compliance. Remote-only legacy records remain inspectable until a local identity is linked; no account is created as a side effect of viewing it.

## Shared components

- `Admin::ComponentsHelper`: labelled input/select fields, hints, errors, checkbox/switch controls, and a shared semantic data-table renderer.
- `admin-controls`: progressively enhances Rails forms, including drawer content loaded later.
- `admin-filters`: one-row search/filter/sort toolbar, apply/reset disclosure, selected-filter chips and individual removal. URLs retain state for sharing and browser navigation. Closing a panel discards unsubmitted filter edits.
- `admin-select`: searchable options, Arrow/Home/End/Enter/Escape/Tab support, explicit selection and active-option state, disabled and invalid state, viewport positioning, and native select fallback. Values are never inferred from display labels. Staff responses and Turbo page snapshots are not cached; browser back/forward restores fresh, authorised server state.
- Native inputs preserve their form behaviour while sharing one set of dimensions, focus rings, colours, error treatment and disabled states. Destructive acknowledgements remain checkboxes; feature settings use switches.
- Shared pagination preserves search/filter/sort state. Category browsing no longer truncates at 500. App review queues and installation lists are paginated.
- The existing drawer/confirmation components continue to provide focus management, full-page escape, attributed commands, reasons and idempotency keys.

## Commerce audit

| Surface | Review and changes |
| --- | --- |
| Orders | Existing state-machine, fulfilment, payment and refund actions preserved; compact composed filtering; server-side sorting; buyer context, amounts and references remain distinct |
| Sourcing | Existing purchasing and fulfilment actions preserved; same control and table system |
| Stores | Branding, store mode, featuring and promotion controls retained; consistent naming, switches and searchable selectors |
| Products | Catalogue, price/SKU, category, media and featuring operations retained; consistent Products naming and controls |
| Merchants | KYB/verification and operational status controls retained; one merchant record linked to stores/orders |
| Categories | Real pagination, preserved filters, a category detail/editor drawer, parent cycle validation; prune remains a guarded explicit action |
| Imports | Monitor, product and storefront views retain review/sync workflows and pagination; controls now share the same components |
| Disputes | Existing protected-payment resolution, allocation validation and unknown-outcome handling retained |
| Payouts | Ledger inspection retained; no unsupported arbitrary ledger editing added |
| Product reviews | Existing approve/reject controls remain permission checked |
| Warehouses/shipping profiles | Existing records remain discoverable and inspectable; no invented fulfilment capabilities |

## Risk, compliance and monitoring

Monitoring loads independent, permission-gated queues for identity exceptions, flagged risk assessments, open disputes, content reports and failed webhook deliveries. A failed connection is shown as unavailable rather than a zero count. Queue cards link to the complete paginated lists.

Flagged risk assessments use retained PEP, sanctions, adverse-media and high-risk classifications. Exchange-rate notifications stay under Money; they are not fraud alerts. This release surfaces the platform's existing risk signals; it does not introduce a new fraud-scoring model or represent unassessed users as alerts.

Identity evidence remains encrypted, authenticated, non-cached and audited. Original automatic/provider results remain separate from manual decisions. Completed screening cases cannot be decided again, including by direct command calls.

## Mini-app lifecycle

The shared form supports a hosted launch URL and optional uploaded distribution package. It includes app identity, semantic version, developer, classification, client type, redirects, permissions, icon/webhook URLs and validation feedback. Editing preserves the app ID. New apps default to Community rather than Official.

Packages are capped at 25 MB, stored privately using the existing S3 credentials, SHA-256 hashed and signed using the persistent TMCP RSA key. They are opaque distribution artifacts: uploading does not extract or execute them on the admin origin. Existing packages are retained when replaced; replacing an uploaded package requires a new version. Embedded official releases need a package for the new version. Hosted updates without a new package retire the old package rather than advertising a mismatched artifact.

Saving returns configuration to review. Review decisions require reasons and recheck state under lock. Approval updates the OAuth client configuration; activation is a separate explicit action. Archive requires an attributed reason. Appeals use explicit boolean decisions and checked state, not string truthiness. Package hashes and download signatures in the client API now refer to actual stored artifacts; placeholder download metadata was removed. Only active, matching versions are publicly distributable. Bootstrap provides published metadata; tokens remain governed by the OAuth + PKCE consent flow and are not minted with blanket wallet privileges.

Storage uses a private-object service rather than the public social-media upload service. Production uses the existing `AWS_*` configuration and `TMCP_PRIVATE_KEY`; no new required environment variable or schema migration is introduced. The bucket policy must permit private objects. Signing is rejected when a persistent private key is unavailable.

Changing an active app's configuration returns it to review and temporarily removes that app from active distribution. A separately staged, zero-downtime release model is not currently present in the platform and is not simulated by this UI.

## Validation

Targeted Rails request/controller/service tests cover the admin routes, permission boundaries, canonical redirects, category pagination and cycles, stateful commands, hosted app creation, package signatures, review-before-activation, and public distribution boundaries. Browser checks cover navigation, page finder, drawers, custom select search/keyboard selection, filters, chip removal, sorting, desktop/mobile overflow and JavaScript errors. Test data is synthetic; no real KYC decisions, transfers, payouts or production app activations are performed.
