'use strict';
// ============================================================
//  ARSON — cliente: jogador local, controles, render, interface
// ============================================================
const $ = id => document.getElementById(id);
const cv = $('cv'), ctx = cv.getContext('2d');
const LC = mk(4, 4), lctx = LC.getContext('2d');
let dpr = 1, zoom = 64, VIEW = { S: 1, ox: 0, oy: 0 }, vignette = null;
// ------------------------------------------------------------
//  Qualidade (automática para celulares e PCs lentos)
// ------------------------------------------------------------
const QUAL = {
  alta: { nome: 'Alta', rs: 1, dprMax: 2, light: true, parts: 1800, cq: 1, shadows: true },
  media: { nome: 'Média', rs: 1, dprMax: 1, light: true, parts: 700, cq: 1, shadows: true },
  baixa: { nome: 'Baixa', rs: 0.7, dprMax: 1, light: false, parts: 250, cq: 0.5, shadows: false },
};
const QORDER = ['alta', 'media', 'baixa'];
const IS_MOBILE = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || (navigator.maxTouchPoints > 1 && Math.min(screen.width, screen.height) < 820);
let Q = QUAL.alta, qName = 'alta';
function applyQuality(name, silent) {
  if (!QUAL[name]) name = 'alta';
  const changed = QUAL[name].cq !== CQ;
  qName = name; Q = QUAL[name];
  if (changed) { CQ = Q.cq; chunkCache.clear(); chunkQueue = []; }
  resize();
  if (!silent) toast(`Qualidade gráfica: ${Q.nome}`);
}
const perf = { acc: 0, n: 0, slow: 0 };
function perfWatch(dt) {
  if (!STORE || STORE.settings.quality !== 'auto' || document.hidden) return;
  perf.acc += dt; perf.n++;
  if (perf.n >= 90) {
    const avg = perf.acc / perf.n * 1000; perf.acc = 0; perf.n = 0;
    if (avg > 27) perf.slow++; else perf.slow = 0;
    if (perf.slow >= 2) { perf.slow = 0; const i = QORDER.indexOf(qName); if (i < QORDER.length - 1) applyQuality(QORDER[i + 1]); }
  }
}
function resize() {
  dpr = Math.min(Q.dprMax, window.devicePixelRatio || 1) * Q.rs;
  cv.width = Math.floor(innerWidth * dpr); cv.height = Math.floor(innerHeight * dpr);
  LC.width = Math.ceil(cv.width / 2); LC.height = Math.ceil(cv.height / 2);
  vignette = mk(cv.width, cv.height);
  const g = vignette.getContext('2d');
  g.fillStyle = rg(g, cv.width / 2, cv.height / 2, Math.min(cv.width, cv.height) * 0.35, cv.width / 2, cv.height / 2, Math.hypot(cv.width, cv.height) * 0.6, [[0, 'rgba(0,0,0,0)'], [1, 'rgba(0,0,0,.55)']]);
  g.fillRect(0, 0, cv.width, cv.height);
  zoom = clamp(zoom, 40, 112);
}
addEventListener('resize', resize); resize();
const GLOW = (() => { const c = mk(128, 128), g = c.getContext('2d'); g.fillStyle = rg(g, 64, 64, 0, 64, 64, 64, [[0, 'rgba(255,255,255,1)'], [0.35, 'rgba(255,255,255,.55)'], [1, 'rgba(255,255,255,0)']]); g.fillRect(0, 0, 128, 128); return c; })();
const GLOWO = (() => { const c = mk(128, 128), g = c.getContext('2d'); g.fillStyle = rg(g, 64, 64, 0, 64, 64, 64, [[0, 'rgba(255,190,90,1)'], [0.3, 'rgba(255,110,30,.5)'], [1, 'rgba(255,60,0,0)']]); g.fillRect(0, 0, 128, 128); return c; })();
const GLOWB = (() => { const c = mk(128, 128), g = c.getContext('2d'); g.fillStyle = rg(g, 64, 64, 0, 64, 64, 64, [[0, 'rgba(200,220,255,1)'], [0.3, 'rgba(110,150,255,.5)'], [1, 'rgba(60,80,255,0)']]); g.fillRect(0, 0, 128, 128); return c; })();
const GLOWG = (() => { const c = mk(128, 128), g = c.getContext('2d'); g.fillStyle = rg(g, 64, 64, 0, 64, 64, 64, [[0, 'rgba(220,255,200,1)'], [0.3, 'rgba(90,255,120,.45)'], [1, 'rgba(0,255,60,0)']]); g.fillRect(0, 0, 128, 128); return c; })();

// ------------------------------------------------------------
//  Estado
// ------------------------------------------------------------
let ME = null, playing = false;
const MON = new Map(), REM = new Map();
const FX = [], PART = [], TXT = [], DECALS = [], CORPSES = [], SPEECH = new Map();
let shake = 0, snapN = 0;
const HEIGHTS = { rato: 26, javali: 46, lobo: 48, goblin: 70, salamandra: 30, golem: 96, arson: 170, human: 84 };
const maxHp = () => maxHpOf(ME.voc, ME.lvl), maxMp = () => maxMpOf(ME.voc, ME.lvl);

// ------------------------------------------------------------
//  Salvamento (chave fixa para sempre; campos novos ganham padrão,
//  então updates nunca apagam o progresso)
// ------------------------------------------------------------
const STORE_KEY = 'arson-save', STORE_BAK = 'arson-save-bak';
const VOCS = ['guerreiro', 'mago', 'arqueiro'];
const newUid = () => 'u' + Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 6);
function defChar(voc) { return { voc, name: '', uid: newUid(), xp: 0, gold: 20, hpPot: 5, mpPot: 5, task: null, hp: null, mp: null, x: null, y: null, sk: { magia: [1, 0], defesa: [1, 0], espada: [1, 0], distancia: [1, 0] }, color: null, played: 0 }; }
function normalizeStore(st) {
  if (!st || typeof st !== 'object') st = {};
  st.v = Math.max(1, st.v | 0);
  if (!st.chars || typeof st.chars !== 'object') st.chars = {};
  for (const v of VOCS) {
    const base = defChar(v), c = st.chars[v] && typeof st.chars[v] === 'object' ? st.chars[v] : {};
    const sk = Object.assign({}, base.sk, c.sk || {});
    for (const k of SKILLS) if (!Array.isArray(sk[k]) || sk[k].length < 2) sk[k] = [Math.max(1, Number(sk[k]) || 1), 0];
    st.chars[v] = Object.assign(base, c, { voc: v, sk });
    if (!st.chars[v].uid) st.chars[v].uid = newUid();
  }
  st.settings = Object.assign({ auto: false, quality: 'auto', mini: true, zoom: 64 }, st.settings || {});
  return st;
}
function loadStore() {
  let st = null;
  for (const k of [STORE_KEY, STORE_BAK]) { try { st = JSON.parse(localStorage.getItem(k)); } catch (e) { st = null; } if (st && st.chars) break; }
  if (!st || !st.chars) { // migra o save da versão 0.2
    try { const o = JSON.parse(localStorage.getItem('arson-personagem-v1')); if (o && VOCS.includes(o.voc)) st = { chars: { [o.voc]: o } }; } catch (e) { }
  }
  return normalizeStore(st);
}
let STORE = loadStore();
function writeStore() {
  try { const s = JSON.stringify(STORE); localStorage.setItem(STORE_KEY, s); localStorage.setItem(STORE_BAK, s); } catch (e) { }
}
function saveGame() {
  if (ME) {
    const c = STORE.chars[ME.voc];
    Object.assign(c, { name: ME.name, uid: ME.uid, xp: ME.xp, gold: ME.gold, hpPot: ME.hpPot, mpPot: ME.mpPot, task: ME.task, hp: Math.round(ME.hp), mp: Math.round(ME.mp), x: ME.x, y: ME.y, sk: ME.sk, played: Date.now() });
  }
  writeStore();
}
setInterval(() => { if (playing) saveGame(); }, 5000);
addEventListener('pagehide', saveGame);
function exportSave() {
  saveGame();
  const json = JSON.stringify(STORE);
  return 'ARSON1:' + btoa(unescape(encodeURIComponent(json)));
}
function importSave(text) {
  text = String(text || '').trim();
  let json = text;
  if (text.startsWith('ARSON1:')) json = decodeURIComponent(escape(atob(text.slice(7))));
  const st = JSON.parse(json);
  if (!st || !st.chars) throw new Error('arquivo inválido');
  STORE = normalizeStore(st);
  writeStore();
}
const skArr = () => SKILLS.map(k => ME.sk[k][0]);
const skLv = () => { const o = {}; for (const k of SKILLS) o[k] = ME.sk[k][0]; return o; };
function helloMsg() { return { t: 'hi', uid: ME.uid, name: ME.name, voc: ME.voc, lvl: ME.lvl, x: ME.x, y: ME.y, sk: skArr() }; }
function skGain(k, amt) {
  if (!ME || !SKV[ME.voc].includes(k)) return;
  const s = ME.sk[k];
  s[1] += amt;
  let up = false;
  while (s[1] >= skNeed(k, s[0])) { s[1] -= skNeed(k, s[0]); s[0]++; up = true; }
  if (up) { sysMsg(`Sua habilidade de ${SKN[k]} subiu para ${s[0]}!`, 'lvl'); addText(ME.x, ME.y - 1, `${SKN[k]} ${s[0]}!`, '#9ad8ff'); if (!$('menu').hidden) renderMenu(); }
}

function startGame(voc) {
  const sv = STORE.chars[voc];
  ME = {
    uid: sv.uid, name: sv.name, voc, xp: sv.xp || 0, gold: sv.gold != null ? sv.gold : 20,
    hpPot: sv.hpPot != null ? sv.hpPot : 5, mpPot: sv.mpPot != null ? sv.mpPot : 5, task: sv.task || null, sk: JSON.parse(JSON.stringify(sv.sk)),
    x: sv.x || TEMPLO.x, y: sv.y || TEMPLO.y, dir: 2, mv: false, walk: 0, target: null, cds: {}, atkCd: 0, atkT: 0, potCd: 0, regenT: 2, autoT: 0, dead: false,
  };
  ME.lvl = levelFor(ME.xp);
  ME.hp = clamp(sv.hp || maxHp(), 1, maxHp()); ME.mp = clamp(sv.mp != null ? sv.mp : maxMp(), 0, maxMp());
  if (!isFinite(ME.x) || !isFinite(ME.y) || hitCircle(ME.x, ME.y, 0.28, false)) { ME.x = TEMPLO.x; ME.y = TEMPLO.y; }
  STORE.last = voc;
  saveGame();
  $('login').classList.add('hidden');
  document.body.classList.add('playing');
  document.body.classList.toggle('auto', !!STORE.settings.auto);
  $('log').innerHTML = ''; $('feed').innerHTML = '';
  playing = true; zoneName = '';
  buildHotbar();
  sysMsg(`Bem-vindo a Arson, ${ME.name}!`, 'lvl');
  sysMsg(STORE.settings.auto ? 'Modo automático ligado: poções infinitas e magias automáticas.' : 'Aperte H para ver os controles.', 'sys');
  netStart();
}
function backToSelect() {
  saveGame();
  netStop();
  playing = false; ME = null;
  MON.clear(); REM.clear(); FX.length = 0; PART.length = 0; TXT.length = 0; CORPSES.length = 0; DECALS.length = 0; SPEECH.clear();
  closeMenu(); closeDlg(); closeChat();
  document.body.classList.remove('playing');
  $('login').classList.remove('hidden');
  renderSelect();
}
function onNetReady() { updNet(); if (NET.isHost && !NET.offline) sysMsg('Conectado ao mundo de Arson.', 'sys'); else if (!NET.isHost) sysMsg('Conectado ao mundo de Arson.', 'sys'); else sysMsg('Sem conexão com o servidor de salas: jogando sozinho.', 'death'); }
function onNetLost() { MON.clear(); REM.clear(); if (ME) ME.target = null; }

