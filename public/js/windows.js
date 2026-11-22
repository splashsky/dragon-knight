// windows.js :: floating windows over the page (docs/APP.md "Windows"): the Babble Box, the
// world map and the character sheet. A link <a href="/map" data-window="map"> opens and
// closes its window, which holds the page at the link's address, fetched as a dialog's page
// (X-DK-Modal: the content alone; the chat's forms and messages live.js keeps going as on
// its page). They are the player's: the strip at the top (the title, the close button at
// the right) drags one, its corner resizes it, a press brings it to the front, and where
// each is, its size and whether it is open are kept (localStorage), so it stays open from
// page to page (the live client's morph leaves them: data-client; a page load opens them
// again). They aren't <dialog>s: the game goes on under them (the arrow keys, the hotbar),
// and a dialog (modal.js) leaves them working and over it. Escape in one closes it. A page
// without a window's link (logged out, the admin panel) doesn't show that window. Without
// JavaScript the links are their pages. The World Map's weather (the map window's, the
// /map page's) is swapped in when the server's tick says it moved (`sky`: below), or drawn
// with WebGL where it can be (worldgl.js, loaded here once a map shows).
(function () {
	"use strict";
	if (typeof document === "undefined" || !window.fetch || !window.JSON || !window.Promise) return;

	// Each window: its title; where it opens the first time (the bottom right corner, the
	// middle, the top right under the header); what of the page it shows (default: the content); the field
	// focused when the player opens it; the regions (layout/main.html) whose change means
	// it is out of date and fetched again (those that hold the right column's panels too:
	// an answer names the outermost region that changed); a <details> of the page folded in
	// the window (open as the player last left it there).
	var KINDS = {
		chat: { title: "Babble Box", at: "corner", pick: ".chat", focus: "[name=babble]" },
		map: { title: "World Map", at: "middle", stale: ["loc", "left", "root"], fold: ".world-map-key" },   // the player's ring; the legend
		stats: { title: "Extended Stats", at: "top", stale: ["charpanel", "invpanel", "spellpanel", "right", "root"] },
	};
	var MARGIN = 8, Z = 950;
	var wins = {};    // kind -> { el, body, loading, stale }
	var order = [];   // kinds, the front one last

	function key(kind) { return "dk-window-" + kind; }
	function load(kind) {
		try { return JSON.parse(window.localStorage.getItem(key(kind))) || {}; } catch (e) { return {}; }
	}
	function save(kind, patch) {
		var s = load(kind);
		for (var k in patch) s[k] = patch[k];
		try { window.localStorage.setItem(key(kind), JSON.stringify(s)); } catch (e) { /* private mode */ }
	}
	function link(kind) { return document.querySelector('a[data-window="' + kind + '"]'); }
	function isOpen(kind) { var w = wins[kind]; return !!(w && w.el.isConnected && !w.el.hidden); }

	// within the viewport, at least MARGIN from its edges
	function place(el, x, y) {
		var w = el.offsetWidth, h = el.offsetHeight;
		x = Math.max(MARGIN, Math.min(x, window.innerWidth - w - MARGIN));
		y = Math.max(MARGIN, Math.min(y, window.innerHeight - h - MARGIN));
		el.style.left = Math.round(x) + "px";
		el.style.top = Math.round(y) + "px";
	}
	function placeFirst(el, at) {
		var w = el.offsetWidth, h = el.offsetHeight, vw = window.innerWidth, vh = window.innerHeight;
		if (at === "middle") place(el, (vw - w) / 2, (vh - h) / 2);
		else if (at === "top") place(el, vw - w - 24, 120);
		else place(el, vw - w - 24, vh - h - 24);
	}

	function front(kind) {
		var i = order.indexOf(kind);
		if (i >= 0) order.splice(i, 1);
		order.push(kind);
		order.forEach(function (k, n) { if (wins[k]) wins[k].el.style.zIndex = Z + n; });
	}

	function build(kind) {
		var s = load(kind);
		var el = document.createElement("section");
		el.className = "dk-window dk-window-" + kind;
		el.hidden = true;
		el.setAttribute("data-client", "");   // the live client's morph leaves it alone
		el.setAttribute("role", "dialog");
		el.setAttribute("aria-label", KINDS[kind].title);
		var grip = document.createElement("div");
		grip.className = "dk-window-grip";
		grip.title = "Drag to move";
		var title = document.createElement("span");
		title.className = "dk-window-title";
		title.textContent = KINDS[kind].title;
		var x = document.createElement("button");
		x.type = "button";
		x.className = "dk-window-x";
		x.setAttribute("aria-label", "Close");
		x.title = "Close";
		x.textContent = "\u00d7";
		x.addEventListener("click", function () { close(kind, true); });
		grip.appendChild(title);
		grip.appendChild(x);
		var body = document.createElement("div");
		body.className = "dk-window-body";
		el.appendChild(grip);
		el.appendChild(body);
		if (s.w) el.style.width = s.w + "px";
		if (s.h) el.style.height = s.h + "px";
		document.body.appendChild(el);
		var w = wins[kind] = { el: el, body: body, loading: null, stale: false };

		el.addEventListener("pointerdown", function () { front(kind); }, true);
		// dragging by the strip (not its close button)
		var drag = null;
		grip.addEventListener("pointerdown", function (ev) {
			if (ev.button !== 0 || x.contains(ev.target)) return;
			drag = { dx: ev.clientX - el.offsetLeft, dy: ev.clientY - el.offsetTop };
			grip.setPointerCapture(ev.pointerId);
			el.classList.add("dk-window-dragging");
			ev.preventDefault();
		});
		grip.addEventListener("pointermove", function (ev) {
			if (drag) place(el, ev.clientX - drag.dx, ev.clientY - drag.dy);
		});
		function drop() {
			if (!drag) return;
			drag = null;
			el.classList.remove("dk-window-dragging");
			save(kind, { x: el.offsetLeft, y: el.offsetTop });
		}
		grip.addEventListener("pointerup", drop);
		grip.addEventListener("pointercancel", drop);
		// its size (the CSS resize corner)
		if (window.ResizeObserver) {
			var timer = 0;
			new ResizeObserver(function () {
				clearTimeout(timer);
				timer = setTimeout(function () { if (isOpen(kind)) save(kind, { w: el.offsetWidth, h: el.offsetHeight }); }, 300);
			}).observe(el);
		}
		el.addEventListener("keydown", function (ev) {
			if (ev.key === "Escape" && !ev.defaultPrevented) { ev.preventDefault(); close(kind, true); }
		});
		return w;
	}

	// The page at the link's address as a dialog's answer (its content alone), without the
	// live client's region names (the page itself may show them: /babble).
	function fill(kind) {
		var w = wins[kind], a = link(kind);
		if (w.loading) return w.loading;
		w.stale = false;
		var headers = { "X-DK-Modal": "1" };
		if (window.DK && window.DK.tab) headers["X-DK-Tab"] = window.DK.tab;
		w.loading = fetch(a.getAttribute("href"), { headers: headers, credentials: "same-origin" }).then(function (res) {
			if (res.headers.get("X-DK-Modal") !== "1") throw new Error("not a dialog's page");
			return res.text();
		}).then(function (html) {
			var t = document.createElement("template");
			t.innerHTML = html;
			var part = (KINDS[kind].pick && t.content.querySelector(KINDS[kind].pick)) || t.content.querySelector(".dk-modal-content");
			if (!part) throw new Error("nothing to show");
			Array.prototype.forEach.call(part.querySelectorAll("[data-r]"), function (e) { e.removeAttribute("data-r"); });
			part.removeAttribute("data-r");
			var fold = KINDS[kind].fold && part.querySelector(KINDS[kind].fold);
			if (fold) {
				fold.open = !!load(kind).fold;
				fold.addEventListener("toggle", function () { save(kind, { fold: fold.open }); });
			}
			w.body.textContent = "";
			w.body.appendChild(part);
			if (kind === "map") mapShown();
		}).catch(function () {
			w.body.textContent = "The " + KINDS[kind].title + " could not be loaded.";
		}).then(function () { w.loading = null; });
		return w.loading;
	}

	function open(kind, focus) {
		if (!link(kind)) return;
		var w = wins[kind];
		if (!w || !w.el.isConnected) w = build(kind);
		var s = load(kind);
		w.el.hidden = false;
		if (s.x != null) place(w.el, s.x, s.y); else placeFirst(w.el, KINDS[kind].at);
		front(kind);
		save(kind, { open: true });
		fill(kind).then(function () {
			if (!isOpen(kind) || !focus) return;
			var field = KINDS[kind].focus && w.el.querySelector(KINDS[kind].focus);
			(field || w.el.querySelector(".dk-window-x")).focus();
		});
	}

	function close(kind, byPlayer) {
		var w = wins[kind];
		if (!w) return;
		var had = w.el.contains(document.activeElement);
		w.el.hidden = true;
		w.body.textContent = "";
		if (byPlayer) {
			save(kind, { open: false });
			var a = link(kind);
			if (had && a) a.focus({ preventScroll: true });
		}
	}

	// the links: open or close (before the live client's listener, on window)
	document.addEventListener("click", function (ev) {
		var a = ev.target && ev.target.closest && ev.target.closest("a[data-window]");
		if (!a || !KINDS[a.getAttribute("data-window")]) return;
		if (ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
		ev.preventDefault();
		var kind = a.getAttribute("data-window");
		if (isOpen(kind)) close(kind, true); else open(kind, true);
	});

	// the page changed (the live client), or loaded: each window as the player left it, on
	// pages with its link; one whose regions changed is fetched again
	function sync() {
		Object.keys(KINDS).forEach(function (kind) {
			var want = load(kind).open && link(kind);
			if (want && !isOpen(kind)) open(kind, false);
			else if (!want && isOpen(kind)) close(kind, false);
			else if (want && wins[kind].stale) fill(kind);
		});
	}
	window.addEventListener("resize", function () {
		Object.keys(wins).forEach(function (kind) { if (isOpen(kind)) place(wins[kind].el, wins[kind].el.offsetLeft, wins[kind].el.offsetTop); });
	});
	// ---- the World Map's WebGL sky (worldgl.js): loaded once a map that offers it
	// (.world-map[data-sky-data]) shows, on browsers with WebGL2; it is told of the maps
	// shown after that (dk-map-shown). Until it draws, and wherever it can't, the SVG sky
	// below is the map's weather.
	var skyScript = null;
	function mapShown() {
		if (!document.querySelector(".world-map[data-sky-data]") || !window.WebGL2RenderingContext) return;
		if (skyScript) { document.dispatchEvent(new CustomEvent("dk-map-shown")); return; }
		skyScript = document.createElement("script");
		skyScript.src = "/static/js/worldgl.js";
		skyScript.async = true;
		skyScript.setAttribute("data-client", "");
		document.body.appendChild(skyScript);
	}

	// ---- the World Map's weather (town/sky.lua): when the server's tick says the sky moved
	// (live.js: a "dk-sky" event, every tick), every overlay the page shows (the
	// map window's, or the /map page's: <g data-sky>) is swapped for GET /map/sky's. The
	// server renders it all; the script only swaps it in, keeping each storm's element
	// (data-storm) and giving it the new position, so it glides there (CSS). A hidden page
	// does it when it shows again; with no map open, nothing happens.

	var skyMissed = false, skyLoading = null;
	function swapSky(old, fresh) {
		var oldStorms = old.querySelector(".sky-storms"), freshStorms = fresh.querySelector(".sky-storms");
		Array.prototype.forEach.call(fresh.children, function (part) {
			// the patterns, the cells' skies and the time of day: the new ones in their place
			var kind = part.tagName === "defs" ? "defs" : "." + (part.getAttribute("class") || "").split(" ")[0];
			if (kind === ".sky-storms" || kind === ".") return;
			var mine = old.querySelector(kind);
			if (mine) mine.replaceWith(document.importNode(part, true));
		});
		if (oldStorms && freshStorms) {
			var keep = {};
			Array.prototype.forEach.call(oldStorms.children, function (e) { keep[e.getAttribute("data-storm")] = e; });
			Array.prototype.forEach.call(freshStorms.children, function (e) {
				var key = e.getAttribute("data-storm"), mine = keep[key];
				if (mine) {
					["class", "transform", "style"].forEach(function (name) { mine.setAttribute(name, e.getAttribute(name) || ""); });
					delete keep[key];
				} else {
					oldStorms.appendChild(document.importNode(e, true));
				}
			});
			Object.keys(keep).forEach(function (key) { keep[key].remove(); });
		}
		old.setAttribute("data-sky", fresh.getAttribute("data-sky"));
	}
	function refreshSky(tick) {
		var shown = document.querySelectorAll("[data-sky]");
		if (!shown.length) return;
		if (document.visibilityState === "hidden") { skyMissed = true; return; }
		if (tick != null && Array.prototype.every.call(shown, function (g) { return g.getAttribute("data-sky") === String(tick); })) return;
		if (skyLoading) return;
		skyLoading = fetch("/map/sky", { credentials: "same-origin" }).then(function (res) {
			if (!res.ok) throw new Error("no sky");
			return res.text();
		}).then(function (text) {
			var fresh = new DOMParser().parseFromString(text, "image/svg+xml").querySelector("[data-sky]");
			if (!fresh) return;
			Array.prototype.forEach.call(document.querySelectorAll("[data-sky]"), function (g) { swapSky(g, fresh); });
		}).catch(function () { /* the next tick tries again */ }).then(function () { skyLoading = null; });
	}
	document.addEventListener("dk-sky", function (ev) { refreshSky(ev.detail && ev.detail.tick); });
	document.addEventListener("visibilitychange", function () {
		if (document.visibilityState === "visible" && skyMissed) { skyMissed = false; refreshSky(null); }
	});

	if (window.DK) {
		window.DK.on("before", function (info) {
			Object.keys(KINDS).forEach(function (kind) {
				var stale = KINDS[kind].stale;
				if (wins[kind] && stale && info.regions.some(function (r) { return stale.indexOf(r) >= 0; })) wins[kind].stale = true;
			});
		});
		window.DK.on("applied", function () { sync(); mapShown(); });
	}
	sync();
	mapShown();   // the /map page
})();
