// =====================================================================
//  دمار: مطاردة الليل  —  لعبة سرقة ومطاردات في مدينة ثلاثية الأبعاد
//  Three.js r160 — بدون أي أدوات بناء، افتحها عبر خادم محلي
// =====================================================================
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

// ------------------------------------------------------------------ إعدادات
const N = 6;                 // عدد المربعات السكنية في كل اتجاه
const BLOCK = 50;            // حجم المربع السكني (م)
const ROAD = 16;             // عرض الشارع (م)
const CELL = BLOCK + ROAD;
const HALF = (N * CELL) / 2;
const BOUND = HALF + ROAD / 2 - 1.2;
const LANE = 3.6;            // إزاحة المسار عن منتصف الشارع
const GOAL = 250000;
const POLICE_TARGET = [2, 2, 3, 5, 7, 9];

const STORE_TYPES = {
  shop:  { name: 'سوبرماركت',     value: [700, 1600],    time: 4,  heat: 1, cd: 60,  color: 0x30d5ff, h: 7 },
  gas:   { name: 'محطة وقود',     value: [1100, 2600],   time: 5,  heat: 2, cd: 75,  color: 0xffa21f, h: 7 },
  jewel: { name: 'مجوهرات',       value: [7000, 15000],  time: 7,  heat: 3, cd: 120, color: 0xff3fd0, h: 9 },
  bank:  { name: 'البنك المركزي', value: [30000, 60000], time: 10, heat: 5, cd: 200, color: 0x45ff8a, h: 16 },
};
const STORE_LIST = ['bank', 'jewel', 'jewel', 'gas', 'gas', 'gas', 'shop', 'shop', 'shop', 'shop', 'shop', 'shop'];
const CIV_COLORS = [0x8a1c1c, 0x1d3f8a, 0xc9c9c9, 0x1e1e1e, 0xe8e8e8, 0x2a6b3a, 0x6b4a1d, 0xb8860b, 0x4b0f5a, 0x555b66, 0x0f5f6b];

// ------------------------------------------------------------------ أدوات
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(20261124);
const rr = (a, b) => a + (b - a) * rand();
const mr = (a, b) => a + (b - a) * Math.random();
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const wrapA = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };
const fmt = (n) => '$' + Math.round(n).toLocaleString('en-US');
const dist2 = (a, x, z) => Math.hypot(a.x - x, a.y - z);

// ------------------------------------------------------------------ المحرك
const canvas = document.getElementById('game');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
const MAX_ANISO = renderer.capabilities.getMaxAnisotropy();

const scene = new THREE.Scene();
const FOG_COL = new THREE.Color().setRGB(0.032, 0.028, 0.048);
scene.background = FOG_COL.clone();
scene.fog = new THREE.FogExp2(FOG_COL, 0.0062);

const camera = new THREE.PerspectiveCamera(65, innerWidth / innerHeight, 0.1, 1000);
camera.position.set(0, 80, 160);

const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

const composer = new EffectComposer(renderer);
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.75, 0.55, 0.8);
composer.addPass(bloom);
composer.addPass(new OutputPass());

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  composer.setSize(innerWidth, innerHeight);
});

// إضاءة الليل
const hemi = new THREE.HemisphereLight(0x5a6c99, 0x18130f, 0.85);
scene.add(hemi);
const moon = new THREE.DirectionalLight(0xa9bbff, 0.85);
moon.castShadow = true;
moon.shadow.mapSize.set(2048, 2048);
Object.assign(moon.shadow.camera, { left: -75, right: 75, top: 75, bottom: -75, near: 1, far: 260 });
moon.shadow.bias = -0.0004;
moon.shadow.normalBias = 0.03;
scene.add(moon, moon.target);