// ------------------------------------------------------------
//  Mensagens da rede
// ------------------------------------------------------------
function clientRecv(m) {
  if (!m || typeof m !== 'object') return;
  switch (m.t) {
    case 's': applySnap(m); break;
    case 'hit': if (ME && !ME.dead) { ME.hp -= m.dmg; skGain('defesa', 1); if (ME.hp <= 0) die(m.src); } break;
    case 'rew': reward(m); break;
    case 'chat': {
      SPEECH.set(m.uid, { text: m.text, until: performance.now() + 4000 + m.text.length * 50 });
      logLine(`${m.name} [${m.lvl}]: ${m.text}`, 'say');
      break;
    }
    case 'sys': sysMsg(m.text, m.c); break;
  }
}
function applySnap(s) {
  const st = ++snapN;
  for (const a of s.m) {
    const [id, ti, x, y, hp, face, fl] = a, type = MTK[ti];
    let m = MON.get(id);
    if (!m) { m = { id, type, x: x / 100, y: y / 100, walk: 0, atkT: 0 }; MON.set(id, m); }
    m.tx = x / 100; m.ty = y / 100; m.hp = hp; m.face = face; m.mvF = fl & 1; if ((fl & 2) && m.atkT <= 0) m.atkT = 0.35; m.seen = st;
  }
  for (const [id, m] of MON) if (m.seen !== st) MON.delete(id);
  for (const a of s.p) {
    const [uid, name, voc, lvl, x, y, dir, hp, fl] = a;
    if (uid === ME.uid) continue;
    let p = REM.get(uid);
    if (!p) { p = { uid, x: x / 100, y: y / 100, walk: 0, atkT: 0 }; REM.set(uid, p); }
    Object.assign(p, { name, voc, lvl, tx: x / 100, ty: y / 100, dir, hp, mvF: fl & 1, dead: !!(fl & 4), seen: st });
    if ((fl & 2) && p.atkT <= 0) p.atkT = 0.3;
  }
  for (const [uid, p] of REM) if (p.seen !== st) REM.delete(uid);
  const now = performance.now();
  for (const e of s.ev) addEvent(e, now);
}

// ------------------------------------------------------------
//  Jogador local
// ------------------------------------------------------------
const keys = new Set();
let chatOpen = false;
function updateLocal(dt) {
  if (ME.dead) { ME.mv = false; return; }
  let ix = 0, iy = 0;
  if (!chatOpen && $('menu').hidden) {
    if (keys.has('KeyA') || keys.has('ArrowLeft')) ix -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) ix += 1;
    if (keys.has('KeyW') || keys.has('ArrowUp')) iy -= 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) iy += 1;
    ix += PAD.x + JOY.x; iy += PAD.y + JOY.y;
  }
  let len = Math.hypot(ix, iy);
  const spd = VOC[ME.voc].spd * (1 + Math.min(0.25, ME.lvl * 0.004));
  if (len > 0.15) {
    const k = Math.min(1, len) / len; ix *= k; iy *= k; // analógico: velocidade proporcional
    len = Math.hypot(ix, iy); const nx = ix / len, ny = iy / len;
    const ox = ME.x, oy = ME.y;
    moveCircle(ME, ix * spd * dt, iy * spd * dt, 0.28, false);
    ME.walk += Math.hypot(ME.x - ox, ME.y - oy);
    ME.mv = Math.hypot(ME.x - ox, ME.y - oy) > 0.0005;
    if (ME.atkT <= 0) ME.dir = Math.abs(nx) > Math.abs(ny) ? (nx > 0 ? 1 : 3) : (ny > 0 ? 2 : 0);
  } else ME.mv = false;
  if (STORE.settings.auto) autoPlay(dt);
  for (const m of MON.values()) {
    const d = Math.hypot(ME.x - m.x, ME.y - m.y), md = 0.26 + MT[m.type].r * 0.8;
    if (d < md && d > 0.001) moveCircle(ME, (ME.x - m.x) / d * (md - d) * 0.5, (ME.y - m.y) / d * (md - d) * 0.5, 0.28, false);
  }
  ME.atkCd -= dt; ME.atkT = Math.max(0, ME.atkT - dt); ME.potCd -= dt;
  for (const k in ME.cds) ME.cds[k] = Math.max(0, ME.cds[k] - dt);
  ME.regenT -= dt;
  if (ME.regenT <= 0) {
    ME.regenT = 2;
    const v = VOC[ME.voc], mult = isPZ(ME.x, ME.y) ? 3 : 1;
    ME.hp = Math.min(maxHp(), ME.hp + (v.hpReg + Math.floor(ME.lvl / 4)) * mult);
    ME.mp = Math.min(maxMp(), ME.mp + (v.mpReg + Math.floor(ME.lvl / 3)) * mult);
  }
  let tg = ME.target != null ? MON.get(ME.target) : null;
  if (ME.target != null && !tg) ME.target = null;
  if (tg && !isPZ(ME.x, ME.y)) {
    const d = Math.hypot(tg.tx - ME.x, tg.ty - ME.y);
    if (d <= VOC[ME.voc].range + MT[tg.type].r + 0.3 && ME.atkCd <= 0) {
      ME.atkCd = VOC[ME.voc].aspd; ME.atkT = 0.3; faceTo(tg.tx, tg.ty);
      toHost({ t: 'atk', tg: tg.id });
      if (ME.voc !== 'mago') skGain(PRIM[ME.voc], 1);
    }
  }
  if (dlgNpc && Math.hypot(dlgNpc.x - ME.x, dlgNpc.y - ME.y) > 4) closeDlg();
  zoneCheck();
}
function faceTo(x, y) { const dx = x - ME.x, dy = y - ME.y; ME.dir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0); }
function nearestMon(x, y, r) { let b = null, bd = r; for (const m of MON.values()) { const d = Math.hypot(m.tx - x, m.ty - y); if (d < bd) { bd = d; b = m; } } return b; }
function castSlot(i) {
  if (!ME || ME.dead || chatOpen) return;
  const s = SPELLS[ME.voc][i]; if (!s) return;
  if (ME.lvl < s.lvl) return toast(`${s.nome} requer nível ${s.lvl}.`);
  if ((ME.cds[s.k] || 0) > 0) return;
  if (ME.mp < s.mana) return toast('Mana insuficiente.');
  if (s.type !== 'heal' && isPZ(ME.x, ME.y)) return toast('Você não pode atacar dentro da cidade.');
  const tg = ME.target != null ? MON.get(ME.target) : null;
  const mw = mouseWorld();
  let ax = mw.x, ay = mw.y;
  if (tg) { ax = tg.tx; ay = tg.ty; }
  if (s.type === 'bolt' || s.type === 'chain') {
    let c = tg && Math.hypot(tg.tx - ME.x, tg.ty - ME.y) <= s.range + 1 ? tg : null;
    if (!c) { c = nearestMon(mw.x, mw.y, 2.5); if (c && Math.hypot(c.tx - ME.x, c.ty - ME.y) > s.range + 1) c = null; }
    if (!c) c = nearestMon(ME.x, ME.y, s.range);
    if (!c) return toast('Nenhum alvo ao alcance.');
    ax = c.tx; ay = c.ty;
  }
  ME.mp -= s.mana; ME.cds[s.k] = s.cd; ME.atkT = 0.3;
  skGain('magia', s.mana);
  if (s.type !== 'heal') faceTo(ax, ay);
  let v = 0;
  if (s.type === 'heal') { v = Math.round((s.base + s.perL * ME.lvl) * (1 + 0.05 * ME.sk.magia[0]) * (0.85 + Math.random() * 0.15)); ME.hp = Math.min(maxHp(), ME.hp + v); addEvent({ k: 'heal', x: ME.x, y: ME.y, v }, performance.now()); }
  SPEECH.set(ME.uid, { text: s.nome, until: performance.now() + 1500, spell: true });
  toHost({ t: 'cast', k: s.k, tg: tg ? tg.id : null, ax, ay, v, useTarget: !!tg });
}
function usePot(kind) {
  if (!ME || ME.dead || ME.potCd > 0) return false;
  const inf = STORE.settings.auto;
  if (kind === 'hp') {
    if (!inf && ME.hpPot <= 0) { toast('Sem poções de vida. Compre com Brann na cidade.'); return false; }
    if (!inf) ME.hpPot--;
    const v = 90 + ME.lvl * 3; ME.hp = Math.min(maxHp(), ME.hp + v);
    addEvent({ k: 'heal', x: ME.x, y: ME.y, v }, performance.now()); toHost({ t: 'fx', e: { k: 'heal', v } });
  } else {
    if (!inf && ME.mpPot <= 0) { toast('Sem poções de mana. Compre com Brann na cidade.'); return false; }
    if (!inf) ME.mpPot--;
    const v = 60 + ME.lvl * 3; ME.mp = Math.min(maxMp(), ME.mp + v);
    addText(ME.x, ME.y, '+' + v, '#6aa8ff');
  }
  ME.potCd = 1;
  return true;
}
// ------------------------------------------------------------
//  Modo automático (celular / controle)
// ------------------------------------------------------------
function autoPlay(dt) {
  ME.autoT -= dt; if (ME.autoT > 0 || ME.dead) return;
  ME.autoT = 0.15;
  const list = SPELLS[ME.voc], heal = list.find(s => s.type === 'heal');
  const atk = list.filter(s => s.type !== 'heal' && ME.lvl >= s.lvl);
  const hpF = ME.hp / maxHp();
  // 25%: poção de vida além da cura
  if (hpF <= 0.25) usePot('hp');
  // 50%: magia de cura (toma mana antes se faltar)
  if (hpF <= 0.5 && (ME.cds[heal.k] || 0) <= 0) {
    if (ME.mp < heal.mana) usePot('mp');
    if (ME.mp >= heal.mana) { castSlot(list.indexOf(heal)); return; }
  }
  const minMana = Math.min(heal.mana, ...atk.map(s => s.mana));
  if (ME.mp < minMana || ME.mp < maxMp() * 0.12) usePot('mp');
  if (isPZ(ME.x, ME.y)) return;
  let tg = ME.target != null ? MON.get(ME.target) : null;
  if (!tg) { const n = nearestMon(ME.x, ME.y, 7); if (n) { ME.target = n.id; tg = n; } }
  if (!tg) return;
  const d = Math.hypot(tg.tx - ME.x, tg.ty - ME.y);
  for (let i = atk.length - 1; i >= 0; i--) {
    const s = atk[i];
    if ((ME.cds[s.k] || 0) > 0) continue;
    const reach = s.type === 'area' && s.at === 'self' ? s.radius + MT[tg.type].r : s.type === 'cone' ? s.range : s.range;
    if (d > reach + 0.3) continue;
    if (ME.mp < s.mana) { usePot('mp'); if (ME.mp < s.mana) continue; }
    castSlot(list.indexOf(s));
    return;
  }
}
// ------------------------------------------------------------
//  Controle (Xbox / qualquer gamepad) e toque
// ------------------------------------------------------------
const PAD = { x: 0, y: 0, prev: [] };
function pollPad() {
  PAD.x = 0; PAD.y = 0;
  const pads = navigator.getGamepads ? navigator.getGamepads() : [];
  for (const gp of pads) {
    if (!gp) continue;
    let ax = gp.axes[0] || 0, ay = gp.axes[1] || 0;
    if (Math.hypot(ax, ay) < 0.25) { ax = 0; ay = 0; }
    const b = i => gp.buttons[i] && gp.buttons[i].pressed;
    if (b(14)) ax = -1; if (b(15)) ax = 1; if (b(12)) ay = -1; if (b(13)) ay = 1;
    PAD.x = ax; PAD.y = ay;
    const now = gp.buttons.map(x => x.pressed);
    const hit = i => now[i] && !PAD.prev[i];
    if (playing) {
      if (hit(9)) toggleMenu();
      if ($('menu').hidden) {
        if (hit(0)) targetNext();           // A: próximo alvo
        if (hit(1)) usePot('hp');           // B: poção de vida
        if (hit(2)) usePot('mp');           // X: poção de mana
        if (hit(3)) { const h = SPELLS[ME.voc].findIndex(s => s.type === 'heal'); castSlot(h); } // Y: cura
        if (hit(4)) castSlot(0); if (hit(5)) castSlot(1); if (hit(6)) castSlot(2); if (hit(7)) castSlot(3); // LB RB LT RT
      }
    } else if (hit(0) || hit(9)) { const b2 = document.querySelector('.slot-card.sel .play'); if (b2) b2.click(); }
    PAD.prev = now;
    break;
  }
}
const JOY = { x: 0, y: 0, id: null, cx: 0, cy: 0 };
function setupTouch() {
  const j = $('joy'), k = $('joyK');
  const R = 55;
  j.addEventListener('pointerdown', e => { JOY.id = e.pointerId; const r = j.getBoundingClientRect(); JOY.cx = r.left + r.width / 2; JOY.cy = r.top + r.height / 2; j.setPointerCapture(e.pointerId); moveJ(e); e.preventDefault(); });
  const moveJ = e => { if (e.pointerId !== JOY.id) return; let dx = e.clientX - JOY.cx, dy = e.clientY - JOY.cy; const d = Math.hypot(dx, dy); if (d > R) { dx *= R / d; dy *= R / d; } JOY.x = dx / R; JOY.y = dy / R; k.style.transform = `translate(${dx}px,${dy}px)`; };
  j.addEventListener('pointermove', moveJ);
  const end = e => { if (e.pointerId !== JOY.id) return; JOY.id = null; JOY.x = 0; JOY.y = 0; k.style.transform = ''; };
  j.addEventListener('pointerup', end); j.addEventListener('pointercancel', end);
  $('bTarget').onclick = () => targetNext();
  $('bChat').onclick = () => openChat();
  $('bMenu').onclick = () => toggleMenu();
}
function reward(r) {
  const t = MT[r.mt];
  const old = ME.lvl;
  ME.xp += r.xp;
  addText(ME.x, ME.y - 0.3, '+' + r.xp + ' xp', '#ffffff');
  if (r.loot) {
    const parts = [];
    if (r.gold) { ME.gold += r.gold; parts.push(`${r.gold} ouro`); }
    if (r.hp) { ME.hpPot += r.hp; parts.push(`${r.hp} poção(ões) de vida`); }
    if (r.mp) { ME.mpPot += r.mp; parts.push(`${r.mp} poção(ões) de mana`); }
    logLine(`Saque de ${t.name}: ${parts.length ? parts.join(', ') : 'nada'}.`, 'loot');
  }
  if (ME.task && ME.task.type === r.mt && ME.task.count < ME.task.need) {
    ME.task.count++;
    if (ME.task.count === ME.task.need) sysMsg('Tarefa concluída! Volte até Lira para receber a recompensa.', 'loot');
  }
  levelCheck(old);
}
function levelCheck(old) {
  const nl = levelFor(ME.xp);
  if (nl > old) {
    ME.lvl = nl; ME.hp = maxHp(); ME.mp = maxMp();
    centerMsg(`Nível ${nl}!`, 'Você ficou mais forte.');
    sysMsg(`Você avançou do nível ${old} para o nível ${nl}!`, 'lvl');
    addEvent({ k: 'lvl', x: ME.x, y: ME.y }, performance.now());
    toHost({ t: 'fx', e: { k: 'lvl' } });
    const s = SPELLS[ME.voc].find(s => s.lvl > old && s.lvl <= nl);
    if (s) sysMsg(`Nova magia liberada: ${s.nome}!`, 'lvl');
    buildHotbar();
  }
}
function die(src) {
  ME.dead = true; ME.hp = 0; ME.target = null;
  const lx = Math.floor(ME.xp * 0.08), lg2 = Math.floor(ME.gold * 0.1);
  ME.xp -= lx; ME.gold -= lg2; ME.lvl = levelFor(ME.xp);
  addEvent({ k: 'pdie', x: ME.x, y: ME.y }, performance.now()); toHost({ t: 'fx', e: { k: 'pdie' } });
  centerMsg('Você morreu', `Morto por ${src}. Perdeu ${lx} de experiência e ${lg2} de ouro.`);
  sysMsg(`Você foi morto por ${src}.`, 'death');
  setTimeout(() => { ME.dead = false; ME.x = TEMPLO.x; ME.y = TEMPLO.y; ME.hp = maxHp(); ME.mp = maxMp(); saveGame(); }, 2600);
}

