// chatbox.js :: the Babble Box as a floating window (docs/APP.md "Chat"). The Functions
// box's link (<a href="/babble" data-chatbox>) opens and closes it; it holds the chat of
// GET /babble (fetched as a dialog's page: X-DK-Modal, the chat alone), whose forms and
// messages live.js keeps going as on the page. It is the player's: a strip at its top
// (with the close button at the right) drags it, its corner resizes it, and where it is,
// its size and whether it is open are kept (localStorage), so it stays open from page to
// page (the live client's morph leaves it: data-client; a page load opens it again). It
// isn't a <dialog>: the game goes on under it (the arrow keys, the hotbar), and a dialog
// (modal.js) leaves it working and under it. Escape in it closes it. Pages without the
// link (logged out, the admin panel) don't show it. Without JavaScript the link is the
// /babble page.
(function () {
	"use strict";
	if (typeof document === "undefined" || !window.fetch || !window.JSON || !window.Promise) return;

	var KEY = "dk-chatbox", MARGIN = 8;
	var win = null, body = null, loading = null;

	function load() {
		try { return JSON.parse(window.localStorage.getItem(KEY)) || {}; } catch (e) { return {}; }
	}
	function save(patch) {
		var s = load();
		for (var k in patch) s[k] = patch[k];
		try { window.localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) { /* private mode */ }
	}
	function toggle() { return document.querySelector("a[data-chatbox]"); }
	function isOpen() { return !!(win && !win.hidden); }

	// within the window's viewport, at least MARGIN from its edges
	function place(x, y) {
		var w = win.offsetWidth, h = win.offsetHeight;
		x = Math.max(MARGIN, Math.min(x, window.innerWidth - w - MARGIN));
		y = Math.max(MARGIN, Math.min(y, window.innerHeight - h - MARGIN));
		win.style.left = Math.round(x) + "px";
		win.style.top = Math.round(y) + "px";
	}

	function build() {
		var s = load();
		win = document.createElement("section");
		win.className = "dk-chatbox";
		win.hidden = true;
		win.setAttribute("data-client", "");   // the live client's morph leaves it alone
		win.setAttribute("data-chatbox-window", "");
		win.setAttribute("role", "dialog");
		win.setAttribute("aria-label", "Babble Box");
		var grip = document.createElement("div");
		grip.className = "dk-chatbox-grip";
		grip.title = "Drag to move";
		var x = document.createElement("button");
		x.type = "button";
		x.className = "dk-chatbox-x";
		x.setAttribute("aria-label", "Close");
		x.title = "Close";
		x.textContent = "\u00d7";
		x.addEventListener("click", function () { close(true); });
		grip.appendChild(x);
		body = document.createElement("div");
		body.className = "dk-chatbox-body";
		win.appendChild(grip);
		win.appendChild(body);
		if (s.w) win.style.width = s.w + "px";
		if (s.h) win.style.height = s.h + "px";
		document.body.appendChild(win);

		// dragging by the strip
		var drag = null;
		grip.addEventListener("pointerdown", function (ev) {
			if (ev.button !== 0 || ev.target !== grip) return;
			drag = { dx: ev.clientX - win.offsetLeft, dy: ev.clientY - win.offsetTop };
			grip.setPointerCapture(ev.pointerId);
			win.classList.add("dk-chatbox-dragging");
			ev.preventDefault();
		});
		grip.addEventListener("pointermove", function (ev) {
			if (drag) place(ev.clientX - drag.dx, ev.clientY - drag.dy);
		});
		function drop() {
			if (!drag) return;
			drag = null;
			win.classList.remove("dk-chatbox-dragging");
			save({ x: win.offsetLeft, y: win.offsetTop });
		}
		grip.addEventListener("pointerup", drop);
		grip.addEventListener("pointercancel", drop);
		// its size (the CSS resize corner)
		if (window.ResizeObserver) {
			var timer = 0;
			new ResizeObserver(function () {
				clearTimeout(timer);
				timer = setTimeout(function () { if (isOpen()) save({ w: win.offsetWidth, h: win.offsetHeight }); }, 300);
			}).observe(win);
		}
		win.addEventListener("keydown", function (ev) {
			if (ev.key === "Escape" && !ev.defaultPrevented) { ev.preventDefault(); close(true); }
		});
	}

	// The chat from GET /babble (the dialog's answer: the chat alone), without the live
	// client's region names (the page may show its own: /babble).
	function fill() {
		if (loading) return loading;
		var headers = { "X-DK-Modal": "1" };
		if (window.DK && window.DK.tab) headers["X-DK-Tab"] = window.DK.tab;
		loading = fetch("/babble", { headers: headers, credentials: "same-origin" }).then(function (res) {
			if (res.headers.get("X-DK-Modal") !== "1") throw new Error("not the chat");
			return res.text();
		}).then(function (html) {
			var t = document.createElement("template");
			t.innerHTML = html;
			var chat = t.content.querySelector(".chat") || t.content.querySelector(".dk-modal-content");
			if (!chat) throw new Error("no chat");
			Array.prototype.forEach.call(chat.querySelectorAll("[data-r]"), function (e) { e.removeAttribute("data-r"); });
			chat.removeAttribute("data-r");
			body.textContent = "";
			body.appendChild(chat);
		}).catch(function () {
			body.textContent = "The Babble Box could not be loaded.";
		}).then(function () { loading = null; });
		return loading;
	}

	function open(focus) {
		if (!toggle()) return;
		if (!win || !win.isConnected) build();
		var s = load();
		win.hidden = false;
		if (s.x != null) place(s.x, s.y);
		else place(window.innerWidth - win.offsetWidth - 24, window.innerHeight - win.offsetHeight - 24);
		save({ open: true });
		fill().then(function () {
			if (!isOpen()) return;
			var field = win.querySelector("[name=babble]");
			if (focus && field) field.focus();
		});
	}

	function close(byPlayer) {
		if (!win) return;
		var had = win.contains(document.activeElement);
		win.hidden = true;
		body.textContent = "";
		if (byPlayer) {
			save({ open: false });
			var t = toggle();
			if (had && t) t.focus({ preventScroll: true });
		}
	}

	// the link: open or close (before the live client's listener, on window)
	document.addEventListener("click", function (ev) {
		var a = ev.target && ev.target.closest && ev.target.closest("a[data-chatbox]");
		if (!a || ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
		ev.preventDefault();
		if (isOpen()) close(true); else open(true);
	});

	// the page changed (the live client), or loaded: open as the player left it, on pages
	// with the link
	function sync() {
		var want = load().open && toggle();
		if (want && !isOpen()) open(false);
		else if (!want && isOpen()) close(false);
	}
	window.addEventListener("resize", function () { if (isOpen()) place(win.offsetLeft, win.offsetTop); });
	if (window.DK) window.DK.on("applied", sync);
	sync();
})();