// السماء والنجوم والقمر
const sky = new THREE.Mesh(
  new THREE.SphereGeometry(800, 32, 16),
  new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { hor: { value: FOG_COL.clone() }, top: { value: new THREE.Color().setRGB(0.003, 0.005, 0.018) } },
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: 'uniform vec3 hor; uniform vec3 top; varying vec3 vP; void main(){ float h = clamp(vP.y,0.0,1.0); vec3 glow = vec3(0.09,0.05,0.04) * pow(1.0-h, 8.0); gl_FragColor = vec4(mix(hor, top, pow(h,0.5)) + glow, 1.0); }',
  }),
);
sky.renderOrder = -10;
scene.add(sky);
{
  const pos = [];
  for (let i = 0; i < 900; i++) {
    const th = rand() * Math.PI * 2, ph = Math.acos(rr(0.15, 1));
    pos.push(Math.sin(ph) * Math.cos(th) * 750, Math.cos(ph) * 750, Math.sin(ph) * Math.sin(th) * 750);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  const stars = new THREE.Points(g, new THREE.PointsMaterial({ color: 0xffffff, size: 1.6, sizeAttenuation: false, fog: false, transparent: true, opacity: 0.8 }));
  sky.add(stars);
  const moonDisc = new THREE.Mesh(new THREE.SphereGeometry(18, 24, 12), new THREE.MeshBasicMaterial({ color: new THREE.Color(2.2, 2.2, 2.0), fog: false }));
  moonDisc.position.set(380, 420, 240);
  sky.add(moonDisc);
}

// ------------------------------------------------------------------ قوام مولّدة
function canvasTex(c, srgb = true) {
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = MAX_ANISO;
  return t;
}
function noiseCanvas(size, base, amp, seed, tint = [1, 1, 1.03]) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  const g = c.getContext('2d'); const img = g.createImageData(size, size); const r = mulberry32(seed);
  for (let i = 0; i < size * size; i++) {
    const v = base + (r() - 0.5) * amp + (r() < 0.004 ? -25 : 0);
    img.data[i * 4] = v * tint[0]; img.data[i * 4 + 1] = v * tint[1]; img.data[i * 4 + 2] = v * tint[2]; img.data[i * 4 + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  return c;
}
function facadeTex(wall, litCols, litP, seed) {
  const S = 512, C = 8, cs = S / C, r = mulberry32(seed);
  const cm = document.createElement('canvas'); cm.width = cm.height = S;
  const ce = document.createElement('canvas'); ce.width = ce.height = S;
  const m = cm.getContext('2d'), e = ce.getContext('2d');
  m.fillStyle = wall; m.fillRect(0, 0, S, S);
  for (let i = 0; i < 2500; i++) { m.fillStyle = `rgba(0,0,0,${r() * 0.08})`; m.fillRect(r() * S, r() * S, 2, 2); }
  e.fillStyle = '#000'; e.fillRect(0, 0, S, S);
  for (let row = 0; row < C; row++) {
    m.fillStyle = 'rgba(0,0,0,0.25)'; m.fillRect(0, row * cs, S, 4);
    for (let col = 0; col < C; col++) {
      const x = col * cs + 11, y = row * cs + 13, w = cs - 22, h = cs - 24;
      m.fillStyle = '#1a1d24'; m.fillRect(x - 2, y - 2, w + 4, h + 4);
      if (r() < litP) {
        const col0 = litCols[Math.floor(r() * litCols.length)];
        m.fillStyle = col0; m.fillRect(x, y, w, h);
        e.globalAlpha = 0.45 + r() * 0.55; e.fillStyle = col0; e.fillRect(x, y, w, h);
        if (r() < 0.5) { const cw = w * rr(0.2, 0.5); m.fillStyle = 'rgba(40,25,20,0.85)'; m.fillRect(x, y, cw, h); e.globalAlpha = 1; e.fillStyle = '#000'; e.fillRect(x, y, cw, h); }
      } else {
        const gr = m.createLinearGradient(x, y, x + w, y + h);
        gr.addColorStop(0, '#16202e'); gr.addColorStop(1, '#07090e');
        m.fillStyle = gr; m.fillRect(x, y, w, h);
      }
      e.globalAlpha = 1;
    }
  }
  return { map: canvasTex(cm), emissiveMap: canvasTex(ce) };
}
function radialTex(inner, outer) {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const g = c.getContext('2d'); const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  gr.addColorStop(0, inner); gr.addColorStop(1, outer);
  g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
function signTex(text, color) {
  const hex = '#' + color.toString(16).padStart(6, '0');
  const c = document.createElement('canvas'); c.width = 1024; c.height = 224;
  const g = c.getContext('2d');
  g.fillStyle = '#07080c'; g.fillRect(0, 0, 1024, 224);
  g.strokeStyle = hex; g.lineWidth = 10; g.strokeRect(14, 14, 996, 196);
  g.font = '900 118px Cairo, Tahoma, Arial'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.direction = 'rtl';
  g.shadowColor = hex; g.shadowBlur = 34; g.fillStyle = hex; g.fillText(text, 512, 120);
  g.shadowBlur = 0; g.globalAlpha = 0.8; g.fillStyle = '#fff'; g.fillText(text, 512, 120);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = MAX_ANISO; return t;
}

// انتظر الخط العربي لكتابة اللافتات
try { await Promise.race([document.fonts.load('900 64px Cairo'), new Promise((r) => setTimeout(r, 1500))]); } catch (e) { /* يكفي الخط الاحتياطي */ }

// ------------------------------------------------------------------ مواد
const std = (p) => new THREE.MeshStandardMaterial({ envMapIntensity: 0.15, ...p });
const asphaltTex = canvasTex(noiseCanvas(256, 40, 22, 7));
asphaltTex.repeat.set(160, 160);
const concreteTex = canvasTex(noiseCanvas(256, 92, 26, 9));
concreteTex.repeat.set(6, 6);
const M = {
  ground: std({ map: asphaltTex, roughness: 0.62, metalness: 0.05 }),
  sidewalk: std({ map: concreteTex, color: 0x8c8c94, roughness: 0.9 }),
  grass: std({ color: 0x1f3a1f, roughness: 1 }),
  parapet: std({ color: 0x1c1e23, roughness: 0.9 }),
  roofUnit: std({ color: 0x55585e, roughness: 0.6, metalness: 0.4 }),
  line: new THREE.MeshBasicMaterial({ color: new THREE.Color(0.55, 0.5, 0.3) }),
  cross: new THREE.MeshBasicMaterial({ color: new THREE.Color(0.42, 0.42, 0.45) }),
  pole: std({ color: 0x2c2f35, roughness: 0.5, metalness: 0.7 }),
  bulb: new THREE.MeshBasicMaterial({ color: new THREE.Color(3.2, 2.4, 1.4) }),
  pool: new THREE.MeshBasicMaterial({ map: radialTex('rgba(255,190,110,0.55)', 'rgba(255,170,90,0)'), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }),
  trunk: std({ color: 0x3b2a1c, roughness: 1 }),
  leaves: std({ color: 0x1c3d22, roughness: 0.95 }),
  glass: std({ color: 0x0b1118, roughness: 0.08, metalness: 0.9, envMapIntensity: 0.9 }),
  rubber: std({ color: 0x111111, roughness: 0.9 }),
  rim: std({ color: 0x9aa0a8, roughness: 0.3, metalness: 0.9, envMapIntensity: 0.6 }),
  head: new THREE.MeshBasicMaterial({ color: new THREE.Color(4, 4, 3.6) }),
  bumper: std({ color: 0x15161a, roughness: 0.6 }),
  redLight: new THREE.MeshBasicMaterial({ color: new THREE.Color(5, 0.2, 0.2) }),
};
const facadeMats = [
  ['#2c2e34', ['#ffd89a', '#ffe9c0', '#bfe0ff'], 0.36, 11],
  ['#3d3530', ['#ffcf88', '#ffe2a8'], 0.3, 12],
  ['#26323d', ['#cfe8ff', '#ffffff', '#9fd0ff'], 0.42, 13],
  ['#4a4640', ['#ffd89a', '#ffc070'], 0.28, 14],
].map(([wall, lit, p, s]) => {
  const t = facadeTex(wall, lit, p, s);
  return std({ map: t.map, emissiveMap: t.emissiveMap, emissive: 0xffffff, emissiveIntensity: 1.15, roughness: 0.75, metalness: 0.1, envMapIntensity: 0.35 });
});
const paintCache = new Map();
function paint(color) {
  if (!paintCache.has(color)) paintCache.set(color, std({ color, roughness: 0.32, metalness: 0.55, envMapIntensity: 0.9 }));
  return paintCache.get(color);
}

// ------------------------------------------------------------------ بناء المدينة
const colliders = [];   // {minX,maxX,minZ,maxZ,h}
const blocks = [];      // للخريطة المصغّرة
const lots = [];
const nodePos = (i, j) => ({ x: i * CELL - HALF, z: j * CELL - HALF });
const nearestNode = (x, z) => ({ i: clamp(Math.round((x + HALF) / CELL), 0, N), j: clamp(Math.round((z + HALF) / CELL), 0, N) });
function neighbors(n) {
  const out = [];
  if (n.i > 0) out.push({ i: n.i - 1, j: n.j });
  if (n.i < N) out.push({ i: n.i + 1, j: n.j });
  if (n.j > 0) out.push({ i: n.i, j: n.j - 1 });
  if (n.j < N) out.push({ i: n.i, j: n.j + 1 });
  return out;
}
function lanePoint(p, t) {
  const c = nodePos(t.i, t.j);
  if (!p) return c;
  const dx = t.i - p.i, dz = t.j - p.j;
  return { x: c.x - dz * LANE, z: c.z + dx * LANE };
}
function addCollider(cx, cz, w, d, h) {
  colliders.push({ minX: cx - w / 2, maxX: cx + w / 2, minZ: cz - d / 2, maxZ: cz + d / 2, h });
}
function scaleUV(g, w, h, d, offU) {
  const uv = g.attributes.uv; const dims = [[d, h], [d, h], null, null, [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) {
    const i = f * 4 + k;
    if (!dims[f]) { uv.setXY(i, 0.004, 0.004); continue; }
    uv.setXY(i, uv.getX(i) * dims[f][0] / 24 + offU, uv.getY(i) * dims[f][1] / 28);
  }
}
const roofUnitGeo = new THREE.BoxGeometry(2.4, 1.4, 2);
function addBuilding(cx, cz, w, d, h, mat, collide = true) {
  const g = new THREE.BoxGeometry(w, h, d); scaleUV(g, w, h, d, Math.floor(rand() * 8) / 8);
  const m = new THREE.Mesh(g, mat); m.position.set(cx, h / 2, cz);
  m.castShadow = true; m.receiveShadow = true; scene.add(m);
  const p = new THREE.Mesh(new THREE.BoxGeometry(w + 0.3, 0.7, d + 0.3), M.parapet);
  p.position.set(cx, h + 0.2, cz); scene.add(p);
  if (rand() < 0.6) { const u = new THREE.Mesh(roofUnitGeo, M.roofUnit); u.position.set(cx + rr(-w / 4, w / 4), h + 0.7, cz + rr(-d / 4, d / 4)); scene.add(u); }
  if (h > 42) { const l = new THREE.Mesh(new THREE.SphereGeometry(0.35, 8, 6), M.redLight); l.position.set(cx, h + 1.2, cz); scene.add(l); blinkers.push(l); }
  if (collide) addCollider(cx, cz, w, d, h);
  return m;
}
const blinkers = [];

// الأرض
{
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(1400, 1400), M.ground);
  ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; scene.add(ground);
}

const sidewalkMatrices = [];
const treeSpots = [];
for (let bi = -1; bi <= N; bi++) for (let bj = -1; bj <= N; bj++) {
  const cx = (bi + 0.5) * CELL - HALF, cz = (bj + 0.5) * CELL - HALF;
  const inner = bi >= 0 && bi < N && bj >= 0 && bj < N;
  sidewalkMatrices.push(new THREE.Matrix4().makeTranslation(cx, 0.075, cz));
  const park = inner && !(bi === 0 && bj === 0) && rand() < 0.08;
  blocks.push({ cx, cz, park });
  if (park) {
    const g = new THREE.Mesh(new THREE.BoxGeometry(BLOCK - 6, 0.08, BLOCK - 6), M.grass);
    g.position.set(cx, 0.18, cz); g.receiveShadow = true; scene.add(g);
    for (let t = 0; t < 14; t++) treeSpots.push([cx + rr(-19, 19), cz + rr(-19, 19), rr(0.8, 1.3)]);
    continue;
  }
  const dc = Math.hypot(cx, cz) / HALF;
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const lx = cx + sx * 12, lz = cz + sz * 12;
    if (inner) lots.push({ lx, lz, sx, sz, cx, cz, bi, bj });
    else addBuilding(lx, lz, rr(17, 20), rr(17, 20), rr(14, 40), facadeMats[Math.floor(rand() * 4)], false);
  }
}
{
  const sw = new THREE.InstancedMesh(new THREE.BoxGeometry(BLOCK, 0.15, BLOCK), M.sidewalk, sidewalkMatrices.length);
  sidewalkMatrices.forEach((m, i) => sw.setMatrixAt(i, m));
  sw.receiveShadow = true; scene.add(sw);
}

// المخبأ + المتاجر
const lotKey = (l) => `${l.bi},${l.bj},${l.sx},${l.sz}`;
const used = new Set();
const safeLot = lots.find((l) => l.bi === 0 && l.bj === 0 && l.sx === -1 && l.sz === 1);
used.add(lotKey(safeLot));
const stores = [];
{
  const shuffled = lots.filter((l) => !used.has(lotKey(l))).map((l) => [rand(), l]).sort((a, b) => a[0] - b[0]).map((x) => x[1]);
  const usedBlocks = new Set([`${safeLot.bi},${safeLot.bj}`]);
  for (const type of STORE_LIST) {
    let pool = shuffled.filter((l) => !used.has(lotKey(l)) && !usedBlocks.has(`${l.bi},${l.bj}`));
    if (type === 'bank') pool = pool.sort((a, b) => Math.hypot(a.lx, a.lz) - Math.hypot(b.lx, b.lz));
    const l = pool[0]; if (!l) break;
    used.add(lotKey(l)); usedBlocks.add(`${l.bi},${l.bj}`);
    stores.push(makeStore(type, l));
  }
}
const safe = makeSafehouse(safeLot);

// باقي المباني
for (const l of lots) {
  if (used.has(lotKey(l))) continue;
  const dc = Math.hypot(l.lx, l.lz) / HALF;
  const h = rr(9, 22) + Math.max(0, 1 - dc) * rr(0, 55);
  const w = rr(16, 19.5), d = rr(16, 19.5);
  const mat = facadeMats[Math.floor(rand() * 4)];
  addBuilding(l.lx, l.lz, w, d, h, mat);
  if (h > 30 && rand() < 0.6) {
    const h2 = rr(5, 14), w2 = w * rr(0.55, 0.75), d2 = d * rr(0.55, 0.75);
    const g = new THREE.BoxGeometry(w2, h2, d2); scaleUV(g, w2, h2, d2, 0.25);
    const m = new THREE.Mesh(g, mat); m.position.set(l.lx, h + 0.55 + h2 / 2, l.lz); m.castShadow = true; scene.add(m);
  }
}

function makeStore(type, l) {
  const def = STORE_TYPES[type];
  const w = 19, h = def.h;
  const bodyMat = std({ color: type === 'bank' ? 0xd8d2c4 : 0x3a3d44, roughness: 0.7 });
  const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, w), bodyMat);
  b.position.set(l.lx, h / 2, l.lz); b.castShadow = b.receiveShadow = true; scene.add(b);
  addCollider(l.lx, l.lz, w, w, h);
  const face = l.lx + l.sx * (w / 2);
  const rotY = l.sx > 0 ? Math.PI / 2 : -Math.PI / 2;
  const col = new THREE.Color(def.color);
  const glassMat = new THREE.MeshBasicMaterial({ color: col.clone().multiplyScalar(0.55) });
  const glass = new THREE.Mesh(new THREE.PlaneGeometry(12, 3), glassMat);
  glass.position.set(face + l.sx * 0.03, 1.7, l.lz); glass.rotation.y = rotY; scene.add(glass);
  const signMat = new THREE.MeshBasicMaterial({ map: signTex(def.name, def.color), color: new THREE.Color(1.7, 1.7, 1.7) });
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(10, 2.2), signMat);
  sign.position.set(face + l.sx * 0.06, Math.min(h - 1.4, 5.2), l.lz); sign.rotation.y = rotY; scene.add(sign);
  const canopy = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.15, 13), std({ color: def.color, roughness: 0.5, emissive: def.color, emissiveIntensity: 0.25 }));
  canopy.position.set(face + l.sx * 0.8, 3.6, l.lz); scene.add(canopy);
  if (type === 'bank') {
    for (let k = -2; k <= 2; k++) {
      const c = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.5, 8, 14), bodyMat);
      c.position.set(face + l.sx * 1.4, 4, l.lz + k * 3.4); c.castShadow = true; scene.add(c);
    }
  }
  const zone = { x: l.lx + l.sx * 13.6, z: l.lz };
  const ringMat = new THREE.MeshBasicMaterial({ color: col.clone().multiplyScalar(2), transparent: true, opacity: 0.85, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
  const ring = new THREE.Mesh(new THREE.RingGeometry(1.7, 2.2, 40), ringMat);
  ring.rotation.x = -Math.PI / 2; ring.position.set(zone.x, 0.2, zone.z); scene.add(ring);
  const beacon = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 0.7, 70, 12, 1, true),
    new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.14, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  beacon.position.set(zone.x, 35, zone.z); scene.add(beacon);
  return { type, def, ...zone, sx: l.sx, cooldown: 0, signMat, glassMat, ring, beacon, col };
}

