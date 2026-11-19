// dk.js :: popup links. <a href="/map" data-popup="520x520"> opens a small window
// (legacy opencharpopup/openmappopup); without JS it is a normal link.
document.addEventListener("click", function (ev) {
	var a = ev.target.closest && ev.target.closest("a[data-popup]");
	if (!a) return;
	var size = a.getAttribute("data-popup").split("x");
	var w = window.open(a.href, "", "width=" + size[0] + ",height=" + size[1] + ",scrollbars");
	if (w) ev.preventDefault();
});
