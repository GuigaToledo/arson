'use strict';
// ============================================================
//  ARSON — rede (PeerJS). Um mundo único: o primeiro jogador
//  assume o ID fixo do anfitrião; os demais conectam nele.
//  Se o anfitrião sair, outro jogador assume automaticamente.
// ============================================================
const HOST_ID = 'arson-mmo-mundo-unico-v1-r8k2q';
const MAX_PLAYERS = 20;
const PEER_OPTS = { debug: 0, config: { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }, { urls: 'stun:stun1.l.google.com:19302' }, { urls: 'stun:global.stun.twilio.com:3478' }] } };
const NET = { peer: null, isHost: false, ready: false, offline: false, conns: new Map(), hostConn: null, gen: 0, status: 'conectando…' };

function netStart() {
  if (typeof Peer === 'undefined') { goOffline('PeerJS indisponível'); return; }
  tryHost();
}
function killPeer() { try { if (NET.peer) NET.peer.destroy(); } catch (e) { } NET.peer = null; NET.hostConn = null; NET.conns.clear(); }
function tryHost() {
  const gen = ++NET.gen;
  killPeer();
  NET.status = 'procurando o mundo…';
  const p = new Peer(HOST_ID, PEER_OPTS);
  NET.peer = p;
  let decided = false;
  p.on('open', () => { if (gen !== NET.gen) return; decided = true; becomeHost(); });
  p.on('connection', c => { if (gen === NET.gen) hostAccept(c); });
  p.on('disconnected', () => { if (gen === NET.gen && NET.isHost && !p.destroyed) setTimeout(() => { try { p.reconnect(); } catch (e) { } }, 1000); });
  p.on('error', e => {
    if (gen !== NET.gen) return;
    if (!decided && e.type === 'unavailable-id') { decided = true; joinClient(); }
    else if (!decided && ['network', 'server-error', 'socket-error', 'socket-closed', 'browser-incompatible', 'ssl-unavailable'].includes(e.type)) { decided = true; goOffline(e.type); }
    else console.warn('peer(host):', e.type);
  });
}
function joinClient() {
  const gen = ++NET.gen;
  killPeer();
  NET.status = 'entrando no mundo…';
  const p = new Peer(undefined, PEER_OPTS);
  NET.peer = p;
  p.on('open', () => {
    if (gen !== NET.gen) return;
    const c = p.connect(HOST_ID, { reliable: true, serialization: 'json' });
    NET.hostConn = c;
    const to = setTimeout(() => { if (gen === NET.gen && !c.open) hostLost('tempo esgotado'); }, 9000);
    c.on('open', () => {
      if (gen !== NET.gen) return;
      clearTimeout(to);
      NET.isHost = false; NET.ready = true; NET.offline = false; NET.status = 'online';
      c.send(helloMsg());
      onNetReady();
    });
    c.on('data', d => { if (gen === NET.gen) clientRecv(d); });
    c.on('close', () => { if (gen === NET.gen) hostLost('fechou'); });
    c.on('error', () => { if (gen === NET.gen) hostLost('erro'); });
  });
  p.on('error', e => {
    if (gen !== NET.gen) return;
    if (e.type === 'peer-unavailable') hostLost('anfitrião sumiu');
    else if (['network', 'server-error', 'socket-error', 'browser-incompatible'].includes(e.type)) goOffline(e.type);
    else console.warn('peer(cliente):', e.type);
  });
}
function hostLost(why) {
  const wasReady = NET.ready;
  NET.ready = false; NET.isHost = false;
  const gen = ++NET.gen;
  killPeer();
  NET.status = 'reconectando…';
  if (wasReady) { onNetLost(); sysMsg('O anfitrião do mundo saiu. Reconectando…', 'sys'); }
  setTimeout(() => { if (gen === NET.gen) tryHost(); }, 400 + Math.random() * 1800);
}
function goOffline(why) {
  console.warn('offline:', why);
  ++NET.gen;
  killPeer();
  NET.offline = true;
  becomeHost();
  NET.status = 'offline (sem conexão com o servidor de salas)';
}
function becomeHost() {
  NET.isHost = true; NET.ready = true;
  NET.status = NET.offline ? 'offline' : 'online · você hospeda o mundo';
  hostInit();
  hostRecv(ME.uid, helloMsg());
  onNetReady();
}
function hostAccept(c) {
  c.on('open', () => {
    if (NET.conns.size >= MAX_PLAYERS) { try { c.send({ t: 'sys', text: 'O mundo está cheio.', c: 'death' }); } catch (e) { } setTimeout(() => c.close(), 300); return; }
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
function netStop() {
  ++NET.gen;
  killPeer();
  NET.ready = false; NET.isHost = false; NET.offline = false; NET.status = 'desconectado';
  SIM.on = false;
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
