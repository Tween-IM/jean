// ============================================================================
// Tween Mart — Demo Mini-App
// Exercises every TMCP JSON-RPC method with full trace logging
// ============================================================================

const PRODUCTS = [
  { id: 'p1', name: 'Wireless Earbuds', emoji: '🎧', price: 49.99, desc: 'Noise cancelling, 30h battery' },
  { id: 'p2', name: 'Smart Watch', emoji: '⌚', price: 199.99, desc: 'Health tracking, GPS' },
  { id: 'p3', name: 'Portable Charger', emoji: '🔋', price: 29.99, desc: '20000mAh, fast charge' },
  { id: 'p4', name: 'Mechanical Keyboard', emoji: '⌨️', price: 129.99, desc: 'RGB, hot-swappable' },
  { id: 'p5', name: 'Webcam 4K', emoji: '📷', price: 89.99, desc: 'Auto-focus, HDR' },
  { id: 'p6', name: 'Desk Lamp', emoji: '💡', price: 34.99, desc: 'Smart, dimmable' },
];

// State
let cart = [];
let userInfo = null;
let currentScopes = [];
let requestId = 1;
const pendingRequests = new Map();

// ============================================================================
// TMCP Bridge
// ============================================================================

function initBridge() {
  logTrace('system', 'Initializing TMCP bridge...');

  // Listen for messages from host
  window.addEventListener('message', (event) => {
    handleHostMessage(event.data);
  });

  // Also check if bridge is already injected
  if (window.tmcpBridge) {
    logTrace('system', 'tmcpBridge already available');
  }

  // Request user info on load
  setTimeout(() => {
    callMethod('tween.auth.getUserInfo', {});
    callMethod('tween.auth.getScopes', {});
    refreshBalance();
    loadCartFromStorage();
  }, 500);
}

function sendToHost(payload) {
  const json = JSON.stringify(payload);
  logTrace('request', payload.method, payload);

  if (window.tmcpBridge && window.tmcpBridge.postMessage) {
    window.tmcpBridge.postMessage(json);
  } else {
    // Fallback: postMessage to parent
    window.parent.postMessage(payload, '*');
    logTrace('system', 'Fallback: used window.parent.postMessage');
  }
}

function callMethod(method, params = {}) {
  const id = requestId++;
  const payload = { jsonrpc: '2.0', id, method, params };
  pendingRequests.set(id, { method, time: Date.now() });
  sendToHost(payload);
  return id;
}

function handleHostMessage(data) {
  // Data might be a string or object
  let msg = data;
  if (typeof data === 'string') {
    try { msg = JSON.parse(data); } catch (e) {
      logTrace('error', 'Parse error', { raw: data });
      return;
    }
  }

  if (msg.jsonrpc !== '2.0') return;

  if (msg.id !== undefined) {
    // Response
    const pending = pendingRequests.get(msg.id);
    if (pending) pendingRequests.delete(msg.id);

    if (msg.error) {
      logTrace('error', pending?.method || 'unknown', msg.error);
      handleErrorResponse(pending?.method, msg.error);
    } else {
      logTrace('response', pending?.method || 'unknown', msg.result);
      handleSuccessResponse(pending?.method, msg.result);
    }
  } else if (msg.method) {
    // Host-initiated notification
    logTrace('notification', msg.method, msg.params);
    handleNotification(msg.method, msg.params);
  }
}

