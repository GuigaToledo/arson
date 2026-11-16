'use strict';
// ============================================================
//  ARSON — núcleo: ruído, mapa, dados do jogo, colisão
// ============================================================
const VERSION = '0.6.1';
const TS = 64; // pixels de arte por tile
// suba MAP_VERSION sempre que o mapa mudar: quem estava fora do templo volta para Cinzaforte (evita nascer dentro de parede/água)
const MAP_VERSION = 1;

function hash2(x, y, s) {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(s | 0, 982451653)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
function vnoise(x, y, s) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const a = hash2(xi, yi, s), b = hash2(xi + 1, yi, s), c = hash2(xi, yi + 1, s), d = hash2(xi + 1, yi + 1, s);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function fbm(x, y, s) { return vnoise(x, y, s) * 0.6 + vnoise(x * 2, y * 2, s + 7) * 0.3 + vnoise(x * 4, y * 4, s + 13) * 0.1; }
function prng(seed) { let s = (seed >>> 0) % 2147483647; if (s <= 0) s += 2147483646; return () => (s = (s * 16807) % 2147483647) / 2147483647; }
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const lerp = (a, b, t) => a + (b - a) * t;
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

// ------------------------------------------------------------
//  Mapa
// ------------------------------------------------------------
const T = { GRASS: 0, WATER: 1, SAND: 2, TREE: 3, STONE: 4, WALL: 5, ROCK: 6, FLOWER: 7, PATH: 8, ASH: 9, LAVA: 10, DEADTREE: 11, BRIDGE: 12 };
const BLOCK = new Set([T.WATER, T.TREE, T.WALL, T.ROCK, T.LAVA, T.DEADTREE]);
const ROUND = new Set([T.TREE, T.ROCK, T.DEADTREE]);
const W = 128, H = 128, CX = 64, CY = 64, VX = 104, VY = 24;
const MAP = new Uint8Array(W * H);
const tileAt = (x, y) => (x < 0 || y < 0 || x >= W || y >= H) ? T.TREE : MAP[y * W + x];
const pzTile = (tx, ty) => Math.abs(tx - CX) <= 9 && Math.abs(ty - CY) <= 9;
const isPZ = (x, y) => pzTile(Math.floor(x), Math.floor(y));
const TEMPLO = { x: CX + 0.5, y: CY + 1.5 };

(function gerarMapa() {
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    let t;
    const n1 = fbm(x / 16, y / 16, 1), n2 = fbm(x / 5, y / 5, 2), h = hash2(x, y, 3);
    const vd = Math.hypot(x - VX, y - VY);
    if (vd < 24 + (n2 - 0.5) * 8) {
      t = T.ASH;
      if (vd > 5) {
        const ln = fbm(x / 7, y / 7, 4);
        if (ln > 0.62) t = T.LAVA;
        else if (n2 > 0.64) t = T.DEADTREE;
        else if (h < 0.03) t = T.ROCK;
      }
    } else {
      if (n1 < 0.34) t = T.WATER;
      else if (n1 < 0.38) t = T.SAND;
      else if (n2 > 0.63) t = T.TREE;
      else if (h < 0.012) t = T.ROCK;
      else if (h < 0.05) t = T.FLOWER;
      else t = T.GRASS;
    }
    if (x < 2 || y < 2 || x >= W - 2 || y >= H - 2) t = T.TREE;
    MAP[y * W + x] = t;
  }
  for (let dy = -12; dy <= 12; dy++) for (let dx = -12; dx <= 12; dx++) {
    const ax = Math.abs(dx), ay = Math.abs(dy);
    let t = T.GRASS;
    if (ax <= 9 && ay <= 9) {
      t = T.STONE;
      if ((ax === 9 || ay === 9) && !(ax <= 1 || ay <= 1)) t = T.WALL;
    } else if (hash2(dx, dy, 77) < 0.06) t = T.FLOWER;
    MAP[(CY + dy) * W + (CX + dx)] = t;
  }
  for (const [dx, dy] of [[-6, -6], [6, -6], [-6, 6], [6, 6]]) MAP[(CY + dy) * W + CX + dx] = T.FLOWER;
  for (const [dx, dy] of [[0, 4], [1, 4], [0, 5], [1, 5]]) MAP[(CY + dy) * W + CX + dx] = T.WATER;
  function carve(x, y, dx, dy, len) {
    for (let i = 0; i < len; i++) {
      if (x < 3 || y < 3 || x >= W - 3 || y >= H - 3) break;
      const k = y * W + x, t = MAP[k];
      if (!pzTile(x, y)) {
        if (t === T.WATER) MAP[k] = T.BRIDGE;
        else if (t === T.ASH || t === T.LAVA || t === T.DEADTREE) MAP[k] = T.ASH;
        else if (t !== T.BRIDGE) MAP[k] = T.PATH;
        // estrada com 2 de largura
        const k2 = dx !== 0 ? k + W : k + 1, t2 = MAP[k2];
        if (t2 === T.TREE || t2 === T.ROCK || t2 === T.GRASS || t2 === T.FLOWER || t2 === T.SAND) MAP[k2] = T.PATH;
      }
      const r = hash2(x, y, 9);
      if (i > 4 && r < 0.14) { if (dx !== 0) y += r < 0.07 ? 1 : -1; else x += r < 0.07 ? 1 : -1; }
      else { x += dx; y += dy; }
    }
    return [x, y];
  }
  carve(CX, CY - 9, 0, -1, 56);
  carve(CX, CY + 9, 0, 1, 56);
  carve(CX - 9, CY, -1, 0, 56);
  const [ex, ey] = carve(CX + 9, CY, 1, 0, 40);
  carve(ex, ey, 0, -1, 42);
  MAP[VY * W + VX] = T.ASH;
  for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) MAP[(VY + dy) * W + VX + dx] = T.ASH;
})();

