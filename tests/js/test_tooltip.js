// tests/js/test_tooltip.js :: the tooltip placement (public/js/tooltip.js place()), with no
// DOM: rects in, side and position out. tests/run.sh runs it with node when there is one
// (Linux node, or node.exe from Windows), fed on stdin after tooltip.js (which then sets
// module.exports); `node tests/js/test_tooltip.js` works too. Prints "ok N", or the failures
// and exits non-zero.
var tip = typeof module === "object" && module.exports && module.exports.place ? module.exports :
	require(require("path").join(__dirname, "..", "..", "public", "js", "tooltip.js"));
var place = tip.place, M = tip.MARGIN, G = tip.GAP;

var fails = 0, count = 0;
function check(name, cond, got) {
	count++;
	if (!cond) { fails++; console.log("FAIL " + name + ": " + JSON.stringify(got)); }
}
function rect(x, y, w, h) { return { left: x, top: y, right: x + w, bottom: y + h }; }
// the box is inside the viewport (MARGIN from every edge) when it fits at all
function inside(p, tw, th, vw, vh) {
	return p.x >= M && p.y >= M && p.x + tw <= vw - M && p.y + th <= vh - M;
}
function overlaps(p, tw, th, t) {
	return p.x < t.right && p.x + tw > t.left && p.y < t.bottom && p.y + th > t.top;
}

var VW = 1280, VH = 800, TW = 240, TH = 120;

// the middle of the page: the preferred side, centred, arrow at the centre
var mid = rect(600, 400, 44, 44);
var p = place(mid, { width: TW, height: TH }, VW, VH, "top");
check("middle top side", p.side === "top", p);
check("middle top x centred", p.x === Math.round(622 - TW / 2), p);
check("middle top y above", p.y === 400 - G - TH, p);
check("middle top arrow centre", p.arrow === TW / 2, p);
["bottom", "left", "right"].forEach(function (s) {
	var q = place(mid, { width: TW, height: TH }, VW, VH, s);
	check("middle keeps " + s, q.side === s, q);
	check("middle " + s + " inside", inside(q, TW, TH, VW, VH), q);
	check("middle " + s + " clear of the trigger", !overlaps(q, TW, TH, mid), q);
});
check("unknown side means top", place(mid, { width: TW, height: TH }, VW, VH, "nope").side === "top");
var below = place(mid, { width: TW, height: TH }, VW, VH, "bottom");
check("bottom y", below.y === 444 + G, below);
var left = place(mid, { width: TW, height: TH }, VW, VH, "left");
check("left x", left.x === 600 - G - TW && left.arrow === TH / 2, left);

// each edge: top flips to bottom, bottom to top, left to right, right to left
var edges = [
	{ name: "top edge", t: rect(600, 2, 44, 44), side: "top", want: "bottom" },
	{ name: "bottom edge", t: rect(600, VH - 46, 44, 44), side: "bottom", want: "top" },
	{ name: "left edge", t: rect(2, 400, 44, 44), side: "left", want: "right" },
	{ name: "right edge", t: rect(VW - 46, 400, 44, 44), side: "right", want: "left" },
];
edges.forEach(function (e) {
	var q = place(e.t, { width: TW, height: TH }, VW, VH, e.side);
	check(e.name + " flips", q.side === e.want, q);
	check(e.name + " inside", inside(q, TW, TH, VW, VH), q);
	check(e.name + " clear of the trigger", !overlaps(q, TW, TH, e.t), q);
});

// top at the right edge (Fast Spells): stays on top, clamped left, arrow still on the trigger
var fast = rect(VW - 40, 500, 34, 34);
p = place(fast, { width: 280, height: 150 }, VW, VH, "top");
check("right edge top side", p.side === "top", p);
check("right edge clamped", p.x === VW - M - 280, p);
check("right edge arrow on the trigger", p.x + p.arrow >= fast.left && p.x + p.arrow <= fast.right, p);
// left side at the right edge of the right column: room on the left
p = place(fast, { width: 280, height: 150 }, VW, VH, "left");
check("right column left side", p.side === "left" && p.x + 280 <= fast.left - G + 0.5, p);

