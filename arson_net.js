'use strict';
// ============================================================
//  ARSON (Godot) — rede pelo navegador com PeerJS.
//  Mesma ideia do Arson antigo: o primeiro jogador assume o ID fixo
//  do anfitrião; os outros se conectam nele. Se o anfitrião sair,
//  outro jogador assume sozinho.
//
//  O Godot só chama:
//    ArsonNet.start(nome)        -> começa a conectar
//    ArsonNet.setMe(json)        -> estado do meu personagem (~10x/s)
//    ArsonNet.poll()             -> JSON {status, host, ready, me, players}
//    ArsonNet.say(texto)         -> mensagem de chat
// ============================================================
(function () {
  // ---- atualização automática: a página sabe a própria versão (arson_net.js?v=xxxx) e
  // confere version.json a cada minuto. O Godot vê updateReady() e recarrega salvando tudo.
  const BUILD = (() => { try { return new URL(document.currentScript.src).searchParams.get('v') || ''; } catch (e) { return ''; } })();
  let NEW_BUILD = '';
  function checkVersion() {
    if (!BUILD) return;
    fetch('version.json?t=' + Date.now(), { cache: 'no-store' }).then(r => r.ok ? r.json() : null).then(j => {
      if (j && j.v && j.v !== BUILD) NEW_BUILD = j.v;
    }).catch(() => { });
  }
  setInterval(checkVersion, 60000);
  setTimeout(checkVersion, 15000);
  const SALA = (new URLSearchParams(location.search).get('sala') || '').replace(/[^a-z0-9-]/gi, '').slice(0, 24);
  const HOST_ID = 'arson-godot-taverna-v1-q9w4z' + (SALA ? '-' + SALA : '');
  const MAX_PLAYERS = 20;
  const STUN = [{ urls: 'stun:stun.l.google.com:19302' }, { urls: 'stun:stun1.l.google.com:19302' }, { urls: 'stun:global.stun.twilio.com:3478' }];
  const TURN = [
    { urls: 'turn:openrelay.metered.ca:80', username: 'openrelayproject', credential: 'openrelayproject' },
    { urls: 'turn:openrelay.metered.ca:443', username: 'openrelayproject', credential: 'openrelayproject' },
    { urls: 'turn:openrelay.metered.ca:443?transport=tcp', username: 'openrelayproject', credential: 'openrelayproject' },
  ];
  const ICE = [
    { nome: 'conexão direta', cfg: { iceServers: STUN } },
    { nome: 'direta + retransmissão', cfg: { iceServers: STUN.concat(TURN) } },
    { nome: 'só retransmissão', cfg: { iceServers: TURN, iceTransportPolicy: 'relay' } },
  ];
  const CDNS = ['https://cdn.jsdelivr.net/npm/peerjs@1.5.4/dist/peerjs.min.js', 'https://unpkg.com/peerjs@1.5.4/dist/peerjs.min.js', 'https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js'];

  const uid = Math.random().toString(36).slice(2, 10);
  const S = {
    peer: null, isHost: false, ready: false, running: false, gen: 0, timer: 0,
    conns: new Map(), hostConn: null, lastRx: 0, fails: 0, backoff: 0, level: 0, attempt: 0, cdn: 0,
    status: 'desconectado', me: null, name: 'Viajante', players: {}, chat: [], lastSend: 0,
    world: null, worldIn: null, events: [], inbox: [],
  };
  try { S.level = Math.min(ICE.length - 1, Math.max(0, Number(localStorage.getItem('arson-g-net-level')) || 0)); } catch (e) { }

  const diag = m => { S.status = m; console.log('[arson-net]', m); };
  const now = () => performance.now();

  function loadLib() {
    if (S.cdn >= CDNS.length) S.cdn = 0;
    const url = CDNS[S.cdn++];
    diag('Baixando biblioteca de rede…');
    const s = document.createElement('script');
    s.src = url;
    s.onload = () => loop();
    s.onerror = () => retry('Não consegui baixar a biblioteca de rede.');
    document.head.appendChild(s);
  }
  function loop() {
    if (!S.running) return;
    if (typeof Peer === 'undefined') { loadLib(); return; }
    tryHost();
  }
  function kill() { try { if (S.peer) S.peer.destroy(); } catch (e) { } S.peer = null; S.hostConn = null; S.conns.clear(); }
  function retry(why, fast) {
    if (!S.running) return;
    S.ready = false; S.isHost = false;
    const gen = ++S.gen;
    kill();
    S.backoff = fast ? 1.2 : Math.min(15, S.backoff ? S.backoff * 2 : 2);
    diag(why + ' Tentando de novo…');
    clearTimeout(S.timer);
    S.timer = setTimeout(() => { if (gen === S.gen) loop(); }, S.backoff * 1000 + Math.random() * 800);
  }
  function escalate() {
    S.fails++;
    if (S.fails >= 2 && S.level < ICE.length - 1) { S.level++; S.fails = 0; }
    else if (S.fails >= 3) { S.level = 0; S.fails = 0; }
  }

  function tryHost() {
    const gen = ++S.gen;
    kill();
    S.attempt++;
    diag('Procurando o mundo…');
    let p;
    try { p = new Peer(HOST_ID, { debug: 0, config: ICE[Math.max(1, S.level)].cfg }); } catch (e) { retry('Erro ao iniciar a rede.'); return; }
    S.peer = p;
    let decided = false;
    const to = setTimeout(() => { if (gen === S.gen && !decided) { decided = true; retry('O servidor de salas não respondeu.'); } }, 12000);
    p.on('open', () => { if (gen !== S.gen) return; decided = true; clearTimeout(to); becomeHost(); });
    p.on('connection', c => { if (gen === S.gen) accept(c); });
    p.on('disconnected', () => { if (gen === S.gen && S.isHost && !p.destroyed) setTimeout(() => { try { p.reconnect(); } catch (e) { } }, 1500); });
    p.on('error', e => {
      if (gen !== S.gen) return;
      if (!decided && e.type === 'unavailable-id') { decided = true; clearTimeout(to); join(); }
      else if (!decided) { decided = true; clearTimeout(to); retry('Falha no servidor de salas (' + e.type + ').'); }
    });
  }

  function becomeHost() {
    S.isHost = true; S.ready = true; S.fails = 0; S.backoff = 0;
    S.players = {};
    diag('Online — você está hospedando o mundo.');
  }

  function accept(c) {
    c.on('open', () => {
      if (S.conns.size >= MAX_PLAYERS) { setTimeout(() => c.close(), 200); return; }
      S.conns.set(c.peer, { c, uid: null });
    });
    c.on('data', d => {
      const e = S.conns.get(c.peer);
      if (!e || !d || typeof d !== 'object') return;
      if (d.t === 'st' && d.s && typeof d.s === 'object') {
        e.uid = String(d.uid || '').slice(0, 16);
        const s = clean(d.s);
        if (s) { s.seen = now(); S.players[e.uid] = s; }
      } else if (d.t === 'say' && e.uid) {
        relaySay(e.uid, d.text);
      } else if (d.t === 'ev' && e.uid && d.e && typeof d.e === 'object') {
        if (S.inbox.length < 200) S.inbox.push({ from: e.uid, e: d.e });
      }
    });
    const gone = () => {
      const e = S.conns.get(c.peer);
      if (e && e.uid) delete S.players[e.uid];
      S.conns.delete(c.peer);
    };
    c.on('close', gone);
    c.on('error', gone);
  }

  function join() {
    const gen = ++S.gen;
    kill();
    diag('Mundo encontrado. Entrando (' + ICE[S.level].nome + ')…');
    let p;
    try { p = new Peer(undefined, { debug: 0, config: ICE[S.level].cfg }); } catch (e) { retry('Erro ao iniciar a rede.'); return; }
    S.peer = p;
    p.on('open', () => {
      if (gen !== S.gen) return;
      const c = p.connect(HOST_ID, { reliable: true, serialization: 'json' });
      S.hostConn = c;
      const to = setTimeout(() => {
        if (gen !== S.gen || c.open) return;
        escalate();
        retry('A conexão com o anfitrião demorou demais.');
      }, 10000);
      c.on('open', () => {
        if (gen !== S.gen) return;
        clearTimeout(to);
        S.isHost = false; S.ready = true; S.fails = 0; S.backoff = 0; S.lastRx = now();
        try { localStorage.setItem('arson-g-net-level', String(S.level)); } catch (e) { }
        diag('Online — conectado ao mundo.');
      });
      c.on('data', d => {
        if (gen !== S.gen || !d) return;
        S.lastRx = now();
        if (d.t === 'w' && d.p) { S.players = d.p; if (d.m) S.worldIn = d.m; }
        else if (d.t === 'say') pushChat(d.n, d.text);
        else if (d.t === 'ev2' && d.e && S.events.length < 200) S.events.push(d.e);
      });
      c.on('close', () => { if (gen === S.gen) retry('O anfitrião saiu.', true); });
      c.on('error', () => { if (gen === S.gen) retry('Conexão com o anfitrião perdida.', true); });
    });
    p.on('error', e => {
      if (gen !== S.gen) return;
      if (e.type === 'peer-unavailable') retry('O anfitrião saiu; assumindo o mundo…', true);
      else retry('Falha na conexão (' + e.type + ').');
    });
  }

  // só aceita campos conhecidos, com tamanho limitado
  function clean(s) {
    if (!isFinite(s.x) || !isFinite(s.y)) return null;
    const eq = {};
    if (s.eq && typeof s.eq === 'object') for (const k of Object.keys(s.eq).slice(0, 12)) eq[String(k).slice(0, 3)] = String(s.eq[k]).slice(0, 40);
    return {
      x: Math.max(-5000, Math.min(5000, +s.x)), y: Math.max(-5000, Math.min(5000, +s.y)),
      f: String(s.f || 'S').slice(0, 2), a: String(s.a || 'idle').slice(0, 8), n: String(s.n || 'Viajante').slice(0, 16), eq,
      d: s.d ? 1 : 0, sf: s.sf ? 1 : 0, l: Math.max(1, Math.min(9999, s.l | 0)), c: String(s.c || '').replace(/[^a-z]/g, '').slice(0, 8), hp: Math.max(0, Math.min(100, s.hp | 0)),
      sm: Array.isArray(s.sm) ? s.sm.slice(0, 2).filter(a => Array.isArray(a) && a.length === 6).map(a => [a[0] | 0, a[1] | 0, String(a[2]).replace(/[^a-z]/g, '').slice(0, 9), a[3] ? 1 : 0, String(a[4]).slice(0, 2), String(a[5]).replace(/[^a-z]/g, '').slice(0, 8)]) : [],
    };
  }

  function pushChat(n, text) {
    S.chat.push({ n: String(n || '?').slice(0, 16), text: String(text || '').slice(0, 120) });
    if (S.chat.length > 30) S.chat.shift();
  }
  function relaySay(fromUid, text) {
    const p = fromUid === uid ? S.me : S.players[fromUid];
    const n = p ? p.n : '?';
    pushChat(n, text);
    for (const e of S.conns.values()) if (e.c.open) e.c.send({ t: 'say', n, text: String(text || '').slice(0, 120) });
  }

  // anfitrião: envia o mundo 10x por segundo e limpa quem sumiu
  setInterval(() => {
    if (!S.running) return;
    if (S.isHost && S.ready) {
      const t = now();
      for (const k of Object.keys(S.players)) if (k !== uid && t - (S.players[k].seen || 0) > 6000) delete S.players[k];
      if (S.me) S.players[uid] = Object.assign({}, S.me, { seen: t });
      const msg = { t: 'w', p: S.players, m: S.world };
      for (const e of S.conns.values()) if (e.uid && e.c.open) { try { e.c.send(msg); } catch (err) { } }
    } else if (S.ready && now() - S.lastRx > 6000) {
      retry('O anfitrião parou de responder.', true);
    }
  }, 100);

  window.ArsonNet = {
    start(name) {
      if (S.running) return;
      S.name = String(name || 'Viajante').slice(0, 16);
      S.running = true;
      loop();
    },
    setMe(json) {
      let s;
      try { s = clean(JSON.parse(json)); } catch (e) { return; }
      if (!s) return;
      S.me = s;
      if (!S.isHost && S.ready && S.hostConn && S.hostConn.open) {
        try { S.hostConn.send({ t: 'st', uid, s }); } catch (e) { }
      }
    },
    say(text) {
      text = String(text || '').trim().slice(0, 120);
      if (!text || !S.ready) return;
      if (S.isHost) relaySay(uid, text);
      else if (S.hostConn && S.hostConn.open) { S.hostConn.send({ t: 'say', text }); }
    },
    poll() {
      const others = {};
      for (const k of Object.keys(S.players)) if (k !== uid) others[k] = S.players[k];
      const chat = S.chat; S.chat = [];
      const events = S.events; S.events = [];
      const inbox = S.inbox; S.inbox = [];
      const world = S.isHost ? null : S.worldIn; S.worldIn = null;
      return JSON.stringify({ status: S.status, host: S.isHost, ready: S.ready, uid, players: others, chat, events, inbox, world });
    },
    // anfitrião: estado dos monstros (vai junto com os jogadores, 10x/s)
    setWorld(json) {
      if (!S.isHost) return;
      try { S.world = JSON.parse(json); } catch (e) { }
    },
    // qualquer um -> anfitrião (no anfitrião, cai na própria caixa de entrada)
    send(json) {
      let e; try { e = JSON.parse(json); } catch (er) { return; }
      if (!S.ready) return;
      if (S.isHost) { S.inbox.push({ from: uid, e }); return; }
      if (S.hostConn && S.hostConn.open) { try { S.hostConn.send({ t: 'ev', e }); } catch (er) { } }
    },
    // anfitrião -> um jogador
    sendTo(to, json) {
      let e; try { e = JSON.parse(json); } catch (er) { return; }
      if (!S.isHost) return;
      if (to === uid) { S.events.push(e); return; }
      for (const c of S.conns.values()) if (c.uid === to && c.c.open) { try { c.c.send({ t: 'ev2', e }); } catch (er) { } }
    },
    // ?nome=Fulano no endereço tem prioridade (atalho e testes automáticos)
    savedName() {
      const q = (new URLSearchParams(location.search).get('nome') || '').replace(/[^\p{L}\p{N} _-]/gu, '').trim().slice(0, 16);
      if (q) return q;
      try { return localStorage.getItem('arson-g-nome') || ''; } catch (e) { return ''; }
    },
    build() { return BUILD; },
    updateReady() { return NEW_BUILD !== ''; },
    // recarrega para a versão nova e, na volta, entra direto no personagem (pula a tela inicial)
    reloadForUpdate(slot) { try { sessionStorage.setItem('arson-resume', String(slot || 1)); } catch (e) { } location.reload(); },
    takeResume() { try { const r = Number(sessionStorage.getItem('arson-resume') || 0); sessionStorage.removeItem('arson-resume'); return r; } catch (e) { return 0; } },
    saveName(n) { try { localStorage.setItem('arson-g-nome', String(n).slice(0, 16)); } catch (e) { } },
  };
})();
