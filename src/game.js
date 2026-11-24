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
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';

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
const PISTOL_PRICE = 3000, LAUNDER_FEE = 0.2, MAG = 12;

const STORE_TYPES = {
  shop:  { name: 'سوبرماركت',     value: [700, 1600],    time: 4,  heat: 1, cd: 60,  color: 0x30d5ff, h: 7 },
  gas:   { name: 'محطة وقود',     value: [1100, 2600],   time: 5,  heat: 2, cd: 75,  color: 0xffa21f, h: 7 },
  jewel: { name: 'مجوهرات',       value: [7000, 15000],  time: 7,  heat: 3, cd: 120, color: 0xff3fd0, h: 9, goods: true },
  bank:  { name: 'البنك المركزي', value: [30000, 60000], time: 10, heat: 5, cd: 200, color: 0x45ff8a, h: 16 },
};
const STORE_LIST = ['bank', 'jewel', 'jewel', 'gas', 'gas', 'gas', 'shop', 'shop', 'shop', 'shop', 'shop', 'shop'];
const CAR_MODELS = ['sedan', 'sedan_sports', 'suv', 'suv_luxury', 'taxi', 'van', 'hatchback_sports', 'delivery_van'];

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

// ------------------------------------------------------------------ تحميل النماذج ثلاثية الأبعاد
const MODELS = {};
{
  const loader = new GLTFLoader(); loader.setMeshoptDecoder(MeshoptDecoder);
  const list = [...CAR_MODELS, 'police_car', 'worker', 'tree_oak', 'tree_pine'];
  let done = 0;
  try {
    await Promise.all(list.map(async (n) => {
      MODELS[n] = await loader.loadAsync(`assets/models/${n}.glb`);
      document.getElementById('loading').textContent = `جارٍ تحميل النماذج… ${++done}/${list.length}`;
    }));
  } catch (e) {
    document.getElementById('loading').innerHTML = 'تعذّر تحميل ملفات اللعبة.<br>شغّلها عبر start.bat أو خادم محلي ولا تفتح index.html مباشرة.';
    throw e;
  }
  // الأشجار مصنوعة بمواد غير مضاءة؛ نحوّلها لمواد تتأثر بإضاءة الليل
  for (const n of ['tree_oak', 'tree_pine']) MODELS[n].scene.traverse((m) => {
    if (m.isMesh) { m.castShadow = true; if (m.material.isMeshBasicMaterial) m.material = new THREE.MeshStandardMaterial({ color: m.material.color.clone().multiplyScalar(0.8), map: m.material.map, roughness: 0.95, envMapIntensity: 0.15 }); }
  });
}
const treeScale = (() => { const b = new THREE.Box3().setFromObject(MODELS.tree_oak.scene); return 6.5 / (b.max.y - b.min.y); })();

// ------------------------------------------------------------------ مواد
const std = (p) => new THREE.MeshStandardMaterial({ envMapIntensity: 0.15, ...p });
const asphaltTex = canvasTex(noiseCanvas(256, 40, 22, 7));
asphaltTex.repeat.set(160, 160);
const concreteTex = canvasTex(noiseCanvas(256, 92, 26, 9));
concreteTex.repeat.set(6, 6);
// خرائط نتوءات حقيقية (CC0) + خريطة بِرَك ماء للأسفلت المبلل
const texLoader = new THREE.TextureLoader();
const normalTex = async (name, rep) => {
  const t = await texLoader.loadAsync(`assets/textures/${name}.webp`);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(rep, rep); t.anisotropy = MAX_ANISO; return t;
};
const [asphaltN, pavingN, plasterN] = await Promise.all([normalTex('asphalt_normal', 700), normalTex('paving_normal', 10), normalTex('plaster_normal', 8)]);
const puddleTex = (() => {
  const c = document.createElement('canvas'); c.width = c.height = 512; const g = c.getContext('2d'); const r = mulberry32(99);
  g.fillStyle = 'rgb(0,190,0)'; g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 70; i++) {
    const x = r() * 512, y = r() * 512, rad = 10 + r() * 55;
    for (const [ox, oy] of [[0, 0], [512, 0], [-512, 0], [0, 512], [0, -512]]) {
      const gr = g.createRadialGradient(x + ox, y + oy, 0, x + ox, y + oy, rad);
      gr.addColorStop(0, 'rgba(0,25,0,0.95)'); gr.addColorStop(0.6, 'rgba(0,40,0,0.7)'); gr.addColorStop(1, 'rgba(0,190,0,0)');
      g.fillStyle = gr; g.beginPath(); g.ellipse(x + ox, y + oy, rad * 1.6, rad, r() * 3, 0, Math.PI * 2); g.fill();
    }
  }
  const t = canvasTex(c, false); t.repeat.set(30, 30); return t;
})();
const M = {
  ground: std({ map: asphaltTex, normalMap: asphaltN, normalScale: new THREE.Vector2(0.22, 0.22), roughnessMap: puddleTex, roughness: 1, metalness: 0.05, envMapIntensity: 0.9 }),
  sidewalk: std({ map: concreteTex, normalMap: pavingN, color: 0x8c8c94, roughness: 0.7, envMapIntensity: 0.5 }),
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
  return std({ map: t.map, emissiveMap: t.emissiveMap, normalMap: plasterN, normalScale: new THREE.Vector2(0.6, 0.6), emissive: 0xffffff, emissiveIntensity: 1.15, roughness: 0.75, metalness: 0.1, envMapIntensity: 0.35 });
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
// المشتري (يشتري البضائع المسروقة ويبيع المسدسات) ومغسلة الأموال
const [fence, laundry] = (() => {
  const out = [];
  const pool = lots.filter((l) => !used.has(lotKey(l))).sort((a, b) => Math.hypot(b.lx - safe.x, b.lz - safe.z) - Math.hypot(a.lx - safe.x, a.lz - safe.z));
  const pick = (pred) => { const l = pool.find((l) => !used.has(lotKey(l)) && pred(l)); used.add(lotKey(l)); return l; };
  const lf = pick((l) => l.bi >= N - 2 && l.bj <= 2);
  const ll = pick((l) => l.bi <= 2 && l.bj >= N - 2);
  out.push(makeSafehouse(lf, 'المشتري', 0xb26bff, 0x231d2b), makeSafehouse(ll, 'مغسلة النور', 0x3dd8ff, 0x1f2a30));
  return out;
})();

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

function makeSafehouse(l, label = 'المخبأ', hex = 0x3dff7a, body = 0x2b2a27) {
  const w = 19, h = 6, cl = new THREE.Color(hex);
  const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, w), std({ color: body, roughness: 0.9 }));
  b.position.set(l.lx, h / 2, l.lz); b.castShadow = b.receiveShadow = true; scene.add(b);
  addCollider(l.lx, l.lz, w, w, h);
  const face = l.lx + l.sx * (w / 2), rotY = l.sx > 0 ? Math.PI / 2 : -Math.PI / 2;
  const door = new THREE.Mesh(new THREE.PlaneGeometry(8, 4), std({ color: 0x6d7076, roughness: 0.5, metalness: 0.6 }));
  door.position.set(face + l.sx * 0.03, 2, l.lz); door.rotation.y = rotY; scene.add(door);
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(7, 1.6), new THREE.MeshBasicMaterial({ map: signTex(label, hex), color: new THREE.Color(1.7, 1.7, 1.7) }));
  sign.position.set(face + l.sx * 0.06, 4.9, l.lz); sign.rotation.y = rotY; scene.add(sign);
  const zone = { x: l.lx + l.sx * 13.6, z: l.lz };
  const ring = new THREE.Mesh(new THREE.RingGeometry(2.2, 2.8, 40), new THREE.MeshBasicMaterial({ color: cl.clone().multiplyScalar(2.2), transparent: true, opacity: 0.85, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
  ring.rotation.x = -Math.PI / 2; ring.position.set(zone.x, 0.2, zone.z); scene.add(ring);
  const beacon = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 0.9, 70, 12, 1, true),
    new THREE.MeshBasicMaterial({ color: hex, transparent: true, opacity: 0.12, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  beacon.position.set(zone.x, 35, zone.z); scene.add(beacon);
  return { ...zone, sx: l.sx, ring, hex };
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

// الأشجار في الحدائق (نماذج Quaternius)
for (const [x, z, k] of treeSpots) {
  const t = MODELS[rand() < 0.5 ? 'tree_oak' : 'tree_pine'].scene.clone(true);
  t.scale.setScalar(treeScale * k); t.position.set(x, 0.2, z); t.rotation.y = rand() * Math.PI * 2;
  scene.add(t);
  addCollider(x, z, 0.6, 0.6, 1);
}

// انعكاسات حقيقية: نلتقط بيئة المدينة الليلية نفسها كخريطة انعكاس
{
  scene.environment = null;
  scene.position.set(0, -3, 0); scene.updateMatrixWorld(true);
  scene.environment = pmrem.fromScene(scene, 0.02, 0.5, 900).texture;
  scene.position.set(0, 0, 0); scene.updateMatrixWorld(true);
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

// ------------------------------------------------------------------ الشخصيات (نموذج Quaternius متحرك)
const HUMAN_ROLES = {
  thief: { Shirt: 0x1d1e22, Pants: 0x1c2638, Hair: 0x111111, Socks: 0x222222 },
  cop: { Shirt: 0x1d3466, Pants: 0x121a2b, Hair: 0x0e1a36, Socks: 0x111111 },
};
const roleMats = {};
const BAG_GEO = new THREE.BoxGeometry(0.42, 0.46, 0.22);
let HUMAN_SCALE = 1, HUMAN_FOOT = 0;
{ // قياس الطول الحقيقي للنموذج مرة واحدة لتحجيمه إلى 1.8 م
  const probe = SkeletonUtils.clone(MODELS.worker.scene);
  const mx = new THREE.AnimationMixer(probe);
  mx.clipAction(clipOf('idle')).play(); mx.update(0.01);
  probe.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(probe, true);
  HUMAN_SCALE = 1.8 / (box.max.y - box.min.y); HUMAN_FOOT = -box.min.y * HUMAN_SCALE;
}
function clipOf(kind) {
  const names = { idle: 'Man_Idle', walk: 'Man_Walk', run: 'Man_Run', rob: 'Man_Punch' };
  return MODELS.worker.animations.find((a) => a.name.endsWith(names[kind]));
}
function makeHuman(o) {
  const g = new THREE.Group();
  const root = SkeletonUtils.clone(MODELS.worker.scene);
  root.scale.setScalar(HUMAN_SCALE); root.position.y = HUMAN_FOOT;
  const mats = roleMats[o.role] || (roleMats[o.role] = {});
  root.traverse((m) => {
    if (!m.isMesh) return;
    m.castShadow = true; m.frustumCulled = false;
    const name = m.material.name, col = HUMAN_ROLES[o.role][name];
    if (!mats[name]) { mats[name] = m.material.clone(); if (col !== undefined) mats[name].color.setHex(col); mats[name].envMapIntensity = 0.2; }
    m.material = mats[name];
  });
  g.add(root);
  const mixer = new THREE.AnimationMixer(root);
  const actions = {};
  for (const k of ['idle', 'walk', 'run', 'rob']) actions[k] = mixer.clipAction(clipOf(k));
  actions.idle.play();
  // قناع ومسدس مثبّتان على عظمتي الرأس واليد اليمنى (يتبعان الحركة)
  let mask = null, gun = null;
  if (o.gear) {
    g.updateMatrixWorld(true);
    let head = null, hand = null;
    root.traverse((b) => { if (!b.isBone) return; if (/^Head$/.test(b.name)) head = b; if (/^Palm\.?R$/.test(b.name)) hand = b; });
    const ws = new THREE.Vector3();
    if (head) {
      head.getWorldScale(ws); const k = 1 / ws.x;
      mask = new THREE.Group(); mask.scale.setScalar(k); mask.position.set(0, 0.13 * k, 0.015 * k);
      const cloth = std({ color: 0x0b0b0d, roughness: 0.95 });
      const m1 = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.3, 0.26), cloth); m1.castShadow = true; mask.add(m1);
      const eyes = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.045, 0.02), new THREE.MeshBasicMaterial({ color: 0xd9c3a5 }));
      eyes.position.set(0, 0.035, 0.13); mask.add(eyes);
      mask.visible = false; head.add(mask);
    }
    if (hand) {
      hand.getWorldScale(ws); const k = 1 / ws.x;
      gun = new THREE.Group(); gun.scale.setScalar(k); gun.position.set(0, 0.06 * k, 0.02 * k);
      const metal = std({ color: 0x1a1b1e, roughness: 0.35, metalness: 0.8 });
      const sl = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.05, 0.2), metal); sl.position.set(0, 0.03, 0.05);
      const gr = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.1, 0.045), metal); gr.position.set(0, -0.02, -0.02); gr.rotation.x = 0.25;
      gun.add(sl, gr); gun.visible = false; hand.add(gun);
    }
  }
  let bag = null;
  if (o.bag) { bag = new THREE.Mesh(BAG_GEO, std({ color: 0x3e4a2a, roughness: 1 })); bag.position.set(0, 1.25, -0.24); bag.castShadow = true; bag.visible = false; g.add(bag); }
  const arms = {};
  root.traverse((b) => { if (b.isBone && /^UpperArm\.?[LR]$/.test(b.name)) arms[b.name.slice(-1)] = b; });
  return { g, mixer, actions, cur: 'idle', bag, mask, gun, arms };
}
function animHuman(H, speed, dt, rob = false) {
  const want = rob ? 'rob' : speed > 5.4 ? 'run' : speed > 0.35 ? 'walk' : 'idle';
  if (want !== H.cur) {
    const next = H.actions[want].reset().play();
    H.actions[H.cur].crossFadeTo(next, 0.22, false);
    H.cur = want;
  }
  if (want === 'walk') H.actions.walk.timeScale = clamp(speed / 2.6, 0.6, 2.2);
  if (want === 'run') H.actions.run.timeScale = clamp(speed / 7.5, 0.7, 1.4);
  H.mixer.update(dt);
}

