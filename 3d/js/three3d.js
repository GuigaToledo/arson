'use strict';
// ============================================================
//  ARSON — mundo 3D (Three.js r147 + modelos KayKit, licença CC0)
//  Personagens com esqueleto e animações reais; chão procedural
//  com luz e sombra; cenário em instâncias para rodar rápido.
// ============================================================
const R3 = { ok: false, ready: false, failed: false, prog: 0, models: {}, clips: { M: {}, L: {} }, weapons: {}, hgt: {} };
const MODEL_DEF = {
  guerreiro: { f: 'Knight', rig: 'M', s: 1, w: [['sword_1handed', 'handslot.r'], ['shield_round', 'handslot.l']], atk: 'Melee_1H_Attack_Chop', cast: 'Melee_1H_Attack_Slice_Horizontal', tintParts: /Cape|Body/ },
  mago: { f: 'Mage', rig: 'M', s: 1, w: [['staff', 'handslot.r']], atk: 'Ranged_Magic_Shoot', cast: 'Ranged_Magic_Spellcasting', tintParts: /Cape|Hat|Body/ },
  arqueiro: { f: 'Ranger', rig: 'M', s: 1, w: [['bow_withString', 'handslot.l']], atk: 'Ranged_Bow_Release', cast: 'Ranged_Bow_Draw', tintParts: /Cape|Body/ },
  rato: { f: 'Skeleton_Minion', rig: 'M', s: 0.82, atk: 'Melee_Unarmed_Attack_Punch_A' },
  javali: { f: 'Skeleton_Warrior', rig: 'M', s: 1, atk: 'Melee_Unarmed_Attack_Kick' },
  lobo: { f: 'Werewolf_Wolf', rig: 'M', s: 1.08, atk: 'Melee_Unarmed_Attack_Punch_A' },
  goblin: { f: 'Skeleton_Mage', rig: 'M', s: 1, atk: 'Ranged_Magic_Shoot' },
  salamandra: { f: 'Monstrosity', rig: 'L', s: 0.48, tint: 0xffa070, emis: 0x3a0e00, atk: 'Melee_Unarmed_Punch' },
  golem: { f: 'FrostGolem', rig: 'L', s: 0.6, tint: 0x8a5a48, emis: 0x8a2a00, atk: 'Melee_2H_Slam' },
  arson: { f: 'Monstrosity', rig: 'L', s: 1.2, tint: 0xff7030, emis: 0xa02a00, atk: 'Melee_Unarmed_Smash', fire: true },
  boneco: { f: 'Mannequin_Medium', rig: 'M', s: 1, atk: 'Melee_Unarmed_Attack_Punch_A', still: true },
  mercador: { f: 'Paladin', rig: 'M', s: 1 },
  sacerdotisa: { f: 'Cleric', rig: 'M', s: 1 },
};
const MODEL_BASE = (document.currentScript && document.currentScript.src) ? document.currentScript.src.replace(/js\/three3d\.js.*$/, 'models/') : 'models/';
const CHAR_SCALE = 0.7; // personagens e monstros em relação ao cenário
const RIG_FILES = { M: ['Rig_Medium_General', 'Rig_Medium_MovementBasic', 'Rig_Medium_CombatMelee', 'Rig_Medium_CombatRanged'], L: ['Rig_Large_General', 'Rig_Large_MovementBasic', 'Rig_Large_CombatMelee'] };
const WEAPON_FILES = ['sword_1handed', 'shield_round', 'staff', 'bow_withString'];

function load3D(onProg) {
  if (!window.THREE || !THREE.GLTFLoader || !THREE.SkeletonUtils) { R3.failed = true; return Promise.resolve(false); }
  try { if (!init3D()) { R3.failed = true; return Promise.resolve(false); } } catch (e) { console.warn('3D:', e); R3.failed = true; return Promise.resolve(false); }
  const loader = new THREE.GLTFLoader();
  const files = [...new Set(Object.values(MODEL_DEF).map(d => d.f))].map(f => ['m', f, MODEL_BASE + f + '.glb'])
    .concat(RIG_FILES.M.map(f => ['M', f, MODEL_BASE + f + '.glb']), RIG_FILES.L.map(f => ['L', f, MODEL_BASE + f + '.glb']), WEAPON_FILES.map(f => ['w', f, MODEL_BASE + f + '.gltf']));
  let done = 0, texArr = null;
  const texP = loadTexArrays().then(t => { texArr = t; });
  return Promise.all([texP].concat(files.map(([k, name, url]) => loader.loadAsync(url).then(g => {
    if (k === 'm') R3.models[name] = g.scene;
    else if (k === 'w') R3.weapons[name] = g.scene;
    else for (const c of g.animations) R3.clips[k][c.name] = c;
    done++; R3.prog = done / files.length; if (onProg) onProg(R3.prog);
  })))).then(() => {
    buildGround(texArr);
    for (const [type, d] of Object.entries(MODEL_DEF)) {
      const b = new THREE.Box3().setFromObject(R3.models[d.f]);
      R3.hgt[type] = (b.max.y - b.min.y) * d.s * CHAR_SCALE;
    }
    R3.ready = true; return true;
  }).catch(e => { console.warn('falha ao carregar modelos 3D:', e); R3.failed = true; return false; });
}