function makeSafehouse(l) {
  const w = 19, h = 6;
  const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, w), std({ color: 0x2b2a27, roughness: 0.9 }));
  b.position.set(l.lx, h / 2, l.lz); b.castShadow = b.receiveShadow = true; scene.add(b);
  addCollider(l.lx, l.lz, w, w, h);
  const face = l.lx + l.sx * (w / 2), rotY = l.sx > 0 ? Math.PI / 2 : -Math.PI / 2;
  const door = new THREE.Mesh(new THREE.PlaneGeometry(8, 4), std({ color: 0x6d7076, roughness: 0.5, metalness: 0.6 }));
  door.position.set(face + l.sx * 0.03, 2, l.lz); door.rotation.y = rotY; scene.add(door);
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(7, 1.6), new THREE.MeshBasicMaterial({ map: signTex('المخبأ', 0x3dff7a), color: new THREE.Color(1.7, 1.7, 1.7) }));
  sign.position.set(face + l.sx * 0.06, 4.9, l.lz); sign.rotation.y = rotY; scene.add(sign);
  const zone = { x: l.lx + l.sx * 13.6, z: l.lz };
  const ring = new THREE.Mesh(new THREE.RingGeometry(2.2, 2.8, 40), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.4, 2.4, 0.8), transparent: true, opacity: 0.85, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
  ring.rotation.x = -Math.PI / 2; ring.position.set(zone.x, 0.2, zone.z); scene.add(ring);
  const beacon = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 0.9, 70, 12, 1, true),
    new THREE.MeshBasicMaterial({ color: 0x3dff7a, transparent: true, opacity: 0.12, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  beacon.position.set(zone.x, 35, zone.z); scene.add(beacon);
  return { ...zone, sx: l.sx, ring };
}

// علامات الطرق وممرات المشاة
{
  const dash = [], cross = [];
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(1, 1, 1), p = new THREE.Vector3();
  const flat = new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, 0));
  const flatRot = new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, Math.PI / 2));
  for (let k = 0; k <= N; k++) {
    const c = k * CELL - HALF;
    for (let t = -HALF; t <= HALF; t += 7) {
      const nearNode = Math.abs(((t + HALF) % CELL + CELL) % CELL) < ROAD / 2 + 3 || Math.abs(((t + HALF) % CELL + CELL) % CELL - CELL) < ROAD / 2 + 3;
      if (nearNode) continue;
      dash.push(m4.clone().compose(p.set(t, 0.02, c), flatRot, s));
      dash.push(m4.clone().compose(p.set(c, 0.02, t), flat, s));
    }
  }
  for (let i = 0; i <= N; i++) for (let j = 0; j <= N; j++) {
    const n = nodePos(i, j);
    for (const nb of neighbors({ i, j })) {
      const dx = nb.i - i, dz = nb.j - j;
      for (let w = -6; w <= 6; w += 1.3) {
        const x = n.x + dx * (ROAD / 2 + 2) + (dz !== 0 ? w : 0);
        const z = n.z + dz * (ROAD / 2 + 2) + (dx !== 0 ? w : 0);
        cross.push(m4.clone().compose(p.set(x, 0.02, z), dx !== 0 ? flatRot : flat, s));
      }
    }
  }
  const dm = new THREE.InstancedMesh(new THREE.PlaneGeometry(0.22, 3), M.line, dash.length);
  dash.forEach((m, i) => dm.setMatrixAt(i, m)); scene.add(dm);
  const cm = new THREE.InstancedMesh(new THREE.PlaneGeometry(0.6, 3), M.cross, cross.length);
  cross.forEach((m, i) => cm.setMatrixAt(i, m)); scene.add(cm);
}

// أعمدة الإنارة
{
  const spots = [];
  for (const b of blocks) for (const sx of [-1, 1]) for (const sz of [-1, 1]) spots.push([b.cx + sx * 23.6, b.cz + sz * 23.6, sx, sz]);
  const n = spots.length;
  const poles = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.09, 0.13, 7, 8), M.pole, n);
  const bulbs = new THREE.InstancedMesh(new THREE.BoxGeometry(0.7, 0.18, 0.4), M.bulb, n);
  const pools = new THREE.InstancedMesh(new THREE.PlaneGeometry(16, 16), M.pool, n);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), one = new THREE.Vector3(1, 1, 1), p = new THREE.Vector3();
  const flat = new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, 0));
  spots.forEach(([x, z, sx, sz], i) => {
    poles.setMatrixAt(i, m4.makeTranslation(x, 3.5, z));
    bulbs.setMatrixAt(i, m4.makeTranslation(x + sx * 0.9, 6.95, z + sz * 0.9));
    pools.setMatrixAt(i, m4.compose(p.set(x + sx * 3, 0.17, z + sz * 3), flat, one));
    addCollider(x, z, 0.35, 0.35, 1);
  });
  poles.castShadow = true;
  scene.add(poles, bulbs, pools);
}

// الأشجار في الحدائق
if (treeSpots.length) {
  const trunks = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.18, 0.28, 3, 7), M.trunk, treeSpots.length);
  const crowns = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(2.1, 1), M.leaves, treeSpots.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), s = new THREE.Vector3();
  treeSpots.forEach(([x, z, k], i) => {
    trunks.setMatrixAt(i, m4.compose(p.set(x, 1.5 * k, z), q.identity(), s.set(k, k, k)));
    crowns.setMatrixAt(i, m4.compose(p.set(x, 3.9 * k, z), q.setFromEuler(new THREE.Euler(rand(), rand(), 0)), s.set(k, k * 1.2, k)));
    addCollider(x, z, 0.5, 0.5, 1);
  });
  trunks.castShadow = crowns.castShadow = true;
  scene.add(trunks, crowns);
}

// ------------------------------------------------------------------ تصادمات
function collideCircle(p, r, vel, ox = 0, oz = 0) {
  let impact = 0;
  for (const c of colliders) {
    const cx = p.x + ox, cz = p.y + oz;
    if (cx < c.minX - r || cx > c.maxX + r || cz < c.minZ - r || cz > c.maxZ + r) continue;
    const qx = clamp(cx, c.minX, c.maxX), qz = clamp(cz, c.minZ, c.maxZ);
    let nx = cx - qx, nz = cz - qz; const d = Math.hypot(nx, nz);
    if (d >= r) continue;
    let push;
    if (d < 1e-5) {
      const l = cx - c.minX, rt = c.maxX - cx, t = cz - c.minZ, b = c.maxZ - cz, m = Math.min(l, rt, t, b);
      if (m === l) { nx = -1; nz = 0; push = l + r; } else if (m === rt) { nx = 1; nz = 0; push = rt + r; }
      else if (m === t) { nx = 0; nz = -1; push = t + r; } else { nx = 0; nz = 1; push = b + r; }
    } else { nx /= d; nz /= d; push = r - d; }
    p.x += nx * push; p.y += nz * push;
    if (vel) {
      const vn = vel.x * nx + vel.y * nz;
      if (vn < 0) { vel.x -= nx * vn * 1.25; vel.y -= nz * vn * 1.25; vel.multiplyScalar(0.97); impact = Math.max(impact, -vn); }
    }
  }
  if (Math.abs(p.x) > BOUND) { p.x = Math.sign(p.x) * BOUND; if (vel) vel.x *= -0.3; }
  if (Math.abs(p.y) > BOUND) { p.y = Math.sign(p.y) * BOUND; if (vel) vel.y *= -0.3; }
  return impact;
}
// تقاطع قطعة مستقيمة مع المباني — يعيد أول نسبة تصادم (1 = لا شيء)
function segHit(ax, az, bx, bz, minH = 2, pad = 0) {
  const dx = bx - ax, dz = bz - az; let best = 1;
  for (const c of colliders) {
    if (c.h < minH) continue;
    let t0 = 0, t1 = best;
    if (Math.abs(dx) < 1e-6) { if (ax < c.minX - pad || ax > c.maxX + pad) continue; }
    else { let ta = (c.minX - pad - ax) / dx, tb = (c.maxX + pad - ax) / dx; if (ta > tb) [ta, tb] = [tb, ta]; t0 = Math.max(t0, ta); t1 = Math.min(t1, tb); if (t0 > t1) continue; }
    if (Math.abs(dz) < 1e-6) { if (az < c.minZ - pad || az > c.maxZ + pad) continue; }
    else { let ta = (c.minZ - pad - az) / dz, tb = (c.maxZ + pad - az) / dz; if (ta > tb) [ta, tb] = [tb, ta]; t0 = Math.max(t0, ta); t1 = Math.min(t1, tb); if (t0 > t1) continue; }
    if (t0 < best) best = t0;
  }
  return best;
}

// ------------------------------------------------------------------ الشخصيات
const HUMAN_GEO = {
  torso: new THREE.BoxGeometry(0.48, 0.62, 0.27), hips: new THREE.BoxGeometry(0.44, 0.2, 0.25),
  head: new THREE.SphereGeometry(0.14, 14, 10), leg: new THREE.BoxGeometry(0.17, 0.9, 0.19).translate(0, -0.45, 0),
  arm: new THREE.BoxGeometry(0.13, 0.62, 0.13).translate(0, -0.31, 0), cap: new THREE.CylinderGeometry(0.16, 0.16, 0.08, 14),
  bag: new THREE.BoxGeometry(0.42, 0.46, 0.22),
};
function makeHuman(o) {
  const g = new THREE.Group();
  const add = (geo, mat, x, y, z, parent = g) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.castShadow = true; parent.add(m); return m; };
  const top = std({ color: o.top, roughness: 0.9 }), legs = std({ color: o.legs, roughness: 0.9 }), head = std({ color: o.head, roughness: 0.8 });
  add(HUMAN_GEO.torso, top, 0, 1.32, 0);
  add(HUMAN_GEO.hips, legs, 0, 0.98, 0);
  add(HUMAN_GEO.head, head, 0, 1.79, 0);
  if (o.cap) { add(HUMAN_GEO.cap, std({ color: 0x0f1a33 }), 0, 1.92, 0); }
  const pivot = (x, y) => { const p = new THREE.Group(); p.position.set(x, y, 0); g.add(p); return p; };
  const legL = pivot(-0.12, 0.95), legR = pivot(0.12, 0.95), armL = pivot(-0.31, 1.6), armR = pivot(0.31, 1.6);
  add(HUMAN_GEO.leg, legs, 0, 0, 0, legL); add(HUMAN_GEO.leg, legs, 0, 0, 0, legR);
  add(HUMAN_GEO.arm, top, 0, 0, 0, armL); add(HUMAN_GEO.arm, top, 0, 0, 0, armR);
  let bag = null;
  if (o.bag) { bag = add(HUMAN_GEO.bag, std({ color: 0x3e4a2a, roughness: 1 }), 0, 1.3, -0.25); bag.visible = false; }
  return { g, legL, legR, armL, armR, bag, phase: 0 };
}
function animHuman(H, speed, dt, rob = false) {
  H.phase += dt * speed * 1.9;
  const amp = Math.min(speed / 4.5, 1.25) * 0.75, s = Math.sin(H.phase) * amp;
  H.legL.rotation.x = s; H.legR.rotation.x = -s;
  if (rob) { H.armL.rotation.x = H.armR.rotation.x = -1.45; }
  else { H.armL.rotation.x = -s * 0.9; H.armR.rotation.x = s * 0.9; }
  H.g.position.y = Math.abs(Math.cos(H.phase)) * 0.05 * amp;
}