// ------------------------------------------------------------------ السيارات (طقم سيارات Kenney)
const LIGHT_GEO = new THREE.BoxGeometry(0.4, 0.13, 0.05), BAR_GEO = new THREE.BoxGeometry(0.5, 0.14, 0.3);
const carTemplates = {};
for (const name of [...CAR_MODELS, 'police_car']) {
  const scene0 = MODELS[name].scene;
  scene0.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(scene0), size = box.getSize(new THREE.Vector3());
  const s = 4.4 / size.z;
  scene0.traverse((m) => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; m.material.envMapIntensity = 0.7; m.material.roughness = 0.45; m.material.metalness = 0.25; } });
  carTemplates[name] = { scene: scene0, s, cx: (box.min.x + box.max.x) / 2, cz: (box.min.z + box.max.z) / 2, minY: box.min.y, W: size.x * s, H: size.y * s, wheelR: 0.3 * s };
}
function makeCarMesh(name, police) {
  const T = carTemplates[name];
  const g = new THREE.Group();
  const m = T.scene.clone(true);
  m.scale.setScalar(T.s); m.position.set(-T.cx * T.s, -T.minY * T.s, -T.cz * T.s);
  g.add(m);
  const wheels = [], fronts = [];
  m.traverse((o) => {
    if (o.name && o.name.startsWith('wheel') && !(o.parent && o.parent.name.startsWith('wheel'))) {
      o.rotation.order = 'YXZ'; wheels.push(o); if (o.name.includes('front')) fronts.push(o);
    }
  });
  const add = (geo, mat, x, y, z) => { const k = new THREE.Mesh(geo, mat); k.position.set(x, y, z); g.add(k); return k; };
  const lx = T.W * 0.3, ly = T.H * 0.36;
  add(LIGHT_GEO, M.head, -lx, ly, 2.2); add(LIGHT_GEO, M.head, lx, ly, 2.2);
  const tailMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.2, 0.05, 0.05) });
  add(LIGHT_GEO, tailMat, -lx, ly + 0.05, -2.2); add(LIGHT_GEO, tailMat, lx, ly + 0.05, -2.2);
  let barR = null, barB = null;
  if (police) {
    barR = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.4, 0, 0) });
    barB = new THREE.MeshBasicMaterial({ color: new THREE.Color(0, 0, 0.4) });
    add(BAR_GEO, barR, -0.28, T.H - 0.04, -0.15); add(BAR_GEO, barB, 0.28, T.H - 0.04, -0.15);
  }
  g.rotation.order = 'YXZ';
  return { mesh: g, wheels, fronts, tailMat, barR, barB, wheelR: T.wheelR };
}


class Car {
  constructor(x, z, h, o = {}) {
    this.pos = new THREE.Vector2(x, z); this.vel = new THREE.Vector2(); this.h = h;
    this.speed = 0; this.lat = 0; this.steerS = 0;
    this.police = !!o.police; this.ai = o.ai || 'parked';
    this.accel = o.accel || mr(8, 11); this.max = o.max || mr(30, 37);
    Object.assign(this, makeCarMesh(this.police ? 'police_car' : (o.model || CAR_MODELS[Math.floor(Math.random() * CAR_MODELS.length)]), this.police));
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
    for (const w of this.wheels) w.rotation.x += this.speed * dt / this.wheelR;
    for (const f of this.fronts) f.rotation.y = this.steerS * 0.45;
    const braking = (this.input.throttle < 0 && this.speed > 0.5) || this.input.brake || this.input.hand;
    this.tailMat.color.setRGB(braking ? 6 : 1.2, braking ? 0.25 : 0.05, braking ? 0.25 : 0.05);
    if (this.police) {
      const on = this.chase || (this === player.car && sirenOn), ph = (time * 2.2 + this.pos.x * 0.01) % 1 < 0.5;
      this.barR.color.setRGB(on && ph ? 9 : 0.4, 0, 0);
      this.barB.color.setRGB(0, on && !ph ? 1.5 : 0, on && !ph ? 10 : 0.4);
    }
  }
  remove() { scene.remove(this.mesh); }
}

// ------------------------------------------------------------------ حالة اللعبة
let time = 0, state = 'menu';
const cars = [], officers = [];
// نظام الملاحقة على طريقة ROB RUN (بلا نجوم):
// clean = لا أحد يبحث عنك · alarm = إنذار والشرطة متجهة إلى مكان الجريمة ولا تعرفك
// chase = رأتك الشرطة وتعرّفت عليك فتلاحقك مباشرة · search = أفلتّ منهم فيمشّطون آخر مكان رأوك فيه
// level = شدة الاستجابة (مخفية): تحدد عدد الدوريات وإطلاق النار
// الدور: civilian = مدني لا تلاحقه الشرطة · criminal = تحوّل إلى مجرم بارتكاب جريمة · cop = شرطي يطارد اللصوص
let role = 'civilian';
const W = { level: 0, mode: 'clean', modeT: 0, lastSeen: 0, crimeCd: 0, tx: 0, tz: 0, id: 0, car: null };
const MODE_TIME = { alarm: (l) => 25 + l * 4, search: (l) => 18 + l * 5 };
const hot = () => W.mode === 'chase' || W.mode === 'search';
let spawnT = 0, arrest = 0, shake = 0, robbing = null, robProg = 0, wonShown = false;
let cash = 0, bank = 0, dirty = 0, goods = 0;          // نقد قذر معك، نظيف في المخبأ، قذر في المخبأ، بضائع
const gun = { owned: false, drawn: false, ammo: MAG, reloadT: 0, cd: 0 };
let fenceRate = 0.8, fenceT = 0, launderAcc = 0, bustReason = '';
try { const sv = JSON.parse(localStorage.getItem('damar_save') || '{}'); bank = sv.bank || 0; dirty = sv.dirty || 0; } catch (e) { bank = 0; }
if (bank >= GOAL) wonShown = true;
const save = () => { try { localStorage.setItem('damar_save', JSON.stringify({ bank, dirty })); } catch (e) { /* بلا حفظ */ } };