// ------------------------------------------------------------
//  Cena
// ------------------------------------------------------------
let renderer, scene, camera, sun, hemi, groundMat, P3add, P3norm;
const ACT = new Map(), FX3 = [], DEATHS = [], LIGHTS = [], CHUNKS = [];
let _v, _ray, _plane;
function init3D() {
  _v = new THREE.Vector3(); _ray = new THREE.Raycaster(); _plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const c = $('gl');
  renderer = new THREE.WebGLRenderer({ canvas: c, antialias: true, powerPreference: 'high-performance' });
  if (!renderer.getContext()) return false;
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  renderer.setSize(innerWidth, innerHeight, false);
  renderer.outputEncoding = THREE.sRGBEncoding;
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x9cc3e6);
  scene.fog = new THREE.Fog(0x9cc3e6, 22, 46);
  camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.3, 60);
  hemi = new THREE.HemisphereLight(0xcfe3ff, 0x4a3a28, 0.75); scene.add(hemi);
  sun = new THREE.DirectionalLight(0xfff0d8, 2.1);
  sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
  const sc = sun.shadow.camera; sc.left = -11; sc.right = 11; sc.top = 11; sc.bottom = -11; sc.near = 1; sc.far = 40;
  sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.02;
  scene.add(sun); scene.add(sun.target);
  for (let i = 0; i < 2; i++) { const l = new THREE.PointLight(0xff8a3a, 0, 6, 2); scene.add(l); LIGHTS.push(l); }
  buildWorld();
  P3add = makeParticles(true); P3norm = makeParticles(false);
  SKY = new THREE.Color(); SKY_DAY = new THREE.Color(0x9cc3e6); SKY_VOLC = new THREE.Color(0x2a0c06);
  R3.ok = true;
  try { setupPost(); } catch (e) { console.warn('pós-processamento indisponível:', e); }
  addEventListener('resize', () => { renderer.setSize(innerWidth, innerHeight, false); camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); });
  return true;
}
function dataTex(src, linear, mul) {
  const d = new Uint8Array(W * H * 4);
  for (let i = 0; i < W * H; i++) { const v = Math.min(255, Math.round(src[i] * (mul || 1))); d[i * 4] = v; d[i * 4 + 1] = v; d[i * 4 + 2] = v; d[i * 4 + 3] = 255; }
  const t = new THREE.DataTexture(d, W, H, THREE.RGBAFormat);
  t.magFilter = t.minFilter = linear ? THREE.LinearFilter : THREE.NearestFilter;
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping; t.needsUpdate = true;
  return t;
}
// chão: o mesmo desenho procedural de antes, agora com luz e sombras reais
// texturas reais (ambientCG, CC0) empilhadas em 2 "array textures": cores e relevo (normal map)
const TEX_LAYERS = ['grass', 'forest', 'path', 'sand', 'stone', 'ash'];
function loadTexArrays() {
  if (!renderer.capabilities.isWebGL2 || !THREE.DataArrayTexture) return Promise.resolve(null);
  const S = 512;
  const load = n => new Promise((res, rej) => { const im = new Image(); im.onload = () => res(im); im.onerror = rej; im.src = MODEL_BASE + 'tex/' + n + '.jpg'; });
  return Promise.all(TEX_LAYERS.flatMap(n => [load(n + '_c'), load(n + '_n')])).then(ims => {
    const c = mk(S, S), g = c.getContext('2d', { willReadFrequently: true });
    const arr = off => {
      const data = new Uint8Array(S * S * 4 * TEX_LAYERS.length);
      TEX_LAYERS.forEach((n, i) => { g.clearRect(0, 0, S, S); g.drawImage(ims[i * 2 + off], 0, 0, S, S); data.set(g.getImageData(0, 0, S, S).data, i * S * S * 4); });
      const t = new THREE.DataArrayTexture(data, S, S, TEX_LAYERS.length);
      t.format = THREE.RGBAFormat; t.type = THREE.UnsignedByteType;
      t.wrapS = t.wrapT = THREE.RepeatWrapping; t.minFilter = THREE.LinearMipmapLinearFilter; t.magFilter = THREE.LinearFilter;
      t.generateMipmaps = true; t.anisotropy = 8; t.needsUpdate = true;
      return t;
    };
    return { col: arr(0), nrm: arr(1) };
  }).catch(e => { console.warn('texturas PBR indisponíveis:', e); return null; });
}
function buildGround(tex) {
  const U = { uMap: { value: dataTex(MAP) }, uGrd: { value: dataTex(GRD) }, uDep: { value: dataTex(DEPTH, true, 60) }, uTime: { value: 0 } };
  if (tex) { U.uCol = { value: tex.col }; U.uNrm = { value: tex.nrm }; }
  groundMat = new THREE.MeshStandardMaterial({ roughness: 0.92, metalness: 0 });
  if (tex) groundMat.defines = { USE_PBR: '' };
  R3.pbr = !!tex;
  groundMat.onBeforeCompile = sh => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vW;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvW = (modelMatrix * vec4(position, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\n' + GROUND_GLSL)
      .replace('vec4 diffuseColor = vec4( diffuse, opacity );', 'vec4 diffuseColor = vec4( groundColor(vW.xz), opacity );')
      .replace('#include <roughnessmap_fragment>', 'float roughnessFactor = gRough;')
      .replace('#include <normal_fragment_begin>', `#include <normal_fragment_begin>
#ifdef USE_PBR
  if (gUseN > .5) { vec3 nw = normalize(vec3(gN.x, gN.z, gN.y)); normal = normalize((viewMatrix * vec4(nw, 0.)).xyz); } else
#endif
  {
    vec3 dpx = dFdx(-vViewPosition), dpy = dFdy(-vViewPosition);
    float dhx = dFdx(gH), dhy = dFdy(gH);
    vec3 r1 = cross(dpy, normal), r2 = cross(normal, dpx);
    float det = dot(dpx, r1);
    vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
    normal = normalize(abs(det) * normal - grad * 0.06);
  }`)
      .replace('#include <emissivemap_fragment>', 'totalEmissiveRadiance += diffuseColor.rgb * gEmis * 1.3;');
  };
  const geo = new THREE.PlaneGeometry(W + 40, H + 40, 1, 1);
  const m = new THREE.Mesh(geo, groundMat);
  m.rotation.x = -Math.PI / 2; m.position.set(W / 2, 0, H / 2);
  m.receiveShadow = true;
  scene.add(m);
  R3.groundU = U;
}
const GROUND_GLSL = `
uniform sampler2D uMap, uGrd, uDep; uniform float uTime;
varying vec3 vW;
float gH = 0., gEmis = 0., gRough = .92;
#ifdef USE_PBR
uniform highp sampler2DArray uCol, uNrm;
vec3 gN = vec3(0., 0., 1.); float gUseN = 0.;
#endif
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3. - 2. * f);
  return mix(mix(h21(i), h21(i + vec2(1., 0.)), u.x), mix(h21(i + vec2(0., 1.)), h21(i + vec2(1., 1.)), u.x), u.y); }
float fbm(vec2 p){ float s = 0., a = .5; for (int i = 0; i < 3; i++){ s += a * vn(p); p = p * 2.03 + 17.1; a *= .5; } return s / .875; }
float raw(vec2 t){ if (t.x < 0. || t.y < 0. || t.x > 127. || t.y > 127.) return 3.; return floor(texture2D(uMap, (t + .5) / 128.).r * 255. + .5); }
float grd(vec2 t){ if (t.x < 0. || t.y < 0. || t.x > 127. || t.y > 127.) return 0.; return floor(texture2D(uGrd, (t + .5) / 128.).r * 255. + .5); }
bool sharpT(float r){ return r == 4. || r == 5. || r == 12.; }
#ifdef USE_PBR
bool pbrT(float g){ return g == 0. || g == 2. || g == 4. || g == 8. || g == 9.; }
vec3 nmap(vec2 uv, float L){ vec3 n = texture(uNrm, vec3(uv, L)).xyz * 2. - 1.; n.y = -n.y; return n; }
// uma camada de textura real; a grama mistura duas escalas e manchas de grama de floresta (sem repetição visível)
vec4 lay(vec2 w, float g, out vec3 nrm){
  float L; vec2 uv; float rough;
  if (g == 2.) { L = 3.; uv = w / 2.5; rough = .9; }
  else if (g == 8.) { L = 2.; uv = w / 2.2; rough = .95; }
  else if (g == 4.) { L = 4.; uv = w / 2.4; rough = .7; }
  else if (g == 9.) { L = 5.; uv = w / 2.8; rough = .82; }
  else { L = 0.; uv = w / 2.2; rough = .93; }
  vec3 c = texture(uCol, vec3(uv, L)).rgb, n = nmap(uv, L);
  if (L == 0.) {
    vec2 uv2 = mat2(.8, -.6, .6, .8) * w / 5.3 + .37;
    float m = smoothstep(.3, .7, vn(w * .35 + 4.)) * .5;
    c = mix(c, texture(uCol, vec3(uv2, 0.)).rgb, m); n = normalize(mix(n, nmap(uv2, 0.), m));
    float f = smoothstep(.62, .8, fbm(w * .12 + 20.)) * .7;
    vec2 uf = w / 3.2;
    c = mix(c, texture(uCol, vec3(uf, 1.)).rgb, f); n = normalize(mix(n, nmap(uf, 1.), f));
    float l = dot(c, vec3(.3, .59, .11)); c = mix(vec3(l), c, 1.25) * vec3(.82, .92, .74); // grama mais viva e menos amarela
  } else if (L == 5.) { c *= .8; }
  nrm = n;
  return vec4(c, rough);
}
#endif
vec3 groundColor(vec2 w){
  vec2 tp = floor(w);
  float r0 = raw(tp), g;
  if (sharpT(r0)) g = r0 == 12. ? 12. : 4.;
  else {
    vec2 j = vec2(vn(w * 1.3 + 3.1) + vn(w * 3.4 + 8.2) * .5, vn(w * 1.3 + 17.7) + vn(w * 3.4 + 29.3) * .5) / 1.5 - .5;
    vec2 tq = floor(w + j * .62);
    float rq = raw(tq);
    g = sharpT(rq) ? grd(tp) : grd(tq);
  }
  float big = vn(w * .22), t = uTime;
  vec3 col;
#ifdef USE_PBR
  if (pbrT(g)) {
    // segunda amostra com outro contorno: bordas suaves entre terrenos
    vec2 j2 = vec2(vn(w * 1.7 + 41.) , vn(w * 1.7 + 63.)) - .5;
    float g2 = sharpT(r0) ? g : grd(floor(w + j2 * .5));
    if (!pbrT(g2)) g2 = g;
    vec3 n1, n2;
    vec4 a = lay(w, g, n1);
    vec4 b = g2 == g ? a : lay(w, g2, n2);
    if (g2 == g) n2 = n1;
    col = mix(a.rgb, b.rgb, .5); gRough = mix(a.a, b.a, .5); gN = normalize(mix(n1, n2, .5)); gUseN = 1.;
    if (g == 9.) {
      float cr = abs(vn(w * 1.3) - .5), glow = smoothstep(.022, 0., cr);
      col = mix(col * (1. - smoothstep(.05, .02, cr) * .4), vec3(1., .45, .1), glow * (.75 + .25 * sin(t * 2. + w.y * 3.)));
      gEmis = glow;
    }
    if (r0 == 7.) {
      vec2 cc = floor(w * 5.), o = vec2(h21(cc), h21(cc + 4.)) * .6 + .2;
      float fd = length(fract(w * 5.) - o), pick = h21(cc + 7.);
      vec3 fc = pick < .2 ? vec3(1., .85, .3) : pick < .4 ? vec3(1., .45, .58) : pick < .6 ? vec3(.95, .95, .95) : pick < .8 ? vec3(1., .6, .25) : vec3(.7, .55, 1.);
      if (fd < .09) col = mix(fc, vec3(1., .92, .6), smoothstep(.035, 0., fd));
    }
    if (raw(tp - vec2(0., 1.)) == 5. && r0 != 5.) col *= mix(.6, 1., smoothstep(0., .45, fract(w.y)));
    col *= .95 + big * .1;
    return pow(col, vec3(2.2));
  }
#endif
  if (g == 1.) {
    float d = texture2D(uDep, w / 128.).r * 4.25;
    float k = clamp(d / 3., 0., 1.);
    col = mix(vec3(.2, .5, .52), vec3(.04, .16, .32), k);
    gH = (vn(w * 3. + t * vec2(.35, .2)) + vn(w * 5.3 - t * vec2(.25, .4)) * .6) * .35;
    float ca = abs(vn(w * 4. + t * .25) - .5);
    col += (1. - k) * smoothstep(.06, 0., ca) * .14;
    float foam = smoothstep(.65, 0., d) * (.45 + .55 * vn(w * 9. + t * .6));
    col = mix(col, vec3(.9, .95, .93), foam * .65);
    gRough = mix(.08, .6, foam);
  } else if (g == 10.) {
    vec2 fl = w + vec2(t * .05, t * .03);
    float mol = smoothstep(.42, .58, fbm(fl * .9));
    float q = fbm(w * 2.4 - t * .08);
    vec3 hot = mix(vec3(.85, .22, .03), vec3(1., .82, .35), q);
    float vein = smoothstep(.05, 0., abs(vn(w * 3. + t * .1) - .5));
    hot = mix(hot, vec3(1., .96, .7), vein * (.6 + .4 * sin(t * 2. + w.x)));
    col = mix(vec3(.2, .08, .05) * (.7 + .5 * vn(w * 20.)), hot, mol);
    gEmis = mol; gH = (1. - mol) * vn(w * 12.) * .5; gRough = mix(.95, .5, mol);
  } else if (g == 2.) {
    col = vec3(.81, .72, .52) * (.92 + big * .14) * (.94 + h21(floor(w * 160.)) * .1);
    gH = sin((w.y + w.x * .3 + fbm(w * 1.5) * 1.2) * 18.) * .06 + vn(w * 40.) * .04;
  } else if (g == 8.) {
    col = vec3(.48, .37, .24) * (.82 + fbm(w * 2.5) * .35);
    gH = fbm(w * 6.) * .2;
    vec2 cc = floor(w * 7.), o = vec2(h21(cc), h21(cc + 9.)) * .5 + .25;
    float pd = length(fract(w * 7.) - o);
    if (h21(cc + 3.) < .22 && pd < .24) { col = vec3(.56, .53, .49) * (.8 + h21(cc + 5.) * .3); gH = sqrt(max(0., .0576 - pd * pd)) * 3.; }
    col *= .93 + h21(floor(w * 150.)) * .12;
  } else if (g == 4.) {
    float row = floor(w.y * 3.), fy = fract(w.y * 3.);
    float cf = w.x * 2. + mod(row, 2.) * .5, fx = fract(cf), cx = floor(cf);
    float e = min(min(fx, 1. - fx) * 32., min(fy, 1. - fy) * 21.3);
    float hb = h21(vec2(cx, row));
    if (e < 1.8) { col = vec3(.26, .25, .22) + vec3(0., .06, 0.) * step(.7, vn(w * 8.)); gH = 0.; }
    else { col = (vec3(.6, .57, .52) + (hb - .5) * vec3(.1, .08, .05)) * (.9 + vn(w * 9.) * .18); gH = smoothstep(1.8, 7., e) * .45 + vn(w * 25.) * .04; gRough = .75; }
    col *= .94 + h21(floor(w * 170.)) * .08;
  } else if (g == 9.) {
    col = vec3(.27, .24, .23) * (.8 + fbm(w * 2.) * .4);
    float cr = abs(vn(w * 1.3) - .5);
    gH = fbm(w * 5.) * .3 - smoothstep(.05, 0., cr) * .3;
    float glow = smoothstep(.022, 0., cr);
    col = mix(col * (1. - smoothstep(.05, .02, cr) * .3), vec3(1., .45, .1), glow * (.75 + .25 * sin(t * 2. + w.y * 3.)));
    gEmis = glow;
  } else if (g == 12.) {
    vec2 f = fract(w);
    float hz = (raw(tp + vec2(-1., 0.)) == 12. || raw(tp + vec2(1., 0.)) == 12. || raw(tp + vec2(-1., 0.)) == 8. || raw(tp + vec2(1., 0.)) == 8.) ? 1. : 0.;
    float al = mix(f.y, f.x, hz), ac = mix(f.x, f.y, hz);
    float pl = floor(al * 4.5), pf = fract(al * 4.5);
    col = vec3(.49, .34, .2) * (.8 + h21(vec2(pl, tp.x + tp.y * 7.)) * .3) * (.92 + sin(ac * 40. + vn(w * 4.) * 6.) * .06);
    gH = smoothstep(0., .08, pf) * smoothstep(1., .9, pf) * .35;
    if (pf < .07) col *= .35;
    if (ac < .07 || ac > .93) col *= .55;
  } else {
    float lush = vn(w * .7);
    col = mix(vec3(.2, .4, .14), vec3(.38, .51, .21), lush * lush);
    col = mix(col, vec3(.55, .55, .28), smoothstep(.6, .75, fbm(w * .15 + 50.)) * .6);
    float sway = sin(t * 1.3 + w.x * .8 + w.y * .5) * .04;
    float blade = vn(vec2(w.x * 38. + sway * 20., w.y * 11.));
    float blade2 = vn(vec2(w.x * 70. - 5., w.y * 22.) + sway * 10.);
    gH = blade * .4 + blade2 * .2 + fbm(w * 3.) * .2;
    col *= .72 + blade * .3 + blade2 * .15 + (vn(w * 4.) - .5) * .25;
    if (r0 == 7.) {
      vec2 cc = floor(w * 5.), o = vec2(h21(cc), h21(cc + 4.)) * .6 + .2;
      float fd = length(fract(w * 5.) - o), pick = h21(cc + 7.);
      vec3 fc = pick < .2 ? vec3(1., .85, .3) : pick < .4 ? vec3(1., .45, .58) : pick < .6 ? vec3(.95, .95, .95) : pick < .8 ? vec3(1., .6, .25) : vec3(.7, .55, 1.);
      if (fd < .11) { col = mix(fc, vec3(1., .92, .6), smoothstep(.04, 0., fd)); gH = .5; }
    }
  }
  if (raw(tp - vec2(0., 1.)) == 5. && r0 != 5.) col *= mix(.6, 1., smoothstep(0., .45, fract(w.y)));
  col *= .93 + big * .14;
  return pow(col, vec3(2.2)); // cores em sRGB -> linear
}`;

// ------------------------------------------------------------
//  Cenário (instâncias: milhares de objetos em poucas chamadas)
// ------------------------------------------------------------
function colorize(geo, fn) {
  const p = geo.attributes.position, c = new Float32Array(p.count * 3);
  for (let i = 0; i < p.count; i++) { const [r, g, b] = fn(p.getX(i), p.getY(i), p.getZ(i), i); c[i * 3] = r; c[i * 3 + 1] = g; c[i * 3 + 2] = b; }
  geo.setAttribute('color', new THREE.BufferAttribute(c, 3));
  return geo;
}
function jiggle(geo, amt, seed) {
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const n = vnoise(x * 3 + seed, z * 3 + y * 2, 7) - 0.5;
    p.setXYZ(i, x * (1 + n * amt), y * (1 + n * amt * 0.6), z * (1 + n * amt));
  }
  geo.computeVertexNormals();
  return geo;
}
function prep(geo) { geo = geo.index ? geo.toNonIndexed() : geo; geo.deleteAttribute && geo.attributes.uv && geo.deleteAttribute('uv'); return geo; }
function merge(list) { return THREE.BufferGeometryUtils.mergeBufferGeometries(list.map(prep)); }
const hexRGB = h => [((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255].map(v => Math.pow(v, 2.2));
function treeGeo(pine, seed) {
  const r = prng(seed), parts = [];
  const trunk = new THREE.CylinderGeometry(0.07, 0.12, pine ? 0.7 : 1.0, 7);
  trunk.translate(0, pine ? 0.35 : 0.5, 0);
  parts.push(colorize(trunk, () => hexRGB(0x5a3c22)));
  if (pine) {
    for (let i = 0; i < 4; i++) {
      const c = new THREE.ConeGeometry(0.62 - i * 0.12, 0.75, 7, 1);
      c.translate(0, 0.65 + i * 0.42, 0);
      jiggle(c, 0.12, seed + i);
      parts.push(colorize(c, (x, y) => { const k = clamp((y - 0.6) / 2, 0, 1); return hexRGB(0x1d4a1b).map((v, j) => v * (0.75 + k * 0.6 + (r() - 0.5) * 0.15)); }));
    }
  } else {
    const blobs = [[0, 1.35, 0, 0.6], [0.35, 1.2, 0.15, 0.45], [-0.32, 1.22, -0.1, 0.46], [0.05, 1.68, -0.05, 0.42], [-0.1, 1.15, 0.36, 0.4], [0.15, 1.2, -0.38, 0.4]];
    for (const [x, y, z, s] of blobs) {
      const b = new THREE.IcosahedronGeometry(s, 1);
      jiggle(b, 0.28, seed * 3 + x * 10);
      b.translate(x, y, z);
      parts.push(colorize(b, (vx, vy) => { const k = clamp((vy - 0.8) / 1.2, 0, 1); const base = hexRGB(0x2e6a24); const n = 0.75 + k * 0.55 + (r() - 0.5) * 0.18; return [base[0] * n, base[1] * n, base[2] * n]; }));
    }
  }
  return merge(parts);
}
function deadTreeGeo(seed) {
  const r = prng(seed), parts = [];
  const t = new THREE.CylinderGeometry(0.06, 0.13, 1.4, 6); t.translate(0, 0.7, 0); parts.push(t);
  for (let i = 0; i < 4; i++) {
    const b = new THREE.CylinderGeometry(0.02, 0.05, 0.6, 5); b.translate(0, 0.3, 0);
    b.rotateZ((r() < 0.5 ? 1 : -1) * (0.5 + r() * 0.5)); b.rotateY(r() * 6.28); b.translate(0, 0.6 + i * 0.2, 0);
    parts.push(b);
  }
  return colorize(merge(parts), (x, y) => hexRGB(0x221a17).map(v => v * (0.8 + y * 0.15)));
}
function rockGeo(ash) {
  const g = new THREE.DodecahedronGeometry(0.42, 1);
  jiggle(g, 0.35, ash ? 9 : 3); g.scale(1, 0.7, 1); g.translate(0, 0.18, 0);
  return colorize(g, (x, y) => { const base = ash ? hexRGB(0x3a3432) : hexRGB(0x8a8680); const k = 0.75 + y * 0.6; return base.map(v => v * k); });
}
function canvasTex(w, h, fn, rep) {
  const c = mk(w, h); fn(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.encoding = THREE.sRGBEncoding; t.anisotropy = 8;
  if (rep) { t.wrapS = t.wrapT = THREE.RepeatWrapping; }
  return t;
}
function buildWorld() {
  const lists = { broad: [], pine: [], dead: [], rock: [], ashrock: [], wall: [] };
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const t = MAP[y * W + x];
    if (t === T.TREE) (vnoise(x / 9, y / 9, 301) > 0.56 ? lists.pine : lists.broad).push([x, y]);
    else if (t === T.DEADTREE) lists.dead.push([x, y]);
    else if (t === T.ROCK) (grdOf(x, y) === T.ASH ? lists.ashrock : lists.rock).push([x, y]);
    else if (t === T.WALL) lists.wall.push([x, y]);
  }
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.88, metalness: 0 });
  const inst = (geo, all, fn, shadow) => {
    const groups = new Map();
    for (const p of all) { const k = Math.floor(p[0] / 16) * 100 + Math.floor(p[1] / 16); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(p); }
    for (const [k, arr] of groups) instChunk(geo, arr, fn, shadow, Math.floor(k / 100) * 16 + 8, (k % 100) * 16 + 8);
  };
  const instChunk = (geo, arr, fn, shadow, cx, cz) => {
    const m = new THREE.InstancedMesh(geo, mat, arr.length);
    m.frustumCulled = false; CHUNKS.push({ m, cx, cz });
    const o = new THREE.Object3D(), col = new THREE.Color();
    arr.forEach(([x, y], i) => {
      const h = hash2(x, y, 302);
      o.position.set(x + 0.5 + (h - 0.5) * 0.3, 0, y + 0.5 + (hash2(x, y, 303) - 0.5) * 0.3);
      o.rotation.set(0, h * 6.28, 0);
      const s = fn ? fn(h) : 1; o.scale.set(s, s * (0.9 + hash2(x, y, 304) * 0.25), s);
      o.updateMatrix(); m.setMatrixAt(i, o.matrix);
      const v = 0.85 + hash2(x, y, 305) * 0.3; col.setRGB(v, v * (0.95 + h * 0.1), v); m.setColorAt(i, col);
    });
    m.castShadow = shadow !== false; m.receiveShadow = true;
    scene.add(m); return m;
  };
  inst(treeGeo(false, 11), lists.broad, h => 0.9 + h * 0.35);
  inst(treeGeo(true, 23), lists.pine, h => 0.95 + h * 0.4);
  inst(deadTreeGeo(5), lists.dead, h => 0.8 + h * 0.3);
  inst(rockGeo(false), lists.rock, h => 0.7 + h * 0.4);
  inst(rockGeo(true), lists.ashrock, h => 0.7 + h * 0.4);
  // muralha de pedra com textura
  const brick = canvasTex(256, 256, (g, w, h) => {
    const r = prng(77); g.fillStyle = '#4a4036'; g.fillRect(0, 0, w, h);
    for (let row = 0; row < 8; row++) for (let col = -1; col < 5; col++) {
      const x = col * 64 + (row % 2) * 32, y = row * 32;
      g.fillStyle = shade('#8a7d6a', (r() - 0.5) * 0.35); g.fillRect(x + 3, y + 3, 58, 26);
      g.fillStyle = 'rgba(255,255,255,.08)'; g.fillRect(x + 3, y + 3, 58, 4);
      g.fillStyle = 'rgba(0,0,0,.15)'; g.fillRect(x + 3, y + 25, 58, 4);
    }
  }, true);
  const wallMat = new THREE.MeshStandardMaterial({ map: brick, roughness: 0.9 });
  const wg = new THREE.BoxGeometry(1, 1.3, 1); wg.translate(0, 0.65, 0);
  const wm = new THREE.InstancedMesh(wg, wallMat, lists.wall.length); wm.frustumCulled = false;
  const crenG = new THREE.BoxGeometry(0.3, 0.28, 0.3); crenG.translate(0, 1.44, 0);
  const crens = [];
  const o = new THREE.Object3D();
  lists.wall.forEach(([x, y], i) => {
    o.position.set(x + 0.5, 0, y + 0.5); o.rotation.set(0, 0, 0); o.scale.set(1, 1, 1); o.updateMatrix(); wm.setMatrixAt(i, o.matrix);
    if ((x + y) % 2 === 0) crens.push([x + 0.5, y + 0.5]);
  });
  wm.castShadow = true; wm.receiveShadow = true; scene.add(wm);
  const cm = new THREE.InstancedMesh(crenG, wallMat, crens.length); cm.frustumCulled = false;
  crens.forEach(([x, y], i) => { o.position.set(x, 0, y); o.updateMatrix(); cm.setMatrixAt(i, o.matrix); });
  cm.castShadow = true; scene.add(cm);
  buildProps();
}
const FLAMES = [];
function glowTex(col) {
  return canvasTex(128, 128, (g) => { g.fillStyle = rg(g, 64, 64, 0, 64, 64, 64, [[0, col[0]], [0.35, col[1]], [1, 'rgba(0,0,0,0)']]); g.fillRect(0, 0, 128, 128); });
}
let TEX_FIRE, TEX_BLUE, TEX_GREEN, TEX_WHITE;
function spriteMat(tex, op) { return new THREE.SpriteMaterial({ map: tex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: op == null ? 1 : op }); }
function addFlame(x, y, z, s) {
  const sp = new THREE.Sprite(spriteMat(TEX_FIRE)); sp.position.set(x, y, z); sp.scale.set(s, s * 1.4, s); scene.add(sp);
  FLAMES.push({ sp, s, x, y, z, seed: Math.random() * 10 });
}
function buildProps() {
  TEX_FIRE = glowTex(['rgba(255,240,180,1)', 'rgba(255,120,30,.6)']);
  TEX_BLUE = glowTex(['rgba(230,240,255,1)', 'rgba(100,140,255,.6)']);
  TEX_GREEN = glowTex(['rgba(220,255,220,1)', 'rgba(60,255,110,.5)']);
  TEX_WHITE = glowTex(['rgba(255,255,255,1)', 'rgba(255,255,255,.4)']);
  const wood = new THREE.MeshStandardMaterial({ color: 0x7a5232, roughness: 0.85 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x2b2b2e, roughness: 0.5, metalness: 0.6 });
  const stone = new THREE.MeshStandardMaterial({ color: 0xbdb5a4, roughness: 0.9 });
  const add = (geo, mat, x, y, z, ry) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.rotation.y = ry || 0; m.castShadow = true; m.receiveShadow = true; scene.add(m); return m; };
  for (const p of PROPS) {
    if (p.k === 'barril') { add(new THREE.CylinderGeometry(0.2, 0.2, 0.5, 12), wood, p.x, 0.25, p.y); add(new THREE.TorusGeometry(0.205, 0.015, 4, 16), dark, p.x, 0.12, p.y).rotation.x = Math.PI / 2; }
    else if (p.k === 'caixa') add(new THREE.BoxGeometry(0.45, 0.45, 0.45), wood, p.x, 0.225, p.y, 0.3);
    else if (p.k === 'braseiro') { add(new THREE.CylinderGeometry(0.22, 0.1, 0.18, 12), dark, p.x, 0.62, p.y); add(new THREE.CylinderGeometry(0.03, 0.05, 0.55, 6), dark, p.x, 0.27, p.y); addFlame(p.x, 0.85, p.y, 0.5); }
    else if (p.k === 'banca') {
      add(new THREE.BoxGeometry(1.8, 0.08, 0.7), wood, p.x, 0.75, p.y);
      for (const dx of [-0.8, 0.8]) add(new THREE.BoxGeometry(0.08, 1.5, 0.08), wood, p.x + dx, 0.75, p.y - 0.3);
      const aw = canvasTex(256, 64, (g) => { for (let i = 0; i < 8; i++) { g.fillStyle = i % 2 ? '#e9dcc0' : '#b3261e'; g.fillRect(i * 32, 0, 32, 64); } });
      const a = add(new THREE.BoxGeometry(1.9, 0.04, 0.9), new THREE.MeshStandardMaterial({ map: aw, roughness: 0.8 }), p.x, 1.5, p.y); a.rotation.x = 0.25;
      ['#d8322a', '#3a7bff', '#d8322a', '#3a7bff', '#3fd34a'].forEach((c, i) => add(new THREE.SphereGeometry(0.07, 10, 8), new THREE.MeshStandardMaterial({ color: c, roughness: 0.15, metalness: 0.1, emissive: c, emissiveIntensity: 0.25 }), p.x - 0.6 + i * 0.3, 0.86, p.y));
    } else if (p.k === 'altar') {
      add(new THREE.BoxGeometry(1, 0.8, 0.6), stone, p.x, 0.4, p.y);
      add(new THREE.CylinderGeometry(0.25, 0.12, 0.15, 12), dark, p.x, 0.88, p.y);
      addFlame(p.x, 1.1, p.y, 0.7);
    }
  }
}

