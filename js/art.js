'use strict';
// ============================================================
//  ARSON — arte procedural em alta resolução (100% original)
// ============================================================
function mk(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function lg(g, x0, y0, x1, y1, stops) { const gr = g.createLinearGradient(x0, y0, x1, y1); stops.forEach((s, i) => gr.addColorStop(s[0], s[1])); return gr; }
function rg(g, x, y, r0, x1, y1, r1, stops) { const gr = g.createRadialGradient(x, y, r0, x1, y1, r1); stops.forEach(s => gr.addColorStop(s[0], s[1])); return gr; }
function shade(hex, f) { // f>0 clareia, f<0 escurece
  const n = parseInt(hex.slice(1), 16); let r = n >> 16, g = (n >> 8) & 255, b = n & 255;
  if (f >= 0) { r += (255 - r) * f; g += (255 - g) * f; b += (255 - b) * f; } else { r *= 1 + f; g *= 1 + f; b *= 1 + f; }
  return `rgb(${r | 0},${g | 0},${b | 0})`;
}

// ------------------------------------------------------------
//  Terreno (pintado por pixel em blocos de 8x8 tiles)
// ------------------------------------------------------------
const GRD = new Uint8Array(W * H);
const DEPTH = new Float32Array(W * H);
(function prepTerreno() {
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const t = MAP[y * W + x];
    let g = t;
    if (t === T.TREE || t === T.FLOWER) g = T.GRASS;
    else if (t === T.DEADTREE) g = T.ASH;
    else if (t === T.WALL) g = T.STONE;
    else if (t === T.ROCK) { g = T.GRASS; for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) if (tileAt(x + dx, y + dy) === T.ASH || tileAt(x + dx, y + dy) === T.LAVA) g = T.ASH; }
    GRD[y * W + x] = g;
    DEPTH[y * W + x] = t === T.WATER ? 99 : 0;
  }
  for (let pass = 0; pass < 5; pass++) for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const k = y * W + x; if (DEPTH[k] === 0) continue;
    let m = 99;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const xx = x + dx, yy = y + dy; const v = (xx < 0 || yy < 0 || xx >= W || yy >= H) ? 4 : DEPTH[yy * W + xx]; if (v < m) m = v; }
    DEPTH[k] = Math.min(DEPTH[k], m + 1, 4);
  }
})();
const grdOf = (x, y) => (x < 0 || y < 0 || x >= W || y >= H) ? T.GRASS : GRD[y * W + x];
function depthAt(u, v) {
  u -= 0.5; v -= 0.5;
  const x = Math.floor(u), y = Math.floor(v), fx = u - x, fy = v - y;
  const d = (xx, yy) => (xx < 0 || yy < 0 || xx >= W || yy >= H) ? 4 : DEPTH[yy * W + xx];
  return lerp(lerp(d(x, y), d(x + 1, y), fx), lerp(d(x, y + 1), d(x + 1, y + 1), fx), fy);
}

let OR = 0, OG = 0, OB = 0;
function groundColor(u, v, ix, iy) {
  const tx = Math.floor(u), ty = Math.floor(v), t0 = tileAt(tx, ty);
  let t;
  if (t0 === T.STONE || t0 === T.WALL) t = T.STONE;
  else if (t0 === T.BRIDGE) t = T.BRIDGE;
  else {
    const jx = (vnoise(u * 1.6, v * 1.6, 91) - 0.5) * 0.34, jy = (vnoise(u * 1.6 + 33.3, v * 1.6 + 17.7, 92) - 0.5) * 0.34;
    const ux = Math.floor(u + jx), vy = Math.floor(v + jy), tt = tileAt(ux, vy);
    t = (tt === T.STONE || tt === T.WALL || tt === T.BRIDGE) ? grdOf(tx, ty) : grdOf(ux, vy);
  }
  const hh = hash2(ix, iy, 5);
  const P = vnoise(u / 3.5, v / 3.5, 61);
  let r, g, b, s;
  switch (t) {
    case T.SAND: {
      r = 206; g = 186; b = 136;
      const rip = Math.sin((v + u * 0.3 + vnoise(u * 1.5, v * 1.5, 70) * 1.2) * 18) * 0.04;
      s = 0.95 + rip + (hh - 0.5) * 0.14 + (P - 0.5) * 0.12;
      break;
    }
    case T.PATH: {
      r = 124; g = 95; b = 62;
      s = 0.9 + (vnoise(u * 3, v * 3, 71) - 0.5) * 0.3 + (hh - 0.5) * 0.18;
      const cxp = Math.floor(u * 7), cyp = Math.floor(v * 7), hp = hash2(cxp, cyp, 72);
      if (hp < 0.18) {
        const ox = (0.3 + hash2(cxp, cyp, 73) * 0.4), oy = (0.3 + hash2(cxp, cyp, 74) * 0.4);
        const dx = u * 7 - cxp - ox, dy = v * 7 - cyp - oy, dd = Math.hypot(dx, dy);
        if (dd < 0.24) { r = 150; g = 142; b = 128; s = 0.85 + (-dy) * 1.2 + (hh - 0.5) * 0.1; }
        else if (dd < 0.32 && dy > 0) s *= 0.75;
      }
      break;
    }
    case T.STONE: {
      const row = Math.floor(v * 3), fy = v * 3 - row, cf = u * 2 + (row & 1) * 0.5, col = Math.floor(cf), fx = cf - col;
      const e = Math.min(Math.min(fx, 1 - fx) * 32, Math.min(fy, 1 - fy) * 21.3);
      const hb = hash2(col, row, 73);
      if (e < 1.7) { r = 72; g = 68; b = 62; s = 0.9 + hh * 0.2; }
      else {
        r = 150 + hb * 22; g = 144 + hb * 18; b = 132 + hb * 10;
        s = 0.92 + (hh - 0.5) * 0.14 + (vnoise(u * 6, v * 6, 76) - 0.5) * 0.18;
        if (fx < 0.1 || fy < 0.12) s += 0.12; else if (fx > 0.9 || fy > 0.86) s -= 0.16;
      }
      break;
    }
    case T.ASH: {
      r = 70; g = 62; b = 58;
      s = 0.85 + (vnoise(u * 2, v * 2, 74) - 0.5) * 0.35 + (hh - 0.5) * 0.15;
      const cr = Math.abs(vnoise(u * 1.3, v * 1.3, 75) - 0.5);
      if (cr < 0.02) { const k = 1 - cr / 0.02; r = lerp(r * s, 255, k); g = lerp(g * s, 120, k); b = lerp(b * s, 30, k); s = 1; }
      else if (cr < 0.05) s *= 0.78;
      if (hh < 0.0015) { r = 255; g = 150; b = 50; s = 1; }
      break;
    }
    case T.WATER: {
      const d = depthAt(u, v), k = clamp(d / 3, 0, 1);
      r = lerp(66, 20, k); g = lerp(148, 56, k); b = lerp(152, 104, k);
      s = 0.92 + vnoise(u * 3.2, v * 3.2, 76) * 0.16;
      if (d < 0.6) {
        const f = (0.6 - d) / 0.6 * (0.45 + vnoise(u * 7, v * 7, 77) * 0.55);
        r = lerp(r, 235, f * 0.6); g = lerp(g, 245, f * 0.6); b = lerp(b, 240, f * 0.6);
      }
      break;
    }
    case T.LAVA: {
      const m = fbm(u * 0.9, v * 0.9, 78), mol = clamp((m - 0.42) / 0.16, 0, 1);
      const cr0 = 58 * (0.8 + hh * 0.3), cg0 = 22 * (0.8 + hh * 0.3), cb0 = 14;
      const q = vnoise(u * 2.5, v * 2.5, 79);
      let mr = 232 + 23 * q, mg = 70 + 130 * q, mb = 10 + 60 * q;
      if (Math.abs(vnoise(u * 3, v * 3, 80) - 0.5) < 0.04) { mr = 255; mg = 240; mb = 150; }
      r = lerp(cr0, mr, mol); g = lerp(cg0, mg, mol); b = lerp(cb0, mb, mol); s = 1;
      break;
    }
    case T.BRIDGE: {
      const fu = u - tx, fv = v - ty;
      const horiz = [T.BRIDGE, T.PATH].includes(tileAt(tx - 1, ty)) || [T.BRIDGE, T.PATH].includes(tileAt(tx + 1, ty));
      const along = horiz ? fu : fv, across = horiz ? fv : fu;
      const pl = Math.floor(along * 4.5), pf = along * 4.5 - pl, hp = hash2(pl + tx * 9, ty * 7 + (horiz ? 1 : 0), 81);
      r = 124; g = 86; b = 52;
      s = 0.82 + hp * 0.25 + Math.sin(across * 40 + vnoise(u * 4, v * 4, 82) * 6) * 0.05 + (hh - 0.5) * 0.08;
      if (pf < 0.07) s = 0.35;
      if (across < 0.07 || across > 0.93) s *= 0.55;
      break;
    }
    default: { // grama
      const m = vnoise(u * 0.7, v * 0.7, 62);
      r = lerp(50, 98, m * m); g = lerp(102, 130, m); b = lerp(36, 56, m);
      const blade = vnoise(u * 28, v * 7, 63), clump = vnoise(u * 4, v * 4, 64);
      s = 0.78 + blade * 0.34 + (clump - 0.5) * 0.26 + (hh - 0.5) * 0.12;
    }
  }
  s *= 0.93 + 0.14 * P;
  OR = r * s; OG = g * s; OB = b * s;
}

