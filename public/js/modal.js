// modal.js :: dialogs over the page (docs/APP.md "Modals"). A link with data-modal opens
// its address in one: the request says X-DK-Modal: 1 and the server answers with the
// page's title and content alone (lib/view.lua, layout/modal.html), shown in a <dialog>
// (showModal: the page behind is inert, Escape closes, focus stays inside). Forms in it
// submit into it; a redirect (X-DK-Go) closes it and the page goes there; a link in it
// closes it and goes on like any link (the live client takes it). An element with
// data-modal-close closes it, a submit button too (no request; without JavaScript it
// submits as it says). After a POST in the dialog the page behind brings itself up to
// date (DK.refresh, client.js; without it, a reload when the dialog closes). Without this
// script (no JavaScript, no <dialog>) a data-modal link is an ordinary link to the page.
(function () {
	"use strict";
	if (typeof document === "undefined" || !window.fetch || !window.HTMLDialogElement || !window.AbortController ||
		!window.URL || !window.URLSearchParams || !window.FormData || !window.Promise) return;

	var SLOW = 250;   // ms before the dialog opens with "Loading" while its page is on the way
	var dlg = null, box = null;
	var opener = null;       // the element focused when it opened (focused again when it closes)
	var req = null;          // { ctl, post, inside (asked from the open dialog) } in flight
	var dirty = false;       // a POST happened: the page behind is out of date
	var lastButton = null;   // the submit button last clicked (browsers without ev.submitter)
	var downOnBackdrop = false, slowTimer = 0;

	function build() {
		dlg = document.createElement("dialog");
		dlg.className = "dk-modal";
		dlg.setAttribute("data-client", "");   // the live client's morph leaves it alone
		dlg.setAttribute("aria-labelledby", "dk-modal-title");
		box = document.createElement("div");
		box.className = "dk-modal-box";
		var x = document.createElement("button");
		x.type = "button";
		x.className = "dk-modal-x";
		x.setAttribute("data-modal-close", "");
		x.setAttribute("aria-label", "Close");
		x.textContent = "\u00d7";
		dlg.appendChild(box);
		dlg.appendChild(x);
		dlg.addEventListener("close", closed);
		// a click on the backdrop (the dialog around its box) closes it; a drag that only
		// ends there (selecting text) doesn't
		dlg.addEventListener("pointerdown", function (ev) { downOnBackdrop = ev.target === dlg; });
		dlg.addEventListener("click", function (ev) { if (ev.target === dlg && downOnBackdrop) close(); });
		document.body.appendChild(dlg);
	}

	function isOpen() { return !!(dlg && dlg.open); }
	function inside(el) { return isOpen() && dlg.contains(el); }

	function show(html) {
		if (!dlg || !dlg.isConnected) build();
		box.innerHTML = html;
		if (window.dkTip) window.dkTip.hide();
		if (!dlg.open) {
			if (!opener) opener = document.activeElement;
			dlg.showModal();
		}
		var f = box.querySelector("[autofocus]") ||
			box.querySelector("input:not([type=hidden]):not([disabled]), select, textarea, button:not([disabled])");
		if (!f) {
			f = box.querySelector(".dk-modal-title") || box;
			f.setAttribute("tabindex", "-1");
		}
		f.focus();
	}

	function close() { if (isOpen()) dlg.close(); }

	// (the close event comes a moment after the dialog closed: it may have opened again since,
	// and a request to open it may be on its way)
	function closed() {
		if (dlg.open) return;
		if (req && !req.post && req.inside) {   // (a POST runs on: it changes the game)
			req.ctl.abort();
			req = null;
			clearTimeout(slowTimer);
		}
		box.textContent = "";
		if (window.dkTip) window.dkTip.hide();
		if (dirty) {
			dirty = false;
			if (window.DK) window.DK.refresh(); else location.reload();
		}
		var o = opener;
		opener = null;
		if (o && o.isConnected && o.focus) o.focus({ preventScroll: true });
	}

	// The dialog closes and the page goes to url (nothing to refresh: the new page is current).
	function leave(url) {
		dirty = false;
		opener = null;
		close();
		if (window.DK) window.DK.visit(url); else location.assign(url);
	}

	function request(url, post) {
		if (req) {
			if (req.post) return;   // never cancel what changes the game; a second submit is a double click
			req.ctl.abort();
		}
		var ctl = new AbortController(), mine = req = { ctl: ctl, post: !!post, inside: isOpen() };
		var headers = { "X-DK-Modal": "1" };
		if (window.DK && window.DK.tab) headers["X-DK-Tab"] = window.DK.tab;   // (live.js: this tab knows)
		clearTimeout(slowTimer);
		if (isOpen()) dlg.setAttribute("aria-busy", "true");
		else slowTimer = setTimeout(function () {
			if (req === mine) show('<p class="dk-modal-loading" role="status">Loading\u2026</p>');
		}, SLOW);
		fetch(url, {
			method: post ? "POST" : "GET", body: post || undefined, headers: headers, credentials: "same-origin",
			signal: ctl.signal,
		}).then(function (res) {
			if (post) dirty = true;
			var go = res.headers.get("X-DK-Go");
			if (go !== null) { req = null; leave(go); return; }
			if (res.headers.get("X-DK-Modal") !== "1") {
				if (!post) throw new Error("not a modal's answer");
				// a POST answered with a whole page (an error): show it as the browser would
				return res.text().then(function (html) { document.open(); document.write(html); document.close(); });
			}
			return res.text().then(function (html) {
				if (req !== mine) return;
				show(html);
				if (post && window.DK) { dirty = false; window.DK.refresh(); }
			});
		}).catch(function (err) {
			if (ctl.signal.aborted && req !== mine) return;   // superseded or closed
			if (window.console) console.warn("modal.js:", err);
			// a GET: the page itself; a POST lost on the way may or may not have happened:
			// the page as it is now
			if (post) location.reload(); else location.assign(url);
		}).then(function () {
			if (req !== mine) return;
			req = null;
			clearTimeout(slowTimer);
			if (dlg) dlg.removeAttribute("aria-busy");
		});
	}

	function sameOrigin(href) {
		try { return new URL(href, location.href).origin === location.origin; } catch (e) { return false; }
	}

	// on document: before the live client's listeners (on window), which skip what is
	// handled here (defaultPrevented)
	document.addEventListener("click", function (ev) {
		var t = ev.target && (ev.target.nodeType === 1 ? ev.target : ev.target.parentElement);
		if (!t || !t.closest) return;
		var b = t.closest("button, input[type=submit], input[type=image]");
		if (b && inside(b)) lastButton = b;
		if (ev.defaultPrevented || ev.button !== 0) return;
		var x = t.closest("[data-modal-close]");
		if (x && inside(x)) { ev.preventDefault(); close(); return; }
		if (ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
		var a = t.closest("a[href]");
		if (!a || (a.target && a.target !== "_self") || a.hasAttribute("download")) return;
		if (a.hasAttribute("data-modal") && sameOrigin(a.href)) {
			ev.preventDefault();
			if (!isOpen()) opener = a;
			request(a.href);
		} else if (inside(a)) {
			// a link out of the dialog: it closes, the link goes on
			dirty = false;
			opener = null;
			close();
		}
	});

	document.addEventListener("submit", function (ev) {
		var form = ev.target;
		if (ev.defaultPrevented || !inside(form)) return;
		var submitter = "submitter" in ev ? ev.submitter : (lastButton && lastButton.form === form ? lastButton : null);
		lastButton = null;
		var method = (form.getAttribute("method") || "get").toLowerCase();
		if (method !== "get" && method !== "post") return;   // (method="dialog": the browser closes it)
		ev.preventDefault();
		var data;
		try { data = new FormData(form, submitter || undefined); } catch (e) {
			data = new FormData(form);
			if (submitter && submitter.name) data.append(submitter.name, submitter.value);
		}
		var params = new URLSearchParams();
		data.forEach(function (v, k) { if (typeof v === "string") params.append(k, v); });
		var u = new URL(form.getAttribute("action") || location.href, location.href);
		if (method === "get") {
			u.search = params.toString();
			request(u.href);
		} else {
			request(u.href, params);
		}
	});

	// for other scripts (and tests)
	window.dkModal = { open: function (url) { request(url); }, close: close, isOpen: isOpen };
})();
