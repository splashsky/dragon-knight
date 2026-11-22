// tests/js/test_client.js :: the live client's pure parts (public/js/client.js): the wire
// format reader, the hash map, which addresses it fetches. tests/run.sh runs it with node
// when there is one, fed on stdin after client.js (which then sets module.exports); `node
// tests/js/test_client.js` works too. Prints "ok N", or the failures and exits non-zero.
var c = typeof module === "object" && module.exports && module.exports.decode ? module.exports :
	require(require("path").join(__dirname, "..", "..", "public", "js", "client.js"));

var fails = 0, count = 0;
function check(name, cond, got) {
	count++;
	if (!cond) { fails++; console.log("FAIL " + name + ": " + JSON.stringify(got)); }
}
function throws(name, fn) {
	try { fn(); check(name, false, "no error"); } catch (e) { check(name, true); }
}
var enc = new TextEncoder(), dec = new TextDecoder();
function text(b) { return dec.decode(b); }
function bytes(s) { return enc.encode(s); }

// frames: lengths are bytes, payloads raw (newlines, multibyte characters, empty ones)
var body = "DK1\ntitle 9\nÜnïcode\nurl 1\n/\nregion main 11\n<p>a\nb</p>\n\nevents fight 2\n[]\ngo 0\n\nnew a b 3\nxyz\n";
var f = c.decode(bytes(body), text);
check("frame count", f.length === 6, f.length);
check("title (bytes, not characters)", f[0].op === "title" && f[0].payload === "Ünïcode", f[0]);
check("region payload with newlines", f[2].op === "region" && f[2].args[0] === "main" && f[2].payload === "<p>a\nb</p>\n", f[2]);
check("events kind", f[3].op === "events" && f[3].args[0] === "fight" && f[3].payload === "[]", f[3]);
check("empty payload", f[4].op === "go" && f[4].payload === "", f[4]);
check("unknown ops are read too", f[5].op === "new" && f[5].args.join(",") === "a,b" && f[5].payload === "xyz", f[5]);
check("just the header", c.decode(bytes("DK1\n"), text).length === 0);
throws("no header", function () { c.decode(bytes("<!doctype html>"), text); });
throws("short frame", function () { c.decode(bytes("DK1\nregion main 50\nshort\n"), text); });
throws("no newline after the payload", function () { c.decode(bytes("DK1\ntitle 1\nab"), text); });
throws("bad length", function () { c.decode(bytes("DK1\ntitle x\n\n"), text); });

// the hash map
var have = c.mergeHashes({}, "head=abc root=0123456789ab loc=ff");
check("parse", have.head === "abc" && have.root === "0123456789ab" && have.loc === "ff", have);
c.mergeHashes(have, "loc=ee main=12 head=-");
check("merge: change, add, remove", have.loc === "ee" && have.main === "12" && !("head" in have), have);
c.mergeHashes(have, "junk =1 bad=XYZ");
check("junk ignored", !("junk" in have) && !("bad" in have) && !("" in have), have);
check("format", c.formatHashes({ a: "1", b: "2" }) === "a=1 b=2");
check("nothing", c.mergeHashes({}, null) && Object.keys(c.mergeHashes({}, "")).length === 0);

// which addresses go through the client
var B = "http://dk.test/inn";
check("a path", c.livePath("/shop", B, "/inn") === "/shop");
check("relative, with a query", c.livePath("forum/3?start=15", "http://dk.test/forum/", "/forum/") === "/forum/forum/3?start=15");
check("the same page with a hash: native", c.livePath("/inn#x", B, "/inn") === null);
check("another page with a hash", c.livePath("/shop#x", B, "/inn") === "/shop");
check("a hash, the page unknown (forms)", c.livePath("/inn#x", B, null) === "/inn");
check("other site", c.livePath("http://other.test/", B, "/inn") === null);
check("other port", c.livePath("http://dk.test:8080/", B, "/inn") === null);
check("static files", c.livePath("/static/images/world.svg", B, "/inn") === null);
check("the event stream", c.livePath("/live", B, "/inn") === null && c.livePath("/live/state", B, "/inn") === null);
check("not /livestock", c.livePath("/livestock", B, "/inn") === "/livestock");
check("javascript:", c.livePath("javascript:alert(1)", B, "/inn") === null);
check("mailto:", c.livePath("mailto:a@b", B, "/inn") === null);

console.log(fails ? fails + " of " + count + " failed" : "ok " + count);
if (fails && typeof process === "object") process.exit(1);
