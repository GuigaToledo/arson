'use strict';
// ============================================================
//  ARSON — tela inicial em 3D: os 3 heróis contra Arson no vulcão,
//  e os cartões de personagem com os modelos 3D animados.
// ============================================================
let T3 = null;
function titleSpot() {
  // procura um chão de cinzas aberto perto do vulcão para a batalha
  let best = null, bd = 1e9;
  for (let y = VY + 4; y < VY + 20; y++) for (let x = VX - 14; x < VX + 6; x++) {
    let ok = true;
    for (let dy = -3; dy <= 3 && ok; dy++) for (let dx = -3; dx <= 3 && ok; dx++) { const t = tileAt(x + dx, y + dy); if (BLOCK.has(t) || t === T.LAVA) ok = false; }
    if (!ok) continue;
    const d = Math.hypot(x - (VX - 5), y - (VY + 9));
    if (d < bd) { bd = d; best = { x: x + 0.5, y: y + 0.5 }; }
  }
  return best || { x: VX - 4.5, y: VY + 9.5 };
}
function setupTitle3D() {
  const c = titleSpot();
  const put = (type, x, y) => { const a = makeActor(type); a.px = x; a.pz = y; a.root.position.set(x, 0, y); a.timer = Math.random(); return a; };
  T3 = {
    c, t: 0,
    boss: put('arson', c.x + 0.4, c.y - 2.4),
    heroes: { guerreiro: put('guerreiro', c.x - 0.5, c.y + 0.9), mago: put('mago', c.x - 1.9, c.y + 2.1), arqueiro: put('arqueiro', c.x + 1.4, c.y + 2.3) },
  };
}
function hideTitle3D() {
  if (!T3) return;
  disposeActor(T3.boss); for (const a of Object.values(T3.heroes)) disposeActor(a);
  T3 = null;
}
function renderTitle3D(now, dt) {
  if (!T3) setupTitle3D();
  const t = now / 1000, B = T3.boss, H = T3.heroes;
  T3.t += dt;
  R3.groundU.uTime.value = t % 1000;
  const face = (a, tx, tz) => { a.root.rotation.y = Math.atan2(tx - a.root.position.x, tz - a.root.position.z); };
  for (const a of Object.values(H)) face(a, B.root.position.x, B.root.position.z);
  face(B, H.guerreiro.root.position.x, H.guerreiro.root.position.z);
  const P = a => ({ x: a.root.position.x, y: a.root.position.z });
  // ciclo da luta
  const act = (a, every, fn) => { a.timer -= dt; a.lock -= dt; if (a.timer <= 0) { a.timer = every * (0.85 + Math.random() * 0.3); fn(); } else if (a.lock <= 0) play(a, 'Idle_A'); };
  act(H.guerreiro, 1.3, () => { play(H.guerreiro, MODEL_DEF.guerreiro.atk, true, 0.55); const g = P(H.guerreiro), b = P(B); setTimeout(() => fx3Event({ k: 'slash', x: b.x, y: b.y - 0.2, a: Math.atan2(b.y - g.y, b.x - g.x) }), 250); });
  act(H.mago, 2.4, () => { play(H.mago, MODEL_DEF.mago.cast, true, 0.7); const m = P(H.mago), b = P(B); setTimeout(() => fx3Event({ k: 'proj', f: 'fogo', x: m.x, y: m.y - 0.3, x1: b.x, y1: b.y - 0.4, big: 1 }), 350); });
  act(H.arqueiro, 1.7, () => { play(H.arqueiro, MODEL_DEF.arqueiro.atk, true, 0.6); const r = P(H.arqueiro), b = P(B); setTimeout(() => fx3Event({ k: 'proj', f: 'flecha', x: r.x, y: r.y - 0.3, x1: b.x, y1: b.y - 0.4 }), 300); });
  act(B, 4.2, () => {
    play(B, MODEL_DEF.arson.atk, true, 1.1);
    const b = P(B), g = P(H.guerreiro);
    setTimeout(() => { fx3Event({ k: 'cone', f: 'fogo', x: b.x, y: b.y, a: Math.atan2(g.y - b.y, g.x - b.x), r: 3.6, w: 0.32 }); setTimeout(() => play(H.guerreiro, 'Hit_A', true, 0.4), 250); }, 500);
  });
  for (const a of [B, ...Object.values(H)]) a.mixer.update(dt);
  if (Math.random() < 0.7) { const p = B.root.position; burst3(p.x + (Math.random() - 0.5) * 1.2, 0.4 + Math.random() * 2.2, p.z + (Math.random() - 0.5) * 1.2, 1, FIRE3, 0.5, 1, { up: 1.5, s: 0.32 }); }
  stepFx3(dt, t);
  stepParticles(P3add, dt); stepParticles(P3norm, dt);
  // câmera de cinema girando devagar em volta da luta
  const cx = T3.c.x, cz = T3.c.y, ang = 0.35 + Math.sin(T3.t * 0.06) * 0.55, rad = 7.5;
  camT.x = cx; camT.z = cz;
  camera.position.set(cx + Math.sin(ang) * rad, 3.6, cz + Math.cos(ang) * rad);
  camera.lookAt(cx, 1.0, cz - 0.6);
  sun.position.set(cx - 7, 14, cz + 5); sun.target.position.set(cx, 0, cz);
  sun.intensity = 1.1; sun.color.setRGB(1, 0.7, 0.45); hemi.intensity = 0.5;
  SKY.copy(SKY_VOLC).lerp(SKY_DAY, 0.15); scene.background.copy(SKY); scene.fog.color.copy(SKY);
  sun.castShadow = Q.shadows;
  for (const c of CHUNKS) c.m.visible = Math.abs(c.cx - cx) < 30 && Math.abs(c.cz - cz) < 26;
  renderFrame(true);
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, cv.width, cv.height);
  if (!POST.on) ctx.drawImage(vignette, 0, 0);
}

