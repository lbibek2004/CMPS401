import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/muscle_map/domain/glb_recolor.dart';

/// Runs against the real `assets/muscleAnatomy.glb`, not a fixture - the point
/// is to catch the asset and the code drifting apart.
void main() {
  late Uint8List glb;

  setUpAll(() {
    glb = File('assets/muscleAnatomy.glb').readAsBytesSync();
  });

  test('every one of the 16 muscle keys is a material in the asset', () {
    expect(
      missingMaterials(glb, MuscleGroup.values.map((g) => g.wireName)),
      isEmpty,
    );
  });

  test('recolors exactly the named materials, in linear space', () {
    final out = recolorGlb(glb, {
      'chest_lower': (r: 255, g: 0, b: 0),
      'quads': (r: 128, g: 128, b: 128),
    });
    final materials = (readGlbJson(out)['materials'] as List)
        .cast<Map<String, dynamic>>();
    Map<String, dynamic> named(String name) =>
        materials.firstWhere((m) => m['name'] == name);

    final chest = named(
      'chest_lower',
    )['pbrMetallicRoughness']['baseColorFactor'];
    expect(chest, [1.0, 0.0, 0.0, 1.0]);

    // sRGB 128 is ~0.2159 linear, not 0.502.
    final quads =
        named('quads')['pbrMetallicRoughness']['baseColorFactor'] as List;
    expect(quads[0], closeTo(0.2159, 0.0005));

    // Untouched material keeps whatever it had.
    final before = (readGlbJson(glb)['materials'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((m) => m['name'] == 'biceps');
    expect(named('biceps'), before);
  });

  test('strips the stray animation', () {
    expect(
      readGlbJson(glb).containsKey('animations'),
      isTrue,
      reason:
          'If this fails the asset was re-exported clean - drop this check.',
    );
    final out = recolorGlb(glb, const {});
    expect(readGlbJson(out).containsKey('animations'), isFalse);
  });

  test(
    'output is a valid, 4-byte aligned GLB with the binary chunk intact',
    () {
      final out = recolorGlb(glb, {'abs': (r: 10, g: 200, b: 30)});
      final header = ByteData.sublistView(out);
      expect(header.getUint32(0, Endian.little), 0x46546C67);
      expect(header.getUint32(8, Endian.little), out.lengthInBytes);
      expect(out.lengthInBytes % 4, 0);
      // The geometry is the same size; only the JSON chunk changed.
      expect((out.lengthInBytes - glb.lengthInBytes).abs(), lessThan(8 * 1024));
      // Round-trips through the parser.
      expect(glbMaterialNames(out), glbMaterialNames(glb));
    },
  );

  test('data URL is base64 GLB', () {
    expect(
      glbDataUrl(Uint8List.fromList([1, 2, 3])),
      'data:model/gltf-binary;base64,AQID',
    );
  });

  test('rejects bytes that are not a GLB', () {
    expect(
      () => recolorGlb(Uint8List(64), const {}),
      throwsA(isA<GlbFormatException>()),
    );
  });
}