// ------------------------------------------------------------------ السيارات
const CAR_GEO = {
  body: new THREE.BoxGeometry(1.9, 0.55, 4.4), cabin: new THREE.BoxGeometry(1.64, 0.55, 2.15), roof: new THREE.BoxGeometry(1.6, 0.06, 1.75),
  bumper: new THREE.BoxGeometry(1.94, 0.22, 0.2), wheel: new THREE.CylinderGeometry(0.37, 0.37, 0.28, 18).rotateZ(Math.PI / 2),
  hub: new THREE.CylinderGeometry(0.22, 0.22, 0.3, 10).rotateZ(Math.PI / 2), light: new THREE.BoxGeometry(0.44, 0.15, 0.06), bar: new THREE.BoxGeometry(0.6, 0.15, 0.32),
};
function makeCarMesh(color, police) {
  const g = new THREE.Group();
  const add = (geo, mat, x, y, z, parent = g) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); parent.add(m); return m; };
  const body = add(CAR_GEO.body, paint(police ? 0xf0f0f0 : color), 0, 0.62, 0); body.castShadow = true;
  if (police) { const d = add(new THREE.BoxGeometry(1.93, 0.3, 1.9), paint(0x111318), 0, 0.6, -0.1); }
  add(CAR_GEO.cabin, M.glass, 0, 1.17, -0.25).castShadow = true;
  add(CAR_GEO.roof, paint(police ? 0x111318 : color), 0, 1.47, -0.25);
  add(CAR_GEO.bumper, M.bumper, 0, 0.42, 2.22); add(CAR_GEO.bumper, M.bumper, 0, 0.42, -2.22);
  const wheels = [], fronts = [];
  for (const [x, z] of [[-0.93, 1.38], [0.93, 1.38], [-0.93, -1.38], [0.93, -1.38]]) {
    const piv = new THREE.Group(); piv.position.set(x, 0.37, z); g.add(piv);
    const w = add(CAR_GEO.wheel, M.rubber, 0, 0, 0, piv); add(CAR_GEO.hub, M.rim, 0, 0, 0, w);
    wheels.push(w); if (z > 0) fronts.push(piv);
  }
  add(CAR_GEO.light, M.head, -0.62, 0.68, 2.21); add(CAR_GEO.light, M.head, 0.62, 0.68, 2.21);
  const tailMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.2, 0.05, 0.05) });
  add(CAR_GEO.light, tailMat, -0.62, 0.7, -2.21); add(CAR_GEO.light, tailMat, 0.62, 0.7, -2.21);
  let barR = null, barB = null;
  if (police) {
    barR = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.4, 0, 0) });
    barB = new THREE.MeshBasicMaterial({ color: new THREE.Color(0, 0, 0.4) });
    add(CAR_GEO.bar, barR, -0.33, 1.58, -0.25); add(CAR_GEO.bar, barB, 0.33, 1.58, -0.25);
  }
  g.rotation.order = 'YXZ';
  return { mesh: g, wheels, fronts, tailMat, barR, barB };
}

class Car {
  constructor(x, z, h, o = {}) {
    this.pos = new THREE.Vector2(x, z); this.vel = new THREE.Vector2(); this.h = h;
    this.speed = 0; this.lat = 0; this.steerS = 0;
    this.police = !!o.police; this.ai = o.ai || 'parked';
    this.accel = o.accel || mr(8, 11); this.max = o.max || mr(30, 37);
    Object.assign(this, makeCarMesh(o.color ?? CIV_COLORS[Math.floor(Math.random() * CIV_COLORS.length)], this.police));
    scene.add(this.mesh);
    this.input = { throttle: 0, steer: 0, brake: false, hand: false };
    this.stuckT = 0; this.reverseT = 0; this.prevN = null; this.tgtN = null;
    this.chase = false; this.officer = null; this.exitCd = 0; this.ignoreT = 0; this.blockedT = 0;
    this.sync(0);
  }
  physics(dt) {
    const inp = this.input;
    let fx = Math.sin(this.h), fz = Math.cos(this.h);
    let fwd = this.vel.x * fx + this.vel.y * fz;
    let lat = this.vel.x * -fz + this.vel.y * fx;
    const t = inp.throttle;
    if (t > 0) fwd += (fwd < -0.5 ? 18 : this.accel * (1 - Math.max(0, fwd) / this.max * 0.55)) * t * dt;
    else if (t < 0) fwd -= (fwd > 0.5 ? 18 : this.accel * 0.6) * -t * dt;
    else fwd *= Math.exp(-0.45 * dt);
    if (inp.brake) fwd *= Math.exp(-3 * dt);
    if (inp.hand) fwd *= Math.exp(-0.9 * dt);
    fwd = clamp(fwd, -this.max * 0.35, this.max);
    lat *= Math.exp(-(inp.hand ? 1.3 : 9) * dt);
    this.steerS += (inp.steer - this.steerS) * Math.min(1, dt * 7);
    const turn = this.steerS * 1.9 * clamp(fwd / 4, -1, 1) / (1 + Math.abs(fwd) * 0.025) * (inp.hand ? 1.5 : 1);
    this.h += turn * dt;
    fx = Math.sin(this.h); fz = Math.cos(this.h);
    this.vel.set(fx * fwd - fz * lat, fz * fwd + fx * lat);
    this.pos.x += this.vel.x * dt; this.pos.y += this.vel.y * dt;
    this.speed = fwd; this.lat = lat;
  }
  collideWorld() {
    const fx = Math.sin(this.h) * 1.25, fz = Math.cos(this.h) * 1.25;
    return Math.max(collideCircle(this.pos, 1.05, this.vel, fx, fz), collideCircle(this.pos, 1.05, this.vel, -fx, -fz));
  }
  sync(dt) {
    this.mesh.position.set(this.pos.x, 0, this.pos.y);
    this.mesh.rotation.set(0, this.h, clamp(-this.lat * 0.012, -0.08, 0.08));
    for (const w of this.wheels) w.rotation.x += this.speed * dt / 0.37;
    for (const f of this.fronts) f.rotation.y = this.steerS * 0.45;
    const braking = (this.input.throttle < 0 && this.speed > 0.5) || this.input.brake || this.input.hand;
    this.tailMat.color.setRGB(braking ? 6 : 1.2, braking ? 0.25 : 0.05, braking ? 0.25 : 0.05);
    if (this.police) {
      const on = this.chase, ph = (time * 2.2 + this.pos.x * 0.01) % 1 < 0.5;
      this.barR.color.setRGB(on && ph ? 9 : 0.4, 0, 0);
      this.barB.color.setRGB(0, on && !ph ? 1.5 : 0, on && !ph ? 10 : 0.4);
    }
  }
  remove() { scene.remove(this.mesh); }
}

// ------------------------------------------------------------------ حالة اللعبة
let time = 0, state = 'menu';
const cars = [], officers = [];
const W = { level: 0, lastSeen: 0, crimeCd: 0 };
let spawnT = 0, arrest = 0, shake = 0, robbing = null, robProg = 0, wonShown = false;
let cash = 0, bank = 0;
try { bank = JSON.parse(localStorage.getItem('damar_save') || '{}').bank || 0; } catch (e) { bank = 0; }
if (bank >= GOAL) wonShown = true;
const save = () => { try { localStorage.setItem('damar_save', JSON.stringify({ bank })); } catch (e) { /* بلا حفظ */ } };

const player = {
  pos: new THREE.Vector2(safe.x, safe.z), vel: new THREE.Vector2(), facing: 0, stamina: 1, car: null,
  H: makeHuman({ top: 0x2a2b30, legs: 0x1e2a3d, head: 0x0d0d0d, bag: true }),
};
player.H.g.visible = false;
scene.add(player.H.g);
const COP = { top: 0x1b2f5c, legs: 0x141c2e, head: 0xc79a77, cap: true };

const cam = { yaw: 0, pitch: 0.3, lastMouse: -10, orbit: 0 };

// المصابيح الأمامية لسيارة اللاعب وأضواء الشرطة (مُعدّة مسبقاً لتجنب إعادة تجميع الظلال)
const headlight = new THREE.SpotLight(0xfff1d6, 0, 70, 0.5, 0.55, 1.4);
const headTarget = new THREE.Object3D();
scene.add(headlight, headTarget); headlight.target = headTarget;
const copLights = [];
for (let i = 0; i < 4; i++) { const l = new THREE.PointLight(0xff0000, 0, 32, 1.5); scene.add(l); copLights.push(l); }

