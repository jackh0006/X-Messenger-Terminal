// SPDX-License-Identifier: MIT
// Boot probe (plain ES5): on browsers too old to parse the app, show an
// honest update notice instead of a white screen.
(function () {
  var ok = false;
  try { ok = !!(window.Promise && window.fetch && window.WebAssembly && window.BigInt && window.crypto && window.crypto.subtle && window.localStorage); } catch (e) { ok = false; }
  if (!ok) { document.write('<div style="font-family:sans-serif;max-width:420px;margin:40px auto;padding:24px;text-align:center"><h2>X Messenger needs a newer browser</h2><p>Please update Android System WebView (Play Store) or Chrome, then reopen. Your messages stay offline on this device.</p></div>'); }
})();