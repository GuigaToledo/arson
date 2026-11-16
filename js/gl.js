'use strict';
// ============================================================
//  ARSON — chão em WebGL: pintado pixel a pixel na resolução
//  nativa, com relevo iluminado, água e lava animadas.
//  Sem WebGL, o jogo volta para os blocos pintados em canvas.
// ============================================================
const GLR = { ok: false };
(function initGL() {
  const c = document.getElementById('gl');
  let gl = null;
  try { gl = c.getContext('webgl', { antialias: false, alpha: false, depth: false, stencil: false, preserveDrawingBuffer: false, powerPreference: 'high-performance' }); } catch (e) { }
  if (!gl) return;
  const deriv = gl.getExtension('OES_standard_derivatives');
  const hp = gl.getShaderPrecisionFormat(gl.FRAGMENT_SHADER, gl.HIGH_FLOAT);
  const prec = hp && hp.precision > 0 ? 'highp' : 'mediump';
  const VS = 'attribute vec2 a;void main(){gl_Position=vec4(a,0.,1.);}';
  const FS = (deriv ? '#extension GL_OES_standard_derivatives : enable\n#define DERIV 1\n' : '') + `
precision ${prec} float;
uniform sampler2D uMap, uGrd, uDep;
uniform vec2 uRes, uCam;
uniform float uScale, uTime, uQ;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3. - 2. * f);
  return mix(mix(h21(i), h21(i + vec2(1., 0.)), u.x), mix(h21(i + vec2(0., 1.)), h21(i + vec2(1., 1.)), u.x), u.y); }
float fbm(vec2 p){ float s = 0., a = .5; for (int i = 0; i < 4; i++){ s += a * vn(p); p = p * 2.03 + 17.1; a *= .5; } return s / .9375; }
float raw(vec2 t){ return floor(texture2D(uMap, (t + .5) / 128.).r * 255. + .5); }
float grd(vec2 t){ return floor(texture2D(uGrd, (t + .5) / 128.).r * 255. + .5); }
bool sharpT(float r){ return r == 4. || r == 5. || r == 12.; }
void main(){
  vec2 pix = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y);
  vec2 w = uCam + pix / uScale;
  vec2 tp = floor(w);
  float r0 = raw(tp), g;
  if (sharpT(r0)) g = r0 == 12. ? 12. : 4.;
  else {
    vec2 j = vec2(vn(w * 1.3 + 3.1) + vn(w * 3.4 + 8.2) * .5, vn(w * 1.3 + 17.7) + vn(w * 3.4 + 29.3) * .5) / 1.5 - .5;
    vec2 tq = floor(w + j * .62);
    float rq = raw(tq);
    g = sharpT(rq) ? grd(tp) : grd(tq);
  }
  float big = fbm(w * .22);
  vec3 col; float hgt = 0.; float emis = 0.; float spec = 0.; float shin = 0.;
  float t = uTime;
  if (g == 1.) { // água
    float d = texture2D(uDep, w / 128.).r * 4.25;
    float k = clamp(d / 3., 0., 1.);
    col = mix(vec3(.25, .58, .58), vec3(.06, .2, .38), k);
    hgt = (vn(w * 3. + t * vec2(.35, .2)) + vn(w * 5.3 - t * vec2(.25, .4)) * .6) * .5;
    float ca = abs(vn(w * 4. + t * .25) - .5);
    col += (1. - k) * smoothstep(.06, 0., ca) * .12;
    float foam = smoothstep(.65, 0., d) * (.45 + .55 * vn(w * 9. + t * .6));
    col = mix(col, vec3(.9, .95, .93), foam * .65);
    spec = 1.; shin = 60.;
  } else if (g == 10.) { // lava
    vec2 fl = w + vec2(t * .05, t * .03);
    float m = fbm(fl * .9);
    float mol = smoothstep(.42, .58, m);
    float q = fbm(w * 2.4 - t * .08);
    vec3 hot = mix(vec3(.85, .22, .03), vec3(1., .82, .35), q);
    float vein = smoothstep(.05, 0., abs(vn(w * 3. + t * .1) - .5));
    hot = mix(hot, vec3(1., .96, .7), vein * (.6 + .4 * sin(t * 2. + w.x)));
    vec3 crust = vec3(.2, .08, .05) * (.7 + .5 * vn(w * 20.));
    col = mix(crust, hot, mol);
    emis = mol; hgt = (1. - mol) * vn(w * 12.) * .6;
  } else if (g == 2.) { // areia
    float rip = sin((w.y + w.x * .3 + fbm(w * 1.5) * 1.2) * 18.);
    col = vec3(.81, .72, .52) * (.92 + big * .14);
    col *= .94 + h21(floor(w * 160.)) * .1;
    hgt = rip * .08 + vn(w * 40.) * .05;
  } else if (g == 8.) { // terra / estrada
    col = vec3(.48, .37, .24) * (.82 + fbm(w * 2.5) * .35);
    hgt = fbm(w * 6.) * .25;
    vec2 cc = floor(w * 7.), o = vec2(h21(cc), h21(cc + 9.)) * .5 + .25;
    float pd = length(fract(w * 7.) - o);
    if (h21(cc + 3.) < .22 && pd < .24) { col = vec3(.56, .53, .49) * (.8 + h21(cc + 5.) * .3); hgt = sqrt(max(0., .0576 - pd * pd)) * 4.; }
    col *= .93 + h21(floor(w * 150.)) * .12;
  } else if (g == 4.) { // calçamento
    float row = floor(w.y * 3.), fy = fract(w.y * 3.);
    float cf = w.x * 2. + mod(row, 2.) * .5, fx = fract(cf), cx = floor(cf);
    float e = min(min(fx, 1. - fx) * 32., min(fy, 1. - fy) * 21.3);
    float hb = h21(vec2(cx, row));
    if (e < 1.8) { col = vec3(.26, .25, .22) + vec3(0., .06, 0.) * step(.7, vn(w * 8.)); hgt = 0.; }
    else {
      col = vec3(.6, .57, .52) + (hb - .5) * vec3(.1, .08, .05);
      col *= .9 + vn(w * 9.) * .18;
      hgt = smoothstep(1.8, 7., e) * .5 + vn(w * 25.) * .05;
    }
    col *= .94 + h21(floor(w * 170.)) * .08;
  } else if (g == 9.) { // cinzas
    col = vec3(.27, .24, .23) * (.8 + fbm(w * 2.) * .4);
    float cr = abs(vn(w * 1.3) - .5);
    hgt = fbm(w * 5.) * .3 - smoothstep(.05, 0., cr) * .3;
    float glow = smoothstep(.022, 0., cr);
    col = mix(col * (1. - smoothstep(.05, .02, cr) * .3), vec3(1., .45, .1), glow * (.75 + .25 * sin(t * 2. + w.y * 3.)));
    emis = glow;
    if (h21(floor(w * 64.)) > .9985) { col = vec3(1., .6, .2); emis = 1.; }
  } else if (g == 12.) { // ponte
    vec2 f = fract(w);
    float hz = (raw(tp + vec2(-1., 0.)) == 12. || raw(tp + vec2(1., 0.)) == 12. || raw(tp + vec2(-1., 0.)) == 8. || raw(tp + vec2(1., 0.)) == 8.) ? 1. : 0.;
    float al = mix(f.y, f.x, hz), ac = mix(f.x, f.y, hz);
    float pl = floor(al * 4.5), pf = fract(al * 4.5);
    col = vec3(.49, .34, .2) * (.8 + h21(vec2(pl, tp.x + tp.y * 7.)) * .3);
    col *= .92 + sin(ac * 40. + vn(w * 4.) * 6.) * .06;
    hgt = smoothstep(0., .08, pf) * smoothstep(1., .9, pf) * .4;
    if (pf < .07) col *= .35;
    if (ac < .07 || ac > .93) col *= .55;
  } else { // grama
    float lush = vn(w * .7);
    col = mix(vec3(.2, .4, .14), vec3(.38, .51, .21), lush * lush);
    col = mix(col, vec3(.55, .55, .28), smoothstep(.6, .75, fbm(w * .15 + 50.)) * .6);
    float sway = sin(t * 1.3 + w.x * .8 + w.y * .5) * .04;
    float blade = vn(vec2(w.x * 38. + sway * 20., w.y * 11.));
    float blade2 = vn(vec2(w.x * 70. - 5., w.y * 22.) + sway * 10.);
    hgt = blade * .45 + blade2 * .25 + fbm(w * 3.) * .2;
    col *= .72 + blade * .3 + blade2 * .15 + (vn(w * 4.) - .5) * .25;
    if (r0 == 7.) { // flores
      vec2 cc = floor(w * 5.), o = vec2(h21(cc), h21(cc + 4.)) * .6 + .2;
      float fd = length(fract(w * 5.) - o);
      float pick = h21(cc + 7.);
      vec3 fc = pick < .2 ? vec3(1., .85, .3) : pick < .4 ? vec3(1., .45, .58) : pick < .6 ? vec3(.95, .95, .95) : pick < .8 ? vec3(1., .6, .25) : vec3(.7, .55, 1.);
      if (fd < .11) { col = mix(fc, vec3(1., .92, .6), smoothstep(.04, 0., fd)); hgt = .5; }
    }
  }
  // sombra da muralha e das árvores (oclusão)
  if (raw(tp - vec2(0., 1.)) == 5. && r0 != 5.) col *= mix(.55, 1., smoothstep(0., .45, fract(w.y)));
  if (uQ > .5) {
    float ao = 0.;
    ao += raw(tp + vec2(1., 0.)) == 3. ? 1. : 0.; ao += raw(tp - vec2(1., 0.)) == 3. ? 1. : 0.;
    ao += raw(tp + vec2(0., 1.)) == 3. ? 1. : 0.; ao += raw(tp - vec2(0., 1.)) == 3. ? 1. : 0.;
    if (r0 == 3.) ao += 2.;
    col *= 1. - ao * .045;
  }
  // luz do sol a partir do relevo
  float lit = 1.;
#ifdef DERIV
  if (uQ > .5) {
    vec2 dh = vec2(dFdx(hgt), dFdy(hgt)) * uScale * .035;
    vec3 n = normalize(vec3(-dh.x, -dh.y, 1.));
    vec3 L = normalize(vec3(-.45, -.6, .66));
    lit = .62 + .5 * max(dot(n, L), 0.);
    if (spec > 0.) { vec3 hv = normalize(L + vec3(0., 0., 1.)); col += pow(max(dot(n, hv), 0.), shin) * .55; }
  }
#endif
  col *= mix(lit, 1., emis);
  col *= .93 + big * .14;
  // leve gradação de cor (quente nas luzes, fria nas sombras)
  col = mix(col, col * vec3(1.04, 1., .94), .5);
  gl_FragColor = vec4(col, 1.);
}`;
  const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { console.warn('shader:', gl.getShaderInfoLog(s)); return null; } return s; };
  const vs = sh(gl.VERTEX_SHADER, VS), fs = sh(gl.FRAGMENT_SHADER, FS);
  if (!vs || !fs) return;
  const prog = gl.createProgram(); gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) { console.warn('link:', gl.getProgramInfoLog(prog)); return; }
  gl.useProgram(prog);
  const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const la = gl.getAttribLocation(prog, 'a'); gl.enableVertexAttribArray(la); gl.vertexAttribPointer(la, 2, gl.FLOAT, false, 0, 0);
  const tex = (unit, data, linear) => {
    const t = gl.createTexture(); gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, t);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, W, H, 0, gl.LUMINANCE, gl.UNSIGNED_BYTE, data);
    const f = linear ? gl.LINEAR : gl.NEAREST;
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  };
  const dep = new Uint8Array(W * H); for (let i = 0; i < W * H; i++) dep[i] = Math.min(255, Math.round(DEPTH[i] * 60));
  tex(0, MAP, false); tex(1, GRD, false); tex(2, dep, true);
  const U = n => gl.getUniformLocation(prog, n);
  gl.uniform1i(U('uMap'), 0); gl.uniform1i(U('uGrd'), 1); gl.uniform1i(U('uDep'), 2);
  Object.assign(GLR, { ok: true, gl, c, uRes: U('uRes'), uCam: U('uCam'), uScale: U('uScale'), uTime: U('uTime'), uQ: U('uQ') });
  c.addEventListener('webglcontextlost', e => { e.preventDefault(); GLR.ok = false; });
})();
function glDraw(camX0, camY0, scale, time, hq) {
  const { gl, c } = GLR;
  if (c.width !== cv.width || c.height !== cv.height) { c.width = cv.width; c.height = cv.height; }
  gl.viewport(0, 0, c.width, c.height);
  gl.uniform2f(GLR.uRes, c.width, c.height);
  gl.uniform2f(GLR.uCam, camX0, camY0);
  gl.uniform1f(GLR.uScale, scale);
  gl.uniform1f(GLR.uTime, time % 1000);
  gl.uniform1f(GLR.uQ, hq ? 1 : 0);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}
