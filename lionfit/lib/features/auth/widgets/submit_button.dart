import 'package:flutter/material.dart';

/// Full-width primary action for the auth forms.
///
/// While [busy] the button is disabled - which is the real double-submit
/// guard at the UI level - and swaps its label for a spinner plus [busyLabel]
/// so the wait is explained rather than just frozen.
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      child: busy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(busyLabel),
              ],
            )
          : Text(label),
    );
  }
}