// ------------------------------------------------------------
//  NPCs
// ------------------------------------------------------------
let dlgNpc = null;
function openDlg(n) {
  dlgNpc = n;
  const box = $('dlg');
  let html = `<div class="dlg-t">${n.name}</div>`;
  if (n.key === 'brann') {
    html += `<p>Olá, ${esc(ME.name)}! Poções fresquinhas, 20 de ouro cada. Você tem <b class="gold">${ME.gold}</b> de ouro.</p>
      <div class="dlg-b"><button data-a="vida1">Vida ×1</button><button data-a="vida5">Vida ×5</button><button data-a="vida20">Vida ×20</button></div>
      <div class="dlg-b"><button data-a="mana1">Mana ×1</button><button data-a="mana5">Mana ×5</button><button data-a="mana20">Mana ×20</button></div>`;
  } else {
    let task = '';
    if (ME.task) { const mt = MT[ME.task.type]; task = ME.task.count >= ME.task.need ? `Você completou a tarefa contra ${mt.name}!` : `Tarefa: ${ME.task.count}/${ME.task.need} ${mt.name}.`; }
    html += `<p>Que as chamas te guardem, ${esc(ME.name)}. ${task}</p>
      <div class="dlg-b"><button data-a="cura">Curar</button><button data-a="tarefa">${ME.task && ME.task.count >= ME.task.need ? 'Receber recompensa' : ME.task ? 'Ver tarefa' : 'Pedir tarefa'}</button></div>`;
  }
  html += `<div class="dlg-b"><button data-a="fechar" class="ghost">Fechar (Esc)</button></div>`;
  box.innerHTML = html; box.hidden = false;
  box.querySelectorAll('button').forEach(b => b.onclick = () => npcAction(b.dataset.a));
}
function closeDlg() { dlgNpc = null; $('dlg').hidden = true; }
function npcSay(text) { if (dlgNpc) { SPEECH.set(dlgNpc.id, { text, until: performance.now() + 4500 }); logLine(`${dlgNpc.name}: ${text}`, 'npc'); } }
function npcAction(a) {
  const n = dlgNpc; if (!n) return;
  if (a === 'fechar') return closeDlg();
  const m = a.match(/^(vida|mana)(\d+)$/);
  if (m) {
    const q = Number(m[2]), cost = q * 20;
    if (ME.gold < cost) npcSay(`Isso custa ${cost} de ouro, e você só tem ${ME.gold}.`);
    else { ME.gold -= cost; if (m[1] === 'vida') ME.hpPot += q; else ME.mpPot += q; npcSay(`Aqui estão ${q} poção(ões) de ${m[1]}. Boa caçada!`); }
  } else if (a === 'cura') {
    ME.hp = maxHp(); ME.mp = maxMp(); addEvent({ k: 'heal', x: ME.x, y: ME.y, v: 0 }, performance.now()); npcSay('Suas feridas se fecham e sua mente clareia.');
  } else if (a === 'tarefa') {
    if (!ME.task) {
      const [, type, need] = TASKS.find(([l]) => ME.lvl < l);
      ME.task = { type, need, count: 0 };
      npcSay(`Elimine ${need} ${MT[type].name} e volte aqui.`);
    } else if (ME.task.count >= ME.task.need) {
      const mt = MT[ME.task.type], xp = Math.round(mt.xp * ME.task.need * 1.5), gold = ME.task.need * mt.gold[1];
      const old = ME.lvl; ME.task = null; ME.gold += gold; ME.xp += xp;
      npcSay(`Excelente trabalho! Receba ${xp} de experiência e ${gold} de ouro.`);
      levelCheck(old);
    } else npcSay(`Você já eliminou ${ME.task.count} de ${ME.task.need} ${MT[ME.task.type].name}. Continue!`);
  }
  openDlg(n);
}

