import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/setup_required_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: LionFitApp()));
}

class LionFitApp extends ConsumerWidget {
  const LionFitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problem = Env.configurationProblem;

    // Degraded mode: the app still boots and explains itself rather than
    // crashing on a client that was never initialized.
    if (problem != null) {
      return MaterialApp(
        title: 'LionFit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: SetupRequiredScreen(problem: problem),
      );
    }

    return MaterialApp.router(
      title: 'LionFit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
