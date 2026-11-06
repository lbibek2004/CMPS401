/// The JavaScript that turns a tap on the 3D model into a material name.
///
/// model-viewer's `materialFromPoint(clientX, clientY)` returns the material
/// under the pointer, and the GLB's material names **are** the 16 muscle keys
/// (see `CLAUDE.md` -> Assets), so the name is all Dart needs. The neutral
/// body returns a non-muscle name, which Dart ignores.
///
/// A tap is a pointerdown and pointerup less than [kTapSlopPx] apart, so
/// dragging to orbit the model never opens a muscle.
library;

const String kMuscleViewerId = 'lionfit-muscle-map';
const int kTapSlopPx = 6;

/// Installs the listener once per page. [deliver] is a JS expression called
/// with the material name.
String muscleTapScript(String deliver) =>
    '''
(function () {
  if (window.__lionfitMuscleTap) return;
  window.__lionfitMuscleTap = true;
  var down = null;
  document.addEventListener('pointerdown', function (e) {
    down = { x: e.clientX, y: e.clientY };
  }, true);
  document.addEventListener('pointerup', function (e) {
    if (!down) return;
    var moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
    down = null;
    if (moved > $kTapSlopPx) return;
    var path = e.composedPath ? e.composedPath() : [e.target];
    var viewer = null;
    for (var i = 0; i < path.length; i++) {
      var node = path[i];
      if (node && node.tagName === 'MODEL-VIEWER' && node.id === '$kMuscleViewerId') {
        viewer = node;
        break;
      }
    }
    if (!viewer || !viewer.materialFromPoint) return;
    var material = viewer.materialFromPoint(e.clientX, e.clientY);
    if (material && material.name) { $deliver(material.name); }
  }, true);
})();
''';