// ------------------------------------------------------------
//  Efeitos
// ------------------------------------------------------------
function addText(x, y, text, color, big) { TXT.push({ x, y, text, color, t0: performance.now(), dur: big ? 1600 : 1000, big }); }
function part(o) { if (PART.length < 1800) PART.push(o); }
function burst(x, y, n, col, spd, life, opt) {
  opt = opt || {};
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, v = spd * (0.3 + Math.random() * 0.7);
    part({ x: x * TS, y: y * TS, vx: Math.cos(a) * v, vy: Math.sin(a) * v * (opt.flat ? 0.5 : 1) - (opt.up || 0), life: life * (0.5 + Math.random() * 0.5), max: life, s: (opt.s || 3) * (0.6 + Math.random() * 0.8), c: col[Math.floor(Math.random() * col.length)], add: opt.add !== false, grav: opt.grav || 0, drag: opt.drag || 2 });
  }
}
const FIRE = [[255, 220, 120], [255, 150, 40], [255, 90, 20], [220, 50, 10]];
const SMOKE = [[90, 84, 80], [60, 56, 54], [120, 112, 104]];
function addEvent(e, now) {
  // efeitos próprios já foram mostrados localmente; ignora o eco da rede
  if (e.uid && ME && e.uid === ME.uid && (e.k === 'heal' || e.k === 'lvl' || e.k === 'pdie')) return;
  switch (e.k) {
    case 'dmg': addText(e.x, e.y - 0.6, String(e.v), e.c); burst(e.x, e.y - 0.4, 6, [[200, 20, 20], [140, 10, 10]], 90, 0.4, { add: false, grav: 300, s: 2.5 }); break;
    case 'txt': addText(e.x, e.y - 0.6, e.v, e.c); break;
    case 'proj': FX.push({ k: 'proj', f: e.f, x0: e.x, y0: e.y, x1: e.x1, y1: e.y1, t0: now, dur: Math.max(110, Math.hypot(e.x1 - e.x, e.y1 - e.y) * (e.f === 'flecha' ? 45 : 70)), big: e.big }); break;
    case 'slash': FX.push({ k: 'slash', x: e.x, y: e.y, a: e.a, big: e.big, t0: now, dur: 240 }); break;
    case 'cone': {
      FX.push({ k: 'cone', f: e.f, x: e.x, y: e.y, a: e.a, r: e.r, w: e.w, t0: now, dur: e.f === 'fogo' ? 520 : 300 });
      if (e.f === 'flechas') for (let i = 0; i < 7; i++) { const a = e.a - e.w + (2 * e.w) * i / 6; FX.push({ k: 'proj', f: 'flecha', x0: e.x, y0: e.y, x1: e.x + Math.cos(a) * e.r, y1: e.y + Math.sin(a) * e.r, t0: now, dur: e.r * 45 }); }
      break;
    }
    case 'chain': FX.push({ k: 'chain', pts: e.pts, t0: now, dur: 480 }); for (const [x, y] of e.pts) burst(x, y, 8, [[220, 235, 255], [140, 180, 255]], 160, 0.35, { s: 2 }); break;
    case 'area': FX.push({ k: 'area', f: e.f, x: e.x, y: e.y, r: e.r, delay: (e.delay || 0) * 1000, t0: now, dur: (e.delay || 0) * 1000 + 700, boom: false }); break;
    case 'heal':
      if (e.v) addText(e.x, e.y - 0.6, '+' + e.v, '#5dff7a');
      for (let i = 0; i < 18; i++) { const a = i / 18 * Math.PI * 2; part({ x: (e.x + Math.cos(a) * 0.45) * TS, y: (e.y + Math.sin(a) * 0.2) * TS, vx: -Math.sin(a) * 20, vy: -40 - Math.random() * 40, life: 0.9, max: 0.9, s: 2.5, c: [120, 255, 140], add: true, grav: 0, drag: 1 }); }
      FX.push({ k: 'glow', x: e.x, y: e.y - 0.4, r: 1.6, col: 'g', t0: now, dur: 600 });
      break;
    case 'lvl': FX.push({ k: 'pillar', x: e.x, y: e.y, t0: now, dur: 1500 }); burst(e.x, e.y - 0.5, 40, [[255, 230, 120], [255, 200, 60]], 120, 1.2, { up: 60, s: 2.5 }); if (e.uid && e.uid !== ME.uid) addText(e.x, e.y - 1.2, 'NÍVEL!', '#ffd23a', true); break;
    case 'die': {
      burst(e.x, e.y - 0.3, 14, SMOKE, 50, 0.9, { add: false, up: 30, s: 5 });
      if (e.mt) CORPSES.push({ mt: e.mt, x: e.x, y: e.y, face: e.face || 1, t0: now });
      if (e.mt === 'arson') { burst(e.x, e.y - 1, 120, FIRE, 320, 1.4, { s: 4 }); shake = 18; DECALS.push({ x: e.x, y: e.y, r: 3.5, t0: now, life: 20000 }); }
      break;
    }
    case 'pdie': burst(e.x, e.y - 0.4, 20, SMOKE, 60, 1, { add: false, up: 30, s: 5 }); break;
  }
}

function updateFx(dt, now) {
  for (let i = PART.length - 1; i >= 0; i--) {
    const p = PART[i]; p.life -= dt;
    if (p.life <= 0) { PART.splice(i, 1); continue; }
    p.vy += p.grav * dt; const k = Math.max(0, 1 - p.drag * dt); p.vx *= k; p.vy *= k;
    p.x += p.vx * dt; p.y += p.vy * dt;
  }
  for (let i = TXT.length - 1; i >= 0; i--) if (now - TXT[i].t0 > TXT[i].dur) TXT.splice(i, 1);
  for (let i = DECALS.length - 1; i >= 0; i--) if (now - DECALS[i].t0 > DECALS[i].life) DECALS.splice(i, 1);
  for (let i = CORPSES.length - 1; i >= 0; i--) if (now - CORPSES[i].t0 > 14000) CORPSES.splice(i, 1);
  shake = Math.max(0, shake - dt * 40);
}
function updateRemote(dt) {
  const k = Math.min(1, dt * 11);
  const step = (e, dirFromFace) => {
    if (e.tx == null) return;
    const dx = e.tx - e.x, dy = e.ty - e.y, d = Math.hypot(dx, dy);
    if (d > 3) { e.x = e.tx; e.y = e.ty; }
    else { e.x += dx * k; e.y += dy * k; e.walk += d * k; }
    e.mv = e.mvF || d > 0.03;
    e.atkT = Math.max(0, e.atkT - dt);
  };
  for (const m of MON.values()) step(m);
  for (const p of REM.values()) step(p);
}

