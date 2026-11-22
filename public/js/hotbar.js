// hotbar.js :: the fight's hotbar (docs/APP.md "Hotbar"). In a fight the number keys press
// the slots' buttons (fight/fight.html: [data-hotkey] 1 Attack ... 9 Guard, 0 Run; a locked turn's
// Continue for any of them), as a click would: the live client (client.js) sends the form
// and fight.js plays the round. Not while a field has the keyboard (the chat), a modifier
// is held, a dialog is open, the key repeats or a request runs; a disabled button (MP short,
// or the forms locked while a round plays) does nothing. On /hotbar (town/hotbar.html) the
// action tiles can be dragged onto the slots (a slot's list takes the action; where it was
// before gets the slot's old one), between slots (a swap) and back to the actions (the slot
// empties), and the form saves. html.dk-hotbar-js shows what needs this script (the fight's
// key badges, the drag hint). Without it the buttons are clicked and the lists picked.
(function () {
	"use strict";
	if (typeof document === "undefined" || !document.documentElement.classList) return;
	document.documentElement.classList.add("dk-hotbar-js");

	function closest(node, sel) {
		var e = node && (node.nodeType === 1 ? node : node.parentElement);
		return e && e.closest ? e.closest(sel) : null;
	}
	function submit(form, button) {
		if (form.requestSubmit) form.requestSubmit(button); else button.click();
	}

	// ---- the number keys in a fight

	document.addEventListener("keydown", function (ev) {
		if (!/^[0-9]$/.test(ev.key) || ev.defaultPrevented || ev.ctrlKey || ev.metaKey || ev.altKey) return;
		if (closest(ev.target, "input, textarea, select, [contenteditable]")) return;
		var form = document.querySelector("form[data-fight]");
		if (!form || document.querySelector("dialog[open]")) return;
		var button = form.querySelector('[name="continue"]') ||
			form.querySelector('[data-hotkey="' + ev.key + '"] button');
		if (!button) return;
		ev.preventDefault();
		if (ev.repeat || button.disabled || (window.DK && window.DK.busy())) return;
		button.classList.add("hotbar-pressed");
		setTimeout(function () { button.classList.remove("hotbar-pressed"); }, 150);
		submit(form, button);
	});

	// ---- dragging on /hotbar

	var dragged = null;   // { key, from (the slot's number, or null: the actions' list) }

	function page() { return document.querySelector("[data-hotbar-page]"); }
	function list(n) { return page().querySelector('select[name="slot' + n + '"]'); }
	function slotOf(node) { var li = closest(node, "[data-slot]"); return li ? li.getAttribute("data-slot") : null; }

	document.addEventListener("dragstart", function (ev) {
		var tile = closest(ev.target, "[data-hotbar-page] [draggable][data-key]");
		if (!tile) return;
		dragged = { key: tile.getAttribute("data-key"), from: slotOf(tile) };
		ev.dataTransfer.effectAllowed = "move";
		try { ev.dataTransfer.setData("text/plain", dragged.key); } catch (e) { /* old browsers */ }
		if (window.dkTip) window.dkTip.hide();
	});
	document.addEventListener("dragend", function () {
		dragged = null;
		Array.prototype.forEach.call(document.querySelectorAll(".hotbar-over"), function (e) { e.classList.remove("hotbar-over"); });
	});

	function target(ev) { return dragged && closest(ev.target, "[data-hotbar-page] [data-slot], [data-hotbar-actions]"); }
	document.addEventListener("dragover", function (ev) {
		var t = target(ev);
		if (!t) return;
		ev.preventDefault();
		ev.dataTransfer.dropEffect = "move";
		t.classList.add("hotbar-over");
	});
	document.addEventListener("dragleave", function (ev) {
		var t = target(ev);
		if (t && !t.contains(ev.relatedTarget)) t.classList.remove("hotbar-over");
	});
	document.addEventListener("drop", function (ev) {
		var t = target(ev);
		if (!t) return;
		ev.preventDefault();
		var d = dragged, to = t.getAttribute("data-slot");
		dragged = null;
		if (to === d.from) return;
		if (to === null) {
			if (d.from === null) return;
			list(d.from).value = "";   // back to the actions: the slot empties
		} else {
			var before = list(to).value;
			// where the action was (dragged from a slot, or picked in another list) gets the
			// target's old one: a swap
			var from = d.from;
			if (from === null) {
				Array.prototype.forEach.call(page().querySelectorAll("select[name^=slot]"), function (s) {
					if (s.value === d.key) from = s.name.slice(4);
				});
			}
			list(to).value = d.key;
			if (from !== null && from !== to) list(from).value = before;
		}
		var form = list(2).form;
		submit(form, form.querySelector('[name="save"]'));
	});
})();
