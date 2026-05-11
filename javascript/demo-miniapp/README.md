# Tween Mart — TMCP Demo Mini-App

A complete, real-feeling e-commerce mini-app that exercises every TMCP JSON-RPC method. Use it to validate the entire mini-app platform end-to-end.

## Features Demonstrated

| Screen | TMCP Methods |
|--------|-------------|
| **Home** | `tween.auth.getUserInfo`, `tween.wallet.getBalance` |
| **Cart** | `tween.storage.get`, `tween.storage.set`, `tween.wallet.pay` |
| **Wallet** | `tween.wallet.getBalance`, `tween.wallet.sendMoney`, `tween.wallet.sendGift`, `tween.wallet.openGift`, `tween.auth.requestScopes`, `tween.auth.getScopes` |
| **Profile** | `tween.storage.get/set/delete`, `tween.app.minimize`, `tween.app.close`, `tween.messaging.sendCard` |
| **Global** | `tween.lifecycle.onShow/onHide` (host notifications) |

## Dev Trace Console

Tap the graph icon (top-right) to open a live trace panel showing every JSON-RPC request, response, and error in real time.

## Running Locally

### Option 1: Served by Jean (recommended)

The demo files are copied to `jean/public/demo-miniapp/`. Jean serves them automatically:

```bash
cd ../jean
bin/rails server
```

Then open `http://localhost:3000/demo-miniapp/index.html` in a browser, or register `ma_tweenmart` in the store and launch it from the Flutter app.

### Option 2: Standalone

Open `index.html` directly in a browser. The TMCP bridge methods will gracefully fall back to `window.parent.postMessage` and show trace errors, so you can still test the UI.

## Registering in the Store

```bash
cd ../jean
bin/rails db:seed
```

This creates the `ma_tweenmart` record from `config/mini_apps.yml`. The Flutter store page will then list it under **Shopping**.

## What to Test

1. **Install** — Find Tween Mart in the store and install it
2. **Launch** — Open the app, verify the welcome banner shows your Matrix user ID
3. **Balance** — Check that wallet balance loads on Home and Wallet tabs
4. **Add to Cart** — Tap products, watch cart badge update
5. **Storage** — Cart persists via `tween.storage.set/get`
6. **Payment** — Checkout triggers `tween.wallet.pay` with PIN dialog
7. **Scope Request** — Wallet tab → "Request Payment Scope" triggers consent bottom sheet
8. **P2P** — Wallet tab → Send Money opens a form, triggers `tween.wallet.sendMoney`
9. **Gifts** — Wallet tab → Send Gift / Open Gift
10. **Share** — Profile tab → Share Product triggers `tween.messaging.sendCard`
11. **Minimize** — Profile tab → Minimize App
12. **Close** — Profile tab → Close App
13. **Trace** — Tap the top-right graph icon to inspect all JSON-RPC traffic