// Adereços da cidade (decoração + luz)
const PROPS = [
  { k: 'braseiro', x: CX - 1.5, y: CY - 8.4 }, { k: 'braseiro', x: CX + 2.5, y: CY - 8.4 },
  { k: 'braseiro', x: CX - 1.5, y: CY + 9.6 }, { k: 'braseiro', x: CX + 2.5, y: CY + 9.6 },
  { k: 'braseiro', x: CX - 8.4, y: CY - 1.2 }, { k: 'braseiro', x: CX - 8.4, y: CY + 2.2 },
  { k: 'braseiro', x: CX + 9.4, y: CY - 1.2 }, { k: 'braseiro', x: CX + 9.4, y: CY + 2.2 },
  { k: 'banca', x: CX - 2.5, y: CY - 3.6 },
  { k: 'altar', x: CX + 3.5, y: CY - 3.6 },
  { k: 'barril', x: CX - 7.2, y: CY - 7.2 }, { k: 'barril', x: CX - 6.4, y: CY - 7.4 }, { k: 'caixa', x: CX - 7.3, y: CY - 6.3 },
  { k: 'caixa', x: CX + 7.6, y: CY + 7.4 }, { k: 'barril', x: CX + 6.8, y: CY + 7.6 },
  { k: 'barril', x: CX - 7.4, y: CY + 7.5 }, { k: 'caixa', x: CX + 7.5, y: CY - 7.2 },
];
const NPCS = [
  { id: 'n1', key: 'brann', name: 'Brann, o Mercador', look: 'mercador', x: CX - 2.5, y: CY - 2.6 },
  { id: 'n2', key: 'lira', name: 'Lira, a Sacerdotisa', look: 'sacerdotisa', x: CX + 3.5, y: CY - 2.6 },
];

// ------------------------------------------------------------
//  Colisão (círculo contra tiles)
// ------------------------------------------------------------
function hitCircle(x, y, r, mon) {
  const x0 = Math.floor(x - r - 0.3), x1 = Math.floor(x + r + 0.3), y0 = Math.floor(y - r - 0.3), y1 = Math.floor(y + r + 0.3);
  for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) {
    const t = tileAt(tx, ty);
    const solid = BLOCK.has(t) || (mon && pzTile(tx, ty));
    if (!solid) continue;
    if (ROUND.has(t) && !(mon && pzTile(tx, ty))) {
      const dx = x - (tx + 0.5), dy = y - (ty + 0.5), rr = r + 0.24;
      if (dx * dx + dy * dy < rr * rr) return true;
    } else {
      const cx = clamp(x, tx, tx + 1), cy = clamp(y, ty, ty + 1), dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy < r * r) return true;
    }
  }
  return false;
}
function moveCircle(e, dx, dy, r, mon) {
  const steps = Math.max(1, Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / 0.15));
  let moved = false;
  for (let i = 0; i < steps; i++) {
    const sx = dx / steps, sy = dy / steps;
    let a = false, b = false;
    if (sx && !hitCircle(e.x + sx, e.y, r, mon)) { e.x += sx; a = true; }
    if (sy && !hitCircle(e.x, e.y + sy, r, mon)) { e.y += sy; b = true; }
    if (!a && !b && (sx || sy)) {
      // desliza contornando obstáculos redondos
      const len = Math.hypot(sx, sy), px = -sy / len * len * 0.7, py = sx / len * len * 0.7;
      if (!hitCircle(e.x + px, e.y + py, r, mon)) { e.x += px; e.y += py; a = true; }
      else if (!hitCircle(e.x - px, e.y - py, r, mon)) { e.x -= px; e.y -= py; a = true; }
    }
    moved = moved || a || b;
  }
  return moved;
}

