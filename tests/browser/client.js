// tests/browser/client.js :: the live client (public/js/client.js) in a real browser,
// driven over the DevTools protocol with node's WebSocket (no dependencies). tests/run.sh
// runs it when node and a Chromium browser (Chrome, Edge, Chromium; BROWSER=path picks one)
// are found, with: node - BASE USER PASS (fed on stdin, like the JS unit tests). Prints
// "ok N" or the failures and exits non-zero.
"use strict";
var cp = require("child_process"), fs = require("fs"), os = require("os"), path = require("path");

var BASE = process.argv[2], USER = process.argv[3], PASS = process.argv[4];
var fails = 0, count = 0, section = "";
function check(name, cond, got) {
	count++;
	if (!cond) { fails++; console.log("FAIL [" + section + "] " + name + (got !== undefined ? ": " + JSON.stringify(got) : "")); }
}

function findBrowser() {
	var list = [process.env.BROWSER,
		"C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
		"C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
		"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
		"/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome",
		"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"];
	for (var i = 0; i < list.length; i++) if (list[i] && fs.existsSync(list[i])) return list[i];
	return null;
}

function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

async function main() {
	var exe = findBrowser();
	if (!exe) { console.log("skip: no browser"); return; }
	var dir = fs.mkdtempSync(path.join(os.tmpdir(), "dk-browser-"));
	var port = 9300 + Math.floor(Math.random() * 600);
	var proc = cp.spawn(exe, ["--headless=new", "--remote-debugging-port=" + port, "--user-data-dir=" + dir,
		"--no-first-run", "--no-default-browser-check", "--disable-extensions", "--window-size=1280,900", "about:blank"],
		{ stdio: "ignore" });
	try {
		var info = null;
		for (var i = 0; i < 100 && !info; i++) {
			try { info = await (await fetch("http://127.0.0.1:" + port + "/json/list")).json(); } catch (e) { await sleep(100); }
		}
		var pageTarget = info.filter(function (t) { return t.type === "page"; })[0];
		await run(pageTarget.webSocketDebuggerUrl, port);
	} finally {
		proc.kill();
		await sleep(300);
		try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { /* still locked */ }
	}
}

// A DevTools session with one tab: send(method, params), js(expr) (its value; promises
// awaited), until(expr, ms), nav(path) (a normal page load), loads (page loads so far).
async function session(wsUrl) {
	var ws = new WebSocket(wsUrl), id = 0, waiting = {}, t = { loads: 0, ws: ws, log: [] };
	await new Promise(function (r, j) { ws.onopen = r; ws.onerror = j; });
	ws.onmessage = function (m) {
		var d = JSON.parse(m.data);
		if (d.id && waiting[d.id]) { waiting[d.id](d); delete waiting[d.id]; }
		if (d.method === "Page.loadEventFired") t.loads++;
		if (d.method === "Runtime.consoleAPICalled" && /^(warning|error)$/.test(d.params.type)) {
			t.log.push(d.params.type + ": " + d.params.args.map(function (a) { return a.value || a.description; }).join(" "));
		}
		if (d.method === "Runtime.exceptionThrown") t.log.push("exception: " + JSON.stringify(d.params.exceptionDetails.exception && d.params.exceptionDetails.exception.description || d.params.exceptionDetails.text));
	};
	t.send = function (method, params) {
		return new Promise(function (r) { var n = ++id; waiting[n] = r; ws.send(JSON.stringify({ id: n, method: method, params: params || {} })); });
	};
	t.js = async function (expr) {
		var r = await t.send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
		if (r.result && r.result.exceptionDetails) throw new Error(expr + ": " + JSON.stringify(r.result.exceptionDetails));
		return r.result && r.result.result ? r.result.result.value : undefined;
	};
	t.until = async function (expr, ms) {
		var end = Date.now() + (ms || 5000);
		while (Date.now() < end) {
			try { if (await t.js(expr)) return true; } catch (e) { /* page navigating */ }
			await sleep(50);
		}
		return false;
	};
	t.nav = async function (url) {
		var before = t.loads;
		await t.send("Page.navigate", { url: BASE + url });
		await t.until("document.readyState === 'complete'");
		for (var i = 0; i < 100 && t.loads === before; i++) await sleep(50);
	};
	await t.send("Page.enable");
	await t.send("Runtime.enable");
	return t;
}

