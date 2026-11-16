'use strict';
// ============================================================
//  ARSON — simulação do mundo (roda só no anfitrião)
// ============================================================
const MTK = Object.keys(MT);
const SIM = { mons: [], byId: new Map(), players: new Map(), ev: [], pending: [], nextId: 1, on: false, snapT: 0 };
const R = Math.random;
const rint = (a, b) => a + Math.floor(R() * (b - a + 1));

function hostInit() {
  SIM.mons = []; SIM.byId.clear(); SIM.players.clear(); SIM.ev = []; SIM.pending = []; SIM.nextId = 1; SIM.on = true;
  const occ = new Set();
  const place = (type, n, test) => {
    for (let k = 0; k < n; k++) for (let i = 0; i < 4000; i++) {
      const x = rint(3, W - 4), y = rint(3, H - 4);
      if (BLOCK.has(tileAt(x, y)) || pzTile(x, y) || occ.has(y * W + x) || !test(x, y)) continue;
      if (Math.abs(x - CX) < 14 && Math.abs(y - CY) < 14) continue;
      occ.add(y * W + x); spawnMon(type, x + 0.5, y + 0.5); break;
    }
  };
  const d = (x, y) => Math.hypot(x - CX, y - CY);
  const ash = (x, y) => tileAt(x, y) === T.ASH;
  place('rato', 34, (x, y) => !ash(x, y) && d(x, y) < 32);
  place('javali', 26, (x, y) => !ash(x, y) && d(x, y) > 20 && d(x, y) < 42);
  place('lobo', 26, (x, y) => !ash(x, y) && d(x, y) > 34 && d(x, y) < 62);
  place('goblin', 22, (x, y) => !ash(x, y) && d(x, y) > 42);
  place('salamandra', 18, (x, y) => ash(x, y) && Math.hypot(x - VX, y - VY) > 8);
  place('golem', 10, (x, y) => ash(x, y) && Math.hypot(x - VX, y - VY) < 18 && Math.hypot(x - VX, y - VY) > 4);
  spawnMon('arson', VX + 0.5, VY + 0.5);
}
function spawnMon(type, x, y) {
  const t = MT[type];
  const m = { id: SIM.nextId++, type, x, y, sx: x, sy: y, hp: t.hp, mhp: t.hp, tgt: null, acd: 0, face: 1, mv: false, dead: false, rsp: 0, dmg: new Map(), wx: x, wy: y, wt: R() * 3, scan: 0, atkT: 0, spc: 3, det: 0, detA: 0, stuck: 0 };
  SIM.mons.push(m); SIM.byId.set(m.id, m);
}
const ev = e => SIM.ev.push(e);
function roll(power, def) { return Math.max(1, Math.round(power * (0.75 + R() * 0.25)) - (def || 0)); }

