#!/usr/bin/env node
/**
 * LionFit GLB inspector.
 *
 *   node tool/inspect_glb.js assets/muscleAnatomy.glb
 *
 * Prints the facts that matter for the muscle-intensity map: rendered triangle
 * count (node instances, not unique meshes), the colorable muscle groups keyed
 * by material name, how much of the budget is non-colorable filler, and the
 * byte breakdown of the binary chunk.
 *
 * Re-run this after any Blender re-export or decimation pass to confirm the
 * node and material names the app depends on survived.
 */
'use strict';
const fs = require('fs');

const NEUTRAL_MATERIAL = 'body_neutral';
const path = process.argv[2] || 'assets/muscleAnatomy.glb';

if (!fs.existsSync(path)) {
  console.error(`not found: ${path}`);
  process.exit(1);
}

const buf = fs.readFileSync(path);
if (buf.toString('ascii', 0, 4) !== 'glTF') {
  console.error(`${path} is not a binary glTF (.glb)`);
  process.exit(1);
}

let off = 12;
let gltf = null;
let binBytes = 0;
while (off < buf.length) {
  const len = buf.readUInt32LE(off);
  const type = buf.toString('ascii', off + 4, off + 8);
  if (type.startsWith('JSON')) gltf = JSON.parse(buf.toString('utf8', off + 8, off + 8 + len));
  else binBytes = len;
  off += 8 + len;
}

const mib = (n) => `${(n / 1048576).toFixed(2)} MiB`;
const sizeLine = (n) => `${mib(n)} (${n.toLocaleString('en-US')} bytes)`;
const num = (n) => n.toLocaleString('en-US');

const trisOf = (mesh) =>
  (mesh.primitives || []).reduce((sum, p) => {
    const acc = p.indices != null ? gltf.accessors[p.indices] : gltf.accessors[p.attributes.POSITION];
    return sum + Math.floor(acc.count / 3);
  }, 0);

const materialNameOf = (p) =>
  p.material != null ? gltf.materials[p.material].name || `material_${p.material}` : '(none)';

console.log(`file         : ${path}`);
console.log(`size         : ${sizeLine(buf.length)}`);
console.log(`bin chunk    : ${sizeLine(binBytes)}`);
console.log(`generator    : ${gltf.asset && gltf.asset.generator}`);
console.log(`extensions   : ${JSON.stringify(gltf.extensionsUsed || [])}`);

// ---- triangles: rendered counts instances, unique counts meshes once -------
let rendered = 0;
let unique = 0;
const seen = new Set();
const perMaterial = Object.create(null);

for (const node of gltf.nodes || []) {
  if (node.mesh == null) continue;
  const mesh = gltf.meshes[node.mesh];
  const t = trisOf(mesh);
  rendered += t;
  if (!seen.has(node.mesh)) {
    seen.add(node.mesh);
    unique += t;
  }
  for (const p of mesh.primitives || []) {
    const name = materialNameOf(p);
    const acc = p.indices != null ? gltf.accessors[p.indices] : gltf.accessors[p.attributes.POSITION];
    perMaterial[name] = (perMaterial[name] || 0) + Math.floor(acc.count / 3);
  }
}

console.log(`\nunique mesh triangles : ${num(unique)}`);
console.log(`RENDERED triangles    : ${num(rendered)}   <- the number that costs you frames`);

// ---- colorable groups -----------------------------------------------------
const entries = Object.entries(perMaterial).sort((a, b) => b[1] - a[1]);
let neutral = 0;
let muscle = 0;
console.log(`\ntriangles per material (material name == muscle group key):`);
for (const [name, t] of entries) {
  const isNeutral = name === NEUTRAL_MATERIAL;
  if (isNeutral) neutral += t;
  else muscle += t;
  console.log(`  ${name.padEnd(16)} ${num(t).padStart(9)}${isNeutral ? '   <- not colorable' : ''}`);
}
const totalMat = muscle + neutral;
console.log(`\n  colorable : ${num(muscle)} (${((100 * muscle) / totalMat).toFixed(0)}%)`);
console.log(`  filler    : ${num(neutral)} (${((100 * neutral) / totalMat).toFixed(0)}%)`);

const groups = Object.keys(perMaterial).filter((k) => k !== NEUTRAL_MATERIAL && k !== '(none)').sort();
console.log(`\n${groups.length} colorable muscle groups:`);
console.log(`  ${groups.join(', ')}`);

// ---- node naming contract -------------------------------------------------
const nodeNames = (gltf.nodes || []).filter((n) => n.mesh != null).map((n) => n.name || '(unnamed)');
const bad = [];
for (const g of groups) {
  const hasPlain = nodeNames.includes(g);
  const hasPair = nodeNames.includes(`${g}_l`) && nodeNames.includes(`${g}_r`);
  if (!hasPlain && !hasPair) bad.push(g);
}
console.log(`\nnode naming: ${bad.length === 0 ? 'every group resolves as <group> or <group>_l/<group>_r' : 'BROKEN for -> ' + bad.join(', ')}`);
if (bad.length) {
  console.log('  node names present:');
  console.log('   ', nodeNames.join(', '));
}

// ---- render flags ---------------------------------------------------------
const notDouble = (gltf.materials || []).filter((m) => !m.doubleSided).map((m) => m.name);
const mirrored = (gltf.nodes || []).filter((n) => n.scale && n.scale[0] * n.scale[1] * n.scale[2] < 0);
console.log(`\nmirrored nodes (negative scale, winding flips): ${mirrored.length}`);
console.log(`materials missing doubleSided                 : ${notDouble.length ? notDouble.join(', ') : 'none'}`);
if (mirrored.length && notDouble.length) {
  console.log('  WARNING: mirrored geometry with single-sided material renders inside-out.');
}

// ---- byte breakdown -------------------------------------------------------
const bytes = Object.create(null);
for (const mesh of gltf.meshes || []) {
  for (const p of mesh.primitives || []) {
    for (const [attr, idx] of Object.entries(p.attributes || {})) {
      const bv = gltf.bufferViews[gltf.accessors[idx].bufferView];
      if (bv) bytes[attr] = (bytes[attr] || 0) + bv.byteLength;
    }
    if (p.indices != null) {
      const bv = gltf.bufferViews[gltf.accessors[p.indices].bufferView];
      if (bv) bytes.INDICES = (bytes.INDICES || 0) + bv.byteLength;
    }
  }
}
console.log('\nbin bytes by attribute:');
for (const [k, v] of Object.entries(bytes).sort((a, b) => b[1] - a[1])) {
  const waste = k === 'TEXCOORD_0' && (gltf.textures || []).length === 0 ? '   <- no textures use this; strippable' : '';
  console.log(`  ${k.padEnd(12)} ${mib(v)}${waste}`);
}
console.log(`\ntextures: ${(gltf.textures || []).length}   animations: ${(gltf.animations || []).length}   skins: ${(gltf.skins || []).length}`);