// corners: always inside, never on the trigger, the arrow within the box
[
	["top-left", rect(0, 0, 30, 30)], ["top-right", rect(VW - 30, 0, 30, 30)],
	["bottom-left", rect(0, VH - 30, 30, 30)], ["bottom-right", rect(VW - 30, VH - 30, 30, 30)],
].forEach(function (c) {
	["top", "bottom", "left", "right"].forEach(function (s) {
		var q = place(c[1], { width: TW, height: TH }, VW, VH, s);
		check(c[0] + " " + s + " inside", inside(q, TW, TH, VW, VH), q);
		check(c[0] + " " + s + " clear", !overlaps(q, TW, TH, c[1]), q);
		check(c[0] + " " + s + " arrow", q.arrow >= 10 && q.arrow <= (q.side === "top" || q.side === "bottom" ? TW : TH) - 10, q);
	});
});
p = place(rect(0, VH - 30, 30, 30), { width: TW, height: TH }, VW, VH, "top");
check("bottom-left: top, arrow clamped to the corner", p.side === "top" && p.x === M && p.arrow === 10, p);

// a trigger partly off screen: the box stays inside
p = place(rect(-20, 300, 44, 44), { width: TW, height: TH }, VW, VH, "top");
check("off the left edge", p.x === M && p.side === "top", p);
p = place(rect(600, -30, 44, 44), { width: TW, height: TH }, VW, VH, "top");
check("off the top edge: below", p.side === "bottom" && p.y === 14 + G, p);

// a tiny viewport (320x200) and a tall box: the side that lacks the least, pinned at the margin
var small = rect(140, 90, 40, 20);
p = place(small, { width: 300, height: 180 }, 320, 200, "top");
check("tiny viewport: no side fits, top wins a tie-break by order", ["top", "bottom", "left", "right"].indexOf(p.side) >= 0, p);
check("tiny viewport x centred within the margins", p.x === 10 && p.x >= M && p.x + 300 <= 320 - M, p);
check("tiny viewport y pinned", p.y === M, p);
p = place(rect(140, 150, 40, 20), { width: 300, height: 100 }, 320, 200, "bottom");
check("tiny viewport flips to top", p.side === "top" && p.y === 150 - G - 100, p);

// a huge box (wider and taller than the viewport): pinned at the top-left margin
p = place(mid, { width: 2000, height: 2000 }, VW, VH, "top");
check("huge box pinned", p.x === M && p.y === M, p);
check("huge box arrow inside", p.arrow >= 10 && p.arrow <= 2000 - 10, p);

// a wide box beside a trigger: left/right need its width
p = place(rect(100, 400, 44, 44), { width: 200, height: 60 }, VW, VH, "left");
check("no room on the left: right", p.side === "right" && p.x === 144 + G, p);
p = place(rect(100, 400, 44, 44), { width: 50, height: 60 }, VW, VH, "left");
check("room on the left", p.side === "left" && p.x === 100 - G - 50, p);

// the vertical arrow (left/right sides) follows the trigger's centre
p = place(rect(600, 20, 40, 40), { width: 200, height: 300 }, VW, VH, "right");
check("right side clamped down", p.side === "right" && p.y === M && p.arrow === 40 - M, p);

// exact fit counts as room
p = place(rect(600, M + G + 100, 40, 40), { width: 100, height: 100 }, VW, VH, "top");
check("exact fit", p.side === "top" && p.y === M, p);
p = place(rect(600, M + G + 99, 40, 40), { width: 100, height: 100 }, VW, VH, "top");
check("one pixel short", p.side === "bottom", p);

// integers out
p = place(rect(100.5, 200.25, 33.3, 33.3), { width: 101.7, height: 50.2 }, 1001, 701, "top");
check("rounded", p.x === Math.round(p.x) && p.y === Math.round(p.y) && p.arrow === Math.round(p.arrow), p);

if (fails) { console.log(fails + " of " + count + " checks failed"); process.exit(1); }
console.log("ok " + count);