// ------------------------------------------------------------------ إنشاء المركبات
function randomSegment() {
  const a = { i: Math.floor(Math.random() * (N + 1)), j: Math.floor(Math.random() * (N + 1)) };
  const nb = neighbors(a); const b = nb[Math.floor(Math.random() * nb.length)];
  return [a, b];
}
function spaceFree(x, z, r) { return cars.every((c) => dist2(c.pos, x, z) > r) && Math.hypot(x - safe.x, z - safe.z) > 6; }
function spawnTraffic(ai) {
  for (let tries = 0; tries < 30; tries++) {
    const [a, b] = randomSegment(); const pa = nodePos(a.i, a.j), pb = nodePos(b.i, b.j);
    const dx = b.i - a.i, dz = b.j - a.j, f = mr(0.3, 0.7);
    const off = ai === 'parked' ? 6.5 : LANE;
    const x = pa.x + (pb.x - pa.x) * f - dz * off, z = pa.z + (pb.z - pa.z) * f + dx * off;
    if (!spaceFree(x, z, 9)) continue;
    const c = new Car(x, z, Math.atan2(dx, dz), { ai });
    if (ai === 'traffic') { c.prevN = a; c.tgtN = b; c.max = 26; }
    cars.push(c); return c;
  }
}
function spawnPolice(chasing) {
  const P = state === 'play' ? player.pos : new THREE.Vector2();
  const cand = [];
  for (let i = 0; i <= N; i++) for (let j = 0; j <= N; j++) {
    const n = nodePos(i, j), d = Math.hypot(n.x - P.x, n.z - P.y);
    if (d > 110 && d < 190 && spaceFree(n.x, n.z, 10)) cand.push({ i, j, n });
  }
  if (!cand.length) return;
  const k = cand[Math.floor(Math.random() * cand.length)];
  const c = new Car(k.n.x, k.n.z, Math.atan2(P.x - k.n.x, P.y - k.n.z), { ai: 'police', police: true, accel: 12, max: 30 });
  c.chase = chasing; c.tgtN = chasing ? null : { i: k.i, j: k.j };
  cars.push(c);
}
for (let i = 0; i < 16; i++) spawnTraffic('traffic');
for (let i = 0; i < 26; i++) spawnTraffic('parked');
{ // سيارة جاهزة أمام المخبأ
  const c = new Car(safe.x + safe.sx * 8, safe.z + 4, 0, { ai: 'parked', color: 0x8a1c1c, accel: 12, max: 38 });
  cars.push(c);
}
for (let i = 0; i < 2; i++) spawnPolice(false);

function removeCar(c) {
  if (c.officer) removeOfficer(c.officer);
  c.remove(); cars.splice(cars.indexOf(c), 1);
}
function removeOfficer(o) {
  scene.remove(o.H.g); officers.splice(officers.indexOf(o), 1);
  if (o.car) o.car.officer = null;
}

// ------------------------------------------------------------------ الذكاء الاصطناعي
function steerTo(c, tx, tz, maxV, dt) {
  const diff = wrapA(Math.atan2(tx - c.pos.x, tz - c.pos.y) - c.h);
  if (c.reverseT > 0) { c.reverseT -= dt; return { throttle: -1, steer: -(Math.sign(diff) || 1), brake: false, hand: false }; }
  const desired = maxV * (1 - Math.min(Math.abs(diff) / 1.6, 1) * 0.7);
  const throttle = c.speed < desired ? 1 : (c.speed > desired + 2 ? -0.7 : 0);
  if (throttle > 0.5 && Math.abs(c.speed) < 1) c.stuckT += dt; else c.stuckT = Math.max(0, c.stuckT - dt);
  if (c.stuckT > 1.3) { c.reverseT = 1.1; c.stuckT = 0; }
  return { throttle, steer: clamp(diff * 2.5, -1, 1), brake: false, hand: false };
}
function pickNext(c, goal) {
  const t = c.tgtN, p = c.prevN;
  let opts = neighbors(t).filter((n) => !p || n.i !== p.i || n.j !== p.j);
  if (!opts.length) opts = neighbors(t);
  if (goal) {
    const score = (n) => Math.abs(n.i - goal.i) + Math.abs(n.j - goal.j) + Math.random() * 0.5;
    return opts.map((n) => [score(n), n]).sort((a, b) => a[0] - b[0])[0][1];
  }
  return opts[Math.floor(Math.random() * opts.length)];
}
function obstacleAhead(c) {
  const fx = Math.sin(c.h), fz = Math.cos(c.h);
  const test = (x, z, side) => { const rx = x - c.pos.x, rz = z - c.pos.y, a = rx * fx + rz * fz; return a > 1 && a < 9.5 && Math.abs(rx * -fz + rz * fx) < side; };
  for (const o of cars) if (o !== c && test(o.pos.x, o.pos.y, 2.3)) return true;
  if (state === 'play' && !player.car && test(player.pos.x, player.pos.y, 1.8)) return true;
  return false;
}
function trafficAI(c, dt, maxV = 11) {
  if (!c.tgtN) { c.tgtN = nearestNode(c.pos.x, c.pos.y); c.prevN = null; }
  let tp = lanePoint(c.prevN, c.tgtN);
  if (Math.hypot(tp.x - c.pos.x, tp.z - c.pos.y) < 6) { const nx = pickNext(c, null); c.prevN = c.tgtN; c.tgtN = nx; tp = lanePoint(c.prevN, c.tgtN); }
  const inp = steerTo(c, tp.x, tp.z, maxV, dt);
  if (c.ignoreT > 0) c.ignoreT -= dt;
  else if (obstacleAhead(c)) {
    inp.throttle = c.speed > 0.3 ? -1 : 0; c.stuckT = 0;
    c.blockedT += dt; if (c.blockedT > 4) { c.ignoreT = 2.5; c.blockedT = 0; }
  } else c.blockedT = 0;
  c.input = inp;
}
function policeAI(c, dt) {
  c.exitCd -= dt;
  if (c.officer) { c.input = { throttle: 0, steer: 0, brake: true, hand: false }; return; }
  if (!c.chase) { trafficAI(c, dt, 12); return; }
  const P = player.pos, PV = player.car ? player.car.vel : player.vel;
  const d = dist2(c.pos, P.x, P.y);
  const maxV = Math.min(27 + W.level * 1.8, 37);
  let tx, tz;
  const los = d < 60 && segHit(c.pos.x, c.pos.y, P.x, P.y, 2, 1.0) >= 1;
  if (los) {
    const k = clamp(d / 25, 0, 1.2); tx = P.x + PV.x * k; tz = P.y + PV.y * k; c.tgtN = null; c.prevN = null;
  } else {
    if (!c.tgtN) { c.tgtN = nearestNode(c.pos.x, c.pos.y); c.prevN = null; }
    let tp = lanePoint(c.prevN, c.tgtN);
    if (Math.hypot(tp.x - c.pos.x, tp.z - c.pos.y) < 8) {
      const nx = pickNext(c, nearestNode(P.x, P.y)); c.prevN = c.tgtN; c.tgtN = nx; tp = lanePoint(c.prevN, c.tgtN);
    }
    tx = tp.x; tz = tp.z;
  }
  const onFoot = !player.car;
  const inp = steerTo(c, tx, tz, onFoot && d < 30 ? clamp((d - 6) * 1.1, 0, maxV) : maxV, dt);
  if (onFoot && d < 9 && c.reverseT <= 0) inp.throttle = c.speed > 0.5 ? -1 : 0;
  c.input = inp;
  if (onFoot && d < 30 && Math.abs(c.speed) < 3 && c.exitCd <= 0 && officers.length < 6) spawnOfficer(c);
}
function spawnOfficer(c) {
  const fx = Math.sin(c.h), fz = Math.cos(c.h);
  const o = { car: c, pos: new THREE.Vector2(c.pos.x + fz * 1.8, c.pos.y - fx * 1.8), vel: new THREE.Vector2(), H: makeHuman(COP), facing: c.h, ret: false };
  scene.add(o.H.g); officers.push(o); c.officer = o;
}
function updateOfficers(dt) {
  for (const o of [...officers]) {
    if (!cars.includes(o.car)) { removeOfficer(o); continue; }
    const P = player.pos;
    const dP = dist2(o.pos, P.x, P.y);
    o.ret = W.level === 0 || state !== 'play' || (player.car && dP > 5);
    const tx = o.ret ? o.car.pos.x : P.x, tz = o.ret ? o.car.pos.y : P.y;
    const dx = tx - o.pos.x, dz = tz - o.pos.y, d = Math.hypot(dx, dz);
    const spd = o.ret ? 5 : 6.9, stop = o.ret ? 0.1 : 1.0;
    const wx = d > stop ? (dx / d) * spd : 0, wz = d > stop ? (dz / d) * spd : 0;
    const k = 1 - Math.exp(-8 * dt);
    o.vel.x += (wx - o.vel.x) * k; o.vel.y += (wz - o.vel.y) * k;
    o.pos.x += o.vel.x * dt; o.pos.y += o.vel.y * dt;
    collideCircle(o.pos, 0.4, o.vel);
    pushFromCars(o.pos, 0.4, o.car);
    const sp = o.vel.length();
    if (sp > 0.3) o.facing = Math.atan2(o.vel.x, o.vel.y);
    else if (!o.ret) o.facing = Math.atan2(dx, dz);
    o.H.g.position.set(o.pos.x, 0, o.pos.y); o.H.g.rotation.y = o.facing;
    animHuman(o.H, sp, dt, !o.ret && d < 4);
    if (o.ret && dist2(o.pos, o.car.pos.x, o.car.pos.y) < 2.7) { removeOfficer(o); o.car.exitCd = 5; }
  }
}
function pushFromCars(p, r, ignore) {
  for (const c of cars) {
    if (c === ignore) continue;
    const dxc = p.x - c.pos.x, dzc = p.y - c.pos.y;
    if (dxc * dxc + dzc * dzc > 16) continue;
    const fx = Math.sin(c.h) * 1.25, fz = Math.cos(c.h) * 1.25;
    for (const s of [1, -1]) {
      const cx = c.pos.x + fx * s, cz = c.pos.y + fz * s, dx = p.x - cx, dz = p.y - cz, d = Math.hypot(dx, dz), m = 1.05 + r;
      if (d < m && d > 1e-4) { p.x = cx + dx / d * m; p.y = cz + dz / d * m; }
    }
  }
}
function carCollisions() {
  for (let i = 0; i < cars.length; i++) for (let j = i + 1; j < cars.length; j++) {
    const a = cars[i], b = cars[j];
    if (Math.abs(a.pos.x - b.pos.x) > 6 || Math.abs(a.pos.y - b.pos.y) > 6) continue;
    const afx = Math.sin(a.h) * 1.25, afz = Math.cos(a.h) * 1.25, bfx = Math.sin(b.h) * 1.25, bfz = Math.cos(b.h) * 1.25;
    for (const sa of [1, -1]) for (const sb of [1, -1]) {
      const ax = a.pos.x + afx * sa, az = a.pos.y + afz * sa, bx = b.pos.x + bfx * sb, bz = b.pos.y + bfz * sb;
      const dx = bx - ax, dz = bz - az, d = Math.hypot(dx, dz);
      if (d >= 2.1 || d < 1e-4) continue;
      const nx = dx / d, nz = dz / d, ov = (2.1 - d) / 2;
      a.pos.x -= nx * ov; a.pos.y -= nz * ov; b.pos.x += nx * ov; b.pos.y += nz * ov;
      const vrel = (b.vel.x - a.vel.x) * nx + (b.vel.y - a.vel.y) * nz;
      if (vrel < 0) {
        const imp = -vrel * 0.62;
        a.vel.x -= nx * imp; a.vel.y -= nz * imp; b.vel.x += nx * imp; b.vel.y += nz * imp;
        const pc = player.car;
        if (pc && (a === pc || b === pc) && -vrel > 5) {
          crashFx(-vrel);
          const other = a === pc ? b : a;
          if (other.police && -vrel > 9 && W.crimeCd <= 0) { setWanted(W.level + 1, 'اصطدمت بسيارة شرطة!'); W.crimeCd = 4; }
        }
      }
    }
  }
}

