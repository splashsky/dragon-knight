// client.js :: the live client (docs/APP.md "Live client"). Links and forms of the game go
// through fetch with X-DK-Live: 1 and X-DK-Have (the hashes of the regions on screen, from
// <html data-h> and every answer since); the server answers in the wire format with the
// regions that changed, which are morphed into the page: only the nodes that differ are
// touched, so focus, typed text, scroll positions and open panels stay, and the page's
// scripts and event stream live on. What is on screen after any request is what a full
// load of that address shows. Without this script (no JavaScript, an old browser, before
// it has loaded) every link and form works natively; whenever a request or its answer goes
// wrong, the page is loaded natively (GETs never change the game, so loading the address
// again is always safe). Other scripts use window.DK: visit(url), refresh(), on(name, fn)
// ("events:<kind>": a player of an answer's events, returning a promise, run before the
// regions apply; "before": then, with { regions (the names coming), from, to (the
// addresses), user (a link or form of the player's, not a refresh or back/forward) },
// returning a promise too (scene.js fades the page out); "applied": after an answer is
// on screen), touched(el) (a script changed
// the region el is in), view() ({ url, post }: the address on screen, a POST's own page?),
// busy().
(function () {
	"use strict";

	var SLOW = 250;            // ms before the progress bar shows
	var GET_TIMEOUT = 10000;   // ms before a GET is loaded natively instead

	// ---- pure parts (tests/js/test_client.js)

	// The wire format (app/lib/wire.lua): "DK1\n" then "<op> [<arg> ...] <length>\n<payload>\n"
	// frames, lengths in bytes. bytes: a Uint8Array; text: bytes -> string. Returns
	// [{ op, args, payload }] or throws.
	function decode(bytes, text) {
		var magic = [68, 75, 49, 10];
		for (var m = 0; m < 4; m++) if (bytes[m] !== magic[m]) throw new Error("wire: no DK1 header");
		var out = [], pos = 4;
		while (pos < bytes.length) {
			var nl = bytes.indexOf(10, pos);
			if (nl < 0) throw new Error("wire: no frame line");
			var words = text(bytes.subarray(pos, nl)).split(" ");
			var len = Number(words.pop());
			if (!(len >= 0) || words.length < 1) throw new Error("wire: bad frame line");
			var end = nl + 1 + len;
			if (end + 1 > bytes.length || bytes[end] !== 10) throw new Error("wire: short frame");
			out.push({ op: words[0], args: words.slice(1), payload: text(bytes.subarray(nl + 1, end)) });
			pos = end + 1;
		}
		return out;
	}

	// "name=hash ..." -> { name: hash } (merged into `into`; "name=-" removes)
	function mergeHashes(into, s) {
		String(s || "").split(/\s+/).forEach(function (w) {
			var i = w.indexOf("=");
			if (i < 1) return;
			var k = w.slice(0, i), v = w.slice(i + 1);
			if (v === "-") delete into[k]; else if (/^[0-9a-f]+$/.test(v)) into[k] = v;
		});
		return into;
	}
	function formatHashes(map) {
		return Object.keys(map).map(function (k) { return k + "=" + map[k]; }).join(" ");
	}

	// The path and query of a URL the live client may fetch, or null: same origin, not a
	// static file or the event stream, and not just another #hash of the page at `here`.
	function livePath(href, base, here) {
		var u;
		try { u = new URL(href, base); } catch (e) { return null; }
		var b = new URL(base);
		if (u.origin !== b.origin || !/^https?:$/.test(u.protocol)) return null;
		if (/^\/(static|live)(\/|$)/.test(u.pathname) || /^\/live\//.test(u.pathname)) return null;
		var path = u.pathname + u.search;
		if (u.hash && here != null && path === here) return null;
		return path;
	}

	var api = { decode: decode, mergeHashes: mergeHashes, formatHashes: formatHashes, livePath: livePath };
	if (typeof module === "object" && module.exports) module.exports = api;
	if (typeof document === "undefined") return;
	if (!window.fetch || !window.AbortController || !window.TextDecoder || !window.DOMParser || !window.URL ||
		!window.URLSearchParams || !window.FormData || !window.Promise || !(history && history.pushState) ||
		!document.documentElement.hasAttribute("data-h")) return;

	var root = document.documentElement;
	var utf8 = new TextDecoder("utf-8");
	function text(b) { return utf8.decode(b); }

	var have = mergeHashes({}, root.getAttribute("data-h"));
	var view = { url: here(), post: false };   // the address on screen; a POST's own page?
	var hooks = {};
	var inflight = null;       // { method, controller, form, timer }
	var queued = null;         // the visit to start once a POST is answered
	var lastButton = null;     // the submit button last clicked (browsers without ev.submitter)
	var slowTimer = 0, progress = null, announcer = null;
	// this page's id: the server's `stale` events say which page sent the change (live.js)
	var tab = Math.random().toString(36).slice(2, 14);

	function here() { return location.pathname + location.search; }
	function on(name, fn) { (hooks[name] = hooks[name] || []).push(fn); }
	function emit(name, arg) {
		(hooks[name] || []).forEach(function (fn) {
			try { fn(arg); } catch (e) { if (window.console) console.error(e); }
		});
	}
	function client(tag, cls) {
		var e = document.createElement(tag);
		e.className = cls;
		e.setAttribute("data-client", "");
		return e;
	}
	function closest(node, sel) {
		var el = node && (node.nodeType === 1 ? node : node.parentElement);
		return el && el.closest ? el.closest(sel) : null;
	}

	// ---- the morph: make `from` (in the page) like `to` (parsed), touching what differs

	function keyOf(n) {
		if (n.nodeType !== 1) return null;
		var k = n.getAttribute("data-r");
		if (k) return "r:" + k;
		if (n.id) return "#" + n.id;
		k = n.getAttribute("data-k") || n.getAttribute("data-id");
		return k ? n.nodeName + ":" + k : null;
	}
	// nodes other scripts put in the page (the tooltip box, toasts, the progress bar)
	function isClient(n) { return n.nodeType === 1 && n.hasAttribute("data-client"); }
	function same(a, b) {
		if (a.nodeType !== b.nodeType) return false;
		if (a.nodeType !== 1) return true;
		return a.nodeName === b.nodeName && (a.nodeName !== "INPUT" || a.type === b.type);
	}
	// attributes the page's scripts own: the open state of a <details> panel the player
	// folded, a title tooltip.js moved to data-tip-title
	function ownAttr(el, name, to) {
		if (name === "open" && el.nodeName === "DETAILS") return true;
		if (name === "data-tip-title") return true;
		if (name === "title" && el.hasAttribute("data-tip-title") && to &&
			to.getAttribute("title") === el.getAttribute("data-tip-title")) return true;
		return false;
	}
	function syncAttrs(from, to) {
		var i, a;
		for (i = 0; i < to.attributes.length; i++) {
			a = to.attributes[i];
			if (from.getAttribute(a.name) !== a.value && !ownAttr(from, a.name, to)) from.setAttribute(a.name, a.value);
		}
		for (i = from.attributes.length - 1; i >= 0; i--) {
			a = from.attributes[i];
			if (!to.hasAttribute(a.name) && !ownAttr(from, a.name, to)) from.removeAttribute(a.name);
		}
	}
	function morph(from, to) {
		syncAttrs(from, to);
		if (from.nodeName === "TEMPLATE") {
			if (from.innerHTML !== to.innerHTML) from.innerHTML = to.innerHTML;
			return;
		}
		morphChildren(from, to);
	}
	function morphChildren(from, to) {
		var keyed = {}, c, k;
		for (c = from.firstChild; c; c = c.nextSibling) {
			k = keyOf(c);
			if (k) keyed[k] = c;
		}
		var cur = from.firstChild, news = Array.prototype.slice.call(to.childNodes);
		for (var i = 0; i < news.length; i++) {
			var n = news[i], match = null;
			while (cur && isClient(cur)) cur = cur.nextSibling;
			// a region the page has as the server has it: the page's own element, from here
			// or from elsewhere in the page, moved here untouched
			var keep = n.nodeType === 1 && n.nodeName === "TEMPLATE" && n.getAttribute("data-r-keep");
			if (keep) {
				match = keyed["r:" + keep] || pageRegion(keep);
				if (!match) throw new Error("client.js: no region " + keep + " to keep");
				delete keyed["r:" + keep];
				if (match === cur) cur = cur.nextSibling;
				else from.insertBefore(match, cur);
				continue;
			}
			k = keyOf(n);
			if (k) {
				match = keyed[k] && same(keyed[k], n) ? keyed[k] : null;
				if (match) delete keyed[k];
			} else if (cur && !keyOf(cur) && same(cur, n)) {
				match = cur;
			}
			if (!match) {
				// a new node: the regions in it the page shows are the page's own (moved here)
				from.insertBefore(adopt(n, function (el) { if (el === cur) cur = cur.nextSibling; }), cur);
				continue;
			}
			if (match === cur) cur = cur.nextSibling;
			else from.insertBefore(match, cur);
			if (n.nodeType === 1) morph(match, n);
			else if (match.data !== n.data) match.data = n.data;
		}
		while (cur) {
			var next = cur.nextSibling;
			if (!isClient(cur)) { park(cur); from.removeChild(cur); }
			cur = next;
		}
	}
	// The page's own element for region `name` (in the page, or taken out by this answer).
	function pageRegion(name) {
		return document.querySelector('[data-r="' + name + '"]') || parked[name] || null;
	}
	// A new subtree going into the page: a region in it the page already shows is the page's
	// own element instead, morphed into the new markup (typed text, scroll and focus stay);
	// a placeholder (<template data-r-keep>) is the page's element as it is. moving(el) is
	// told about each element taken from its place.
	function adopt(n, moving) {
		if (n.nodeType !== 1) return n;
		var name = n.getAttribute("data-r"), old = name && pageRegion(name);
		if (old && old.nodeName === n.nodeName) {
			moving(old);
			morph(old, n);
			return old;
		}
		Array.prototype.slice.call(n.childNodes).forEach(function (c) {
			if (c.nodeType !== 1) return;
			var keep = c.nodeName === "TEMPLATE" && c.getAttribute("data-r-keep"), r;
			if (keep) {
				r = pageRegion(keep);
				if (!r) throw new Error("client.js: no region " + keep + " to keep");
				moving(r);
			} else {
				r = adopt(c, moving);
			}
			if (r !== c) n.replaceChild(r, c);
		});
		return n;
	}

	// Regions taken out of the page while an answer applies wait here: a later region of the
	// same answer may keep them (the chat moving from the middle column to the right one).
	var parked = {};
	function park(node) {
		if (node.nodeType !== 1) return;
		if (node.hasAttribute("data-r")) parked[node.getAttribute("data-r")] = node;
		Array.prototype.forEach.call(node.querySelectorAll("[data-r]"), function (e) { parked[e.getAttribute("data-r")] = e; });
	}

	// What is on screen in region `name` (and the regions in it) is not what the server's
	// hashes say: the next answer sends it.
	function forget(name) {
		var el = document.querySelector('[data-r="' + name + '"]');
		delete have[name];
		if (el) Array.prototype.forEach.call(el.querySelectorAll("[data-r]"), function (e) { delete have[e.getAttribute("data-r")]; });
	}

	// A region's HTML into the page; false when the page has no such region.
	function applyRegion(name, html) {
		if (name === "root") {
			var doc = new DOMParser().parseFromString("<!doctype html><html><head></head>" + html + "</html>", "text/html");
			morph(document.body, doc.body);
			return true;
		}
		// (a region taken out by an earlier region of this answer, waiting to be kept by a later one)
		var target = pageRegion(name);
		if (!target) return false;
		var t = document.createElement("template");
		t.innerHTML = html;
		var el = t.content.firstElementChild;
		if (!el || el.nodeName !== target.nodeName) {
			if (!el) return false;
			park(target);
			target.parentNode.replaceChild(adopt(el, function () {}), target);
			return true;
		}
		morph(target, el);
		return true;
	}

	// ---- progress and announcements

	function busy(on) {
		clearTimeout(slowTimer);
		var main = document.querySelector('[data-r="main"]');
		if (on) {
			if (main) main.setAttribute("aria-busy", "true");
			slowTimer = setTimeout(function () {
				if (!progress || !progress.isConnected) {
					progress = client("div", "dk-progress");
					progress.setAttribute("aria-hidden", "true");
					document.body.appendChild(progress);
				}
				root.classList.add("dk-busy");
			}, SLOW);
		} else {
			if (main) main.removeAttribute("aria-busy");
			root.classList.remove("dk-busy");
		}
	}
	function announce(title) {
		if (!announcer || !announcer.isConnected) {
			announcer = client("div", "dk-sr");
			announcer.setAttribute("aria-live", "polite");
			document.body.appendChild(announcer);
		}
		announcer.textContent = title;
	}

	// ---- history: each entry made here has a key; its scroll position is kept in memory
	// while the page lives (popstate comes after the browser left the entry, too late to ask)
	// and in history.state for reloads

	var entry = "", scrolls = {};
	function newKey() { return Math.random().toString(36).slice(2); }
	function entryState(post, x, y) { return { dk: 1, key: entry, post: !!post, x: x || 0, y: y || 0 }; }
	function saveScroll() {
		var st = history.state && history.state.dk ? history.state : {};
		try { history.replaceState(entryState(st.post, window.scrollX, window.scrollY), "", location.href); }
		catch (e) { /* too many replaceState calls: never mind */ }
	}

	// ---- requests

	// A native load of a GET address (the fallback for anything that goes wrong).
	function native(url) {
		window.location.assign(url || view.url);
		return new Promise(function () {});   // the page goes: stay busy
	}

	function visit(url, o) {
		o = o || {};
		o.method = o.method || "GET";
		if (inflight) {
			if (inflight.method === "POST") {
				// wait for the POST's answer (never cancel what changes the game); a second
				// submit of the same form is a double click
				if (!(o.form && o.form === inflight.form)) queued = [url, o];
				return;
			}
			inflight.controller.abort();
			clearTimeout(inflight.timer);
		}
		var controller = new AbortController();
		var req = inflight = { method: o.method, controller: controller, form: o.form };
		var timedOut = false;
		if (o.method === "GET") req.timer = setTimeout(function () { timedOut = true; controller.abort(); }, GET_TIMEOUT);
		busy(true);
		var answered = false;
		fetch(url, {
			method: o.method, body: o.body, credentials: "same-origin", signal: controller.signal,
			headers: { "X-DK-Live": "1", "X-DK-Have": formatHashes(have), "X-DK-Tab": tab },
		}).then(function (res) {
			answered = true;
			var type = res.headers.get("Content-Type") || "";
			if (type.indexOf("application/x-dk-live") === 0) {
				return res.arrayBuffer().then(function (buf) {
					busy(false);   // the answer is here (a fight round may still play)
					return apply(decode(new Uint8Array(buf), text), url, o);
				});
			}
			if (o.method === "GET") return native(url);
			// a POST answered with something else: show it as the browser would
			return res.text().then(function (body) { showDocument(body); });
		}).catch(function (err) {
			if (req !== inflight || (controller.signal.aborted && !timedOut)) return;   // superseded
			if (window.console) console.warn("client.js:", err);
			// a GET: load it natively; a POST lost before its answer may or may not have
			// happened: show the game as it is now
			return native(o.method === "GET" ? url : (answered ? null : view.url));
		}).then(function () {
			if (req !== inflight) return;
			clearTimeout(req.timer);
			inflight = null;
			busy(false);
			if (queued) {
				var q = queued;
				queued = null;
				visit(q[0], q[1]);
			}
		});
	}

	function showDocument(html) {
		document.open();
		document.write(html);
		document.close();
	}

	function apply(frames, requested, o) {
		var a = { title: null, url: null, events: [], regions: [], hashes: null, go: null, doc: null };
		frames.forEach(function (f) {
			if (f.op === "title") a.title = f.payload;
			else if (f.op === "url") a.url = f.payload;
			else if (f.op === "events") a.events.push({ kind: f.args[0], data: f.payload });
			else if (f.op === "region") a.regions.push({ name: f.args[0], html: f.payload });
			else if (f.op === "hashes") a.hashes = f.payload;
			else if (f.op === "go") a.go = f.payload;
			else if (f.op === "doc") a.doc = f.payload;
		});
		if (a.go != null) return native(a.go || view.url);
		if (a.doc != null) { showDocument(a.doc); return; }
		return play(a.events).then(function () { return before(a, o); }).then(function () {
			var focused = document.activeElement;
			parked = {};
			for (var i = 0; i < a.regions.length; i++) {
				if (a.regions[i].name === o.keep) continue;
				// a region the page lacks: the page isn't what the server thinks; load it
				if (!applyRegion(a.regions[i].name, a.regions[i].html)) {
					if (window.console) console.warn("client.js: the page has no region " + a.regions[i].name + ": loading it");
					return native(a.url || view.url);
				}
			}
			parked = {};
			if (a.hashes != null) mergeHashes(have, a.hashes);
			if (o.keep) forget(o.keep);
			if (o.form && o.form.isConnected && o.method === "POST") o.form.reset();
			if (a.title != null) document.title = a.title;
			finish(a, o, focused);
		});
	}

	// The "before" hooks, in turn, once the answer's events have played.
	function before(a, o) {
		var info = { regions: a.regions.map(function (r) { return r.name; }), from: view.url,
			to: a.url != null ? a.url : view.url, user: o.history !== "none" && !o.keep };
		var p = Promise.resolve();
		(hooks.before || []).forEach(function (fn) {
			p = p.then(function () {
				try { return fn(info); } catch (e) { if (window.console) console.error(e); }
			});
		});
		return p;
	}

	function play(events) {
		var p = Promise.resolve();
		events.forEach(function (e) {
			(hooks["events:" + e.kind] || []).forEach(function (fn) {
				p = p.then(function () { return fn(e.data); });
			});
		});
		return p;
	}

	// The address, history entry, scroll and focus after an answer.
	function finish(a, o, focused) {
		var url = a.url, moved = url != null && url !== view.url, post = a.url == null || !!o.post;
		if (url == null) url = view.url;   // a POST's own page: the address stays
		if (o.history === "none") {
			history.replaceState(entryState(post, o.scroll && o.scroll.x, o.scroll && o.scroll.y), "", url);
		} else if (moved) {
			saveScroll();
			entry = newKey();
			history.pushState(entryState(post), "", url);
		} else {
			history.replaceState(entryState(post, window.scrollX, window.scrollY), "", url);
		}
		view = { url: url, post: post };
		if (o.scroll) window.scrollTo(o.scroll.x, o.scroll.y);
		else if (moved) {
			var target = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
			if (target) target.scrollIntoView(); else window.scrollTo(0, 0);
		}
		if (moved && a.title) announce(a.title);
		// focus that was lost with its element goes to the middle column
		if (focused && focused !== document.body && !focused.isConnected) {
			var main = document.querySelector('[data-r="main"]');
			if (main) {
				main.setAttribute("tabindex", "-1");
				main.focus({ preventScroll: true });
			}
		}
		emit("applied", { url: url, post: post });
	}

	// ---- what the client takes over

	function formRequest(form, submitter) {
		var method = (form.getAttribute("method") || "get").toLowerCase();
		var action = form.getAttribute("action") || here();
		if ((method !== "get" && method !== "post") || (form.target && form.target !== "_self") ||
			form.hasAttribute("data-native") || (form.enctype && form.enctype !== "application/x-www-form-urlencoded")) return null;
		if (submitter && (submitter.hasAttribute("formaction") || submitter.hasAttribute("formmethod") ||
			submitter.hasAttribute("formtarget"))) return null;
		var path = livePath(action, location.href, null);
		if (!path) return null;
		var data;
		try { data = new FormData(form, submitter || undefined); } catch (e) {
			data = new FormData(form);
			if (submitter && submitter.name) data.append(submitter.name, submitter.value);
		}
		var params = new URLSearchParams();
		data.forEach(function (v, k) { if (typeof v === "string") params.append(k, v); });
		if (method === "get") {
			var u = new URL(path, location.href);
			u.search = params.toString();
			return { url: u.pathname + u.search, o: { method: "GET" } };
		}
		return { url: path, o: { method: "POST", body: params, form: form } };
	}

	// on window, so the page's other scripts (their listeners are on document) see clicks and
	// submits first: one that handles a form itself (the chat) prevents the default
	window.addEventListener("click", function (ev) {
		var button = closest(ev.target, "button, input[type=submit], input[type=image]");
		if (button && button.form) lastButton = button;
		if (ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
		var a = closest(ev.target, "a[href]");
		if (!a || (a.target && a.target !== "_self") || a.hasAttribute("download") || a.hasAttribute("data-popup") ||
			closest(a, "[data-native]")) return;
		var path = livePath(a.href, location.href, here());
		if (!path) return;
		ev.preventDefault();
		visit(path);
	});

	window.addEventListener("submit", function (ev) {
		var form = ev.target;
		if (ev.defaultPrevented || closest(form, "[data-native]")) return;
		// (the last button clicked only where browsers don't say: an Enter key or a script's
		// requestSubmit() has no button)
		var submitter = "submitter" in ev ? ev.submitter : (lastButton && lastButton.form === form ? lastButton : null);
		lastButton = null;
		var r = formRequest(form, submitter);
		if (!r) return;
		ev.preventDefault();
		visit(r.url, r.o);
	});

	window.addEventListener("popstate", function (ev) {
		var st = ev.state;
		if (!st || !st.dk) {
			if (here() !== view.url) native(here());   // an entry this page didn't make
			return;
		}
		// the page on screen is still the entry being left: its scroll
		scrolls[entry] = { x: window.scrollX, y: window.scrollY };
		view = { url: here(), post: !!st.post };
		entry = st.key || newKey();
		visit(here(), { history: "none", scroll: scrolls[entry] || { x: st.x || 0, y: st.y || 0 } });
	});

	history.scrollRestoration = "manual";
	var saved = history.state;   // a reload: where this entry was scrolled to
	entry = saved && saved.dk && saved.key || newKey();
	if (saved && saved.dk && (saved.x || saved.y)) window.scrollTo(saved.x, saved.y);
	history.replaceState(entryState(false, window.scrollX, window.scrollY), "", location.href);
	window.addEventListener("scroll", function () { scrolls[entry] = { x: window.scrollX, y: window.scrollY }; }, { passive: true });
	window.addEventListener("pagehide", saveScroll);

	window.DK = {
		visit: function (url) { visit(livePath(url, location.href, null) || url); },
		// the page as the server has it now (only what changed comes); a POST's own page keeps
		// its middle column (no GET shows it) and updates the rest
		refresh: function () {
			if (inflight) return;
			visit(view.url, { history: "none", keep: view.post ? "main" : null, post: view.post,
				scroll: { x: window.scrollX, y: window.scrollY } });
		},
		on: on,
		view: function () { return { url: view.url, post: view.post }; },
		busy: function () { return !!inflight; },
		tab: tab,
		// another script changed el's region in the page: its hash no longer says what is
		// on screen, so the next answer sends that region
		touched: function (el) {
			var r = closest(el, "[data-r]");
			delete have[r ? r.getAttribute("data-r") : "root"];
		},
	};
})();