const player = {
  pos: new THREE.Vector2(safe.x, safe.z), vel: new THREE.Vector2(), facing: 0, stamina: 1, car: null,
  H: makeHuman({ role: 'thief', bag: true, gear: true }),
  hp: 100, regenT: 0, masked: false, surrender: false,
};
player.H.g.visible = false;
scene.add(player.H.g);
const COP = { role: 'cop' };

const cam = { yaw: 0, pitch: 0.3, lastMouse: -10, orbit: 0 };

// المصابيح الأمامية لسيارة اللاعب وأضواء الشرطة (مُعدّة مسبقاً لتجنب إعادة تجميع الظلال)
const headlight = new THREE.SpotLight(0xfff1d6, 0, 70, 0.5, 0.55, 1.4);
const headTarget = new THREE.Object3D();
scene.add(headlight, headTarget); headlight.target = headTarget;
const copLights = [];
for (let i = 0; i < 4; i++) { const l = new THREE.PointLight(0xff0000, 0, 32, 1.5); scene.add(l); copLights.push(l); }
const muzzle = new THREE.PointLight(0xffc070, 0, 14, 2); scene.add(muzzle);
const tracers = [], bodies = [];
const TRACER_MAT = new THREE.LineBasicMaterial({ color: new THREE.Color(3, 2.2, 1), transparent: true, opacity: 0.9 });
function tracer(a, b) {
  const g = new THREE.BufferGeometry().setFromPoints([a, b]);
  const l = new THREE.Line(g, TRACER_MAT); scene.add(l); tracers.push({ l, t: 0.07 });
}

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
  const c = new Car(safe.x + safe.sx * 8, safe.z + 4, 0, { ai: 'parked', model: 'sedan_sports', accel: 12, max: 38 });
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
  if (W.mode !== 'chase') { // يتجه إلى مكان البلاغ ثم يمشّط الشوارع حوله
    if (!c.tgtN) { c.tgtN = nearestNode(c.pos.x, c.pos.y); c.prevN = null; }
    let tp = lanePoint(c.prevN, c.tgtN);
    if (Math.hypot(tp.x - c.pos.x, tp.z - c.pos.y) < 8) {
      const nx = pickNext(c, nearestNode(W.tx, W.tz)); c.prevN = c.tgtN; c.tgtN = nx; tp = lanePoint(c.prevN, c.tgtN);
    }
    const far = Math.hypot(W.tx - c.pos.x, W.tz - c.pos.y) > 60;
    c.input = steerTo(c, tp.x, tp.z, W.mode === 'alarm' && far ? 26 : 13, dt);
    return;
  }
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
  const o = { car: c, pos: new THREE.Vector2(c.pos.x + fz * 1.8, c.pos.y - fx * 1.8), vel: new THREE.Vector2(), H: makeHuman(COP), facing: c.h, ret: false, hp: 100, shootT: mr(1.2, 2.2) };
  scene.add(o.H.g); officers.push(o); c.officer = o;
}
function updateOfficers(dt) {
  for (const o of [...officers]) {
    if (!cars.includes(o.car)) { removeOfficer(o); continue; }
    const P = player.pos;
    const dP = dist2(o.pos, P.x, P.y);
    o.ret = W.mode !== 'chase' || state !== 'play' || (player.car && dP > 5);
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
    // من 3 نجوم فما فوق يطلق الضباط النار على اللص الراجل (إلا إن استسلم)
    if (!o.ret && W.mode === 'chase' && W.level >= 3 && !player.car && !player.surrender && state === 'play') {
      o.shootT -= dt;
      if (o.shootT <= 0 && dP < 24 && segHit(o.pos.x, o.pos.y, P.x, P.y, 1.5) >= 1) { o.shootT = mr(0.9, 1.7); copShoot(o, dP); }
    }
    if (o.ret && dist2(o.pos, o.car.pos.x, o.car.pos.y) < 2.7) { removeOfficer(o); o.car.exitCd = 5; }
  }
}
function copShoot(o, d) {
  const from = new THREE.Vector3(o.pos.x + Math.sin(o.facing) * 0.5, 1.4, o.pos.y + Math.cos(o.facing) * 0.5);
  const fast = player.vel.length() > 6;
  const hitP = clamp(0.55 - d * 0.012 - (fast ? 0.2 : 0), 0.12, 0.6);
  const hit = Math.random() < hitP;
  const to = new THREE.Vector3(player.pos.x + (hit ? 0 : mr(-1.6, 1.6)), hit ? 1.25 : mr(0.3, 2.2), player.pos.y + (hit ? 0 : mr(-1.6, 1.6)));
  tracer(from, to); muzzle.position.copy(from); muzzle.intensity = 40;
  sound.shot(0.6 * Math.max(0.25, 1 - d / 40));
  if (hit) playerHit(mr(8, 13));
}
function playerHit(dmg) {
  player.hp -= dmg; player.regenT = 0; shake = Math.max(shake, 0.35);
  ui.hurt.style.opacity = 0.75;
  if (player.hp <= 0) { player.hp = 0; bustReason = 'أُصبت وسقطت أرضاً.'; bust(); }
}
function downOfficer(o) {
  removeOfficer(o);
  scene.add(o.H.g);
  o.H.g.rotation.order = 'YXZ'; o.H.g.rotation.set(-Math.PI / 2, o.facing, 0); o.H.g.position.y = 0.2;
  o.H.actions[o.H.cur].stop();
  bodies.push({ H: o.H, t: 14 });
  if (o.car) o.car.exitCd = 2;
}
function shoot() {
  if (!gun.drawn || gun.cd > 0 || gun.reloadT > 0 || player.car || player.surrender) return;
  if (gun.ammo <= 0) { gun.reloadT = 1.4; return; }
  gun.ammo--; gun.cd = 0.24;
  const o = camera.position.clone(), dir = new THREE.Vector3(); camera.getWorldDirection(dir);
  const R = 90;
  let best = segHit(o.x, o.z, o.x + dir.x * R, o.z + dir.z * R, 2) * R, hit = null;
  if (dir.y < -1e-3) best = Math.min(best, -o.y / dir.y);
  const v = new THREE.Vector3();
  const minT = camera.position.distanceTo(new THREE.Vector3(player.pos.x, 1.4, player.pos.y)) + 0.4;
  // اختبار أسطوانة رأسية (جسم الشرطي أو السيارة): أقرب نقطة أفقياً ثم التحقق من الارتفاع
  const h2 = Math.hypot(dir.x, dir.z) || 1e-6;
  const test = (x, z, r, top) => {
    const t = ((x - o.x) * dir.x + (z - o.z) * dir.z) / (h2 * h2);
    if (t < minT || t > best) return -1;
    const px = o.x + dir.x * t, py = o.y + dir.y * t, pz = o.z + dir.z * t;
    return Math.hypot(px - x, pz - z) < r && py > 0 && py < top ? t : -1;
  };
  if (role !== 'cop') for (const q of officers) { const t = test(q.pos.x, q.pos.y, 0.45, 1.85); if (t > 0) { best = t; hit = q; } }
  let rHit = null;
  for (const r of robbers) { if (!r.H.g.visible || r.state === 'down' || r.state === 'arrested') continue; const t = test(r.pos.x, r.pos.y, 0.45, 1.85); if (t > 0) { best = t; rHit = r; hit = null; } }
  let carHit = null;
  for (const c of cars) { if (c === player.car) continue; const t = test(c.pos.x, c.pos.y, 1.5, 1.6); if (t > 0) { best = t; hit = null; rHit = null; carHit = c; } }
  const end = o.clone().addScaledVector(dir, best);
  const mz = new THREE.Vector3(); (player.H.gun || player.H.g).getWorldPosition(mz);
  tracer(mz, end); muzzle.position.copy(mz); muzzle.intensity = 60;
  sound.shot(1);
  if (rHit) {
    rHit.hp -= 50;
    if (rHit.hp <= 0) downRobber(rHit);
    else if (['rob', 'walk_in', 'walk_out'].includes(rHit.state)) rHit.state = 'flee_foot';
  } else if (hit) {
    hit.hp -= 50; hit.vel.set(0, 0);
    if (hit.hp <= 0) { downOfficer(hit); setWanted(Math.max(W.level + 1, 3), 'أسقطت شرطياً!', true); }
    else setWanted(Math.max(W.level, 3), 'أطلقت النار على شرطي!', true);
    W.lastSeen = 0;
  } else if (carHit && carHit.police) { setWanted(Math.max(W.level, 3), 'أطلقت النار على سيارة شرطة!', true); W.lastSeen = 0; }
  else {
    const heard = cars.some((c) => c.police && dist2(c.pos, player.pos.x, player.pos.y) < 90) || officers.some((q) => dist2(q.pos, player.pos.x, player.pos.y) < 60);
    if (heard) setWanted(Math.max(W.level, 2), W.mode === 'chase' ? '' : '🚨 سُمع إطلاق نار! الشرطة في الطريق');
  }
  if (gun.ammo <= 0) gun.reloadT = 1.4;
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
          if (other.police && -vrel > 9 && W.crimeCd <= 0) { setWanted(W.level + 1, 'اصطدمت بسيارة شرطة!', true); W.crimeCd = 4; }
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
  shot(v = 1) {
    if (!this.ctx) return;
    const s = this.ctx.createBufferSource(), g = this.ctx.createGain(), lp = this.ctx.createBiquadFilter(), t = this.ctx.currentTime;
    s.buffer = this.noise; s.playbackRate.value = 0.7; lp.type = 'lowpass'; lp.frequency.value = 2600;
    g.gain.setValueAtTime(0.55 * v, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.22);
    s.connect(lp); lp.connect(g); g.connect(this.master); s.start(t); s.stop(t + 0.25);
    this.beep(120, 0.12, 'sine', 0.25 * v);
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
  if (locked && gun.drawn) { shoot(); return; }
  if (!locked && canvas.requestPointerLock) { try { const p = canvas.requestPointerLock(); if (p && p.catch) p.catch(() => {}); } catch (e) { /* السحب يكفي */ } }
});
addEventListener('mouseup', () => { dragging = false; });
addEventListener('mousemove', (e) => {
  if (state !== 'play' || !(locked || dragging)) return;
  cam.yaw -= e.movementX * 0.0026;
  cam.pitch = clamp(cam.pitch + e.movementY * 0.002, gun.drawn ? -0.35 : -0.05, 1.1);
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
['cash', 'bank', 'goalFill', 'goalText', 'stars', 'wantedText', 'loseBar', 'loseFill', 'arrest', 'arrestFill', 'toast', 'progress', 'progLabel', 'progFill', 'hint', 'speedo', 'kmh', 'stamFill', 'stamWrap', 'goods', 'dirty', 'hpFill', 'weapon', 'maskTag', 'cross', 'hurt'].forEach((k) => (ui[k] = $(k)));
const uiCache = {};
const setText = (el, key, v) => { if (uiCache[key] !== v) { uiCache[key] = v; el.textContent = v; } };
let toastT = 0;
function toast(msg, color = '#fff') { ui.toast.textContent = msg; ui.toast.style.color = color; ui.toast.classList.add('show'); toastT = 2.6; }

// جريمة: ترفع شدة الاستجابة وتبلّغ الشرطة بمكانها. seen = شاهدتك الشرطة فتبدأ المطاردة فوراً
function becomeCriminal() {
  if (role !== 'civilian') return;
  role = 'criminal'; toast('🦹 أصبحت مجرماً — الشرطة ستلاحقك إن تعرّفت عليك', '#ff9b6b');
}
function setWanted(lvl, msg, seen = false) {
  if (role === 'cop') return;
  if (role === 'civilian') { becomeCriminal(); if (msg) setTimeout(() => toast(msg, '#ff6b6b'), 1600); msg = ''; }
  W.level = Math.max(W.level, clamp(lvl, 1, 5));
  if (msg) toast(msg, '#ff6b6b');
  if (seen) startChase();
  else if (W.mode !== 'chase') { W.tx = player.pos.x; W.tz = player.pos.y; if (W.mode !== 'search') { W.mode = 'alarm'; W.modeT = 0; } }
  for (const c of cars) if (c.ai === 'police' && !c.chase) { c.chase = true; c.tgtN = null; c.prevN = null; }
}
function startChase() {
  W.mode = 'chase'; W.lastSeen = 0; W.modeT = 0; W.level = Math.max(W.level, 1);
  W.tx = player.pos.x; W.tz = player.pos.y; W.car = player.car;
  for (const c of cars) if (c.ai === 'police' && !c.chase) { c.chase = true; c.tgtN = null; c.prevN = null; }
}
function clearWanted(msg) {
  W.mode = 'clean'; W.level = 0; W.lastSeen = 0; W.modeT = 0; W.car = null;
  if (msg) toast(msg, '#8fd3ff');
  for (const c of cars) if (c.ai === 'police') { c.chase = false; c.tgtN = null; c.prevN = null; }
}
// هل تتعرف عليك الشرطة إن رأتك؟ وجه مصوَّر، أو قناع، أو سلاح، أو سرقة جارية، أو حقيبة غنيمة قرب البلاغ، أو السيارة التي هربت بها
function recognizable() {
  if (role !== 'criminal') return false;
  if (W.id > 0 || robbing) return true;
  if (player.car) return player.car === W.car || player.car.police;
  return player.masked || gun.drawn || (W.mode !== 'clean' && cash + goods > 0);
}

function updateHUD(dt) {
  setText(ui.cash, 'cash', fmt(cash));
  setText(ui.bank, 'bank', fmt(bank));
  setText(ui.goods, 'goods', fmt(goods));
  setText(ui.dirty, 'dirty', fmt(dirty));
  ui.hpFill.style.width = player.hp + '%';
  ui.hpFill.style.background = player.hp < 35 ? '#ff3b3b' : '';
  setText(ui.weapon, 'wp', !gun.owned ? '' : gun.drawn ? (gun.reloadT > 0 ? '🔫 إعادة تعبئة…' : `🔫 ${gun.ammo} / ${MAG}`) : '🔫 في الحزام (Q)');
  setText(ui.maskTag, 'mk', player.surrender ? '🙌 مستسلم' : player.masked ? '🎭 مقنّع' : '');
  ui.cross.classList.toggle('hidden', !(gun.drawn && !player.car));
  ui.hurt.style.opacity = Math.max(0, parseFloat(ui.hurt.style.opacity || 0) - dt * 1.5);
  ui.goalFill.style.width = Math.min(100, (bank / GOAL) * 100) + '%';
  setText(ui.goalText, 'goal', `الهدف: ${fmt(GOAL)}`);
  const hiding = W.mode === 'chase' && W.lastSeen > 0.5;
  const ST = {
    clean: ['', ''],
    alarm: ['🚨 إنذار', 'الشرطة متجهة إلى مكان الجريمة — لا تعرفك بعد'],
    chase: ['🚔 مطارَد!', hiding ? 'اختفيت عن أنظارهم… استمر' : 'الشرطة تراك — اكسر خط الرؤية'],
    search: ['🔦 بحث', 'الشرطة تمشّط المنطقة — ابتعد وغيّر مظهرك'],
  }[W.mode];
  let cls = 'mode-' + W.mode + (hiding ? ' blink' : '');
  if (role === 'cop') {
    const act = robbers.filter((r) => !['down', 'arrested'].includes(r.state) && r.state !== 'drive_in');
    const robNow = act.find((r) => r.state === 'rob');
    ST[0] = '👮 شرطي'; cls = 'mode-cop';
    ST[1] = robNow ? `🚨 سرقة جارية: ${robNow.store.def.name}` : act.length ? `🏃 ${act.length} لص هارب — طاردهم` : 'لا بلاغات — قم بدورية في المدينة';
  } else if (W.mode === 'clean') { ST[0] = role === 'criminal' ? '🦹 مجرم' : '🙂 مدني'; ST[1] = role === 'criminal' ? 'الشرطة لا تعرفك الآن' : 'الشرطة لا تلاحق المدنيين'; cls = 'mode-' + role; }
  setText(ui.stars, 'st', ST[0]);
  ui.stars.className = cls;
  const idTxt = W.id > 0 ? `📷 وجهك معروف ${Math.floor(W.id / 60)}:${String(Math.floor(W.id % 60)).padStart(2, '0')}` : '';
  setText(ui.wantedText, 'wt', [ST[1], idTxt].filter(Boolean).join('\n'));
  const barK = W.mode === 'chase' ? (hiding ? W.lastSeen / 5 : -1) : W.mode === 'clean' ? -1 : W.modeT / MODE_TIME[W.mode](W.level);
  ui.loseBar.classList.toggle('hidden', barK < 0);
  if (barK >= 0) ui.loseFill.style.width = Math.min(1, barK) * 100 + '%';
  ui.arrest.classList.toggle('hidden', arrest <= 0.01);
  ui.arrestFill.style.width = arrest * 100 + '%';
  ui.speedo.classList.toggle('hidden', !player.car);
  ui.stamWrap.classList.toggle('hidden', !!player.car);
  if (player.car) setText(ui.kmh, 'kmh', String(Math.round(Math.abs(player.car.speed) * 3.6)));
  ui.stamFill.style.width = player.stamina * 100 + '%';
  ui.progress.classList.toggle('hidden', !robbing);
  if (robbing) { setText(ui.progLabel, 'pl', `جارٍ سرقة ${robbing.def.name}…`); ui.progFill.style.width = robProg * 100 + '%'; }
  else if (launderAcc > 0) { ui.progress.classList.remove('hidden'); setText(ui.progLabel, 'pl', `جارٍ الغسيل… ${fmt(launderAcc)} صارت نظيفة`); ui.progFill.style.width = Math.min(100, (launderAcc % 10000) / 100) + '%'; }
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
  if (W.mode === 'alarm' || W.mode === 'search') { // منطقة البلاغ / البحث
    const [ax, ay] = toMap(W.tx, W.tz), pr = (W.mode === 'alarm' ? 30 : 45) * s * (1 + Math.sin(time * 4) * 0.06);
    mctx.fillStyle = W.mode === 'alarm' ? 'rgba(255,50,50,.28)' : 'rgba(255,170,40,.22)';
    mctx.strokeStyle = W.mode === 'alarm' ? '#ff4040' : '#ffaa30'; mctx.lineWidth = 2 * MMD;
    mctx.beginPath(); mctx.arc(ax, ay, pr, 0, Math.PI * 2); mctx.fill(); mctx.stroke();
  }
  for (const r of robbers) { // اللصوص على خريطة الشرطي
    if (['down', 'arrested', 'drive_in'].includes(r.state)) continue;
    const vis = r.state === 'rob' || dist2(r.pos, P.x, P.y) < 110;
    if (vis) icon(r.pos.x, r.pos.y, (time * 5 | 0) % 2 ? '#ff2a2a' : '#ffffff', 5 * MMD, '', r.state === 'rob');
  }
  icon(safe.x, safe.z, '#3dff7a', 8 * MMD, 'H', true);
  icon(fence.x, fence.z, '#b26bff', 7 * MMD, 'F', goods > 0);
  icon(laundry.x, laundry.z, '#3dd8ff', 7 * MMD, 'L', cash + dirty > 0);
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
  let len = Math.hypot(mx, mz);
  if (player.surrender) { mx = mz = len = 0; }
  const sprint = K('ShiftLeft', 'ShiftRight') && len > 0 && player.stamina > 0.03;
  player.stamina = clamp(player.stamina + (sprint ? -dt / 7 : dt / 5), 0, 1);
  const spd = len > 0 ? (sprint ? 8.2 : 4.6) : 0;
  const tx = len > 0 ? (mx / len) * spd : 0, tz = len > 0 ? (mz / len) * spd : 0;
  const k = 1 - Math.exp(-10 * dt);
  player.vel.x += (tx - player.vel.x) * k; player.vel.y += (tz - player.vel.y) * k;
  player.pos.x += player.vel.x * dt; player.pos.y += player.vel.y * dt;
  const sp = player.vel.length();
  if (gun.drawn) player.facing += wrapA(cam.yaw - player.facing) * Math.min(1, dt * 20);
  else if (sp > 0.3) player.facing += wrapA(Math.atan2(player.vel.x, player.vel.y) - player.facing) * Math.min(1, dt * 12);
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
  for (const c of cars) { const d = dist2(c.pos, player.pos.x, player.pos.y); if (d < bd && !c.officer && c.ai !== 'robber') { bd = d; best = c; } }
  return best;
}
function policeSees(range = 60) {
  for (const c of cars) if (c.police && c.ai === 'police' && dist2(c.pos, player.pos.x, player.pos.y) < range && segHit(c.pos.x, c.pos.y, player.pos.x, player.pos.y, 2) >= 1) return true;
  return false;
}
function enterCar(c) {
  if (role === 'cop') { /* الشرطي يستخدم أي سيارة */ }
  else if (c.police) setWanted(W.level + 2, 'سرقت سيارة شرطة!', true);
  else if (c.ai === 'traffic' && policeSees()) setWanted(W.level + 1, 'الشرطة رأتك تسرق سيارة!', true);
  c.ai = 'player'; c.chase = false; player.car = c; robbing = null;
  if (gun.drawn) holster();
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
  if (role === 'cop') { copInteractions(dt); return; }
  if (!player.car) {
    if (near && nd < 3.2) {
      if (near.cooldown > 0) { hint = `${near.def.name} مغلق الآن — عُد بعد ${Math.ceil(near.cooldown)} ثانية`; robbing = null; }
      else if (keys.KeyE) {
        if (robbing !== near) {
          robbing = near; robProg = 0; becomeCriminal();
          if (player.masked) setWanted(near.def.heat, '🚨 انطلق جهاز الإنذار! الشرطة في الطريق');
          else { setWanted(near.def.heat, '📷 الكاميرات صوّرت وجهك! الشرطة ستعرفك أينما رأتك'); W.id = 150; }
        }
        robProg += dt / near.def.time;
        player.facing = -near.sx * Math.PI / 2;
        if (Math.floor(time * 2.5) !== Math.floor((time - dt) * 2.5)) sound.beep(1250, 0.1, 'square', 0.05);
        if (robProg >= 1) {
          const amt = Math.round(mr(near.def.value[0], near.def.value[1]) / 10) * 10;
          if (near.def.goods) goods += amt; else cash += amt;
          near.cooldown = near.def.cd; robbing = null; robProg = 0;
          setWanted(Math.min(5, Math.max(W.level, near.def.heat) + (near.def.heat >= 3 ? 1 : 0)));
          toast(near.def.goods ? `+ مجوهرات بقيمة ${fmt(amt)} — بعها عند المشتري (F)` : `+${fmt(amt)}  اهرب إلى المخبأ!`, '#7dff9e'); sound.cash();
        }
      } else {
        if (robbing) { toast('توقفت السرقة'); robbing = null; }
        hint = `اضغط مطولاً E لسرقة ${near.def.name}  (${fmt(near.def.value[0])} – ${fmt(near.def.value[1])})`;
      }
    } else if (robbing) { toast('ابتعدت — فشلت السرقة'); robbing = null; }
    if (dSafe < 3.6 && role === 'criminal' && cash === 0 && goods === 0) {
      hint = W.mode === 'clean' && W.id <= 0 ? 'اضغط C لتعود مدنياً (تتوقف الشرطة عن ملاحقتك)' : 'لا يمكنك اعتزال الإجرام وأنت مطلوب أو وجهك معروف';
      if (pressed.KeyC && W.mode === 'clean' && W.id <= 0) { role = 'civilian'; setMask(false); holster(); toast('🙂 عدت مدنياً', '#8fd3ff'); }
    } else if (dSafe < 3.6) {
      hint = cash > 0 ? `اضغط E لإخفاء ${fmt(cash)} في المخبأ (يبقى مالاً قذراً حتى تغسله)` : 'المخبأ — خبّئ المال المسروق هنا لتحميه من المصادرة';
      if (pressed.KeyE && cash > 0) {
        if (hot()) toast('الشرطة تلاحقك! تخلّص منها أولاً', '#ff6b6b');
        else { dirty += cash; toast(`تم إخفاء ${fmt(cash)} 💰 — اغسله في المغسلة (L)`, '#7dff9e'); cash = 0; save(); sound.cash(); }
      }
    }
    const dFence = dist2(P, fence.x, fence.z), dLaund = dist2(P, laundry.x, laundry.z);
    if (dFence < 3.6) {
      const offer = Math.round(goods * fenceRate / 10) * 10;
      hint = (goods > 0 ? `E بيع المجوهرات بـ ${fmt(offer)} (السعر اليوم ${Math.round(fenceRate * 100)}%)` : 'المشتري — يشتري المجوهرات المسروقة')
        + (gun.owned ? '' : `   ·   B شراء مسدس ${fmt(PISTOL_PRICE)}`);
      if ((pressed.KeyE && goods > 0) || (pressed.KeyB && !gun.owned)) {
        if (hot()) toast('المشتري لا يتعامل مع المطلوبين! اختفِ أولاً', '#ff6b6b');
        else if (pressed.KeyE) { cash += offer; goods = 0; toast(`بعت المجوهرات بـ ${fmt(offer)} نقداً`, '#7dff9e'); sound.cash(); }
        else if (cash + bank < PISTOL_PRICE) toast(`تحتاج ${fmt(PISTOL_PRICE)} لشراء المسدس`, '#ff6b6b');
        else {
          const fromCash = Math.min(cash, PISTOL_PRICE); cash -= fromCash; bank -= PISTOL_PRICE - fromCash; save();
          gun.owned = true; gun.ammo = MAG; toast('اشتريت مسدساً 🔫 — Q لإشهاره، نقرة يسار للإطلاق', '#ffd36b'); sound.cash();
        }
      }
    }
    if (dLaund < 3.6) {
      const avail = cash + dirty;
      hint = avail > 0 ? `اضغط مطولاً E لغسل ${fmt(avail)} (عمولة ${LAUNDER_FEE * 100}%) — المال النظيف وحده يُحتسب للهدف` : 'مغسلة النور — تغسل المال القذر مقابل عمولة';
      if (keys.KeyE && avail > 0) {
        if (hot()) { if (pressed.KeyE) toast('لا يمكنك الغسيل وأنت مطلوب', '#ff6b6b'); }
        else {
          let amt = Math.min(avail, dt * 9000);
          const fc = Math.min(cash, amt); cash -= fc; dirty -= amt - fc;
          bank += amt * (1 - LAUNDER_FEE); launderAcc += amt * (1 - LAUNDER_FEE);
          if (Math.floor(time * 3) !== Math.floor((time - dt) * 3)) sound.beep(660, 0.06, 'sine', 0.05);
          if (cash + dirty < 1) { cash = 0; dirty = 0; toast(`تم غسيل المال! +${fmt(launderAcc)} نظيف`, '#7dff9e'); sound.cash(); launderAcc = 0; save(); }
          if (bank >= GOAL && !wonShown) { wonShown = true; save(); setTimeout(() => setState('win'), 900); }
        }
      } else if (launderAcc > 0) { toast(`غسلت ${fmt(launderAcc)}`, '#7dff9e'); launderAcc = 0; save(); }
    } else if (launderAcc > 0) { launderAcc = 0; save(); }
    const car = nearestCar(3.6);
    if (car && !hint) hint = car.police && role !== 'cop' ? 'اضغط F لسرقة سيارة الشرطة (ستلاحقك فوراً)' : 'اضغط F لركوب السيارة';
    if (car && pressed.KeyF) enterCar(car);
  } else {
    if (near && nd < 7 && near.cooldown <= 0) hint = `انزل من السيارة (F) لسرقة ${near.def.name}`;
    if (dSafe < 7 && cash > 0) hint = 'انزل من السيارة (F) لإخفاء المال';
    if (dist2(P, fence.x, fence.z) < 7 && goods > 0) hint = 'انزل من السيارة (F) لبيع المجوهرات';
    if (dist2(P, laundry.x, laundry.z) < 7 && cash + dirty > 0) hint = 'انزل من السيارة (F) لغسل المال';
    if (pressed.KeyF) exitCar();
  }
  setText(ui.hint, 'hint', hint);
}

function wantedUpdate(dt) {
  W.crimeCd -= dt;
  if (role === 'cop') return;
  W.id = Math.max(0, W.id - dt);
  // هل تراك أي دورية أو ضابط الآن؟
  let seen = false;
  const P = player.pos, range = W.mode === 'chase' ? 65 : 45;
  for (const c of cars) {
    if (!(c.police && c.ai === 'police')) continue;
    const d = dist2(c.pos, P.x, P.y);
    if (d < 14 || (d < range && segHit(c.pos.x, c.pos.y, P.x, P.y, 2) >= 1)) { seen = true; break; }
  }
  if (!seen) for (const o of officers) if (dist2(o.pos, P.x, P.y) < 35 && segHit(o.pos.x, o.pos.y, P.x, P.y, 2) >= 1) { seen = true; break; }
  const known = seen && recognizable();
  if (W.mode === 'chase') {
    if (seen) { W.lastSeen = 0; W.tx = P.x; W.tz = P.y; if (player.car) W.car = player.car; }
    else if ((W.lastSeen += dt) > 5) { W.mode = 'search'; W.modeT = 0; toast('أفلتّ من أنظارهم — الشرطة تمشّط المنطقة', '#8fd3ff'); }
    return;
  }
  if (known && W.crimeCd <= 0) {
    const why = W.mode !== 'clean' ? 'الشرطة تعرّفت عليك! اهرب' : W.id > 0 ? 'الشرطة تعرّفت على وجهك!' : player.masked ? 'الشرطة اشتبهت بقناعك! انزعه (X) لتختلط بالناس' : gun.drawn ? 'الشرطة رأتك تشهر سلاحاً!' : 'الشرطة تعرّفت عليك! اهرب';
    toast(why, '#ff6b6b'); startChase(); W.crimeCd = 2; return;
  }
  if (W.mode === 'alarm' || W.mode === 'search') {
    if ((W.modeT += dt) > MODE_TIME[W.mode](W.level)) clearWanted(W.mode === 'search' ? 'تخلّصت من الشرطة! 😎' : 'انتهى البلاغ — الشرطة غادرت المكان');
  }
}
function policeManager(dt) {
  spawnT -= dt;
  const pol = cars.filter((c) => c.ai === 'police');
  if (pol.length < POLICE_TARGET[W.level] && spawnT <= 0) { spawnPolice(W.mode !== 'clean'); spawnT = W.mode === 'chase' ? 2.2 : W.mode !== 'clean' ? 4 : 8; }
  if (W.mode === 'clean' && pol.length > 2) {
    for (const c of pol.slice(2)) if (dist2(c.pos, player.pos.x, player.pos.y) > 80 || state !== 'play') removeCar(c);
  }
}
function arrestUpdate(dt) {
  let rate = 0;
  if (W.mode === 'chase') {
    const P = player.pos;
    if (!player.car) {
      for (const o of officers) if (!o.ret && dist2(o.pos, P.x, P.y) < (player.surrender ? 3 : 1.8)) rate += player.surrender ? 1.5 : 0.75;
      if (player.surrender) for (const c of cars) if (c.ai === 'police' && c.chase && dist2(c.pos, P.x, P.y) < 14) rate += 0.4;
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
  const keep = player.surrender ? Math.round(cash * 0.5 / 10) * 10 : 0;
  const lost = [];
  if (cash - keep > 0) lost.push(`${fmt(cash - keep)} نقداً`);
  if (goods > 0) lost.push(`مجوهرات بقيمة ${fmt(goods)}`);
  if (gun.owned) lost.push('مسدسك');
  $('bustText').textContent = (bustReason ? bustReason + ' ' : '') + (player.surrender ? 'استسلمت فخفّفوا عنك: احتفظت بنصف نقودك. ' : '')
    + (lost.length ? `صادرت الشرطة: ${lost.join('، ')}.` : 'لم يكن معك شيء هذه المرة.') + ' ما في المخبأ بأمان.';
  cash = keep; goods = 0; gun.owned = false; arrest = 0; robbing = null; bustReason = '';
  sound.beep(220, 0.5, 'sawtooth', 0.12); sound.beep(165, 0.7, 'sawtooth', 0.12, 0.3);
  setState('busted');
}
function respawn() {
  if (player.car) { player.car.speed = 0; player.car.vel.set(0, 0); exitCar(); }
  clearWanted(); W.id = 0;
  for (const o of [...officers]) removeOfficer(o);
  for (const c of cars.filter((c) => c.ai === 'police')) { c.chase = false; c.tgtN = null; c.prevN = null; }
  for (const c of cars.filter((c) => c.ai === 'police').slice(2)) removeCar(c);
  player.pos.set(safe.x, safe.z); player.vel.set(0, 0);
  player.facing = safe.sx * Math.PI / 2; cam.yaw = player.facing;
  player.H.g.visible = true;
  player.hp = 100; player.surrender = false; holster(); setMask(false);
  for (const b of bodies.splice(0)) scene.remove(b.H.g);
}
// وضعيات الذراعين فوق الحركة: رفع اليدين عند الاستسلام، ومدّ اليد اليمنى عند التصويب
const qTmp = new THREE.Quaternion(), qW = new THREE.Quaternion(), vAxis = new THREE.Vector3();
function aimBone(b, worldDir, k = 1) { // يدير العظمة حتى يشير محورها Y نحو اتجاه عالمي
  if (!b) return;
  b.parent.getWorldQuaternion(qW);
  const cur = new THREE.Vector3(0, 1, 0).applyQuaternion(b.getWorldQuaternion(qTmp)).normalize();
  const want = worldDir.clone().normalize();
  const delta = new THREE.Quaternion().setFromUnitVectors(cur, want);
  const target = delta.multiply(qTmp);           // الدوران العالمي المطلوب
  const local = qW.clone().invert().multiply(target);
  b.quaternion.slerp(local, k);
}
function handsUp(H) { aimBone(H.arms.L, vAxis.set(-0.25, 1, 0)); aimBone(H.arms.R, vAxis.set(0.25, 1, 0)); }
function poseArms() {
  if (player.surrender) handsUp(player.H);
  else if (gun.drawn) { const d = new THREE.Vector3(); camera.getWorldDirection(d); aimBone(player.H.arms.R, d); }
}
function holster() { gun.drawn = false; if (player.H.gun) player.H.gun.visible = false; }
function setMask(on) { player.masked = on; if (player.H.mask) player.H.mask.visible = on; }
function gearKeys() {
  if (player.car) return;
  if (role === 'cop') { if (pressed.KeyX) toast('الشرطي لا يلبس قناعاً'); }
  else if (pressed.KeyX && !player.surrender) { if (!player.masked) becomeCriminal(); setMask(!player.masked); toast(player.masked ? '🎭 لبست القناع — لن تتعرف عليك الكاميرات' : 'نزعت القناع'); }
  if (pressed.KeyQ && !player.surrender) {
    if (!gun.owned) toast(`لا تملك سلاحاً — اشترِه من المشتري (F) بـ ${fmt(PISTOL_PRICE)}`, '#ffb36b');
    else { gun.drawn = !gun.drawn; if (gun.drawn) becomeCriminal(); if (player.H.gun) player.H.gun.visible = gun.drawn; cam.lastMouse = time; }
  }
  if (pressed.KeyZ) {
    if (player.surrender) { player.surrender = false; toast('تراجعت عن الاستسلام'); }
    else if (W.mode === 'chase') { player.surrender = true; holster(); robbing = null; toast('🙌 استسلمت — ستحتفظ بنصف نقودك', '#ffd36b'); }
    else toast('لا أحد يلاحقك لتستسلم');
  }
}

// ------------------------------------------------------------------ دور الشرطي: لصوص يتحكم بهم الكمبيوتر
// اللص يصل بسيارة، ينزل ويسرق متجراً (بلاغ يصل إليك)، ثم يعود إلى سيارته ويهرب.
// أوقف سيارته فينزل ويركض، وعندها اقترب واعتقله (E مطولاً) أو أسقطه بالمسدس.
const robbers = [];
let robberT = 6, copArrest = null, copArrestT = 0, sirenOn = false;
const ROBBER_MAX = 2;
function nodeFarFrom(x, z) {
  let best = null, bd = -1;
  for (let i = 0; i <= N; i++) for (let j = 0; j <= N; j++) {
    const n = nodePos(i, j), d = Math.hypot(n.x - x, n.z - z) + Math.random() * 40;
    if (d > bd) { bd = d; best = { i, j }; }
  }
  return best;
}
function routeTo(c, goal, finalPt, dt, maxV) { // قيادة عبر شبكة الشوارع إلى عقدة ثم إلى نقطة نهائية
  if (!c.tgtN) { c.tgtN = nearestNode(c.pos.x, c.pos.y); c.prevN = null; }
  if (finalPt && c.tgtN.i === goal.i && c.tgtN.j === goal.j && (c.atGoal || dist2(c.pos, nodePos(goal.i, goal.j).x, nodePos(goal.i, goal.j).z) < 10)) {
    c.atGoal = true;
    return steerTo(c, finalPt.x, finalPt.z, clamp(dist2(c.pos, finalPt.x, finalPt.z) * 0.9, 0, maxV), dt);
  }
  let tp = lanePoint(c.prevN, c.tgtN);
  if (Math.hypot(tp.x - c.pos.x, tp.z - c.pos.y) < 7) { const nx = pickNext(c, goal); c.prevN = c.tgtN; c.tgtN = nx; tp = lanePoint(c.prevN, c.tgtN); }
  return steerTo(c, tp.x, tp.z, maxV, dt);
}
function spawnRobber() {
  const open = stores.filter((st) => st.cooldown <= 0 && !robbers.some((r) => r.store === st) && dist2(player.pos, st.x, st.z) > 70);
  if (!open.length) return;
  const st = open[Math.floor(Math.random() * open.length)];
  const stop = { x: st.x + st.sx * 3.6, z: st.z };
  let c = null;
  for (let k = 0; k < 25 && !c; k++) {
    const i = Math.floor(Math.random() * (N + 1)), j = Math.floor(Math.random() * (N + 1)), n = nodePos(i, j);
    const d = Math.hypot(n.x - stop.x, n.z - stop.z);
    if (d > 110 && d < 260 && dist2(player.pos, n.x, n.z) > 60 && spaceFree(n.x, n.z, 10)) {
      c = new Car(n.x, n.z, Math.atan2(stop.x - n.x, stop.z - n.z), { ai: 'robber', model: ['sedan_sports', 'suv', 'hatchback_sports', 'van'][k % 4], accel: 11, max: 33 });
    }
  }
  if (!c) return;
  cars.push(c);
  const H = makeHuman({ role: 'thief', bag: true, gear: true });
  H.mask.visible = true; H.g.visible = false; scene.add(H.g);
  const r = { H, pos: new THREE.Vector2(c.pos.x, c.pos.y), vel: new THREE.Vector2(), facing: 0, car: c, store: st, stop,
    goal: nearestNode(stop.x, stop.z), state: 'drive_in', t: 0, hp: 100, armed: Math.random() < 0.4, shootT: 2, escT: 0,
    loot: 0, seen: false, stuckT: 0, lastP: new THREE.Vector2(), dirT: 0, dir: 0, name: ['أبو صقر', 'الثعلب', 'شبح', 'كوبرا', 'الذئب', 'نمر'][Math.floor(Math.random() * 6)] };
  c.robber = r; robbers.push(r);
}
function removeRobber(r) {
  scene.remove(r.H.g); robbers.splice(robbers.indexOf(r), 1);
  if (r.car && cars.includes(r.car)) { r.car.robber = null; if (r.car !== player.car) r.car.ai = 'parked'; }
}
function robberCarAI(c, dt) {
  const r = c.robber;
  if (!r) { c.input = { throttle: 0, steer: 0, brake: true, hand: false }; c.ai = 'parked'; return; }
  if (r.state === 'drive_in') {
    c.input = routeTo(c, r.goal, r.stop, dt, 16);
    if (dist2(c.pos, r.stop.x, r.stop.z) < 3.5) { // وصل: ينزل ويمشي إلى الباب
      c.input = { throttle: 0, steer: 0, brake: true, hand: false };
      r.state = 'walk_in'; r.pos.set(c.pos.x, c.pos.y); r.H.g.visible = true; c.ai = 'parked';
    }
  } else if (r.state === 'flee_car') {
    if (!r.fleeGoal || (r.fleeT -= dt) <= 0) { r.fleeGoal = nodeFarFrom(player.pos.x, player.pos.y); r.fleeT = 6; c.tgtN = null; }
    c.input = routeTo(c, r.fleeGoal, null, dt, 30);
    // سيارة متوقفة والشرطي قريب: يترجّل ويركض
    const near = dist2(c.pos, player.pos.x, player.pos.y) < 16;
    if (Math.abs(c.speed) < 2.2 && near) r.stuckT += dt; else r.stuckT = Math.max(0, r.stuckT - dt);
    if (r.stuckT > 1.6) {
      r.state = Math.random() < 0.3 ? 'surrender' : 'flee_foot';
      const fx = Math.sin(c.h), fz = Math.cos(c.h);
      r.pos.set(c.pos.x - fz * 1.9, c.pos.y + fx * 1.9); collideCircle(r.pos, 0.4, null);
      r.H.g.visible = true; c.ai = 'parked'; c.input = { throttle: 0, steer: 0, brake: true, hand: false };
      toast(r.state === 'surrender' ? `🙌 ${r.name} استسلم!` : `🏃 ${r.name} ترك السيارة وهرب راجلاً!`, '#ffd36b');
    }
  }
}
function robberShoot(r, d) {
  const from = new THREE.Vector3(r.pos.x, 1.4, r.pos.y);
  const hit = Math.random() < clamp(0.4 - d * 0.015, 0.1, 0.4);
  const to = new THREE.Vector3(player.pos.x + (hit ? 0 : mr(-1.5, 1.5)), hit ? 1.25 : mr(0.4, 2), player.pos.y + (hit ? 0 : mr(-1.5, 1.5)));
  tracer(from, to); muzzle.position.copy(from); muzzle.intensity = 40; sound.shot(0.6);
  if (hit) {
    player.hp -= mr(7, 12); player.regenT = 0; shake = 0.35; ui.hurt.style.opacity = 0.75;
    if (player.hp <= 0) { player.hp = 0; toast('أُصبت! نُقلت إلى المستشفى', '#ff6b6b'); respawn(); }
  }
}
function updateRobbers(dt) {
  if (state === 'play' && role === 'cop') {
    robberT -= dt;
    if (robberT <= 0 && robbers.length < ROBBER_MAX) { spawnRobber(); robberT = mr(25, 40); }
  }
  const P = player.pos;
  for (const r of [...robbers]) {
    const dP = dist2(r.pos, P.x, P.y);
    if (r.state === 'drive_in' || r.state === 'flee_car') {
      if (!cars.includes(r.car)) { removeRobber(r); continue; }
      r.pos.copy(r.car.pos);
    } else if (r.state !== 'down' && r.state !== 'arrested') {
      let tx = 0, tz = 0, spd = 0;
      if (r.state === 'walk_in') { tx = r.store.x; tz = r.store.z; spd = 3.8; if (dist2(r.pos, tx, tz) < 0.8) { r.state = 'rob'; r.t = 0; r.alarm = true;
        toast(`🚨 بلاغ: سرقة جارية في ${r.store.def.name}!`, '#ff6b6b'); sound.beep(1250, 0.25, 'square', 0.08); sound.beep(950, 0.25, 'square', 0.08, 0.3); } }
      else if (r.state === 'rob') {
        r.t += dt; r.facing = -r.store.sx * Math.PI / 2;
        if (dP < 14) { r.state = 'flee_foot'; toast(`${r.name} رآك وهرب!`, '#ffd36b'); }
        else if (r.t > r.store.def.time + 3) {
          r.loot = Math.round(mr(r.store.def.value[0], r.store.def.value[1]) / 10) * 10; r.store.cooldown = r.store.def.cd;
          r.state = cars.includes(r.car) ? 'walk_out' : 'flee_foot';
        }
      } else if (r.state === 'walk_out') {
        if (r.car === player.car || !cars.includes(r.car)) { r.state = 'flee_foot'; continue; }
        tx = r.car.pos.x; tz = r.car.pos.y; spd = 6.2;
        if (dist2(r.pos, tx, tz) < 2.6) { r.state = 'flee_car'; r.H.g.visible = false; r.car.ai = 'robber'; r.car.tgtN = null; r.fleeGoal = null; r.stuckT = 0; }
      } else if (r.state === 'flee_foot') {
        spd = 6.3;
        if ((r.dirT -= dt) <= 0 || r.stuckT > 0.6) {
          const away = Math.atan2(r.pos.x - P.x, r.pos.y - P.y);
          r.dir = away + mr(-0.9, 0.9) + (r.stuckT > 0.6 ? mr(-1.5, 1.5) : 0); r.dirT = mr(1, 2.2); r.stuckT = 0;
        }
        tx = r.pos.x + Math.sin(r.dir) * 10; tz = r.pos.y + Math.cos(r.dir) * 10;
        if (gun.drawn && dP < 7 && Math.random() < dt * 0.35) { r.state = 'surrender'; toast(`🙌 ${r.name} رفع يديه!`, '#ffd36b'); }
        if (r.armed && dP < 16 && !player.car && (r.shootT -= dt) <= 0 && segHit(r.pos.x, r.pos.y, P.x, P.y, 1.5) >= 1) { r.shootT = mr(1.3, 2.2); robberShoot(r, dP); }
      }
      const dx = tx - r.pos.x, dz = tz - r.pos.y, d = Math.hypot(dx, dz);
      const wx = d > 0.3 && spd ? dx / d * spd : 0, wz = d > 0.3 && spd ? dz / d * spd : 0, k = 1 - Math.exp(-8 * dt);
      r.vel.x += (wx - r.vel.x) * k; r.vel.y += (wz - r.vel.y) * k;
      r.lastP.copy(r.pos);
      r.pos.x += r.vel.x * dt; r.pos.y += r.vel.y * dt;
      collideCircle(r.pos, 0.4, r.vel); pushFromCars(r.pos, 0.4, null);
      if (spd && r.pos.distanceTo(r.lastP) < spd * dt * 0.35) r.stuckT += dt;
      if (r.vel.length() > 0.3) r.facing = Math.atan2(r.vel.x, r.vel.y);
    }
    if (r.H.g.visible && r.state !== 'down') {
      r.H.g.position.set(r.pos.x, 0, r.pos.y); r.H.g.rotation.y = r.facing;
      animHuman(r.H, r.state === 'surrender' || r.state === 'arrested' ? 0 : r.vel.length(), dt, r.state === 'rob');
      if (r.state === 'surrender' || r.state === 'arrested') handsUp(r.H);
      r.H.bag.visible = r.loot > 0;
    }
    if (r.state === 'arrested' || r.state === 'down') { if ((r.t -= dt) <= 0) removeRobber(r); continue; }
    // الهروب الناجح: بعيد جداً عن الشرطي لمدة طويلة
    if (r.state === 'flee_car' || r.state === 'flee_foot') {
      if (dP > 230) r.escT += dt; else r.escT = 0;
      if (r.escT > 20) { toast(`💨 ${r.name} أفلت منك`, '#ff9b6b'); removeRobber(r); }
    }
  }
}
function copReward(r, how) {
  const pay = how === 'arrest' ? 2000 + Math.round(r.loot * 0.3) : 800;
  bank += pay; save(); sound.cash();
  toast(how === 'arrest' ? `🚔 اعتقلت ${r.name}! مكافأة ${fmt(pay)}` : `أسقطت ${r.name} — مكافأة ${fmt(pay)}`, '#7dff9e');
  if (bank >= GOAL && !wonShown) { wonShown = true; setTimeout(() => setState('win'), 900); }
}
function downRobber(r) {
  r.state = 'down'; r.t = 14;
  r.H.g.rotation.order = 'YXZ'; r.H.g.rotation.set(-Math.PI / 2, r.facing, 0); r.H.g.position.y = 0.2;
  r.H.actions[r.H.cur].stop();
  copReward(r, 'down');
}
function copInteractions(dt) {
  let hint = '';
  const P = player.pos;
  if (!player.car) {
    let tgt = null, td = 2.6;
    for (const r of robbers) { if (!r.H.g.visible || ['down', 'arrested'].includes(r.state)) continue; const d = dist2(r.pos, P.x, P.y); if (d < td) { td = d; tgt = r; } }
    if (tgt) {
      hint = `اضغط مطولاً E لاعتقال ${tgt.name}`;
      if (keys.KeyE) {
        if (copArrest !== tgt) { copArrest = tgt; copArrestT = 0; }
        copArrestT += dt * (tgt.state === 'surrender' ? 1.6 : 0.8);
        if (tgt.state !== 'surrender') tgt.vel.multiplyScalar(0.5);   // تمسكه فيتباطأ
        if (copArrestT >= 1) { tgt.state = 'arrested'; tgt.t = 3; copArrest = null; copReward(tgt, 'arrest'); }
      } else copArrest = null;
    } else copArrest = null;
    const car = nearestCar(3.6);
    if (car && !hint) hint = car.police ? 'اضغط F لركوب سيارة الدورية' : 'اضغط F لاستخدام السيارة';
    if (car && pressed.KeyF) enterCar(car);
  } else {
    if (player.car.police) hint = sirenOn ? '' : 'H لتشغيل صفارة الإنذار';
    if (pressed.KeyF) exitCar();
  }
  setText(ui.hint, 'hint', hint);
}
function setRole(r) {
  role = r;
  for (const x of [...robbers]) removeRobber(x);
  scene.remove(player.H.g);
  player.H = makeHuman({ role: r === 'cop' ? 'cop' : 'thief', bag: r !== 'cop', gear: true });
  scene.add(player.H.g);
  gun.owned = r === 'cop'; gun.ammo = MAG; sirenOn = false; robberT = 6;
  clearWanted(); W.id = 0;
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
  if (!c && gun.drawn) { // تصويب من فوق الكتف: مركز الشاشة = اتجاه الرصاصة
    const fx = Math.sin(cam.yaw), fz = Math.cos(cam.yaw), ap = cam.pitch * 0.9 - 0.18;
    const dir = new THREE.Vector3(fx * Math.cos(ap), -Math.sin(ap), fz * Math.cos(ap));
    const bx = tx - fz * 0.7, bz = tz + fx * 0.7;
    let ox = -dir.x * 2.6, oz = -dir.z * 2.6;
    const t = segHit(tx, tz, bx + ox, bz + oz, 2.5, 0.35);
    if (t < 1) { const k = Math.max(0.1, t - 0.05); ox *= k; oz *= k; }
    const want = new THREE.Vector3(bx + ox, Math.max(0.6, 1.75 - dir.y * 2.6), bz + oz);
    camera.position.lerp(want, 1 - Math.exp(-dt * 22));
    camera.lookAt(camera.position.clone().addScaledVector(dir, 40));
    if (Math.abs(camera.fov - 50) > 0.05) { camera.fov += (50 - camera.fov) * Math.min(1, dt * 8); camera.updateProjectionMatrix(); }
    return;
  }
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
    else if (c.ai === 'robber') robberCarAI(c, dt);
    else if (c.ai === 'parked') c.input = { throttle: 0, steer: 0, brake: true, hand: false };
  }
  for (const c of cars) c.physics(dt);
  carCollisions();
  for (const c of cars) { const imp = c.collideWorld(); if (c === player.car && imp > 6) crashFx(imp); }
  updateOfficers(dt);
  updateRobbers(dt);
  for (const c of cars) c.sync(dt);
  for (let i = tracers.length - 1; i >= 0; i--) { const t = tracers[i]; if ((t.t -= dt) <= 0) { scene.remove(t.l); t.l.geometry.dispose(); tracers.splice(i, 1); } }
  for (let i = bodies.length - 1; i >= 0; i--) if ((bodies[i].t -= dt) <= 0) { scene.remove(bodies[i].H.g); bodies.splice(i, 1); }
  muzzle.intensity = Math.max(0, muzzle.intensity - dt * 900);
  policeManager(dt);
  for (const s of stores) s.cooldown = Math.max(0, s.cooldown - dt);
}
function update(dt) {
  if (pressed.KeyR) { rainOn = !rainOn; toast(rainOn ? 'المطر: تشغيل' : 'المطر: إيقاف'); }
  if (pressed.KeyM) { sound.toggle(); toast(sound.muted ? 'الصوت: مكتوم' : 'الصوت: تشغيل'); }
  if (pressed.KeyH && role === 'cop' && player.car && player.car.police) { sirenOn = !sirenOn; toast(sirenOn ? '🚨 الصفارة: تشغيل' : 'الصفارة: إيقاف'); }
  else if (pressed.KeyH) { sound.beep(392, 0.35, 'sawtooth', 0.07); sound.beep(494, 0.35, 'sawtooth', 0.05); }
  if (player.car) updateDriving(); else updateOnFoot(dt);
  worldUpdate(dt);
  if (player.car) player.pos.copy(player.car.pos);
  else {
    collideCircle(player.pos, 0.4, player.vel);
    pushFromCars(player.pos, 0.4, null);
    player.H.g.position.set(player.pos.x, 0, player.pos.y);
    player.H.g.rotation.y = player.facing;
    animHuman(player.H, player.vel.length(), dt, !!robbing);
    if (player.H.bag) {
      player.H.bag.visible = cash + goods > 0;
      const bs = 0.7 + Math.min((cash + goods) / 60000, 1) * 0.8; player.H.bag.scale.set(bs, bs, bs);
    }
    poseArms();
  }
  interactions(dt);
  gearKeys();
  wantedUpdate(dt);
  arrestUpdate(dt);
  // السلاح والصحة وسعر المشتري
  gun.cd -= dt;
  if (gun.reloadT > 0 && (gun.reloadT -= dt) <= 0) { gun.ammo = MAG; sound.beep(900, 0.05, 'square', 0.05); }
  player.regenT += dt;
  if (player.regenT > 5) player.hp = Math.min(100, player.hp + dt * 6);
  if ((fenceT -= dt) <= 0) { fenceT = 45; fenceRate = Math.round(mr(0.55, 1.0) * 100) / 100; }
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
$('copBtn').onclick = () => {
  sound.init(); setRole('cop'); respawn(); setState('play'); lockPointer();
  toast('👮 أنت شرطي: انتظر البلاغات (🚨) وطارد اللصوص', '#8fd3ff');
};
$('roleBtn').onclick = () => setState('menu');
$('startBtn').onclick = () => {
  sound.init(); setRole('civilian'); respawn(); setState('play'); lockPointer();
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
  if (sirenOn && player.car && state === 'play') siren = 1;
  else if (W.mode !== 'clean' && state === 'play') for (const c of cars) if (c.police && c.chase) siren = Math.max(siren, Math.pow(Math.max(0, 1 - dist2(c.pos, player.pos.x, player.pos.y) / 140), 1.5));
  sound.update(state === 'play' ? siren : 0, player.car ? Math.abs(player.car.speed) : 0, player.car ? Math.max(0, player.car.input.throttle) : 0, rainOn && state !== 'menu');
  for (const k in pressed) delete pressed[k];
  composer.render();
}
$('loading').remove();
loop();

// واجهة صغيرة للاختبار والتطوير من الطرفية
window.__damar = { step(n, dt = 0.05) { for (let i = 0; i < n && state === 'play'; i++) { time += dt; update(dt); for (const k in pressed) delete pressed[k]; } }, get cash() { return cash; }, get bank() { return bank; }, get arrest() { return arrest; }, get goods() { return goods; }, get dirty() { return dirty; }, set cash(v) { cash = v; }, set goods(v) { goods = v; }, gun, fence, laundry, shoot, bodies, get fenceRate() { return fenceRate; }, officers, player, cars, stores, safe, W, get state() { return state; }, robbers, setRole, get role() { return role; }, spawnRobber, setState, keys, pressed, cam, setWanted, clearWanted, startChase };
