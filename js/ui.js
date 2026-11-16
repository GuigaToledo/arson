'use strict';
// ============================================================
//  ARSON — teclado, laços, menu do jogo, seleção de personagens
// ============================================================
addEventListener('keydown', e => {
  if (!playing) return;
  if (chatOpen) return;
  const c = e.code;
  if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Tab'].includes(c)) e.preventDefault();
  if (c === 'Escape') {
    if (!$('menu').hidden) closeMenu();
    else if (!$('help').hidden) $('help').hidden = true;
    else if (dlgNpc) closeDlg();
    else if (ME.target != null) ME.target = null;
    else openMenu('skills');
    return;
  }
  if (c === 'KeyK') { const off = document.body.classList.toggle('noskh'); STORE.settings.skh = !off; return; }
  if (!$('menu').hidden) return;
  if (c === 'Enter' || c === 'NumpadEnter') { e.preventDefault(); openChat(); return; }
  if (c === 'Space') { if (!e.repeat) targetNext(); return; }
  const m = c.match(/^(?:Numpad|Digit)([1-9])$/);
  if (m) { e.preventDefault(); castSlot(Number(m[1]) - 1); return; }
  if (c === 'KeyQ') return usePot('hp');
  if (c === 'KeyE') return usePot('mp');
  if (c === 'KeyH') { $('help').hidden = !$('help').hidden; return; }
  if (c === 'KeyM') { setMini(!miniOn); return; }
  if (c === 'NumpadAdd' || c === 'Equal') setZoom(zoom * 1.1);
  if (c === 'NumpadSubtract' || c === 'Minus') setZoom(zoom / 1.1);
  keys.add(c);
});
addEventListener('keyup', e => keys.delete(e.code));
addEventListener('blur', () => keys.clear());
document.addEventListener('visibilitychange', () => { if (document.hidden) { keys.clear(); if (ME) ME.mv = false; saveGame(); } });
function setZoom(z) { zoom = clamp(z, 40, 140); STORE.settings.zoom = Math.round(zoom); }
function setMini(on) { miniOn = on; $('mini').style.display = on ? '' : 'none'; STORE.settings.mini = on; }

// ------------------------------------------------------------
//  Laços
// ------------------------------------------------------------
let lastF = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - lastF) / 1000); lastF = now;
  pollPad();
  if (playing) updateLocal(dt);
  updateRemote(dt);
  updateFx(dt, now);
  if (playing) render(now, dt); else drawTitle(now);
  if (playing) { updHud(now); drawMini(); perfWatch(dt); }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
// tick independente da aba estar visível (worker não é estrangulado)
let lastTick = performance.now(), stT = 0;
function onTick() {
  const now = performance.now(), dt = Math.min(0.25, (now - lastTick) / 1000); lastTick = now;
  if (!playing || !ME) return;
  netWatchdog();
  if (!NET.ready) return;
  if (NET.isHost) hostTick(dt);
  stT -= dt;
  if (stT <= 0) { stT = 0.1; toHost({ t: 'st', x: Math.round(ME.x * 1000) / 1000, y: Math.round(ME.y * 1000) / 1000, dir: ME.dir, mv: ME.mv ? 1 : 0, hp: Math.round(ME.hp), mhp: maxHp(), lvl: ME.lvl, dead: ME.dead, sk: skArr() }); }
}
try { const wk = new Worker(URL.createObjectURL(new Blob(['setInterval(()=>postMessage(0),50)'], { type: 'text/javascript' }))); wk.onmessage = onTick; }
catch (e) { setInterval(onTick, 50); }