// ------------------------------------------------------------
//  Render
// ------------------------------------------------------------
let firstFrame = true;
function render(now, dt) {
  const cw = cv.width, ch = cv.height, S = zoom * dpr / TS;
  let camX, camY;
  if (playing) { camX = ME.x; camY = ME.y - 0.5; }
  else { camX = CX + 0.5 + Math.sin(now / 9000) * 7; camY = CY + 0.5 + Math.cos(now / 12000) * 5; }
  if (shake > 0) { camX += (Math.random() - 0.5) * shake / TS; camY += (Math.random() - 0.5) * shake / TS; }
  const ox = cw / 2 - camX * TS * S, oy = ch / 2 - camY * TS * S;
  VIEW = { S, ox, oy, camX, camY };
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.fillStyle = '#0b0806'; ctx.fillRect(0, 0, cw, ch);
  ctx.setTransform(S, 0, 0, S, ox, oy);
  ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
  const vw = cw / (TS * S), vh = ch / (TS * S);
  const tx0 = Math.floor(camX - vw / 2) - 1, tx1 = Math.ceil(camX + vw / 2) + 1, ty0 = Math.floor(camY - vh / 2) - 1, ty1 = Math.ceil(camY + vh / 2) + 1;
  // chão
  const cx0 = Math.floor(tx0 / CH), cx1 = Math.floor(tx1 / CH), cy0 = Math.floor(ty0 / CH), cy1 = Math.floor(ty1 / CH);
  for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++) {
    if (cx < 0 || cy < 0 || cx * CH >= W || cy * CH >= H) { ctx.fillStyle = '#1d3a16'; ctx.fillRect(cx * CPX, cy * CPX, CPX + 1, CPX + 1); continue; }
    const c = getChunk(cx, cy);
    if (c) ctx.drawImage(c, cx * CPX, cy * CPX, CPX + 0.6, CPX + 0.6);
    else { ctx.fillStyle = '#3d5e2c'; ctx.fillRect(cx * CPX, cy * CPX, CPX + 1, CPX + 1); }
  }
  // pré-carrega um anel em volta
  for (let cy = cy0 - 1; cy <= cy1 + 1; cy++) for (let cx = cx0 - 1; cx <= cx1 + 1; cx++) if (cx >= 0 && cy >= 0 && cx * CH < W && cy * CH < H) { if (!chunkCache.has(chunkKey(cx, cy)) && !chunkQueue.includes(chunkKey(cx, cy))) chunkQueue.push(chunkKey(cx, cy)); }
  chunkQueue.sort((a, b) => { const da = Math.hypot(Math.floor(a / 1000) * CH + 4 - camX, (a % 1000) * CH + 4 - camY), db = Math.hypot(Math.floor(b / 1000) * CH + 4 - camX, (b % 1000) * CH + 4 - camY); return da - db; });
  pumpChunks(firstFrame ? 0 : 10, firstFrame); firstFrame = false;

  const lights = [];
  const t = now / 1000;
  // água e lava animadas
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    const tt = tileAt(tx, ty);
    if (tt === T.WATER) {
      const h = hash2(tx, ty, 200), ph = t * 0.6 + h * 6.28;
      ctx.fillStyle = `rgba(255,255,255,${0.05 + 0.05 * Math.sin(ph)})`;
      ctx.beginPath(); ctx.ellipse((tx + 0.3 + 0.4 * h) * TS + Math.sin(ph) * 7, (ty + 0.5) * TS + Math.cos(ph * 0.7) * 5, 11, 2, 0, 0, 7); ctx.fill();
    } else if (tt === T.LAVA) {
      const h = hash2(tx, ty, 201);
      ctx.globalCompositeOperation = 'lighter';
      ctx.globalAlpha = 0.18 + 0.12 * Math.sin(t * 1.6 + h * 6.28);
      ctx.drawImage(GLOWO, (tx - 0.3) * TS, (ty - 0.3) * TS, TS * 1.6, TS * 1.6);
      ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
      if ((tx + ty) % 2 === 0) lights.push([tx + 0.5, ty + 0.5, 1.8, 0.55]);
      if (Math.random() < 0.004) part({ x: (tx + Math.random()) * TS, y: (ty + Math.random()) * TS, vx: 0, vy: -30, life: 0.8, max: 0.8, s: 3, c: FIRE[1], add: true, grav: -20, drag: 0.5 });
    }
  }
  // marcas no chão
  for (const d of DECALS) {
    const a = 1 - (now - d.t0) / d.life;
    ctx.globalAlpha = Math.min(1, a * 2) * 0.55;
    ctx.fillStyle = rg(ctx, d.x * TS, d.y * TS, 0, d.x * TS, d.y * TS, d.r * TS, [[0, 'rgba(10,6,4,1)'], [0.6, 'rgba(30,16,10,.6)'], [1, 'rgba(0,0,0,0)']]);
    ctx.beginPath(); ctx.ellipse(d.x * TS, d.y * TS, d.r * TS, d.r * TS * 0.75, 0, 0, 7); ctx.fill();
    ctx.globalAlpha = 1;
  }
  // corpos
  for (const c of CORPSES) {
    const a = clamp((14000 - (now - c.t0)) / 3000, 0, 1);
    if (c.mt === 'arson') continue;
    const fr = getFrame(c.mt, 1, 0), L = LOOKS[c.mt];
    ctx.save(); ctx.globalAlpha = a * 0.85; ctx.translate(c.x * TS, c.y * TS);
    if (L.type === 'quad') { ctx.scale(c.face, -0.9); ctx.drawImage(fr, -FAX, -FAY * 0.2 - 10); }
    else { ctx.rotate(Math.PI / 2 * c.face); ctx.drawImage(fr, -FAX, -FAY); }
    ctx.restore();
    ctx.globalAlpha = a * 0.35; ctx.fillStyle = '#5a0a0a'; ctx.beginPath(); ctx.ellipse(c.x * TS, c.y * TS + 4, 18, 7, 0, 0, 7); ctx.fill(); ctx.globalAlpha = 1;
  }
  // sombras das árvores
  ctx.fillStyle = 'rgba(0,0,0,.22)';
  for (let ty = ty0; ty <= ty1 + 3; ty++) for (let tx = tx0 - 2; tx <= tx1 + 2; tx++) {
    const tt = tileAt(tx, ty);
    if (tt === T.TREE) { ctx.beginPath(); ctx.ellipse((tx + 0.8) * TS, (ty + 0.75) * TS, TS * 1.15, TS * 0.42, 0, 0, 7); ctx.fill(); }
  }
  // lista ordenada por profundidade
  const D = [];
  for (let ty = ty0; ty <= ty1 + 4; ty++) for (let tx = tx0 - 2; tx <= tx1 + 2; tx++) {
    const tt = tileAt(tx, ty);
    if (tt === T.TREE || tt === T.DEADTREE || tt === T.ROCK) D.push({ y: ty + 0.75, k: 1, tx, ty, tt });
    else if (tt === T.WALL && ty <= ty1 + 1) D.push({ y: ty + 1, k: 2, tx, ty });
  }
  for (const p of PROPS) if (p.x > tx0 - 2 && p.x < tx1 + 2 && p.y > ty0 && p.y < ty1 + 3) D.push({ y: p.y, k: 3, p });
  for (const n of NPCS) D.push({ y: n.y, k: 4, e: n, look: n.look, dir: 2 });
  for (const m of MON.values()) D.push({ y: m.y, k: 4, e: m, look: m.type, mon: true });
  for (const p of REM.values()) if (!p.dead) D.push({ y: p.y, k: 4, e: p, look: p.voc, dir: p.dir });
  if (playing && !ME.dead) D.push({ y: ME.y, k: 4, e: ME, look: ME.voc, dir: ME.dir, me: true });
  D.sort((a, b) => a.y - b.y);
  for (const it of D) {
    if (it.k === 1) drawObj(it, now);
    else if (it.k === 2) drawWall(it.tx, it.ty);
    else if (it.k === 3) drawProp(it.p, t, lights);
    else drawEnt(it, now, t, lights);
  }
  // efeitos
  drawFx(now, lights);
  for (const p of PART) {
    const a = clamp(p.life / p.max, 0, 1);
    if (p.add) ctx.globalCompositeOperation = 'lighter';
    ctx.fillStyle = `rgba(${p.c[0]},${p.c[1]},${p.c[2]},${a})`;
    ctx.beginPath(); ctx.arc(p.x, p.y, p.s * (0.4 + a * 0.6), 0, 7); ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
  }
  // iluminação
  const vd = Math.hypot(camX - VX, camY - VY);
  const amb = clamp((34 - vd) / 18, 0, 1) * 0.62;
  ctx.globalCompositeOperation = 'lighter';
  for (const [x, y, r, i, col] of lights) { ctx.globalAlpha = i * 0.28; ctx.drawImage(col === 'b' ? GLOWB : col === 'g' ? GLOWG : GLOWO, (x - r) * TS, (y - r) * TS, r * 2 * TS, r * 2 * TS); }
  ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  if (amb > 0.01) {
    lctx.setTransform(1, 0, 0, 1, 0, 0); lctx.globalCompositeOperation = 'source-over';
    lctx.clearRect(0, 0, LC.width, LC.height);
    lctx.fillStyle = `rgba(26,6,2,${amb})`; lctx.fillRect(0, 0, LC.width, LC.height);
    lctx.globalCompositeOperation = 'destination-out';
    lctx.setTransform(S / 2, 0, 0, S / 2, ox / 2, oy / 2);
    if (playing) lights.push([ME.x, ME.y - 0.4, 3.2, 0.7]);
    for (const [x, y, r, i] of lights) { lctx.globalAlpha = Math.min(1, i); lctx.drawImage(GLOW, (x - r) * TS, (y - r) * TS, r * 2 * TS, r * 2 * TS); }
    lctx.globalAlpha = 1;
    ctx.drawImage(LC, 0, 0, cw, ch);
    // cinzas flutuando
    if (Math.random() < amb * 0.9) part({ x: (camX + (Math.random() - 0.5) * vw) * TS, y: (camY + vh / 2) * TS, vx: (Math.random() - 0.5) * 20, vy: -40 - Math.random() * 40, life: 4, max: 4, s: 1.6, c: FIRE[Math.floor(Math.random() * 3)], add: true, grav: 0, drag: 0 });
  }
  ctx.drawImage(vignette, 0, 0);
  if (playing) drawOverlayText(now);
}
function treeSpr(tx, ty) { const h = Math.floor(hash2(tx, ty, 300) * 1000); return vnoise(tx / 9, ty / 9, 301) > 0.56 ? TREES[3 + h % 2] : TREES[h % 3]; }
function drawObj(it, now) {
  const { tx, ty, tt } = it, h = hash2(tx, ty, 302);
  let spr, sc, x, y;
  if (tt === T.TREE) { spr = treeSpr(tx, ty); sc = 0.82 + h * 0.3; x = (tx + 0.5 + (h - 0.5) * 0.25) * TS; y = (ty + 0.72) * TS; }
  else if (tt === T.DEADTREE) { spr = DEADTREES[Math.floor(h * 3)]; sc = 0.75 + h * 0.25; x = (tx + 0.5) * TS; y = (ty + 0.75) * TS; }
  else { spr = ROCKS[(grdOf(tx, ty) === T.ASH ? 2 : 0) + Math.floor(h * 2)]; sc = 0.62 + h * 0.2; x = (tx + 0.5) * TS; y = (ty + 0.75) * TS; }
  let a = 1;
  if (playing && tt === T.TREE && ME.y < ty + 0.6 && ME.y > ty - 2.4 && Math.abs(ME.x - (tx + 0.5)) < 1.4) a = 0.42;
  ctx.globalAlpha = a;
  ctx.drawImage(spr.c, x - spr.ax * sc, y - spr.ay * sc, spr.c.width * sc, spr.c.height * sc);
  ctx.globalAlpha = 1;
}
function drawWall(tx, ty) {
  const x = tx * TS, y = ty * TS;
  ctx.drawImage(WALL_TOP, x, y - WALLH, TS + 0.5, TS + 0.5);
  if (tileAt(tx, ty + 1) !== T.WALL) {
    ctx.drawImage(WALL_FRONT, x, y + TS - WALLH, TS + 0.5, WALLH);
    // ameias
    ctx.fillStyle = '#9d9482';
    for (let i = 0; i < 3; i++) ctx.fillRect(x + 4 + i * 22, y + TS - WALLH - 10, 12, 10);
  }
  if (tileAt(tx, ty - 1) !== T.WALL) { ctx.fillStyle = '#9d9482'; for (let i = 0; i < 3; i++) ctx.fillRect(x + 4 + i * 22, y - WALLH - 8, 12, 9); }
  if (tileAt(tx - 1, ty) !== T.WALL) { ctx.fillStyle = 'rgba(0,0,0,.3)'; ctx.fillRect(x, y - WALLH, 4, TS); }
  if (tileAt(tx + 1, ty) !== T.WALL) { ctx.fillStyle = 'rgba(0,0,0,.4)'; ctx.fillRect(x + TS - 4, y - WALLH, 4, TS + WALLH); }
}
function drawProp(p, t, lights) {
  const a = PROPART[p.k];
  ctx.drawImage(a.c, p.x * TS - a.ax, p.y * TS - a.ay);
  if (a.fire) { const fx = p.x * TS - a.ax + a.fire[0], fy = p.y * TS - a.ay + a.fire[1]; flame(ctx, fx, fy, a.fire[2], t, p.x * 7 + p.y); lights.push([fx / TS, fy / TS, 3, 0.85]); if (Math.random() < 0.08) part({ x: fx, y: fy - 10, vx: (Math.random() - 0.5) * 20, vy: -50, life: 0.9, max: 0.9, s: 1.6, c: FIRE[0], add: true, grav: -10, drag: 0.5 }); }
  if (a.candles) for (const [cx, cy] of a.candles) { flame(ctx, p.x * TS - a.ax + cx, p.y * TS - a.ay + cy, 0.35, t, cx); }
}
function entFrame(it) {
  const e = it.e, L = LOOKS[it.look];
  let dir = it.dir;
  if (it.mon || it.look === 'goblin') dir = (e.face || 1) > 0 ? 1 : 3;
  let fi = 0;
  const atkT = e.atkT || 0;
  if (atkT > 0) fi = 9 + clamp(Math.floor((1 - atkT / 0.35) * 3), 0, 2);
  else if (e.mv) fi = 1 + Math.floor(e.walk / (L.type === 'quad' ? 0.09 : 0.11)) % 8;
  return { dir, fi, L };
}
function drawEnt(it, now, t, lights) {
  const e = it.e, x = e.x * TS, y = e.y * TS;
  // seleção do alvo
  if (it.mon && ME && ME.target === e.id) {
    const r = MT[e.type].r * TS + 14;
    ctx.strokeStyle = 'rgba(255,50,40,.9)'; ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.ellipse(x, y, r, r * 0.45, 0, 0, 7); ctx.stroke();
    ctx.strokeStyle = 'rgba(255,120,90,.35)'; ctx.lineWidth = 6; ctx.stroke();
  }
  if (it.look === 'arson') { drawArson(x, y, t, e.atkT > 0, lights); return; }
  const { dir, fi, L } = entFrame(it);
  const sc = it.look === 'golem' ? 1.25 : 1;
  ctx.fillStyle = 'rgba(0,0,0,.32)';
  ctx.beginPath(); ctx.ellipse(x, y - 1, (L.type === 'quad' ? L.len * 0.55 : 15) * sc, 6 * sc, 0, 0, 7); ctx.fill();
  const fr = getFrame(it.look, dir, fi);
  ctx.save(); ctx.translate(x, y);
  if (dir === 3) ctx.scale(-1, 1);
  if (sc !== 1) ctx.scale(sc, sc);
  ctx.drawImage(fr, -FAX, -FAY);
  // fogo vivo
  if (it.look === 'goblin') { const hx = 14, hy = -48; flame(ctx, hx, hy, 0.6, t, e.id || 1); }
  if (it.look === 'salamandra') { for (let i = 0; i < 4; i++) flame(ctx, -16 + i * 9, -20, 0.45 + 0.1 * Math.sin(t * 3 + i), t, i * 3 + (e.id || 0)); }
  ctx.restore();
  if (it.look === 'goblin') lights.push([e.x + (dir === 3 ? -0.22 : 0.22), e.y - 0.8, 2.4, 0.7]);
  if (it.look === 'salamandra') lights.push([e.x, e.y - 0.4, 2, 0.6]);
  if (it.look === 'golem') lights.push([e.x, e.y - 1, 2.2, 0.5]);
  if (it.look === 'mago') { const d = dir; const ox2 = d === 2 ? -15 : d === 0 ? 15 : d === 1 ? 6 : -6; lights.push([e.x + ox2 / TS, e.y - 1.4, 1.2, 0.6]); }
  if (it.look === 'lobo' && Math.random() < 0.05) part({ x: x - (e.face || 1) * 20, y: y - 30, vx: 0, vy: -15, life: 1.2, max: 1.2, s: 4, c: SMOKE[2], add: false, grav: 0, drag: 0.3 });
}
function drawArson(x, y, t, atk, lights) {
  ctx.fillStyle = 'rgba(0,0,0,.35)'; ctx.beginPath(); ctx.ellipse(x, y, 44, 14, 0, 0, 7); ctx.fill();
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  const s = atk ? 1.12 : 1;
  ctx.globalAlpha = 0.5; ctx.drawImage(GLOWO, x - 130, y - 230, 260, 260); ctx.globalAlpha = 1;
  // corpo
  const body = (col, k) => {
    ctx.fillStyle = col; ctx.beginPath();
    ctx.moveTo(x - 30 * k * s, y - 4);
    ctx.quadraticCurveTo(x - 46 * k * s, y - 70, x - 26 * k * s, y - 112 * s);
    ctx.quadraticCurveTo(x - 50 * k * s, y - 120 * s + Math.sin(t * 5) * 6, x - 56 * k * s, y - 150 * s);
    ctx.quadraticCurveTo(x - 20 * k, y - 138 * s, x - 14 * k, y - 132 * s);
    ctx.quadraticCurveTo(x, y - 178 * s + Math.sin(t * 7) * 8, x + 14 * k, y - 132 * s);
    ctx.quadraticCurveTo(x + 20 * k, y - 138 * s, x + 56 * k * s, y - 150 * s);
    ctx.quadraticCurveTo(x + 50 * k * s, y - 120 * s + Math.cos(t * 5) * 6, x + 26 * k * s, y - 112 * s);
    ctx.quadraticCurveTo(x + 46 * k * s, y - 70, x + 30 * k * s, y - 4);
    ctx.quadraticCurveTo(x, y + 6, x - 30 * k * s, y - 4);
    ctx.fill();
  };
  body('rgba(200,40,10,.55)', 1.1); body('rgba(255,110,20,.6)', 0.85); body('rgba(255,200,90,.55)', 0.55);
  for (let i = 0; i < 12; i++) { const a = i / 12; flame(ctx, x - 40 + a * 80, y - 20 - Math.sin(a * Math.PI) * 100, 1.1 + Math.sin(t * 4 + i) * 0.3, t, i * 13); }
  ctx.globalCompositeOperation = 'source-over';
  ctx.fillStyle = '#fff'; for (const ex of [-9, 9]) { ctx.beginPath(); ctx.ellipse(x + ex, y - 120 * s, 5, 3, ex > 0 ? -0.3 : 0.3, 0, 7); ctx.fill(); }
  ctx.restore();
  lights.push([x / TS, y / TS - 1.5, 6, 1]);
  if (Math.random() < 0.5) part({ x: x + (Math.random() - 0.5) * 70, y: y - Math.random() * 120, vx: (Math.random() - 0.5) * 30, vy: -80 - Math.random() * 60, life: 1, max: 1, s: 2.5, c: FIRE[Math.floor(Math.random() * 3)], add: true, grav: 0, drag: 0.5 });
}

