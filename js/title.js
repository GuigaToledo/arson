'use strict';
// ============================================================
//  ARSON — arte da tela inicial: os 3 heróis contra o dragão
// ============================================================
const TITLE = { embers: [], bg: null, bw: 0, bh: 0 };
function titleBg(w, h) {
  const c = mk(w, h), g = c.getContext('2d'), r = prng(7);
  g.fillStyle = lg(g, 0, 0, 0, h, [[0, '#0d0404'], [0.35, '#2a0a06'], [0.62, '#7a2408'], [0.72, '#c2470f'], [1, '#1a0604']]);
  g.fillRect(0, 0, w, h);
  // lua de brasa
  g.fillStyle = rg(g, w * 0.5, h * 0.2, 0, w * 0.5, h * 0.2, h * 0.16, [[0, 'rgba(255,180,90,.55)'], [1, 'rgba(255,90,20,0)']]);
  g.fillRect(0, 0, w, h * 0.5);
  // fumaça
  for (let i = 0; i < 26; i++) { const x = r() * w, y = h * (0.1 + r() * 0.4), s = h * (0.08 + r() * 0.14); g.fillStyle = `rgba(20,8,6,${0.25 + r() * 0.25})`; g.beginPath(); g.ellipse(x, y, s * 2, s * 0.6, 0, 0, 7); g.fill(); }
  // montanhas e vulcões
  const ridge = (base, amp, col, seed) => {
    const rr = prng(seed); g.fillStyle = col; g.beginPath(); g.moveTo(0, h);
    let y = base; for (let x = 0; x <= w + 20; x += 20) { y = base - amp * (0.5 + 0.5 * Math.sin(x / w * 7 + seed) * Math.cos(x / w * 3.1 + seed * 2)) - rr() * amp * 0.15; g.lineTo(x, y); }
    g.lineTo(w, h); g.closePath(); g.fill();
  };
  ridge(h * 0.62, h * 0.18, '#3a120a', 3);
  // vulcão central com lava
  g.fillStyle = '#26100a'; g.beginPath(); g.moveTo(w * 0.32, h * 0.66); g.lineTo(w * 0.46, h * 0.36); g.lineTo(w * 0.54, h * 0.36); g.lineTo(w * 0.7, h * 0.66); g.closePath(); g.fill();
  g.fillStyle = rg(g, w * 0.5, h * 0.36, 0, w * 0.5, h * 0.36, h * 0.14, [[0, 'rgba(255,200,80,.9)'], [0.4, 'rgba(255,90,20,.4)'], [1, 'rgba(255,40,0,0)']]); g.fillRect(w * 0.3, h * 0.2, w * 0.4, h * 0.3);
  g.strokeStyle = '#ff7a1a'; g.lineWidth = 3; g.shadowColor = '#ff5a00'; g.shadowBlur = 12;
  for (let i = 0; i < 4; i++) { g.beginPath(); let x = w * (0.47 + i * 0.02), y = h * 0.37; g.moveTo(x, y); for (let k = 0; k < 8; k++) { x += (r() - 0.5) * 18 + (i - 1.5) * 4; y += h * 0.035; g.lineTo(x, y); } g.stroke(); }
  g.shadowBlur = 0;
  ridge(h * 0.72, h * 0.1, '#1c0a06', 9);
  // chão rochoso em primeiro plano
  g.fillStyle = lg(g, 0, h * 0.74, 0, h, [[0, '#2a120c'], [1, '#0e0605']]);
  g.beginPath(); g.moveTo(0, h * 0.8); g.quadraticCurveTo(w * 0.3, h * 0.74, w * 0.55, h * 0.78); g.quadraticCurveTo(w * 0.8, h * 0.82, w, h * 0.76); g.lineTo(w, h); g.lineTo(0, h); g.closePath(); g.fill();
  g.strokeStyle = 'rgba(255,110,30,.75)'; g.lineWidth = 2; g.shadowColor = '#ff5a00'; g.shadowBlur = 8;
  for (let i = 0; i < 9; i++) { g.beginPath(); let x = r() * w, y = h * (0.82 + r() * 0.15); g.moveTo(x, y); for (let k = 0; k < 5; k++) { x += (r() - 0.5) * 60; y += (r() - 0.3) * 14; g.lineTo(x, y); } g.stroke(); }
  g.shadowBlur = 0;
  return c;
}