async function run(wsUrl, port) {
	var tab = await session(wsUrl);
	var send = tab.send, js = tab.js, until = tab.until, nav = tab.nav, ws = tab.ws;

	section = "login";
	await nav("/login");
	check("no live client on a page without data-h? (it has one)", await js("document.documentElement.hasAttribute('data-h')"));
	await js("document.querySelector('[name=username]').value = " + JSON.stringify(USER) +
		"; document.querySelector('[name=password]').value = " + JSON.stringify(PASS) + "; window.__dk = 1;" +
		"document.querySelector('form[action=\"/login\"]').requestSubmit()");
	check("logged in, in town", await until("document.title === 'In Town'"), await js("document.title"));
	check("without a page load", await js("window.__dk === 1"));
	check("the address", await js("location.pathname === '/'"), await js("location.pathname"));
	// live.js starts its stream when the page becomes a player's (<body data-live>)
	check("the event stream starts", await until("!!localStorage.getItem('dk-live-leader')"));

	section = "navigation";
	var loadsBefore = tab.loads;
	await js("document.querySelector('a[href=\"/inventory\"]').click()");
	check("inventory page", await until("location.pathname === '/inventory' && document.title === 'Inventory'"), await js("document.title"));
	check("no reload", await js("window.__dk === 1") && tab.loads === loadsBefore);
	check("the middle column", await js("!!document.querySelector('[data-r=main]').textContent.match(/bag/i)"));
	check("one region of each", await js("[...document.querySelectorAll('[data-r]')].map(e => e.dataset.r).every((n, i, a) => a.indexOf(n) === i)"));
	await js("history.back()");
	check("back: town again", await until("location.pathname === '/' && document.title === 'In Town' && !DK.busy()"), await js("document.title"));
	check("back: no reload", await js("window.__dk === 1"));
	await js("history.forward()");
	check("forward", await until("location.pathname === '/inventory' && !DK.busy()"));

	section = "typed text survives";
	await js("window.__inp = document.querySelector('[data-chat-form] [name=babble]'); window.__inp.value = 'half a thought';" +
		"window.__mut = []; new MutationObserver(function (l) { l.forEach(function (m) { window.__mut.push(m.type + ':' + (m.target.getAttribute ? (m.target.getAttribute('data-r') || m.target.nodeName) : m.target.nodeName) + ':' + m.removedNodes.length + '/' + m.addedNodes.length + ':' + (m.attributeName || '')); }); })" +
		".observe(document.body, { subtree: true, childList: true, attributes: true })");
	await js("document.querySelector('a[href=\"/news\"]').click()");
	check("news", await until("location.pathname === '/news'"));
	check("the chat input keeps its text", await js("document.querySelector('[data-chat-form] [name=babble]').value === 'half a thought'"),
		await js("document.querySelector('[data-chat-form] [name=babble]').value"));
	check("still no reload", await js("window.__dk === 1"));
	check("the same input element", await js("document.querySelector('[data-chat-form] [name=babble]') === window.__inp"), await js("window.__mut.slice(0, 40)"));

	section = "a panel that moves";
	// the town page has the chat in its middle column, the others in the right one: the
	// region comes as a placeholder, and the page's own panel moves there untouched
	await js("DK.visit('/')");
	await until("location.pathname === '/' && !DK.busy()");
	if (await js("!!document.querySelector('[data-r=main] [data-r=chat]')")) {
		await js("window.__chat = document.querySelector('[data-r=chat]'); document.querySelector('[data-r=chat] [name=babble]').value = 'typed in town'");
		await js("document.querySelector('a[href=\"/inventory\"]').click()");
		check("inventory", await until("location.pathname === '/inventory' && !DK.busy()"));
		check("the chat in the right column", await js("!!document.querySelector('[data-r=right] [data-r=chat]')"));
		check("the same panel (moved, not rebuilt)", await js("document.querySelector('[data-r=chat]') === window.__chat"));
		check("with what was typed", await js("document.querySelector('[data-r=chat] [name=babble]').value === 'typed in town'"));
		check("its address field follows the page", await js("document.querySelector('[data-r=chat-form] [name=back]').value === '/inventory'"));
		await js("document.querySelector('[data-r=chat] [name=babble]').value = ''");
	}

	section = "the chat";
	await js("var f = document.querySelector('[data-chat-form]'); f.querySelector('[name=babble]').value = 'hello from the browser'; f.requestSubmit()");
	check("my message in the panel", await until("/hello from the browser/.test(document.querySelector('[data-r=chat-posts]').textContent)"));
	check("the input cleared", await until("document.querySelector('[data-chat-form] [name=babble]').value === ''"));
	// the message came from the page's chat-post prototype: the server's own markup for it
	// (a player's; an administrator's has the page's address in its delete form)
	if (await js("!document.body.hasAttribute('data-live-admin')")) {
		var mine = await js("[...document.querySelectorAll('[data-r=chat-posts] li')].pop().outerHTML");
		await js("DK.refresh()");
		await until("!DK.busy()");
		var theirs = await js("[...document.querySelectorAll('[data-r=chat-posts] li')].pop().outerHTML");
		check("the prototype's markup is the server's", mine === theirs, [mine, theirs]);
	}
	await js("document.querySelector('details[data-chat]').open = false");
	await js("document.querySelector('a[href=\"/inventory\"]').click()");
	check("inventory", await until("location.pathname === '/inventory' && !DK.busy()"));
	check("the message is still there", await js("/hello from the browser/.test(document.querySelector('[data-r=chat-posts]').textContent)"));
	check("the chat stays folded", await js("document.querySelector('details[data-chat]').open === false"));
	await js("document.querySelector('details[data-chat]').open = true");

	section = "forms";
	await js("document.querySelector('a[href=\"/\"]').click()");
	await until("location.pathname === '/'");
	// walk out of town (a POST answered by the page it redirects to)
	await js("document.querySelector('form.compass input[name=north]').click()");
	check("moved", await until("/Latitude: 1/.test(document.querySelector('[data-r=loc]').textContent) || location.pathname === '/fight'"),
		await js("document.querySelector('[data-r=loc]').textContent"));
	check("no reload after a POST", await js("window.__dk === 1"));
	var fighting = await js("location.pathname === '/fight'");
	check("exploring or fighting", await js("/^(Exploring|Fighting)$/.test(document.title)"), await js("document.title"));
	if (!fighting) {
		await js("document.querySelector('form.compass input[name=south]').click()");
		check("back in Midworld", await until("document.title === 'Travel To' || location.pathname === '/fight'"), await js("document.title"));
		// "You have travelled to Midworld" is the POST's own page: no address shows it, the
		// address stays, and a reload shows the town
		if (await js("document.title === 'Travel To'")) {
			check("the address stays", await js("location.pathname === '/'"), await js("location.pathname"));
			check("marked as a POST's page", await js("history.state.post === true && DK.view().post === true"));
		}
	}

	section = "another tab";
	// a second tab of the same player: a change in one shows in the other (the server's
	// `stale` event over the shared stream, then a live refresh), without a page load
	var info2 = await (await fetch("http://127.0.0.1:" + port + "/json/new?" + encodeURIComponent(BASE + "/inventory"), { method: "PUT" })).json();
	var other = await session(info2.webSocketDebuggerUrl);
	await other.until("document.readyState === 'complete' && !!window.DK");
	await other.js("window.__dk2 = 1");
	await until("!DK.busy()");
	var lat = await js("(document.querySelector('[data-r=loc]').textContent.match(/Latitude: (-?\\d+)/) || [])[1]");
	var where = await js("location.pathname");
	if (where === "/" && await js("!!document.querySelector('form.compass')")) {
		await js("document.querySelector('form.compass input[name=north]').click()");
		await until("!DK.busy()");
		var lat2 = await js("(document.querySelector('[data-r=loc]').textContent.match(/Latitude: (-?\\d+)/) || [])[1]");
		check("moved here", lat2 !== lat, [lat, lat2]);
		check("the other tab follows", await other.until("(document.querySelector('[data-r=loc]').textContent.match(/Latitude: (-?\\d+)/) || [])[1] === " + JSON.stringify(lat2), 6000),
			await other.js("document.querySelector('[data-r=loc]').textContent"));
		check("the other tab: no page load", await other.js("window.__dk2 === 1 && location.pathname === '/inventory'"));
	}
	await other.send("Page.close").catch(function () {});
	other.ws.close();
	await js("DK.visit('/')");
	await until("!DK.busy()");

	section = "a fight";
	await js("fetch('/__test/encounter', { method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-Token': document.body.dataset.csrf } })" +
		".then(function () { DK.visit('/fight'); })");
	check("the fight page", await until("location.pathname === '/fight' && document.title === 'Fighting' && !DK.busy()"), await js("document.title"));
	check("no reload", await js("window.__dk === 1"));
	if (await js("!!document.querySelector('form[data-fight] button[name=fight]')")) {
		check("the monster's bar (made by fight.js, kept by the morph)", await js("!!document.querySelector('[data-fighter] .fight-meter[data-client]')"));
		var round = await js("Number(document.querySelector('form[data-fight] [name=round]').value)");
		await js("document.querySelector('form[data-fight] button[name=fight]').focus(); document.querySelector('form[data-fight] button[name=fight]').click()");
		check("the round plays: its first line", await until("!!document.querySelector('[data-fight-log] .fight-line')", 3000));
		check("the forms are locked meanwhile", await js("!document.querySelector('form[data-fight]') || !!document.querySelector('[data-fight-locked]')"));
		check("then the page as the server has it", await until("!DK.busy() && !document.querySelector('[data-fight-log] .fight-line') && !document.querySelector('[data-fight-locked]')", 8000));
		var after = await js("location.pathname");
		if (after === "/fight" && await js("!!document.querySelector('form[data-fight] [name=round]')")) {
			check("the next round's form", await js("Number(document.querySelector('form[data-fight] [name=round]').value)") === round + 1);
			check("the focus back on Attack", await js("document.activeElement && document.activeElement.name === 'fight'"), await js("document.activeElement && document.activeElement.outerHTML.slice(0, 80)"));
			check("the bar still there", await js("!!document.querySelector('[data-fighter] .fight-meter[data-client]')"));
		}
		check("no reload", await js("window.__dk === 1"));
	}
	await js("DK.visit('/')");
	await until("!DK.busy()");

	section = "slow answers";
	await js("var a = document.createElement('a'); a.href = '/__test/slow?ms=900'; a.textContent = 'slow';" +
		"document.querySelector('[data-r=main]').appendChild(a); a.click()");
	await sleep(500);
	check("the progress bar after a moment", await js("document.documentElement.classList.contains('dk-busy') && !!document.querySelector('.dk-progress')"));
	check("the middle column is busy", await js("document.querySelector('[data-r=main]').getAttribute('aria-busy') === 'true'"));
	check("the page comes", await until("document.title === 'Slow' && !DK.busy()"), await js("document.title"));
	check("no bar after", await js("!document.documentElement.classList.contains('dk-busy')"));
	// a second link while the first is on its way: the first is dropped
	await js("var a = document.createElement('a'); a.href = '/__test/slow?ms=700'; document.body.appendChild(a); a.click();" +
		"setTimeout(function () { document.querySelector('a[href=\"/news\"]').click(); }, 100)");
	check("the last link wins", await until("location.pathname === '/news' && !DK.busy()", 8000), await js("location.pathname"));
	await sleep(900);
	check("and stays", await js("location.pathname === '/news' && document.title !== 'Slow'"), await js("document.title"));

	section = "another layout";
	await js("window.scrollTo(0, 0); document.querySelector('.dk-topnav a[href=\"/help\"]').click()");
	check("help (the minimal layout)", await until("location.pathname === '/help' && document.body.classList.contains('minimal') && !DK.busy()"));
	check("no reload", await js("window.__dk === 1"));
	check("one body region", await js("!document.querySelector('[data-r=left]')"));
	check("the stream lives on (a player's page)", await js("document.body.hasAttribute('data-live')"));
	await js("window.scrollTo(0, 600)");
	var y = await js("window.scrollY");
	await js("history.back()");
	check("back: the news in the main layout", await until("location.pathname === '/news' && !!document.querySelector('[data-r=left]') && !DK.busy()"));
	await js("history.forward()");
	check("forward: help, scrolled where it was", await until("location.pathname === '/help' && !DK.busy() && Math.abs(window.scrollY - " + y + ") < 2"),
		await js("window.scrollY") + " vs " + y);
	await js("document.querySelector('a[href=\"/\"]') ? document.querySelector('a[href=\"/\"]').click() : DK.visit('/')");
	await until("location.pathname === '/' && !DK.busy()");

	section = "logging out";
	await js("document.querySelector('.dk-topnav form[action=\"/logout\"] input[type=image]').click()");
	check("the login page", await until("location.pathname === '/login' && !DK.busy()"), await js("location.pathname"));
	check("no player any more", await js("!document.body.hasAttribute('data-live')"));
	check("the stream stopped", await until("!localStorage.getItem('dk-live-leader')"), await js("localStorage.getItem('dk-live-leader')"));
	check("no reload", await js("window.__dk === 1"));
	await js("document.querySelector('[name=username]').value = " + JSON.stringify(USER) +
		"; document.querySelector('[name=password]').value = " + JSON.stringify(PASS) + ";" +
		"document.querySelector('form[action=\"/login\"]').requestSubmit()");
	check("logged in again", await until("/^\\/(fight)?$/.test(location.pathname) && !DK.busy() && document.body.hasAttribute('data-live')"),
		await js("location.pathname"));

	section = "bad answers";
	// a region the page doesn't have: the client loads the page natively
	await js("window.__dk = 2; document.querySelector('[data-r=main]').removeAttribute('data-r');" +
		"document.querySelector('a[href=\"/news\"]').click()");
	check("reloaded natively", await until("window.__dk === undefined && document.readyState === 'complete'"));

	if (fails && tab.log.length) console.log("the page's console:\n  " + tab.log.slice(-20).join("\n  "));
	console.log(fails ? fails + " of " + count + " failed" : "ok " + count);
	ws.close();
}

main().then(function () { process.exit(fails ? 1 : 0); }, function (e) { console.log("FAIL " + (e && e.stack || e)); process.exit(1); });