function handleSuccessResponse(method, result) {
  switch (method) {
    case 'tween.auth.getUserInfo':
      userInfo = result;
      document.getElementById('userName').textContent = result.display_name || result.user_id || 'Guest';
      document.getElementById('profileName').textContent = result.display_name || result.user_id || 'Guest';
      document.getElementById('profileId').textContent = result.user_id || '--';
      document.getElementById('profileAvatar').textContent = (result.display_name || result.user_id || '?')[0].toUpperCase();
      showToast('👋 Welcome, ' + (result.display_name || result.user_id));
      break;

    case 'tween.auth.getScopes':
      currentScopes = result.scopes || [];
      break;

    case 'tween.auth.requestScopes':
      currentScopes = result.scopes || currentScopes;
      showToast('🔐 Scopes updated: ' + (result.scopes || []).join(', '));
      break;

    case 'tween.wallet.getBalance':
      const balance = result.balance !== undefined ? `$${result.balance.toFixed(2)}` : '--';
      document.getElementById('balanceValue').textContent = balance;
      document.getElementById('walletAmount').textContent = balance;
      break;

    case 'tween.wallet.pay':
      showToast('✅ Payment successful!');
      refreshBalance();
      cart = [];
      updateCartUI();
      saveCartToStorage();
      break;

    case 'tween.wallet.sendMoney':
      showToast('💸 Money sent!');
      refreshBalance();
      break;

    case 'tween.wallet.sendGift':
      showToast('🎁 Gift created: ' + (result.gift_id || 'sent'));
      break;

    case 'tween.wallet.openGift':
      showToast('🎉 Gift opened! You got $' + (result.amount || '??'));
      refreshBalance();
      break;

    case 'tween.storage.get':
      document.getElementById('storageResult').textContent = JSON.stringify(result, null, 2);
      break;

    case 'tween.storage.set':
      showToast('💾 Saved to storage');
      document.getElementById('storageResult').textContent = 'Saved successfully';
      break;

    case 'tween.storage.delete':
      showToast('🗑️ Deleted from storage');
      document.getElementById('storageResult').textContent = 'Deleted';
      break;

    case 'tween.messaging.sendCard':
      showToast('💬 Card sent!');
      break;

    case 'tween.app.minimize':
    case 'tween.app.close':
      // Host handles UI, we just acknowledge
      break;

    default:
      showToast('✅ ' + method + ' succeeded');
  }
}

function handleErrorResponse(method, error) {
  const msg = error.message || error.code || 'Unknown error';
  showToast('❌ ' + (method || 'Error') + ': ' + msg, true);
}

function handleNotification(method, params) {
  switch (method) {
    case 'tween.lifecycle.onShow':
      logTrace('system', 'App became visible');
      refreshBalance();
      break;
    case 'tween.lifecycle.onHide':
      logTrace('system', 'App hidden');
      break;
  }
}

// ============================================================================
// UI — Navigation
// ============================================================================

function navigateTo(screen) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));

  document.getElementById('screen' + screen.charAt(0).toUpperCase() + screen.slice(1)).classList.add('active');
  document.querySelector(`.nav-item[data-screen="${screen}"]`).classList.add('active');

  if (screen === 'cart') updateCartUI();
}

// ============================================================================
// UI — Products
// ============================================================================

function renderProducts() {
  const featured = document.getElementById('featuredGrid');
  const list = document.getElementById('productList');

  // First 4 as featured grid
  featured.innerHTML = PRODUCTS.slice(0, 4).map(p => `
    <div class="product-card" onclick="addToCart('${p.id}')">
      <div class="product-image">${p.emoji}</div>
      <div class="product-info">
        <div class="product-name">${p.name}</div>
        <div class="product-price">$${p.price.toFixed(2)}</div>
      </div>
    </div>
  `).join('');

  // All as list
  list.innerHTML = PRODUCTS.map(p => `
    <div class="product-row" onclick="viewProduct('${p.id}')">
      <div class="product-image">${p.emoji}</div>
      <div class="product-info">
        <div class="product-name">${p.name}</div>
        <div class="product-desc">${p.desc}</div>
        <div class="product-price">$${p.price.toFixed(2)}</div>
      </div>
      <button class="add-to-cart" onclick="event.stopPropagation(); addToCart('${p.id}')">+</button>
    </div>
  `).join('');
}

function viewProduct(id) {
  const p = PRODUCTS.find(x => x.id === id);
  showModal(p.name, p.desc + '\n\nPrice: $' + p.price.toFixed(2), [
    { label: 'Add to Cart', action: () => addToCart(id), primary: true },
    { label: 'Share', action: () => shareProduct(id) },
    { label: 'Close', action: () => {} },
  ]);
}

// ============================================================================
// Cart
// ============================================================================

function addToCart(id) {
  const existing = cart.find(c => c.id === id);
  if (existing) {
    existing.qty++;
  } else {
    const p = PRODUCTS.find(x => x.id === id);
    cart.push({ ...p, qty: 1 });
  }
  updateCartUI();
  saveCartToStorage();
  showToast('🛒 Added to cart');
}

function removeFromCart(id) {
  cart = cart.filter(c => c.id !== id);
  updateCartUI();
  saveCartToStorage();
}

function updateQty(id, delta) {
  const item = cart.find(c => c.id === id);
  if (!item) return;
  item.qty += delta;
  if (item.qty <= 0) removeFromCart(id);
  else updateCartUI();
  saveCartToStorage();
}