// ------------------------------------------------------------
//  Partículas (um único desenho para milhares)
// ------------------------------------------------------------
function makeParticles(additive) {
  const N = 3000;
  const g = new THREE.BufferGeometry();
  const pos = new Float32Array(N * 3), col = new Float32Array(N * 3), size = new Float32Array(N), alpha = new Float32Array(N);
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3).setUsage(THREE.DynamicDrawUsage));
  g.setAttribute('pcol', new THREE.BufferAttribute(col, 3).setUsage(THREE.DynamicDrawUsage));
  g.setAttribute('psize', new THREE.BufferAttribute(size, 1).setUsage(THREE.DynamicDrawUsage));
  g.setAttribute('palpha', new THREE.BufferAttribute(alpha, 1).setUsage(THREE.DynamicDrawUsage));
  const m = new THREE.ShaderMaterial({
    uniforms: { uPR: { value: renderer.getPixelRatio() * innerHeight / 2 } },
    vertexShader: 'attribute vec3 pcol; attribute float psize; attribute float palpha; varying vec3 vC; varying float vA; uniform float uPR; void main(){ vC = pcol; vA = palpha; vec4 mv = modelViewMatrix * vec4(position, 1.); gl_PointSize = psize * uPR / -mv.z; gl_Position = projectionMatrix * mv; }',
    fragmentShader: additive ? 'varying vec3 vC; varying float vA; void main(){ float r = length(gl_PointCoord - .5); if (r > .5) discard; float a = smoothstep(.5, 0., r) * vA; gl_FragColor = vec4(vC * a, a); }'
      : 'varying vec3 vC; varying float vA; void main(){ float r = length(gl_PointCoord - .5); if (r > .5) discard; gl_FragColor = vec4(vC, smoothstep(.5, .1, r) * vA); }',
    transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
  });
  const pts = new THREE.Points(g, m); pts.frustumCulled = false; scene.add(pts);
  return { pts, g, pos, col, size, alpha, N, list: [] };
}
function p3(sys, o) { if (sys.list.length < Math.min(sys.N, Q.parts * 1.5)) sys.list.push(o); }
// x,z = posição no chão (tiles), y = altura
function burst3(x, y, z, n, cols, spd, life, opt) {
  opt = opt || {};
  const sys = opt.norm ? P3norm : P3add;
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, e = (Math.random() - 0.3) * (opt.flat ? 0.3 : 1.4), v = spd * (0.3 + Math.random() * 0.7);
    const c = cols[Math.floor(Math.random() * cols.length)];
    p3(sys, { x, y, z, vx: Math.cos(a) * v * Math.cos(e), vy: Math.sin(e) * v + (opt.up || 0), vz: Math.sin(a) * v * Math.cos(e), life: life * (0.5 + Math.random() * 0.5), max: life, s: (opt.s || 0.15) * (0.6 + Math.random() * 0.8), c, grav: opt.grav || 0, drag: opt.drag || 2 });
  }
}
function stepParticles(sys, dt) {
  const L = sys.list; let n = 0;
  for (let i = L.length - 1; i >= 0; i--) {
    const p = L[i]; p.life -= dt;
    if (p.life <= 0) { L[i] = L[L.length - 1]; L.pop(); continue; }
    const k = Math.max(0, 1 - p.drag * dt);
    p.vy -= p.grav * dt; p.vx *= k; p.vy *= k; p.vz *= k;
    p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
  }
  for (const p of L) {
    if (n >= sys.N) break;
    const a = clamp(p.life / p.max, 0, 1);
    sys.pos[n * 3] = p.x; sys.pos[n * 3 + 1] = p.y; sys.pos[n * 3 + 2] = p.z;
    sys.col[n * 3] = p.c[0] / 255; sys.col[n * 3 + 1] = p.c[1] / 255; sys.col[n * 3 + 2] = p.c[2] / 255;
    sys.size[n] = p.s * (0.4 + a * 0.6); sys.alpha[n] = a; n++;
  }
  sys.g.setDrawRange(0, n);
  for (const k of ['position', 'pcol', 'psize', 'palpha']) sys.g.attributes[k].needsUpdate = true;
}