const CH = 8, CPX = CH * TS;
const chunkCache = new Map();
function chunkKey(cx, cy) { return cx * 1000 + cy; }
let CQ = 1; // resolução do chão (1 = cheia, 0.5 = metade)
function buildChunk(cx, cy) {
  const N = Math.round(CPX * CQ), pt = TS * CQ;
  const c = mk(N, N), g = c.getContext('2d');
  const img = g.createImageData(N, N), d = img.data;
  const bx = cx * CH, by = cy * CH;
  let i = 0;
  for (let py = 0; py < N; py++) {
    const v = by + (py + 0.5) / pt;
    for (let px = 0; px < N; px++) {
      groundColor(bx + (px + 0.5) / pt, v, cx * N + px, cy * N + py);
      d[i] = OR; d[i + 1] = OG; d[i + 2] = OB; d[i + 3] = 255; i += 4;
    }
  }
  g.putImageData(img, 0, 0);
  g.scale(CQ, CQ);
  // detalhes
  for (let ty = by; ty < by + CH; ty++) for (let tx = bx; tx < bx + CH; tx++) {
    const t = tileAt(tx, ty), ox = (tx - bx) * TS, oy = (ty - by) * TS, r = prng(tx * 7919 + ty * 104729 + 1);
    if (t === T.FLOWER) {
      for (let k = 0; k < 9; k++) flower(g, ox + 6 + r() * 52, oy + 6 + r() * 52, ['#ffd84a', '#ff6f91', '#ffffff', '#ff9a3a', '#b48cff'][Math.floor(r() * 5)], r);
    } else if (GRD[ty * W + tx] === T.GRASS && t !== T.TREE && r() < 0.45) {
      for (let k = 0, n = 1 + Math.floor(r() * 3); k < n; k++) tuft(g, ox + 8 + r() * 48, oy + 12 + r() * 46, r);
    } else if (t === T.ASH && r() < 0.25) {
      pebble(g, ox + 10 + r() * 44, oy + 10 + r() * 44, 3 + r() * 4, '#2e2826', r);
    } else if (t === T.SAND && r() < 0.15) {
      shell(g, ox + 10 + r() * 44, oy + 10 + r() * 44, r);
    }
    // sombra projetada pela muralha
    if (tileAt(tx, ty - 1) === T.WALL && t !== T.WALL) { g.fillStyle = lg(g, 0, oy, 0, oy + 26, [[0, 'rgba(0,0,0,.4)'], [1, 'rgba(0,0,0,0)']]); g.fillRect(ox, oy, TS, 26); }
  }
  return c;
}
function flower(g, x, y, col, r) {
  g.fillStyle = 'rgba(30,70,20,.7)';
  g.beginPath(); g.ellipse(x + 3, y + 3, 4, 2, r() * 3, 0, 7); g.fill();
  g.fillStyle = col;
  for (let p = 0; p < 5; p++) { const a = p / 5 * Math.PI * 2 + r(); g.beginPath(); g.arc(x + Math.cos(a) * 2.6, y + Math.sin(a) * 2.6, 2.1, 0, 7); g.fill(); }
  g.fillStyle = '#ffe9a0'; g.beginPath(); g.arc(x, y, 1.4, 0, 7); g.fill();
}
function tuft(g, x, y, r) {
  g.lineCap = 'round';
  for (let k = 0; k < 7; k++) {
    const a = -Math.PI / 2 + (r() - 0.5) * 1.3, l = 6 + r() * 8;
    g.strokeStyle = r() < 0.5 ? 'rgba(40,82,28,.85)' : 'rgba(120,160,70,.75)';
    g.lineWidth = 1.2;
    g.beginPath(); g.moveTo(x + (r() - 0.5) * 5, y); g.quadraticCurveTo(x + Math.cos(a) * l * 0.5, y + Math.sin(a) * l * 0.6, x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
  }
}
function pebble(g, x, y, s, col, r) {
  g.fillStyle = 'rgba(0,0,0,.3)'; g.beginPath(); g.ellipse(x + 1, y + 1.5, s, s * 0.7, 0, 0, 7); g.fill();
  g.fillStyle = col; g.beginPath(); g.ellipse(x, y, s, s * 0.7, r() * 3, 0, 7); g.fill();
  g.fillStyle = 'rgba(255,255,255,.12)'; g.beginPath(); g.ellipse(x - s * 0.3, y - s * 0.25, s * 0.45, s * 0.3, 0, 0, 7); g.fill();
}
function shell(g, x, y, r) {
  g.fillStyle = '#efe2c8'; g.beginPath(); g.ellipse(x, y, 3, 2.2, r() * 3, 0, 7); g.fill();
  g.strokeStyle = 'rgba(150,120,90,.6)'; g.lineWidth = 0.6; g.stroke();
}
let chunkQueue = [];
function getChunk(cx, cy) {
  const k = chunkKey(cx, cy);
  const c = chunkCache.get(k);
  if (c) { chunkCache.delete(k); chunkCache.set(k, c); return c; }
  if (!chunkQueue.includes(k)) chunkQueue.push(k);
  return null;
}
function pumpChunks(budgetMs, force) {
  const t0 = performance.now();
  while (chunkQueue.length && (force || performance.now() - t0 < budgetMs)) {
    const k = chunkQueue.shift(), cx = Math.floor(k / 1000), cy = k % 1000;
    if (!chunkCache.has(k)) chunkCache.set(k, buildChunk(cx, cy));
    while (chunkCache.size > 70) chunkCache.delete(chunkCache.keys().next().value);
    if (!force) break;
  }
}

// ------------------------------------------------------------
//  Objetos do cenário
// ------------------------------------------------------------
function makeBroadleaf(seed, pal) {
  const c = mk(200, 232), g = c.getContext('2d'), r = prng(seed);
  // tronco
  g.fillStyle = lg(g, 86, 0, 114, 0, [[0, '#2a1a0e'], [0.45, '#6e4c2d'], [1, '#22150b']]);
  g.beginPath(); g.moveTo(82, 218); g.quadraticCurveTo(93, 204, 92, 150); g.lineTo(90, 100); g.lineTo(110, 100); g.lineTo(108, 150); g.quadraticCurveTo(107, 204, 120, 218); g.closePath(); g.fill();
  g.strokeStyle = 'rgba(18,10,4,.55)'; g.lineWidth = 1.3;
  for (let i = 0; i < 6; i++) { const x = 94 + r() * 12; g.beginPath(); g.moveTo(x, 214); g.quadraticCurveTo(x + (r() - 0.5) * 6, 170, x + (r() - 0.5) * 4, 110); g.stroke(); }
  // galhos
  g.strokeStyle = '#4a321c'; g.lineCap = 'round';
  for (let i = 0; i < 4; i++) { g.lineWidth = 5 - i; g.beginPath(); g.moveTo(100, 140 - i * 10); g.quadraticCurveTo(100 + (i % 2 ? 1 : -1) * 20, 115 - i * 8, 100 + (i % 2 ? 1 : -1) * (36 + r() * 10), 100 - i * 10); g.stroke(); }
  // sombra interna da copa
  g.fillStyle = pal[0];
  g.beginPath(); g.ellipse(100, 92, 80, 64, 0, 0, 7); g.fill();
  const cl = [];
  for (let i = 0; i < 120; i++) {
    const a = r() * Math.PI * 2, rad = Math.sqrt(r());
    cl.push({ x: 100 + Math.cos(a) * rad * 70, y: 90 + Math.sin(a) * rad * 54, s: 11 + r() * 15 });
  }
  cl.sort((a, b) => a.y - b.y);
  for (const q of cl) {
    const lf = clamp(0.62 - (q.y - 90) / 54 * 0.42 - (q.x - 100) / 70 * 0.22 + (r() - 0.5) * 0.15, 0, 1);
    const c1 = lf > 0.66 ? pal[3] : lf > 0.4 ? pal[2] : pal[1];
    g.fillStyle = rg(g, q.x - q.s * 0.35, q.y - q.s * 0.4, 1, q.x, q.y, q.s, [[0, shade(c1, 0.18)], [0.6, c1], [1, shade(c1, -0.35)]]);
    g.beginPath(); g.arc(q.x, q.y, q.s, 0, 7); g.fill();
  }
  // brilhos de folhas
  for (let i = 0; i < 90; i++) {
    const a = r() * Math.PI * 2, rad = Math.sqrt(r()) * 0.9;
    const x = 100 + Math.cos(a) * rad * 70, y = 90 + Math.sin(a) * rad * 54;
    if (y - 90 > 20 && r() < 0.7) continue;
    g.fillStyle = `rgba(230,255,170,${0.15 + r() * 0.25})`;
    g.beginPath(); g.ellipse(x, y, 2.5, 1.4, r() * 3, 0, 7); g.fill();
  }
  return { c, ax: 100, ay: 216 };
}
function makePine(seed) {
  const c = mk(160, 250), g = c.getContext('2d'), r = prng(seed);
  g.fillStyle = lg(g, 72, 0, 88, 0, [[0, '#2a1a0e'], [0.5, '#5e3f24'], [1, '#22150b']]);
  g.fillRect(73, 190, 14, 46);
  const tiers = 5;
  for (let i = 0; i < tiers; i++) {
    const yb = 206 - i * 34, w = 70 - i * 11, top = yb - 58;
    g.fillStyle = lg(g, 80 - w, 0, 80 + w, 0, [[0, '#4f8a3a'], [0.45, '#2f6427'], [1, '#173a17']]);
    g.beginPath(); g.moveTo(80, top);
    const n = 9;
    for (let k = 0; k <= n; k++) { const x = 80 + w - (2 * w) * k / n, y = yb + (k % 2 ? -8 : 2) + (r() - 0.5) * 4; g.lineTo(x, y); }
    g.closePath(); g.fill();
    g.strokeStyle = 'rgba(0,0,0,.25)'; g.lineWidth = 1; g.stroke();
    g.fillStyle = 'rgba(200,255,160,.12)';
    for (let k = 0; k < 10; k++) { g.beginPath(); g.ellipse(80 - w * 0.5 + r() * w * 0.6, yb - 10 - r() * 40, 3, 1.3, -0.6, 0, 7); g.fill(); }
  }
  return { c, ax: 80, ay: 234 };
}
function makeDeadTree(seed) {
  const c = mk(170, 220), g = c.getContext('2d'), r = prng(seed);
  g.lineCap = 'round';
  const tips = [];
  function br(x, y, a, len, w, d) {
    const x2 = x + Math.cos(a) * len, y2 = y + Math.sin(a) * len;
    g.strokeStyle = d < 2 ? '#1c1614' : '#2a211d'; g.lineWidth = w;
    g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo((x + x2) / 2 + (r() - 0.5) * 8, (y + y2) / 2, x2, y2); g.stroke();
    if (d >= 4 || len < 8) { tips.push([x2, y2]); return; }
    br(x2, y2, a - 0.35 - r() * 0.4, len * (0.62 + r() * 0.15), w * 0.62, d + 1);
    br(x2, y2, a + 0.35 + r() * 0.4, len * (0.62 + r() * 0.15), w * 0.62, d + 1);
  }
  g.fillStyle = 'rgba(0,0,0,0)';
  br(85, 214, -Math.PI / 2 + (r() - 0.5) * 0.2, 64, 13, 0);
  g.strokeStyle = 'rgba(255,255,255,.06)'; g.lineWidth = 2; g.beginPath(); g.moveTo(82, 210); g.lineTo(81, 160); g.stroke();
  for (const [x, y] of tips) if (r() < 0.3) {
    g.fillStyle = rg(g, x, y, 0, x, y, 6, [[0, 'rgba(255,200,80,.9)'], [1, 'rgba(255,90,20,0)']]); g.beginPath(); g.arc(x, y, 6, 0, 7); g.fill();
  }
  for (let i = 0; i < 6; i++) { g.fillStyle = 'rgba(255,110,30,.8)'; g.fillRect(80 + (r() - 0.5) * 8, 150 + r() * 60, 1.5, 3); }
  return { c, ax: 85, ay: 216 };
}
function makeRock(seed, ash) {
  const c = mk(110, 96), g = c.getContext('2d'), r = prng(seed);
  const pts = [], n = 9;
  for (let i = 0; i < n; i++) { const a = i / n * Math.PI * 2, rad = 34 + r() * 10; pts.push([55 + Math.cos(a) * rad, 58 + Math.sin(a) * rad * 0.62 - (Math.sin(a) < 0 ? 10 : 0)]); }
  const base = ash ? ['#4a4442', '#2a2524', '#171313'] : ['#a6a29a', '#77736c', '#4b4844'];
  g.fillStyle = 'rgba(0,0,0,.35)'; g.beginPath(); g.ellipse(58, 78, 42, 13, 0, 0, 7); g.fill();
  g.beginPath(); pts.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.closePath();
  g.fillStyle = lg(g, 25, 25, 85, 85, [[0, base[0]], [0.55, base[1]], [1, base[2]]]); g.fill();
  g.save(); g.clip();
  // facetas
  for (let i = 0; i < 5; i++) {
    g.fillStyle = `rgba(0,0,0,${0.08 + r() * 0.12})`;
    g.beginPath(); g.moveTo(40 + r() * 30, 30 + r() * 20); g.lineTo(20 + r() * 70, 80); g.lineTo(30 + r() * 60, 85); g.closePath(); g.fill();
  }
  g.fillStyle = 'rgba(255,255,255,.16)'; g.beginPath(); g.ellipse(45, 38, 22, 9, -0.3, 0, 7); g.fill();
  if (!ash) { for (let i = 0; i < 40; i++) { g.fillStyle = `rgba(${70 + r() * 30},${110 + r() * 40},50,${0.4 + r() * 0.4})`; g.beginPath(); g.arc(30 + r() * 50, 30 + r() * 14, 2 + r() * 3, 0, 7); g.fill(); } }
  else { g.strokeStyle = '#ff7a1a'; g.lineWidth = 1.5; g.shadowColor = '#ff5a00'; g.shadowBlur = 6; g.beginPath(); g.moveTo(40, 45); g.lineTo(52, 60); g.lineTo(48, 75); g.moveTo(52, 60); g.lineTo(68, 64); g.stroke(); g.shadowBlur = 0; }
  g.restore();
  g.strokeStyle = 'rgba(0,0,0,.45)'; g.lineWidth = 1.5;
  g.beginPath(); pts.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.closePath(); g.stroke();
  return { c, ax: 55, ay: 80 };
}
const TREES = [
  makeBroadleaf(11, ['#12300f', '#245a1d', '#3d7f2c', '#68a843']),
  makeBroadleaf(23, ['#10280e', '#1e4d1a', '#326b26', '#57923a']),
  makeBroadleaf(37, ['#2a2a0e', '#4d5a1c', '#6f7f2c', '#a3a846']),
  makePine(41), makePine(53),
];
const DEADTREES = [makeDeadTree(7), makeDeadTree(19), makeDeadTree(31)];
const ROCKS = [makeRock(3, false), makeRock(9, false), makeRock(5, true), makeRock(14, true)];

// Muralha
const WALLH = 44;
const WALL_TOP = (() => {
  const c = mk(TS, TS), g = c.getContext('2d'), r = prng(99);
  g.fillStyle = '#8f8676'; g.fillRect(0, 0, TS, TS);
  for (let row = 0; row < 4; row++) for (let col = 0; col < 3; col++) {
    const x = col * 22 + (row % 2) * 11 - 6, y = row * 16;
    g.fillStyle = shade('#a49a88', (r() - 0.5) * 0.25); g.fillRect(x + 1, y + 1, 20, 14);
    g.fillStyle = 'rgba(255,255,255,.12)'; g.fillRect(x + 1, y + 1, 20, 2);
  }
  return c;
})();
const WALL_FRONT = (() => {
  const c = mk(TS, WALLH), g = c.getContext('2d'), r = prng(77);
  g.fillStyle = '#4a4036'; g.fillRect(0, 0, TS, WALLH);
  for (let row = 0; row < 4; row++) for (let col = -1; col < 4; col++) {
    const x = col * 24 + (row % 2) * 12, y = row * 11;
    g.fillStyle = lg(g, 0, y, 0, y + 10, [[0, shade('#7a6d5c', (r() - 0.5) * 0.3)], [1, shade('#5a4e40', (r() - 0.5) * 0.2)]]);
    g.fillRect(x + 1, y + 1, 22, 9);
  }
  g.fillStyle = lg(g, 0, 0, 0, WALLH, [[0, 'rgba(0,0,0,0)'], [1, 'rgba(0,0,0,.35)']]); g.fillRect(0, 0, TS, WALLH);
  return c;
})();

// Adereços
function makeProp(k) {
  if (k === 'barril') {
    const c = mk(40, 50), g = c.getContext('2d');
    g.fillStyle = 'rgba(0,0,0,.3)'; g.beginPath(); g.ellipse(20, 46, 15, 4, 0, 0, 7); g.fill();
    g.fillStyle = lg(g, 6, 0, 34, 0, [[0, '#4a2e17'], [0.4, '#8a5a30'], [1, '#3a2312']]);
    g.beginPath(); g.moveTo(8, 12); g.quadraticCurveTo(3, 28, 8, 44); g.lineTo(32, 44); g.quadraticCurveTo(37, 28, 32, 12); g.closePath(); g.fill();
    g.strokeStyle = '#2a2a2a'; g.lineWidth = 2.5; for (const y of [17, 38]) { g.beginPath(); g.moveTo(6, y); g.lineTo(34, y); g.stroke(); }
    g.fillStyle = '#6e4626'; g.beginPath(); g.ellipse(20, 12, 12, 4, 0, 0, 7); g.fill(); g.strokeStyle = '#2a2a2a'; g.lineWidth = 2; g.stroke();
    return { c, ax: 20, ay: 46 };
  }
  if (k === 'caixa') {
    const c = mk(46, 48), g = c.getContext('2d');
    g.fillStyle = 'rgba(0,0,0,.3)'; g.fillRect(6, 40, 36, 6);
    g.fillStyle = '#9a6e40'; g.fillRect(5, 6, 36, 10);
    g.fillStyle = lg(g, 0, 16, 0, 44, [[0, '#7e5632'], [1, '#5a3c22']]); g.fillRect(5, 16, 36, 28);
    g.strokeStyle = '#3a2614'; g.lineWidth = 2; g.strokeRect(5, 6, 36, 38); g.beginPath(); g.moveTo(5, 16); g.lineTo(41, 16); g.moveTo(5, 44); g.lineTo(41, 16); g.stroke();
    return { c, ax: 23, ay: 44 };
  }
  if (k === 'braseiro') {
    const c = mk(40, 56), g = c.getContext('2d');
    g.fillStyle = 'rgba(0,0,0,.35)'; g.beginPath(); g.ellipse(20, 52, 13, 4, 0, 0, 7); g.fill();
    g.strokeStyle = '#2b2b2e'; g.lineWidth = 3; g.beginPath(); g.moveTo(12, 52); g.lineTo(18, 30); g.moveTo(28, 52); g.lineTo(22, 30); g.moveTo(20, 52); g.lineTo(20, 30); g.stroke();
    g.fillStyle = lg(g, 6, 0, 34, 0, [[0, '#2a2a2e'], [0.4, '#6a6a72'], [1, '#1e1e22']]);
    g.beginPath(); g.moveTo(5, 22); g.quadraticCurveTo(20, 38, 35, 22); g.closePath(); g.fill();
    g.fillStyle = '#ff8a2a'; g.beginPath(); g.ellipse(20, 22, 14, 3.5, 0, 0, 7); g.fill();
    return { c, ax: 20, ay: 52, fire: [20, 18, 1] };
  }
  if (k === 'banca') {
    const c = mk(150, 130), g = c.getContext('2d');
    g.fillStyle = 'rgba(0,0,0,.3)'; g.fillRect(10, 112, 130, 12);
    g.fillStyle = '#4a2e17'; g.fillRect(14, 30, 6, 90); g.fillRect(130, 30, 6, 90);
    g.fillStyle = lg(g, 0, 70, 0, 118, [[0, '#8a5a30'], [1, '#4a2e17']]); g.fillRect(8, 74, 134, 44);
    g.fillStyle = '#a87444'; g.fillRect(6, 68, 138, 10);
    // toldo listrado
    for (let i = 0; i < 9; i++) { g.fillStyle = i % 2 ? '#e9dcc0' : '#b3261e'; g.beginPath(); g.moveTo(4 + i * 15.8, 10); g.lineTo(4 + (i + 1) * 15.8, 10); g.lineTo(4 + (i + 1) * 15.8, 36); g.quadraticCurveTo(4 + (i + 0.5) * 15.8, 44, 4 + i * 15.8, 36); g.closePath(); g.fill(); }
    g.fillStyle = 'rgba(0,0,0,.2)'; g.fillRect(4, 10, 142, 6);
    // poções na mesa
    const cols = ['#d8322a', '#3a7bff', '#d8322a', '#3a7bff', '#3fd34a'];
    cols.forEach((cc, i) => { const x = 26 + i * 22; g.fillStyle = 'rgba(255,255,255,.25)'; g.fillRect(x + 3, 50, 4, 6); g.fillStyle = cc; g.beginPath(); g.arc(x + 5, 62, 7, 0, 7); g.fill(); g.fillStyle = 'rgba(255,255,255,.5)'; g.beginPath(); g.arc(x + 3, 60, 2, 0, 7); g.fill(); g.fillStyle = '#6b4422'; g.fillRect(x + 3, 47, 4, 4); });
    return { c, ax: 75, ay: 118 };
  }
  if (k === 'altar') {
    const c = mk(90, 100), g = c.getContext('2d');
    g.fillStyle = 'rgba(0,0,0,.3)'; g.beginPath(); g.ellipse(45, 92, 38, 8, 0, 0, 7); g.fill();
    g.fillStyle = lg(g, 10, 0, 80, 0, [[0, '#cfc6b4'], [0.5, '#a49a88'], [1, '#6e665a']]); g.fillRect(12, 50, 66, 42);
    g.fillStyle = '#d9d0be'; g.fillRect(6, 42, 78, 10);
    g.fillStyle = '#b07a1e'; g.fillRect(36, 58, 18, 18); g.fillStyle = '#ffd23a'; g.beginPath(); g.moveTo(45, 60); g.lineTo(52, 74); g.lineTo(38, 74); g.closePath(); g.fill();
    g.fillStyle = '#3a3a40'; g.beginPath(); g.moveTo(28, 30); g.quadraticCurveTo(45, 46, 62, 30); g.closePath(); g.fill();
    for (const x of [14, 76]) { g.fillStyle = '#f2ead6'; g.fillRect(x - 3, 28, 6, 14); }
    return { c, ax: 45, ay: 92, fire: [45, 26, 1.2], candles: [[14, 26], [76, 26]] };
  }
}
const PROPART = {};
for (const k of ['barril', 'caixa', 'braseiro', 'banca', 'altar']) PROPART[k] = makeProp(k);

// ------------------------------------------------------------
//  Fogo (desenhado ao vivo)
// ------------------------------------------------------------
function flame(g, x, y, s, t, seed) {
  const f = Math.sin(t * 11 + seed) * 0.12 + Math.sin(t * 17 + seed * 3) * 0.08;
  const prev = g.globalCompositeOperation;
  g.globalCompositeOperation = 'lighter';
  const layers = [['rgba(200,40,10,.55)', 1], ['rgba(255,120,20,.7)', 0.72], ['rgba(255,220,120,.85)', 0.42]];
  for (const [col, k] of layers) {
    const w = 9 * s * k, h = 22 * s * k * (1 + f);
    g.fillStyle = col;
    g.beginPath();
    g.moveTo(x - w, y);
    g.quadraticCurveTo(x - w * 1.1, y - h * 0.5, x + Math.sin(t * 7 + seed) * 3 * s, y - h);
    g.quadraticCurveTo(x + w * 1.1, y - h * 0.5, x + w, y);
    g.quadraticCurveTo(x, y + w * 0.6, x - w, y);
    g.fill();
  }
  g.globalCompositeOperation = prev;
}

// ------------------------------------------------------------
//  Personagens humanos (vetorial, com sombreamento)
// ------------------------------------------------------------
const LOOKS = {
  guerreiro: { type: 'human', skin: '#e2b48c', hair: '#5a3a1e', top: '#9aa4ae', armor: true, trim: '#b3261e', pants: '#3b3f4a', boots: '#2e2218', cape: '#9e1f18', hat: 'helmet', weapon: 'sword', shield: true },
  mago: { type: 'human', skin: '#e2b48c', hair: '#dcdcdc', top: '#4d2a86', robe: true, trim: '#e8c33a', pants: '#2e1a52', boots: '#2e2218', hat: 'wizard', hatCol: '#3e2270', beard: '#e6e6e6', weapon: 'staff' },
  arqueiro: { type: 'human', skin: '#d9a77c', hair: '#6b4422', top: '#7a5230', trim: '#2f6b2a', pants: '#4a3a28', boots: '#3a2a1a', cape: '#2c5e27', hat: 'hood', hatCol: '#2f6b2a', weapon: 'bow', quiver: true },
  mercador: { type: 'human', skin: '#e2b48c', hair: '#4a2e17', top: '#2a5c9a', apron: '#d9c08a', trim: '#1e4170', pants: '#3b3f4a', boots: '#2e2218', hat: 'none', beard: '#4a2e17', mustache: true },
  sacerdotisa: { type: 'human', skin: '#efc6a0', hair: '#f2d06b', long: true, top: '#efeadf', robe: true, trim: '#ff8a2a', pants: '#efeadf', boots: '#a08a60', hat: 'circlet' },
  goblin: { type: 'human', skin: '#6aa33a', hair: '#2a3a10', top: '#6b4422', trim: '#4a2e17', pants: '#5a3a1e', boots: '#3a2a1a', hat: 'ears', weapon: 'torch', scale: 0.82, bare: true },
  rato: { type: 'quad', len: 30, h: 13, leg: 7, head: 7, col: '#6e6862', belly: '#9a928a', tail: 'thin', tailCol: '#c99a92', ear: 'round', earCol: '#d9a0a0', eye: '#ff3b2e', embers: true },
  javali: { type: 'quad', len: 48, h: 26, leg: 12, head: 12, col: '#5e4029', belly: '#7a5a3e', tail: 'curl', tailCol: '#4a3220', ear: 'point', earCol: '#4a3220', eye: '#140c08', tusks: true, bristle: true, embers: true },
  lobo: { type: 'quad', len: 50, h: 20, leg: 17, head: 10, col: '#3e3e44', belly: '#6a6a72', tail: 'bushy', tailCol: '#34343a', ear: 'point', earCol: '#2a2a2e', eye: '#ffb02e', glowEye: true, ruff: true },
  salamandra: { type: 'quad', len: 58, h: 12, leg: 6, head: 9, col: '#d4521a', belly: '#ffb03a', tail: 'lizard', tailCol: '#c4461a', ear: 'none', eye: '#1a0a04', spots: '#5a1a08', lizard: true },
  golem: { type: 'golem' },
  arson: { type: 'boss' },
  boneco: { type: 'dummy' },
};
function drawDummy(g, atk) {
  const tilt = atk ? Math.sin(atk * Math.PI) * 0.18 : 0;
  g.fillStyle = 'rgba(0,0,0,.2)'; g.beginPath(); g.ellipse(0, -1, 10, 3, 0, 0, 7); g.fill();
  g.fillStyle = lg(g, -3, 0, 3, 0, [[0, '#5e3f24'], [1, '#2e1d10']]); g.fillRect(-3, -40, 6, 40);
  g.strokeStyle = OUT; g.lineWidth = 1; g.strokeRect(-3, -40, 6, 40);
  g.save(); g.translate(0, -30); g.rotate(tilt);
  // braços (travessa)
  g.fillStyle = lg(g, 0, -34, 0, -28, [[0, '#7a5230'], [1, '#4a2e17']]); g.fillRect(-24, -34, 48, 6); g.strokeRect(-24, -34, 48, 6);
  for (const sx of [-1, 1]) { g.strokeStyle = '#d9b860'; g.lineWidth = 2; for (let i = 0; i < 4; i++) { g.beginPath(); g.moveTo(sx * 24, -33 + i * 1.5); g.lineTo(sx * (28 + i), -35 + i * 3); g.stroke(); } }
  // corpo de palha
  g.fillStyle = lg(g, -14, 0, 14, 0, [[0, '#e8cc78'], [0.5, '#c9a64e'], [1, '#8a6e2a']]);
  g.beginPath(); g.ellipse(0, -18, 14, 20, 0, 0, 7); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.3; g.stroke();
  g.strokeStyle = 'rgba(120,90,30,.6)'; g.lineWidth = 1; for (let i = 0; i < 9; i++) { g.beginPath(); g.moveTo(-10 + i * 2.5, -34); g.lineTo(-11 + i * 2.6, -2); g.stroke(); }
  g.strokeStyle = '#6b4422'; g.lineWidth = 2.5; g.beginPath(); g.moveTo(-13, -24); g.lineTo(13, -24); g.moveTo(-12, -10); g.lineTo(12, -10); g.stroke();
  // alvo no peito
  for (const [r, c] of [[8, '#e8e2d0'], [5.5, '#b3261e'], [3, '#e8e2d0'], [1.4, '#b3261e']]) { g.fillStyle = c; g.beginPath(); g.arc(0, -18, r, 0, 7); g.fill(); }
  // cabeça de saco
  g.fillStyle = rg(g, -3, -48, 1, 0, -45, 11, [[0, '#e6d6b0'], [1, '#a8936a']]); g.beginPath(); g.arc(0, -45, 10, 0, 7); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.3; g.stroke();
  g.strokeStyle = '#3a2a1a'; g.lineWidth = 1.8;
  for (const ex of [-4, 4]) { g.beginPath(); g.moveTo(ex - 2, -48); g.lineTo(ex + 2, -44); g.moveTo(ex + 2, -48); g.lineTo(ex - 2, -44); g.stroke(); }
  g.beginPath(); g.moveTo(-4, -40); g.lineTo(4, -40); g.stroke();
  g.strokeStyle = '#8a6e2a'; g.lineWidth = 2; g.beginPath(); g.moveTo(-5, -54); g.lineTo(-7, -59); g.moveTo(0, -55); g.lineTo(0, -60); g.moveTo(5, -54); g.lineTo(7, -59); g.stroke();
  g.restore();
}

function limb(g, x1, y1, x2, y2, w, col, out) {
  g.lineCap = 'round';
  if (out !== false) { g.strokeStyle = 'rgba(15,10,8,.85)'; g.lineWidth = w + 2.4; g.beginPath(); g.moveTo(x1, y1); g.lineTo(x2, y2); g.stroke(); }
  g.strokeStyle = col; g.lineWidth = w; g.beginPath(); g.moveTo(x1, y1); g.lineTo(x2, y2); g.stroke();
}
function ell(g, x, y, rx, ry, fill, stroke) { g.beginPath(); g.ellipse(x, y, rx, ry, 0, 0, 7); g.fillStyle = fill; g.fill(); if (stroke) { g.strokeStyle = stroke; g.lineWidth = 1.2; g.stroke(); } }
const OUT = 'rgba(15,10,8,.85)';

function drawHuman(g, L, dir, ph, atk) {
  const side = dir === 1, up = dir === 0, down = dir === 2;
  const sw = Math.sin(ph * Math.PI * 2), moving = ph > 0;
  const bob = moving ? -Math.abs(Math.cos(ph * Math.PI * 2)) * 2 : 0;
  g.save(); g.translate(0, bob);
  const hipY = -25, shY = -46, headY = -58;
  const legCol = L.pants, bootCol = L.boots;
  // ---- itens de trás
  const drawCape = () => { if (!L.cape) return; g.fillStyle = lg(g, -16, 0, 16, 0, [[0, shade(L.cape, -0.35)], [0.5, L.cape], [1, shade(L.cape, -0.45)]]); g.beginPath(); g.moveTo(-12, shY); g.lineTo(12, shY); g.lineTo(15 + sw * (up ? 2 : 0), -10); g.quadraticCurveTo(0, -6, -15 - sw * (up ? 2 : 0), -10); g.closePath(); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.2; g.stroke(); };
  const drawQuiver = () => { if (!L.quiver) return; g.save(); g.translate(up ? 6 : side ? -10 : 8, shY + 6); g.rotate(up ? 0.3 : side ? -0.4 : 0.3); g.fillStyle = '#5a3a1e'; g.fillRect(-4, -6, 8, 24); g.strokeStyle = OUT; g.strokeRect(-4, -6, 8, 24); for (let i = 0; i < 4; i++) { g.strokeStyle = '#d9c08a'; g.lineWidth = 1.2; g.beginPath(); g.moveTo(-2 + i * 1.5, -6); g.lineTo(-2 + i * 1.5, -14); g.stroke(); g.fillStyle = '#e9e2d0'; g.fillRect(-3 + i * 1.5, -16, 2, 4); } g.restore(); };
  const weaponHand = side ? [6 + sw * -4, -28] : down ? [-15, -29 + sw * 2] : [15, -29 - sw * 2];
  const drawWeapon = (behind) => {
    if (!L.weapon) return;
    const [hx, hy] = weaponHand;
    g.save(); g.translate(hx, hy);
    const swing = atk ? (-1.6 + atk * 2.4) : 0;
    if (L.weapon === 'sword') {
      g.rotate((side ? 0.4 : down ? -0.25 : 0.25) + (side ? swing : swing * (down ? -0.6 : 0.6)));
      g.fillStyle = lg(g, -2, 0, 2, 0, [[0, '#f2f6fa'], [0.5, '#b8c2cc'], [1, '#6e7a86']]);
      g.beginPath(); g.moveTo(-2.4, -4); g.lineTo(-2.4, -32); g.lineTo(0, -37); g.lineTo(2.4, -32); g.lineTo(2.4, -4); g.closePath(); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1; g.stroke();
      g.fillStyle = '#c9a227'; g.fillRect(-7, -5, 14, 3); g.fillStyle = '#4a2e17'; g.fillRect(-1.5, -2, 3, 6); g.fillStyle = '#c9a227'; g.beginPath(); g.arc(0, 5, 2, 0, 7); g.fill();
    } else if (L.weapon === 'staff') {
      g.rotate((side ? 0.12 : 0.06 * (down ? -1 : 1)) + (atk ? -0.5 * Math.sin(atk * Math.PI) : 0));
      g.fillStyle = lg(g, -2, 0, 2, 0, [[0, '#8a5e34'], [1, '#3e2814']]); g.fillRect(-2, -50, 4, 62); g.strokeStyle = OUT; g.lineWidth = 1; g.strokeRect(-2, -50, 4, 62);
      g.strokeStyle = '#c9a227'; g.lineWidth = 2; g.beginPath(); g.moveTo(-5, -50); g.quadraticCurveTo(0, -64, 5, -50); g.stroke();
      g.fillStyle = rg(g, -1.5, -57, 0.5, 0, -55, 6, [[0, '#fff6c0'], [0.4, '#ff9a2a'], [1, '#b3260e']]); g.beginPath(); g.arc(0, -55, 5.5, 0, 7); g.fill();
    } else if (L.weapon === 'bow') {
      g.rotate(side ? 0 : down ? 0.2 : -0.2);
      const pull = atk ? Math.sin(atk * Math.PI) * 6 : 0;
      g.strokeStyle = '#6b4422'; g.lineWidth = 3.2; g.beginPath(); g.arc(side ? -6 : 0, -8, 18, side ? -1.1 : -2.0, side ? 1.1 : -1.1 + 0.0001); g.stroke();
      g.strokeStyle = '#a0703a'; g.lineWidth = 1.6; g.beginPath(); g.arc(side ? -6 : 0, -8, 18, side ? -1.1 : -2.0, side ? 1.1 : -1.1 + 0.0001); g.stroke();
      if (side) { g.strokeStyle = 'rgba(240,240,240,.8)'; g.lineWidth = 0.8; g.beginPath(); g.moveTo(-6 + 18 * Math.cos(-1.1), -8 + 18 * Math.sin(-1.1)); g.lineTo(-pull, -8); g.lineTo(-6 + 18 * Math.cos(1.1), -8 + 18 * Math.sin(1.1)); g.stroke(); }
    } else if (L.weapon === 'torch') {
      g.rotate(side ? 0.3 : -0.2 + swing * 0.3);
      g.fillStyle = '#5a3a1e'; g.fillRect(-2, -22, 4, 26); g.fillStyle = '#2a1a0e'; g.fillRect(-3, -24, 6, 5);
    }
    g.restore();
  };
  if (!up) { drawCape(); }
  if (down) drawQuiver();
  if (up) drawWeapon(true);
  if (side && L.shield) drawShield(g, -6, -33, 0.7);
  // ---- pernas
  const legW = L.bare ? 5 : 6.5;
  if (side) {
    const fx1 = sw * 8, fx2 = -sw * 8;
    if (!L.robe) {
      limb(g, -1, hipY, fx2, -3, legW, shade(legCol, -0.25)); ell(g, fx2 + 2, -2, 5, 3, shade(bootCol, -0.2), OUT);
      limb(g, 1, hipY, fx1, -3, legW, legCol); ell(g, fx1 + 2, -2, 5, 3, bootCol, OUT);
    } else { ell(g, fx2 + 2, -2, 5, 3, shade(bootCol, -0.2), OUT); ell(g, fx1 + 2, -2, 5, 3, bootCol, OUT); }
  } else {
    const l1 = moving ? sw * 3 : 0;
    if (!L.robe) {
      limb(g, -5, hipY, -6, -3 - Math.max(0, l1), legW, legCol); limb(g, 5, hipY, 6, -3 - Math.max(0, -l1), legW, shade(legCol, -0.1));
    }
    ell(g, -6, -2 - Math.max(0, l1), 4.5, 3.2, bootCol, OUT); ell(g, 6, -2 - Math.max(0, -l1), 4.5, 3.2, bootCol, OUT);
  }
  // ---- braço de trás (lateral)
  const armCol = L.armor ? shade(L.top, -0.05) : L.robe ? L.top : L.bare ? L.skin : shade(L.top, 0.05);
  if (side) { const bx = -4 - sw * 6; limb(g, -2, shY + 3, bx, -29, 5.5, shade(armCol, -0.3)); ell(g, bx, -28, 3, 3, shade(L.skin, -0.25)); }
  // ---- tronco
  const tw = side ? 9 : 12;
  g.beginPath();
  if (L.robe) { g.moveTo(-tw, shY); g.lineTo(tw, shY); g.lineTo(tw + 5, -5); g.quadraticCurveTo(0, -1, -tw - 5, -5); g.closePath(); }
  else { g.moveTo(-tw, shY); g.lineTo(tw, shY); g.lineTo(tw - 2, hipY + 2); g.lineTo(-tw + 2, hipY + 2); g.closePath(); }
  g.fillStyle = lg(g, -tw, 0, tw, 0, [[0, shade(L.top, 0.18)], [0.5, L.top], [1, shade(L.top, -0.4)]]); g.fill();
  g.strokeStyle = OUT; g.lineWidth = 1.3; g.stroke();
  if (L.robe) { g.strokeStyle = L.trim; g.lineWidth = 2; g.beginPath(); g.moveTo(side ? 4 : 0, shY + 2); g.lineTo(side ? 6 : 0, -4); g.stroke(); g.beginPath(); g.moveTo(-tw - 4, -6); g.quadraticCurveTo(0, -2, tw + 4, -6); g.stroke(); }
  if (L.armor && !up) { g.fillStyle = lg(g, -6, 0, 6, 0, [[0, shade(L.trim, 0.1)], [1, shade(L.trim, -0.35)]]); g.fillRect(side ? -3 : -5, shY + 3, side ? 7 : 10, 21); g.fillStyle = '#e8c33a'; g.fillRect(side ? -1 : -2, shY + 8, 3, 3); }
  if (L.armor) { g.fillStyle = 'rgba(255,255,255,.25)'; g.fillRect(-tw + 2, shY + 1, 4, 14); }
  if (L.apron && !up) { g.fillStyle = L.apron; g.fillRect(side ? -2 : -7, shY + 10, side ? 8 : 14, 18); g.strokeStyle = 'rgba(0,0,0,.3)'; g.strokeRect(side ? -2 : -7, shY + 10, side ? 8 : 14, 18); }
  if (!L.robe) { g.fillStyle = L.bare ? '#4a2e17' : '#3a2412'; g.fillRect(-tw + 1, hipY - 3, tw * 2 - 2, 4); if (!up) { g.fillStyle = '#c9a227'; g.fillRect(-2, hipY - 3, 4, 4); } }
  if (L.bare) { g.fillStyle = L.top; g.beginPath(); g.moveTo(-tw + 1, hipY - 1); g.lineTo(tw - 1, hipY - 1); g.lineTo(tw - 3, hipY + 9); g.lineTo(-tw + 3, hipY + 9); g.closePath(); g.fill(); }
  if (up) drawQuiver();
  if (up) drawCape();
  // ---- ombreiras
  if (L.armor) for (const sx of side ? [1] : [-1, 1]) { g.fillStyle = rg(g, sx * 11 - 2, shY - 1, 1, sx * 11, shY + 1, 7, [[0, '#e0e6ec'], [1, '#6e7a86']]); g.beginPath(); g.ellipse(side ? 1 : sx * 11, shY + 1, 7, 5, 0, 0, 7); g.fill(); g.strokeStyle = OUT; g.stroke(); }
  // ---- braços
  if (side) {
    const fx = 6 + sw * -4;
    if (!L.shield) { limb(g, 1, shY + 3, fx, -29, 5.5, armCol); ell(g, fx, -28, 3.2, 3.2, L.skin, OUT); }
    else { limb(g, 1, shY + 3, fx, -29, 5.5, armCol); ell(g, fx, -28, 3.2, 3.2, L.skin, OUT); }
  } else {
    const a1 = moving ? sw * 3 : 0;
    const lx = -15, rx = 15;
    limb(g, -12, shY + 3, lx, -29 + a1, 5.5, armCol); ell(g, lx, -28 + a1, 3.2, 3.2, L.skin, OUT);
    limb(g, 12, shY + 3, rx, -29 - a1, 5.5, armCol); ell(g, rx, -28 - a1, 3.2, 3.2, L.skin, OUT);
  }
  if (!up) drawWeapon(false);
  if (side && false) drawShield(g, 6, -32, 1);
  if (down && L.shield) drawShield(g, 15, -33, 1);
  if (up && L.shield) drawShield(g, -14, -36, 0.9, true);
  // ---- cabeça
  drawHead(g, L, dir, headY);
  g.restore();
}
function drawShield(g, x, y, s, back) {
  g.save(); g.translate(x, y); g.scale(s, 1);
  g.fillStyle = rg(g, -3, -3, 1, 0, 0, 10, [[0, '#a87444'], [1, '#5a3a1e']]); g.beginPath(); g.arc(0, 0, 9.5, 0, 7); g.fill();
  g.strokeStyle = '#8a929a'; g.lineWidth = 2.2; g.stroke(); g.strokeStyle = OUT; g.lineWidth = 0.8; g.beginPath(); g.arc(0, 0, 10.8, 0, 7); g.stroke();
  if (!back) { g.fillStyle = rg(g, -1, -1, 0.5, 0, 0, 3.5, [[0, '#f0f0f0'], [1, '#6e7a86']]); g.beginPath(); g.arc(0, 0, 3.2, 0, 7); g.fill(); g.fillStyle = '#b3261e'; g.fillRect(-1, -8, 2, 5); g.fillRect(-1, 3, 2, 5); }
  g.restore();
}
function drawHead(g, L, dir, hy) {
  const side = dir === 1, up = dir === 0;
  const R = 10;
  // cabelo de trás
  if (L.long) { g.fillStyle = shade(L.hair, -0.1); g.beginPath(); g.ellipse(side ? -3 : 0, hy + 8, R + 2, 14, 0, 0, 7); g.fill(); }
  if (L.hat === 'ears') { // orelhas de goblin
    g.fillStyle = shade(L.skin, -0.1);
    for (const sx of side ? [-1] : [-1, 1]) { g.beginPath(); g.moveTo(sx * 6, hy - 2); g.lineTo(sx * 21, hy - 8); g.lineTo(sx * 8, hy + 4); g.closePath(); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1; g.stroke(); }
  }
  g.fillStyle = rg(g, -3, hy - 4, 1, 0, hy, R + 2, [[0, shade(L.skin, 0.15)], [0.7, L.skin], [1, shade(L.skin, -0.35)]]);
  g.beginPath(); g.arc(side ? 1 : 0, hy, R, 0, 7); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.3; g.stroke();
  if (side) { g.fillStyle = L.skin; g.beginPath(); g.ellipse(10.5, hy + 1.5, 2.2, 2.6, 0, 0, 7); g.fill(); }
  // rosto
  if (!up) {
    const eyes = side ? [[6, hy - 1]] : [[-4, hy - 1], [4, hy - 1]];
    for (const [ex, ey] of eyes) {
      g.fillStyle = L.hat === 'ears' ? '#ffe14a' : '#ffffff'; g.beginPath(); g.ellipse(ex, ey, 2.2, 2.4, 0, 0, 7); g.fill();
      g.fillStyle = '#1a1410'; g.beginPath(); g.arc(ex + (side ? 0.8 : 0), ey + 0.3, 1.4, 0, 7); g.fill();
      g.fillStyle = 'rgba(255,255,255,.9)'; g.fillRect(ex - 0.6 + (side ? 0.8 : 0), ey - 0.8, 0.9, 0.9);
      g.strokeStyle = shade(L.hair, -0.2); g.lineWidth = 1.2; g.beginPath(); g.moveTo(ex - 2.5, ey - 3.6); g.lineTo(ex + 2.5, ey - 4); g.stroke();
    }
    g.strokeStyle = 'rgba(90,40,30,.7)'; g.lineWidth = 1; g.beginPath(); if (side) { g.moveTo(5, hy + 5); g.lineTo(8, hy + 5); } else { g.moveTo(-2.5, hy + 5); g.quadraticCurveTo(0, hy + 6.2, 2.5, hy + 5); } g.stroke();
    g.fillStyle = 'rgba(255,120,100,.18)'; if (!side) { g.beginPath(); g.arc(-6, hy + 3, 2.2, 0, 7); g.arc(6, hy + 3, 2.2, 0, 7); g.fill(); }
    if (L.beard) { g.fillStyle = L.beard; g.beginPath(); if (side) { g.moveTo(2, hy + 3); g.quadraticCurveTo(10, hy + 6, 7, hy + (L.mustache ? 10 : 18)); g.quadraticCurveTo(2, hy + 12, 2, hy + 3); } else { g.moveTo(-7, hy + 3); g.quadraticCurveTo(0, hy + (L.mustache ? 12 : 22), 7, hy + 3); g.quadraticCurveTo(0, hy + 7, -7, hy + 3); } g.fill(); g.strokeStyle = 'rgba(0,0,0,.25)'; g.stroke(); }
  }
  // cabelo / chapéus
  if (L.hat === 'helmet') {
    g.fillStyle = lg(g, -R, 0, R, 0, [[0, '#e6ecf2'], [0.5, '#a4aeb8'], [1, '#5e6872']]);
    g.beginPath(); g.arc(side ? 1 : 0, hy - 1, R + 1.5, Math.PI * 1.02, Math.PI * 1.98); g.lineTo(R + 2.5, hy + (up ? 8 : 1)); g.lineTo(-R - 1.5, hy + (up ? 8 : 1)); g.closePath(); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.2; g.stroke();
    if (!up) { g.fillStyle = '#7a848e'; g.fillRect(side ? 6 : -1.5, hy - 4, 3, 9); }
    g.fillStyle = '#b3261e'; g.beginPath(); g.moveTo(-1.5, hy - R - 2); g.quadraticCurveTo(side ? -14 : 0, hy - R - 12, side ? -12 : 1.5, hy - R - 2 + (side ? 6 : 0)); g.closePath(); g.fill();
  } else if (L.hat === 'wizard') {
    g.fillStyle = shade(L.hatCol, -0.2); g.beginPath(); g.ellipse(side ? 1 : 0, hy - 6, 17, 5, 0, 0, 7); g.fill(); g.strokeStyle = OUT; g.stroke();
    g.fillStyle = lg(g, -9, 0, 9, 0, [[0, shade(L.hatCol, 0.2)], [1, shade(L.hatCol, -0.4)]]);
    g.beginPath(); g.moveTo(-9, hy - 7); g.quadraticCurveTo(-2, hy - 22, side ? -12 : 6, hy - 33); g.quadraticCurveTo(4, hy - 20, 9, hy - 7); g.closePath(); g.fill(); g.stroke();
    g.fillStyle = L.trim; g.fillRect(-9, hy - 10, 18, 3);
    g.fillStyle = '#ffe066'; g.beginPath(); const sx = side ? -2 : 1, sy = hy - 18; for (let i = 0; i < 10; i++) { const a = i / 10 * Math.PI * 2 - Math.PI / 2, rr = i % 2 ? 1.3 : 3; g.lineTo(sx + Math.cos(a) * rr, sy + Math.sin(a) * rr); } g.fill();
  } else if (L.hat === 'hood') {
    g.fillStyle = lg(g, -R - 3, 0, R + 3, 0, [[0, shade(L.hatCol, 0.15)], [1, shade(L.hatCol, -0.4)]]);
    g.beginPath();
    if (up) { g.arc(0, hy, R + 3, 0, 7); }
    else if (side) { g.moveTo(10, hy - 9); g.quadraticCurveTo(-2, hy - 18, -13, hy - 4); g.quadraticCurveTo(-12, hy + 9, -4, hy + 12); g.lineTo(2, hy + 8); g.quadraticCurveTo(-4, hy, 4, hy - 6); g.closePath(); }
    else { g.arc(0, hy, R + 3, Math.PI * 0.85, Math.PI * 2.15); g.quadraticCurveTo(R + 2, hy + 10, R - 2, hy + 12); g.quadraticCurveTo(R - 4, hy - 4, 0, hy - 7); g.quadraticCurveTo(-R + 4, hy - 4, -R + 2, hy + 12); g.quadraticCurveTo(-R - 2, hy + 10, -R - 3, hy + 3); g.closePath(); }
    g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.2; g.stroke();
  } else if (L.hat !== 'ears') {
    g.fillStyle = lg(g, -R, hy - R, R, hy, [[0, shade(L.hair, 0.2)], [1, shade(L.hair, -0.3)]]);
    g.beginPath();
    if (up) g.arc(0, hy - 0.5, R + 0.8, 0, 7);
    else if (side) { g.arc(1, hy - 1, R + 1, Math.PI * 0.9, Math.PI * 1.9); g.quadraticCurveTo(0, hy - 2, -6, hy + 4); g.closePath(); }
    else { g.arc(0, hy - 1, R + 1, Math.PI * 1.0, Math.PI * 2.0); g.quadraticCurveTo(4, hy - 7, 0, hy - 6); g.quadraticCurveTo(-5, hy - 6, -R - 1, hy - 1); }
    g.fill(); g.strokeStyle = OUT; g.lineWidth = 1; g.stroke();
    if (L.hat === 'circlet') { g.strokeStyle = '#e8c33a'; g.lineWidth = 1.8; g.beginPath(); g.arc(side ? 1 : 0, hy - 1, R + 0.5, Math.PI * 1.1, Math.PI * 1.9); g.stroke(); if (!up) { g.fillStyle = '#ff6a1a'; g.beginPath(); g.arc(side ? 7 : 0, hy - R + 0.5, 2.2, 0, 7); g.fill(); } }
  }
}

// ------------------------------------------------------------
//  Quadrúpedes / répteis (vista lateral, virado à direita)
// ------------------------------------------------------------
function drawQuad(g, Q, ph, atk) {
  const sw = Math.sin(ph * Math.PI * 2), moving = ph > 0;
  const L = Q.len, Hh = Q.h, leg = Q.leg;
  const bob = moving ? -Math.abs(Math.cos(ph * Math.PI * 2)) * 1.5 : 0;
  const lunge = atk ? Math.sin(atk * Math.PI) * 7 : 0;
  const hipY = -leg + bob, bodyY = hipY - Hh * 0.38;
  const legsAt = [[L * 0.3, 0], [-L * 0.3, Math.PI]];
  const drawLegs = (far) => {
    for (const [lx, off] of legsAt) {
      const a = moving ? Math.sin(ph * Math.PI * 2 + off + (far ? Math.PI : 0)) * 0.55 : 0;
      const x = lx + (far ? 3 : 0), col = far ? shade(Q.col, -0.38) : shade(Q.col, -0.1);
      if (Q.lizard) {
        const fx = x + Math.sin(a) * 8, fy = -1;
        limb(g, x, hipY - 2, x + (far ? 4 : -4), hipY + 3, 4.5, col); limb(g, x + (far ? 4 : -4), hipY + 3, fx, fy, 3.5, col);
      } else {
        const kx = x + Math.sin(a) * leg * 0.45, ky = hipY + leg * 0.5;
        const fx = x + Math.sin(a) * leg * 0.8, fy = -1.5;
        limb(g, x, hipY - Hh * 0.1, kx, ky, Math.max(3.5, Hh * 0.22), col); limb(g, kx, ky, fx, fy, Math.max(2.5, Hh * 0.15), col);
        ell(g, fx + 1.5, -1, 3, 1.8, shade(Q.col, -0.6));
      }
    }
  };
  drawLegs(true);
  // cauda
  const tx = -L / 2, ty = bodyY;
  g.lineCap = 'round';
  if (Q.tail === 'thin') { g.strokeStyle = OUT; g.lineWidth = 3.4; g.beginPath(); g.moveTo(tx + 3, ty); g.bezierCurveTo(tx - 12, ty + 4, tx - 18, ty - 10 + sw * 3, tx - 26, ty - 6); g.stroke(); g.strokeStyle = Q.tailCol; g.lineWidth = 1.8; g.stroke(); }
  else if (Q.tail === 'bushy') { g.fillStyle = lg(g, tx - 26, ty - 10, tx, ty, [[0, shade(Q.tailCol, 0.25)], [1, Q.tailCol]]); g.beginPath(); g.moveTo(tx + 4, ty - 5); g.quadraticCurveTo(tx - 16, ty - 14 + sw * 2, tx - 28, ty + 2 + sw * 3); g.quadraticCurveTo(tx - 14, ty + 8, tx + 4, ty + 4); g.closePath(); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.2; g.stroke(); }
  else if (Q.tail === 'curl') { g.strokeStyle = Q.tailCol; g.lineWidth = 2.5; g.beginPath(); g.arc(tx - 3, ty - 4, 4, 0, Math.PI * 1.6); g.stroke(); }
  else if (Q.tail === 'lizard') { g.fillStyle = lg(g, 0, ty - 6, 0, ty + 6, [[0, shade(Q.tailCol, 0.15)], [1, shade(Q.tailCol, -0.3)]]); g.beginPath(); g.moveTo(tx + 6, ty - Hh * 0.4); g.quadraticCurveTo(tx - 20, ty - 4 + sw * 4, tx - 38, ty + 4 + sw * 6); g.quadraticCurveTo(tx - 18, ty + 6, tx + 6, ty + Hh * 0.4); g.closePath(); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.2; g.stroke(); }
  // corpo
  g.fillStyle = lg(g, 0, bodyY - Hh / 2, 0, bodyY + Hh / 2, [[0, shade(Q.col, 0.22)], [0.55, Q.col], [1, shade(Q.col, -0.4)]]);
  g.beginPath(); g.ellipse(lunge * 0.3, bodyY, L / 2, Hh / 2, 0, 0, 7); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.4; g.stroke();
  g.fillStyle = Q.belly; g.globalAlpha = 0.55; g.beginPath(); g.ellipse(lunge * 0.3, bodyY + Hh * 0.28, L * 0.36, Hh * 0.16, 0, 0, 7); g.fill(); g.globalAlpha = 1;
  if (Q.spots) { g.fillStyle = Q.spots; const r = prng(5); for (let i = 0; i < 7; i++) { g.beginPath(); g.ellipse(-L * 0.35 + i * L * 0.11, bodyY - Hh * 0.15 + (r() - 0.5) * 4, 3, 2, 0, 0, 7); g.fill(); } }
  if (Q.bristle) { g.strokeStyle = shade(Q.col, -0.5); g.lineWidth = 1.4; for (let i = 0; i < 12; i++) { const x = -L * 0.3 + i * L * 0.055; g.beginPath(); g.moveTo(x, bodyY - Hh * 0.45); g.lineTo(x - 2, bodyY - Hh * 0.45 - 5 - (i % 3)); g.stroke(); } }
  if (Q.ruff) { g.fillStyle = shade(Q.col, 0.12); g.beginPath(); g.ellipse(L * 0.32 + lunge * 0.5, bodyY - 1, 9, Hh * 0.55, 0.3, 0, 7); g.fill(); }
  // fios de pelo
  if (!Q.lizard) { g.strokeStyle = 'rgba(255,255,255,.08)'; g.lineWidth = 1; for (let i = 0; i < 10; i++) { const x = -L * 0.4 + i * L * 0.08; g.beginPath(); g.moveTo(x, bodyY - Hh * 0.3); g.lineTo(x - 3, bodyY - Hh * 0.1); g.stroke(); } }
  if (Q.embers) { const r = prng(8); for (let i = 0; i < 4; i++) { g.fillStyle = 'rgba(255,140,40,.9)'; g.beginPath(); g.arc(-L * 0.3 + r() * L * 0.6, bodyY - Hh * 0.2 - r() * Hh * 0.2, 1.4, 0, 7); g.fill(); } }
  drawLegs(false);
  // cabeça
  const hx = L / 2 + lunge, hyy = bodyY - Hh * 0.18 + (atk ? Math.sin(atk * Math.PI) * 3 : 0), Rh = Q.head;
  if (Q.ear === 'point') { g.fillStyle = Q.earCol; g.beginPath(); g.moveTo(hx - Rh * 0.6, hyy - Rh * 0.6); g.lineTo(hx - Rh * 0.2, hyy - Rh * 1.7); g.lineTo(hx + Rh * 0.2, hyy - Rh * 0.6); g.closePath(); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1; g.stroke(); }
  g.fillStyle = lg(g, 0, hyy - Rh, 0, hyy + Rh, [[0, shade(Q.col, 0.2)], [1, shade(Q.col, -0.3)]]);
  g.beginPath(); g.ellipse(hx, hyy, Rh, Rh * 0.85, 0, 0, 7); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.3; g.stroke();
  // focinho
  g.fillStyle = shade(Q.col, Q.lizard ? 0.05 : 0.1);
  g.beginPath(); g.ellipse(hx + Rh * 0.9, hyy + Rh * 0.15, Rh * 0.75, Rh * (Q.lizard ? 0.42 : 0.5), 0, 0, 7); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.1; g.stroke();
  g.fillStyle = Q.tusks ? '#c98f8f' : '#1a1210'; g.beginPath(); g.ellipse(hx + Rh * 1.6, hyy + Rh * 0.05, Rh * 0.2, Rh * 0.22, 0, 0, 7); g.fill();
  if (Q.tusks) { g.strokeStyle = '#f4efe2'; g.lineWidth = 2.2; g.beginPath(); g.moveTo(hx + Rh * 1.1, hyy + Rh * 0.5); g.quadraticCurveTo(hx + Rh * 1.6, hyy + Rh * 0.3, hx + Rh * 1.5, hyy - Rh * 0.3); g.stroke(); }
  if (Q.ear === 'round') { g.fillStyle = Q.earCol; g.beginPath(); g.arc(hx - Rh * 0.3, hyy - Rh * 0.8, Rh * 0.5, 0, 7); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1; g.stroke(); }
  // olho
  if (Q.glowEye) { g.fillStyle = rg(g, hx + Rh * 0.35, hyy - Rh * 0.2, 0, hx + Rh * 0.35, hyy - Rh * 0.2, 5, [[0, 'rgba(255,200,80,.9)'], [1, 'rgba(255,140,20,0)']]); g.beginPath(); g.arc(hx + Rh * 0.35, hyy - Rh * 0.2, 5, 0, 7); g.fill(); }
  g.fillStyle = Q.eye; g.beginPath(); g.arc(hx + Rh * 0.35, hyy - Rh * 0.2, Math.max(1.4, Rh * 0.17), 0, 7); g.fill();
  g.fillStyle = 'rgba(255,255,255,.8)'; g.fillRect(hx + Rh * 0.3, hyy - Rh * 0.32, 1, 1);
  if (atk) { g.fillStyle = '#5a0e0e'; g.beginPath(); g.ellipse(hx + Rh * 1.1, hyy + Rh * 0.55, Rh * 0.5, Rh * 0.18 * Math.sin(atk * Math.PI) + 0.5, 0, 0, 7); g.fill(); }
}

// ------------------------------------------------------------
//  Golem de Brasa (vista frontal)
// ------------------------------------------------------------
function drawGolem(g, ph, atk) {
  const sw = Math.sin(ph * Math.PI * 2), moving = ph > 0;
  const bob = moving ? -Math.abs(Math.cos(ph * Math.PI * 2)) * 2 : 0;
  const r = prng(17);
  const rock = (x, y, rx, ry, rot) => {
    g.save(); g.translate(x, y); g.rotate(rot || 0);
    g.beginPath(); const n = 7; for (let i = 0; i < n; i++) { const a = i / n * Math.PI * 2, k = 0.82 + r() * 0.3; g.lineTo(Math.cos(a) * rx * k, Math.sin(a) * ry * k); } g.closePath();
    g.fillStyle = lg(g, -rx, -ry, rx, ry, [[0, '#6e625c'], [0.5, '#3e3430'], [1, '#1c1614']]); g.fill(); g.strokeStyle = OUT; g.lineWidth = 1.5; g.stroke();
    g.restore();
  };
  const crack = (pts) => { g.save(); g.strokeStyle = '#ffb03a'; g.shadowColor = '#ff5a00'; g.shadowBlur = 8; g.lineWidth = 2; g.beginPath(); pts.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.stroke(); g.restore(); };
  g.save(); g.translate(0, bob);
  const l1 = moving ? sw * 4 : 0;
  rock(-11, -12 - Math.max(0, l1), 9, 12); rock(11, -12 - Math.max(0, -l1), 9, 12);
  rock(0, -44, 24, 22);
  crack([[-10, -56], [-4, -46], [-8, -36], [2, -30]]); crack([[8, -58], [4, -48], [12, -40]]);
  const ar = atk ? Math.sin(atk * Math.PI) * 10 : 0;
  rock(-28, -42 + (moving ? sw * 3 : 0) - ar, 10, 15, 0.2); rock(28, -42 - (moving ? sw * 3 : 0) - ar, 10, 15, -0.2);
  rock(-31, -24 - ar, 8, 8); rock(31, -24 - ar, 8, 8);
  rock(0, -72, 12, 10);
  for (const ex of [-5, 5]) { g.fillStyle = rg(g, ex, -73, 0, ex, -73, 6, [[0, 'rgba(255,240,160,1)'], [0.4, 'rgba(255,150,30,.9)'], [1, 'rgba(255,80,0,0)']]); g.beginPath(); g.arc(ex, -73, 6, 0, 7); g.fill(); }
  g.restore();
}

// ------------------------------------------------------------
//  Cache de quadros
// ------------------------------------------------------------
const FW = 128, FH = 140, FAX = 64, FAY = 126;
const frameCache = new Map();
function getFrame(look, dir, fi) {
  const L = LOOKS[look];
  const ddir = L.type === 'human' ? (dir === 3 ? 1 : dir) : 1;
  const key = look + '|' + ddir + '|' + fi;
  let c = frameCache.get(key);
  if (c) return c;
  const tmp = mk(FW, FH), g = tmp.getContext('2d');
  g.translate(FAX, FAY);
  const s = L.scale || 1; g.scale(s, s);
  const ph = fi >= 1 && fi <= 8 ? (fi - 1) / 8 + 0.001 : 0;
  const atk = fi >= 9 ? (fi - 8) / 3 : 0;
  if (L.type === 'human') drawHuman(g, L, ddir, ph, atk);
  else if (L.type === 'quad') drawQuad(g, L, ph, atk);
  else if (L.type === 'golem') drawGolem(g, ph, atk);
  else if (L.type === 'dummy') drawDummy(g, atk);
  frameCache.set(key, tmp);
  return tmp;
}