function drawDragon(g, x, y, s, t, breath) {
  g.save(); g.translate(x, y); g.scale(s, s);
  const flap = Math.sin(t * 1.6) * 0.12;
  const wing = (far) => {
    g.save(); g.translate(-10, -60); g.rotate((far ? -0.25 : 0.05) + flap * (far ? -1 : 1));
    const col = far ? '#3a0c08' : '#5a140c';
    const tips = [[-60, -260], [40, -250], [140, -200], [220, -120]];
    g.fillStyle = lg(g, 0, -260, 0, 40, [[0, far ? '#4a100a' : '#7a1c10'], [1, far ? '#200604' : '#30080a']]);
    g.beginPath(); g.moveTo(0, 0);
    tips.forEach(([tx, ty], i) => { g.lineTo(tx, ty); const nx = i < tips.length - 1 ? tips[i + 1] : [250, 10]; g.quadraticCurveTo((tx + nx[0]) / 2 - 10, (ty + nx[1]) / 2 + 50, nx[0], nx[1]); });
    g.closePath(); g.fill();
    g.strokeStyle = col; g.lineWidth = 7; g.lineCap = 'round';
    for (const [tx, ty] of tips) { g.beginPath(); g.moveTo(0, 0); g.lineTo(tx, ty); g.stroke(); }
    g.strokeStyle = 'rgba(0,0,0,.6)'; g.lineWidth = 2; g.stroke();
    g.restore();
  };
  wing(true);
  // cauda
  g.fillStyle = lg(g, 60, -20, 60, 60, [[0, '#8a2012'], [1, '#3a0c08']]);
  g.beginPath(); g.moveTo(70, -30); g.bezierCurveTo(200, -10 + Math.sin(t) * 8, 260, 90, 380, 40 + Math.sin(t * 1.3) * 12); g.lineTo(392, 34 + Math.sin(t * 1.3) * 12); g.bezierCurveTo(250, 120, 180, 60, 70, 50); g.closePath(); g.fill();
  g.fillStyle = '#2a0806'; g.beginPath(); const tx = 386, ty = 36 + Math.sin(t * 1.3) * 12; g.moveTo(tx, ty); g.lineTo(tx + 30, ty - 22); g.lineTo(tx + 14, ty + 6); g.lineTo(tx + 28, ty + 26); g.closePath(); g.fill();
  // pernas de trás
  const leg = (lx, ly, fx, fy, w2, col) => { g.strokeStyle = col; g.lineWidth = w2; g.lineCap = 'round'; g.beginPath(); g.moveTo(lx, ly); g.quadraticCurveTo(lx + 30, (ly + fy) / 2, fx, fy); g.stroke(); g.fillStyle = '#e8dcc0'; for (let k = 0; k < 3; k++) { g.beginPath(); g.moveTo(fx - 18 + k * 10, fy + 4); g.lineTo(fx - 26 + k * 10, fy + 18); g.lineTo(fx - 14 + k * 10, fy + 6); g.fill(); } };
  leg(70, 20, 90, 130, 38, '#5a140c');
  // corpo
  g.fillStyle = lg(g, 0, -80, 0, 80, [[0, '#9a2614'], [0.55, '#6a160c'], [1, '#3a0a06']]);
  g.beginPath(); g.ellipse(10, 0, 130, 72, -0.08, 0, 7); g.fill();
  g.strokeStyle = 'rgba(0,0,0,.5)'; g.lineWidth = 3; g.stroke();
  // escamas
  g.strokeStyle = 'rgba(30,4,2,.45)'; g.lineWidth = 2;
  for (let i = 0; i < 40; i++) { const a = (i * 2.4) % 6.28, rr = 30 + (i * 13) % 90; const ex = 10 + Math.cos(a) * rr, ey = Math.sin(a) * rr * 0.5 - 10; g.beginPath(); g.arc(ex, ey, 9, 0.2, Math.PI - 0.2); g.stroke(); }
  // barriga
  g.fillStyle = lg(g, 0, 20, 0, 70, [[0, '#e0a050'], [1, '#a05a20']]);
  g.beginPath(); g.ellipse(-10, 38, 100, 30, -0.1, 0, Math.PI); g.fill();
  g.strokeStyle = 'rgba(90,40,10,.6)'; for (let i = 0; i < 9; i++) { g.beginPath(); g.moveTo(-95 + i * 22, 40); g.quadraticCurveTo(-85 + i * 22, 62, -75 + i * 22, 40); g.stroke(); }
  // perna da frente
  leg(-60, 30, -70, 135, 34, '#7a1c10');
  // espinhos das costas
  g.fillStyle = '#2a0806';
  for (let i = 0; i < 7; i++) { const sx = 90 - i * 26, sy = -66 + Math.abs(i - 3) * 3; g.beginPath(); g.moveTo(sx - 10, sy + 6); g.lineTo(sx, sy - 26); g.lineTo(sx + 10, sy + 6); g.closePath(); g.fill(); }
  wing(false);
  // pescoço
  g.fillStyle = lg(g, -200, -200, -60, 0, [[0, '#a02a16'], [1, '#6a160c']]);
  g.beginPath(); g.moveTo(-70, -50); g.bezierCurveTo(-120, -90, -130, -170, -200, -175); g.lineTo(-215, -125); g.bezierCurveTo(-150, -110, -130, -40, -90, 20); g.closePath(); g.fill();
  g.fillStyle = '#d08a40'; g.beginPath(); g.moveTo(-95, 10); g.bezierCurveTo(-130, -40, -150, -100, -210, -128); g.lineTo(-206, -118); g.bezierCurveTo(-145, -90, -125, -35, -88, 18); g.closePath(); g.fill();
  g.fillStyle = '#2a0806'; for (let i = 0; i < 5; i++) { const px = -110 - i * 20, py = -95 - i * 18; g.beginPath(); g.moveTo(px, py); g.lineTo(px + 8, py - 22); g.lineTo(px + 16, py + 2); g.closePath(); g.fill(); }
  // cabeça
  const jaw = breath ? 0.25 + Math.sin(t * 9) * 0.04 : 0.08;
  g.save(); g.translate(-215, -150);
  g.fillStyle = '#5a140c'; g.save(); g.rotate(jaw); g.beginPath(); g.moveTo(10, 12); g.lineTo(-95, 22); g.lineTo(-88, 34); g.lineTo(15, 30); g.closePath(); g.fill();
  g.fillStyle = '#f2ead6'; for (let k = 0; k < 6; k++) { g.beginPath(); g.moveTo(-85 + k * 14, 22); g.lineTo(-80 + k * 14, 12); g.lineTo(-75 + k * 14, 22); g.fill(); }
  g.restore();
  g.fillStyle = lg(g, -100, -40, 30, 20, [[0, '#b83018'], [1, '#6a160c']]);
  g.beginPath(); g.moveTo(30, -20); g.quadraticCurveTo(0, -42, -40, -30); g.lineTo(-100, -6); g.quadraticCurveTo(-106, 8, -96, 14); g.lineTo(20, 18); g.quadraticCurveTo(40, 0, 30, -20); g.closePath(); g.fill();
  g.strokeStyle = 'rgba(0,0,0,.5)'; g.lineWidth = 2.5; g.stroke();
  g.fillStyle = '#f2ead6'; for (let k = 0; k < 6; k++) { g.beginPath(); g.moveTo(-90 + k * 14, 13); g.lineTo(-85 + k * 14, 24); g.lineTo(-80 + k * 14, 13); g.fill(); }
  // chifres
  g.fillStyle = lg(g, 0, -80, 0, -20, [[0, '#f2ead6'], [1, '#8a7a60']]);
  g.beginPath(); g.moveTo(0, -30); g.quadraticCurveTo(30, -70, 70, -78); g.quadraticCurveTo(40, -55, 18, -18); g.closePath(); g.fill();
  g.beginPath(); g.moveTo(-15, -32); g.quadraticCurveTo(0, -80, 30, -100); g.quadraticCurveTo(14, -70, 5, -26); g.closePath(); g.fill();
  // olho
  g.fillStyle = rg(g, -38, -18, 0, -38, -18, 16, [[0, 'rgba(255,240,150,1)'], [0.4, 'rgba(255,170,40,.9)'], [1, 'rgba(255,90,0,0)']]); g.beginPath(); g.arc(-38, -18, 16, 0, 7); g.fill();
  g.fillStyle = '#1a0402'; g.beginPath(); g.ellipse(-38, -18, 2, 6, 0, 0, 7); g.fill();
  g.fillStyle = '#1a0402'; g.beginPath(); g.arc(-96, -2, 3, 0, 7); g.fill();
  g.restore();
  g.restore();
  return { mx: x + (-215 - 98) * s, my: y + (-150 + 16) * s };
}

