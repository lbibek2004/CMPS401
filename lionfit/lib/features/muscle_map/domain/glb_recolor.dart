/// Recolours `assets/muscleAnatomy.glb` by **material**, not by mesh.
///
/// Left and right sides share one material per muscle group, so a full repaint
/// is 16 `baseColorFactor` writes into the GLB's JSON chunk - no textures, no
/// per-mesh work, and the misleading mesh names and the `tricep_r` node typo
/// never come into it. See `CLAUDE.md` -> Assets.
///
/// The rewrite also **drops the stray `cvel_lAction` animation**, so no
/// renderer can ever autoplay it and snap the left calf.
///
/// Pure Dart (`dart:convert` + `dart:typed_data`) so it is unit-tested against
/// the real asset and behaves identically on Web and Android.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const int _glbMagic = 0x46546C67; // "glTF"
const int _chunkJson = 0x4E4F534A; // "JSON"
const int _chunkBin = 0x004E4942; // "BIN\0"

/// An sRGB colour as 0-255 channels. Kept free of `dart:ui` on purpose.
typedef Rgb = ({int r, int g, int b});

/// Thrown when the bytes are not a GLB this code understands.
class GlbFormatException implements Exception {
  GlbFormatException(this.message);
  final String message;
  @override
  String toString() => 'GlbFormatException: $message';
}

/// The JSON chunk of a GLB, decoded.
Map<String, dynamic> readGlbJson(Uint8List glb) => _parse(glb).json;

/// Material names in the GLB, in index order.
List<String> glbMaterialNames(Uint8List glb) {
  final materials = (readGlbJson(glb)['materials'] as List?) ?? const [];
  return [
    for (final material in materials)
      ((material as Map)['name'] as String?) ?? '',
  ];
}

/// Returns a new GLB with each material named in [colorsByMaterial] painted
/// that colour (opaque), and with every animation removed.
///
/// Colours are given in **sRGB** (what a designer picks) and written as
/// **linear** values, because glTF's `baseColorFactor` is linear. Skipping that
/// conversion makes every colour on the model look washed out.
///
/// Material names not in the map are left untouched (the neutral body).
/// Names in the map that the GLB does not contain are returned by
/// [missingMaterials] so a drift between the database enum and the asset is
/// detectable instead of silent.
Uint8List recolorGlb(Uint8List glb, Map<String, Rgb> colorsByMaterial) {
  final parsed = _parse(glb);
  final json = parsed.json;

  final materials = (json['materials'] as List?) ?? const [];
  for (final material in materials) {
    final map = material as Map<String, dynamic>;
    final color = colorsByMaterial[map['name']];
    if (color == null) continue;
    final pbr =
        (map['pbrMetallicRoughness'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    pbr['baseColorFactor'] = [
      _srgbToLinear(color.r),
      _srgbToLinear(color.g),
      _srgbToLinear(color.b),
      1.0,
    ];
    // A matte-ish finish reads the colour more honestly than the default
    // fully metallic look under model-viewer's neutral environment.
    pbr['metallicFactor'] = 0.0;
    pbr['roughnessFactor'] = 0.6;
    map['pbrMetallicRoughness'] = pbr;
  }

  json.remove('animations');

  return _build(json, parsed.bin);
}

/// Names in [wanted] that no material in [glb] carries.
Set<String> missingMaterials(Uint8List glb, Iterable<String> wanted) {
  final present = glbMaterialNames(glb).toSet();
  return {
    for (final name in wanted)
      if (!present.contains(name)) name,
  };
}

/// A `data:` URL for [glb], which both model-viewer on Web and the Android
/// WebView accept as `src`.
String glbDataUrl(Uint8List glb) =>
    'data:model/gltf-binary;base64,${base64Encode(glb)}';

double _srgbToLinear(int channel) {
  final c = channel.clamp(0, 255) / 255.0;
  final linear = c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  // Six decimals is far below what 8-bit output can resolve.
  return double.parse(linear.toStringAsFixed(6));
}

({Map<String, dynamic> json, Uint8List? bin}) _parse(Uint8List glb) {
  if (glb.lengthInBytes < 20) {
    throw GlbFormatException('Too short to be a GLB');
  }
  final data = ByteData.sublistView(glb);
  if (data.getUint32(0, Endian.little) != _glbMagic) {
    throw GlbFormatException('Missing glTF magic');
  }
  final version = data.getUint32(4, Endian.little);
  if (version != 2) {
    throw GlbFormatException('Unsupported GLB version $version');
  }

  Map<String, dynamic>? json;
  Uint8List? bin;
  var offset = 12;
  while (offset + 8 <= glb.lengthInBytes) {
    final length = data.getUint32(offset, Endian.little);
    final type = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    final end = start + length;
    if (end > glb.lengthInBytes) {
      throw GlbFormatException('Chunk runs past the end of the file');
    }
    final payload = Uint8List.sublistView(glb, start, end);
    if (type == _chunkJson) {
      json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } else if (type == _chunkBin) {
      bin = payload;
    }
    offset = end;
  }
  if (json == null) throw GlbFormatException('No JSON chunk');
  return (json: json, bin: bin);
}

Uint8List _build(Map<String, dynamic> json, Uint8List? bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  // Chunks are 4-byte aligned. JSON pads with spaces, BIN with zeros.
  final jsonPadded = _pad(jsonBytes, 0x20);
  final binPadded = bin == null ? null : _pad(bin, 0x00);

  final total =
      12 +
      8 +
      jsonPadded.length +
      (binPadded == null ? 0 : 8 + binPadded.length);
  final out = Uint8List(total);
  final data = ByteData.sublistView(out);

  data.setUint32(0, _glbMagic, Endian.little);
  data.setUint32(4, 2, Endian.little);
  data.setUint32(8, total, Endian.little);

  var offset = 12;
  data.setUint32(offset, jsonPadded.length, Endian.little);
  data.setUint32(offset + 4, _chunkJson, Endian.little);
  out.setRange(offset + 8, offset + 8 + jsonPadded.length, jsonPadded);
  offset += 8 + jsonPadded.length;

  if (binPadded != null) {
    data.setUint32(offset, binPadded.length, Endian.little);
    data.setUint32(offset + 4, _chunkBin, Endian.little);
    out.setRange(offset + 8, offset + 8 + binPadded.length, binPadded);
  }
  return out;
}

Uint8List _pad(List<int> bytes, int fill) {
  final padding = (4 - bytes.length % 4) % 4;
  if (padding == 0) return Uint8List.fromList(bytes);
  return Uint8List(bytes.length + padding)
    ..setRange(0, bytes.length, bytes)
    ..fillRange(bytes.length, bytes.length + padding, fill);
}