// ------------------------------------------------------------
//  Dados do jogo
// ------------------------------------------------------------
const VOC = {
  guerreiro: { nome: 'Guerreiro', hp0: 160, hpL: 16, mp0: 40, mpL: 6, range: 1.5, atk0: 11, atkL: 2.1, aspd: 1.0, armor: 0.5, hpReg: 3, mpReg: 1, spd: 3.5, proj: null },
  mago: { nome: 'Mago', hp0: 100, hpL: 7, mp0: 100, mpL: 24, range: 5.5, atk0: 8, atkL: 1.1, aspd: 1.15, armor: 0.15, hpReg: 1, mpReg: 4, spd: 3.4, proj: 'arcano' },
  arqueiro: { nome: 'Arqueiro', hp0: 125, hpL: 10, mp0: 60, mpL: 12, range: 6.5, atk0: 9, atkL: 1.7, aspd: 1.05, armor: 0.3, hpReg: 2, mpReg: 2, spd: 3.7, proj: 'flecha' },
};
// tipos: bolt (alvo), cone, chain, area (at: 'aim' | 'self'), heal
const SPELLS = {
  mago: [
    { k: 'ignis', nome: 'Ignis', lvl: 1, mana: 20, cd: 1.2, type: 'bolt', range: 7, base: 26, perL: 4, fx: 'fogo' },
    { k: 'sopro', nome: 'Sopro de Chamas', lvl: 2, mana: 35, cd: 3, type: 'cone', range: 4.5, ang: 0.6, base: 30, perL: 4.5, fx: 'fogo' },
    { k: 'corrente', nome: 'Corrente Elétrica', lvl: 4, mana: 45, cd: 3.5, type: 'chain', range: 7, jumps: 6, jumpR: 3.6, decay: 0.85, base: 34, perL: 5, fx: 'raio' },
    { k: 'meteoro', nome: 'Meteoro', lvl: 6, mana: 70, cd: 5, type: 'area', at: 'aim', range: 8, radius: 2.3, delay: 0.7, base: 48, perL: 6, fx: 'meteoro' },
    { k: 'nova', nome: 'Nova Flamejante', lvl: 10, mana: 95, cd: 7, type: 'area', at: 'self', radius: 3.4, delay: 0, base: 52, perL: 6, fx: 'nova' },
    { k: 'sana', nome: 'Cura', lvl: 1, mana: 25, cd: 1, type: 'heal', base: 30, perL: 4 },
  ],
  guerreiro: [
    { k: 'golpe', nome: 'Golpe Brutal', lvl: 1, mana: 20, cd: 2, type: 'bolt', range: 1.8, base: 38, perL: 5, fx: 'corte' },
    { k: 'talho', nome: 'Talho Amplo', lvl: 2, mana: 30, cd: 3, type: 'cone', range: 2.4, ang: 1.1, base: 32, perL: 4.5, fx: 'corte' },
    { k: 'furia', nome: 'Fúria Giratória', lvl: 5, mana: 45, cd: 4.5, type: 'area', at: 'self', radius: 2, delay: 0, base: 40, perL: 5, fx: 'giro' },
    { k: 'sana', nome: 'Cura', lvl: 1, mana: 25, cd: 1, type: 'heal', base: 35, perL: 4 },
  ],
  arqueiro: [
    { k: 'flecha', nome: 'Flecha Ardente', lvl: 1, mana: 20, cd: 1.5, type: 'bolt', range: 8, base: 30, perL: 4, fx: 'fogo' },
    { k: 'leque', nome: 'Leque de Flechas', lvl: 2, mana: 35, cd: 3, type: 'cone', range: 5.5, ang: 0.5, base: 28, perL: 4, fx: 'flechas' },
    { k: 'chuva', nome: 'Chuva de Flechas', lvl: 6, mana: 60, cd: 5, type: 'area', at: 'aim', range: 8, radius: 2.2, delay: 0.5, base: 38, perL: 5, fx: 'chuva' },
    { k: 'sana', nome: 'Cura', lvl: 1, mana: 25, cd: 1, type: 'heal', base: 32, perL: 4 },
  ],
};
const MT = {
  rato: { name: 'Esqueleto Lacaio', hp: 30, atk: 5, def: 0, xp: 12, spd: 2.4, range: 0.9, aspd: 1.5, gold: [0, 6], pot: 0.05, r: 0.25, aggro: 5 },
  javali: { name: 'Esqueleto Guerreiro', hp: 60, atk: 9, def: 1, xp: 28, spd: 2.7, range: 1.0, aspd: 1.6, gold: [2, 12], pot: 0.08, r: 0.33, aggro: 5 },
  lobo: { name: 'Lobisomem', hp: 110, atk: 14, def: 2, xp: 55, spd: 3.4, range: 1.0, aspd: 1.3, gold: [5, 20], pot: 0.1, r: 0.33, aggro: 7 },
  goblin: { name: 'Esqueleto Mago', hp: 140, atk: 16, def: 2, xp: 75, spd: 2.8, range: 4.5, aspd: 1.8, gold: [10, 30], pot: 0.15, proj: 'fogo', r: 0.3, aggro: 7 },
  salamandra: { name: 'Cria das Chamas', hp: 260, atk: 26, def: 4, xp: 160, spd: 3.0, range: 3.5, aspd: 1.7, gold: [20, 50], pot: 0.2, proj: 'fogo', r: 0.35, aggro: 7 },
  golem: { name: 'Golem de Brasa', hp: 520, atk: 40, def: 8, xp: 380, spd: 1.9, range: 1.2, aspd: 2.0, gold: [40, 90], pot: 0.3, r: 0.45, aggro: 6 },
  arson: { name: 'Arson, o Coração em Chamas', hp: 4000, atk: 70, def: 10, xp: 4000, spd: 2.2, range: 1.6, aspd: 1.5, gold: [500, 1000], pot: 1, boss: true, respawn: 600, r: 0.7, aggro: 8 },
  boneco: { name: 'Boneco de Treino', hp: 1000, atk: 1, def: 0, xp: 0, spd: 0, range: 1.3, aspd: 2, gold: [0, 0], pot: 0, r: 0.35, aggro: 2.6, dummy: true },
};
// bonecos de treino: do lado de fora do portão norte
const DUMMIES = [[CX - 5.5, CY - 11.5], [CX - 3.5, CY - 11.5], [CX + 4.5, CY - 11.5], [CX + 6.5, CY - 11.5]];