// ------------------------------------------------------------
//  Personagens animados
// ------------------------------------------------------------
function makeActor(type, col, parent) {
  const d = MODEL_DEF[type]; if (!d) return null;
  const m = THREE.SkeletonUtils.clone(R3.models[d.f]);
  m.scale.setScalar(d.s * CHAR_SCALE);
  const tint = col && col[0] >= 0 && d.tintParts ? new THREE.Color(OUTFIT[col[0]]) : null;
  m.traverse(o => {
    if (!o.isMesh) return;
    o.castShadow = true; o.frustumCulled = true;
    if (d.tint || d.emis || (tint && d.tintParts.test(o.name))) {
      o.material = o.material.clone();
      if (d.tint) o.material.color.setHex(d.tint);
      if (d.emis) { o.material.emissive = new THREE.Color(d.emis); o.material.emissiveIntensity = 1; }
      if (tint && d.tintParts.test(o.name)) o.material.color.copy(tint).lerp(new THREE.Color(1, 1, 1), 0.35);
    }
  });
  for (const [w, slot] of d.w || []) {
    const bone = m.getObjectByName(slot), src = R3.weapons[w];
    if (bone && src) { const c = src.clone(); c.traverse(o => { if (o.isMesh) o.castShadow = true; }); bone.add(c); }
  }
  const root = new THREE.Group(); root.add(m); (parent || scene).add(root);
  const mixer = new THREE.AnimationMixer(m);
  const a = { type, root, m, mixer, d, clips: R3.clips[d.rig], act: null, cur: '', lock: 0, yaw: 0, px: null, pz: null, dying: false, dieT: 0 };
  if (!d.still) play(a, 'Idle_A');
  return a;
}
function play(a, name, once, dur) {
  const clip = a.clips[name]; if (!clip) return false;
  if (a.cur === name && !once) return true;
  const act = a.mixer.clipAction(clip);
  act.reset(); act.enabled = true;
  act.setLoop(once ? THREE.LoopOnce : THREE.LoopRepeat, Infinity);
  act.clampWhenFinished = !!once;
  act.timeScale = dur ? clip.duration / dur : 1;
  if (a.act && a.act !== act) act.crossFadeFrom(a.act, once ? 0.08 : 0.2, false);
  act.play();
  a.act = act; a.cur = name;
  if (once) a.lock = dur || clip.duration;
  return true;
}
function disposeActor(a) { if (a.root.parent) a.root.parent.remove(a.root); a.mixer.stopAllAction(); }
function actorFor(key, type, col) {
  let a = ACT.get(key);
  const ck = col ? col.join(',') : '';
  if (a && (a.type !== type || a.ck !== ck)) { disposeActor(a); a = null; }
  if (!a) { a = makeActor(type, col); if (!a) return null; a.ck = ck; ACT.set(key, a); }
  a.seen = true;
  return a;
}
// atualiza posição, rotação (giro de verdade, suave) e animação
function driveActor(a, e, dt, opts) {
  const x = e.x, z = e.y;
  if (a.px == null) { a.px = x; a.pz = z; }
  const dx = x - a.px, dz = z - a.pz, sp = Math.hypot(dx, dz) / Math.max(dt, 1e-3);
  a.px = x; a.pz = z;
  if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
  a.root.position.set(x, 0, z);
  const far = Math.hypot(x - camT.x, z - camT.z);
  a.root.visible = far < 17;
  const sh = far < 9 && Q.shadows;
  if (a.sh !== sh) { a.sh = sh; a.m.traverse(o => { if (o.isMesh) o.castShadow = sh; }); }
  if (!a.root.visible) { a.lock -= dt; return; }
  let want = a.yaw;
  if (opts.face != null) want = opts.face;
  else if (sp > 0.3) want = Math.atan2(dx, dz);
  let diff = want - a.yaw; while (diff > Math.PI) diff -= Math.PI * 2; while (diff < -Math.PI) diff += Math.PI * 2;
  a.yaw += diff * Math.min(1, dt * 12);
  a.root.rotation.y = a.yaw;
  a.lock -= dt;
  if (a.dying) return;
  if (a.d.still) { a.m.rotation.z = e.hurtT > 0 ? Math.sin(performance.now() / 40) * 0.12 * (e.hurtT / 0.25) : 0; return; }
  if (opts.atk && a.lock <= 0) { play(a, opts.cast ? (a.d.cast || a.d.atk) : a.d.atk, true, opts.cast ? 0.6 : 0.5) || play(a, 'Melee_Unarmed_Attack_Punch_A', true, 0.5); return; }
  if (opts.hurt && a.lock <= 0 && !a.d.still) { play(a, 'Hit_A', true, 0.35); return; }
  if (a.lock > 0) return;
  if (a.d.still) { play(a, 'Idle_A'); return; }
  const moving = opts.mv || sp > 0.25;
  if (moving) { const run = sp > 2.6; play(a, run ? 'Running_A' : 'Walking_A'); a.act.timeScale = run ? clamp(sp / 4.2, 0.7, 1.5) : clamp(sp / 1.6, 0.6, 1.6); }
  else play(a, 'Idle_A');
}
function faceToward(e, tx, ty) { return Math.atan2(tx - e.x, ty - e.y); }

