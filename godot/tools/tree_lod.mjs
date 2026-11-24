// الاستخدام: npm i @gltf-transform/core@4 @gltf-transform/extensions@4 @gltf-transform/functions@4 meshoptimizer@0.22
// node tools/tree_lod.mjs in.gltf out.gltf [keepEveryLeaf=22] [branchRatio=0.15]
// يحوّل شجرة سينمائية (ملايين المثلثات) إلى نسخة ألعاب: تقليل أوراق ذكي + تبسيط الأغصان.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { simplify, weld, prune, dedup } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
const [inp, out, keepEvery, branchRatio] = [process.argv[2], process.argv[3], +(process.argv[4] || 8), +(process.argv[5] || 0.06)];
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(inp);
for (const mesh of doc.getRoot().listMeshes()) {
  for (const prim of mesh.listPrimitives()) {
    for (const s of ['COLOR_0', 'COLOR_1']) { const a = prim.getAttribute(s); if (a) prim.setAttribute(s, null); }
    const mat = prim.getMaterial();
    if (!mat.getName().includes('leaves')) continue;
    mat.setAlphaMode('MASK').setAlphaCutoff(0.45);
    const idx = prim.getIndices().getArray();
    const pos = prim.getAttribute('POSITION');
    const P = pos.getArray();
    // كل ورقة = مربع من مثلثين متتاليين. نحتفظ بواحدة من كل keepEvery ونكبّرها حول مركزها.
    const kept = [];
    const scale = Math.sqrt(keepEvery) * 0.92;
    const touched = new Set();
    for (let q = 0; q < idx.length / 6; q++) {
      if (q % keepEvery !== 0) continue;
      const tri = Array.from(idx.slice(q * 6, q * 6 + 6));
      const verts = [...new Set(tri)];
      let cx = 0, cy = 0, cz = 0;
      for (const v of verts) { cx += P[v * 3]; cy += P[v * 3 + 1]; cz += P[v * 3 + 2]; }
      cx /= verts.length; cy /= verts.length; cz /= verts.length;
      for (const v of verts) {
        if (touched.has(v)) continue; touched.add(v);
        P[v * 3] = cx + (P[v * 3] - cx) * scale; P[v * 3 + 1] = cy + (P[v * 3 + 1] - cy) * scale; P[v * 3 + 2] = cz + (P[v * 3 + 2] - cz) * scale;
      }
      kept.push(...tri);
    }
    pos.setArray(P);
    // ضغط الرؤوس: نبني مصفوفات جديدة تحوي الرؤوس المستخدمة فقط
    const remap = new Map(); const order = [];
    for (const v of kept) if (!remap.has(v)) { remap.set(v, order.length); order.push(v); }
    for (const sem of prim.listSemantics()) {
      const acc = prim.getAttribute(sem); const n = acc.getElementSize(); const src = acc.getArray();
      const dst = new src.constructor(order.length * n);
      order.forEach((v, i) => { for (let k = 0; k < n; k++) dst[i * n + k] = src[v * n + k]; });
      const nacc = doc.createAccessor().setType(acc.getType()).setArray(dst).setBuffer(acc.getBuffer());
      prim.setAttribute(sem, nacc);
    }
    prim.getIndices().setArray(new Uint32Array(kept.map(v => remap.get(v))));
    console.log('leaves quads', idx.length / 6, '->', kept.length / 6);
  }
}
await MeshoptSimplifier.ready;
function compact(prim, newIdx) {
  const remap = new Map(); const order = [];
  for (const v of newIdx) if (!remap.has(v)) { remap.set(v, order.length); order.push(v); }
  for (const sem of prim.listSemantics()) {
    const acc = prim.getAttribute(sem); const n = acc.getElementSize(); const src = acc.getArray();
    const dst = new src.constructor(order.length * n);
    order.forEach((v, i) => { for (let k = 0; k < n; k++) dst[i * n + k] = src[v * n + k]; });
    prim.setAttribute(sem, doc.createAccessor().setType(acc.getType()).setArray(dst).setBuffer(acc.getBuffer()));
  }
  prim.getIndices().setArray(new Uint32Array(Array.from(newIdx, v => remap.get(v))));
}
for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) {
  const name = p.getMaterial().getName();
  if (name.includes('leaves')) continue;
  const ratio = name.includes('trunk') ? 0.35 : branchRatio;
  const idx = new Uint32Array(p.getIndices().getArray());
  const pos = new Float32Array(p.getAttribute('POSITION').getArray());
  const target = Math.floor(idx.length / 3 * ratio);
  // مكوّنات متصلة (اتحاد-بحث) بالرؤوس المتطابقة موضعياً
  const key = (v) => `${Math.round(pos[v*3]*1e3)},${Math.round(pos[v*3+1]*1e3)},${Math.round(pos[v*3+2]*1e3)}`;
  const canon = new Map(); const vc = new Uint32Array(pos.length / 3);
  for (let v = 0; v < vc.length; v++) { const k = key(v); if (!canon.has(k)) canon.set(k, v); vc[v] = canon.get(k); }
  const parent = new Uint32Array(vc.length).map((_, i) => i);
  const find = (x) => { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; };
  for (let t = 0; t < idx.length; t += 3) { const a = find(vc[idx[t]]), b = find(vc[idx[t+1]]), c = find(vc[idx[t+2]]); parent[b] = a; parent[find(c)] = a; }
  const comps = new Map();
  for (let t = 0; t < idx.length; t += 3) { const r = find(vc[idx[t]]); if (!comps.has(r)) comps.set(r, []); comps.get(r).push(t); }
  const sorted = [...comps.values()].sort((x, y) => y.length - x.length);
  const keep = []; let tri = 0;
  for (const c of sorted) { if (tri >= target) break; for (const t of c) keep.push(idx[t], idx[t+1], idx[t+2]); tri += c.length; }
  compact(p, new Uint32Array(keep));
  // تبسيط هندسي إضافي لما تبقى (الجذع والأغصان الرئيسية متصلة)
  const p2 = new Float32Array(p.getAttribute('POSITION').getArray());
  const cmap = new Map();
  const i2 = new Uint32Array(p.getIndices().getArray()).map((v) => {
    const k = `${Math.round(p2[v*3]*1e3)},${Math.round(p2[v*3+1]*1e3)},${Math.round(p2[v*3+2]*1e3)}`;
    if (!cmap.has(k)) cmap.set(k, v); return cmap.get(k); });
  const goal = name.includes('trunk') ? 15000 : 40000;
  const [res, err] = MeshoptSimplifier.simplify(i2, p2, 3, Math.min(i2.length, goal * 3), 0.08, []);
  console.log('  simplify', name, i2.length/3, '->', res.length/3, 'err', err);
  compact(p, res);
  if (p.getIndices().getCount() / 3 > goal * 1.3) {
    // تجميع الرؤوس في شبكة (Vertex Clustering) عندما يفشل التبسيط التقليدي
    const P3 = new Float32Array(p.getAttribute('POSITION').getArray());
    const I3 = p.getIndices().getArray();
    let cellSize = 0.02, out = I3;
    for (let it = 0; it < 12 && out.length / 3 > goal; it++, cellSize *= 1.4) {
      const rep = new Map(); const map = new Uint32Array(P3.length / 3);
      for (let v = 0; v < map.length; v++) {
        const k = `${Math.floor(P3[v*3]/cellSize)},${Math.floor(P3[v*3+1]/cellSize)},${Math.floor(P3[v*3+2]/cellSize)}`;
        if (!rep.has(k)) rep.set(k, v); map[v] = rep.get(k);
      }
      const o = []; const seen = new Set();
      for (let t = 0; t < I3.length; t += 3) {
        const a = map[I3[t]], b = map[I3[t+1]], c = map[I3[t+2]];
        if (a === b || b === c || a === c) continue;
        const key = [a, b, c].sort((x, y) => x - y).join(',');
        if (seen.has(key)) continue; seen.add(key);
        o.push(a, b, c);
      }
      out = o;
    }
    compact(p, new Uint32Array(out));
    console.log('  clustered', name, '->', p.getIndices().getCount() / 3, 'cell', cellSize.toFixed(3));
  }
  console.log(name, idx.length / 3, '->', p.getIndices().getCount() / 3);
}
await doc.transform(prune(), dedup());
await io.write(out, doc);
