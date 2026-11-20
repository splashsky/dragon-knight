// live.js :: live pages (docs/APP.md "Live pages"). One event stream (GET /live) per
// browser, shared by its tabs: the tabs elect a leader (a heartbeat in localStorage) that
// holds the EventSource and forwards every event to the others over a BroadcastChannel;
// when it closes, another tab takes over. Without BroadcastChannel or localStorage each
// tab has its own stream. The events update the Babble Box, who's online, the broadcast
// banner, show notices, and close the page's stream on logout. Event data is put in the
// page with textContent only. Loaded on the pages of logged-in players (<body data-live>);
// without it everything works with plain forms and page loads.
(function () {
	"use strict";
	var body = document.body;
	if (!body || !body.hasAttribute("data-live") || !window.EventSource || !window.fetch) return;

	var CSRF = body.getAttribute("data-csrf") || "";
	var SESSION = body.getAttribute("data-live-session") || "";
	var ADMIN = body.hasAttribute("data-live-admin");
	var HISTORY = 50;               // messages kept in a chat panel (lib/chat.lua HISTORY)
	var EVENTS = ["babble", "delete", "join", "leave", "news", "reply", "banner", "clear", "logout", "resync"];
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
	function hidden(name, value) {
		var i = el("input"); i.type = "hidden"; i.name = name; i.value = value; return i;
	}
	function post(url, fields) {
		var data = new URLSearchParams(fields);
		data.set("csrf", CSRF);
		return fetch(url, { method: "POST", body: data, credentials: "same-origin",
			headers: { "Accept": "application/json", "X-CSRF-Token": CSRF } });
	}
	function local(fn) { try { return fn(window.localStorage); } catch (e) { return null; } }

	// ---- the Babble Box

	function deleteForm(id) {
		var f = el("form", "inline chat-delete");
		f.method = "post"; f.action = "/babble/" + id + "/delete";
		f.appendChild(hidden("csrf", CSRF)); f.appendChild(hidden("back", here()));
		var b = el("button", "link"); b.type = "submit"; b.title = "Delete"; b.setAttribute("aria-label", "Delete");
		b.textContent = "\u00d7";
		f.appendChild(b);
		return f;
	}
	function addPost(m) {
		var id = Number(m.id);
		if (!id) return;
		$$("[data-chat-posts]").forEach(function (list) {
			if (list.querySelector('[data-id="' + id + '"]')) return;
			var li = el("li", "babble-post");
			li.setAttribute("data-id", id);
			if (m.time) li.title = new Date(m.time * 1000).toLocaleString();
			var b = el("b"); b.textContent = String(m.author);
			li.appendChild(txt("[")); li.appendChild(b); li.appendChild(txt("] " + String(m.text)));
			if (ADMIN) { li.appendChild(txt(" ")); li.appendChild(deleteForm(id)); }
			var next = null;
			Array.prototype.forEach.call(list.children, function (c) {
				if (!next && Number(c.getAttribute("data-id")) > id) next = c;
			});
			list.insertBefore(li, next);
			while (list.children.length > HISTORY) list.removeChild(list.firstElementChild);
		});
	}
	function removePost(id) {
		$$('[data-chat-posts] [data-id="' + Number(id) + '"]').forEach(function (li) { li.remove(); });
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
	function keepChatOpen() {
		$$("details[data-chat]").forEach(function (d) {
			if (local(function (s) { return s.getItem("dk-chat-closed"); }) === "1") d.removeAttribute("open");
			d.addEventListener("toggle", function () {
				local(function (s) { s.setItem("dk-chat-closed", d.open ? "0" : "1"); });
			});
		});
	}

	// ---- who's online

	function setCount(n) {
		if (typeof n === "number") $$("[data-online-count]").forEach(function (e) { e.textContent = n; });
	}
	function relist(list, links) {
		links.sort(function (a, b) {
			var x = a.textContent.toLowerCase(), y = b.textContent.toLowerCase();
			return x < y ? -1 : x > y ? 1 : Number(a.getAttribute("data-id")) - Number(b.getAttribute("data-id"));
		});
		list.textContent = "";
		links.forEach(function (a, i) { list.appendChild(txt(i ? ", " : " ")); list.appendChild(a); });
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
	}
	function join(p) {
		setCount(p.online);
		var id = Number(p.id);
		$$("[data-online-list]").forEach(function (list) {
			var links = onlineLinks(list), limit = Number(list.getAttribute("data-online-limit")) || 0;
			if (!links.some(function (a) { return Number(a.getAttribute("data-id")) === id; }) &&
				(!limit || links.length < limit)) {
				var a = el("a"); a.href = "/character/" + id; a.setAttribute("data-id", id); a.textContent = String(p.name);
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
		var box = document.querySelector(".dk-toasts");
		if (!box) {
			box = el("div", "dk-toasts");
			box.setAttribute("role", "status"); box.setAttribute("aria-live", "polite");
			body.appendChild(box);
		}
		var t = el("div", "dk-toast");
		t.appendChild(txt(before));
		var link = safeUrl(url), a = el(link ? "a" : "b");
		if (link) a.href = link;
		a.textContent = String(title);
		t.appendChild(a);
		if (after) t.appendChild(txt(after));
		var x = el("button", "link dk-toast-close"); x.type = "button"; x.textContent = "\u00d7"; x.setAttribute("aria-label", "Close");
		x.addEventListener("click", function () { t.remove(); });
		t.appendChild(x);
		box.appendChild(t);
		setTimeout(function () { t.remove(); }, 12000);
	}

	// ---- the broadcast banner

	function dismissed() { var m = document.cookie.match(/(?:^|;\s*)dk_banner=(\d+)/); return m ? Number(m[1]) : 0; }
	function expire(div, ttl) {
		if (ttl > 0) setTimeout(function () { div.remove(); }, ttl * 1000);
	}
	function showBanner(b) {
		var id = Number(b.id);
		if (!id || dismissed() === id) return;
		$$("[data-banner-slot]").forEach(function (slot) {
			slot.textContent = "";
			var div = el("div", "dk-banner"); div.setAttribute("role", "status"); div.setAttribute("data-banner", id);
			var span = el("span", "dk-banner-text"); span.textContent = String(b.text);
			var f = el("form", "inline dk-banner-dismiss"); f.method = "post"; f.action = "/banner/dismiss";
			f.appendChild(hidden("csrf", CSRF)); f.appendChild(hidden("id", id)); f.appendChild(hidden("back", here()));
			var x = el("button", "link"); x.type = "submit"; x.title = "Dismiss"; x.setAttribute("aria-label", "Dismiss");
			x.textContent = "\u00d7";
			f.appendChild(x); div.appendChild(span); div.appendChild(f); slot.appendChild(div);
			expire(div, Number(b.ttl));
		});
	}
	function clearBanner() { $$(".dk-banner").forEach(function (d) { d.remove(); }); }
	function dismissBanner(id) {
		document.cookie = "dk_banner=" + Number(id) + "; path=/; max-age=2592000; samesite=lax";
		clearBanner();
	}

	// ---- resync: the live parts again, as the server renders them

	function refresh() {
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
	function initBanners() {
		$$(".dk-banner[data-banner-ttl]").forEach(function (d) { expire(d, Number(d.getAttribute("data-banner-ttl"))); });
	}

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
			if (d.all || d.session === SESSION) { stop(); location.reload(); }
		},
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
		if (leader && bc) local(function (s) { var c = readLeader(); if (c && c.id === me) s.removeItem(KEY); });
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

	// ---- start

	document.addEventListener("submit", function (ev) {
		var f = ev.target;
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
	keepChatOpen();
	initBanners();

	if (!bc) { leader = true; open(false); return; }
	bc.onmessage = function (ev) {
		var m = ev.data || {};
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
	// back from the browser's page cache: what the page shows may be old
	window.addEventListener("pageshow", function (ev) { if (ev.persisted) { refresh(); tick(false); } });
	tick(false);
	setInterval(function () { tick(false); }, BEAT);
})();