// ------------------------------------------------------------------ الصوت
const sound = {
  ctx: null, muted: false,
  init() {
    if (this.ctx) return;
    try {
      const ctx = this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.master = ctx.createGain(); this.master.gain.value = 0.8; this.master.connect(ctx.destination);
      const mk = (type, f) => { const o = ctx.createOscillator(); o.type = type; o.frequency.value = f; o.start(); return o; };
      const gain = (v, to) => { const g = ctx.createGain(); g.gain.value = v; g.connect(to); return g; };
      this.sirenG = gain(0, this.master); this.siren = mk('triangle', 800); this.siren.connect(this.sirenG);
      this.engG = gain(0, this.master); const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 520; lp.connect(this.engG);
      this.eng = mk('sawtooth', 50); this.eng.connect(lp); this.eng2 = mk('square', 25); const g2 = gain(0.4, lp); this.eng2.connect(g2);
      const buf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      this.noise = buf;
      const rain = ctx.createBufferSource(); rain.buffer = buf; rain.loop = true;
      const bp = ctx.createBiquadFilter(); bp.type = 'highpass'; bp.frequency.value = 1500;
      this.rainG = gain(0, this.master); rain.connect(bp); bp.connect(this.rainG); rain.start();
    } catch (e) { this.ctx = null; }
  },
  update(siren, engine, throttle, rainOn) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.siren.frequency.setTargetAtTime(760 + 420 * (0.5 + 0.5 * Math.sin(time * Math.PI * 1.3)), t, 0.03);
    this.sirenG.gain.setTargetAtTime(siren * 0.09, t, 0.1);
    this.eng.frequency.setTargetAtTime(42 + engine * 4.2 + throttle * 12, t, 0.05);
    this.eng2.frequency.setTargetAtTime(21 + engine * 2.1, t, 0.05);
    this.engG.gain.setTargetAtTime(player.car && state === 'play' ? 0.07 + throttle * 0.03 : 0, t, 0.1);
    this.rainG.gain.setTargetAtTime(rainOn ? 0.035 : 0, t, 0.3);
  },
  beep(f, dur = 0.12, type = 'square', vol = 0.08, delay = 0) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime + delay, o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = type; o.frequency.value = f; g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(this.master); o.start(t); o.stop(t + dur + 0.02);
  },
  cash() { [880, 1175, 1568].forEach((f, i) => this.beep(f, 0.18, 'sine', 0.12, i * 0.08)); },
  crash(v) {
    if (!this.ctx) return;
    const s = this.ctx.createBufferSource(), g = this.ctx.createGain(), lp = this.ctx.createBiquadFilter(), t = this.ctx.currentTime;
    s.buffer = this.noise; lp.type = 'lowpass'; lp.frequency.value = 900;
    g.gain.setValueAtTime(Math.min(0.5, v), t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.35);
    s.connect(lp); lp.connect(g); g.connect(this.master); s.start(t); s.stop(t + 0.4);
  },
  toggle() { this.muted = !this.muted; if (this.master) this.master.gain.value = this.muted ? 0 : 0.8; },
};
let lastCrash = 0;
function crashFx(v) {
  if (time - lastCrash < 0.25) return; lastCrash = time;
  shake = Math.min(1, v / 18); sound.crash(v / 30);
}

// ------------------------------------------------------------------ المطر
let rainOn = true;
const RAIN_N = 3500;
const rainPos = new Float32Array(RAIN_N * 6), rainDrops = new Float32Array(RAIN_N * 3);
for (let i = 0; i < RAIN_N; i++) { rainDrops[i * 3] = mr(-45, 45); rainDrops[i * 3 + 1] = mr(0, 30); rainDrops[i * 3 + 2] = mr(-45, 45); }
const rainGeo = new THREE.BufferGeometry(); rainGeo.setAttribute('position', new THREE.BufferAttribute(rainPos, 3));
const rain = new THREE.LineSegments(rainGeo, new THREE.LineBasicMaterial({ color: 0x8090b0, transparent: true, opacity: 0.32 }));
rain.frustumCulled = false; scene.add(rain);
function updateRain(dt) {
  rain.visible = rainOn; if (!rainOn) return;
  const cx = camera.position.x, cy = camera.position.y, cz = camera.position.z;
  for (let i = 0; i < RAIN_N; i++) {
    let y = rainDrops[i * 3 + 1] - 26 * dt;
    if (y < -cy) { y += 32; rainDrops[i * 3] = mr(-45, 45); rainDrops[i * 3 + 2] = mr(-45, 45); }
    rainDrops[i * 3 + 1] = y;
    const x = cx + rainDrops[i * 3], z = cz + rainDrops[i * 3 + 2], yy = cy + y - 10;
    rainPos.set([x, yy, z, x + 0.06, yy + 0.7, z + 0.03], i * 6);
  }
  rainGeo.attributes.position.needsUpdate = true;
}

// ------------------------------------------------------------------ الإدخال
const keys = {}, pressed = {};
addEventListener('keydown', (e) => {
  if (!keys[e.code]) pressed[e.code] = true; keys[e.code] = true;
  if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
  if (e.code === 'Escape' && state === 'play' && !locked) pauseGame();
});
addEventListener('keyup', (e) => { keys[e.code] = false; });
addEventListener('blur', () => { for (const k in keys) keys[k] = false; });
let locked = false, dragging = false, hadLock = false;
canvas.addEventListener('mousedown', () => {
  if (state !== 'play') return;
  dragging = true;
  if (!locked && canvas.requestPointerLock) { try { const p = canvas.requestPointerLock(); if (p && p.catch) p.catch(() => {}); } catch (e) { /* السحب يكفي */ } }
});
addEventListener('mouseup', () => { dragging = false; });
addEventListener('mousemove', (e) => {
  if (state !== 'play' || !(locked || dragging)) return;
  cam.yaw -= e.movementX * 0.0026;
  cam.pitch = clamp(cam.pitch + e.movementY * 0.002, -0.05, 1.1);
  cam.lastMouse = time;
});
document.addEventListener('pointerlockchange', () => {
  locked = document.pointerLockElement === canvas;
  if (!locked && hadLock && state === 'play') pauseGame();
  hadLock = locked;
  $('crosshint') && ($('crosshint').style.display = locked ? 'none' : '');
});
const K = (...c) => c.some((k) => keys[k]);

// ------------------------------------------------------------------ واجهة المستخدم
const $ = (id) => document.getElementById(id);
const ui = {};
['cash', 'bank', 'goalFill', 'goalText', 'stars', 'wantedText', 'loseBar', 'loseFill', 'arrest', 'arrestFill', 'toast', 'progress', 'progLabel', 'progFill', 'hint', 'speedo', 'kmh', 'stamFill', 'stamWrap'].forEach((k) => (ui[k] = $(k)));
const starEls = [...ui.stars.children];
const uiCache = {};
const setText = (el, key, v) => { if (uiCache[key] !== v) { uiCache[key] = v; el.textContent = v; } };
let toastT = 0;
function toast(msg, color = '#fff') { ui.toast.textContent = msg; ui.toast.style.color = color; ui.toast.classList.add('show'); toastT = 2.6; }

function setWanted(lvl, msg) {
  lvl = clamp(lvl, 0, 5);
  if (lvl > W.level) {
    W.level = lvl; W.lastSeen = 0;
    if (msg) toast(msg, '#ff6b6b');
    for (const c of cars) if (c.ai === 'police' && !c.chase) { c.chase = true; c.tgtN = null; c.prevN = null; }
  }
}

function updateHUD(dt) {
  setText(ui.cash, 'cash', fmt(cash));
  setText(ui.bank, 'bank', fmt(bank));
  ui.goalFill.style.width = Math.min(100, (bank / GOAL) * 100) + '%';
  setText(ui.goalText, 'goal', `الهدف: ${fmt(GOAL)}`);
  starEls.forEach((s, i) => s.classList.toggle('on', i < W.level));
  const hiding = W.level > 0 && W.lastSeen > 0.8;
  ui.stars.classList.toggle('blink', hiding);
  setText(ui.wantedText, 'wt', W.level === 0 ? '' : hiding ? 'اختفيت عن أنظارهم… ابقَ مختبئاً' : 'الشرطة تراك! اهرب واختبئ');
  ui.loseBar.classList.toggle('hidden', !hiding);
  if (hiding) ui.loseFill.style.width = (W.lastSeen / (5 + W.level * 2.5)) * 100 + '%';
  ui.arrest.classList.toggle('hidden', arrest <= 0.01);
  ui.arrestFill.style.width = arrest * 100 + '%';
  ui.speedo.classList.toggle('hidden', !player.car);
  ui.stamWrap.classList.toggle('hidden', !!player.car);
  if (player.car) setText(ui.kmh, 'kmh', String(Math.round(Math.abs(player.car.speed) * 3.6)));
  ui.stamFill.style.width = player.stamina * 100 + '%';
  ui.progress.classList.toggle('hidden', !robbing);
  if (robbing) { setText(ui.progLabel, 'pl', `جارٍ سرقة ${robbing.def.name}…`); ui.progFill.style.width = robProg * 100 + '%'; }
  if (toastT > 0) { toastT -= dt; if (toastT <= 0) ui.toast.classList.remove('show'); }
}