function updateCartUI() {
  const container = document.getElementById('cartItems');
  const footer = document.getElementById('cartFooter');
  const badge = document.getElementById('cartBadge');
  const totalQty = cart.reduce((s, c) => s + c.qty, 0);

  badge.textContent = totalQty;
  badge.style.display = totalQty > 0 ? 'flex' : 'none';

  if (cart.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon">🛒</div>
        <p>Your cart is empty</p>
        <button class="btn-primary" onclick="navigateTo('home')">Browse Products</button>
      </div>`;
    footer.style.display = 'none';
    return;
  }

  const total = cart.reduce((s, c) => s + c.price * c.qty, 0);
  container.innerHTML = cart.map(c => `
    <div class="cart-item">
      <div class="product-image">${c.emoji}</div>
      <div class="cart-item-info">
        <div class="cart-item-name">${c.name}</div>
        <div class="cart-item-price">$${(c.price * c.qty).toFixed(2)}</div>
      </div>
      <div class="cart-item-qty">
        <button class="qty-btn" onclick="updateQty('${c.id}', -1)">−</button>
        <span>${c.qty}</span>
        <button class="qty-btn" onclick="updateQty('${c.id}', 1)">+</button>
      </div>
    </div>
  `).join('');

  document.getElementById('cartTotal').textContent = '$' + total.toFixed(2);
  footer.style.display = 'block';
}

function checkout() {
  const total = cart.reduce((s, c) => s + c.price * c.qty, 0);
  if (total <= 0) return;

  showModal('Confirm Payment', `Pay $${total.toFixed(2)} for ${cart.length} item(s)?`, [
    { label: 'Pay Now', action: () => {
      callMethod('tween.wallet.pay', {
        amount: total.toFixed(2),
        currency: 'USD',
        description: 'Tween Mart checkout: ' + cart.map(c => c.name).join(', '),
      });
    }, primary: true },
    { label: 'Cancel', action: () => {} },
  ]);
}

function saveCartToStorage() {
  callMethod('tween.storage.set', {
    key: 'cart',
    value: JSON.stringify(cart),
  });
}

function loadCartFromStorage() {
  callMethod('tween.storage.get', { key: 'cart' });
}

// ============================================================================
// Wallet Actions
// ============================================================================

function refreshBalance() {
  callMethod('tween.wallet.getBalance', {});
}

function sendMoney() {
  showModal('Send Money', '', [
    { label: 'Send', action: (inputs) => {
      callMethod('tween.wallet.sendMoney', {
        recipient: inputs[0].value,
        amount: parseFloat(inputs[1].value),
        currency: 'USD',
        note: inputs[2].value,
      });
    }, primary: true },
    { label: 'Cancel', action: () => {} },
  ], [
    { placeholder: 'Recipient (@user:server)', type: 'text' },
    { placeholder: 'Amount', type: 'number' },
    { placeholder: 'Note (optional)', type: 'text' },
  ]);
}

function sendGift() {
  showModal('Send Gift', '', [
    { label: 'Send Gift', action: (inputs) => {
      callMethod('tween.wallet.sendGift', {
        amount: parseFloat(inputs[0].value),
        currency: 'USD',
        recipients: inputs[1].value.split(',').map(s => s.trim()).filter(Boolean),
        message: inputs[2].value,
      });
    }, primary: true },
    { label: 'Cancel', action: () => {} },
  ], [
    { placeholder: 'Amount per person', type: 'number' },
    { placeholder: 'Recipients (comma separated)', type: 'text' },
    { placeholder: 'Message', type: 'text' },
  ]);
}

function openGift() {
  showModal('Open Gift', '', [
    { label: 'Open', action: (inputs) => {
      callMethod('tween.wallet.openGift', { gift_id: inputs[0].value });
    }, primary: true },
    { label: 'Cancel', action: () => {} },
  ], [
    { placeholder: 'Gift ID', type: 'text' },
  ]);
}

function requestScopeDemo() {
  showModal('Request Scope', 'Request wallet:pay permission?', [
    { label: 'Request', action: () => {
      callMethod('tween.auth.requestScopes', { scopes: ['wallet:pay', 'wallet:history'] });
    }, primary: true },
    { label: 'Cancel', action: () => {} },
  ]);
}

function getScopes() {
  callMethod('tween.auth.getScopes', {});
  showToast('📋 Scopes: ' + currentScopes.join(', '));
}

// ============================================================================
// Storage
// ============================================================================

function storageGet() {
  const key = document.getElementById('storageKey').value;
  if (!key) return showToast('Enter a key', true);
  callMethod('tween.storage.get', { key });
}

function storageSet() {
  const key = document.getElementById('storageKey').value;
  const value = document.getElementById('storageValue').value;
  if (!key) return showToast('Enter a key', true);
  callMethod('tween.storage.set', { key, value });
}

function storageDelete() {
  const key = document.getElementById('storageKey').value;
  if (!key) return showToast('Enter a key', true);
  callMethod('tween.storage.delete', { key });
}

// ============================================================================
// Lifecycle & Share
// ============================================================================

function minimizeApp() {
  callMethod('tween.app.minimize', {});
}

function closeApp() {
  showModal('Close App', 'Are you sure you want to close?', [
    { label: 'Close', action: () => callMethod('tween.app.close', {}), primary: true },
    { label: 'Stay', action: () => {} },
  ]);
}

function shareProduct(productId) {
  const p = productId ? PRODUCTS.find(x => x.id === productId) : PRODUCTS[0];
  callMethod('tween.messaging.sendCard', {
    type: 'product',
    title: p.name,
    description: p.desc,
    image_url: '',
    action_url: '',
    metadata: { product_id: p.id, price: p.price },
  });
}

// ============================================================================
// Trace Console
// ============================================================================

const tracePanel = document.getElementById('tracePanel');
const traceLogs = document.getElementById('traceLogs');
let traceOpen = false;

document.getElementById('traceToggle').addEventListener('click', () => {
  traceOpen = !traceOpen;
  tracePanel.classList.toggle('open', traceOpen);
  document.getElementById('traceToggle').classList.toggle('active', traceOpen);
});

function logTrace(type, method, payload) {
  const time = new Date().toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
  const div = document.createElement('div');
  div.className = `trace-log ${type}`;

  const label = type === 'request' ? '➡️ REQ' : type === 'response' ? '⬅️ RES' : type === 'error' ? '❌ ERR' : type === 'notification' ? '🔔 NOTIF' : 'ℹ️ SYS';

  div.innerHTML = `
    <div class="trace-time">${time} ${label} <span class="trace-method">${method}</span></div>
    ${payload ? `<div class="trace-payload">${escapeHtml(JSON.stringify(payload, null, 2))}</div>` : ''}
  `;

  traceLogs.appendChild(div);
  traceLogs.scrollTop = traceLogs.scrollHeight;
}

function clearTrace() {
  traceLogs.innerHTML = '';
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// ============================================================================
// Toast
// ============================================================================

let toastTimer;
function showToast(message, isError) {
  const toast = document.getElementById('toast');
  document.getElementById('toastIcon').textContent = isError ? '❌' : '✅';
  document.getElementById('toastMessage').textContent = message;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 3000);
}

// ============================================================================
// Modal
// ============================================================================

function showModal(title, body, actions, inputs) {
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay';

  let inputHtml = '';
  if (inputs) {
    inputHtml = inputs.map((inp, i) =>
      `<input class="modal-input" id="modalInput${i}" type="${inp.type}" placeholder="${inp.placeholder}">`
    ).join('');
  }

  overlay.innerHTML = `
    <div class="modal-card">
      <div class="modal-title">${title}</div>
      ${body ? `<div class="modal-body">${body.replace(/\n/g, '<br>')}</div>` : ''}
      ${inputHtml}
      <div class="modal-actions">
        ${actions.map(a => `
          <button class="${a.primary ? 'btn-primary' : 'btn-secondary'}" data-action>${a.label}</button>
        `).join('')}
      </div>
    </div>
  `;

  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) document.body.removeChild(overlay);
  });

  const buttons = overlay.querySelectorAll('[data-action]');
  buttons.forEach((btn, i) => {
    btn.addEventListener('click', () => {
      const inputEls = inputs ? inputs.map((_, i) => overlay.querySelector(`#modalInput${i}`)) : [];
      actions[i].action(inputEls);
      document.body.removeChild(overlay);
    });
  });

  document.body.appendChild(overlay);
}

// ============================================================================
// Init
// ============================================================================

renderProducts();
initBridge();

// Expose for debugging
window.tmcp = { callMethod, cart, userInfo, currentScopes };
