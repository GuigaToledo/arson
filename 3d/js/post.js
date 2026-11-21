'use strict';
// ============================================================
//  ARSON — pós-processamento: HDR, bloom, oclusão de ambiente (SAO),
//  gradação de cor de cinema e profundidade de campo (só na abertura)
// ============================================================
const POST = { ok: false, on: false };
const GRADE_SHADER = {
  uniforms: { tDiffuse: { value: null }, uExposure: { value: 1.0 }, uVig: { value: 0.45 }, uSat: { value: 1.04 }, uWarm: { value: 0.0 } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
  fragmentShader: `
uniform sampler2D tDiffuse; uniform float uExposure, uVig, uSat, uWarm; varying vec2 vUv;
vec3 aces(vec3 x){ x *= .6; return clamp((x * (2.51 * x + .03)) / (x * (2.43 * x + .59) + .14), 0., 1.); }
void main(){
  vec3 c = texture2D(tDiffuse, vUv).rgb * uExposure;
  c = aces(c * 1.25);                                  // tone mapping de cinema (HDR -> tela)
  float l = dot(c, vec3(.2126, .7152, .0722));
  c = mix(vec3(l), c, uSat);                           // saturação
  c += vec3(uWarm, uWarm * .35, -uWarm) * (1. - l);    // sombras levemente frias/quentes
  c = pow(max(c, 0.), vec3(1. / 2.2));                 // linear -> sRGB
  c = (c - .5) * 1.06 + .5;                            // contraste
  float v = smoothstep(.95, .3, length((vUv - .5) * vec2(1.15, 1.)));
  c *= mix(1., v, uVig);                               // vinheta
  gl_FragColor = vec4(c, 1.);
}`,
};
function setupPost() {
  if (!THREE.EffectComposer || !THREE.UnrealBloomPass) return false;
  const size = renderer.getDrawingBufferSize(new THREE.Vector2());
  const rt = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType });
  const comp = new THREE.EffectComposer(renderer, rt);
  comp.setPixelRatio(renderer.getPixelRatio()); comp.setSize(innerWidth, innerHeight);
  const rp = new THREE.RenderPass(scene, camera);
  comp.addPass(rp);
  let sao = null;
  if (THREE.SAOPass) {
    sao = new THREE.SAOPass(scene, camera, false, true);
    Object.assign(sao.params, { saoBias: 0.6, saoIntensity: 0.045, saoScale: 6, saoKernelRadius: 22, saoMinResolution: 0, saoBlur: true, saoBlurRadius: 6, saoBlurStdDev: 3, saoBlurDepthCutoff: 0.02 });
    comp.addPass(sao);
  }
  const bloom = new THREE.UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.32, 0.35, 1.05);
  comp.addPass(bloom);
  let bokeh = null;
  if (THREE.BokehPass) { bokeh = new THREE.BokehPass(scene, camera, { focus: 7.5, aperture: 0.0016, maxblur: 0.008 }); bokeh.enabled = false; comp.addPass(bokeh); }
  const grade = new THREE.ShaderPass(GRADE_SHADER);
  comp.addPass(grade);
  Object.assign(POST, { ok: true, comp, rp, sao, bloom, bokeh, grade, rt });
  addEventListener('resize', () => { comp.setPixelRatio(renderer.getPixelRatio()); comp.setSize(innerWidth, innerHeight); bloom.resolution.set(innerWidth, innerHeight); });
  return true;
}
// liga/desliga conforme a qualidade (troca o tone mapping uma única vez, não a cada quadro)
function postMode() {
  const want = POST.ok && Q.glow; // Alta e Média usam o pós-processamento
  if (want !== POST.on) {
    POST.on = want;
    renderer.toneMapping = want ? THREE.NoToneMapping : THREE.ACESFilmicToneMapping;
    scene.traverse(o => { if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach(m => m.needsUpdate = true); });
  }
  if (POST.sao) POST.sao.enabled = qName === 'alta';
}
function renderFrame(title) {
  postMode();
  if (!POST.on) { renderer.render(scene, camera); return; }
  if (POST.bokeh) { POST.bokeh.enabled = !!title; if (title) POST.bokeh.uniforms.focus.value = camera.position.distanceTo(_v.set(T3 ? T3.c.x : 0, 1, T3 ? T3.c.y - 0.6 : 0)); }
  POST.bloom.strength = title ? 0.45 : 0.32;
  POST.comp.render();
}
