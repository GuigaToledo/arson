'use strict';
// ============================================================
//  ARSON — rede (PeerJS). Um mundo único: o primeiro jogador
//  assume o ID fixo do anfitrião; os demais conectam nele.
//  Se o anfitrião sair, outro jogador assume automaticamente.
//
//  Nunca desiste: tenta de novo até conseguir, e se diagnostica:
//   - PeerJS não carregou      -> carrega de outro CDN
//   - servidor de salas fora   -> tenta de novo com espera crescente
//   - conexão direta bloqueada -> sobe o nível: STUN -> +TURN -> só TURN
//   - anfitrião fantasma       -> espera a sala liberar e assume
// ============================================================
// ?sala=nome cria um mundo separado (útil para testes); sem isso, todos caem no mundo principal
const SALA = (new URLSearchParams(location.search).get('sala') || '').replace(/[^a-z0-9-]/gi, '').slice(0, 24);
const HOST_ID = 'arson-mmo-mundo-unico-v1-r8k2q' + (SALA ? '-' + SALA : '');
const MAX_PLAYERS = 20;
const STUN = [{ urls: 'stun:stun.l.google.com:19302' }, { urls: 'stun:stun1.l.google.com:19302' }, { urls: 'stun:global.stun.twilio.com:3478' }];
const TURN = [
  { urls: 'turn:openrelay.metered.ca:80', username: 'openrelayproject', credential: 'openrelayproject' },
  { urls: 'turn:openrelay.metered.ca:443', username: 'openrelayproject', credential: 'openrelayproject' },
  { urls: 'turn:openrelay.metered.ca:443?transport=tcp', username: 'openrelayproject', credential: 'openrelayproject' },
];
const ICE_LEVELS = [
  { nome: 'conexão direta', cfg: { iceServers: STUN } },
  { nome: 'direta + retransmissão', cfg: { iceServers: STUN.concat(TURN) } },
  { nome: 'só retransmissão', cfg: { iceServers: TURN, iceTransportPolicy: 'relay' } },
];
const PEER_CDNS = ['https://cdn.jsdelivr.net/npm/peerjs@1.5.4/dist/peerjs.min.js', 'https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js'];
const NET = {
  peer: null, isHost: false, ready: false, conns: new Map(), hostConn: null, gen: 0, status: 'conectando…',
  attempt: 0, fails: 0, backoff: 0, level: 0, log: [], cdn: 0, timer: 0, running: false,
};
try { NET.level = clamp(Number(localStorage.getItem('arson-net-level')) || 0, 0, ICE_LEVELS.length - 1); } catch (e) { }
const peerOpts = () => ({ debug: 0, config: ICE_LEVELS[NET.level].cfg });
// o anfitrião sempre oferece retransmissão, para aceitar quem está atrás de rede restrita
const hostOpts = () => ({ debug: 0, config: ICE_LEVELS[Math.max(1, NET.level)].cfg });

