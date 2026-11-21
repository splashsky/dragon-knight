// dk.js :: popup links and the compass's arrow keys.
// Popups: <a href="/map" data-popup="520x520"> opens a small window (legacy
// opencharpopup/openmappopup); without JS it is a normal link.
document.addEventListener("click", function (ev) {
	var a = ev.target.closest && ev.target.closest("a[data-popup]");
	if (!a) return;
	var size = a.getAttribute("data-popup").split("x");
	var w = window.open(a.href, "", "width=" + size[0] + ",height=" + size[1] + ",scrollbars");
	if (w) ev.preventDefault();
});

// The arrow keys press the compass's buttons (layout/place.html: north, west, east,
// south), on a page that shows it, unless a field has the keyboard (typing, a list), a
// modifier key is held or a dialog is open (modal.js). A held key walks on only while the live client (client.js) is free:
// without it each press is a page load, and a held key would queue a pile of them.
(function () {
	var KEYS = { ArrowUp: "north", ArrowLeft: "west", ArrowRight: "east", ArrowDown: "south" };
	document.addEventListener("keydown", function (ev) {
		var dir = KEYS[ev.key];
		if (!dir || ev.defaultPrevented || ev.ctrlKey || ev.metaKey || ev.altKey || ev.shiftKey) return;
		var t = ev.target;
		if (t && t.closest && t.closest("input, textarea, select, [contenteditable], [role=listbox], [role=slider]")) return;
		var button = document.querySelector('form.compass button[name="' + dir + '"]');
		if (!button || document.querySelector("dialog[open]")) return;
		ev.preventDefault();   // (the page doesn't scroll instead)
		if (ev.repeat && !(window.DK && !window.DK.busy())) return;
		button.classList.add("compass-pressed");
		setTimeout(function () { button.classList.remove("compass-pressed"); }, 150);
		if (button.form.requestSubmit) button.form.requestSubmit(button); else button.click();
	});
})();