function drawFx(now, lights) {
  for (let i = FX.length - 1; i >= 0; i--) {
    const f = FX[i], el = now - f.t0, p = el / f.dur;
    if (p >= 1) {
      if (f.k === 'proj') impact(f);
      FX.splice(i, 1); continue;
    }
    if (f.k === 'proj') {
      const x = lerp(f.x0, f.x1, p) * TS, y = lerp(f.y0, f.y1, p) * TS, a = Math.atan2(f.y1 - f.y0, f.x1 - f.x0);
      if (f.f === 'flecha') {
        ctx.save(); ctx.translate(x, y); ctx.rotate(a);
        ctx.strokeStyle = '#6b4422'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(-16, 0); ctx.lineTo(10, 0); ctx.stroke();
        ctx.fillStyle = '#c8ccd0'; ctx.beginPath(); ctx.moveTo(14, 0); ctx.lineTo(8, -3.5); ctx.lineTo(8, 3.5); ctx.fill();
        ctx.fillStyle = '#eeeeee'; ctx.beginPath(); ctx.moveTo(-16, 0); ctx.lineTo(-20, -4); ctx.lineTo(-12, 0); ctx.lineTo(-20, 4); ctx.fill();
        ctx.restore();
      } else {
        const big = f.big ? 1.5 : 1, col = f.f === 'arcano' ? GLOWB : GLOWO;
        ctx.globalCompositeOperation = 'lighter';
        ctx.drawImage(col, x - 26 * big, y - 26 * big, 52 * big, 52 * big);
        ctx.fillStyle = f.f === 'arcano' ? 'rgba(230,220,255,.95)' : 'rgba(255,240,190,.95)';
        ctx.beginPath(); ctx.arc(x, y, 5 * big, 0, 7); ctx.fill();
        ctx.globalCompositeOperation = 'source-over';
        for (let k = 0; k < 2; k++) part({ x: x + (Math.random() - 0.5) * 6, y: y + (Math.random() - 0.5) * 6, vx: -Math.cos(a) * 40 + (Math.random() - 0.5) * 30, vy: -Math.sin(a) * 40 + (Math.random() - 0.5) * 30, life: 0.35, max: 0.35, s: 3.5 * big, c: f.f === 'arcano' ? [170, 150, 255] : FIRE[1 + Math.floor(Math.random() * 2)], add: true, grav: 0, drag: 3 });
        lights.push([x / TS, y / TS, 2 * big, 0.8, f.f === 'arcano' ? 'b' : undefined]);
      }
    } else if (f.k === 'slash') {
      const x = f.x * TS, y = f.y * TS, R = f.big ? 40 : 28;
      ctx.save(); ctx.translate(x, y); ctx.rotate(f.a);
      ctx.globalCompositeOperation = 'lighter';
      const s0 = -1.3 + p * 1.2, s1 = s0 + 1.4;
      ctx.strokeStyle = `rgba(255,255,255,${0.9 * (1 - p)})`; ctx.lineWidth = 6 * (1 - p) + 1;
      ctx.beginPath(); ctx.arc(-R * 0.4, 0, R, s0, s1); ctx.stroke();
      ctx.strokeStyle = `rgba(255,200,140,${0.5 * (1 - p)})`; ctx.lineWidth = 12 * (1 - p);
      ctx.beginPath(); ctx.arc(-R * 0.4, 0, R * 0.9, s0, s1); ctx.stroke();
      ctx.restore();
    } else if (f.k === 'cone') {
      const x = f.x * TS, y = f.y * TS, R = f.r * TS;
      if (f.f === 'fogo') {
        if (p < 0.7) for (let k = 0; k < 9; k++) {
          const a = f.a + (Math.random() - 0.5) * 2 * f.w, v = R * (1.4 + Math.random() * 0.8);
          part({ x: x + Math.cos(a) * 12, y: y + Math.sin(a) * 12, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: 0.55, max: 0.55, s: 7 + Math.random() * 6, c: FIRE[Math.floor(Math.random() * 4)], add: true, grav: -40, drag: 2.2 });
        }
        ctx.globalCompositeOperation = 'lighter';
        ctx.fillStyle = rg(ctx, x, y, 0, x, y, R, [[0, `rgba(255,200,90,${0.45 * (1 - p)})`], [1, 'rgba(255,60,0,0)']]);
        ctx.beginPath(); ctx.moveTo(x, y); ctx.arc(x, y, R, f.a - f.w, f.a + f.w); ctx.closePath(); ctx.fill();
        ctx.globalCompositeOperation = 'source-over';
        lights.push([f.x + Math.cos(f.a) * f.r * 0.5, f.y + Math.sin(f.a) * f.r * 0.5, f.r, 0.9 * (1 - p)]);
      } else if (f.f === 'corte') {
        ctx.save(); ctx.globalCompositeOperation = 'lighter';
        ctx.fillStyle = rg(ctx, x, y, R * 0.3, x, y, R, [[0, 'rgba(255,255,255,0)'], [0.8, `rgba(255,255,255,${0.55 * (1 - p)})`], [1, 'rgba(255,255,255,0)']]);
        const sw = f.a - f.w + p * 2 * f.w;
        ctx.beginPath(); ctx.moveTo(x, y); ctx.arc(x, y, R, f.a - f.w, sw); ctx.closePath(); ctx.fill();
        ctx.restore();
      }
    } else if (f.k === 'chain') {
      ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      const fade = 1 - p;
      for (let s = 0; s < f.pts.length - 1; s++) {
        const [ax, ay] = f.pts[s], [bx, by] = f.pts[s + 1];
        const pts = [[ax * TS, ay * TS]];
        const n = 7;
        for (let k = 1; k < n; k++) { const q = k / n; pts.push([lerp(ax, bx, q) * TS + (Math.random() - 0.5) * 22, lerp(ay, by, q) * TS + (Math.random() - 0.5) * 22]); }
        pts.push([bx * TS, by * TS]);
        for (const [w, c] of [[10, `rgba(90,130,255,${0.35 * fade})`], [4, `rgba(170,200,255,${0.85 * fade})`], [1.6, `rgba(255,255,255,${fade})`]]) {
          ctx.strokeStyle = c; ctx.lineWidth = w; ctx.beginPath(); pts.forEach((q, i) => i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1])); ctx.stroke();
        }
        lights.push([bx, by, 2.4, 0.9 * fade, 'b']);
      }
      ctx.restore();
    } else if (f.k === 'area') drawArea(f, el, now, lights);
    else if (f.k === 'glow') { ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = 1 - p; ctx.drawImage(f.col === 'g' ? GLOWG : GLOWO, (f.x - f.r) * TS, (f.y - f.r) * TS, f.r * 2 * TS, f.r * 2 * TS); ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over'; }
    else if (f.k === 'pillar') {
      const x = f.x * TS, y = f.y * TS, a = Math.sin(p * Math.PI);
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = lg(ctx, 0, y - 260, 0, y, [[0, 'rgba(255,220,100,0)'], [0.7, `rgba(255,220,100,${0.5 * a})`], [1, `rgba(255,255,200,${0.8 * a})`]]);
      ctx.fillRect(x - 22, y - 260, 44, 262);
      ctx.globalCompositeOperation = 'source-over';
      lights.push([f.x, f.y - 1, 3, a]);
    }
  }
}
function impact(f) {
  if (f.f === 'flecha') burst(f.x1, f.y1, 5, [[200, 180, 150]], 60, 0.3, { add: false, s: 2 });
  else if (f.f === 'arcano') burst(f.x1, f.y1, 12, [[200, 180, 255], [140, 110, 255]], 120, 0.4, { s: 3 });
  else burst(f.x1, f.y1, f.big ? 26 : 12, FIRE, f.big ? 180 : 120, 0.5, { s: 4 });
}
function drawArea(f, el, now, lights) {
  const x = f.x * TS, y = f.y * TS, R = f.r * TS;
  const pre = el < f.delay, q = pre ? el / Math.max(1, f.delay) : (el - f.delay) / 700;
  if (pre) {
    ctx.strokeStyle = `rgba(255,80,40,${0.3 + 0.4 * q})`; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.ellipse(x, y, R * q, R * q * 0.7, 0, 0, 7); ctx.stroke();
    ctx.fillStyle = `rgba(255,60,20,${0.12 * q})`; ctx.beginPath(); ctx.ellipse(x, y, R, R * 0.7, 0, 0, 7); ctx.fill();
    if (f.f === 'meteoro') {
      const mx = x + (1 - q) * 3 * TS, my = y - (1 - q) * 7 * TS;
      ctx.globalCompositeOperation = 'lighter';
      ctx.drawImage(GLOWO, mx - 50, my - 50, 100, 100);
      ctx.globalCompositeOperation = 'source-over';
      ctx.fillStyle = '#3a2a22'; ctx.beginPath(); ctx.arc(mx, my, 13, 0, 7); ctx.fill();
      ctx.fillStyle = '#ffb04a'; ctx.beginPath(); ctx.arc(mx - 4, my + 4, 6, 0, 7); ctx.fill();
      for (let k = 0; k < 4; k++) part({ x: mx, y: my, vx: 120 + Math.random() * 60, vy: -260 + Math.random() * 60, life: 0.4, max: 0.4, s: 8, c: FIRE[Math.floor(Math.random() * 4)], add: true, grav: 0, drag: 3 });
      lights.push([mx / TS, my / TS, 3, 0.9]);
    } else if (f.f === 'chuva') {
      for (let k = 0; k < 3; k++) { const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random()) * f.r; FX.push({ k: 'proj', f: 'flecha', x0: f.x + Math.cos(a) * r - 1.2, y0: f.y + Math.sin(a) * r * 0.7 - 4, x1: f.x + Math.cos(a) * r, y1: f.y + Math.sin(a) * r * 0.7, t0: now, dur: 220 }); }
    }
    return;
  }
  if (!f.boom) {
    f.boom = true;
    if (f.f === 'meteoro' || f.f === 'nova') {
      burst(f.x, f.y, 90, FIRE, R * 2.2, 0.8, { s: 6, flat: true, drag: 3 });
      burst(f.x, f.y, 20, [[50, 40, 36], [80, 70, 60]], 260, 0.9, { add: false, s: 3.5, grav: 500, up: 200 });
      DECALS.push({ x: f.x, y: f.y, r: f.r * 0.9, t0: now, life: 8000 });
      if (ME && Math.hypot(ME.x - f.x, ME.y - f.y) < 10) shake = Math.max(shake, f.f === 'meteoro' ? 14 : 8);
    } else if (f.f === 'giro') burst(f.x, f.y, 30, [[220, 210, 190]], R * 2, 0.5, { add: false, s: 3, flat: true });
    else if (f.f === 'chuva') burst(f.x, f.y, 30, [[180, 160, 130]], R * 1.6, 0.5, { add: false, s: 2.5, flat: true });
  }
  const a = 1 - q;
  if (f.f === 'meteoro' || f.f === 'nova') {
    ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = `rgba(255,200,100,${a})`; ctx.lineWidth = 10 * a + 2;
    ctx.beginPath(); ctx.ellipse(x, y, R * (0.3 + q * 0.9), R * (0.3 + q * 0.9) * 0.7, 0, 0, 7); ctx.stroke();
    ctx.globalAlpha = a; ctx.drawImage(GLOWO, x - R * 1.4, y - R * 1.2, R * 2.8, R * 2.4); ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    lights.push([f.x, f.y, f.r * 2.2, a]);
  } else if (f.f === 'giro') {
    ctx.save(); ctx.translate(x, y); ctx.globalCompositeOperation = 'lighter';
    for (let k = 0; k < 3; k++) {
      const s0 = q * 10 + k * 2.1;
      ctx.strokeStyle = `rgba(255,255,255,${0.8 * a})`; ctx.lineWidth = 5 * a + 1;
      ctx.beginPath(); ctx.ellipse(0, -16, R * 0.8, R * 0.45, 0, s0, s0 + 1.2); ctx.stroke();
    }
    ctx.restore();
  } else if (f.f === 'chuva') {
    ctx.strokeStyle = `rgba(230,220,200,${0.5 * a})`; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.ellipse(x, y, R * (0.5 + q * 0.5), R * (0.5 + q * 0.5) * 0.7, 0, 0, 7); ctx.stroke();
  }
}