// الخريطة المصغّرة
const mm = $('minimap'), mctx = mm.getContext('2d');
const MMD = Math.min(2, window.devicePixelRatio || 1);
mm.width = mm.height = 200 * MMD;
function drawMinimap() {
  const S = mm.width, C = S / 2, s = 0.62 * MMD, P = player.pos;
  const cy = Math.cos(cam.yaw), sy = Math.sin(cam.yaw);
  const a = -s * cy, b = -s * sy, c = s * sy, d = -s * cy;
  const e = C - (a * P.x + c * P.y), f = C - (b * P.x + d * P.y);
  const toMap = (x, z) => [a * x + c * z + e, b * x + d * z + f];
  mctx.setTransform(1, 0, 0, 1, 0, 0);
  mctx.clearRect(0, 0, S, S);
  mctx.save(); mctx.beginPath(); mctx.arc(C, C, C, 0, Math.PI * 2); mctx.clip();
  mctx.fillStyle = '#4a4f5a'; mctx.fillRect(0, 0, S, S);
  mctx.setTransform(a, b, c, d, e, f);
  for (const bl of blocks) { mctx.fillStyle = bl.park ? '#1f3d24' : '#1a1d24'; mctx.fillRect(bl.cx - 25, bl.cz - 25, 50, 50); }
  mctx.fillStyle = '#0d0f14';
  mctx.fillRect(-BOUND - 400, -BOUND - 400, 400, 2 * BOUND + 800); mctx.fillRect(BOUND, -BOUND - 400, 400, 2 * BOUND + 800);
  mctx.fillRect(-BOUND, -BOUND - 400, 2 * BOUND, 400); mctx.fillRect(-BOUND, BOUND, 2 * BOUND, 400);
  mctx.setTransform(1, 0, 0, 1, 0, 0);
  const icon = (x, z, col, r, label, edge) => {
    let [mx, my] = toMap(x, z); const dx = mx - C, dy = my - C, dd = Math.hypot(dx, dy), lim = C - r - 3;
    if (dd > lim) { if (!edge) return; mx = C + dx / dd * lim; my = C + dy / dd * lim; }
    mctx.fillStyle = col; mctx.beginPath(); mctx.arc(mx, my, r, 0, Math.PI * 2); mctx.fill();
    if (label) { mctx.fillStyle = '#000'; mctx.font = `bold ${r * 1.3}px Tahoma`; mctx.textAlign = 'center'; mctx.textBaseline = 'middle'; mctx.fillText(label, mx, my + 1); }
  };
  for (const st of stores) {
    const hex = '#' + st.def.color.toString(16).padStart(6, '0');
    icon(st.x, st.z, st.cooldown > 0 ? '#555' : hex, (st.type === 'bank' ? 9 : 7) * MMD, '$', st.cooldown <= 0 && st.type !== 'shop');
  }
  icon(safe.x, safe.z, '#3dff7a', 8 * MMD, 'H', true);
  for (const car of cars) if (car.police) icon(car.pos.x, car.pos.y, car.chase ? ((time * 4 | 0) % 2 ? '#ff3030' : '#3060ff') : '#8fa8ff', 4.5 * MMD, '', false);
  for (const o of officers) icon(o.pos.x, o.pos.y, '#6f9bff', 3 * MMD, '', false);
  // اللاعب
  const heading = player.car ? player.car.h : player.facing;
  mctx.translate(C, C); mctx.rotate(-(heading - cam.yaw));
  mctx.fillStyle = '#fff'; mctx.strokeStyle = '#000'; mctx.lineWidth = 2 * MMD;
  mctx.beginPath(); mctx.moveTo(0, -9 * MMD); mctx.lineTo(6 * MMD, 7 * MMD); mctx.lineTo(0, 3 * MMD); mctx.lineTo(-6 * MMD, 7 * MMD); mctx.closePath(); mctx.stroke(); mctx.fill();
  mctx.restore();
}

// ------------------------------------------------------------------ منطق اللعب
function updateOnFoot(dt) {
  const fx = Math.sin(cam.yaw), fz = Math.cos(cam.yaw), rx = -fz, rz = fx;
  let mx = 0, mz = 0;
  if (K('KeyW', 'ArrowUp')) { mx += fx; mz += fz; }
  if (K('KeyS', 'ArrowDown')) { mx -= fx; mz -= fz; }
  if (K('KeyD', 'ArrowRight')) { mx += rx; mz += rz; }
  if (K('KeyA', 'ArrowLeft')) { mx -= rx; mz -= rz; }
  const len = Math.hypot(mx, mz);
  const sprint = K('ShiftLeft', 'ShiftRight') && len > 0 && player.stamina > 0.03;
  player.stamina = clamp(player.stamina + (sprint ? -dt / 7 : dt / 5), 0, 1);
  const spd = len > 0 ? (sprint ? 8.2 : 4.6) : 0;
  const tx = len > 0 ? (mx / len) * spd : 0, tz = len > 0 ? (mz / len) * spd : 0;
  const k = 1 - Math.exp(-10 * dt);
  player.vel.x += (tx - player.vel.x) * k; player.vel.y += (tz - player.vel.y) * k;
  player.pos.x += player.vel.x * dt; player.pos.y += player.vel.y * dt;
  const sp = player.vel.length();
  if (sp > 0.3) player.facing += wrapA(Math.atan2(player.vel.x, player.vel.y) - player.facing) * Math.min(1, dt * 12);
}
function updateDriving() {
  const c = player.car;
  c.input = {
    throttle: (K('KeyW', 'ArrowUp') ? 1 : 0) - (K('KeyS', 'ArrowDown') ? 1 : 0),
    steer: (K('KeyA', 'ArrowLeft') ? 1 : 0) - (K('KeyD', 'ArrowRight') ? 1 : 0),
    brake: false, hand: K('Space'),
  };
}
function nearestCar(maxD) {
  let best = null, bd = maxD;
  for (const c of cars) { const d = dist2(c.pos, player.pos.x, player.pos.y); if (d < bd && !c.officer) { bd = d; best = c; } }
  return best;
}
function policeSees(range = 60) {
  for (const c of cars) if (c.police && c.ai === 'police' && dist2(c.pos, player.pos.x, player.pos.y) < range && segHit(c.pos.x, c.pos.y, player.pos.x, player.pos.y, 2) >= 1) return true;
  return false;
}
function enterCar(c) {
  if (c.police) setWanted(W.level + 2, 'سرقت سيارة شرطة!');
  else if (c.ai === 'traffic' && policeSees()) setWanted(W.level + 1, 'الشرطة رأتك تسرق سيارة!');
  c.ai = 'player'; c.chase = false; player.car = c; robbing = null;
  player.H.g.visible = false;
  c.mesh.add(headlight); headlight.position.set(0, 0.8, 2.3); headlight.intensity = 260;
  c.mesh.add(headTarget); headTarget.position.set(0, -1, 22);
  cam.lastMouse = -10;
}
function exitCar() {
  const c = player.car;
  if (Math.abs(c.speed) > 7) { toast('خفّف السرعة أولاً'); return; }
  const fx = Math.sin(c.h), fz = Math.cos(c.h);
  player.pos.set(c.pos.x + fz * 1.9, c.pos.y - fx * 1.9);
  collideCircle(player.pos, 0.4, null);
  player.vel.set(0, 0); player.facing = c.h;
  c.ai = 'parked'; c.chase = false; c.input = { throttle: 0, steer: 0, brake: true, hand: false };
  player.car = null; player.H.g.visible = true;
  scene.add(headlight); headlight.intensity = 0; scene.add(headTarget);
}

function interactions(dt) {
  let hint = '';
  const P = player.pos;
  let near = null, nd = 1e9;
  for (const s of stores) { const d = dist2(P, s.x, s.z); if (d < nd) { nd = d; near = s; } }
  const dSafe = dist2(P, safe.x, safe.z);
  if (!player.car) {
    if (near && nd < 3.2) {
      if (near.cooldown > 0) { hint = `${near.def.name} مغلق الآن — عُد بعد ${Math.ceil(near.cooldown)} ثانية`; robbing = null; }
      else if (keys.KeyE) {
        if (robbing !== near) {
          robbing = near; robProg = 0;
          setWanted(near.def.heat, '🚨 انطلق جهاز الإنذار! الشرطة في الطريق');
        }
        robProg += dt / near.def.time;
        player.facing = -near.sx * Math.PI / 2;
        if (Math.floor(time * 2.5) !== Math.floor((time - dt) * 2.5)) sound.beep(1250, 0.1, 'square', 0.05);
        if (robProg >= 1) {
          const amt = Math.round(mr(near.def.value[0], near.def.value[1]) / 10) * 10;
          cash += amt; near.cooldown = near.def.cd; robbing = null; robProg = 0;
          setWanted(Math.min(5, Math.max(W.level, near.def.heat) + (near.def.heat >= 3 ? 1 : 0)));
          W.lastSeen = 0;
          toast(`+${fmt(amt)}  اهرب إلى المخبأ!`, '#7dff9e'); sound.cash();
        }
      } else {
        if (robbing) { toast('توقفت السرقة'); robbing = null; }
        hint = `اضغط مطولاً E لسرقة ${near.def.name}  (${fmt(near.def.value[0])} – ${fmt(near.def.value[1])})`;
      }
    } else if (robbing) { toast('ابتعدت — فشلت السرقة'); robbing = null; }
    if (dSafe < 3.6) {
      hint = cash > 0 ? `اضغط E لإخفاء ${fmt(cash)} في المخبأ` : 'المخبأ — أحضر المال المسروق هنا';
      if (pressed.KeyE && cash > 0) {
        if (W.level > 0) toast('الشرطة تلاحقك! تخلّص منها أولاً', '#ff6b6b');
        else {
          bank += cash; toast(`تم إخفاء ${fmt(cash)} 💰`, '#7dff9e'); cash = 0; save(); sound.cash();
          if (bank >= GOAL && !wonShown) { wonShown = true; setTimeout(() => setState('win'), 900); }
        }
      }
    }
    const car = nearestCar(3.6);
    if (car && !hint) hint = car.police ? 'اضغط F لسرقة سيارة الشرطة (+2 نجمة)' : 'اضغط F لركوب السيارة';
    if (car && pressed.KeyF) enterCar(car);
  } else {
    if (near && nd < 7 && near.cooldown <= 0) hint = `انزل من السيارة (F) لسرقة ${near.def.name}`;
    if (dSafe < 7 && cash > 0) hint = 'انزل من السيارة (F) لإخفاء المال';
    if (pressed.KeyF) exitCar();
  }
  setText(ui.hint, 'hint', hint);
}

