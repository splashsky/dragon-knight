// fight.js :: smooth fights (docs/APP.md "Fight API"). Loaded on the fight pages (fight,
// victory, item drop, death). Forms marked data-fight and links in the middle column to
// those pages go through fetch with Accept: application/json; the server runs the same
// handlers and answers { events, fragments, redirect, url, title } or { error }. The
// events are played one by one (a line every STEP ms, with the HP/MP bars and numbers,
// the statuses and the allies they change), then the page's parts are swapped for the
// fragments, rendered by the same templates as the pages, so what stays on screen is the
// page the server would have shown. A redirect to another fight page is fetched the same
// way and history.replaceState keeps the address right (a reload shows that page). A
// click, any key or "Skip" finishes the round at once; with prefers-reduced-motion there
// are no delays. Buttons are disabled while a round plays. On a network or JSON error the
// form is posted (or the link followed) as without JavaScript. Text from the server goes
// in with textContent only; fragments are the server's own HTML.
(function () {
	"use strict";
	var body = document.body;
	if (!body || !window.fetch || !window.URLSearchParams || !window.FormData || !window.Promise || !window.URL) return;

	var STEP = 400;
	var PAGES = { "/fight": true, "/victory": true, "/drop": true, "/dead": true };
	var PARTS = { player: "fight-yourturn", allies: "fight-allyturn", enemies: "fight-monsterturn", ending: "fight-roundend" };
	var motion = !(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);

	var busy = false;       // a request or a round is under way
	var skipping = false;   // the round plays to its end at once
	var wake = null;        // ends the current wait
	var refocus = false;    // the keyboard was in the middle column: focus the new form
	var lastButton = null;  // the submit button last clicked (browsers without ev.submitter)

	// ---- helpers

	function $(sel, root) { return (root || document).querySelector(sel); }
	function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
	function el(tag, cls, text) {
		var e = document.createElement(tag);
		if (cls) e.className = cls;
		if (text != null) e.textContent = text;
		return e;
	}
	function txt(s) { return document.createTextNode(s); }
	function remove(node) { if (node && node.parentNode) node.parentNode.removeChild(node); }
	function middle() { return $("[data-main]"); }
	function closest(node, sel) { return node && node.closest ? node.closest(sel) : null; }

	// a same-site fight page's path and query, or null
	function fightPage(url) {
		try {
			var u = new URL(url, location.href);
			return u.origin === location.origin && PAGES[u.pathname] ? u.pathname + u.search : null;
		} catch (e) { return null; }
	}

	function csrf(form) {
		var input = form && form.querySelector('input[name="csrf"]');
		return (input && input.value) || body.getAttribute("data-csrf") || "";
	}

	function request(url, data, form) {
		var opts = { credentials: "same-origin", headers: { "Accept": "application/json" } };
		if (data) {
			opts.method = "POST";
			opts.body = data;
			opts.headers["X-CSRF-Token"] = csrf(form);
		}
		return fetch(url, opts).then(function (res) {
			var type = res.headers.get("Content-Type") || "";
			if (!res.ok || type.indexOf("application/json") !== 0) throw new Error("fight.js: " + res.status + " " + type);
			return res.json();
		});
	}

	function lock(on) {
		busy = on;
		var m = middle();
		if (m) {
			if (on) m.setAttribute("aria-busy", "true"); else m.removeAttribute("aria-busy");
		}
		$$("form[data-fight] input, form[data-fight] select, form[data-fight] button").forEach(function (c) {
			if (on && !c.disabled) {
				c.disabled = true;
				c.setAttribute("data-fight-locked", "");
			} else if (!on && c.hasAttribute("data-fight-locked")) {
				c.disabled = false;
				c.removeAttribute("data-fight-locked");
			}
		});
	}

	function wait(ms) {
		if (skipping || !motion || ms <= 0) return Promise.resolve();
		return new Promise(function (resolve) {
			var timer = setTimeout(done, ms);
			function done() { clearTimeout(timer); wake = null; resolve(); }
			wake = done;
		});
	}

	function skip() {
		skipping = true;
		if (wake) wake();
	}

	function flash(node, cls) {
		node.classList.remove("fight-hurt", "fight-healed");
		void node.offsetWidth;   // restart the animation
		node.classList.add(cls);
	}

	// ---- bars and numbers

	function pct(v, max) { return Math.max(0, Math.min(100, Math.ceil(v / max * 100))); }
	function level(p) { return p >= 66 ? "high" : p >= 33 ? "mid" : "low"; }

	// the bar of a [data-stat][data-max] element (made on first use)
	function bar(node) {
		var max = Number(node.getAttribute("data-max")), v = Number(node.getAttribute("data-value"));
		if (!(max > 0) || isNaN(v)) return;
		var b = $(".fight-bar", node);
		if (!b) {
			b = el("span", "fight-bar");
			b.setAttribute("aria-hidden", "true");
			b.appendChild(el("span", "fight-bar-fill"));
			node.appendChild(b);
		}
		var p = pct(v, max);
		b.className = "fight-bar fight-bar-" + node.getAttribute("data-stat") + " fight-bar-" + level(p);
		b.firstChild.style.width = p + "%";
	}

	function enhance(root) {
		$$("[data-stat][data-max]", root).forEach(bar);
	}

	// the number in a combatant's line: "Monster's HP: 12", "Your Wolf: 20 / 30 HP"
	function setNumber(node, v) {
		for (var n = node.firstChild; n; n = n.nextSibling) {
			if (n.nodeType === 3 && /: -?\d+/.test(n.data)) {
				n.data = n.data.replace(/: -?\d+/, ": " + Math.max(0, v));
				return;
			}
		}
	}

	// the player's numbers and bars in the right column (layout/nav_right.html)
	function playerStat(kind, v, max) {
		var box = $("[data-player-stats]");
		var label = kind.toUpperCase() + ": ";
		if (box) {
			for (var n = box.firstChild; n; n = n.nextSibling) {
				if (n.nodeType !== 3 || n.data.indexOf(label) < 0) continue;
				var at = n.data.indexOf(label);
				var next = n.nextSibling;
				if (next && next.nodeType === 1 && next.tagName === "SPAN") remove(next);   // a blinking low number
				if (kind !== "tp" && max > 0 && v <= max / 5) {
					n.data = n.data.slice(0, at) + label;
					var low = el("span", "highlight blink");
					low.appendChild(el("b", null, "*" + v + "*"));
					box.insertBefore(low, n.nextSibling);
				} else {
					n.data = n.data.slice(0, at) + label + v;
				}
				break;
			}
		}
		var fill = $('[data-bar="' + kind + '"]');
		if (fill && max > 0) {
			var p = Math.ceil(v / max * 100);
			fill.style.height = Math.max(0, Math.min(100, p)) + "px";
			fill.className = "statbar-fill " + (p >= 66 ? "green" : p >= 33 ? "yellow" : "red");
		}
	}

	function stat(kind, c) {
		if (c.who === "player") { playerStat(kind, c.to, c.max); return; }
		$$('[data-fighter="' + Number(c.id) + '"][data-stat="' + kind + '"]', middle()).forEach(function (node) {
			node.setAttribute("data-value", c.to);
			if (c.max != null) node.setAttribute("data-max", c.max);
			setNumber(node, c.to);
			bar(node);
			flash(node, c.to < c.from ? "fight-hurt" : "fight-healed");
		});
	}

	// ---- combatants' lines, statuses, allies

	// the line of combatant id (made when the page has none: "You", the monster, an ally)
	function fighterLine(who, id, name) {
		var m = middle(), log = $("[data-fight-log]", m);
		if (!log) return null;
		var node = $('.fight-combatant[data-fighter="' + Number(id) + '"]', m);
		if (node) return node;
		node = el("p", "fight-combatant fight-" + (who === "player" ? "you" : who));
		node.setAttribute("data-fighter", id);
		if (who === "ally") node.appendChild(txt("Your "));
		node.appendChild(el("b", null, who === "player" ? "You" : name));
		var before = log;
		if (who !== "player") before = $(".fight-you", m) || before;
		if (who === "enemy") before = $(".fight-ally", m) || before;
		log.parentNode.insertBefore(node, before);
		return node;
	}

	function status(s) {
		var node = fighterLine(s.who, s.id, s.name);
		if (!node) return;
		var old = $(".fight-statuses", node);
		var list = s.statuses || [];
		var span = el("span", "fight-statuses");
		list.forEach(function (x, i) {
			span.appendChild(txt(i ? ", " : "\u2014 "));
			var chip = el("span", "fight-status" + (s.change === "add" && x.key === s.key ? " fight-status-new" : ""), x.name);
			if (x.turns != null) {
				chip.appendChild(txt(" "));
				chip.appendChild(el("span", "light", "(" + x.turns + " " + (x.turns === 1 ? "turn" : "turns") + ")"));
			}
			span.appendChild(chip);
		});
		if (s.change === "remove" || s.change === "expire") {
			span.appendChild(txt(list.length ? ", " : "\u2014 "));
			span.appendChild(el("span", "fight-status fight-status-gone", s.status));
		}
		if (old) {
			node.replaceChild(span, old);
		} else {
			var at = $(".fight-bar", node);
			node.insertBefore(txt(" "), at);
			node.insertBefore(span, at);
		}
	}

	function summon(s) {
		if (s.change === "join") {
			var node = fighterLine("ally", s.id, s.name);
			if (!node) return;
			node.setAttribute("data-stat", "hp");
			node.setAttribute("data-value", s.hp);
			node.setAttribute("data-max", s.max);
			node.appendChild(txt(": " + s.hp + " / " + s.max + " HP"));
			bar(node);
			node.classList.add("fight-joined");
		} else if (s.change === "leave") {
			var gone = $('.fight-combatant[data-fighter="' + Number(s.id) + '"]', middle());
			if (gone) gone.classList.add("fight-gone");
		}
	}

	// ---- playing a round

	function show(e, log) {
		if (e.text && log) {
			var cls = PARTS[e.part] || PARTS.ending;
			var p = log.lastElementChild;
			if (!p || !p.classList.contains(cls)) {
				p = el("p", cls);
				log.appendChild(p);
			} else {
				p.appendChild(el("br"));
			}
			p.appendChild(el("span", "fight-line fight-by-" + (e.actor || "none"), e.text));
		}
		(e.hp || []).forEach(function (c) { stat("hp", c); });
		(e.mp || []).forEach(function (c) { stat("mp", c); });
		(e.tp || []).forEach(function (c) { stat("tp", c); });
		(e.status || []).forEach(status);
		(e.summon || []).forEach(summon);
	}

	function play(events) {
		var m = middle(), log = m && $("[data-fight-log]", m);
		var lines = events.filter(function (e) { return e.text; }).length;
		var skipButton = null;
		skipping = false;
		if (log) {
			while (log.firstChild) log.removeChild(log.firstChild);
			log.setAttribute("aria-live", "polite");
			$$(".fight-stale, .fight-note", m).forEach(remove);
			if (motion && lines > 1) {
				skipButton = el("button", "fight-skip", "Skip");
				skipButton.type = "button";
				log.parentNode.insertBefore(skipButton, log.nextSibling);
			}
		}
		var i = 0, shown = 0;
		function next() {
			if (i >= events.length) {
				remove(skipButton);
				return Promise.resolve();
			}
			var e = events[i++];
			var delay = e.text && shown > 0 ? STEP : 0;
			if (e.text) shown++;
			return wait(delay).then(function () {
				show(e, log);
				return next();
			});
		}
		return next();
	}

	function note(text) {
		var m = middle();
		if (!m) return;
		$$(".fight-note", m).forEach(remove);
		var p = el("p", "fight-note error", text);
		p.setAttribute("role", "alert");
		var form = $("form[data-fight]", m);
		if (form) form.parentNode.insertBefore(p, form); else m.insertBefore(p, m.firstChild);
	}

	function swap(j) {
		var f = j.fragments, m = middle();
		if (f.main != null && m) {
			m.innerHTML = f.main;
			enhance(m);
		}
		var left = $("[data-nav-left]"), right = $("[data-nav-right]");
		if (f.nav_left != null && left) left.innerHTML = f.nav_left;
		if (f.nav_right != null && right) right.innerHTML = f.nav_right;
		if (j.title) document.title = j.title;
		var url = j.url && fightPage(j.url);
		if (url && window.history && history.replaceState) history.replaceState(null, "", url);
	}

	function follow(url) {
		var page = fightPage(url);
		if (!page) {
			location.assign(url);
			return new Promise(function () {});   // the page goes; stay busy
		}
		return request(page).then(handle, function () {
			location.assign(page);
			return new Promise(function () {});
		});
	}

	function handle(j) {
		if (j.error) {
			note(j.error);
			return Promise.resolve();
		}
		var events = j.events || [];
		return play(events).then(function () {
			if (j.fragments) swap(j);
			if (!j.redirect) return;
			// a moment to read the last blow before the next page
			var said = events.some(function (e) { return e.text; });
			return wait(said ? 2 * STEP : 0).then(function () { return follow(j.redirect); });
		});
	}

	function finish() {
		lock(false);
		var m = middle();
		if (refocus && m) {
			var target = $("form[data-fight] [type=submit]", m) || $("a[href]", m);
			if (target) target.focus({ preventScroll: true });
		}
		refocus = false;
	}

	// sends a request and plays its answer; fallback: the same without JavaScript
	function start(sent, fallback) {
		var m = middle();
		refocus = !!(m && document.activeElement && m.contains(document.activeElement));
		lock(true);
		var answered = false;
		sent.then(function (j) {
			answered = true;
			return handle(j);
		}).then(finish, function (err) {
			if (window.console) console.warn(err);
			lock(false);
			if (answered) location.reload(); else fallback();
		});
	}

	function submitNative(form, button) {
		lock(false);
		if (button && button.name) {
			var h = el("input");
			h.type = "hidden";
			h.name = button.name;
			h.value = button.value;
			form.appendChild(h);
		}
		HTMLFormElement.prototype.submit.call(form);
	}

	// ---- wiring

	document.addEventListener("submit", function (ev) {
		var form = ev.target;
		if (ev.defaultPrevented || !form.hasAttribute || !form.hasAttribute("data-fight")) return;
		ev.preventDefault();
		if (busy) return;
		var button = ev.submitter || (lastButton && lastButton.form === form ? lastButton : null);
		var data = new URLSearchParams(new FormData(form));
		if (button && button.name) data.append(button.name, button.value);
		start(request(form.getAttribute("action") || location.pathname, data, form), function () {
			submitNative(form, button);
		});
	});

	document.addEventListener("click", function (ev) {
		var m = middle();
		var inside = m && m.contains(ev.target);
		if (busy) {
			if (inside) {
				skip();
				if (closest(ev.target, "a[href]")) ev.preventDefault();   // links wait for the round
			}
			return;
		}
		var button = closest(ev.target, "form[data-fight] [type=submit]");
		if (button) lastButton = button;
		var a = closest(ev.target, "a[href]");
		if (!a || !inside || ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
		if (a.target && a.target !== "_self") return;
		var page = fightPage(a.href);
		if (!page) return;
		ev.preventDefault();
		start(request(page), function () { location.assign(page); });
	});

	document.addEventListener("keydown", function (ev) {
		if (!busy || ev.ctrlKey || ev.metaKey || ev.altKey) return;
		if (closest(ev.target, "input, textarea, select, [contenteditable]")) return;   // typing (the chat)
		skip();
	});

	body.classList.add("fight-js");
	enhance(document);
})();