function drawTitle(now) {
  const w = cv.width, h = cv.height, t = now / 1000;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  if (!TITLE.bg || TITLE.bw !== w || TITLE.bh !== h) { TITLE.bg = titleBg(w, h); TITLE.bw = w; TITLE.bh = h; }
  ctx.drawImage(TITLE.bg, 0, 0);
  const wide = w / dpr >= 1100; // cartão centralizado: heróis à esquerda, dragão à direita
  const s = Math.min(w / 1600, h / 900) * (wide ? 0.92 : 1);
  const narrow = !wide && w / h < 1.2;
  // dragão
  const dx = wide ? w * 0.87 : w * (narrow ? 0.72 : 0.8), dy = h * (wide ? 0.5 : 0.5);
  const breath = (t % 6) < 3.4;
  const m = drawDragon(ctx, dx, dy, s * 1.15, t, breath);
  // heróis (esquerda), virados para o dragão
  const hs = 2.6 * s * 1.15, hy = h * 0.86;
  const hx = wide ? [0.04, 0.1, 0.165] : narrow ? [0.08, 0.16, 0.26] : [0.1, 0.17, 0.25];
  const heroes = [['arqueiro', w * hx[0], hy - 10 * s, 9 + Math.floor(t * 3) % 3], ['mago', w * hx[1], hy - 4 * s, 9 + Math.floor(t * 4) % 3], ['guerreiro', w * hx[2], hy + 6 * s, 1 + Math.floor(t * 9) % 8]];
  for (const [v, x, y, fi] of heroes) {
    ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.ellipse(x, y, 22 * hs, 6 * hs, 0, 0, 7); ctx.fill();
    ctx.save(); ctx.translate(x, y); ctx.scale(hs, hs); ctx.drawImage(getFrame(v, 1, fi), -FAX, -FAY); ctx.restore();
  }
  const gx = heroes[2][1] + 14 * hs, gy = heroes[2][2] - 40 * hs; // escudo do guerreiro
  // magia do mago: orbe brilhando
  const mgx = heroes[1][1] + 6 * hs, mgy = heroes[1][2] - 82 * hs;
  ctx.globalCompositeOperation = 'lighter';
  ctx.globalAlpha = 0.6 + Math.sin(t * 6) * 0.2; ctx.drawImage(GLOWO, mgx - 60 * s, mgy - 60 * s, 120 * s, 120 * s); ctx.globalAlpha = 1;
  // sopro de fogo do dragão em direção ao guerreiro
  if (breath) {
    const k = Math.min(1, (t % 6) / 0.6);
    const ex = lerp(m.mx, gx + 40 * s, k), ey = lerp(m.my, gy, k);
    const ang = Math.atan2(ey - m.my, ex - m.mx), len = Math.hypot(ex - m.mx, ey - m.my);
    ctx.save(); ctx.translate(m.mx, m.my); ctx.rotate(ang);
    for (let i = 0; i < 3; i++) {
      const wdt = [70, 46, 22][i] * s, col = ['rgba(200,40,10,.5)', 'rgba(255,130,30,.6)', 'rgba(255,230,150,.8)'][i];
      ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(0, -6 * s);
      ctx.quadraticCurveTo(len * 0.5, -wdt + Math.sin(t * 13 + i) * 6 * s, len, -wdt * 1.1);
      ctx.quadraticCurveTo(len + wdt * 0.8, 0, len, wdt * 1.1);
      ctx.quadraticCurveTo(len * 0.5, wdt + Math.cos(t * 11 + i) * 6 * s, 0, 6 * s); ctx.closePath(); ctx.fill();
    }
    ctx.restore();
    ctx.drawImage(GLOWO, ex - 160 * s, ey - 160 * s, 320 * s, 320 * s);
    for (let i = 0; i < 6; i++) TITLE.embers.push({ x: ex + (Math.random() - 0.5) * 40 * s, y: ey + (Math.random() - 0.5) * 40 * s, vx: (Math.random() - 0.3) * 260 * s, vy: (Math.random() - 0.8) * 260 * s, life: 0.8, c: FIRE[Math.floor(Math.random() * 3)] });
  }
  // flecha voando em direção ao dragão
  const fp = (t * 0.9) % 1, ax0 = heroes[0][1] + 30 * hs, ay0 = heroes[0][2] - 40 * hs, ax1 = dx - 120 * s, ay1 = dy - 120 * s;
  ctx.globalCompositeOperation = 'source-over';
  ctx.save(); ctx.translate(lerp(ax0, ax1, fp), lerp(ay0, ay1, fp) - Math.sin(fp * Math.PI) * 80 * s); ctx.rotate(Math.atan2(ay1 - ay0, ax1 - ax0) - Math.cos(fp * Math.PI) * 0.35);
  ctx.strokeStyle = '#d9c08a'; ctx.lineWidth = 3 * s; ctx.beginPath(); ctx.moveTo(-26 * s, 0); ctx.lineTo(18 * s, 0); ctx.stroke();
  ctx.fillStyle = '#c8ccd0'; ctx.beginPath(); ctx.moveTo(26 * s, 0); ctx.lineTo(14 * s, -6 * s); ctx.lineTo(14 * s, 6 * s); ctx.fill(); ctx.restore();
  // brasas no ar
  ctx.globalCompositeOperation = 'lighter';
  if (Math.random() < 0.9) TITLE.embers.push({ x: Math.random() * w, y: h + 5, vx: (Math.random() - 0.5) * 30, vy: -60 - Math.random() * 90, life: 5, c: FIRE[Math.floor(Math.random() * 3)] });
  for (let i = TITLE.embers.length - 1; i >= 0; i--) {
    const e = TITLE.embers[i]; e.life -= 1 / 60; e.x += e.vx / 60; e.y += e.vy / 60;
    if (e.life <= 0 || e.y < -10) { TITLE.embers.splice(i, 1); continue; }
    ctx.fillStyle = `rgba(${e.c[0]},${e.c[1]},${e.c[2]},${Math.min(1, e.life)})`; ctx.fillRect(e.x, e.y, 2.5 * Math.max(1, s * 1.5), 2.5 * Math.max(1, s * 1.5));
  }
  if (TITLE.embers.length > 600) TITLE.embers.splice(0, TITLE.embers.length - 600);
  ctx.globalCompositeOperation = 'source-over';
  ctx.drawImage(vignette, 0, 0);
}
