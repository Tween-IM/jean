# Commerce catalog import (external marketplaces)

Internal operational API for mirroring externally-sourced catalogs (Jumia,
Konga, …) into the Tween storefront. Used by the `tween-scraper` service.

This is **not** part of the miniapp-facing TMCP protocol surface — it is an
operator/merchant-scoped endpoint, so it does not extend `PROTO.md`.

## Auth

`Authorization: Bearer <TEP token>` where the token subject owns the target
merchant (`merchant.owner_user_id == token.sub`) and carries the
`commerce:merchant` scope (first-party miniapps with wildcard permission are
exempt, as everywhere else in commerce).

## `POST /api/v1/commerce/imports`

Batch upsert of products, SKUs and reviews. Idempotent: the natural source keys
decide create vs update, so a scheduled sync can replay the same batch.

```json
{
  "merchant_id": "mch_xxx",
  "storefront_id": "stf_xxx",
  "category_id": "cat_xxx",
  "storefront": {
    "display_name": "Bella's Coutures",
    "slug": "bella-s-coutures-jumia",
    "store_type": "marketplace",
    "about": "Handmade Ankara pieces, made in Lagos.",
    "banner_url": "https://cdn/banner.jpg",
    "logo_url": "https://cdn/logo.jpg",
    "accent_color": "#7C3AED",
    "source": {
      "kind": "seller",
      "platform": "jumia",
      "source_id": "bella-s-coutures",
      "source_url": "https://www.jumia.com.ng/bella-s-coutures/",
      "scraped_at": "2026-09-15T10:06:29Z"
    },
    "contact": {
      "phone": "+2348012345678",
      "email": "hello@bellas.test",
      "website": "https://bellas.test",
      "address": "12 Balogun St, Lagos",
      "social_links": { "instagram": "bellascoutures" }
    }
  },
  "products": [
    {
      "storefront_id": "stf_optional_per_entry_override",
      "source": {
        "platform": "jumia",
        "source_id": "AP044MP5XRWSCNAFAMZ",
        "source_url": "https://www.jumia.com.ng/…",
        "brand": "Apple",
        "category_path": ["Phones & Tablets", "Mobile Phones"],
        "seller_name": "…", "seller_id": "…",
        "rating_average": 4.5, "rating_count": 128,
        "price_cents": 98000000, "original_price_cents": 110000000,
        "currency": "NGN", "is_available": true,
        "badges": ["Express"], "scraped_at": "2026-09-15T10:00:00Z"
      },
      "product": {
        "title": "iPhone 14 Pro Max …",
        "description": "…",
        "media_urls": ["https://cdn/…-large.jpg"],
        "tags": ["Apple", "source:jumia"],
        "dimensions": { "brand": "Apple", "specifications": { "Storage": "256GB" } },
        "condition": "new",
        "status": "active",
        "seo_title": "…", "seo_description": "…",
        "weight_grams": 240
      },
      "skus": [
        {
          "source_sku_id": "AP044MP5XRWSCNAFAMZ-BLK",
          "title": "Black",
          "price_cents": 98000000,
          "currency": "NGN",
          "inventory_status": "in_stock",
          "quantity_available": null,
          "properties": { "colour": "black" }
        }
      ],
      "reviews": [
        {
          "source_review_id": "R-1",
          "reviewer_display_name": "Chidinma O.",
          "reviewer_handle": "chidinma-o",
          "is_anonymous": false,
          "rating": 5,
          "title": "Excellent",
          "body": "Works perfectly.",
          "helpful_count": 3,
          "verified_purchase": true,
          "review_date": "2026-08-01T10:00:00Z"
        }
      ]
    }
  ]
}
```

Response:

```json
{
  "results": [
    {
      "source_platform": "jumia",
      "source_id": "AP044MP5XRWSCNAFAMZ",
      "product_id": "prod_xxx",
      "storefront_id": "stf_xxx",
      "action": "created",
      "skus": 1,
      "reviews": 1
    }
  ],
  "meta": { "total": 1, "created": 1, "updated": 0, "failed": 0 }
}
```

`action` is `created`, `updated` or `failed`. A `failed` entry includes an
`error` message and leaves no partial writes (each product is one transaction).
At most `100` products per request.

### Behaviour

| Concern | Behaviour |
|---|---|
| Product upsert key | `commerce_products(source_platform, source_id)` (unique, partial) |
| Review upsert key | `commerce_reviews(source_platform, source_review_id)` (unique, partial) |
| SKU identity | `commerce_skus.properties->>'source_sku_id'` |
| Missing SKUs | Kept, but marked `out_of_stock` (carts/orders reference them) |
| Store resolution | `storefront_id` → else by `storefront.slug` → else merchant's store |
| Store branding | `display_name`, `about`, `banner_url`, `logo_url`, `accent_color`, … applied on import |
| Store provenance | `source` → `source_platform`, `source_kind`, `source_id`, `source_url`, `source_payload`, `source_synced_at` |
| Store contact | `contact` → `contact_phone`/`_email`/`_website`/`_address` + `social_links` (owner-only, see below) |
| Imported reviews | `status = approved`, `imported = true`, purchase check bypassed |
| `buyer_user_id` | `import:<platform>:<source_review_id>` — no Tween user is impersonated |
| Reviewer identity | `reviewer_display_name`/`reviewer_handle`, or "Anonymous Buyer"/"Anonymous" |
| Rating recache | Product and storefront rating/product counts are recached |