// textos de tela (nomes, barras, números, falas)
function W2S(x, y) { return [VIEW.ox + x * TS * VIEW.S, VIEW.oy + y * TS * VIEW.S]; }
function drawOverlayText(now) {
  const fs = Math.round(11 * dpr * Math.max(0.85, zoom / 64));
  ctx.textAlign = 'center'; ctx.lineJoin = 'round';
  const label = (e, name, hp, col, h, spKey) => {
    const [sx, sy0] = W2S(e.x, e.y); const sy = sy0 - h * VIEW.S;
    ctx.font = `bold ${fs}px Verdana, sans-serif`; ctx.lineWidth = 3 * dpr; ctx.strokeStyle = 'rgba(0,0,0,.85)';
    ctx.strokeText(name, sx, sy - 9 * dpr); ctx.fillStyle = col; ctx.fillText(name, sx, sy - 9 * dpr);
    if (hp != null) {
      const bw = 34 * dpr, bh = 4 * dpr;
      ctx.fillStyle = 'rgba(0,0,0,.8)'; ctx.fillRect(sx - bw / 2 - dpr, sy - 4 * dpr - dpr, bw + 2 * dpr, bh + 2 * dpr);
      ctx.fillStyle = hp > 60 ? '#3fd34a' : hp > 30 ? '#e8c33a' : hp > 10 ? '#ff7a1a' : '#e02020'; ctx.fillRect(sx - bw / 2, sy - 4 * dpr, bw * hp / 100, bh);
    }
    const s = SPEECH.get(spKey);
    if (s) {
      if (now > s.until) SPEECH.delete(spKey);
      else {
        ctx.font = `${s.spell ? 'bold ' : ''}${fs}px Verdana, sans-serif`;
        const lines = wrap(s.text, 32);
        lines.forEach((ln, i) => { const yy = sy - (24 + (lines.length - 1 - i) * 14) * dpr; ctx.strokeText(ln, sx, yy); ctx.fillStyle = s.spell ? '#ffb23a' : s.npc ? '#7fdcff' : '#ffff8a'; ctx.fillText(ln, sx, yy); });
      }
    }
  };
  for (const n of NPCS) label(n, n.name, null, '#7fdcff', HEIGHTS.human, n.id);
  for (const m of MON.values()) label(m, MT[m.type].name, m.hp, ME.target === m.id ? '#ff8a7a' : '#e6d6c6', HEIGHTS[m.type] * (m.type === 'golem' ? 1.25 : 1), 'm' + m.id);
  for (const p of REM.values()) if (!p.dead) label(p, p.name, p.hp, '#ffffff', HEIGHTS.human, p.uid);
  if (!ME.dead) label(ME, ME.name, Math.round(100 * ME.hp / maxHp()), '#ffe066', HEIGHTS.human, ME.uid);
  for (const tx of TXT) {
    const p = (now - tx.t0) / tx.dur, [sx, sy] = W2S(tx.x, tx.y);
    ctx.globalAlpha = 1 - p * p;
    ctx.font = `bold ${Math.round((tx.big ? 20 : 14) * dpr)}px Verdana, sans-serif`;
    const yy = sy - p * 40 * dpr;
    ctx.lineWidth = 3.5 * dpr; ctx.strokeText(tx.text, sx, yy); ctx.fillStyle = tx.color; ctx.fillText(tx.text, sx, yy);
    ctx.globalAlpha = 1;
  }
  ctx.textAlign = 'start';
}
function wrap(text, n) { const out = []; let cur = ''; for (const w of text.split(' ')) { if ((cur + ' ' + w).trim().length > n) { if (cur) out.push(cur); cur = w; } else cur = (cur + ' ' + w).trim(); } if (cur) out.push(cur); return out.slice(0, 5); }