// ------------------------------------------------------------
//  Efeitos de magia em 3D
// ------------------------------------------------------------
const FIRE3 = [[255, 230, 140], [255, 150, 40], [255, 90, 20], [220, 50, 10]];
function sprite(tex, x, y, z, s, op) { const sp = new THREE.Sprite(spriteMat(tex, op)); sp.position.set(x, y, z); sp.scale.setScalar(s); scene.add(sp); return sp; }
function flash(x, y, z, color, power, dur) { FX3.push({ k: 'light', x, y, z, color, power, t: 0, dur }); }
function fx3Event(e) {
  switch (e.k) {
    case 'dmg': burst3(e.x, 0.7, e.y, 7, [[200, 20, 20], [140, 10, 10]], 2, 0.45, { norm: true, grav: 6, s: 0.08 }); break;
    case 'proj': {
      const len = Math.hypot(e.x1 - e.x, e.y1 - e.y);
      const o = { k: 'proj', f: e.f, x0: e.x, z0: e.y + 0.5, x1: e.x1, z1: e.y1 + 0.35, t: 0, dur: Math.max(0.1, len * (e.f === 'flecha' ? 0.045 : 0.07)), big: e.big ? 1.5 : 1 };
      if (e.f === 'flecha' || e.f === 'palha') {
        const g = new THREE.Group();
        const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.6, 5), new THREE.MeshStandardMaterial({ color: e.f === 'palha' ? 0xd9b860 : 0x7a5232 }));
        shaft.rotation.x = Math.PI / 2; g.add(shaft);
        if (e.f === 'flecha') { const tip = new THREE.Mesh(new THREE.ConeGeometry(0.035, 0.1, 6), new THREE.MeshStandardMaterial({ color: 0xc8ccd0, metalness: 0.8, roughness: 0.3 })); tip.rotation.x = Math.PI / 2; tip.position.z = 0.33; g.add(tip); }
        scene.add(g); o.obj = g;
      } else {
        o.obj = sprite(e.f === 'arcano' ? TEX_BLUE : TEX_FIRE, e.x, 0.9, e.y, 0.7 * o.big);
      }
      FX3.push(o); break;
    }
    case 'slash': { const m = new THREE.Mesh(new THREE.RingGeometry(0.45, 0.6, 24, 1, -1.1, 2.2), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.9, side: THREE.DoubleSide, blending: THREE.AdditiveBlending, depthWrite: false })); m.rotation.x = -Math.PI / 2; m.rotation.z = -e.a; m.position.set(e.x, 0.75, e.y + 0.35); m.scale.setScalar(e.big ? 1.4 : 1); scene.add(m); FX3.push({ k: 'fade', obj: m, t: 0, dur: 0.25, grow: 1.4 }); break; }
    case 'cone': {
      const m = new THREE.Mesh(new THREE.CircleGeometry(e.r, 24, -e.w, e.w * 2), new THREE.MeshBasicMaterial({ color: e.f === 'fogo' ? 0xff8a30 : 0xffffff, transparent: true, opacity: 0.45, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
      m.rotation.x = -Math.PI / 2; m.rotation.z = -e.a; m.position.set(e.x, 0.05, e.y + 0.3); scene.add(m);
      FX3.push({ k: 'fade', obj: m, t: 0, dur: 0.5 });
      if (e.f === 'fogo') FX3.push({ k: 'spray', x: e.x, z: e.y + 0.3, a: e.a, w: e.w, r: e.r, t: 0, dur: 0.45 });
      if (e.f === 'flechas') for (let i = 0; i < 7; i++) { const a = e.a - e.w + (2 * e.w) * i / 6; fx3Event({ k: 'proj', f: 'flecha', x: e.x, y: e.y, x1: e.x + Math.cos(a) * e.r, y1: e.y + Math.sin(a) * e.r }); }
      break;
    }
    case 'chain': {
      const mat = new THREE.LineBasicMaterial({ color: 0xbcd4ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false });
      const lines = [];
      for (let s = 0; s < e.pts.length - 1; s++) { const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(9 * 3), 3)); const l = new THREE.Line(g, mat); scene.add(l); lines.push(l); }
      const sprites = e.pts.slice(1).map(([x, y]) => sprite(TEX_BLUE, x, 0.8, y + 0.4, 1.1));
      FX3.push({ k: 'chain', pts: e.pts, lines, sprites, mat, t: 0, dur: 0.5 });
      for (const [x, y] of e.pts) burst3(x, 0.8, y + 0.4, 10, [[220, 235, 255], [140, 180, 255]], 3, 0.35, { s: 0.1 });
      const last = e.pts[e.pts.length - 1]; flash(last[0], 1, last[1] + 0.4, 0x7aa0ff, 6, 0.4);
      break;
    }
    case 'area': {
      const ring = new THREE.Mesh(new THREE.RingGeometry(e.r * 0.93, e.r, 48), new THREE.MeshBasicMaterial({ color: 0xff5a30, transparent: true, opacity: 0.8, depthWrite: false, side: THREE.DoubleSide }));
      ring.rotation.x = -Math.PI / 2; ring.position.set(e.x, 0.04, e.y); scene.add(ring);
      const o = { k: 'area', f: e.f, x: e.x, z: e.y, r: e.r, delay: e.delay || 0, t: 0, dur: (e.delay || 0) + 0.8, ring, boom: false };
      if (e.f === 'meteoro') { o.rock = new THREE.Mesh(new THREE.DodecahedronGeometry(0.35, 1), new THREE.MeshStandardMaterial({ color: 0x3a2a22, emissive: 0xff5a10, emissiveIntensity: 0.7 })); scene.add(o.rock); o.glow = sprite(TEX_FIRE, e.x, 6, e.y, 2); }
      FX3.push(o); break;
    }
    case 'heal': for (let i = 0; i < 24; i++) { const a = i / 24 * Math.PI * 2; p3(P3add, { x: e.x + Math.cos(a) * 0.45, y: 0.2, z: e.y + Math.sin(a) * 0.45, vx: -Math.sin(a) * 0.4, vy: 1.2 + Math.random(), vz: Math.cos(a) * 0.4, life: 1, max: 1, s: 0.12, c: [120, 255, 140], grav: 0, drag: 1 }); } flash(e.x, 1, e.y, 0x60ff80, 3, 0.6); break;
    case 'lvl': { const m = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.5, 6, 24, 1, true), new THREE.MeshBasicMaterial({ color: 0xffd860, transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide })); m.position.set(e.x, 3, e.y); scene.add(m); FX3.push({ k: 'fade', obj: m, t: 0, dur: 1.4 }); burst3(e.x, 0.6, e.y, 50, [[255, 230, 120], [255, 200, 60]], 2.5, 1.4, { up: 1.5, s: 0.12 }); flash(e.x, 1.5, e.y, 0xffd860, 6, 1.2); break; }
    case 'die': burst3(e.x, 0.5, e.y, 16, [[90, 84, 80], [60, 56, 54], [120, 112, 104]], 1.2, 1.1, { norm: true, up: 0.8, s: 0.35 }); DEATHS.push({ x: e.x, y: e.y, mt: e.mt, t: performance.now() }); if (e.mt === 'arson') { burst3(e.x, 1.5, e.y, 160, FIRE3, 7, 1.4, { s: 0.25 }); shake = 18; } break;
    case 'pdie': burst3(e.x, 0.5, e.y, 22, [[90, 84, 80], [60, 56, 54]], 1.3, 1.1, { norm: true, up: 0.8, s: 0.35 }); break;
  }
}
function stepFx3(dt, t) {
  const lightsWanted = [];
  for (const f of FLAMES) {
    const k = 1 + Math.sin(t * 13 + f.seed) * 0.08 + Math.sin(t * 7 + f.seed * 3) * 0.06;
    f.sp.scale.set(f.s * k, f.s * 1.4 * k, 1);
    if (Math.random() < 0.15) p3(P3add, { x: f.x + (Math.random() - 0.5) * 0.1, y: f.y + 0.1, z: f.z, vx: (Math.random() - 0.5) * 0.3, vy: 1 + Math.random(), vz: 0, life: 0.8, max: 0.8, s: 0.06, c: FIRE3[0], grav: -0.5, drag: 0.5 });
    lightsWanted.push([f.x, f.y + 0.2, f.z, 0xff8a3a, 2.2]);
  }
  for (let i = FX3.length - 1; i >= 0; i--) {
    const f = FX3[i]; f.t += dt;
    const p = f.t / f.dur;
    if (f.k === 'proj') {
      const q = Math.min(1, p), x = lerp(f.x0, f.x1, q), z = lerp(f.z0, f.z1, q), y = 0.9 + Math.sin(q * Math.PI) * (f.f === 'flecha' ? 0.4 : 0.15);
      f.obj.position.set(x, y, z);
      if (f.f === 'flecha' || f.f === 'palha') { f.obj.lookAt(f.x1, 0.8, f.z1); if (f.f === 'palha') f.obj.rotateZ(f.t * 20); }
      else { burst3(x, y, z, 2, f.f === 'arcano' ? [[170, 150, 255], [120, 140, 255]] : FIRE3, 0.6, 0.35, { s: 0.16 * f.big }); lightsWanted.push([x, y, z, f.f === 'arcano' ? 0x7a8aff : 0xff7a2a, 3 * f.big]); }
      if (p >= 1) {
        scene.remove(f.obj);
        if (f.f === 'flecha' || f.f === 'palha') burst3(f.x1, 0.7, f.z1, 6, [[200, 180, 150]], 1, 0.3, { norm: true, s: 0.06, grav: 4 });
        else { burst3(f.x1, 0.8, f.z1, f.big > 1 ? 30 : 14, f.f === 'arcano' ? [[200, 180, 255], [140, 110, 255]] : FIRE3, f.big > 1 ? 3 : 2, 0.5, { s: 0.18 }); flash(f.x1, 1, f.z1, f.f === 'arcano' ? 0x7a8aff : 0xff7a2a, 4, 0.25); }
        FX3.splice(i, 1);
      }
    } else if (f.k === 'fade') {
      f.obj.material.opacity = (1 - p) * (f.obj.material.userData.o0 || (f.obj.material.userData.o0 = f.obj.material.opacity));
      if (f.grow) f.obj.scale.setScalar(1 + p * (f.grow - 1));
      if (p >= 1) { scene.remove(f.obj); FX3.splice(i, 1); }
    } else if (f.k === 'spray') {
      for (let k = 0; k < 10; k++) { const a = f.a + (Math.random() - 0.5) * 2 * f.w, v = f.r * (1.6 + Math.random()); p3(P3add, { x: f.x, y: 0.8, z: f.z, vx: Math.cos(a) * v, vy: (Math.random() - 0.2) * 0.8, vz: Math.sin(a) * v, life: 0.55, max: 0.55, s: 0.35 + Math.random() * 0.3, c: FIRE3[Math.floor(Math.random() * 4)], grav: -1, drag: 2.2 }); }
      lightsWanted.push([f.x + Math.cos(f.a) * f.r * 0.5, 0.8, f.z + Math.sin(f.a) * f.r * 0.5, 0xff7a2a, 6]);
      if (p >= 1) FX3.splice(i, 1);
    } else if (f.k === 'chain') {
      f.mat.opacity = 1 - p;
      f.lines.forEach((l, s) => {
        const [ax, ay] = f.pts[s], [bx, by] = f.pts[s + 1], arr = l.geometry.attributes.position.array;
        for (let k = 0; k <= 8; k++) { const q = k / 8, j = (k === 0 || k === 8) ? 0 : 0.18; arr[k * 3] = lerp(ax, bx, q) + (Math.random() - 0.5) * j; arr[k * 3 + 1] = 0.9 + (Math.random() - 0.5) * j; arr[k * 3 + 2] = lerp(ay, by, q) + 0.4 + (Math.random() - 0.5) * j; }
        l.geometry.attributes.position.needsUpdate = true;
      });
      f.sprites.forEach(s => s.material.opacity = 1 - p);
      if (p >= 1) { f.lines.forEach(l => scene.remove(l)); f.sprites.forEach(s => scene.remove(s)); FX3.splice(i, 1); }
    } else if (f.k === 'area') {
      if (f.t < f.delay) {
        const q = f.t / Math.max(0.01, f.delay);
        f.ring.scale.setScalar(0.3 + q * 0.7); f.ring.material.opacity = 0.4 + 0.4 * q;
        if (f.rock) { const rx = f.x + (1 - q) * 3, ry = 0.3 + (1 - q) * 7; f.rock.position.set(rx, ry, f.z - (1 - q) * 2); f.rock.rotation.x += dt * 5; f.glow.position.copy(f.rock.position); burst3(rx, ry, f.z - (1 - q) * 2, 4, FIRE3, 1, 0.4, { s: 0.3 }); lightsWanted.push([rx, ry, f.z, 0xff7a2a, 5]); }
        if (f.f === 'chuva' && Math.random() < 0.6) { const a = Math.random() * 6.28, r = Math.sqrt(Math.random()) * f.r; fx3Event({ k: 'proj', f: 'flecha', x: f.x + Math.cos(a) * r - 0.8, y: f.z + Math.sin(a) * r - 3, x1: f.x + Math.cos(a) * r, y1: f.z + Math.sin(a) * r - 0.35 }); }
      } else {
        if (!f.boom) {
          f.boom = true;
          if (f.rock) { scene.remove(f.rock); scene.remove(f.glow); }
          if (f.f === 'meteoro' || f.f === 'nova') { burst3(f.x, 0.5, f.z, 110, FIRE3, f.r * 2.4, 0.8, { s: 0.35, flat: true, drag: 3 }); burst3(f.x, 0.3, f.z, 24, [[50, 40, 36], [80, 70, 60]], 4, 0.9, { norm: true, s: 0.12, grav: 9, up: 3 }); flash(f.x, 1.2, f.z, 0xff7a2a, 12, 0.6); if (ME && Math.hypot(ME.x - f.x, ME.y - f.z) < 10) shake = Math.max(shake, f.f === 'meteoro' ? 14 : 8); }
          else if (f.f === 'giro') { burst3(f.x, 0.6, f.z, 40, [[230, 220, 200]], f.r * 2, 0.5, { norm: true, s: 0.08, flat: true }); }
          else burst3(f.x, 0.3, f.z, 30, [[180, 160, 130]], f.r * 1.5, 0.5, { norm: true, s: 0.08, flat: true });
        }
        const q = (f.t - f.delay) / 0.8;
        f.ring.scale.setScalar(1 + q * 0.4); f.ring.material.opacity = Math.max(0, 0.8 * (1 - q));
        f.ring.material.color.setHex(f.f === 'giro' || f.f === 'chuva' ? 0xffffff : 0xffb050);
      }
      if (p >= 1) { scene.remove(f.ring); FX3.splice(i, 1); }
    } else if (f.k === 'light') {
      lightsWanted.push([f.x, f.y, f.z, f.color, f.power * (1 - p)]);
      if (p >= 1) FX3.splice(i, 1);
    }
  }
  // as luzes mais fortes perto da câmera ganham as 4 luzes reais
  if (ME) lightsWanted.sort((a, b) => (b[4] / (1 + Math.hypot(b[0] - ME.x, b[2] - ME.y))) - (a[4] / (1 + Math.hypot(a[0] - ME.x, a[2] - ME.y))));
  LIGHTS.forEach((l, i) => { const w = Q.light ? lightsWanted[i] : null; if (w) { l.position.set(w[0], w[1], w[2]); l.color.setHex(w[3]); l.intensity = w[4]; } else l.intensity = 0; });
}