// ------------------------------------------------------------
//  Mensagens dos jogadores
// ------------------------------------------------------------
function hostRecv(uid, d) {
  if (!SIM.on) return;
  const now = performance.now();
  let p = SIM.players.get(uid);
  switch (d.t) {
    case 'hi': {
      const isNew = !p;
      p = p || { uid, x: TEMPLO.x, y: TEMPLO.y, dir: 2, mv: 0, hp: 1, mhp: 1, lastAtk: 0, atkT: 0 };
      p.name = String(d.name || 'Viajante').slice(0, 16); p.voc = VOC[d.voc] ? d.voc : 'guerreiro'; p.lvl = clamp(d.lvl | 0, 1, 999);
      if (typeof d.x === 'number') { p.x = d.x; p.y = d.y; }
      p.seen = now;
      SIM.players.set(uid, p);
      if (isNew && uid !== ME.uid) broadcast({ t: 'sys', text: `${p.name} entrou no mundo.`, c: 'sys' });
      if (isNew) sendTo(uid, { t: 'sys', text: `Jogadores online: ${SIM.players.size}.`, c: 'sys' });
      break;
    }
    case 'st': {
      if (!p) return;
      if (typeof d.x === 'number' && isFinite(d.x) && isFinite(d.y)) { p.x = clamp(d.x, 0, W); p.y = clamp(d.y, 0, H); }
      p.dir = d.dir | 0; p.mv = d.mv ? 1 : 0; p.hp = d.hp | 0; p.mhp = Math.max(1, d.mhp | 0); p.lvl = clamp(d.lvl | 0, 1, 999); p.dead = !!d.dead; p.pz = isPZ(p.x, p.y);
      p.seen = now;
      break;
    }
    case 'atk': {
      if (!p || p.dead || p.pz) return;
      const m = SIM.byId.get(d.tg); if (!m || m.dead) return;
      const v = VOC[p.voc];
      if (dist(p, m) > v.range + MT[m.type].r + 0.6) return;
      if (now - p.lastAtk < v.aspd * 800) return;
      p.lastAtk = now; p.atkT = 0.3;
      if (v.proj) ev({ k: 'proj', f: v.proj, x: p.x, y: p.y - 0.5, x1: m.x, y1: m.y - 0.35, d: 0 });
      else ev({ k: 'slash', x: m.x, y: m.y - 0.35, a: Math.atan2(m.y - p.y, m.x - p.x) });
      hurtMon(m, roll(v.atk0 + v.atkL * p.lvl, MT[m.type].def), uid);
      break;
    }
    case 'cast': if (p) hostCast(p, d, now); break;
    case 'chat': {
      const text = String(d.text || '').replace(/[\u0000-\u001f]/g, '').slice(0, 140).trim();
      if (!text || !p) return;
      if (now - (p.lastChat || 0) < 350) return;
      p.lastChat = now;
      broadcast({ t: 'chat', uid, name: p.name, lvl: p.lvl, text });
      break;
    }
    case 'fx': { // efeitos locais (cura, nível, morte) repassados aos outros
      if (!p || !d.e || typeof d.e !== 'object') return;
      const e = d.e;
      if (!['heal', 'lvl', 'pdie', 'txt'].includes(e.k)) return;
      e.x = p.x; e.y = p.y; e.uid = uid;
      ev(e);
      break;
    }
  }
}
function hostPlayerLeft(uid) {
  const p = SIM.players.get(uid);
  if (!p) return;
  SIM.players.delete(uid);
  for (const m of SIM.mons) if (m.tgt === uid) m.tgt = null;
  broadcast({ t: 'sys', text: `${p.name} saiu do mundo.`, c: 'sys' });
}

