// worldgl.js :: the World Map's sky drawn with WebGL (docs/APP.md "Terrain and the map"): a
// transparent canvas over the land's picture and under the towns, drawing the weather the
// server's tick keeps for the tick (GET /map/sky/data, the same facts as the SVG overlay
// GET /map/sky, which stays the reference rendering): light by the time of day over the
// land's relief (public/images/world-relief.bin), clouds and their shadows, swirling storms
// gliding between ticks, fog banks on low ground, rain, falling and settled snow,
// lightning, lit towns at night. A deliberate exception to "markup comes from the server":
// the server sends data and the page draws the pixels.
//
// windows.js loads it when a map that offers it (.world-map[data-sky-data]) shows. It runs
// on a hardware GPU only (a software renderer, or first frames slower than SLOW_MS, keep
// the SVG sky), at the frame rate of what is on screen (a still frame when nothing moves,
// 15 fps for drifting clouds, 30 while rain, snow or lightning show), not at all while the
// page is hidden, the map closed or scrolled away, and in still frames with
// prefers-reduced-motion. Until its first frame, and whenever it stops for good or loses
// its context, the SVG sky shows exactly as without it (windows.js keeps swapping it).
(function () {
	"use strict";
	if (typeof document === "undefined" || !window.fetch || !window.WebGL2RenderingContext || !window.Promise) return;

	var SIDE = 101, WSIDE = 51, UP = 4, SUP = 4;   // the map's cells, the weather's; how much finer their textures
	var DPR = 1.5;                                 // the device pixel ratio, at most
	var SLOW_MS = 12;                              // a first frame slower than this (median of 4) keeps the SVG sky
	var GLIDE = 10000, FADE = 3000;                // the storms glide over a tick; the cells' skies fade
	var MAX_STORMS = 8, MAX_TOWNS = 12;
	// lib/mapsky.lua's lists: each cell is ALPHABET[sky index * 5 + ground index]
	var SKIES = ["clear", "sun", "heat", "overcast", "fog", "drizzle", "rain", "downpour", "thunderstorm", "snow", "blizzard"];
	var ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
	// per sky: cloud cover, rain, snowfall, fog; then whether it moves fast (30 fps) or slowly (15)
	var SKY = {
		clear: [0.03, 0, 0, 0, 0], sun: [0, 0, 0, 0, 0], heat: [0, 0, 0, 0, 15], overcast: [0.72, 0, 0, 0, 15],
		fog: [0.12, 0, 0, 0.85, 15], drizzle: [0.72, 0.3, 0, 0, 30], rain: [0.85, 0.55, 0, 0, 30],
		downpour: [0.95, 0.85, 0, 0, 30], thunderstorm: [1, 1, 0, 0, 30], snow: [0.8, 0, 0.55, 0, 30], blizzard: [1, 0, 1, 0, 30],
	};
	var GROUND = [[0, 0], [0.45, 0], [0.85, 0], [0, 1], [0.2, 0.75]];   // dry wet mud snow ice: wetness, snow

	// The browser test's switch, honoured only where the server says test_routes
	// (data-sky-test): localStorage["dk-sky-gl-test"] = "software" draws on a software
	// renderer too (headless Chrome's SwiftShader) and never judges the frames slow; "slow"
	// judges them slow.
	function testMode(map) {
		if (!map || !map.hasAttribute("data-sky-test")) return "";
		try { return window.localStorage.getItem("dk-sky-gl-test") || ""; } catch (e) { return ""; }
	}

	// ---- the shader: the sky over the map, premultiplied, layer over layer
	var VERT = "#version 300 es\nin vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }";
	var FRAG = [
		"#version 300 es",
		"precision highp float;",
		"uniform vec4 uView;   // offset (px), pixels a unit, canvas height (px)",
		"uniform sampler2D uNoise, uRelief, uSky0, uSky1, uGround0, uGround1;",
		"uniform float uMix, uTime, uDpr, uNight, uDay, uLightK, uShadeK, uWashA;",
		"uniform vec3 uL, uLCol, uShade, uWash;",
		"uniform vec4 uStorms[" + MAX_STORMS + "]; uniform int uNStorms;",
		"uniform vec2 uTowns[" + MAX_TOWNS + "]; uniform int uNTowns;",
		"out vec4 outColor;",
		"vec4 acc;",
		"void over(vec3 c, float a) { a = clamp(a, 0.0, 1.0); acc = vec4(c * a, a) + acc * (1.0 - a); }",
		"float nz(vec2 p) { return texture(uNoise, p / 256.0).r; }",
		"vec2 nz2(vec2 p) { return texture(uNoise, p / 256.0).rg; }",
		"const mat2 ROT = mat2(0.8, 0.6, -0.6, 0.8);",
		"float fbm(vec2 p, int oct) { float s = 0.0, a = 0.5, n = 0.0; for (int i = 0; i < 5; i++) { if (i >= oct) break;",
		"  s += a * nz(p); n += a; p = ROT * p * 2.03 + 17.1; a *= 0.5; } return s / n; }",
		"float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }",
		"float H(vec2 p) { return texture(uRelief, p / 101.0).r * 6.0; }",
		// the puffs at scale sc: how far inside the nearest circle of a jittered lattice (units)
		"float puffs(vec2 p, float sc) { vec2 g = p / sc, i = floor(g), f = g - i; float best = -9.0;",
		"  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) { vec2 c = i + vec2(float(x), float(y));",
		"    vec2 o = vec2(float(x), float(y)) + 0.15 + 0.7 * vec2(hash(c), hash(c + 19.19)) - f;",
		"    best = max(best, 0.45 + 0.4 * hash(c + 7.7) - length(o)); }",
		"  return best * sc; }",
		"float clouds(vec2 q, float bias) { return max(puffs(q, 3.0), puffs(q + vec2(13.7, 5.3), 1.5) - 0.15) + bias; }",
		"void main() {",
		"  vec2 p = (vec2(gl_FragCoord.x, uView.w - gl_FragCoord.y) - uView.xy) / uView.z;",
		"  if (p.x < 0.0 || p.y < 0.0 || p.x > 101.0 || p.y > 101.0) { outColor = vec4(0.0); return; }",
		"  acc = vec4(0.0);",
		"  vec2 rel = texture(uRelief, p / 101.0).rg; float h = rel.r; float water = smoothstep(0.4, 0.6, rel.g);",
		"  vec2 warp = (nz2(p * 5.0 + 9.0) - 0.5) * 1.8;",
		"  vec2 wuv = (p + warp + vec2(-0.5, 1.5)) / 102.0;",
		"  vec4 s = mix(texture(uSky0, wuv), texture(uSky1, wuv), uMix);",
		"  vec4 g = mix(texture(uGround0, wuv), texture(uGround1, wuv), uMix);",
		// the time of day's wash, then the light over the relief: slopes toward it lit, away shaded
		"  over(uWash, uWashA);",
		"  float e = 0.35;",
		"  vec3 n = normalize(vec3(H(p - vec2(e, 0.0)) - H(p + vec2(e, 0.0)), H(p - vec2(0.0, e)) - H(p + vec2(0.0, e)), 2.0 * e));",
		"  float d = (dot(n, uL) - uL.z) * (1.0 - water);",
		"  if (d < 0.0) over(uShade, min(-d * uShadeK, 0.3)); else over(uLCol, min(d * uLightK, 0.2));",
		// wet and muddy ground a little darker; snow lying, from the high ground down, not on the water
		"  over(vec3(0.18, 0.14, 0.1), g.r * 0.12);",
		"  float snow = g.g * smoothstep(0.3, 0.6, g.g * 0.7 + h * 0.5 + (fbm(p * 3.0, 3) - 0.5) * 0.5) * (1.0 - water * 0.8);",
		"  over(vec3(0.95, 0.97, 1.0) * (0.55 + 0.45 * uDay) + uLCol * 0.05, snow * 0.8);",
		// the storms: masses swirling round their centres, dragging the clouds with them
		"  vec2 q = p; float cov = s.r; float dark = 0.0;",
		"  for (int i = 0; i < " + MAX_STORMS + "; i++) { if (i >= uNStorms) break;",
		"    vec4 st = uStorms[i]; vec2 dd = p - st.xy; float dist = length(dd) / max(st.z, 0.3);",
		"    float w = 1.0 - smoothstep(0.3, 1.3, dist); float inner = 1.0 - min(dist, 1.3) / 1.3;",
		"    float ang = inner * inner * 5.0 + uTime * 0.1; float cs = cos(ang), sn = sin(ang);",
		"    q += (mat2(cs, sn, -sn, cs) * dd - dd) * w * st.w;",
		"    float arms = 0.5 + 0.5 * sin(atan(dd.y, dd.x) * 2.0 + log(max(dist, 0.05)) * 5.0 - uTime * 0.25);",
		"    cov = max(cov, w * st.w * (0.55 + 0.45 * arms) * (0.75 + 0.25 * inner));",
		"    dark = max(dark, (1.0 - smoothstep(0.1, 1.0, dist)) * st.w);",
		"  }",
		// the clouds: banks of puffs (circles on a jittered lattice at two scales, their union
		// grown by the cells' cover, so a full sky is one mass and a thin one scattered puffs),
		// drifting toward Gilead with the weather; F is the distance inside their edge (units)
		"  vec2 cq = q + vec2(-0.005, -0.005) * uTime; float bias = (cov - 0.535) * 4.4 - (1.0 - smoothstep(0.12, 0.3, cov)) * 0.8;",
		"  float aa = 0.8 / uView.z, F = -9.0, dens = 0.0, sd = 0.0;",
		"  if (cov > 0.08) {",
		"    F = clouds(cq, bias); dens = smoothstep(-aa, aa, F);",
		"    vec2 off = uL.z > 0.02 ? uL.xy / max(uL.z, 0.25) * 1.2 : vec2(0.0);",
		"    sd = smoothstep(-0.2, 0.2, clouds(cq + off, bias));",
		"  }",
		"  over(vec3(0.08, 0.07, 0.12), sd * 0.26 * (0.3 + 0.7 * uDay));",              // the clouds' shadows
		"  over(vec3(0.12, 0.14, 0.2), s.g * 0.18);",                                  // under the rain
		"  float fog = s.a * smoothstep(0.72, 0.38, h) * smoothstep(0.25, 0.6, fbm(p * 1.3 + vec2(uTime * 0.04, uTime * 0.01), 3) + 0.15);",
		"  over(vec3(0.94, 0.95, 0.97) * (0.45 + 0.55 * uDay) + uLCol * 0.05, fog * 0.9);",   // fog banks on low ground
		"  if (g.a > 0.02) over(vec3(0.95, 0.62, 0.3), g.a * (0.1 + 0.05 * sin(p.y * 6.0 + uTime * 2.0 + nz(p * 8.0) * 6.0)));",   // heat
		"  if (F > -aa) {",
		"    float thick = clamp(s.g * 0.9 + s.b * 0.25 + dark * 0.7, 0.0, 1.0);",
		// near an edge: lit on the side toward the sun or the moon, shaded away from it
		"    float lit = 0.0, shade = 0.0;",
		"    if (F < 1.2) { vec2 ld = length(uL.xy) > 0.05 ? normalize(uL.xy) : vec2(-0.6, -0.8);",
		"      lit = 1.0 - smoothstep(-0.06, 0.06, clouds(cq + ld * 0.3, bias));",
		"      shade = 1.0 - smoothstep(-0.4, 0.5, clouds(cq - ld * 0.9, bias)); }",
		"    vec3 light = mix(vec3(1.0), uLCol, 0.2) * (0.62 + 0.38 * uDay);",
		"    vec3 cloud = mix(vec3(1.0), vec3(0.6, 0.63, 0.7), thick);",
		"    cloud = mix(cloud, vec3(0.3, 0.32, 0.38), dark * 0.8);",
		"    cloud = mix(cloud, cloud * vec3(0.7, 0.74, 0.84), shade * 0.8) * light;",
		"    cloud = mix(cloud, light * 1.05, lit * 0.6 * (1.0 - 0.5 * thick));",
		"    over(cloud, dens * (0.78 + 0.12 * uDay));",
		// their edge inked like the map's lines (darker for rain clouds)
		"    float w = 1.8 * uDpr / uView.z;",
		"    float line = dens * (1.0 - smoothstep(w - aa, w + aa, F));",
		"    over(mix(vec3(0.3, 0.26, 0.24), vec3(0.18, 0.2, 0.27), thick) * (0.5 + 0.5 * uDay), line * (0.6 + 0.3 * uDay));",
		"  }",
		// lightning: now and then a thunderstorm's cell flashes
		"  if (g.b > 0.05) {",
		"    vec2 lc = (p + warp * 0.5) / 2.0; vec2 cell = floor(lc); float k = floor(uTime * 5.0), ft = fract(uTime * 5.0);",
		"    float f = step(0.975, hash(cell + k * 0.37)) * (1.0 - ft) + step(0.985, hash(cell + (k - 1.0) * 0.37)) * (1.0 - ft) * 0.4;",
		"    f *= 1.0 - smoothstep(0.15, 0.7, length(fract(lc) - 0.5));",
		"    over(vec3(0.85, 0.9, 1.0), f * g.b * (0.4 + dens));",
		"  }",
		// rain streaks and falling snow, in the screen's pixels
		"  vec2 sp = gl_FragCoord.xy / uDpr;",
		// rain falls from the clouds as dark slanted streaks, snow as rimmed flakes
		"  float rain = s.g * smoothstep(-0.8, 0.2, F), snowing = s.b * smoothstep(-0.8, 0.2, F);",
		"  if (rain > 0.02) {",
		"    vec2 rs = mat2(0.97, -0.26, 0.26, 0.97) * sp; rs.y += uTime * 220.0;",
		"    vec2 c = floor(rs / vec2(4.0, 28.0)); vec2 f = fract(rs / vec2(4.0, 28.0)); float rnd = hash(c); f.y = fract(f.y + rnd * 7.0);",
		"    float streak = step(rnd, 0.25 + rain * 0.6) * (1.0 - smoothstep(0.1, 0.24, abs(f.x - 0.5))) * smoothstep(0.0, 0.25, f.y) * (1.0 - smoothstep(0.65, 0.85, f.y));",
		"    over(vec3(0.12, 0.18, 0.32) * (0.6 + 0.4 * uDay), streak * 0.8 * smoothstep(0.02, 0.2, rain));",
		"  }",
		"  if (snowing > 0.02) {",
		"    for (int layer = 0; layer < 2; layer++) { float sz = layer == 0 ? 12.0 : 18.0; float fall = layer == 0 ? 20.0 : 30.0;",
		"      vec2 rs = sp + vec2(sin(uTime * 0.7 + sp.y * 0.03) * 4.0, uTime * fall);",
		"      vec2 c = floor(rs / sz); vec2 f = fract(rs / sz) - 0.5; vec2 o = vec2(hash(c + 3.1), hash(c + 7.7)) - 0.5;",
		"      float on = step(hash(c + float(layer) * 13.0), 0.25 + snowing * 0.6), d = length(f - o * 0.6), r0 = 0.12 + float(layer) * 0.04;",
		"      over(vec3(0.22, 0.27, 0.38), on * (1.0 - smoothstep(r0, r0 + 0.06, d)) * 0.75);",
		"      over(vec3(1.0) * (0.7 + 0.3 * uDay), on * (1.0 - smoothstep(r0 - 0.04, r0, d))); }",
		"  }",
		// the towns' lights at night, dimmer through clouds
		"  if (uNight > 0.01) { float glow = 0.0;",
		"    for (int i = 0; i < " + MAX_TOWNS + "; i++) { if (i >= uNTowns) break; vec2 dd = p - uTowns[i]; float r2 = dot(dd, dd);",
		"      glow += exp(-r2 / 1.2) * 0.8 + exp(-r2 / 10.0) * 0.3; }",
		"    over(vec3(1.0, 0.7, 0.36), glow * uNight * (1.0 - dens * 0.5));",
		"  }",
		"  outColor = acc;",
		"}",
	].join("\n");

	// ---- data the renderer keeps (also to set up again after a lost context)
	var relief = null, noise = null;   // Float32Array (height, water), Uint8Array
	var dataUrl = "", reliefUrl = "";

	// a cubic B-spline over a side x side grid (smooth, no overshoot), `up` times finer, of
	// one Float32Array per channel into `out` (`stride` channels a texel, times `scale`)
	function bspline(grids, side, up, out, stride, scale) {
		var n = side * up, wx = [], ix = [];
		function at(g, x, y) { x = x < 0 ? 0 : x >= side ? side - 1 : x; y = y < 0 ? 0 : y >= side ? side - 1 : y; return g[y * side + x]; }
		for (var x = 0; x < n; x++) {
			var f = (x + 0.5) / up - 0.5, i = Math.floor(f), t = f - i, t2 = t * t, t3 = t2 * t;
			ix.push(i);
			wx.push([(1 - t) * (1 - t) * (1 - t) / 6, (3 * t3 - 6 * t2 + 4) / 6, (-3 * t3 + 3 * t2 + 3 * t + 1) / 6, t3 / 6]);
		}
		for (var y = 0; y < n; y++) for (x = 0; x < n; x++) {
			var k = (y * n + x) * stride, X = ix[x], Y = ix[y], WX = wx[x], WY = wx[y];
			for (var c = 0; c < grids.length; c++) {
				var g = grids[c], v = 0;
				for (var j = 0; j < 4; j++) {
					v += WY[j] * (WX[0] * at(g, X - 1, Y + j - 1) + WX[1] * at(g, X, Y + j - 1) + WX[2] * at(g, X + 1, Y + j - 1) +
						WX[3] * at(g, X + 2, Y + j - 1));
				}
				out[k + c] = v * scale;
			}
		}
		return out;
	}

	// world-relief.bin (a byte a cell: the height, plus 64 on water) as height and water
	function reliefOf(bytes) {
		var hgt = new Float32Array(SIDE * SIDE), wat = new Float32Array(SIDE * SIDE);
		for (var i = 0; i < SIDE * SIDE; i++) { hgt[i] = (bytes[i] & 63) / 35; wat[i] = bytes[i] & 64 ? 1 : 0; }
		return bspline([hgt, wat], SIDE, UP, new Float32Array(SIDE * UP * SIDE * UP * 2), 2, 1);
	}

	// a tileable smooth noise: two channels of value noise, four octaves
	function noiseOf() {
		var N = 256, out = new Uint8Array(N * N * 4), layers = [[8, 1], [16, 0.5], [32, 0.25], [64, 0.125]];
		for (var ch = 0; ch < 2; ch++) {
			var acc = new Float32Array(N * N), norm = 0;
			layers.forEach(function (L, li) {
				var cells = L[0], amp = L[1], lat = new Float32Array(cells * cells), seed = 7 + ch * 101 + li * 17, step = N / cells;
				for (var i = 0; i < lat.length; i++) { seed = (seed * 1103515245 + 12345) & 0x7fffffff; lat[i] = seed / 0x7fffffff; }
				norm += amp;
				for (var y = 0; y < N; y++) for (var x = 0; x < N; x++) {
					var gx = x / step, gy = y / step, x0 = Math.floor(gx), y0 = Math.floor(gy), tx = gx - x0, ty = gy - y0;
					tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty);
					var x1 = (x0 + 1) % cells, y1 = (y0 + 1) % cells;
					acc[y * N + x] += amp * ((lat[y0 * cells + x0] * (1 - tx) + lat[y0 * cells + x1] * tx) * (1 - ty) +
						(lat[y1 * cells + x0] * (1 - tx) + lat[y1 * cells + x1] * tx) * ty);
				}
			});
			for (var j = 0; j < N * N; j++) out[j * 4 + ch] = Math.round(acc[j] / norm * 255);
		}
		return out;
	}

	function skyName(d, i) { return SKIES[(ALPHABET.indexOf(d.cells.charAt(i)) / 5) | 0] || "clear"; }
	// a tick's sky as textures (cover, rain, snowfall, fog; wetness, snow lying, thunder, heat)
	function skyOf(d) {
		var N = WSIDE * WSIDE, WS = WSIDE * SUP, ch = [];
		for (var c = 0; c < 8; c++) ch.push(new Float32Array(N));
		for (var i = 0; i < N; i++) {
			var sk = skyName(d, i), gr = GROUND[ALPHABET.indexOf(d.cells.charAt(i)) % 5] || GROUND[0], v = SKY[sk];
			ch[0][i] = v[0]; ch[1][i] = v[1]; ch[2][i] = v[2]; ch[3][i] = v[3];
			ch[4][i] = gr[0]; ch[5][i] = gr[1]; ch[6][i] = sk === "thunderstorm" ? 1 : 0; ch[7][i] = sk === "heat" ? 1 : 0;
		}
		return { sky: bspline(ch.slice(0, 4), WSIDE, SUP, new Uint8ClampedArray(WS * WS * 4), 4, 255),
			ground: bspline(ch.slice(4), WSIDE, SUP, new Uint8ClampedArray(WS * WS * 4), 4, 255) };
	}
	// the frame rate the sky needs where the map is in view (rect: map units, null all): 30
	// for rain, snow or lightning, 15 for clouds, fog, heat or a storm, else 0 (still)
	function levelOf(d, rect) {
		var fps = 0;
		for (var i = 0; i < WSIDE * WSIDE && fps < 30; i++) {
			var f = SKY[skyName(d, i)][4];
			if (f > fps && inView(rect, 2 * (i % WSIDE) + 1.5, 2 * ((i / WSIDE) | 0) - 0.5, 2)) fps = f;
		}
		(d.storms || []).forEach(function (s) { if (fps < 15 && inView(rect, s.x, s.y, s.r)) fps = 15; });
		return fps;
	}
	function inView(rect, x, y, r) { return !rect || (x + r >= rect[0] && x - r <= rect[2] && y + r >= rect[1] && y - r <= rect[3]); }

	// the light by the sun's and the moon's angles: its direction (x east, y south, z up), its
	// colour and strength, the shade's, the time of day's wash (dawn warm, dusk purple, night
	// blue, at most WASH_NIGHT so the map stays readable), how much it is day and night
	var WASH_NIGHT = 0.42;
	function smooth(a, b, x) { var t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); }
	function dirOf(az, el) { return [Math.sin(az) * Math.cos(el), -Math.cos(az) * Math.cos(el), Math.sin(el)]; }
	function mixv(a, b, t) { return a.map(function (v, i) { return v + (b[i] - v) * t; }); }
	function lightOf(d) {
		var sunEl = d.sun[1], moonEl = d.moon[1], evening = d.day > 0.5;
		var day = smooth(-0.12, 0.3, sunEl), night = 1 - smooth(-0.16, 0.06, sunEl);
		var low = smooth(-0.2, 0.0, sunEl) * (1 - smooth(0.08, 0.45, sunEl));
		var sunUp = sunEl > -0.04 || moonEl <= 0;
		var L = sunUp ? dirOf(d.sun[0], Math.max(sunEl, 0.12)) : dirOf(d.moon[0], Math.max(moonEl, 0.15));
		var col = sunUp ? mixv([1.0, 0.96, 0.86], [1.0, 0.62, 0.32], low) : [0.72, 0.82, 1.0];
		var lightK = sunUp ? 0.22 + low * 0.1 : 0.3, shadeK = sunUp ? 0.55 + low * 0.15 : 0.7;
		var shade = sunUp ? mixv([0.16, 0.12, 0.22], evening ? [0.25, 0.1, 0.3] : [0.3, 0.14, 0.18], low) : [0.0, 0.03, 0.1];
		var washLow = evening ? [0.42, 0.23, 0.39] : [0.95, 0.7, 0.54], washNight = [0.05, 0.1, 0.24];
		var wl = low * (evening ? 0.22 : 0.15), wn = night * WASH_NIGHT, wa = wl + wn - wl * wn;
		var wash = wa > 0 ? mixv(washLow, washNight, wn / (wl + wn)) : [0, 0, 0];
		return { L: L, col: col, lightK: lightK, shadeK: shadeK, shade: shade, wash: wash, washA: wa, day: day, night: night };
	}

	// ---- the renderer: one per page; its canvas moves to whichever map shows
	var R = null, refused = "";
	function make(map) {
		var canvas = document.createElement("canvas");
		canvas.className = "world-map-canvas";
		canvas.setAttribute("data-client", "");
		canvas.setAttribute("aria-hidden", "true");
		var r = { canvas: canvas, gl: null, map: null, svg: null, data: null, level: 0, rect: null, visible: true,
			storms: {}, towns: [], running: false, last: 0, shown: false, frames: 0, stats: [], skyFrom: -1e9,
			light: null, test: testMode(map), fetches: 0 };
		canvas.addEventListener("webglcontextlost", function (ev) {
			ev.preventDefault();
			r.running = false; r.gl = null;
			showSVG(r);
			r.lostTimer = setTimeout(function () { giveUp("context lost"); }, 5000);
		});
		canvas.addEventListener("webglcontextrestored", function () {
			clearTimeout(r.lostTimer);
			if (!setup(r)) { giveUp("context not restored"); return; }
			firstFrames(r);
		});
		if (window.IntersectionObserver) {
			r.io = new IntersectionObserver(function (entries) {
				var e = entries[entries.length - 1];
				r.visible = e.isIntersecting;
				r.rect = visibleRect(r, e.isIntersecting ? e.intersectionRect : null);
				if (r.data) r.level = levelOf(r.data, r.rect);
				if (r.visible) start(r); else r.running = false;
			}, { threshold: [0, 0.25, 0.5, 0.75, 1] });
		}
		return r;
	}

	// the canvas's WebGL2 context on a hardware GPU, or null (the test's switch allows software)
	function context(r) {
		var soft = r.test === "software" || r.test === "slow";
		var gl = r.canvas.getContext("webgl2", { alpha: true, premultipliedAlpha: true, antialias: false, depth: false,
			powerPreference: "low-power", failIfMajorPerformanceCaveat: !soft });
		if (!gl || gl.isContextLost()) return null;
		var dbg = gl.getExtension("WEBGL_debug_renderer_info");
		r.renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
		// headless Chromium hands out SwiftShader all the same: refuse what is known to be software
		r.software = /SwiftShader|llvmpipe|softpipe|Software|Basic Render/i.test(r.renderer);
		return r.software && !soft ? null : gl;
	}

	// the GPU's side (again after a lost context): false when it can't be used
	function setup(r) {
		var gl = context(r);
		if (!gl) return false;
		function compile(type, src) {
			var s = gl.createShader(type);
			gl.shaderSource(s, src); gl.compileShader(s);
			if (!gl.getShaderParameter(s, gl.COMPILE_STATUS) && !gl.isContextLost()) throw new Error(gl.getShaderInfoLog(s));
			return s;
		}
		var t0 = performance.now();
		try {
			var p = gl.createProgram();
			gl.attachShader(p, compile(gl.VERTEX_SHADER, VERT));
			gl.attachShader(p, compile(gl.FRAGMENT_SHADER, FRAG));
			gl.bindAttribLocation(p, 0, "aPos");
			gl.linkProgram(p);
			if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
		} catch (e) {
			if (window.console) console.warn("worldgl:", e.message);
			return false;
		}
		r.compileMs = performance.now() - t0;
		var u = {}, count = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
		for (var i = 0; i < count; i++) { var info = gl.getActiveUniform(p, i); u[info.name.replace(/\[0\]$/, "")] = gl.getUniformLocation(p, info.name); }
		gl.useProgram(p);
		gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
		gl.enableVertexAttribArray(0);
		gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
		gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
		function texture(unit, name, w, h, ifmt, fmt, type, data, wrap) {
			var t = gl.createTexture();
			gl.activeTexture(gl.TEXTURE0 + unit);
			gl.bindTexture(gl.TEXTURE_2D, t);
			gl.texImage2D(gl.TEXTURE_2D, 0, ifmt, w, h, 0, fmt, type, data);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap || gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap || gl.CLAMP_TO_EDGE);
			gl.uniform1i(u[name], unit);
			return t;
		}
		var WS = WSIDE * SUP, blank = new Uint8Array(WS * WS * 4);
		texture(0, "uNoise", 256, 256, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, noise || (noise = noiseOf()), gl.REPEAT);
		texture(1, "uRelief", SIDE * UP, SIDE * UP, gl.RG16F, gl.RG, gl.FLOAT, relief);
		// the cells' skies, the tick before (units 2, 4) and this one (3, 5)
		r.tex = [texture(2, "uSky0", WS, WS, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, blank), texture(3, "uSky1", WS, WS, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, blank),
			texture(4, "uGround0", WS, WS, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, blank), texture(5, "uGround1", WS, WS, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, blank)];
		r.gl = gl; r.u = u;
		if (r.data) { var d = r.data; r.data = null; setSky(r, d); }
		return true;
	}

	function upload(gl, unit, data) {
		gl.activeTexture(gl.TEXTURE0 + unit);
		gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, WSIDE * SUP, WSIDE * SUP, gl.RGBA, gl.UNSIGNED_BYTE, data);
	}

	// a tick's sky: into units 3 and 5, what they showed into 2 and 4 (it fades from them)
	function setSky(r, d) {
		var gl = r.gl, now = performance.now(), first = !r.data, t0 = now;
		var s = skyOf(d);
		r.skyMs = performance.now() - t0;
		r.level = levelOf(d, r.rect);
		var fade = !first && r.level > 0 && !r.still;
		if (gl) {
			if (fade) {
				// the textures shown become the "before" ones: a copy through a framebuffer would
				// cost more than sending the last tick's again
				if (r.prev) { upload(gl, 2, r.prev.sky); upload(gl, 4, r.prev.ground); }
			} else { upload(gl, 2, s.sky); upload(gl, 4, s.ground); }
			upload(gl, 3, s.sky); upload(gl, 5, s.ground);
		}
		r.prev = s;
		r.skyFrom = fade ? now : -1e9;
		// the storms glide to their new places over the tick (trailing the real storm by a tick)
		var seen = {};
		(d.storms || []).forEach(function (st) {
			var key = String(st.id), strength = st.size === "great" ? 1 : st.size === "storm" ? 0.9 : 0.75, old = r.storms[key];
			seen[key] = true;
			r.storms[key] = { from: old && fade ? stormNow(old, now) : [st.x, st.y, st.r, fade ? 0 : strength],
				to: [st.x, st.y, st.r, strength], at: fade ? now : -1e9 };
		});
		Object.keys(r.storms).forEach(function (key) {
			if (seen[key]) return;
			var cur = stormNow(r.storms[key], now);
			if (!fade || cur[3] <= 0.001) delete r.storms[key];
			else r.storms[key] = { from: cur, to: [cur[0], cur[1], cur[2], 0], at: now };
		});
		var target = lightOf(d);
		r.lightFrom = fade && r.light ? lightNow(r, now) : target;
		r.light = target; r.lightAt = fade ? now : -1e9;
		r.data = d;
		var lit = target.night > 0.5;
		if (r.map) r.map.classList.toggle("world-map-lit", lit && r.shown);
	}
	function ease(t) { return t < 0 ? 0 : t > 1 ? 1 : t; }
	function stormNow(st, now) {
		var t = ease((now - st.at) / GLIDE);
		return st.from.map(function (v, i) { return v + (st.to[i] - v) * t; });
	}
	function lightNow(r, now) {
		var t = ease((now - r.lightAt) / GLIDE), a = r.lightFrom, b = r.light, out = {};
		Object.keys(b).forEach(function (k) { out[k] = typeof b[k] === "number" ? a[k] + (b[k] - a[k]) * t : mixv(a[k], b[k], t); });
		var len = Math.hypot(out.L[0], out.L[1], out.L[2]) || 1;
		out.L = out.L.map(function (v) { return v / len; });
		return out;
	}

	// ---- the canvas over the map's SVG: its box (to the fraction of a pixel, followed when it
	// changes: a ResizeObserver on the SVG), the land's picture as its background (the SVG's
	// own <image> hidden once the canvas draws, the towns and the player above it)
	function fit(r) {
		var svg = r.svg, c = r.canvas, map = r.map;
		if (!svg || !svg.isConnected) return;
		var sb = svg.getBoundingClientRect(), mb = map.getBoundingClientRect();
		var dpr = Math.min(window.devicePixelRatio || 1, DPR), w = sb.width, h = sb.height;
		c.style.left = (sb.left - mb.left - map.clientLeft) + "px"; c.style.top = (sb.top - mb.top - map.clientTop) + "px";
		c.style.width = w + "px"; c.style.height = h + "px";
		var pw = Math.max(1, Math.round(w * dpr)), ph = Math.max(1, Math.round(h * dpr));
		if (c.width !== pw || c.height !== ph) { c.width = pw; c.height = ph; }
		r.dpr = dpr;
		r.rect = visibleRect(r);
		if (r.data) r.level = levelOf(r.data, r.rect);
	}
	function view(r) {
		var w = r.canvas.width, h = r.canvas.height, s = Math.min(w, h) / SIDE;
		return [(w - SIDE * s) / 2, (h - SIDE * s) / 2, s, h];
	}
	// the part of the map in view, in the map's units (x0, y0, x1, y1), or null: all; `seen` is
	// the canvas's visible part (an IntersectionObserver's, clipped by the window's scrolling),
	// else the viewport's
	function visibleRect(r, seen) {
		var b = r.canvas.getBoundingClientRect();
		if (!b.width || !b.height) return null;
		var v = view(r), k = r.canvas.width / b.width;
		function mx(px) { return ((px - b.left) * k - v[0]) / v[2]; }
		function my(px) { return ((px - b.top) * k - v[1]) / v[2]; }
		if (seen) return [mx(seen.left), my(seen.top), mx(seen.right), my(seen.bottom)];
		return [mx(Math.max(b.left, 0)), my(Math.max(b.top, 0)), mx(Math.min(b.right, window.innerWidth)), my(Math.min(b.bottom, window.innerHeight))];
	}

	function draw(r, now) {
		var gl = r.gl, u = r.u;
		if (!gl || !r.data || gl.isContextLost()) return;
		var v = view(r), li = lightNow(r, now), t = r.still ? 0 : now / 1000;
		gl.viewport(0, 0, r.canvas.width, r.canvas.height);
		gl.uniform4f(u.uView, v[0], v[1], v[2], v[3]);
		gl.uniform1f(u.uMix, ease((now - r.skyFrom) / FADE));
		gl.uniform1f(u.uTime, t);
		gl.uniform1f(u.uDpr, r.dpr || 1);
		gl.uniform3fv(u.uL, li.L); gl.uniform3fv(u.uLCol, li.col); gl.uniform3fv(u.uShade, li.shade); gl.uniform3fv(u.uWash, li.wash);
		gl.uniform1f(u.uLightK, li.lightK); gl.uniform1f(u.uShadeK, li.shadeK); gl.uniform1f(u.uWashA, li.washA);
		gl.uniform1f(u.uDay, li.day); gl.uniform1f(u.uNight, li.night);
		var st = [], n = 0;
		Object.keys(r.storms).forEach(function (key) {
			if (n >= MAX_STORMS) return;
			Array.prototype.push.apply(st, stormNow(r.storms[key], now)); n++;
		});
		while (st.length < MAX_STORMS * 4) st.push(0);
		gl.uniform4fv(u.uStorms, st); gl.uniform1i(u.uNStorms, n);
		var tw = [];
		r.towns.slice(0, MAX_TOWNS).forEach(function (p) { tw.push(p[0], p[1]); });
		while (tw.length < MAX_TOWNS * 2) tw.push(0);
		gl.uniform2fv(u.uTowns, tw); gl.uniform1i(u.uNTowns, Math.min(r.towns.length, MAX_TOWNS));
		gl.drawArrays(gl.TRIANGLES, 0, 3);
		r.frames++;
	}

	// ---- when to draw: at the rate of what shows (0: a still frame on each change)
	function fps(r) { return r.still || !r.visible ? 0 : r.forced != null ? r.forced : r.level; }
	function loop(t) {
		var r = R;
		if (!r || !r.running) return;
		if (!r.gl || !r.canvas.isConnected || document.visibilityState === "hidden" || !r.visible || !fps(r)) { r.running = false; return; }
		window.requestAnimationFrame(loop);
		if (t - r.last < 1000 / fps(r) - 3) return;
		var t0 = performance.now();
		draw(r, t);
		r.stats.push([t - (r.last || t), performance.now() - t0]);
		if (r.stats.length > 2000) r.stats.shift();
		r.last = t;
	}
	function start(r) {
		if (!r.gl || !r.shown || !r.canvas.isConnected || document.visibilityState === "hidden" || !r.visible) return;
		if (!fps(r)) { draw(r, performance.now()); return; }
		if (r.running) return;
		r.running = true; r.last = 0;
		window.requestAnimationFrame(loop);
	}

	// the first frames, timed (each finished by the GPU): too slow, and the SVG sky stays;
	// else the canvas shows and the SVG's sky and picture hide
	function firstFrames(r) {
		var gl = r.gl, px = new Uint8Array(4), times = [], now = performance.now();
		if (r.test !== "software") {
			for (var i = 0; i < 5; i++) {
				var t0 = performance.now();
				draw(r, now + i * 33);
				gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
				if (i) times.push(performance.now() - t0);   // the first compiles the shader
			}
			times.sort(function (a, b) { return a - b; });
			r.firstMs = (times[1] + times[2]) / 2;
			if (r.test === "slow" || r.firstMs > SLOW_MS) { giveUp("slow: " + r.firstMs.toFixed(1) + " ms a frame"); return; }
		}
		draw(r, performance.now());
		r.shown = true;
		r.firstFrameAt = performance.now();
		hideSVG(r);
		start(r);
	}

	// the SVG sky (and the land's picture in the SVG) hidden while the canvas draws: windows.js
	// then leaves it (no data-sky); shown again (and asked for anew) when the canvas stops
	function hideSVG(r) {
		var map = r.map;
		if (!map) return;
		map.classList.add("world-map-glsky");
		var g = map.querySelector(".world-sky[data-sky]");
		if (g) { g.setAttribute("data-sky-held", g.getAttribute("data-sky")); g.removeAttribute("data-sky"); }
		if (r.data) map.classList.toggle("world-map-lit", r.light.night > 0.5);
	}
	function showSVG(r) {
		var map = r.map;
		r.shown = false;
		if (!map) return;
		map.classList.remove("world-map-glsky", "world-map-lit");
		var g = map.querySelector(".world-sky[data-sky-held]");
		if (g) {
			g.setAttribute("data-sky", g.getAttribute("data-sky-held"));
			g.removeAttribute("data-sky-held");
			document.dispatchEvent(new CustomEvent("dk-sky", { detail: {} }));   // windows.js: the overlay as it is now
		}
	}

	// for good (this page): the SVG sky as without WebGL
	function giveUp(reason) {
		var r = R;
		refused = reason;
		if (window.console && reason) console.info("worldgl: the SVG sky (" + reason + ")");
		if (!r) return;
		r.running = false;
		showSVG(r);
		if (r.io) r.io.disconnect();
		if (r.ro) r.ro.disconnect();
		if (r.canvas.parentNode) r.canvas.parentNode.removeChild(r.canvas);
		var lose = r.gl && r.gl.getExtension("WEBGL_lose_context");
		if (lose) lose.loseContext();
		r.gl = null;
	}

	function loadAll() {
		return Promise.all([
			relief ? null : fetch(reliefUrl, { credentials: "same-origin" }).then(function (res) {
				if (!res.ok) throw new Error("no relief");
				return res.arrayBuffer();
			}).then(function (buf) { relief = reliefOf(new Uint8Array(buf)); }),
			R && R.data ? null : loadSky(),
		]);
	}
	var skyLoading = null, skyMissed = false;
	function loadSky() {
		if (!skyLoading) {
			skyLoading = fetch(dataUrl, { credentials: "same-origin" }).then(function (res) {
				if (!res.ok) throw new Error("no sky");
				return res.json();
			}).then(function (d) {
				var r = R;
				if (!r) return;
				r.fetches++;
				setSky(r, d);
				if (r.shown) { if (fps(r)) start(r); else draw(r, performance.now()); }
			}).then(function () { skyLoading = null; }, function (e) { skyLoading = null; throw e; });
		}
		return skyLoading;
	}

	// a map on the page (the /map page's, or the window's once filled): its sky with WebGL
	function attach(map) {
		if (refused || !map || (R && R.map === map)) return;
		dataUrl = map.getAttribute("data-sky-data"); reliefUrl = map.getAttribute("data-sky-relief");
		var svg = map.querySelector(".world-map-svg"), image = svg && svg.querySelector("image");
		if (!svg || !dataUrl || !reliefUrl || !image) return;
		var t0 = performance.now(), r = R;
		if (!r) {
			r = R = make(map);
			r.startedAt = t0;
			r.towns = [];
		}
		if (r.map && r.map !== map && r.map.isConnected) showSVG(r);
		r.map = map; r.svg = svg;
		r.still = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
		r.canvas.style.backgroundImage = "url(\"" + image.getAttribute("href") + "\")";
		map.insertBefore(r.canvas, svg);
		r.towns = Array.prototype.map.call(map.querySelectorAll(".world-map-town circle"), function (c) {
			return [parseFloat(c.getAttribute("cx")), parseFloat(c.getAttribute("cy"))];
		});
		fit(r);
		if (window.ResizeObserver) {
			if (!r.ro) r.ro = new ResizeObserver(function () { if (R && R.map) { fit(R); if (R.shown) { draw(R, performance.now()); start(R); } } });
			r.ro.disconnect(); r.ro.observe(svg);
		}
		if (r.io) { r.io.disconnect(); r.io.observe(r.canvas); }
		var fresh = !r.gl;
		if (fresh && !context(r)) { giveUp(r.software ? "software rendering" : "no WebGL2"); return; }
		loadAll().then(function () {
			if (R !== r || r.map !== map || refused) return;
			if (fresh && !setup(r)) { giveUp(r.software ? "software rendering" : "no WebGL2"); return; }
			r.readyAt = performance.now();
			if (r.shown) { hideSVG(r); start(r); } else firstFrames(r);
		}).catch(function (e) { giveUp(e && e.message || "failed"); });
	}

	function scan() {
		var map = document.querySelector(".world-map[data-sky-data]");
		if (map) attach(map);
		else if (R && R.map && !R.map.isConnected) R.running = false;
	}

	document.addEventListener("dk-map-shown", scan);
	document.addEventListener("dk-sky", function (ev) {
		var r = R, tick = ev.detail && ev.detail.tick;
		if (!r || !r.gl || !r.map || !r.map.isConnected) return;
		if (document.visibilityState === "hidden") { skyMissed = true; return; }
		if (tick != null && r.data && r.data.tick === tick) return;
		if (tick == null && !r.shown) return;   // (showSVG's own call for windows.js)
		loadSky().catch(function () { /* the next tick tries again */ });
	});
	document.addEventListener("visibilitychange", function () {
		var r = R;
		if (document.visibilityState !== "visible" || !r || !r.gl) return;
		if (skyMissed) { skyMissed = false; loadSky().catch(function () {}); }
		start(r);
	});
	window.addEventListener("resize", function () { if (R && R.map) fit(R); });
	scan();

	// for measuring and the browser test, where the server says test_routes (data-sky-test)
	if (document.querySelector(".world-map[data-sky-test]")) {
		window.DKSky = {
			info: function () {
				var r = R;
				return { refused: refused, shown: !!(r && r.shown), running: !!(r && r.running), level: r ? r.level : 0,
					frames: r ? r.frames : 0, renderer: r && r.renderer, width: r && r.canvas.width, height: r && r.canvas.height,
					compileMs: r && r.compileMs, firstMs: r && r.firstMs, skyMs: r && r.skyMs, fetches: r ? r.fetches : 0,
					tick: r && r.data && r.data.tick, firstFrameMs: r && r.firstFrameAt - r.startedAt, still: !!(r && r.still) };
			},
			// n frames back to back, each finished by the GPU: [ms, ...]
			bench: function (n) {
				var r = R, out = [], px = new Uint8Array(4), t = performance.now();
				for (var i = 0; i < n; i++) {
					var t0 = performance.now();
					draw(r, t + i * 33.3);
					r.gl.readPixels(0, 0, 1, 1, r.gl.RGBA, r.gl.UNSIGNED_BYTE, px);
					out.push(performance.now() - t0);
				}
				return out;
			},
			// a frame drawn now: how much of the canvas it covers (the mean alpha, 0 to 1)
			coverage: function () {
				var r = R, gl = r.gl, w = r.canvas.width, h = r.canvas.height, px = new Uint8Array(w * h * 4), sum = 0;
				draw(r, performance.now());
				gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
				for (var i = 3; i < px.length; i += 4) sum += px[i];
				return sum / (w * h * 255);
			},
			stats: function () { return R ? R.stats.slice() : []; },
			resetStats: function () { if (R) R.stats = []; },
			setLevel: function (f) { if (R) { R.forced = f; start(R); } },   // null: by what shows
			lose: function () { R.lost = R.gl.getExtension("WEBGL_lose_context"); R.lost.loseContext(); },
			restore: function () { R.lost.restoreContext(); },
			// the canvas alone over the whole viewport (CSS px), for measuring
			full: function (w, h) {
				var r = R;
				if (r.ro) r.ro.disconnect();
				var c = r.canvas, dpr = r.dpr || 1;
				c.style.position = "fixed"; c.style.left = "0"; c.style.top = "0"; c.style.zIndex = "2000";
				c.style.width = w + "px"; c.style.height = h + "px";
				c.width = Math.round(w * dpr); c.height = Math.round(h * dpr);
				r.rect = visibleRect(r);
			},
		};
	}
})();