// ------------------------------------------------------------
//  Quadro 3D
// ------------------------------------------------------------
let camT = { x: 0, z: 0 }, SKY, SKY_DAY, SKY_VOLC;
function render3D(now, dt) {
  const t = now / 1000;
  R3.groundU.uTime.value = t % 1000;
  // personagens
  for (const a of ACT.values()) a.seen = false;
  const tgtFace = (e, tg) => tg ? faceToward(e, tg.tx != null ? tg.tx : tg.x, tg.ty != null ? tg.ty : tg.y) : null;
  for (const n of NPCS) { const a = actorFor('n' + n.id, n.look); if (a) driveActor(a, n, dt, { face: 0 }); }
  for (const m of MON.values()) {
    const a = actorFor('m' + m.id, m.type); if (!a) continue;
    const face = m.dir != null && !m.mvF ? [Math.PI, Math.PI / 2, 0, -Math.PI / 2][m.dir] : null;
    driveActor(a, m, dt, { mv: m.mvF, atk: m.atkT > 0.3, hurt: m.hurtT > 0.15, face });
    if (MODEL_DEF[m.type].fire) { if (Math.random() < 0.6) burst3(m.x + (Math.random() - 0.5), 0.5 + Math.random() * 2, m.y + (Math.random() - 0.5), 1, FIRE3, 0.5, 0.9, { up: 1.5, s: 0.3 }); }
  }
  for (const p of REM.values()) { if (p.dead) continue; const a = actorFor('p' + p.uid, p.voc, p.col); if (a) driveActor(a, p, dt, { mv: p.mvF, atk: p.atkT > 0.25, hurt: p.hurtT > 0.15, face: [Math.PI, Math.PI / 2, 0, -Math.PI / 2][p.dir], cast: false }); }
  if (playing && ME && !ME.dead) {
    const a = actorFor('me', ME.voc, ME.col);
    const tg = ME.target != null ? MON.get(ME.target) : null;
    if (a) driveActor(a, ME, dt, { mv: ME.mv, atk: ME.atkT > 0.25 && !a._atkDone, hurt: ME.hurtT > 0.15, face: ME.atkT > 0 && tg ? tgtFace(ME, tg) : (ME.mv ? null : a.yaw), cast: !!ME.casting });
    if (a && ME.atkT <= 0) ME.casting = false;
  }
  // mortos: animação de morte e somem depois
  for (const [k, a] of ACT) {
    if (a.seen) { a.mixer.update(dt); continue; }
    if (!a.dying && k[0] === 'm') {
      const d = DEATHS.find(d => d.mt === a.type && Math.hypot(d.x - a.px, d.y - a.pz) < 1.5 && now - d.t < 1500);
      if (d) { a.dying = true; a.dieT = 0; a.lock = 0; play(a, 'Death_A', true, 0.9); }
    }
    if (a.dying) { a.dieT += dt; a.mixer.update(dt); if (a.dieT > 8) { a.root.position.y -= dt * 0.3; } if (a.dieT > 11) { disposeActor(a); ACT.delete(k); } continue; }
    disposeActor(a); ACT.delete(k);
  }
  while (DEATHS.length && now - DEATHS[0].t > 3000) DEATHS.shift();
  stepFx3(dt, t);
  stepParticles(P3add, dt); stepParticles(P3norm, dt);
  // câmera de cima, inclinada, seguindo o jogador
  const fx = playing && ME ? ME.x : CX + 0.5, fz = playing && ME ? ME.y : CY + 0.5;
  camT.x += (fx - camT.x) * Math.min(1, dt * 10); camT.z += (fz - camT.z) * Math.min(1, dt * 10);
  if (Math.abs(fx - camT.x) > 6) { camT.x = fx; camT.z = fz; }
  const dist = 8.6 * 84 / zoom, pitch = 1.0;
  let sx = 0, sz = 0; if (shake > 0) { sx = (Math.random() - 0.5) * shake * 0.01; sz = (Math.random() - 0.5) * shake * 0.01; }
  camera.position.set(camT.x + sx, Math.sin(pitch) * dist, camT.z + Math.cos(pitch) * dist + sz);
  camera.lookAt(camT.x + sx, 0.5, camT.z + sz);
  // sol acompanha (sombras nítidas perto do jogador); vulcão escurece e avermelha
  sun.position.set(camT.x - 7, 14, camT.z + 5); sun.target.position.set(camT.x, 0, camT.z);
  const vd = Math.hypot(camT.x - VX, camT.z - VY), amb = clamp((34 - vd) / 18, 0, 1);
  sun.intensity = 2.1 - amb * 1.4; sun.color.setRGB(1, 0.94 - amb * 0.35, 0.85 - amb * 0.6);
  hemi.intensity = 0.75 - amb * 0.35;
  SKY.copy(SKY_DAY).lerp(SKY_VOLC, amb);
  scene.background.copy(SKY); scene.fog.color.copy(SKY);
  sun.castShadow = Q.shadows;
  const smap = qName === 'alta' ? 2048 : 1024;
  if (sun.shadow.mapSize.x !== smap) { sun.shadow.mapSize.set(smap, smap); if (sun.shadow.map) { sun.shadow.map.dispose(); sun.shadow.map = null; } }
  for (const c of CHUNKS) c.m.visible = Math.abs(c.cx - camT.x) < 30 && Math.abs(c.cz - camT.z) < 26;
  renderFrame(false);
  // textos por cima (nomes, barras, números)
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, cv.width, cv.height);
  if (playing) drawOverlayText(now);
}
function proj3(x, y, h) {
  _v.set(x, h, y).project(camera);
  return [(_v.x * 0.5 + 0.5) * cv.width, (-_v.y * 0.5 + 0.5) * cv.height, _v.z];
}
function headH(look) { const k = (look || '').split('|')[0]; return (R3.hgt[k] || 1.3) + 0.15; }
function mouseGround() {
  _v.set(mouse.x / innerWidth * 2 - 1, -(mouse.y / innerHeight) * 2 + 1, 0.5);
  _ray.setFromCamera(_v, camera);
  const p = new THREE.Vector3(); _ray.ray.intersectPlane(_plane, p);
  return { x: p.x, y: p.z };
}
function pick3(mx, my) {
  let best = null, bd = 46 * dpr;
  const test = (e, look, kind) => {
    const h = headH(look);
    const [x1, y1] = proj3(e.x, e.y, h * 0.5);
    const d = Math.hypot(x1 - mx * dpr, y1 - my * dpr);
    if (d < bd) { bd = d; best = { e, kind }; }
  };
  for (const m of MON.values()) test(m, m.type, 'm');
  for (const n of NPCS) test(n, n.look, 'n');
  return best;
}
