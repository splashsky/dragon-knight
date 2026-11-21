// live.js :: live pages (docs/APP.md "Live pages"). One event stream (GET /live) per
// browser, shared by its tabs: the tabs elect a leader (a heartbeat in localStorage) that
// holds the EventSource and forwards every event to the others over a BroadcastChannel;
// when it closes, another tab takes over. Without BroadcastChannel or localStorage each
// tab has its own stream. The events update the Babble Box, who's online, the broadcast
// banner, show notices, and close the page's stream on logout. Event data is put in the
// page with textContent only. Loaded on every page, it runs while the page is a logged-in
// player's (<body data-live>): with the live client (client.js) the page stays while the
// player logs in and out, so the stream starts and stops as data-live comes and goes. When
// it changes a part of the page itself it tells the live client (DK.touched), whose next
// answer then brings that part as the server has it. Without it everything works with
// plain forms and page loads.
(function () {
	"use strict";
	var body = document.body;
	if (!body || !window.EventSource || !window.fetch) return;

	function csrf() { return body.getAttribute("data-csrf") || ""; }
	function sessionId() { return body.getAttribute("data-live-session") || ""; }
	function isAdmin() { return body.hasAttribute("data-live-admin"); }
	function touched(el) { if (window.DK && window.DK.touched) window.DK.touched(el); }
	var HISTORY = 50;               // messages kept in a chat panel (lib/chat.lua HISTORY)
	var EVENTS = ["babble", "delete", "join", "leave", "news", "reply", "banner", "clear", "logout", "stale", "resync"];
	// the leader's claim is renewed every BEAT; a visible tab takes over a claim older than
	// STALE, a hidden one (its timers may be throttled to once a minute) one older than
	// HIDDEN_STALE
	var KEY = "dk-live-leader", BEAT = 2000, STALE = 6000, HIDDEN_STALE = 90000;

	// ---- helpers

	function $$(sel) { return Array.prototype.slice.call(document.querySelectorAll(sel)); }
	function el(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }
	function txt(s) { return document.createTextNode(s); }
	function here() { return location.pathname + location.search; }
	function safeUrl(u) { return typeof u === "string" && /^\/(?![\/\\])/.test(u) ? u : null; }
	// A copy of the page's <template data-proto="name"> (the server renders them with the
	// page: the same markup as its own, with this page's CSRF token and address) with
	// values filled in: data-slot="key" gets the value as text (data-unwrap: the text alone,
	// no element), data-slot-attr="attr:key ..." the values as attributes (left out when a
	// value is missing). null when the page has no such prototype.
	function proto(name, values) {
		var t = document.querySelector('template[data-proto="' + name + '"]');
		if (!t || !t.content) return null;
		var frag = t.content.cloneNode(true);
		Array.prototype.forEach.call(frag.querySelectorAll("[data-slot-attr]"), function (e) {
			e.getAttribute("data-slot-attr").split(" ").forEach(function (pair) {
				var i = pair.indexOf(":"), v = values[pair.slice(i + 1)];
				if (i > 0 && v != null) e.setAttribute(pair.slice(0, i), String(v));
			});
			e.removeAttribute("data-slot-attr");
		});
		Array.prototype.forEach.call(frag.querySelectorAll("[data-slot]"), function (e) {
			var v = values[e.getAttribute("data-slot")];
			v = v == null ? "" : String(v);
			if (e.hasAttribute("data-unwrap")) { e.parentNode.replaceChild(txt(v), e); return; }
			e.textContent = v;
			e.removeAttribute("data-slot");
		});
		var root = frag.firstElementChild;
		if (root) root.normalize();
		return root;
	}
	function post(url, fields) {
		var data = new URLSearchParams(fields);
		data.set("csrf", csrf());
		return fetch(url, { method: "POST", body: data, credentials: "same-origin",
			headers: { "Accept": "application/json", "X-CSRF-Token": csrf() } });
	}
	function local(fn) { try { return fn(window.localStorage); } catch (e) { return null; } }

	// ---- the Babble Box

	function addPost(m) {
		var id = Number(m.id);
		if (!id) return;
		$$("[data-chat-posts]").forEach(function (list) {
			if (list.querySelector('[data-id="' + id + '"]')) return;
			var li = proto("chat-post", { id: id, when: m.when, author: m.author, text: m.text,
				delete: safeUrl(m.delete) });
			if (!li) return;
			var next = null;
			Array.prototype.forEach.call(list.children, function (c) {
				if (!next && Number(c.getAttribute("data-id")) > id) next = c;
			});
			list.insertBefore(li, next);
			while (list.children.length > HISTORY) list.removeChild(list.firstElementChild);
			touched(list);
		});
	}
	function removePost(id) {
		$$('[data-chat-posts] [data-id="' + Number(id) + '"]').forEach(function (li) { touched(li); li.remove(); });
	}
	function chatStatus(form, msg) {
		var s = form.querySelector("[data-chat-status]");
		if (s) s.textContent = msg || "";
	}
	function sendChat(form) {
		var input = form.elements.babble;
		if (!input || !input.value.trim()) return;
		post("/babble", { babble: input.value }).then(function (res) {
			if (res.redirected) { location.reload(); return; }
			return res.json().then(function (j) {
				if (res.ok) {
					input.value = "";
					chatStatus(form, "");
					if (j.message) addPost(j.message);
				} else {
					chatStatus(form, j.error || "The message could not be sent.");
				}
			});
		}).catch(function () { chatStatus(form, "The message could not be sent."); });
	}

	// ---- who's online

	function setCount(n) {
		if (typeof n === "number") $$("[data-online-count]").forEach(function (e) { e.textContent = n; touched(e); });
	}
	function relist(list, links) {
		links.sort(function (a, b) {
			var x = a.textContent.toLowerCase(), y = b.textContent.toLowerCase();
			return x < y ? -1 : x > y ? 1 : Number(a.getAttribute("data-id")) - Number(b.getAttribute("data-id"));
		});
		list.textContent = "";
		links.forEach(function (a, i) { list.appendChild(txt(i ? ", " : " ")); list.appendChild(a); });
		touched(list);
	}
	function onlineLinks(list) { return Array.prototype.slice.call(list.querySelectorAll("a[data-id]")); }
	// The box lists at most data-online-limit names; "and N more" covers the rest (a name
	// that leaves is not replaced by a hidden one until the next page load).
	function setMore(list, count) {
		var box = list.parentNode, more = box && box.querySelector("[data-online-more]");
		if (!more || typeof count !== "number") return;
		var n = Math.max(0, count - onlineLinks(list).length);
		var c = more.querySelector("[data-online-more-count]");
		if (c) c.textContent = n;
		more.hidden = n === 0;
		touched(more);
	}
	function join(p) {
		setCount(p.online);
		var id = Number(p.id);
		$$("[data-online-list]").forEach(function (list) {
			var links = onlineLinks(list), limit = Number(list.getAttribute("data-online-limit")) || 0;
			if (!links.some(function (a) { return Number(a.getAttribute("data-id")) === id; }) &&
				(!limit || links.length < limit)) {
				var a = proto("online-name", { id: id, url: safeUrl(p.url), name: p.name });
				if (!a) return;
				links.push(a);
				relist(list, links);
			}
			setMore(list, p.online);
		});
	}
	function leave(p) {
		setCount(p.online);
		$$("[data-online-list]").forEach(function (list) {
			relist(list, onlineLinks(list).filter(function (a) { return Number(a.getAttribute("data-id")) !== Number(p.id); }));
			setMore(list, p.online);
		});
	}

	// ---- notices (toasts)

	function toast(before, title, url, after) {
		if (window.opener) return;   // not in the small windows (the character sheet, the map)
		var box = document.querySelector(".dk-toasts");
		if (!box) {
			box = el("div", "dk-toasts");
			box.setAttribute("data-client", "");   // the live client's morph leaves it alone
			box.setAttribute("role", "status"); box.setAttribute("aria-live", "polite");
			body.appendChild(box);
		}
		var t = proto("toast", { before: before, title: title, url: safeUrl(url), after: after || "" });
		if (!t) return;
		var x = t.querySelector(".dk-toast-close");
		if (x) x.addEventListener("click", function () { t.remove(); });
		box.appendChild(t);
		setTimeout(function () { t.remove(); }, 12000);
	}

	// ---- the broadcast banner

	function dismissed() { var m = document.cookie.match(/(?:^|;\s*)dk_banner=(\d+)/); return m ? Number(m[1]) : 0; }
	function expire(div, ttl) {
		if (ttl > 0) setTimeout(function () { touched(div); div.remove(); }, ttl * 1000);
	}
	function showBanner(b) {
		var id = Number(b.id);
		if (!id || dismissed() === id) return;
		$$("[data-banner-slot]").forEach(function (slot) {
			var div = proto("banner", { id: id, text: b.text });
			if (!div) return;
			slot.textContent = "";
			slot.appendChild(div);
			touched(slot);
			expire(div, Number(b.ttl));
		});
	}
	function clearBanner() { $$(".dk-banner").forEach(function (d) { touched(d); d.remove(); }); }
	function dismissBanner(id) {
		document.cookie = "dk_banner=" + Number(id) + "; path=/; max-age=2592000; samesite=lax";
		clearBanner();
	}

	// ---- resync: the live parts again, as the server renders them

	function refresh() {
		// the live client: the whole page as the server has it now, only what changed
		if (window.DK && window.DK.refresh) { window.DK.refresh(); return; }
		fetch("/live/state?back=" + encodeURIComponent(here()), { credentials: "same-origin",
			headers: { "Accept": "application/json" } }).then(function (res) {
			if (res.redirected) { location.reload(); return; }
			if (!res.ok) return;
			return res.json().then(function (s) {
				if (typeof s.chat === "string") $$("[data-chat-posts]").forEach(function (e) { e.innerHTML = s.chat; });
				if (s.online) {
					setCount(s.online.count);
					// /live/state renders the capped box; the full /online list keeps its names
					$$("[data-online-list][data-online-limit]").forEach(function (e) { e.innerHTML = s.online.html; });
					$$("[data-online-list]").forEach(function (e) { setMore(e, s.online.count); });
				}
				if (typeof s.banner === "string") $$("[data-banner-slot]").forEach(function (e) { e.innerHTML = s.banner; });
				initBanners();
			});
		}).catch(function () {});
	}
	var timed = window.WeakSet ? new WeakSet() : null;
	function initBanners() {
		$$(".dk-banner[data-banner-ttl]").forEach(function (d) {
			if (timed && timed.has(d)) return;
			if (timed) timed.add(d);
			expire(d, Number(d.getAttribute("data-banner-ttl")));
		});
	}

	// ---- the player changed something on another page (another tab, another device): this
	// page asks the live client for itself again (only what changed comes), a moment later
	// (several changes, one request); a hidden page when it shows again, as one that was
	// hidden for over a minute anyway

	var staleTimer = 0, missed = false, hiddenAt = 0;
	function stale(d) {
		if (!window.DK || d.tab === window.DK.tab) return;
		if (document.visibilityState === "hidden") { missed = true; return; }
		clearTimeout(staleTimer);
		staleTimer = setTimeout(function () { window.DK.refresh(); }, 250);
	}
	document.addEventListener("visibilitychange", function () {
		if (document.visibilityState === "hidden") { hiddenAt = Date.now(); return; }
		if (running && window.DK && (missed || (hiddenAt && Date.now() - hiddenAt > 60000))) window.DK.refresh();
		missed = false;
	});

	// ---- events (every tab)

	var seen = [];
	var handlers = {
		babble: addPost,
		"delete": function (d) { removePost(d.id); },
		join: join,
		leave: leave,
		news: function (n) { toast("News: ", n.title, n.url, n.author ? " (by " + n.author + ")" : ""); },
		reply: function (r) { toast(r.author + " replied in ", r.title, r.url); },
		banner: showBanner,
		clear: clearBanner,
		logout: function (d) {
			if (!(d.all || d.session === sessionId())) return;
			// this page's session ended: with the live client the page asks for itself again
			// (the login page comes; a logout this tab sent brings it anyway), else it reloads
			end();
			if (window.DK) window.DK.refresh(); else location.reload();
		},
		stale: stale,
		resync: refresh,
	};
	function handle(name, raw, id) {
		if (id) {
			if (seen.indexOf(id) >= 0) return;
			seen.push(id);
			if (seen.length > 100) seen.shift();
		}
		var data = {};
		if (raw) { try { data = JSON.parse(raw); } catch (e) { return; } }
		if (handlers[name] && data && typeof data === "object") handlers[name](data);
	}

	// ---- the stream (the leader tab's)

	var bc = null;
	if (window.BroadcastChannel && local(function (s) { s.getItem(KEY); return true; })) {
		try { bc = new BroadcastChannel("dk-live"); } catch (e) { bc = null; }
	}
	var me = Math.random().toString(36).slice(2) + Date.now().toString(36);
	var leader = false, stopped = false, es = null, delay = 1000, timer = null;

	function broadcast(name, data, id) {
		if (bc) bc.postMessage({ type: "event", name: name, data: data, id: id || "" });
		handle(name, data, id);
	}
	function closeStream() {
		if (es) { es.close(); es = null; }
		clearTimeout(timer);
	}
	function open(resync) {
		closeStream();
		if (stopped) return;
		es = new EventSource("/live");
		es.onopen = function () {
			delay = 1000;
			if (resync) { resync = false; broadcast("resync", ""); }
		};
		EVENTS.forEach(function (name) {
			es.addEventListener(name, function (ev) { broadcast(name, ev.data, ev.lastEventId); });
		});
		es.addEventListener("bye", function () { closeStream(); retry(2000 + Math.random() * 3000); });
		// a network error reconnects by itself (CONNECTING); an error status closes it
		es.onerror = function () { if (es && es.readyState === 2) { closeStream(); retry(backoff()); } };
	}
	// 1 s, doubling up to a minute, with jitter; back to 1 s once a stream opens
	function backoff() {
		var ms = delay * (0.75 + Math.random() / 2);
		delay = Math.min(delay * 2, 60000);
		return ms;
	}
	// After an error status or a shutdown: is the player still logged in? A redirect to
	// /login (or another refusal) stops; a busy server is tried again later, less often.
	function retry(ms) {
		clearTimeout(timer);
		timer = setTimeout(function () {
			fetch("/live/state", { credentials: "same-origin", headers: { "Accept": "application/json" } })
				.then(function (res) {
					if (res.redirected || (res.status >= 400 && res.status < 500 && res.status !== 429)) { stop(); return; }
					if (!res.ok) throw new Error("busy");
					open(true);
				}).catch(function () { retry(backoff()); });
		}, ms);
	}
	function stop() {
		stopped = true;
		closeStream();
		// the claim goes, also one not confirmed yet
		if (bc) local(function (s) { var c = readLeader(); if (c && c.id === me) s.removeItem(KEY); });
		leader = false;
	}
	function readLeader() {
		var v = local(function (s) { return s.getItem(KEY); });
		try { return v ? JSON.parse(v) : null; } catch (e) { return null; }
	}
	function writeLeader() { local(function (s) { s.setItem(KEY, JSON.stringify({ id: me, t: Date.now() })); }); }
	function lead(resync) {
		leader = true;
		open(resync);
	}
	// Every BEAT: the leader renews its claim (and steps down if another tab took over);
	// a follower claims a stale or missing lead, and takes it if the claim holds.
	function tick(resync) {
		if (stopped) return;
		var cur = readLeader(), now = Date.now();
		var stale = document.visibilityState === "hidden" ? HIDDEN_STALE : STALE;
		if (leader) {
			if (cur && cur.id !== me && now - cur.t < STALE) { leader = false; closeStream(); return; }
			writeLeader();
		} else if (!cur || now - cur.t > stale) {
			writeLeader();
			setTimeout(function () {
				var c = readLeader();
				if (!leader && !stopped && c && c.id === me) lead(resync || !!cur);
			}, 100 + Math.random() * 100);
		}
	}

	// ---- start and stop with <body data-live>

	var running = false, beat = 0;
	function live() { return body.hasAttribute("data-live"); }

	document.addEventListener("submit", function (ev) {
		var f = ev.target;
		if (!running) return;
		if (f.matches("[data-chat-form]")) { ev.preventDefault(); sendChat(f); }
		else if (f.matches("form.chat-delete")) {
			ev.preventDefault();
			post(f.getAttribute("action"), {}).then(function (res) {
				if (res.ok) removePost(f.getAttribute("action").split("/")[2]);
			}).catch(function () {});
		} else if (f.matches("form.dk-banner-dismiss")) {
			ev.preventDefault();
			dismissBanner(f.elements.id.value);
		}
	});
	if (bc) {
		bc.onmessage = function (ev) {
			var m = ev.data || {};
			if (!running) return;
			if (m.type === "event" && !leader) handle(m.name, m.data, m.id);
			else if (m.type === "gone" && !leader) setTimeout(function () { tick(true); }, Math.random() * 200);
		};
		window.addEventListener("pagehide", function () {
			if (!leader) return;
			leader = false;
			closeStream();
			local(function (s) { var c = readLeader(); if (c && c.id === me) s.removeItem(KEY); });
			bc.postMessage({ type: "gone" });
		});
	}
	// back from the browser's page cache: what the page shows may be old
	window.addEventListener("pageshow", function (ev) { if (ev.persisted && running) { refresh(); tick(false); } });

	function begin() {
		if (running || !live()) return;
		running = true;
		stopped = false;
		initBanners();
		if (!bc) { leader = true; open(false); return; }
		tick(false);
		beat = setInterval(function () { tick(false); }, BEAT);
	}
	function end() {
		if (!running) return;
		running = false;
		clearInterval(beat);
		stop();
	}
	// the live client brought a page: logged in or out, banners to time
	if (window.DK) window.DK.on("applied", function () {
		if (!live()) { end(); return; }
		if (running) initBanners(); else begin();
	});
	begin();
})();