// ------------------------------------------------------------
//  Magias
// ------------------------------------------------------------
function monNear(x, y, r, except) {
  let best = null, bd = r;
  for (const m of SIM.mons) { if (m.dead || (except && except.has(m.id))) continue; const d = Math.hypot(m.x - x, m.y - y); if (d <= bd) { bd = d; best = m; } }
  return best;
}
function hostCast(p, d, now) {
  const s = (SPELLS[p.voc] || []).find(x => x.k === d.k);
  if (!s || p.dead || p.lvl < s.lvl) return;
  p.cds = p.cds || {};
  if ((p.cds[s.k] || 0) > now + 150) return;
  p.cds[s.k] = now + s.cd * 1000 - 200;
  if (s.type === 'heal') { ev({ k: 'heal', x: p.x, y: p.y, v: d.v | 0, uid: p.uid }); return; }
  if (p.pz) return;
  p.atkT = 0.3;
  const power = s.base + s.perL * p.lvl;
  const ax = typeof d.ax === 'number' && isFinite(d.ax) ? d.ax : p.x, ay = typeof d.ay === 'number' && isFinite(d.ay) ? d.ay : p.y;
  const pick = () => {
    let m = SIM.byId.get(d.tg);
    if (m && !m.dead && dist(p, m) <= s.range + 1) return m;
    m = monNear(ax, ay, 2.5);
    if (m && dist(p, m) <= s.range + 1) return m;
    return monNear(p.x, p.y, s.range);
  };
  if (s.type === 'bolt') {
    const m = pick(); if (!m) return;
    if (s.fx === 'corte') ev({ k: 'slash', x: m.x, y: m.y - 0.35, a: Math.atan2(m.y - p.y, m.x - p.x), big: 1 });
    else ev({ k: 'proj', f: s.fx, x: p.x, y: p.y - 0.5, x1: m.x, y1: m.y - 0.35, big: 1 });
    hurtMon(m, roll(power, MT[m.type].def), p.uid);
  } else if (s.type === 'cone') {
    const a = Math.atan2(ay - (p.y - 0.3), ax - p.x);
    ev({ k: 'cone', f: s.fx, x: p.x, y: p.y - 0.3, a, r: s.range, w: s.ang });
    for (const m of SIM.mons) {
      if (m.dead) continue;
      const dx = m.x - p.x, dy = m.y - p.y, dd = Math.hypot(dx, dy);
      if (dd > s.range + MT[m.type].r) continue;
      let da = Math.abs(Math.atan2(dy, dx) - a); if (da > Math.PI) da = Math.PI * 2 - da;
      if (da <= s.ang + 0.15 || dd < 0.6) hurtMon(m, roll(power, MT[m.type].def), p.uid);
    }
  } else if (s.type === 'chain') {
    let m = pick(); if (!m) return;
    const hit = new Set(), pts = [[p.x, p.y - 0.75]];
    let pw = power;
    for (let i = 0; i < s.jumps && m; i++) {
      hit.add(m.id); pts.push([m.x, m.y - 0.4]);
      hurtMon(m, roll(pw, MT[m.type].def), p.uid);
      pw *= s.decay;
      m = monNear(m.x, m.y, s.jumpR, hit);
    }
    ev({ k: 'chain', pts });
  } else if (s.type === 'area') {
    let cx = p.x, cy = p.y;
    if (s.at === 'aim') {
      const dx = ax - p.x, dy = ay - p.y, dd = Math.hypot(dx, dy);
      const k = dd > s.range ? s.range / dd : 1;
      cx = p.x + dx * k; cy = p.y + dy * k;
      const tg = SIM.byId.get(d.tg);
      if (tg && !tg.dead && dist(p, tg) <= s.range && d.useTarget) { cx = tg.x; cy = tg.y; }
    }
    ev({ k: 'area', f: s.fx, x: cx, y: cy, r: s.radius, delay: s.delay || 0 });
    SIM.pending.push({ at: now + (s.delay || 0) * 1000, x: cx, y: cy, r: s.radius, power, uid: p.uid });
  }
}

// ------------------------------------------------------------
//  Dano, morte, recompensa
// ------------------------------------------------------------
function hurtMon(m, dmg, uid) {
  if (m.dead) return;
  m.hp -= dmg;
  m.dmg.set(uid, (m.dmg.get(uid) || 0) + dmg);
  ev({ k: 'dmg', x: m.x, y: m.y, v: dmg, c: '#ff5a4a' });
  const p = SIM.players.get(uid);
  if (!m.tgt && p && !p.pz) m.tgt = uid;
  if (m.hp <= 0) killMon(m);
}
function killMon(m) {
  const t = MT[m.type];
  m.dead = true; m.hp = 0;
  m.rsp = performance.now() + (t.respawn || (30 + R() * 30)) * 1000;
  ev({ k: 'die', x: m.x, y: m.y, mt: m.type, face: m.face });
  let total = 0; for (const v of m.dmg.values()) total += v;
  let top = null, topD = -1;
  const rew = new Map();
  for (const [uid, dd] of m.dmg) {
    if (!SIM.players.has(uid)) continue;
    rew.set(uid, { t: 'rew', mt: m.type, xp: Math.max(1, Math.round(t.xp * dd / total)), gold: 0, hp: 0, mp: 0 });
    if (dd > topD) { topD = dd; top = uid; }
  }
  if (top) {
    const r = rew.get(top);
    r.gold = rint(t.gold[0], t.gold[1]); r.loot = 1;
    if (R() < t.pot) { if (R() < 0.5) r.hp = 1; else r.mp = 1; }
    if (t.boss) r.hp += 3, r.mp += 3;
  }
  for (const [uid, r] of rew) sendTo(uid, r);
  if (t.boss && top) broadcast({ t: 'sys', text: `${SIM.players.get(top).name} derrotou ${t.name}! As chamas se apagam... por enquanto.`, c: 'boss' });
  m.dmg.clear(); m.tgt = null;
}
function monAttack(m, p) {
  const t = MT[m.type];
  m.atkT = 0.35;
  if (t.proj) ev({ k: 'proj', f: t.proj, x: m.x, y: m.y - 0.4, x1: p.x, y1: p.y - 0.5 });
  if (R() < 0.12) { ev({ k: 'txt', x: p.x, y: p.y, v: 'errou', c: '#bbbbbb' }); return; }
  hurtPlayer(p, t.atk * (0.5 + R() * 0.5), t.name);
}
function hurtPlayer(p, raw, src) {
  const dmg = Math.max(1, Math.round(raw * (1 - VOC[p.voc].armor * 0.5) - p.lvl * 0.2));
  ev({ k: 'dmg', x: p.x, y: p.y, v: dmg, c: '#ff2020', pl: 1 });
  sendTo(p.uid, { t: 'hit', dmg, src });
}

