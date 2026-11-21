// scene.js :: smooth changes of page (docs/APP.md "Scenes"). Any action of the player's
// that changes the middle column (a link, a form: the inn, the shops, the inventory...)
// fades it out and the new one in, quickly; fight rounds (fight.js plays them), refreshes
// and back/forward don't. And the page fades through a caption when the player's state
// changes: an answer's `scene` event (lib/scene.lua: { kind, title, detail }), played by
// the live client (client.js) after the round's events (fight.js) and before the page's
// regions apply. The middle column fades out while the caption (the title, a line of
// details) fades in over it; the new page goes in under it, the caption lingers, then it
// fades out and the new page in. A scene whose page is drawn like the caption (`page`: the
// victory page) has no caption: the page fades in slowly and stays. A click or a key cuts
// it short; with prefers-reduced-motion the new page
// just shows. Without the live client (no JavaScript, a page load) there is nothing to
// play: the new page shows as it is. Text from the server goes in with textContent only.
(function () {
	"use strict";
	if (typeof document === "undefined" || !window.DK || !window.Promise || !window.JSON) return;

	// ms: a scene's fade out, caption alone, fade in (1 s in all); the victory page's fade in;
	// a page's fade out (its fade in: dk.css); LOST: no page came, clean up
	var OUT = 200, HOLD = 550, IN = 250, SLOW = 600, FADE = 150, LOST = 4000;
	var LONGER = { town: 250, explore: 250 };   // these captions linger a little longer
	var motion = !(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
	var root = document.documentElement;
	var card = null;       // the caption on screen
	var pending = false;   // the caption (or a page scene) waits for its page
	var pageScene = false; // the page is the caption: it fades in itself
	var fading = false;    // a page change faded the middle column out
	var hold = HOLD;       // how long the caption on screen lingers
	var wake = null, timer = 0, lost = 0;

	function wait(ms) {
		return new Promise(function (resolve) {
			wake = function () { clearTimeout(timer); wake = null; resolve(); };
			timer = setTimeout(wake, ms);
		});
	}
	function cut() { if (wake) wake(); }
	function main() { return document.querySelector('[data-r="main"]') || document.querySelector("[data-main]"); }

	// The caption goes, the page shows (at once: a newer scene, or no page came).
	function clear() {
		clearTimeout(lost);
		pending = pageScene = fading = false;
		root.classList.remove("dk-scene-out", "dk-scene-slow", "dk-fade-out");
		if (card && card.parentNode) card.parentNode.removeChild(card);
		card = null;
		cut();
	}

	function play(data) {
		var s;
		try { s = JSON.parse(data); } catch (e) { return; }
		var m = main();
		if (!motion || !s || !s.title || !m) return;
		clear();
		if (s.page) {
			root.classList.add("dk-scene-out");
			pending = pageScene = true;
			lost = setTimeout(clear, LOST);
			return wait(OUT);
		}
		hold = HOLD + (LONGER[s.kind] || 0);
		var c = card = document.createElement("div");
		c.className = "dk-scene dk-scene-" + String(s.kind || "").replace(/[^a-z]/g, "");
		c.setAttribute("data-client", "");   // the live client's morph leaves it alone
		c.setAttribute("role", "status");
		var title = document.createElement("div");
		title.className = "dk-scene-title";
		title.textContent = s.title;
		c.appendChild(title);
		if (s.detail) {
			var detail = document.createElement("div");
			detail.className = "dk-scene-detail";
			detail.textContent = s.detail;
			c.appendChild(detail);
		}
		// over the middle column, a little above the middle of the window
		var r = m.getBoundingClientRect();
		c.style.left = Math.round(r.left) + "px";
		c.style.width = Math.round(r.width) + "px";
		document.body.appendChild(c);
		root.classList.add("dk-scene-out");
		requestAnimationFrame(function () { c.classList.add("dk-scene-on"); });
		pending = true;
		lost = setTimeout(clear, LOST);
		return wait(OUT);
	}

	// Before an answer applies: one that changes the middle column after a link or form of
	// the player's fades it out (unless a scene does, or it is the next round of a fight or
	// the hotbar saved).
	function before(info) {
		if (!motion || pending || !info.user) return;
		if (info.regions.indexOf("main") < 0 && info.regions.indexOf("root") < 0) return;
		if (/^\/fight(\?|$)/.test(info.from) && /^\/fight(\?|$)/.test(info.to)) return;
		if (/^\/hotbar(\?|$)/.test(info.from) && /^\/hotbar(\?|$)/.test(info.to)) return;
		clear();
		fading = true;
		root.classList.add("dk-fade-out");
		lost = setTimeout(clear, LOST);
		return wait(FADE);
	}

	function applied() {
		if (fading) {
			fading = false;
			clearTimeout(lost);
			root.classList.remove("dk-fade-out");
			return;
		}
		if (!pending) return;
		pending = false;
		clearTimeout(lost);
		if (pageScene) {
			pageScene = false;
			root.classList.add("dk-scene-slow");
			root.classList.remove("dk-scene-out");
			setTimeout(function () { if (!pending) root.classList.remove("dk-scene-slow"); }, SLOW);
			return;
		}
		var c = card;
		wait(hold).then(function () {
			if (card !== c) return;   // a newer scene took over
			root.classList.remove("dk-scene-out");
			c.classList.remove("dk-scene-on");
			setTimeout(function () {
				if (c.parentNode) c.parentNode.removeChild(c);
				if (card === c) card = null;
			}, IN);
		});
	}

	document.addEventListener("pointerdown", function () { if (card) cut(); }, true);
	document.addEventListener("keydown", function (ev) {
		if (card && !ev.ctrlKey && !ev.metaKey && !ev.altKey) cut();
	}, true);

	window.DK.on("events:scene", play);
	window.DK.on("before", before);
	window.DK.on("applied", applied);
})();