### Storefronts

`storefront.slug` is the identity of an imported store, so importers can shape
the catalog however they want without the API changing: one store per
marketplace, one per source seller (set `store_type: "marketplace"` for
peer-to-peer sellers), or one per brand shared across marketplaces. The store is
found-or-created within the target merchant and re-branded on import, so
branding stays correct if it changes upstream. If `slug` is omitted the
merchant's default store is reused.

Stores are real, not just containers: the scraper mirrors the source seller or
brand page into the store, so `about`/`logo_url`/`banner_url` render like any
hand-made store. Anything the operator sets explicitly (branding configured on
the scraper) wins over the mirrored values.

#### Source stores and contact details

`storefront.source` records where the store came from. `source_kind` is
`seller` or `brand` (any other value is ignored rather than rejected), and the
whole block is stored verbatim in `source_payload`.

`storefront.contact` carries seller contact details **for the platform team to
reach the seller out of band**. They are stored on the store but are *not*
public storefront data:

- `storefront_json` exposes `contact` and `source_payload` only when the
  requester is the merchant owner (`merchant_owner?`), i.e. `detail: :full`.
  Everyone else gets branding and provenance, never contact details.
- Fields are optional. Marketplaces rarely publish any (Jumia's seller pages
  sit behind Cloudflare, Konga renders seller info client-side), so a missing
  or entirely empty `contact` block is normal and must not be treated as an
  error.

## `POST /api/v1/commerce/imports/lookup`

Reconcile source identities back to storefront ids (cheap, no side effects).

```json
{
  "merchant_id": "mch_xxx",
  "items": [{ "source_platform": "jumia", "source_id": "AP044MP5XRWSCNAFAMZ" }]
}
```

Returns `{ "products": [{ "source_platform", "source_id", "product_id", "status", "source_synced_at" }] }`.

## Provenance

`commerce_products` gained `source_platform`, `source_id`, `source_url`,
`source_payload` (jsonb) and `source_synced_at`; `commerce_reviews` gained
`source_platform`, `source_review_id`, `reviewer_display_name`,
`reviewer_handle`, `is_anonymous`, `imported`, `review_date` and
`source_payload`. Migration:
`db/migrate/20260915120000_add_commerce_import_provenance.rb`.

`commerce_storefronts` gained `source_platform`, `source_kind`, `source_id`,
`source_url`, `source_payload` (jsonb), `source_synced_at`, `contact_phone`,
`contact_email`, `contact_website`, `contact_address` and `social_links` (jsonb).
Migration: `db/migrate/20260915140000_add_storefront_import_provenance.rb`.

Review payloads expose `imported`, `is_anonymous` and `source_platform` so
clients can label syndicated reviews. Storefront payloads expose the shopper-
facing fields (`about`, `logo_url`, `banner_url`, `description`) plus
`imported`, `source_platform`, `source_kind`, `source_url` and
`source_synced_at` publicly; `contact`, `social_links`, `source_payload`,
`policies` and `seo_*` are owner-only.

## Admin monitoring and curation

Operators watch and correct imports at `/admin/imports` in the TMCP admin,
gated by platform permissions:

| Permission       | Roles                                           |
| ---------------- | ----------------------------------------------- |
| `view_imports`   | support, operations analyst, operations manager |
| `manage_imports` | operations manager                              |

- `/admin/imports` — overview: how many stores, listings and reviews arrived
  per platform, the last sync, which stores have no reachable seller
  ("Outreach needed") and which listings are older than 7 days ("Needs a
  re-sync").
- `/admin/imports/storefronts` — imported seller/brand stores, filterable by
  platform, kind (`seller`/`brand`) or free text.
- `/admin/imports/storefronts/:id` — set the shopper-facing branding
  (`display_name`, `about`, `description`, `store_type`, `status`,
  `accent_color`, `featured`) and record the contact details the platform team
  collects out of band. Contact stays owner-only — it is never public. The raw
  `source_payload` is shown for provenance.
- `/admin/imports/products` — imported listings, filterable by platform,
  status or free text.
- `/admin/imports/products/:id` — move a listing between `active`, `draft` and
  `archived`, toggle `featured`, inspect the mirrored SKUs and reviews, and
  read the source payload.
- `PATCH /admin/imports/reviews/:id` — moderate an imported review
  (`approved`/`pending`/`rejected`). Buyer identity stays as captured at the
  source: the canonical name, or "Anonymous Buyer".

Every mutation writes an `[ADMIN_AUDIT]` line through `log_admin_action`.
Scheduling stays with the scraper: the admin screens read `source_synced_at` to
surface staleness but never trigger runs themselves.
