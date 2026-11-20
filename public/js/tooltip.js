// tooltip.js :: tooltips for any element with data-tip (docs/APP.md "Tooltips").
// Content: the trigger's <template class="tip"> child (rich HTML, rendered and escaped by
// the server), else data-tip="plain text", else its title (moved to data-tip-title so the
// browser's own tooltip doesn't show too). One shared box (#dk-tooltip, role=tooltip),
// placed by place() below: the preferred side (data-tip-side, default top), else the first
// other side with room, clamped into the viewport. Hover (after a short delay, at once
// when moving between triggers), keyboard focus, or a long press on touch screens show it;
// leaving, blur, Escape, or the trigger scrolling away or leaving the page hide it. Events
// are delegated to the document, so content swapped in later needs nothing.
(function () {
	"use strict";

	var MARGIN = 8;      // from the viewport's edges
	var GAP = 8;         // between the trigger and the box (the arrow sits in it)
	var ARROW_EDGE = 10; // the arrow stays this far from the box's corners
	var MAX_WIDTH = 280;
	var DELAY = 120;     // hover delay (ms)
	var PRESS = 400;     // long press (ms)
	var ORDER = {
		top: ["top", "bottom", "right", "left"], bottom: ["bottom", "top", "right", "left"],
		left: ["left", "right", "top", "bottom"], right: ["right", "left", "top", "bottom"],
	};

	function clamp(v, lo, hi) { return hi < lo ? lo : Math.min(Math.max(v, lo), hi); }

	// Where the box goes. t: the trigger's rect { left, top, right, bottom } and tip: the
	// box's { width, height }, both in viewport pixels; vw, vh: the viewport. The first side
	// in ORDER[side] with room for the box wins, else the one that lacks the least; then the
	// box is clamped MARGIN inside the viewport. Returns { side, x, y, arrow } (arrow: the
	// arrow's offset along the box's edge, pointing at the trigger's centre). Pure.
	function place(t, tip, vw, vh, side) {
		var order = ORDER[side] || ORDER.top;
		var room = {
			top: t.top - GAP - MARGIN, bottom: vh - t.bottom - GAP - MARGIN,
			left: t.left - GAP - MARGIN, right: vw - t.right - GAP - MARGIN,
		};
		var need = { top: tip.height, bottom: tip.height, left: tip.width, right: tip.width };
		var pick = null, best = order[0];
		for (var i = 0; i < order.length; i++) {
			var s = order[i];
			if (room[s] >= need[s]) { pick = s; break; }
			if (room[s] - need[s] > room[best] - need[best]) best = s;
		}
		side = pick || best;
		var cx = (t.left + t.right) / 2, cy = (t.top + t.bottom) / 2, x, y;
		if (side === "top" || side === "bottom") {
			x = cx - tip.width / 2;
			y = side === "top" ? t.top - GAP - tip.height : t.bottom + GAP;
		} else {
			y = cy - tip.height / 2;
			x = side === "left" ? t.left - GAP - tip.width : t.right + GAP;
		}
		x = clamp(x, MARGIN, vw - MARGIN - tip.width);
		y = clamp(y, MARGIN, vh - MARGIN - tip.height);
		var arrow = side === "top" || side === "bottom" ?
			clamp(cx - x, ARROW_EDGE, tip.width - ARROW_EDGE) : clamp(cy - y, ARROW_EDGE, tip.height - ARROW_EDGE);
		return { side: side, x: Math.round(x), y: Math.round(y), arrow: Math.round(arrow) };
	}

	if (typeof module === "object" && module.exports) module.exports = { place: place, MARGIN: MARGIN, GAP: GAP };
	if (typeof document === "undefined") return;

	var ID = "dk-tooltip";
	var box = null, body = null, arrowEl = null;
	var current = null, anchor = null, by = null; // the trigger, the element described, how it opened
	var showTimer = 0, pressTimer = 0, press = null, raf = 0, observer = null, lastHide = 0, swallow = false;

	function triggerOf(node) {
		var el = node && (node.nodeType === 1 ? node : node.parentElement);
		return el && el.closest ? el.closest("[data-tip]") : null;
	}

	// title -> data-tip-title, on the trigger and inside it: no native tooltip on top of ours
	function strip(el) {
		var list = [el].concat([].slice.call(el.querySelectorAll("[title]")));
		list.forEach(function (n) {
			if (!n.hasAttribute("title")) return;
			if (!n.hasAttribute("data-tip-title")) n.setAttribute("data-tip-title", n.getAttribute("title"));
			n.removeAttribute("title");
		});
	}

	// Fills the box with the trigger's content; false when it has none.
	function fill(el) {
		if (!box) {
			box = document.createElement("div");
			box.id = ID; box.className = "dk-tip"; box.hidden = true;
			box.setAttribute("data-client", "");   // the live client's morph leaves it alone
			box.setAttribute("role", "tooltip");
			box.appendChild(body = document.createElement("div"));
			box.appendChild(arrowEl = document.createElement("div"));
			arrowEl.className = "dk-tip-arrow";
			document.body.appendChild(box);
		}
		body.textContent = "";
		for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
			if (c.tagName === "TEMPLATE" && c.classList.contains("tip")) {
				body.appendChild(c.content.cloneNode(true));
				return body.firstChild !== null;
			}
		}
		var t = el.getAttribute("data-tip") || (el.querySelector("[data-tip-title]") || el).getAttribute("data-tip-title");
		body.textContent = t || "";
		return !!t;
	}

	function describe(on) {
		if (!anchor) return;
		var ids = (anchor.getAttribute("aria-describedby") || "").split(/\s+/).filter(function (x) { return x && x !== ID; });
		if (on) ids.push(ID);
		if (ids.length) anchor.setAttribute("aria-describedby", ids.join(" "));
		else anchor.removeAttribute("aria-describedby");
	}

	function listen(on) {
		var m = on ? "addEventListener" : "removeEventListener";
		window[m]("scroll", schedule, true);
		window[m]("resize", schedule);
		if (observer) observer.disconnect();
		observer = on && window.MutationObserver ? new MutationObserver(schedule) : null;
		if (observer) observer.observe(document.body, { childList: true, subtree: true });
	}

	function show(el, focused, how) {
		clearTimeout(showTimer);
		if (el === current) { if (by === "hover") by = how; return; }
		strip(el);
		var shown = current !== null;
		if (shown) describe(false);
		if (!fill(el)) { hide(); return; }
		current = el; anchor = focused || el; by = how;
		describe(true);
		box.hidden = false;
		if (!shown) listen(true);
		position();
		if (current && shown) box.classList.add("dk-tip-on");
		else requestAnimationFrame(function () { if (current) box.classList.add("dk-tip-on"); });
	}

	function hide() {
		clearTimeout(showTimer);
		if (!current) return;
		describe(false);
		current = anchor = by = null;
		box.classList.remove("dk-tip-on");
		box.hidden = true;
		lastHide = Date.now();
		listen(false);
	}

	function schedule() { if (!raf) raf = requestAnimationFrame(position); }

	// Whether any of rect r shows: not clipped away by the viewport or a scrolling ancestor.
	function visible(el, r, vw, vh) {
		var l = Math.max(r.left, 0), t = Math.max(r.top, 0), rt = Math.min(r.right, vw), b = Math.min(r.bottom, vh);
		for (var p = el.parentElement; p && p !== document.body && rt > l && b > t; p = p.parentElement) {
			var cs = getComputedStyle(p);
			if (cs.overflowX === "visible" && cs.overflowY === "visible") continue;
			var c = p.getBoundingClientRect();
			l = Math.max(l, c.left); t = Math.max(t, c.top); rt = Math.min(rt, c.right); b = Math.min(b, c.bottom);
		}
		return rt > l && b > t;
	}

	function position() {
		raf = 0;
		if (!current) return;
		var r = current.getBoundingClientRect();
		var vw = document.documentElement.clientWidth, vh = document.documentElement.clientHeight;
		if (!current.isConnected || (r.width === 0 && r.height === 0) || !visible(current, r, vw, vh)) { hide(); return; }
		box.style.maxWidth = Math.max(Math.min(MAX_WIDTH, vw - 2 * MARGIN), 0) + "px";
		box.style.left = box.style.top = "0px";   // measured where nothing squeezes it
		var p = place(r, { width: box.offsetWidth, height: box.offsetHeight }, vw, vh,
			current.getAttribute("data-tip-side") || "top");
		box.setAttribute("data-side", p.side);
		box.style.left = p.x + "px";
		box.style.top = p.y + "px";
		var across = p.side === "top" || p.side === "bottom";
		arrowEl.style.left = across ? p.arrow + "px" : "";
		arrowEl.style.top = across ? "" : p.arrow + "px";
	}

	function on(type, fn, capture) { document.addEventListener(type, fn, !!capture); }
	on("pointerover", function (ev) {
		var el = triggerOf(ev.target);
		if (ev.pointerType === "touch" || !el || el === current) return;
		strip(el);
		clearTimeout(showTimer);
		if (current || Date.now() - lastHide < 300) show(el, null, "hover");
		else showTimer = setTimeout(function () { show(el, null, "hover"); }, DELAY);
	});
	on("pointerout", function (ev) {
		var el = triggerOf(ev.target);
		if (ev.pointerType === "touch" || !el || (ev.relatedTarget && el.contains(ev.relatedTarget))) return;
		clearTimeout(showTimer);
		if (el === current && by === "hover") hide();
	});
	on("focusin", function (ev) {
		var el = triggerOf(ev.target), keyboard = true;
		try { keyboard = ev.target.matches(":focus-visible"); } catch (e) { /* older browsers: show */ }
		if (el && keyboard) show(el, ev.target, "focus");
	});
	on("focusout", function (ev) {
		var el = triggerOf(ev.target);
		if (el && el === current && by !== "hover" && !(ev.relatedTarget && el.contains(ev.relatedTarget))) hide();
	});
	on("keydown", function (ev) { if (current && (ev.key === "Escape" || ev.key === "Esc")) hide(); });

	// touch: a long press shows the tip without pressing the button; a tap still clicks
	function cancelPress() { clearTimeout(pressTimer); press = null; }
	on("pointerdown", function (ev) {
		swallow = false;
		cancelPress();
		if (current && by !== "focus") hide();
		var el = triggerOf(ev.target);
		if (ev.pointerType !== "touch" || !el) return;
		press = { x: ev.clientX, y: ev.clientY };
		pressTimer = setTimeout(function () { press = null; swallow = true; show(el, null, "press"); }, PRESS);
	}, true);
	on("pointermove", function (ev) {
		if (press && Math.abs(ev.clientX - press.x) + Math.abs(ev.clientY - press.y) > 10) cancelPress();
	}, true);
	on("pointerup", cancelPress, true);
	on("pointercancel", cancelPress, true);
	on("click", function (ev) { if (swallow) { swallow = false; ev.preventDefault(); ev.stopPropagation(); } }, true);
	on("contextmenu", function (ev) { if (by === "press" || press) ev.preventDefault(); }, true);

	[].forEach.call(document.querySelectorAll("[data-tip]"), strip);

	// for other scripts (and tests): open a trigger's tip as if focused; close it
	window.dkTip = { place: place, show: function (el) { if (el) show(el, el, "api"); }, hide: hide };
})();