// ------------------------------------------------------------
//  Menu do jogo
// ------------------------------------------------------------
let menuTab = 'skills';
function openMenu(tab) { if (tab) menuTab = tab; $('menu').hidden = false; keys.clear(); renderMenu(); }
function closeMenu() { $('menu').hidden = true; }
function toggleMenu() { if ($('menu').hidden) openMenu(); else closeMenu(); }
function renderMenu() {
  if (!ME) return;
  const tabs = [['skills', 'Habilidades'], ['config', 'Configurações'], ['save', 'Progresso']];
  let h = `<div class="m-tabs">${tabs.map(([k, n]) => `<button data-tab="${k}" class="${k === menuTab ? 'on' : ''}">${n}</button>`).join('')}<button class="x" data-act="close">✕</button></div>`;
  if (menuTab === 'skills') {
    const a = xpToReach(ME.lvl), b = xpToReach(ME.lvl + 1);
    h += `<div class="m-char"><b>${esc(ME.name)}</b> · ${VOC[ME.voc].nome}</div>`;
    h += skRow('Nível', ME.lvl, (ME.xp - a) / (b - a), `${ME.xp - a} / ${b - a} xp`, 'Sobe matando criaturas. Aumenta vida, mana e dano.');
    const tips = { magia: 'Sobe usando magias (cura também conta).', defesa: 'Sobe apanhando de criaturas.', espada: 'Sobe acertando criaturas com a espada.', distancia: 'Sobe acertando criaturas com o arco.' };
    for (const k of SKV[ME.voc]) { const [lv, pts] = ME.sk[k], need = skNeed(k, lv); h += skRow(SKN[k], lv, pts / need, `${Math.floor(pts)} / ${need}`, tips[k]); }
    const sk = skLv();
    h += `<div class="m-note">Força: ataque básico ×${atkMult(ME.voc, sk).toFixed(2)} · magias ×${spellMult(ME.voc, sk).toFixed(2)} · dano recebido ÷${defDiv(sk).toFixed(2)}<br>Dica: os bonecos de treino fora do portão norte sobem todas as habilidades sem risco.</div>`;
  } else if (menuTab === 'config') {
    const s = STORE.settings;
    h += `<label class="m-opt"><input type="checkbox" id="optAuto" ${s.auto ? 'checked' : ''}> <span><b>Modo automático</b><small>Poções infinitas, poção de mana automática, cura em 50% de vida, poção de vida em 25% e magias de ataque assim que recarregam. Ideal para celular e controle.</small></span></label>
      <div class="m-opt"><span><b>Qualidade gráfica</b><small>Automática ajusta sozinha para o seu computador. Atual: <b>${Q.nome}</b>.<br>Detectado: ${esc(HW.gpu || 'placa de vídeo desconhecida')} · ${HW.cores} núcleos${HW.mem ? ' · ' + HW.mem + ' GB' : ''} · monitor ${HW.hz} Hz</small></span>
      <select id="optQ">${[['auto', 'Automática'], ['alta', 'Alta'], ['media', 'Média'], ['baixa', 'Baixa']].map(([v, n]) => `<option value="${v}" ${s.quality === v ? 'selected' : ''}>${n}</option>`).join('')}</select></div>
      <label class="m-opt"><input type="checkbox" id="optMini" ${miniOn ? 'checked' : ''}> <span><b>Minimapa</b></span></label>
      <div class="m-opt"><span><b>Zoom</b></span><input type="range" id="optZoom" min="40" max="140" value="${Math.round(zoom)}"></div>`;
  } else {
    h += `<p class="m-note">Seu progresso é salvo sozinho neste navegador a cada poucos segundos. Para não perder nada se o navegador limpar os dados (ou para jogar em outro aparelho), exporte e guarde o código/arquivo.</p>
      <div class="dlg-b"><button data-act="exp">Baixar arquivo de progresso</button><button data-act="copy">Copiar código</button></div>
      <div class="dlg-b"><button data-act="imp">Importar arquivo</button><button data-act="paste">Colar código</button></div>`;
  }
  h += `<div class="dlg-b m-foot"><button data-act="close">Continuar jogando</button><button data-act="select" class="ghost">Trocar de personagem</button></div>`;
  const box = $('menu'); box.innerHTML = h;
  box.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { menuTab = b.dataset.tab; renderMenu(); });
  box.querySelectorAll('[data-act]').forEach(b => b.onclick = () => menuAct(b.dataset.act));
  const oa = $('optAuto'); if (oa) oa.onchange = () => { STORE.settings.auto = oa.checked; document.body.classList.toggle('auto', oa.checked); saveGame(); toast(oa.checked ? 'Modo automático ligado' : 'Modo automático desligado'); };
  const oq = $('optQ'); if (oq) oq.onchange = () => { STORE.settings.quality = oq.value; applyQuality(oq.value === 'auto' ? autoQualityStart() : oq.value); saveGame(); renderMenu(); };
  const om = $('optMini'); if (om) om.onchange = () => setMini(om.checked);
  const oz = $('optZoom'); if (oz) oz.oninput = () => setZoom(Number(oz.value));
}
function skRow(name, lv, f, txt, tip) {
  return `<div class="sk"><div class="sk-h"><b>${name}</b><span class="sk-lv">${lv}</span></div><div class="bar sk-bar"><i style="width:${clamp(f * 100, 0, 100).toFixed(1)}%"></i><span>${txt}</span></div><small>${tip}</small></div>`;
}
function menuAct(a) {
  if (a === 'close') closeMenu();
  else if (a === 'select') backToSelect();
  else if (a === 'exp') downloadSave();
  else if (a === 'copy') copySave();
  else if (a === 'imp') pickImport();
  else if (a === 'paste') pasteImport();
}
function downloadSave() {
  const blob = new Blob([exportSave()], { type: 'text/plain' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
  a.download = `arson-progresso-${new Date().toISOString().slice(0, 10)}.txt`; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
  toast('Arquivo de progresso baixado.');
}
function copySave() {
  const s = exportSave();
  (navigator.clipboard ? navigator.clipboard.writeText(s) : Promise.reject()).then(() => toast('Código copiado. Guarde em um lugar seguro.'), () => prompt('Copie este código:', s));
}
function doImport(text) {
  try {
    const playingVoc = ME && ME.voc;
    if (playingVoc) { netStop(); playing = false; ME = null; }
    importSave(text);
    toast('Progresso importado!');
    if (playingVoc) backToSelect(); else renderSelect();
  } catch (e) { alert('Não foi possível importar: ' + e.message); }
}
function pickImport() {
  const i = document.createElement('input'); i.type = 'file'; i.accept = '.txt,.json,text/plain,application/json';
  i.onchange = () => { const f = i.files[0]; if (!f) return; const r = new FileReader(); r.onload = () => { if (confirm('Importar vai substituir o progresso deste navegador. Continuar?')) doImport(r.result); }; r.readAsText(f); };
  i.click();
}
function pasteImport() {
  const s = prompt('Cole aqui o código de progresso (começa com ARSON1:)');
  if (s && confirm('Importar vai substituir o progresso deste navegador. Continuar?')) doImport(s);
}

// ------------------------------------------------------------
//  Seleção de personagens (3 vagas: guerreiro, mago, arqueiro)
// ------------------------------------------------------------
let selVoc = null;
function renderSelect() {
  const box = $('slots');
  selVoc = selVoc || STORE.last || 'guerreiro';
  box.innerHTML = VOCS.map(v => {
    const c = STORE.chars[v], lv = levelFor(c.xp || 0);
    const sk = SKV[v].map(k => `${SKN[k]} ${c.sk[k][0]}`).join(' · ');
    return `<div class="slot-card ${v === selVoc ? 'sel' : ''}" data-v="${v}">
      <canvas width="120" height="150"></canvas>
      <div class="sc-voc">${VOC[v].nome}</div>
      <input class="sc-name" maxlength="16" placeholder="Dê um nome" value="${esc(c.name || '')}">
      <div class="sc-cols">${[['Roupa', OUTFIT, 0], ['Pele', SKINC, 1], ['Cabelo', HAIRC, 2]].map(([lb, pal, i]) => `<div class="sw-row" title="${lb}"><span>${lb}</span>${pal.map((col, j) => `<i class="sw ${(c.color && c.color[i] === j) ? 'on' : ''}" data-i="${i}" data-j="${j}" style="background:${col}"></i>`).join('')}</div>`).join('')}</div>
      <div class="sc-info">${c.name ? `Nível ${lv}<br><small>${sk}</small>` : '<small>Novo personagem</small>'}</div>
      <button class="go play">JOGAR</button>
    </div>`;
  }).join('');
  box.querySelectorAll('.slot-card').forEach(cd => {
    const v = cd.dataset.v, cvs = cd.querySelector('canvas'), g = cvs.getContext('2d');
    cd._draw = t => { g.clearRect(0, 0, cvs.width, cvs.height); g.save(); g.translate(cvs.width / 2, cvs.height - 6); g.scale(1.35, 1.35); g.drawImage(getFrame(lookFor(v, STORE.chars[v].color), 2, cd.classList.contains('sel') ? 1 + Math.floor(t / 110) % 8 : 0), -FAX, -FAY, FW, FH); g.restore(); };
    cd._draw(0);
    cd.querySelectorAll('.sw').forEach(sw => sw.onclick = ev => {
      ev.stopPropagation();
      const ch = STORE.chars[v], i = +sw.dataset.i, j = +sw.dataset.j;
      ch.color = Array.isArray(ch.color) ? ch.color.slice() : [-1, -1, -1];
      ch.color[i] = ch.color[i] === j ? -1 : j; // clicar de novo volta ao padrão
      writeStore();
      cd.querySelectorAll(`.sw[data-i="${i}"]`).forEach(x => x.classList.toggle('on', ch.color[i] === +x.dataset.j));
      selVoc = v; box.querySelectorAll('.slot-card').forEach(x => x.classList.toggle('sel', x === cd));
      cd._draw(performance.now());
    });
    cd.onclick = e => { if (e.target.tagName === 'INPUT') return; selVoc = v; box.querySelectorAll('.slot-card').forEach(x => x.classList.toggle('sel', x === cd)); };
    const inp = cd.querySelector('.sc-name');
    inp.onfocus = () => { selVoc = v; box.querySelectorAll('.slot-card').forEach(x => x.classList.toggle('sel', x === cd)); };
    inp.onchange = () => { const n = inp.value.trim().replace(/\s+/g, ' '); if (n && /^[A-Za-zÀ-ÿ ]{3,16}$/.test(n)) { STORE.chars[v].name = n; writeStore(); $('err').textContent = ''; } };
    inp.onkeydown = e => { if (e.key === 'Enter') cd.querySelector('.play').click(); };
    cd.querySelector('.play').onclick = ev => {
      ev.stopPropagation();
      const n = inp.value.trim().replace(/\s+/g, ' ');
      if (!/^[A-Za-zÀ-ÿ ]{3,16}$/.test(n)) { $('err').textContent = `Dê um nome de 3 a 16 letras para o ${VOC[v].nome}.`; inp.focus(); return; }
      STORE.chars[v].name = n;
      STORE.settings.auto = $('autoMode').checked;
      writeStore();
      startGame(v);
    };
  });
  $('autoMode').checked = !!STORE.settings.auto;
}
(function selAnim(t) { if (!playing) document.querySelectorAll('.slot-card.sel').forEach(cd => cd._draw && cd._draw(t)); requestAnimationFrame(selAnim); })(0);

// ------------------------------------------------------------
//  Inicialização
// ------------------------------------------------------------
(function init() {
  applyQuality(STORE.settings.quality === 'auto' ? autoQualityStart() : STORE.settings.quality, true);
  zoom = clamp(STORE.settings.zoom || (IS_MOBILE ? 64 : 84), 40, 140);
  if (STORE.settings.skh === false) document.body.classList.add('noskh');
  miniOn = STORE.settings.mini !== false; $('mini').style.display = miniOn ? '' : 'none';
  if (IS_MOBILE || navigator.maxTouchPoints > 0) document.body.classList.add('touch');
  setupTouch();
  $('autoMode').onchange = () => { STORE.settings.auto = $('autoMode').checked; writeStore(); };
  $('selExp').onclick = downloadSave; $('selImp').onclick = pickImport; $('selPaste').onclick = pasteImport;
  $('ver').textContent = 'v' + VERSION;
  renderSelect();
  // carrega o mundo 3D em segundo plano
  const lp = $('load3d');
  load3D(p => { lp.textContent = `Carregando gráficos 3D… ${Math.round(p * 100)}%`; }).then(ok => { lp.textContent = ok ? '' : 'Gráficos 3D indisponíveis neste aparelho: usando 2D.'; if (ok) setTimeout(() => lp.remove(), 50); });
  // voltando de uma atualização automática: entra direto com o mesmo personagem
  try {
    const r = JSON.parse(sessionStorage.getItem('arson-resume') || 'null');
    sessionStorage.removeItem('arson-resume');
    if (r && r.voc && Date.now() - r.t < 90000 && STORE.chars[r.voc] && STORE.chars[r.voc].name) {
      setTimeout(() => { startGame(r.voc); sysMsg(`Jogo atualizado para a versão ${VERSION}.`, 'lvl'); }, 50);
    }
  } catch (e) { }
  setTimeout(checkUpdate, 15000);
  setInterval(checkUpdate, 45000);
})();

// ------------------------------------------------------------
//  Atualização automática (sem F5, sem perder o login)
// ------------------------------------------------------------
let updating = false;
function checkUpdate() {
  if (updating || location.protocol === 'file:') return;
  fetch('version.json?t=' + Date.now(), { cache: 'no-store' }).then(r => r.ok ? r.json() : null).then(j => {
    if (!j || !j.v || j.v === VERSION) return;
    // proteção: se já recarregamos para essa versão e o servidor ainda entrega a antiga, espera 5 min
    let last = null; try { last = JSON.parse(sessionStorage.getItem('arson-upd') || 'null'); } catch (e) { }
    if (last && last.v === j.v && Date.now() - last.t < 300000) return;
    try { sessionStorage.setItem('arson-upd', JSON.stringify({ v: j.v, t: Date.now() })); } catch (e) { }
    applyUpdate(j.v);
  }).catch(() => { });
}
function applyUpdate(v) {
  updating = true;
  if (playing) { centerMsg('Atualizando o jogo…', `Versão ${v}. Você volta em instantes no mesmo lugar.`); saveGame(); }
  try { if (playing && ME) sessionStorage.setItem('arson-resume', JSON.stringify({ voc: ME.voc, t: Date.now() })); } catch (e) { }
  setTimeout(() => {
    const u = new URL(location.href);
    u.searchParams.set('u', v); // endereço novo = página nova, sem cache antigo
    location.replace(u.toString());
  }, playing ? 1500 : 300);
}