// ------------------------------------------------------------
//  Cartões: modelo 3D animado de cada personagem
// ------------------------------------------------------------
let PV = null;
function previewInit() {
  const c = mk(240, 300);
  let r;
  try { r = new THREE.WebGLRenderer({ canvas: c, alpha: true, antialias: true }); } catch (e) { return null; }
  r.outputEncoding = THREE.sRGBEncoding; r.toneMapping = THREE.ACESFilmicToneMapping; r.setPixelRatio(1); r.setSize(240, 300, false);
  const sc = new THREE.Scene();
  sc.add(new THREE.HemisphereLight(0xfff0e0, 0x3a2a20, 1.1));
  const d = new THREE.DirectionalLight(0xffe0c0, 1.8); d.position.set(-2, 4, 3); sc.add(d);
  const rim = new THREE.DirectionalLight(0xff8a3a, 1.2); rim.position.set(2, 2, -3); sc.add(rim);
  const cam = new THREE.PerspectiveCamera(30, 240 / 300, 0.1, 20);
  PV = { r, c, sc, cam, actors: {} };
  return PV;
}
function previewActor(voc, col) {
  const ck = col ? col.join(',') : '';
  let a = PV.actors[voc];
  if (a && a.ck !== ck) { PV.sc.remove(a.root); a = null; }
  if (!a) {
    a = makeActor(voc, col, PV.sc); a.ck = ck;
    const k = 1.55 / (R3.hgt[voc] || 1.2); a.root.scale.setScalar(k);
    a.root.traverse(o => { if (o.isMesh) o.castShadow = false; });
    PV.actors[voc] = a;
  }
  return a;
}
// desenha o modelo 3D no canvas 2D do cartão
function drawPreview3D(cvs, voc, col, selected, dt) {
  if (!R3.ready || (!PV && !previewInit())) return false;
  const a = previewActor(voc, col);
  for (const o of Object.values(PV.actors)) o.root.visible = o === a;
  a.lock -= dt; a.timer = (a.timer || 0) - dt;
  if (selected) {
    if (a.timer <= 0) { a.timer = 2.6; play(a, MODEL_DEF[voc].atk, true, 0.8); }
    else if (a.lock <= 0) play(a, 'Idle_B') || play(a, 'Idle_A');
  } else if (a.lock <= 0) play(a, 'Idle_A');
  a.root.rotation.y = selected ? Math.sin(performance.now() / 1400) * 0.5 : 0.25;
  a.mixer.update(dt);
  PV.cam.position.set(0, 1.05, 3.6); PV.cam.lookAt(0, 0.78, 0);
  PV.r.render(PV.sc, PV.cam);
  const g = cvs.getContext('2d');
  g.clearRect(0, 0, cvs.width, cvs.height);
  g.drawImage(PV.c, 0, 0, cvs.width, cvs.height);
  return true;
}