function diag(msg, cls) {
  const t = new Date().toTimeString().slice(0, 8);
  NET.log.push(`${t} ${msg}`); if (NET.log.length > 40) NET.log.shift();
  NET.status = msg;
  if (cls) sysMsg(msg, cls);
  if (typeof updConn === 'function') updConn();
}
function netStart() {
  NET.running = true; NET.fails = 0; NET.backoff = 0; NET.attempt = 0;
  if (window.ARSON_SEM_REDE) { becomeHost(); return; } // só para testes automáticos
  connectLoop();
}
function connectLoop() {
  if (!NET.running) return;
  if (typeof Peer === 'undefined') { loadPeerLib(); return; }
  tryHost();
}
function loadPeerLib() {
  if (NET.cdn >= PEER_CDNS.length) NET.cdn = 0;
  const url = PEER_CDNS[NET.cdn++];
  diag(`Biblioteca de rede não carregou; tentando outra fonte (${new URL(url).host})…`);
  const s = document.createElement('script'); s.src = url;
  s.onload = () => connectLoop();
  s.onerror = () => retryLater('Não foi possível baixar a biblioteca de rede.');
  document.head.appendChild(s);
}
function retryLater(why) {
  if (!NET.running) return;
  NET.backoff = Math.min(15, NET.backoff ? NET.backoff * 2 : 2);
  const gen = ++NET.gen;
  killPeer();
  diag(`${why} Nova tentativa em ${NET.backoff}s…`);
  clearTimeout(NET.timer);
  NET.timer = setTimeout(() => { if (gen === NET.gen) connectLoop(); }, NET.backoff * 1000 + Math.random() * 800);
}
function escalate(why) {
  NET.fails++;
  if (NET.fails >= 2 && NET.level < ICE_LEVELS.length - 1) { NET.level++; NET.fails = 0; diag(`${why} Ajustando a rede: ${ICE_LEVELS[NET.level].nome}.`); }
  else if (NET.fails >= 3 && NET.level === ICE_LEVELS.length - 1) { NET.level = 0; NET.fails = 0; diag(`${why} Recomeçando pelo modo de conexão direta.`); }
}
function killPeer() { try { if (NET.peer) NET.peer.destroy(); } catch (e) { } NET.peer = null; NET.hostConn = null; NET.conns.clear(); }
function tryHost() {
  const gen = ++NET.gen;
  killPeer();
  NET.attempt++;
  diag(`Procurando o mundo… (tentativa ${NET.attempt})`);
  let p;
  try { p = new Peer(HOST_ID, hostOpts()); } catch (e) { retryLater('Erro ao iniciar a rede.'); return; }
  NET.peer = p;
  let decided = false;
  const to = setTimeout(() => { if (gen === NET.gen && !decided) { decided = true; retryLater('O servidor de salas não respondeu.'); } }, 12000);
  p.on('open', () => { if (gen !== NET.gen) return; decided = true; clearTimeout(to); becomeHost(); });
  p.on('connection', c => { if (gen === NET.gen) hostAccept(c); });
  p.on('disconnected', () => { if (gen === NET.gen && NET.isHost && !p.destroyed) setTimeout(() => { try { p.reconnect(); } catch (e) { } }, 1500); });
  p.on('error', e => {
    if (gen !== NET.gen) return;
    if (!decided && e.type === 'unavailable-id') { decided = true; clearTimeout(to); joinClient(); }
    else if (!decided) { decided = true; clearTimeout(to); retryLater(`Falha no servidor de salas (${e.type}).`); }
    else console.warn('peer(host):', e.type);
  });
}
function joinClient() {
  const gen = ++NET.gen;
  killPeer();
  diag(`Mundo encontrado. Entrando (${ICE_LEVELS[NET.level].nome})…`);
  let p;
  try { p = new Peer(undefined, peerOpts()); } catch (e) { retryLater('Erro ao iniciar a rede.'); return; }
  NET.peer = p;
  p.on('open', () => {
    if (gen !== NET.gen) return;
    const c = p.connect(HOST_ID, { reliable: true, serialization: 'json' });
    NET.hostConn = c;
    const to = setTimeout(() => {
      if (gen !== NET.gen || c.open) return;
      escalate('Não consegui falar com o anfitrião (a rede pode estar bloqueando).');
      retryLater('Conexão com o anfitrião demorou demais.');
    }, 10000);
    c.on('open', () => {
      if (gen !== NET.gen) return;
      clearTimeout(to);
      NET.isHost = false; NET.ready = true; NET.fails = 0; NET.backoff = 0; NET.lastRx = performance.now();
      try { localStorage.setItem('arson-net-level', String(NET.level)); } catch (e) { }
      diag('Conectado ao mundo de Arson.');
      c.send(helloMsg());
      onNetReady();
    });
    c.on('data', d => { if (gen === NET.gen) { NET.lastRx = performance.now(); clientRecv(d); } });
    c.on('close', () => { if (gen === NET.gen) hostLost(); });
    c.on('error', () => { if (gen === NET.gen) hostLost(); });
  });
  p.on('error', e => {
    if (gen !== NET.gen) return;
    if (e.type === 'peer-unavailable') retryLaterFast('O anfitrião saiu; a sala ainda está sendo liberada.');
    else retryLater(`Falha na conexão (${e.type}).`);
  });
}
function retryLaterFast(why) {
  const gen = ++NET.gen;
  killPeer();
  diag(why + ' Tentando assumir o mundo…');
  clearTimeout(NET.timer);
  NET.timer = setTimeout(() => { if (gen === NET.gen) connectLoop(); }, 1200 + Math.random() * 1500);
}
function hostLost() {
  const wasReady = NET.ready;
  NET.ready = false; NET.isHost = false;
  if (wasReady) { onNetLost(); sysMsg('O anfitrião do mundo saiu. Reconectando…', 'sys'); }
  retryLaterFast('Conexão com o anfitrião perdida.');
}
function becomeHost() {
  NET.isHost = true; NET.ready = true; NET.fails = 0; NET.backoff = 0;
  diag('Conectado ao mundo de Arson (você está hospedando).');
  hostInit();
  hostRecv(ME.uid, helloMsg());
  onNetReady();
}
function netStop() {
  NET.running = false;
  ++NET.gen;
  clearTimeout(NET.timer);
  killPeer();
  NET.ready = false; NET.isHost = false; NET.status = 'desconectado';
  SIM.on = false;
}
function hostAccept(c) {
  c.on('open', () => {
    if (NET.conns.size >= MAX_PLAYERS) { try { c.send({ t: 'sys', text: 'O mundo está cheio. Tente de novo em instantes.', c: 'death' }); } catch (e) { } setTimeout(() => c.close(), 300); return; }
    NET.conns.set(c.peer, { c, uid: null });
  });
  c.on('data', d => {
    const e = NET.conns.get(c.peer); if (!e || !d || typeof d !== 'object') return;
    if (d.t === 'hi') e.uid = String(d.uid || '').slice(0, 24);
    if (e.uid) { try { hostRecv(e.uid, d); } catch (err) { console.error(err); } }
  });
  const gone = () => { const e = NET.conns.get(c.peer); if (e && e.uid) hostPlayerLeft(e.uid); NET.conns.delete(c.peer); };
  c.on('close', gone);
  c.on('error', gone);
}
// anfitrião sem sinal por 5s (aba travada / fechada à força) = conexão perdida
function netWatchdog() {
  if (NET.running && NET.ready && !NET.isHost && performance.now() - (NET.lastRx || 0) > 5000) {
    diag('O anfitrião parou de responder.');
    hostLost();
  }
}
// --- envio
function toHost(msg) {
  if (!NET.ready) return;
  if (NET.isHost) hostRecv(ME.uid, msg);
  else if (NET.hostConn && NET.hostConn.open) NET.hostConn.send(msg);
}
function sendTo(uid, msg) {
  if (uid === ME.uid) { clientRecv(msg); return; }
  for (const e of NET.conns.values()) if (e.uid === uid && e.c.open) { e.c.send(msg); return; }
}
function broadcast(msg) {
  clientRecv(msg);
  for (const e of NET.conns.values()) if (e.uid && e.c.open) e.c.send(msg);
}