// ------------------------------------------------------------
//  Habilidades (sobem sem limite)
// ------------------------------------------------------------
const SKILLS = ['magia', 'defesa', 'espada', 'distancia'];
const SKN = { magia: 'Magia', defesa: 'Defesa', espada: 'Espada', distancia: 'Distância' };
const SKV = { guerreiro: ['espada', 'magia', 'defesa'], mago: ['magia', 'defesa'], arqueiro: ['distancia', 'magia', 'defesa'] };
const PRIM = { guerreiro: 'espada', mago: 'magia', arqueiro: 'distancia' };
const skNeed = (k, l) => Math.round({ magia: 30, defesa: 10, espada: 12, distancia: 12 }[k] * Math.pow(l, 1.5));
// multiplicadores de força (sk = { magia, defesa, espada, distancia } em níveis)
const atkMult = (voc, sk) => 1 + 0.04 * ((sk && sk[PRIM[voc]]) || 1);
const spellMult = (voc, sk) => voc === 'mago' ? 1 + 0.06 * ((sk && sk.magia) || 1) : 1 + 0.03 * ((sk && sk.magia) || 1) + 0.03 * ((sk && sk[PRIM[voc]]) || 1);
const defDiv = sk => 1 + 0.04 * ((sk && sk.defesa) || 1);
const xpToReach = l => l <= 1 ? 0 : Math.round(60 * Math.pow(l - 1, 2.2));
function levelFor(xp) { let l = 1; while (xpToReach(l + 1) <= xp) l++; return l; }
const maxHpOf = (voc, lvl) => VOC[voc].hp0 + VOC[voc].hpL * (lvl - 1);
const maxMpOf = (voc, lvl) => VOC[voc].mp0 + VOC[voc].mpL * (lvl - 1);
const TASKS = [[5, 'rato', 10], [10, 'javali', 12], [18, 'lobo', 15], [25, 'goblin', 15], [35, 'salamandra', 15], [999, 'golem', 10]];
