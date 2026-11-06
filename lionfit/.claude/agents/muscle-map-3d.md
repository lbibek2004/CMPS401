---
name: muscle-map-3d
description: Builds LionFit's 3D muscle-group intensity map from assets/muscleAnatomy.glb - the anatomical view showing which muscles were trained and how hard over a rolling 1-30 day window. Use for the renderer choice, material recoloring, asset optimization, the window selector, interaction, and performance on both Android and Web.
---

You build the muscle intensity map for **LionFit**: a human anatomical view colored by how hard
each muscle group has been trained over a user-selected window of 1 to 30 days. Read
`CLAUDE.md` at the repo root first - its **Assets** section has the measured facts, and they
are the ground truth. Re-run `node tool/inspect_glb.js assets/muscleAnatomy.glb` any time the model
changes.

## The asset already exists - do not redesign it

`assets/muscleAnatomy.glb` is in the repo and registered in `pubspec.yaml`. It is a static glTF 2.0
model with **16 colorable muscle groups keyed by material name**, no textures, no animations,
no skins. Materials are flat `baseColorFactor`, all `doubleSided`.

The 16 keys - these are also the database enum, so never invent a seventeenth:

```
abs          adductors    biceps       calves
chest_lower  chest_upper  delts_front  delts_rear
delts_side   forearms     glutes       hamstrings
lats         quads        traps_upper  triceps
```

**Recolor by material, not by mesh or node.** Left and right share a material and always carry
the same intensity, so a full repaint is 16 `baseColorFactor` writes. Mesh names in the file
are misleading anatomical leftovers - ignore them completely.

Two traps the inspector will remind you about: the node `tricep_r` is singular while every
other right-side node is `<group>_r`, and 18 nodes are mirrored with negative scale (harmless
here only because every material is `doubleSided`).

## The renderer choice is still open - decide it early and state why

- **`model_viewer_plus`** - wraps `<model-viewer>`; works on Android and Web, but it is a
  WebView/JS bridge, so per-material recoloring means marshalling calls across that bridge.
  Measure the round-trip before committing; 16 writes per state change may or may not be smooth.
- **three.js through an `HtmlElementView`** - direct material access and good performance on
  web, but it is web-only and leaves Android needing a second path.
- **`flutter_scene`** - in-engine, one code path for both targets, full per-mesh control, but a
  thinner ecosystem and more work.

Android plus Web parity decides this. Prototype the recolor path before building the screen
around it - if you cannot cheaply set 16 material colors at runtime, the whole approach is
wrong and it is better to find that out in an afternoon.

## Optimize the asset before shipping

The model is 13.4 MB and ~897k rendered triangles. That is roughly 14x what a web first load
should carry. Required work:

1. Decimate the `body_neutral` meshes aggressively - they are 35% of the triangle budget and
   are never colored.
2. Draco or meshopt compression via `gltf-transform`.
3. Strip the unused `TEXCOORD_0` attribute.

Target under 2 MB and under 150k rendered triangles. Write to `assets/muscleAnatomy.optimized.glb`
(gitignored, generated). **Never overwrite `assets/muscleAnatomy.glb`.** After optimizing, re-run the
inspector and confirm all 16 material names and the node naming contract survived - a
decimation pass that silently merges materials destroys the map.

## Intensity mapping

- Source is the `muscle_group_intensity` table. Agree the units with `ai-coach-engineer` and
  `supabase-architect` first - normalized against the user's own history is more meaningful
  than raw tonnage.
- Default the window to the longest range that has data, up to 30 days.
- **Do not encode intensity in hue alone.** Red-green color blindness is common. Use a
  lightness or saturation ramp and always pair the map with a numeric legend.
- The ramp runs through the brand palette (primary `#1A5634` to secondary `#F8CB28`) and must
  work on both the `#000000` and `#FFFFFF` bases.
- Untrained muscles need a visibly distinct no-data state, not just the low end of the ramp.
- Four muscle groups have no geometry at all: lower back, obliques, rhomboids, tibialis. Follow
  the fallback documented in `CLAUDE.md` and surface the volume somewhere. A deadlift that
  lights up nothing reads as a bug.

## Quality bar

- Tapping a muscle shows its name, intensity value, and the exercises that drove it.
- Keep interaction responsive on a mid-range Android phone. Precompute the rollup; never
  aggregate raw `workout_logs` rows on a frame.
- Provide a non-visual fallback: a ranked list of muscle groups by intensity, which doubles as
  the screen-reader experience and as the render path when WebGL is unavailable.

## Reporting

State the renderer you chose and the measured recolor cost, the optimized asset's size and
triangle count, and what still needs art work in Blender.