// ------------------------------------------------------------
//  Interface
// ------------------------------------------------------------
function esc(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
function logLine(text, cls) {
  const t = new Date(), stamp = `${String(t.getHours()).padStart(2, '0')}:${String(t.getMinutes()).padStart(2, '0')}`;
  const log = $('log'), d = document.createElement('div');
  d.className = 'c-' + (cls || 'sys'); d.textContent = `${stamp} ${text}`;
  log.appendChild(d); while (log.children.length > 120) log.removeChild(log.firstChild);
  log.scrollTop = log.scrollHeight;
  const f = $('feed'), e = document.createElement('div');
  e.className = 'c-' + (cls || 'sys'); e.textContent = text;
  f.appendChild(e); while (f.children.length > 5) f.removeChild(f.firstChild);
  setTimeout(() => e.classList.add('fade'), 7000); setTimeout(() => e.remove(), 8200);
}
function sysMsg(text, c) { logLine(text, c || 'sys'); }
let toastT = 0;
function toast(text) { const t = $('toast'); t.textContent = text; t.classList.add('on'); clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('on'), 1600); }
let centerT = 0;
function centerMsg(a, b) { const c = $('center'); c.innerHTML = `<div class="big">${esc(a)}</div>${b ? `<div class="small">${esc(b)}</div>` : ''}`; c.classList.add('on'); clearTimeout(centerT); centerT = setTimeout(() => c.classList.remove('on'), 3200); }
let zoneName = '';
function zoneCheck() {
  const z = isPZ(ME.x, ME.y) ? 'Cinzaforte' : grdOf(Math.floor(ME.x), Math.floor(ME.y)) === T.ASH ? 'Terras Queimadas' : Math.hypot(ME.x - CX, ME.y - CY) > 40 ? 'Ermos Fumegantes' : 'Campos de Brasa';
  if (z !== zoneName) { if (zoneName) centerMsg(z, z === 'Cinzaforte' ? 'Zona protegida' : z === 'Terras Queimadas' ? 'Perigo: criaturas de fogo' : ''); zoneName = z; }
}
function spellIcon(c, k) {
  const g = c.getContext('2d'), w = c.width, h = c.height;
  g.clearRect(0, 0, w, h);
  g.fillStyle = rg(g, w / 2, h / 2, 2, w / 2, h / 2, w * 0.7, [[0, '#3a2a20'], [1, '#120c09']]); g.fillRect(0, 0, w, h);
  g.save(); g.translate(w / 2, h / 2); g.lineCap = 'round'; g.lineJoin = 'round';
  const fire = () => { g.globalCompositeOperation = 'lighter'; g.drawImage(GLOWO, -w * 0.45, -h * 0.45, w * 0.9, h * 0.9); g.globalCompositeOperation = 'source-over'; };
  switch (k) {
    case 'ignis': case 'flecha': fire(); flame(g, 0, 10, 0.9, 1, 3); break;
    case 'sopro': fire(); for (let i = -1; i <= 1; i++) { g.save(); g.rotate(i * 0.5); flame(g, 0, 12, 0.7, 2 + i, i); g.restore(); } break;
    case 'corrente': g.globalCompositeOperation = 'lighter'; g.drawImage(GLOWB, -w * 0.45, -h * 0.45, w * 0.9, h * 0.9); g.strokeStyle = '#e8f0ff'; g.lineWidth = 2.5; g.beginPath(); g.moveTo(-6, -14); g.lineTo(3, -3); g.lineTo(-3, 0); g.lineTo(7, 14); g.stroke(); break;
    case 'meteoro': fire(); g.fillStyle = '#3a2a22'; g.beginPath(); g.arc(3, 3, 8, 0, 7); g.fill(); g.fillStyle = '#ffb04a'; g.beginPath(); g.arc(1, 5, 3.5, 0, 7); g.fill(); g.strokeStyle = 'rgba(255,170,60,.8)'; g.lineWidth = 3; g.beginPath(); g.moveTo(-3, -3); g.lineTo(-13, -13); g.stroke(); break;
    case 'nova': fire(); g.strokeStyle = '#ffe2a0'; g.lineWidth = 3; g.beginPath(); g.arc(0, 0, 11, 0, 7); g.stroke(); g.strokeStyle = 'rgba(255,120,30,.8)'; g.lineWidth = 2; g.beginPath(); g.arc(0, 0, 6, 0, 7); g.stroke(); break;
    case 'sana': g.globalCompositeOperation = 'lighter'; g.drawImage(GLOWG, -w * 0.45, -h * 0.45, w * 0.9, h * 0.9); g.globalCompositeOperation = 'source-over'; g.fillStyle = '#e6ffe8'; g.fillRect(-3, -11, 6, 22); g.fillRect(-11, -3, 22, 6); break;
    case 'golpe': g.rotate(-0.7); g.fillStyle = '#d0d8e0'; g.fillRect(-2.5, -15, 5, 22); g.fillStyle = '#c9a227'; g.fillRect(-7, 6, 14, 3); g.fillStyle = '#5a3a1e'; g.fillRect(-1.5, 9, 3, 6); break;
    case 'talho': g.strokeStyle = '#f4f4f4'; g.lineWidth = 3.5; g.beginPath(); g.arc(-6, 6, 16, -1.6, 0.1); g.stroke(); g.strokeStyle = 'rgba(255,255,255,.4)'; g.lineWidth = 7; g.stroke(); break;
    case 'furia': g.strokeStyle = '#f4f4f4'; g.lineWidth = 3; for (let i = 0; i < 3; i++) { g.beginPath(); g.arc(0, 0, 12 - i * 3, i * 2, i * 2 + 2.2); g.stroke(); } break;
    case 'leque': g.strokeStyle = '#d9c08a'; g.lineWidth = 2; for (let i = -2; i <= 2; i++) { g.save(); g.rotate(i * 0.3 - 0.8); g.beginPath(); g.moveTo(0, 12); g.lineTo(0, -12); g.stroke(); g.fillStyle = '#c8ccd0'; g.beginPath(); g.moveTo(0, -15); g.lineTo(-3, -9); g.lineTo(3, -9); g.fill(); g.restore(); } break;
    case 'chuva': g.strokeStyle = '#d9c08a'; g.lineWidth = 2; for (let i = -2; i <= 2; i++) { g.beginPath(); g.moveTo(i * 6, -13 + (i & 1) * 5); g.lineTo(i * 6, 3 + (i & 1) * 5); g.stroke(); g.fillStyle = '#c8ccd0'; g.beginPath(); g.moveTo(i * 6, 7 + (i & 1) * 5); g.lineTo(i * 6 - 3, 1 + (i & 1) * 5); g.lineTo(i * 6 + 3, 1 + (i & 1) * 5); g.fill(); } break;
  }
  g.restore();
}
function buildHotbar() {
  const bar = $('spells'); bar.innerHTML = '';
  SPELLS[ME.voc].forEach((s, i) => {
    const d = document.createElement('div'); d.className = 'slot'; d.title = `${s.nome} — ${s.mana} mana · nível ${s.lvl}`;
    const c = mk(48, 48); spellIcon(c, s.k); d.appendChild(c);
    d.insertAdjacentHTML('beforeend', `<span class="k">${i + 1}</span><span class="cd"></span><span class="lk">nv ${s.lvl}</span>`);
    d.onclick = () => castSlot(i);
    bar.appendChild(d);
  });
}
let hudT = 0;
function updHud(now) {
  if (now - hudT < 90) return; hudT = now;
  const mh = maxHp(), mm = maxMp();
  $('hpF').style.width = (100 * clamp(ME.hp / mh, 0, 1)) + '%'; $('hpT').textContent = `${Math.max(0, Math.round(ME.hp))} / ${mh}`;
  $('mpF').style.width = (100 * clamp(ME.mp / mm, 0, 1)) + '%'; $('mpT').textContent = `${Math.round(ME.mp)} / ${mm}`;
  const a = xpToReach(ME.lvl), b = xpToReach(ME.lvl + 1);
  $('xpF').style.width = (100 * (ME.xp - a) / (b - a)) + '%';
  $('lvl').textContent = ME.lvl; $('nm').textContent = ME.name;
  const inf = STORE.settings.auto;
  $('gold').textContent = ME.gold; $('php').textContent = inf ? '∞' : ME.hpPot; $('pmp').textContent = inf ? '∞' : ME.mpPot;
  const sl = $('spells').children;
  SPELLS[ME.voc].forEach((s, i) => {
    const el = sl[i]; if (!el) return;
    const cd = ME.cds[s.k] || 0;
    el.classList.toggle('locked', ME.lvl < s.lvl);
    el.classList.toggle('nomana', ME.lvl >= s.lvl && ME.mp < s.mana);
    el.querySelector('.cd').style.background = cd > 0 ? `conic-gradient(rgba(0,0,0,.72) ${100 * cd / s.cd}%, transparent 0)` : 'none';
  });
  const tg = ME.target != null ? MON.get(ME.target) : null;
  const tb = $('tgt');
  if (tg) { tb.hidden = false; $('tgtN').textContent = MT[tg.type].name; $('tgtF').style.width = tg.hp + '%'; } else tb.hidden = true;
  if (ME.task) { $('task').hidden = false; $('task').textContent = `Tarefa: ${ME.task.count}/${ME.task.need} ${MT[ME.task.type].name}`; } else $('task').hidden = true;
  updNet();
}
function updNet() { const n = NET.isHost ? SIM.players.size : REM.size + 1; $('net').innerHTML = `<i class="${NET.ready ? (NET.offline ? 'off' : 'on') : 'wait'}"></i>${NET.ready ? (NET.offline ? 'offline' : `online · ${n} jogador${n > 1 ? 'es' : ''}`) : esc(NET.status)}`; }
// minimapa
const MINIBASE = (() => {
  const c = mk(W, H), g = c.getContext('2d'), img = g.createImageData(W, H);
  const COL = { [T.GRASS]: [62, 112, 44], [T.WATER]: [36, 80, 130], [T.SAND]: [200, 182, 130], [T.TREE]: [30, 66, 24], [T.STONE]: [150, 144, 132], [T.WALL]: [70, 60, 50], [T.ROCK]: [110, 108, 104], [T.FLOWER]: [80, 130, 54], [T.PATH]: [140, 108, 70], [T.ASH]: [66, 58, 54], [T.LAVA]: [240, 100, 30], [T.DEADTREE]: [36, 30, 28], [T.BRIDGE]: [120, 84, 50] };
  for (let i = 0; i < W * H; i++) { const c2 = COL[MAP[i]]; img.data[i * 4] = c2[0]; img.data[i * 4 + 1] = c2[1]; img.data[i * 4 + 2] = c2[2]; img.data[i * 4 + 3] = 255; }
  g.putImageData(img, 0, 0); return c;
})();
let miniOn = true;
function drawMini() {
  if (!miniOn) return;
  const c = $('mini'), g = c.getContext('2d'), s = c.width, R = s / 2, sc = 2.6 * (s / 170);
  g.clearRect(0, 0, s, s);
  g.save(); g.beginPath(); g.arc(R, R, R - 2, 0, 7); g.clip();
  g.imageSmoothingEnabled = false;
  g.fillStyle = '#0b0806'; g.fillRect(0, 0, s, s);
  g.drawImage(MINIBASE, R - ME.x * sc, R - ME.y * sc, W * sc, H * sc);
  const dot = (x, y, col, r) => { g.fillStyle = col; g.beginPath(); g.arc(R + (x - ME.x) * sc, R + (y - ME.y) * sc, r, 0, 7); g.fill(); };
  for (const m of MON.values()) dot(m.x, m.y, m.type === 'arson' ? '#ff9a2a' : '#ff3b2e', m.type === 'arson' ? 4 : 2);
  for (const n of NPCS) dot(n.x, n.y, '#7fdcff', 2.5);
  for (const p of REM.values()) dot(p.x, p.y, '#ffffff', 3);
  g.save(); g.translate(R, R); g.rotate([-Math.PI / 2, 0, Math.PI / 2, Math.PI][ME.dir]);
  g.fillStyle = '#ffe066'; g.strokeStyle = '#000'; g.lineWidth = 1; g.beginPath(); g.moveTo(6, 0); g.lineTo(-4, -4); g.lineTo(-2, 0); g.lineTo(-4, 4); g.closePath(); g.fill(); g.stroke();
  g.restore();
  g.restore();
  g.strokeStyle = 'rgba(200,170,130,.55)'; g.lineWidth = 2; g.beginPath(); g.arc(R, R, R - 2, 0, 7); g.stroke();
  g.fillStyle = '#e9dccd'; g.font = 'bold 11px Verdana'; g.textAlign = 'center'; g.fillText('N', R, 13);
}

// ------------------------------------------------------------
//  Controles
// ------------------------------------------------------------
let mouse = { x: innerWidth / 2, y: innerHeight / 2 };
function mouseWorld() { return { x: (mouse.x * dpr - VIEW.ox) / (TS * VIEW.S), y: (mouse.y * dpr - VIEW.oy) / (TS * VIEW.S) }; }
addEventListener('mousemove', e => { mouse.x = e.clientX; mouse.y = e.clientY; });
cv.addEventListener('pointerdown', e => {
  if (!playing || e.button > 0) return;
  mouse.x = e.clientX; mouse.y = e.clientY;
  const w = mouseWorld();
  let best = null, bd = 9;
  for (const m of MON.values()) {
    const h = HEIGHTS[m.type] / TS * (m.type === 'golem' ? 1.25 : 1), r = Math.max(0.45, MT[m.type].r + 0.2);
    if (Math.abs(w.x - m.x) < r && w.y < m.y + 0.25 && w.y > m.y - h) { const d = Math.abs(w.x - m.x) + Math.abs(w.y - (m.y - h / 2)); if (d < bd) { bd = d; best = m; } }
  }
  if (best) { ME.target = best.id; return; }
  for (const n of NPCS) if (Math.abs(w.x - n.x) < 0.5 && w.y < n.y + 0.25 && w.y > n.y - 1.4) {
    if (Math.hypot(n.x - ME.x, n.y - ME.y) < 3.5) openDlg(n); else toast(`Aproxime-se de ${n.name} para conversar.`);
    return;
  }
});
cv.addEventListener('contextmenu', e => e.preventDefault());
cv.addEventListener('wheel', e => { e.preventDefault(); zoom = clamp(zoom * (e.deltaY > 0 ? 0.9 : 1.1), 40, 112); }, { passive: false });
function targetNext() {
  const list = [...MON.values()].map(m => ({ m, d: Math.hypot(m.tx - ME.x, m.ty - ME.y) })).filter(o => o.d < 10).sort((a, b) => a.d - b.d);
  if (!list.length) { ME.target = null; return toast('Nenhuma criatura por perto.'); }
  const i = list.findIndex(o => o.m.id === ME.target);
  ME.target = list[(i + 1) % list.length].m.id;
}
const ci = $('ci');
function openChat() { chatOpen = true; document.body.classList.add('chat'); ci.value = ''; ci.focus(); $('log').scrollTop = 1e9; keys.clear(); }
function closeChat() { chatOpen = false; document.body.classList.remove('chat'); ci.blur(); }
ci.addEventListener('keydown', e => {
  e.stopPropagation();
  if (e.key === 'Enter') {
    const v = ci.value.trim();
    if (v) {
      const t = v.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
      if (v === '/online') { sysMsg('Online: ' + [ME.name, ...[...REM.values()].map(p => `${p.name} [${p.lvl}]`)].join(', ')); }
      else {
        toHost({ t: 'chat', text: v });
        if (/^(oi|ola|hi|hello)$/.test(t)) { for (const n of NPCS) if (Math.hypot(n.x - ME.x, n.y - ME.y) < 4) { openDlg(n); break; } }
      }
    }
    closeChat(); e.preventDefault();
  } else if (e.key === 'Escape') { closeChat(); e.preventDefault(); }
});