// ------------------------------------------------------------
//  Laço da simulação
// ------------------------------------------------------------
function hostTick(dt) {
  if (!SIM.on) return;
  const now = performance.now();
  // jogadores sem sinal somem
  for (const [uid, p] of SIM.players) if (uid !== ME.uid && now - p.seen > 15000) hostPlayerLeft(uid);
  const plist = [...SIM.players.values()];
  for (const p of plist) p.atkT = Math.max(0, p.atkT - dt);
  // áreas com atraso (meteoro, chuva)
  for (let i = SIM.pending.length - 1; i >= 0; i--) {
    const a = SIM.pending[i]; if (now < a.at) continue;
    SIM.pending.splice(i, 1);
    for (const m of SIM.mons) if (!m.dead && Math.hypot(m.x - a.x, m.y - a.y) <= a.r + MT[m.type].r) hurtMon(m, roll(a.power, MT[m.type].def), a.uid);
  }
  for (const m of SIM.mons) {
    const t = MT[m.type];
    if (m.dead) {
      if (now >= m.rsp) {
        if (plist.some(p => Math.hypot(p.x - m.sx, p.y - m.sy) < 3)) m.rsp = now + 4000;
        else { m.dead = false; m.hp = m.mhp; m.x = m.sx; m.y = m.sy; m.tgt = null; m.dmg.clear(); if (t.boss) broadcast({ t: 'sys', text: `O chão treme... ${t.name} despertou no vulcão!`, c: 'boss' }); }
      }
      continue;
    }
    // dormir longe dos jogadores
    let near = false; for (const p of plist) if (Math.abs(p.x - m.x) < 26 && Math.abs(p.y - m.y) < 20) { near = true; break; }
    if (!near) { m.mv = false; m.tgt = null; continue; }
    m.atkT = Math.max(0, m.atkT - dt); m.acd -= dt; m.scan -= dt; m.spc -= dt;
    let p = m.tgt ? SIM.players.get(m.tgt) : null;
    if (p && (p.dead || p.pz || dist(m, p) > 14)) { p = null; m.tgt = null; }
    if (!p && m.scan <= 0) {
      m.scan = 0.4;
      let bd = t.aggro;
      for (const q of plist) { if (q.dead || q.pz) continue; const d = dist(m, q); if (d < bd) { bd = d; p = q; } }
      if (p) m.tgt = p.uid;
    }
    let vx = 0, vy = 0, spd = t.spd;
    if (p) {
      const d = dist(m, p), reach = t.range + t.r + 0.25;
      m.face = p.x >= m.x ? 1 : -1;
      if (d <= reach) {
        if (m.acd <= 0) { m.acd = t.aspd; monAttack(m, p); }
        if (t.range > 2 && d < 1.8) { vx = (m.x - p.x) / d; vy = (m.y - p.y) / d; spd *= 0.6; }
      } else { vx = (p.x - m.x) / d; vy = (p.y - m.y) / d; }
      if (t.boss && m.spc <= 0 && d < 3.2) {
        m.spc = 5;
        ev({ k: 'area', f: 'nova', x: m.x, y: m.y, r: 2.6, delay: 0 });
        for (const q of plist) if (!q.dead && !q.pz && dist(m, q) <= 2.8) hurtPlayer(q, 40 + R() * 20, t.name);
      }
    } else {
      // passeio perto do ponto de nascimento
      m.wt -= dt;
      if (m.wt <= 0) {
        if (R() < 0.45) { m.wx = m.x; m.wy = m.y; m.wt = 1 + R() * 3; }
        else { const a = R() * Math.PI * 2, r = R() * 4; m.wx = m.sx + Math.cos(a) * r; m.wy = m.sy + Math.sin(a) * r; m.wt = 3 + R() * 4; }
      }
      const dx = m.wx - m.x, dy = m.wy - m.y, dd = Math.hypot(dx, dy);
      if (dd > 0.2) { vx = dx / dd; vy = dy / dd; spd *= 0.45; }
      if (Math.hypot(m.x - m.sx, m.y - m.sy) > 10) { const ex = m.sx - m.x, ey = m.sy - m.y, ed = Math.hypot(ex, ey); vx = ex / ed; vy = ey / ed; spd = t.spd; }
    }
    // desvio quando preso
    if (m.det > 0) { m.det -= dt; const c = Math.cos(m.detA), s = Math.sin(m.detA); const nx = vx * c - vy * s, ny = vx * s + vy * c; vx = nx; vy = ny; }
    // separação
    let sx = 0, sy = 0;
    for (const o of SIM.mons) {
      if (o === m || o.dead) continue;
      const dx = m.x - o.x, dy = m.y - o.y; if (Math.abs(dx) > 1.2 || Math.abs(dy) > 1.2) continue;
      const dd = Math.hypot(dx, dy), md = t.r + MT[o.type].r;
      if (dd < md && dd > 0.0001) { sx += dx / dd * (md - dd); sy += dy / dd * (md - dd); }
    }
    const ox = m.x, oy = m.y;
    const want = (vx || vy) ? spd * dt : 0;
    moveCircle(m, vx * spd * dt + sx * 0.3, vy * spd * dt + sy * 0.3, t.r * 0.85, true);
    const moved = Math.hypot(m.x - ox, m.y - oy);
    m.mv = moved > 0.002;
    if (want > 0 && moved < want * 0.3) { m.stuck += dt; if (m.stuck > 0.4 && m.det <= 0) { m.det = 0.7; m.detA = (R() < 0.5 ? 1 : -1) * (Math.PI / 2); m.stuck = 0; } }
    else m.stuck = 0;
    if (!p && Math.abs(vx) > 0.2) m.face = vx > 0 ? 1 : -1;
  }
  SIM.snapT -= dt;
  if (SIM.snapT <= 0) { SIM.snapT = 0.08; hostSnapshot(); }
}
function hostSnapshot() {
  const evs = SIM.ev; SIM.ev = [];
  const ps = [];
  for (const p of SIM.players.values()) ps.push([p.uid, p.name, p.voc, p.lvl, Math.round(p.x * 100), Math.round(p.y * 100), p.dir, Math.round(100 * clamp(p.hp / p.mhp, 0, 1)), (p.mv ? 1 : 0) | (p.atkT > 0 ? 2 : 0) | (p.dead ? 4 : 0)]);
  for (const p of SIM.players.values()) {
    const ms = [];
    for (const m of SIM.mons) {
      if (m.dead || Math.abs(m.x - p.x) > 22 || Math.abs(m.y - p.y) > 15) continue;
      ms.push([m.id, MTK.indexOf(m.type), Math.round(m.x * 100), Math.round(m.y * 100), Math.round(100 * m.hp / m.mhp), m.face, (m.mv ? 1 : 0) | (m.atkT > 0 ? 2 : 0)]);
    }
    const e = evs.filter(x => (x.k === 'chain') ? Math.abs(x.pts[0][0] - p.x) < 26 && Math.abs(x.pts[0][1] - p.y) < 18 : Math.abs(x.x - p.x) < 26 && Math.abs(x.y - p.y) < 18);
    sendTo(p.uid, { t: 's', m: ms, p: ps, ev: e });
  }
}
