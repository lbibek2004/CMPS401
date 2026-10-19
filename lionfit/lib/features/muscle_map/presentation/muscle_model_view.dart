import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../../core/training/models.dart';
import '../domain/glb_recolor.dart';

/// The bundled anatomy model, loaded once.
final muscleModelBytesProvider = FutureProvider<Uint8List>((ref) async {
  final data = await rootBundle.load('assets/muscleAnatomy.glb');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
});

/// Whether to mount the real WebGL viewer.
///
/// `false` swaps in a static placeholder. Widget tests override it, because
/// `flutter test` has neither a browser nor a WebView to host model-viewer.
final muscleModelRendererEnabledProvider = Provider<bool>((ref) => true);

/// Renders `muscleAnatomy.glb` with each muscle group's material painted
/// [colors].
///
/// Renderer: `model_viewer_plus` (Google's `<model-viewer>`) - a web component
/// on Web, an Android WebView on Android, so one widget covers both targets.
/// The colouring is done **before** the model reaches it: the GLB's 16
/// muscle materials are rewritten in Dart and handed over as a `data:` URL, so
/// there is no JavaScript bridge to keep in sync between platforms.
///
/// `autoPlay` stays off. The asset still carries the stray `cvel_lAction`
/// animation; [recolorGlb] strips it anyway, belt and braces.
class MuscleModelView extends ConsumerWidget {
  const MuscleModelView({
    super.key,
    required this.colors,
    required this.semanticsLabel,
  });

  final Map<MuscleGroup, Color> colors;

  /// What a screen reader announces instead of the canvas.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    if (!ref.watch(muscleModelRendererEnabledProvider)) {
      return _Placeholder(label: semanticsLabel);
    }

    final bytes = ref.watch(muscleModelBytesProvider);
    return bytes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Placeholder(label: 'The 3D model could not be loaded.'),
      data: (glb) {
        final materialColors = <String, Rgb>{
          for (final entry in colors.entries)
            entry.key.wireName: (
              r: (entry.value.r * 255).round(),
              g: (entry.value.g * 255).round(),
              b: (entry.value.b * 255).round(),
            ),
        };
        final src = glbDataUrl(recolorGlb(glb, materialColors));
        // The web implementation builds its HTML once, in initState, so a new
        // colouring needs a new element. Key on the colours themselves.
        final signature = Object.hashAll(
          MuscleGroup.values.map((g) => colors[g]?.toARGB32()),
        );
        return Semantics(
          label: semanticsLabel,
          image: true,
          child: ExcludeSemantics(
            child: ModelViewer(
              key: ValueKey(signature),
              src: src,
              alt: semanticsLabel,
              backgroundColor: scheme.surfaceContainerLow,
              cameraControls: true,
              disablePan: true,
              autoRotate: false,
              autoPlay: false,
              interactionPrompt: InteractionPrompt.none,
              shadowIntensity: 0.6,
              exposure: 1.1,
            ),
          ),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.accessibility_new_outlined,
              size: 64,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
