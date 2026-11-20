// fight.js :: smooth fights (docs/APP.md "Fight events"). A fight round sent by the live
// client (client.js) comes back with the round's events (an `events fight` frame), which
// this script plays on the page being shown before the page's regions apply: a line every
// STEP ms, with the HP/MP bars and numbers, the statuses and the allies they change. Then
// the regions bring the page as the server renders it, so what stays on screen is what a
// page load shows. A click in the middle column, any key or "Skip" finishes the round at
// once; with prefers-reduced-motion there are no delays. The fight forms are disabled while
// a round plays, and the button that sent it gets the focus back after. The monsters' and
// allies' bars ([data-stat][data-max]) are drawn here (data-client: the live client's morph
// leaves them, and they are updated after each answer). Without the live client the fight
// forms are plain forms. Text from the server goes in with textContent only.
(function () {
	"use strict";
	var root = document.documentElement;
	if (!document.body || !window.Promise) return;

	var STEP = 400;
	var PARTS = { player: "fight-yourturn", allies: "fight-allyturn", enemies: "fight-monsterturn", ending: "fight-roundend" };
	var motion = !(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);

	var playing = false;    // a round is being played
	var skipping = false;   // the round plays to its end at once
	var wake = null;        // ends the current wait
	var refocus = false;    // the keyboard was in the middle column: focus the new form
	var pressed = null;     // name and value of the button that sent the round (refocused after)

	// ---- helpers

	function $(sel, r) { return (r || document).querySelector(sel); }
	function $$(sel, r) { return Array.prototype.slice.call((r || document).querySelectorAll(sel)); }
	function el(tag, cls, text) {
		var e = document.createElement(tag);
		if (cls) e.className = cls;
		if (text != null) e.textContent = text;
		return e;
	}
	function txt(s) { return document.createTextNode(s); }
	function remove(node) { if (node && node.parentNode) node.parentNode.removeChild(node); }
	function middle() { return $('[data-r="main"]') || $("[data-main]"); }
	function closest(node, sel) {
		var e = node && (node.nodeType === 1 ? node : node.parentElement);
		return e && e.closest ? e.closest(sel) : null;
	}

	function lock(on) {
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
		var b = $(".fight-meter", node);
		if (!b) {
			// the same bar as the Character panel's (dk.css .meter-track/.meter-fill/.bar-*)
			b = el("span", "meter-track fight-meter");
			b.setAttribute("aria-hidden", "true");
			b.setAttribute("data-client", "");   // the live client's morph leaves it
			b.appendChild(el("span", "meter-fill"));
			node.appendChild(b);
		}
		var p = pct(v, max);
		b.firstChild.className = "meter-fill bar-" + (node.getAttribute("data-stat") === "mp" ? "mp" : level(p));
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
		var value = $('[data-meter="' + kind + '"]');
		if (value) {
			if (max == null) max = Number(value.getAttribute("data-max"));
			else value.setAttribute("data-max", max);
		}
		var low = kind !== "tp" && max > 0 && v <= max / 5;
		if (value) {
			value.textContent = "";
			value.appendChild(el("b", null, String(v)));
			value.appendChild(txt("/" + max));
			value.classList.toggle("highlight", low);
			value.classList.toggle("blink", low);
		}
		var fill = $('[data-bar="' + kind + '"]');
		if (fill && max > 0) {
			var p = Math.ceil(v / max * 100);
			fill.style.width = Math.max(0, Math.min(100, p)) + "%";
			if (kind === "hp") fill.className = "meter-fill bar-" + level(p);
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
			var at = $(".fight-meter", node);
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

	// The round's events (JSON), played on the page on screen; the regions apply after.
	function playRound(data) {
		var events;
		try { events = JSON.parse(data); } catch (e) { return Promise.resolve(); }
		if (!Array.isArray(events) || !events.length) return Promise.resolve();
		playing = true;
		lock(true);
		return play(events).then(function () {
			// a moment to read the last blow before the page moves on (victory, escape)
			var last = events[events.length - 1];
			var said = events.some(function (e) { return e.text; });
			return wait(said && last && (last.type === "victory" || last.type === "escape") ? 2 * STEP : 0);
		}).then(function () { playing = false; lock(false); }, function (err) {
			playing = false;
			lock(false);
			throw err;
		});
	}

	// after an answer: the bars of the page now, and the focus back on the button used
	function applied() {
		enhance(document);
		var m = middle();
		if (refocus && m) {
			// the same button again (a spell's, say) if the new form has it enabled, else the first
			var same = pressed && $$("form[data-fight] [type=submit]", m).filter(function (b) {
				return !b.disabled && b.name === pressed.name && b.value === pressed.value;
			})[0];
			var target = same || $("form[data-fight] [type=submit]", m) || $("a[href]", m);
			if (target) target.focus({ preventScroll: true });
		}
		refocus = false;
		pressed = null;
	}

	// ---- wiring

	document.addEventListener("submit", function (ev) {
		var form = ev.target, m = middle();
		if (!form.hasAttribute || !form.hasAttribute("data-fight")) return;
		var button = ev.submitter;
		pressed = button && button.name ? { name: button.name, value: button.value } : null;
		refocus = !!(m && document.activeElement && m.contains(document.activeElement));
	});

	document.addEventListener("click", function (ev) {
		var m = middle();
		if (!playing || !m || !m.contains(ev.target)) return;
		skip();
		if (closest(ev.target, "a[href]")) ev.preventDefault();   // links wait for the round
	});

	document.addEventListener("keydown", function (ev) {
		if (!playing || ev.ctrlKey || ev.metaKey || ev.altKey) return;
		if (closest(ev.target, "input, textarea, select, [contenteditable]")) return;   // typing (the chat)
		skip();
	});

	if (window.DK) {
		window.DK.on("events:fight", playRound);
		window.DK.on("applied", applied);
	}
	root.classList.add("fight-js");
	enhance(document);
})();
