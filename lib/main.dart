import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/app/app_startup.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nini_hub/app/nini_hub_app.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/database_bootstrap.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  DatabaseBootstrapResult? databaseBootstrap;
  AppStartupFailure? startupFailure;
  try {
    databaseBootstrap = await DatabaseBootstrap().open();
  } on Object catch (error) {
    startupFailure = AppStartupFailure.from(error);
  }

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 680),
      minimumSize: Size(900, 600),
      center: true,
      title: 'Nini Hub',
      backgroundColor: Color(0xFF090D12),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  if (databaseBootstrap case final bootstrap?) {
    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => unawaited(bootstrap.database.close()));
            return bootstrap.database;
          }),
        ],
        child: const NiniHubApp(),
      ),
    );
    return;
  }

  runApp(ProviderScope(child: NiniHubApp(startupFailure: startupFailure!)));
}