function wantedUpdate(dt) {
  W.crimeCd -= dt;
  if (W.level <= 0) return;
  let seen = false;
  for (const c of cars) {
    if (!(c.police && c.ai === 'police' && c.chase)) continue;
    const d = dist2(c.pos, player.pos.x, player.pos.y);
    if (d < 18 || (d < 65 && segHit(c.pos.x, c.pos.y, player.pos.x, player.pos.y, 2) >= 1)) { seen = true; break; }
  }
  if (!seen) for (const o of officers) if (!o.ret && dist2(o.pos, player.pos.x, player.pos.y) < 35) { seen = true; break; }
  if (seen || robbing) W.lastSeen = 0; else W.lastSeen += dt;
  if (W.lastSeen > 5 + W.level * 2.5) {
    W.level--; W.lastSeen = 0;
    if (W.level === 0) {
      toast('تخلّصت من الشرطة! 😎', '#8fd3ff');
      for (const c of cars) if (c.ai === 'police') { c.chase = false; c.tgtN = null; c.prevN = null; }
    } else toast('خسرت نجمة — استمر بالاختباء', '#8fd3ff');
  }
}
function policeManager(dt) {
  spawnT -= dt;
  const pol = cars.filter((c) => c.ai === 'police');
  if (pol.length < POLICE_TARGET[W.level] && spawnT <= 0) { spawnPolice(W.level > 0); spawnT = W.level > 0 ? 2.2 : 8; }
  if (W.level === 0 && pol.length > 2) {
    for (const c of pol.slice(2)) if (dist2(c.pos, player.pos.x, player.pos.y) > 80 || state !== 'play') removeCar(c);
  }
}
function arrestUpdate(dt) {
  let rate = 0;
  if (W.level > 0) {
    const P = player.pos;
    if (!player.car) {
      for (const o of officers) if (!o.ret && dist2(o.pos, P.x, P.y) < 1.8) rate += 0.75;
      for (const c of cars) if (c.ai === 'police' && c.chase && dist2(c.pos, P.x, P.y) < 7 && Math.abs(c.speed) < 3) rate += 0.25;
    } else if (Math.abs(player.car.speed) < 3) {
      for (const c of cars) if (c.ai === 'police' && c.chase && dist2(c.pos, P.x, P.y) < 7) rate += 0.35;
      for (const o of officers) if (dist2(o.pos, P.x, P.y) < 3.3) rate += 0.5;
    }
  }
  arrest = rate > 0 ? Math.min(1, arrest + rate * dt) : Math.max(0, arrest - dt * 0.6);
  if (arrest >= 1) bust();
}
function bust() {
  $('bustText').textContent = cash > 0 ? `صادرت الشرطة ${fmt(cash)} كانت بحوزتك. مالك في المخبأ بأمان.` : 'لم يكن معك مال هذه المرة. مالك في المخبأ بأمان.';
  cash = 0; arrest = 0; robbing = null;
  sound.beep(220, 0.5, 'sawtooth', 0.12); sound.beep(165, 0.7, 'sawtooth', 0.12, 0.3);
  setState('busted');
}
function respawn() {
  if (player.car) { player.car.speed = 0; player.car.vel.set(0, 0); exitCar(); }
  W.level = 0; W.lastSeen = 0;
  for (const o of [...officers]) removeOfficer(o);
  for (const c of cars.filter((c) => c.ai === 'police')) { c.chase = false; c.tgtN = null; c.prevN = null; }
  for (const c of cars.filter((c) => c.ai === 'police').slice(2)) removeCar(c);
  player.pos.set(safe.x, safe.z); player.vel.set(0, 0);
  player.facing = safe.sx * Math.PI / 2; cam.yaw = player.facing;
  player.H.g.visible = true;
}

// ------------------------------------------------------------------ الكاميرا والأضواء
function updateCamera(dt) {
  if (state === 'menu') {
    cam.orbit += dt * 0.04;
    camera.position.set(Math.cos(cam.orbit) * 170, 75, Math.sin(cam.orbit) * 170);
    camera.lookAt(0, 10, 0); return;
  }
  const c = player.car;
  const tx = player.pos.x, tz = player.pos.y, ty = c ? 1.5 : 1.65;
  const dist = c ? 9.5 + Math.abs(c.speed) * 0.07 : 5.2;
  if (c && time - cam.lastMouse > 1.0) {
    cam.yaw += wrapA(c.h - cam.yaw) * Math.min(1, dt * 2.6);
    cam.pitch += (0.26 - cam.pitch) * Math.min(1, dt * 1.5);
  }
  const cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
  let dx = -Math.sin(cam.yaw) * cp * dist, dy = sp * dist + 0.4, dz = -Math.cos(cam.yaw) * cp * dist;
  const t = segHit(tx, tz, tx + dx, tz + dz, 2.5, 0.35);
  if (t < 1) { const k = Math.max(0.12, t - 0.04); dx *= k; dz *= k; }
  const want = new THREE.Vector3(tx + dx, Math.max(0.5, ty + dy), tz + dz);
  if (shake > 0) { want.x += mr(-1, 1) * shake * 0.5; want.y += mr(-1, 1) * shake * 0.4; shake = Math.max(0, shake - dt * 2.5); }
  camera.position.lerp(want, 1 - Math.exp(-dt * (c ? 9 : 16)));
  camera.lookAt(tx, ty + (c ? 0.7 : 0.15), tz);
  const fov = c ? 64 + Math.min(Math.abs(c.speed), 35) * 0.45 : 62;
  if (Math.abs(camera.fov - fov) > 0.05) { camera.fov += (fov - camera.fov) * Math.min(1, dt * 3); camera.updateProjectionMatrix(); }
}
function updateLights() {
  const P = state === 'play' ? player.pos : { x: 0, y: 0 };
  moon.position.set(P.x + 45, 95, P.y + 30); moon.target.position.set(P.x, 0, P.y); moon.target.updateMatrixWorld();
  sky.position.copy(camera.position);
  const chasers = cars.filter((c) => c.police && c.chase)
    .map((c) => [c.pos.distanceToSquared(new THREE.Vector2(camera.position.x, camera.position.z)), c]).sort((a, b) => a[0] - b[0]);
  copLights.forEach((l, i) => {
    const e = chasers[i];
    if (!e) { l.intensity = 0; return; }
    const c = e[1], red = (time * 2.2 + c.pos.x * 0.01) % 1 < 0.5;
    l.position.set(c.pos.x, 2.4, c.pos.y); l.color.setHex(red ? 0xff2020 : 0x2050ff); l.intensity = 90;
  });
  for (const b of blinkers) b.visible = (time % 2) < 0.25;
  for (const s of stores) {
    const open = s.cooldown <= 0;
    s.ring.visible = open; s.beacon.visible = open;
    if (open) { const k = 1 + Math.sin(time * 3) * 0.08; s.ring.scale.set(k, k, k); }
    s.signMat.color.setScalar(open ? 1.7 : 0.25); s.glassMat.color.copy(s.col).multiplyScalar(open ? 0.55 : 0.08);
  }
  const k = 1 + Math.sin(time * 3) * 0.08; safe.ring.scale.set(k, k, k);
}

// ------------------------------------------------------------------ الحلقة الرئيسية
function worldUpdate(dt) {
  for (const c of cars) {
    if (c.ai === 'traffic') trafficAI(c, dt);
    else if (c.ai === 'police') policeAI(c, dt);
    else if (c.ai === 'parked') c.input = { throttle: 0, steer: 0, brake: true, hand: false };
  }
  for (const c of cars) c.physics(dt);
  carCollisions();
  for (const c of cars) { const imp = c.collideWorld(); if (c === player.car && imp > 6) crashFx(imp); }
  updateOfficers(dt);
  for (const c of cars) c.sync(dt);
  policeManager(dt);
  for (const s of stores) s.cooldown = Math.max(0, s.cooldown - dt);
}
function update(dt) {
  if (pressed.KeyR) { rainOn = !rainOn; toast(rainOn ? 'المطر: تشغيل' : 'المطر: إيقاف'); }
  if (pressed.KeyM) { sound.toggle(); toast(sound.muted ? 'الصوت: مكتوم' : 'الصوت: تشغيل'); }
  if (pressed.KeyH) { sound.beep(392, 0.35, 'sawtooth', 0.07); sound.beep(494, 0.35, 'sawtooth', 0.05); }
  if (player.car) updateDriving(); else updateOnFoot(dt);
  worldUpdate(dt);
  if (player.car) player.pos.copy(player.car.pos);
  else {
    collideCircle(player.pos, 0.4, player.vel);
    pushFromCars(player.pos, 0.4, null);
    player.H.g.position.set(player.pos.x, 0, player.pos.y);
    player.H.g.rotation.y = player.facing;
    animHuman(player.H, player.vel.length(), dt, !!robbing);
    player.H.bag.visible = cash > 0;
    const bs = 0.7 + Math.min(cash / 60000, 1) * 0.8; player.H.bag.scale.set(bs, bs, bs);
  }
  interactions(dt);
  wantedUpdate(dt);
  arrestUpdate(dt);
}

function setState(s) {
  state = s;
  $('menu').classList.toggle('hidden', s !== 'menu');
  $('busted').classList.toggle('hidden', s !== 'busted');
  $('pause').classList.toggle('hidden', s !== 'paused');
  $('win').classList.toggle('hidden', s !== 'win');
  $('hud').classList.toggle('hidden', s === 'menu');
  if (s !== 'play' && document.pointerLockElement) document.exitPointerLock();
  for (const k in keys) keys[k] = false;
}
function pauseGame() { if (state === 'play') setState('paused'); }
function lockPointer() { try { const p = canvas.requestPointerLock(); if (p && p.catch) p.catch(() => {}); } catch (e) { /* لا بأس */ } }
$('startBtn').onclick = () => {
  sound.init(); respawn(); setState('play'); lockPointer();
  toast('اسرق المتاجر ($) واهرب إلى المخبأ (H)', '#ffd36b');
};
$('bustBtn').onclick = () => { respawn(); setState('play'); lockPointer(); };
$('resumeBtn').onclick = () => { setState('play'); lockPointer(); };
$('winBtn').onclick = () => { setState('play'); lockPointer(); };

const clock = new THREE.Clock();
let hudT = 0;
function loop() {
  requestAnimationFrame(loop);
  const dt = Math.min(clock.getDelta(), 0.05);
  if (state === 'play') { time += dt; update(dt); }
  else if (state === 'menu') { time += dt; worldUpdate(dt); }
  updateCamera(dt);
  updateLights();
  updateRain(state === 'paused' ? 0 : dt);
  if (state !== 'menu') {
    updateHUD(dt);
    if ((hudT += dt) > 1 / 30) { hudT = 0; drawMinimap(); }
  }
  let siren = 0;
  if (W.level > 0 && state === 'play') for (const c of cars) if (c.police && c.chase) siren = Math.max(siren, Math.pow(Math.max(0, 1 - dist2(c.pos, player.pos.x, player.pos.y) / 140), 1.5));
  sound.update(state === 'play' ? siren : 0, player.car ? Math.abs(player.car.speed) : 0, player.car ? Math.max(0, player.car.input.throttle) : 0, rainOn && state !== 'menu');
  for (const k in pressed) delete pressed[k];
  composer.render();
}
$('loading').remove();
loop();

// واجهة صغيرة للاختبار والتطوير من الطرفية
window.__damar = { step(n, dt = 0.05) { for (let i = 0; i < n; i++) { time += dt; update(dt); for (const k in pressed) delete pressed[k]; } }, get cash() { return cash; }, get bank() { return bank; }, get arrest() { return arrest; }, officers, player, cars, stores, safe, W, get state() { return state; }, setState, keys, pressed, cam, setWanted };
