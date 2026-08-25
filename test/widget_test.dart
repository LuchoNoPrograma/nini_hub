import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nini_hub/app/app_startup.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/currency_catalog.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/formatters.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/core/widgets/app_primitives.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/data/account_mapper.dart';
import 'package:nini_hub/features/accounts/data/drift_account_repository.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';
import 'package:nini_hub/features/accounts/presentation/account_dialogs.dart';
import 'package:nini_hub/features/accounts/presentation/accounts_view.dart';
import 'package:nini_hub/features/profiles/data/drift_agent_profile_repository.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/profiles/domain/agent_profile.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/profiles/presentation/profile_dialogs.dart';
import 'package:nini_hub/features/usage/application/usage_calendar.dart';
import 'package:nini_hub/features/usage/application/usage_refresh.dart';
import 'package:nini_hub/features/usage/data/drift_usage_calendar_repository.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/features/usage/presentation/controllers/usage_controller.dart';
import 'package:nini_hub/features/usage/presentation/calendar_view.dart';
import 'package:nini_hub/features/usage/presentation/state/usage_state.dart';
import 'package:nini_hub/features/workspaces/application/launch_agent.dart';
import 'package:nini_hub/features/workspaces/application/workspace_history.dart';
import 'package:nini_hub/features/workspaces/data/desktop_workspace_runtime.dart';
import 'package:nini_hub/features/workspaces/data/drift_workspace_repository.dart';
import 'package:nini_hub/features/workspaces/data/drift_workspace_selection_store.dart';
import 'package:nini_hub/features/workspaces/data/nini_agents_agent_launcher.dart';
import 'package:nini_hub/features/workspaces/domain/agent_launcher.dart';
import 'package:nini_hub/features/workspaces/presentation/controllers/workspace_controller.dart';
import 'package:nini_hub/features/workspaces/presentation/launch_agent_dialog.dart';
import 'package:nini_hub/features/workspaces/presentation/state/workspace_state.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('currency catalog supports common and non-decimal currencies', () {
    expect(currencies.length, greaterThan(100));
    expect(currencyByCode('bob').name, 'Boliviano boliviano');
    expect(currencyMinorFactor('JPY'), 1);
    expect(currencyMinorFactor('KWD'), 1000);
    expect(currencyMinorFactor('USD'), 100);
  });

  test('profile providers keep their Multi CLI prefixes isolated', () {
    final chatGpt = profileProvider('codex');
    final claude = profileProvider('claude-cli');

    expect(chatGpt.profileSpec('work'), 'codex/work');
    expect(chatGpt.commandName('work'), 'codex-work');
    expect(chatGpt.credentialFiles, contains('auth.json'));
    expect(chatGpt.supportsUsage, isTrue);
    expect(chatGpt.showsDefaultProfile, isTrue);
    expect(chatGpt.showsProfileSource('default'), isTrue);
    expect(chatGpt.iconAssetPath, contains('chatgpt-official.png'));
    expect(claude.profileSpec('work'), 'claude-cli/work');
    expect(claude.commandName('work'), 'claude-cli-work');
    expect(claude.credentialFiles, contains('.credentials.json'));
    expect(claude.supportsUsage, isFalse);
    expect(claude.showsDefaultProfile, isFalse);
    expect(claude.showsProfileSource('default'), isFalse);
    expect(claude.showsProfileSource('multicli'), isTrue);
    expect(claude.iconAssetPath, contains('claude-official.png'));
  });

  test('discovery indexes ChatGPT and Claude profiles', () async {
    const root = '/synthetic/providers';
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.saveSetting('profiles_root_path', root);
    final now = DateTime.now().toUtc();
    await database.batch((batch) {
      batch.insertAll(database.cliProfiles, [
        CliProfile(
          id: 'codex-team',
          toolKey: 'codex',
          profileName: 'team',
          commandName: 'codex-team',
          displayName: 'Team',
          profileHome: '$root/codex/team',
          profileSource: 'multicli',
          profileType: 'full',
          hasAuthFile: true,
          isAvailable: true,
          isFavorite: false,
          createdAt: now,
          lastDiscoveredAt: now,
        ),
        CliProfile(
          id: 'claude-research',
          toolKey: 'claude-cli',
          profileName: 'research',
          commandName: 'claude-cli-research',
          displayName: 'Research',
          profileHome: '$root/claude-cli/research',
          profileSource: 'multicli',
          profileType: 'full',
          hasAuthFile: true,
          isAvailable: true,
          isFavorite: false,
          createdAt: now,
          lastDiscoveredAt: now,
        ),
        CliProfile(
          id: 'legacy-claude-default',
          toolKey: 'claude-cli',
          profileName: 'principal',
          commandName: 'claude',
          displayName: 'Claude Code principal',
          profileHome: '$root/legacy-claude-default',
          profileSource: 'default',
          profileType: 'base',
          hasAuthFile: false,
          isAvailable: true,
          isFavorite: false,
          createdAt: now,
          lastDiscoveredAt: now,
        ),
      ]);
    });

    final profiles = await ProfileDiscoveryService(
      database,
      NiniAgentsReadClient(_ProviderDiscoveryRunner(database)),
    ).discoverProfiles();
    final team = profiles.singleWhere(
      (profile) => profile.toolKey == 'codex' && profile.profileName == 'team',
    );
    final research = profiles.singleWhere(
      (profile) =>
          profile.toolKey == 'claude-cli' && profile.profileName == 'research',
    );

    expect(team.commandName, 'codex-team');
    expect(team.hasAuthFile, isTrue);
    expect(research.commandName, 'claude-cli-research');
    expect(research.hasAuthFile, isTrue);
    expect(
      profiles.where(
        (profile) =>
            profile.toolKey == 'claude-cli' &&
            profile.profileSource == 'default',
      ),
      isEmpty,
    );
    final accounts = await DriftAccountRepository(database).loadAll();
    expect(
      accounts.where((item) => item.profile.id == 'legacy-claude-default'),
      isEmpty,
    );
  });

  test(
    'Codex launch directories are validated without touching profiles',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nini-hub-working-dir-',
      );
      addTearDown(() => directory.delete(recursive: true));

      expect(
        DesktopWorkspaceRuntime.validateWorkingDirectory(directory.path),
        directory.absolute.path,
      );
      expect(
        () => DesktopWorkspaceRuntime.validateWorkingDirectory(
          '${directory.path}-missing',
        ),
        throwsStateError,
      );
    },
  );

  test('workspace history is global, normalized, and ordered by use', () async {
    final root = await Directory.systemTemp.createTemp('multicli-workspaces-');
    addTearDown(() => root.delete(recursive: true));
    final first = Directory('${root.path}/nini_hub');
    final second = Directory('${root.path}/parla');
    await first.create();
    await second.create();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftWorkspaceRepository(database);

    final initial = await repository.add('${first.path}/.');
    await repository.recordOpened(first.path);
    await repository.recordOpened('${first.path}/.');
    final recent = await repository.add(second.path);

    var workspaces = await repository.loadAll();
    expect(workspaces, hasLength(2));
    expect(workspaces.first.id, recent.id);
    final initialBeforeSelect = workspaces.singleWhere(
      (item) => item.id == initial.id,
    );
    expect(initialBeforeSelect.openCount, 2);

    await repository.select(initial.id);
    await repository.rename(workspaceId: initial.id, name: 'Multi CLI AI');
    workspaces = await repository.loadAll();
    final selected = workspaces.first;
    expect(selected.id, initial.id);
    expect(selected.name, 'Multi CLI AI');
    expect(selected.openCount, initialBeforeSelect.openCount);
    expect(selected.lastUsedAt.isAfter(initialBeforeSelect.lastUsedAt), isTrue);

    await repository.remove(recent.id);
    expect(await repository.loadAll(), hasLength(1));
  });

  test('terminal arguments preserve native working directories', () {
    const project = '/home/nini/StudioProjects/bora asai';
    const target = '/home/nini/.local/bin/nini-agents';
    const command = ['launch', 'codex/ari'];
    const title = 'codex-ari | bora asai';

    expect(
      ProcessRunner.buildTerminalArguments(
        terminal: 'gnome-terminal',
        target: target,
        arguments: command,
        workingDirectory: project,
        title: title,
      ),
      [
        '--title=$title',
        '--working-directory=$project',
        '--',
        target,
        ...command,
      ],
    );
    expect(
      ProcessRunner.buildTerminalArguments(
        terminal: 'wt',
        target: target,
        arguments: command,
        workingDirectory: project,
        title: title,
      ),
      [
        '--window',
        'new',
        'new-tab',
        '--title',
        title,
        '-d',
        project,
        target,
        ...command,
      ],
    );
    expect(
      ProcessRunner.buildTerminalArguments(
        terminal: 'hyper',
        target: target,
        arguments: command,
        workingDirectory: project,
        title: title,
      ),
      [project],
    );
  });

  test('Linux terminal discovery recognizes Hyper and gsettings values', () {
    expect(
      ProcessRunner.identifyTerminal('/home/nini/.local/bin/hyper-cwd'),
      'hyper',
    );
    expect(
      ProcessRunner.parseGSettingsString("'/home/nini/.local/bin/hyper-cwd'"),
      '/home/nini/.local/bin/hyper-cwd',
    );
    expect(ProcessRunner.parseGSettingsString("''"), isNull);
  });

  test('Hyper receives the command, its arguments, and the tab title', () {
    final environment = ProcessRunner.buildHyperTerminalEnvironment(
      {'PATH': '/usr/bin', 'NO_COLOR': '1', 'MULTICLI_TERMINAL_ARG_9': 'stale'},
      shellLauncher: '/tmp/nini-hub/launch-command',
      target: '/home/nini/.local/bin/nini-agents',
      arguments: const ['launch', 'codex/ari', '--workspace', 'bora asai'],
      title: 'ari · bora asai',
    );

    expect(environment['SHELL'], '/tmp/nini-hub/launch-command');
    expect(
      environment['MULTICLI_TERMINAL_TARGET'],
      '/home/nini/.local/bin/nini-agents',
    );
    expect(environment['MULTICLI_TERMINAL_ARGC'], '4');
    expect(environment['MULTICLI_TERMINAL_ARG_0'], 'launch');
    expect(environment['MULTICLI_TERMINAL_ARG_3'], 'bora asai');
    expect(environment['MULTICLI_TERMINAL_TITLE'], 'ari · bora asai');
    expect(environment, isNot(contains('MULTICLI_TERMINAL_ARG_9')));
    expect(environment, isNot(contains('NO_COLOR')));
  });

  test('interactive terminals restore color and use a compact title', () {
    final environment = ProcessRunner.buildTerminalEnvironment({
      'PATH': '/usr/bin',
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'NO_COLOR': '1',
    });

    expect(environment, isNot(contains('NO_COLOR')));
    expect(environment['TERM'], 'xterm-256color');
    expect(environment['COLORTERM'], 'truecolor');
    expect(
      DesktopWorkspaceRuntime.buildTerminalTitle(
        profileName: 'magic',
        workingDirectory: '/home/nini/StudioProjects/nini_hub',
      ),
      'magic · nini_hub',
    );
  });

  test('sensitive process output is redacted', () {
    final output = ProcessRunner.sanitizeOutput(
      'access_token=secret-value authorization: Bearer abcdef api_key: 123456',
    );
    expect(output, isNot(contains('secret-value')));
    expect(output, isNot(contains('abcdef')));
    expect(output, isNot(contains('123456')));
    expect(output, contains('[REDACTADO]'));
  });

  test('schema migration failures ask for the latest executable', () {
    final failure = AppStartupFailure.from(
      Exception(
        "You've bumped the schema version for your drift database but didn't "
        'provide a strategy for schema updates. Please adapt the migrations '
        'getter in your database class.',
      ),
    );

    expect(failure.kind, AppStartupFailureKind.updateRequired);
    expect(failure.title, 'Ejecutable desactualizado');
    expect(failure.message, contains('versión más reciente'));
    expect(failure.message, contains('Tus datos se conservarán'));
    expect(failure.message, isNot(contains('schema version')));
  });

  test('unexpected startup failures retain sanitized diagnostics', () {
    final failure = AppStartupFailure.from(
      Exception('authorization: Bearer secret-token; conexión rechazada'),
    );

    expect(failure.kind, AppStartupFailureKind.unexpected);
    expect(failure.title, 'No se pudo iniciar');
    expect(failure.message, contains('conexión rechazada'));
    expect(failure.message, contains('[REDACTADO]'));
    expect(failure.message, isNot(contains('secret-token')));
  });

  test('usage check storage values round-trip', () {
    for (final value in UsageCheckState.values) {
      expect(
        UsageCheckState.fromStorage(value.storageValue),
        value == UsageCheckState.error ? UsageCheckState.error : value,
      );
    }
  });

  test(
    'account list sorts by name, availability, renewal, and nearest reset',
    () async {
      final base = DateTime.utc(2026, 8, 17);

      Account account({
        required String id,
        required String name,
        DateTime? renewal,
        DateTime? reset,
        double? usedPercent,
      }) {
        final check = UsageCheck(
          id: '$id-check',
          profileId: id,
          queryMethod: 'test',
          status: 'success',
          startedAt: base,
        );
        return _domainAccount(
          profile: CliProfile(
            id: id,
            toolKey: 'codex',
            profileName: id,
            commandName: 'codex-$id',
            displayName: name,
            profileHome: '/tmp/$id',
            profileSource: 'multicli',
            profileType: 'full',
            hasAuthFile: true,
            isAvailable: true,
            isFavorite: false,
            createdAt: base,
            lastDiscoveredAt: base,
          ),
          metadata: ProfileMetadata(
            profileId: id,
            accountEmail: '',
            accountDisplayName: '',
            planName: '',
            notes: '',
            tagsJson: '[]',
            nextRenewalOn: renewal,
            billingInterval: 'monthly',
            expectedAmountMinor: 0,
            currencyCode: 'USD',
            autoRenew: true,
            subscriptionStatus: 'active',
            purchasedFrom: '',
            paymentMethodLabel: '',
            updatedAt: base,
          ),
          costShares: const [],
          currentCheck: check,
          currentWindows: reset == null && usedPercent == null
              ? const []
              : [
                  QuotaWindow(
                    id: '$id-window',
                    checkId: check.id,
                    limitId: 'codex',
                    windowType: 'primary',
                    usedPercent: usedPercent,
                    resetsAt: reset,
                  ),
                ],
          lastSuccessfulCheck: check,
          lastSuccessfulWindows: const [],
          resetCredits: null,
        );
      }

      final snapshot = AccountSnapshot([
        account(
          id: 'zeta',
          name: 'Zeta',
          renewal: base.add(const Duration(days: 3)),
          reset: base.add(const Duration(hours: 4)),
          usedPercent: 80,
        ),
        account(
          id: 'alpha',
          name: 'Alpha',
          reset: base.add(const Duration(hours: 2)),
          usedPercent: 10,
        ),
        account(
          id: 'mu',
          name: 'Mu',
          renewal: base.add(const Duration(days: 1)),
        ),
      ]);
      var query = const AccountQuery();

      List<String> names() => snapshot
          .visible(query)
          .map((item) => item.profile.displayName)
          .toList();

      expect(names(), ['Alpha', 'Mu', 'Zeta']);
      query = const AccountQuery(sort: AccountSortMode.availability);
      expect(names(), ['Alpha', 'Zeta', 'Mu']);
      query = const AccountQuery(sort: AccountSortMode.renewal);
      expect(names(), ['Mu', 'Zeta', 'Alpha']);
      query = const AccountQuery(sort: AccountSortMode.reset);
      expect(names(), ['Alpha', 'Zeta', 'Mu']);
    },
  );

  test('Codex rate-limit mirrors are deduplicated by bucket and window', () {
    const primary = {
      'usedPercent': 12,
      'windowDurationMins': 300,
      'resetsAt': 1786650000,
    };
    const secondary = {
      'usedPercent': 7,
      'windowDurationMins': 10080,
      'resetsAt': 1787197754,
    };
    const snapshot = {
      'limitId': 'codex',
      'limitName': 'Codex',
      'primary': primary,
      'secondary': secondary,
    };

    final windows = CodexAppServerClient.parseQuotaWindows({
      'rateLimits': snapshot,
      'rateLimitsByLimitId': {'codex': snapshot},
    });

    expect(windows, hasLength(2));
    expect(windows.map((item) => item.windowType), ['primary', 'secondary']);
    expect(windows.first.windowDurationMinutes, 300);
    expect(windows.last.windowDurationMinutes, 10080);
  });

  test('Codex device auth trusts the completed notification result', () {
    final success = CodexDeviceAuthSession.parseCompletionNotification({
      'method': 'account/login/completed',
      'params': {'loginId': 'login-1', 'success': true, 'error': null},
    });
    final failure = CodexDeviceAuthSession.parseCompletionNotification({
      'method': 'account/login/completed',
      'params': {
        'loginId': 'login-2',
        'success': false,
        'error': 'authorization denied',
      },
    });

    expect(success.success, isTrue);
    expect(success.error, isNull);
    expect(failure.success, isFalse);
    expect(failure.error, 'authorization denied');
  });

  test('quota windows use human labels', () {
    expect(formatQuotaWindowLabel(300, 'primary'), 'Ventana de 5 h');
    expect(formatQuotaWindowLabel(10080, 'secondary'), 'Límite semanal');
    final now = DateTime(2026, 8, 13, 10);
    expect(
      formatTimeRemaining(
        now.add(const Duration(days: 6, hours: 13)),
        from: now,
      ),
      '6 d 13 h',
    );
    expect(
      formatTimeRemaining(
        now.add(const Duration(hours: 2, minutes: 18)),
        from: now,
      ),
      '2 h 18 min',
    );
  });

  test('large usage values use stable K, M, and B units', () {
    expect(formatCompactInt(999), '999');
    expect(formatCompactInt(1200), '1,2 K');
    expect(formatCompactInt(999999), '1 M');
    expect(formatCompactInt(1000000), '1 M');
    expect(formatCompactInt(1500000000), '1,5 B');
    expect(formatInteger(1234567), '1.234.567');
    expect(
      formatTokenDetails(322242242),
      '322 M tokens\n322.242.242 tokens exactos',
    );
    expect(formatFullDate(DateTime(2026, 8, 13)), 'Jueves 13 ago 2026');
  });

  test('calendar usage is consolidated and grouped by account', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final day = DateTime(2026, 8, 12);
    final profiles = [
      CliProfile(
        id: 'ari',
        toolKey: 'codex',
        profileName: 'ari',
        displayName: 'Ari Personal',
        profileHome: '/tmp/ari-calendar',
        profileSource: 'multicli',
        profileType: 'full',
        hasAuthFile: true,
        isAvailable: true,
        isFavorite: false,
        createdAt: day,
        lastDiscoveredAt: day,
      ),
      CliProfile(
        id: 'team',
        toolKey: 'codex',
        profileName: 'team',
        displayName: 'Equipo',
        profileHome: '/tmp/team-calendar',
        profileSource: 'multicli',
        profileType: 'full',
        hasAuthFile: true,
        isAvailable: true,
        isFavorite: false,
        createdAt: day,
        lastDiscoveredAt: day,
      ),
    ];
    for (final profile in profiles) {
      await database.into(database.cliProfiles).insert(profile);
    }
    final checks = [
      UsageCheck(
        id: 'ari-check',
        profileId: 'ari',
        queryMethod: 'codex-app-server',
        status: 'success',
        startedAt: day.add(const Duration(hours: 9)),
        accountEmail: 'ari@example.com',
      ),
      UsageCheck(
        id: 'team-check',
        profileId: 'team',
        queryMethod: 'codex-app-server',
        status: 'partial',
        startedAt: day.add(const Duration(hours: 10)),
        accountEmail: 'team@example.com',
      ),
    ];
    for (final check in checks) {
      await database.into(database.usageChecks).insert(check);
    }
    for (final bucket in [
      DailyUsageBucket(
        id: 'ari-older',
        checkId: 'ari-check',
        profileId: 'ari',
        day: DateTime.utc(2026, 8, 12),
        tokens: 1000000,
        source: 'test',
      ),
      DailyUsageBucket(
        id: 'ari-newer',
        checkId: 'ari-check',
        profileId: 'ari',
        day: DateTime.utc(2026, 8, 12),
        tokens: 1500000,
        source: 'test',
      ),
      DailyUsageBucket(
        id: 'team-usage',
        checkId: 'team-check',
        profileId: 'team',
        day: DateTime.utc(2026, 8, 12),
        tokens: 800000,
        source: 'test',
      ),
      DailyUsageBucket(
        id: 'ari-provider-date',
        checkId: 'ari-check',
        profileId: 'ari',
        day: DateTime.utc(2026, 8, 13),
        tokens: 79956487,
        source: 'account/usage/read',
      ),
    ]) {
      await database.into(database.dailyUsageBuckets).insert(bucket);
    }

    final calendar = await DriftUsageCalendarRepository(
      database,
    ).loadCalendar();
    final result = calendar[day];

    expect(result, isNotNull);
    expect(result!.tokens, 2300000);
    expect(result.successfulChecks, 2);
    expect(result.accounts.map((item) => item.displayName), [
      'Ari Personal',
      'Equipo',
    ]);
    expect(result.accounts.first.tokens, 1500000);
    expect(calendar[DateTime(2026, 8, 13)]?.tokens, 79956487);
    expect(result.accounts.first.email, 'ari@example.com');
  });

  test('light and dark themes keep compact controls legible', () {
    for (final theme in [AppTheme.dark('cyan'), AppTheme.light('cyan')]) {
      expect(theme.iconTheme.color, theme.colorScheme.onSurfaceVariant);
      expect(
        theme.iconButtonTheme.style?.foregroundColor?.resolve({}),
        theme.colorScheme.onSurfaceVariant,
      );
      expect(
        theme.popupMenuTheme.labelTextStyle?.resolve({})?.fontWeight,
        FontWeight.w400,
      );
      expect(
        theme.popupMenuTheme.labelTextStyle?.resolve({})?.color,
        theme.colorScheme.onSurface,
      );
      expect(theme.dialogTheme.titleTextStyle?.fontSize, lessThan(16));
      expect(theme.tabBarTheme.unselectedLabelColor, isNot(Colors.black));
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
        38,
      );
      expect(
        theme.outlinedButtonTheme.style?.minimumSize?.resolve({})?.height,
        38,
      );
      expect(theme.textButtonTheme.style?.minimumSize?.resolve({})?.height, 36);
    }
  });

  testWidgets('create profile switches cleanly from ChatGPT to Claude', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.dark('cyan'),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showCreateProfileDialog(
                    context,
                    controller: ref.read(profilesControllerProvider.notifier),
                    readState: () => ref.read(profilesControllerProvider),
                  ),
                  child: const Text('Abrir creación'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir creación'));
    await tester.pumpAndSettle();

    expect(find.text('Crear y vincular'), findsOneWidget);
    expect(find.text('Acceso mediante Codex Device Auth'), findsOneWidget);
    expect(find.textContaining('Configuración > Seguridad'), findsOneWidget);
    expect(
      find.textContaining('habilita el acceso mediante código de dispositivo'),
      findsOneWidget,
    );
    final primaryButton = find.widgetWithText(FilledButton, 'Crear y vincular');
    expect(tester.getSize(primaryButton).height, greaterThanOrEqualTo(38));
    InputDecoration aliasDecoration() => tester
        .widget<InputDecorator>(
          find
              .descendant(
                of: find.byType(TextFormField).first,
                matching: find.byType(InputDecorator),
              )
              .first,
        )
        .decoration;
    expect(aliasDecoration().prefixText, 'codex-');
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('Cómo empezar'), findsOneWidget);
    expect(find.text('Compartir ajustes'), findsOneWidget);
    expect(find.text('Independiente'), findsOneWidget);
    expect(find.byType(RadioListTile<ProfileSetupMode>), findsNWidgets(2));
    expect(
      tester
          .widget<RadioGroup<ProfileSetupMode>>(
            find.byType(RadioGroup<ProfileSetupMode>),
          )
          .groupValue,
      ProfileSetupMode.shared,
    );

    await tester.tap(find.text('Independiente'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<ProfileSetupMode>>(
            find.byType(RadioGroup<ProfileSetupMode>),
          )
          .groupValue,
      ProfileSetupMode.full,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude · Claude Code').last);
    await tester.pumpAndSettle();

    expect(find.text('Crear en Claude'), findsOneWidget);
    expect(find.text('Acceso de Claude Code'), findsOneWidget);
    expect(
      find.textContaining('vinculación automática todavía no está disponible'),
      findsOneWidget,
    );
    expect(find.text('Acceso mediante Codex Device Auth'), findsNothing);
    expect(find.text('multi-cli new claude-cli/alias'), findsOneWidget);
    expect(aliasDecoration().prefixText, 'claude-cli-');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state remains usable in a narrow surface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: const SizedBox(
          width: 320,
          height: 480,
          child: EmptyState(
            icon: Icons.account_tree_outlined,
            title: 'No hay perfiles Codex',
            message: 'Crea una cuenta para comenzar.',
          ),
        ),
      ),
    );

    expect(find.text('No hay perfiles Codex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('brand icon is bundled as a Flutter asset', (tester) async {
    final data = await rootBundle.load('assets/branding/nini-hub-icon.png');

    expect(data.lengthInBytes, greaterThan(1000));
  });

  testWidgets('account card distinguishes queued running and completed usage', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(460, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = Account(
      profile: Profile(
        id: 'progress',
        toolKey: 'codex',
        profileName: 'progress',
        commandName: 'codex-progress',
        displayName: 'Progress',
        profileHome: '/profiles/progress',
        source: ProfileSource.multiCli,
        kind: ProfileKind.full,
        hasAuthFile: true,
        isAvailable: true,
        isFavorite: false,
      ),
      metadata: null,
      costShares: const [],
      currentCheck: null,
      currentWindows: const [],
      lastSuccessfulCheck: null,
      lastSuccessfulWindows: const [],
      resetCredits: null,
    );

    Widget card(UsageProfileRefreshStage stage, {String? failure}) =>
        MaterialApp(
          theme: AppTheme.dark('cyan'),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 430,
                height: 246,
                child: AccountCard(
                  account: account,
                  refreshing: stage == UsageProfileRefreshStage.running,
                  compact: false,
                  accountBusy: false,
                  profileMutationBusy: false,
                  usageRefreshStage: stage,
                  usageFailureMessage: failure,
                  usageActionsDisabled: stage != UsageProfileRefreshStage.idle,
                  onEditAccount: () async {},
                  onHeartbeat: (_) async {},
                  onRefresh: (_) async {},
                  onDeviceAuth: (_) async {},
                  onRenameProfile: (_) async {},
                  onDeleteProfile: (_) async {},
                  onLaunchAgent: (_) {},
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(card(UsageProfileRefreshStage.queued));
    expect(
      find.byKey(const ValueKey('usage-refresh-queued-progress')),
      findsOneWidget,
    );
    expect(find.byTooltip('En cola para consultar'), findsOneWidget);

    await tester.pumpWidget(card(UsageProfileRefreshStage.running));
    expect(
      find.byKey(const ValueKey('usage-refresh-running-progress')),
      findsOneWidget,
    );
    expect(find.byTooltip('Consultando cuotas'), findsOneWidget);

    await tester.pumpWidget(card(UsageProfileRefreshStage.completed));
    expect(
      find.byKey(const ValueKey('usage-refresh-completed-progress')),
      findsOneWidget,
    );
    expect(find.byTooltip('Cuotas actualizadas'), findsOneWidget);

    await tester.pumpWidget(
      card(UsageProfileRefreshStage.failed, failure: 'Falló Progress.'),
    );
    expect(find.byTooltip('Falló Progress.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account card fits every distinct quota stack', (tester) async {
    await tester.binding.setSurfaceSize(const Size(460, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final fallbackDirectory = DesktopWorkspaceRuntime.userHomeDirectory();
    final now = DateTime(2026, 8, 13);
    final check = UsageCheck(
      id: 'check',
      profileId: 'ari',
      queryMethod: 'codex-app-server',
      status: 'success',
      startedAt: now,
      planType: 'plus',
      accountEmail: 'ari@example.com',
    );
    final profile = CliProfile(
      id: 'ari',
      toolKey: 'codex',
      profileName: 'ari',
      commandName: 'codex-ari',
      displayName: 'Ari',
      profileHome: '/tmp/ari',
      profileSource: 'multicli',
      profileType: 'full',
      hasAuthFile: true,
      isAvailable: true,
      isFavorite: false,
      createdAt: now,
      lastDiscoveredAt: now,
    );
    final account = _domainAccount(
      profile: profile,
      metadata: null,
      costShares: const [],
      currentCheck: check,
      currentWindows: [
        QuotaWindow(
          id: 'short',
          checkId: 'check',
          limitId: 'codex_bengalfox',
          limitName: 'GPT-5.3-Codex-Spark',
          windowType: 'primary',
          usedPercent: 12,
          windowDurationMinutes: 300,
          resetsAt: now.add(const Duration(hours: 2)),
        ),
        QuotaWindow(
          id: 'weekly',
          checkId: 'check',
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 7,
          windowDurationMinutes: 10080,
          resetsAt: now.add(const Duration(days: 6)),
        ),
        QuotaWindow(
          id: 'spark-weekly',
          checkId: 'check',
          limitId: 'codex_bengalfox',
          limitName: 'GPT-5.3-Codex-Spark',
          windowType: 'secondary',
          usedPercent: 0,
          windowDurationMinutes: 10080,
          resetsAt: now.add(const Duration(days: 7)),
        ),
      ],
      lastSuccessfulCheck: check,
      lastSuccessfulWindows: const [],
      resetCredits: null,
    );
    final otherAccount = _domainAccount(
      profile: profile.copyWith(
        id: 'sol',
        profileName: 'sol',
        displayName: 'Sol',
        profileHome: '/tmp/sol',
      ),
      metadata: null,
      costShares: const [],
      currentCheck: null,
      currentWindows: const [],
      lastSuccessfulCheck: null,
      lastSuccessfulWindows: const [],
      resetCredits: null,
    );
    final fillerAccounts = List.generate(
      8,
      (index) => _domainAccount(
        profile: profile.copyWith(
          id: 'filler-$index',
          profileName: 'filler-$index',
          displayName: 'A Cuenta $index',
          profileHome: '/tmp/filler-$index',
        ),
        metadata: null,
        costShares: const [],
        currentCheck: null,
        currentWindows: const [],
        lastSuccessfulCheck: null,
        lastSuccessfulWindows: const [],
        resetCredits: null,
      ),
    );
    final accounts = [otherAccount, ...fillerAccounts, account];
    final accountsContainer = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(accountsContainer.dispose);
    final accountsController = accountsContainer.read(
      accountsControllerProvider.notifier,
    );
    final workspaces = [
      Workspace(
        id: 'workspace',
        path: '/home/nini/StudioProjects/nini_hub',
        pathKey: '/home/nini/StudioProjects/nini_hub',
        name: 'nini_hub',
        openCount: 1,
        createdAt: now,
        lastUsedAt: now,
      ),
    ];
    for (final workspace in workspaces) {
      await database.into(database.workspaces).insert(workspace);
    }
    await database.saveSetting('current_workspace_id', 'workspace');
    final workspaceProvider =
        NotifierProvider<WorkspaceController, WorkspaceState>(
          () => _workspaceController(database),
        );
    final workspaceContainer = ProviderContainer();
    addTearDown(workspaceContainer.dispose);
    final workspaceController = workspaceContainer.read(
      workspaceProvider.notifier,
    );
    expect(await workspaceController.load(), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 430,
              height: 250,
              child: AccountCard(
                account: account,
                refreshing: false,
                compact: false,
                accountBusy: false,
                profileMutationBusy: false,
                onEditAccount: () => showEditAccountDialog(
                  tester.element(find.byType(AccountCard)),
                  accountsController,
                  () => accountsContainer.read(accountsControllerProvider),
                  account,
                ),
                onHeartbeat: (_) async {},
                onRefresh: (_) async {},
                onDeviceAuth: (_) async {},
                onRenameProfile: (_) async {},
                onDeleteProfile: (_) async {},
                onLaunchAgent: (profileId) {
                  unawaited(
                    showDialog<void>(
                      context: tester.element(find.byType(AccountCard)),
                      builder: (context) => LaunchAgentDialog(
                        controller: workspaceController,
                        state: workspaceContainer.read(workspaceProvider),
                        profiles: accounts
                            .map(_launchProfileOptionForTest)
                            .toList(),
                        pickDirectory: (_) async => null,
                        fallbackDirectory: fallbackDirectory,
                        onProfileSelected: (_) {},
                        initialProfileId: profileId,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('codex-ari'), findsOneWidget);
    expect(find.text('GPT-5.3-Codex-Spark · Ventana de 5 h'), findsOneWidget);
    expect(find.text('Codex · Límite semanal'), findsOneWidget);
    expect(find.text('GPT-5.3-Codex-Spark · Límite semanal'), findsOneWidget);
    expect(find.text('93% disponible'), findsOneWidget);
    final snapshotAge = find.byKey(const ValueKey('quota-snapshot-age-ari'));
    expect(snapshotAge, findsOneWidget);
    expect(find.byTooltip('Lanzar agente con Ari'), findsOneWidget);
    final terminalRect = tester.getRect(
      find.byTooltip('Lanzar agente con Ari'),
    );
    final snapshotAgeRect = tester.getRect(snapshotAge);
    final refreshRect = tester.getRect(
      find.byTooltip('Consultar sólo esta cuenta'),
    );
    expect(terminalRect.right, lessThanOrEqualTo(snapshotAgeRect.left));
    expect(snapshotAgeRect.right, lessThanOrEqualTo(refreshRect.left));
    expect(snapshotAgeRect.center.dy, closeTo(refreshRect.center.dy, 1));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byTooltip('Editar perfil'),
              matching: find.byIcon(Icons.edit_outlined),
            ),
          )
          .size,
      18,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byTooltip('Más acciones'),
              matching: find.byIcon(Icons.more_vert),
            ),
          )
          .size,
      18,
    );
    final cardRect = tester.getRect(find.byType(AccountCard));
    final availableRect = tester.getRect(find.text('93% disponible'));
    final weeklyRect = tester.getRect(find.text('Codex · Límite semanal'));
    final weeklyResetRect = tester.getRect(
      find.textContaining('Reinicia en').last,
    );
    expect(cardRect.right - availableRect.right, closeTo(11, 1));
    expect(weeklyResetRect.left - weeklyRect.right, lessThanOrEqualTo(20));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar ciclo'), findsOneWidget);
    expect(find.text('Renombrar alias físico'), findsOneWidget);
    expect(find.text('Eliminar perfil'), findsOneWidget);
    expect(
      DefaultTextStyle.of(
        tester.element(find.text('Renombrar alias físico')),
      ).style.fontWeight,
      FontWeight.w400,
    );
    expect(
      IconTheme.of(
        tester.element(find.byIcon(Icons.drive_file_rename_outline)),
      ).color,
      AppTheme.dark('cyan').colorScheme.onSurfaceVariant,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Iniciar ciclo'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar ciclo de Ari'), findsOneWidget);
    expect(find.textContaining('consulta mínima real'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Elegir destino'), findsNothing);
    expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(900, 620));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lanzar agente con Ari'));
    await tester.pumpAndSettle();
    final ariPicker = find.byKey(const ValueKey('launch-account-ari'));
    expect(
      find.descendant(of: ariPicker, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<GridView>(find.byKey(const Key('launch-account-list')))
          .controller!
          .offset,
      greaterThan(0),
    );
    expect(
      find.descendant(of: ariPicker, matching: find.text('88% disponible')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('launch-account-availability-ari')),
          )
          .value,
      closeTo(.88, .001),
    );
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    unawaited(
      showEditAccountDialog(
        tester.element(find.byType(AccountCard)),
        accountsController,
        () => accountsContainer.read(accountsControllerProvider),
        account,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Editar perfil "Ari"'), findsOneWidget);
    final accountTabScroll = tester.widget<ListView>(
      find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(ListView),
          )
          .first,
    );
    expect(accountTabScroll.padding, const EdgeInsets.fromLTRB(0, 9, 0, 4));
    final subscriptionTabIcon = find
        .descendant(
          of: find.byType(TabBar),
          matching: find.byIcon(Icons.event_repeat),
        )
        .first;
    expect(
      IconTheme.of(tester.element(subscriptionTabIcon)).color,
      AppTheme.dark('cyan').colorScheme.onSurfaceVariant,
    );
    await tester.tap(find.text('Renovación'));
    await tester.pumpAndSettle();
    expect(find.text('Fecha de próxima renovación'), findsOneWidget);
    expect(find.text('Precio por renovación'), findsOneWidget);
    expect(find.text('Estado de la suscripción'), findsOneWidget);
    expect(find.text('Estado comercial'), findsNothing);

    await tester.tap(find.byKey(const Key('next-renewal-date-field')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('currency-field')));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar moneda'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('currency-search-field')),
      'JPY',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yen japonés'));
    await tester.pumpAndSettle();
    expect(find.text('JPY · Yen japonés'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 430,
              height: 186,
              child: AccountCard(
                account: account,
                refreshing: false,
                compact: true,
                accountBusy: false,
                profileMutationBusy: false,
                onEditAccount: () async {},
                onHeartbeat: (_) async {},
                onRefresh: (_) async {},
                onDeviceAuth: (_) async {},
                onRenameProfile: (_) async {},
                onDeleteProfile: (_) async {},
                onLaunchAgent: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GPT-5.3-Codex-Spark · Ventana de 5 h'), findsOneWidget);
    expect(find.textContaining('Límite semanal'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('quota-snapshot-age-ari')))
          .data,
      contains('+2'),
    );
    expect(tester.takeException(), isNull);

    final reserveAccount = _domainAccount(
      profile: profile,
      metadata: null,
      costShares: const [],
      currentCheck: check,
      currentWindows: [
        QuotaWindow(
          id: 'codex-weekly',
          checkId: check.id,
          limitId: 'codex',
          limitName: 'Codex',
          windowType: 'primary',
          usedPercent: 0,
          windowDurationMinutes: 10080,
          resetsAt: now.add(const Duration(days: 7)),
        ),
        QuotaWindow(
          id: 'reserve-weekly',
          checkId: check.id,
          limitId: 'gpt-reserve',
          windowType: 'primary',
          usedPercent: 54,
          windowDurationMinutes: 10080,
          resetsAt: now.add(const Duration(days: 5, hours: 15)),
        ),
      ],
      lastSuccessfulCheck: check,
      lastSuccessfulWindows: const [],
      resetCredits: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 460,
              height: 280,
              child: AccountCard(
                account: reserveAccount,
                refreshing: false,
                compact: false,
                accountBusy: false,
                profileMutationBusy: false,
                onEditAccount: () async {},
                onHeartbeat: (_) async {},
                onRefresh: (_) async {},
                onDeviceAuth: (_) async {},
                onRenameProfile: (_) async {},
                onDeleteProfile: (_) async {},
                onLaunchAgent: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final codexQuotaTitle = tester.widget<Text>(
      find.byKey(const ValueKey('quota-title-codex-primary')),
    );
    final reserveQuotaTitle = tester.widget<Text>(
      find.byKey(const ValueKey('quota-title-gpt-reserve-primary')),
    );
    expect(codexQuotaTitle.data, contains('Codex'));
    expect(reserveQuotaTitle.data, contains('gpt-reserve'));
    expect(codexQuotaTitle.data, isNot(reserveQuotaTitle.data));
    expect(tester.takeException(), isNull);
  });

  testWidgets('agent launcher keeps workspaces separate from accounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final currentWorkspacePath = Directory.current.path;
    final now = DateTime(2026, 8, 14);
    final accountProfile = CliProfile(
      id: 'ari',
      toolKey: 'codex',
      profileName: 'ari',
      commandName: 'codex-ari',
      displayName: 'Ari',
      profileHome: '/tmp/ari',
      profileSource: 'multicli',
      profileType: 'full',
      hasAuthFile: true,
      isAvailable: true,
      isFavorite: false,
      createdAt: now,
      lastDiscoveredAt: now,
    );
    final zoeCheck = UsageCheck(
      id: 'zoe-check',
      profileId: 'zoe',
      queryMethod: 'codex-app-server',
      status: 'success',
      startedAt: now,
    );
    final zoeProfile = accountProfile.copyWith(
      id: 'zoe',
      profileName: 'zoe',
      displayName: 'Zoe',
      profileHome: '/tmp/zoe',
    );
    await database.into(database.cliProfiles).insert(accountProfile);
    await database.into(database.cliProfiles).insert(zoeProfile);
    await database.into(database.usageChecks).insert(zoeCheck);
    await database.batch((batch) {
      batch.insertAll(database.quotaWindows, [
        QuotaWindow(
          id: 'zoe-spark-short',
          checkId: zoeCheck.id,
          limitId: 'codex_bengalfox',
          limitName: 'GPT-5.3-Codex-Spark',
          windowType: 'primary',
          usedPercent: 0,
          windowDurationMinutes: 300,
        ),
        QuotaWindow(
          id: 'zoe-codex-weekly',
          checkId: zoeCheck.id,
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 28,
          windowDurationMinutes: 10080,
        ),
        QuotaWindow(
          id: 'zoe-spark-weekly',
          checkId: zoeCheck.id,
          limitId: 'codex_bengalfox',
          limitName: 'GPT-5.3-Codex-Spark',
          windowType: 'secondary',
          usedPercent: 0,
          windowDurationMinutes: 10080,
        ),
      ]);
    });
    final launcher = _RecordingWorkspaceAgentLauncher();
    final workspaces = [
      Workspace(
        id: 'workspace',
        path: currentWorkspacePath,
        pathKey: currentWorkspacePath,
        name: 'nini_hub',
        openCount: 3,
        createdAt: now,
        lastUsedAt: now,
      ),
      Workspace(
        id: 'workspace-2',
        path: '/home/nini/StudioProjects/parla',
        pathKey: '/home/nini/StudioProjects/parla',
        name: 'parla',
        openCount: 2,
        createdAt: now,
        lastUsedAt: now.subtract(const Duration(minutes: 5)),
      ),
      Workspace(
        id: 'workspace-3',
        path: '/home/nini/StudioProjects/bora_asai',
        pathKey: '/home/nini/StudioProjects/bora_asai',
        name: 'bora_asai',
        openCount: 1,
        createdAt: now,
        lastUsedAt: now.subtract(const Duration(minutes: 10)),
      ),
      Workspace(
        id: 'workspace-4',
        path: '/home/nini/StudioProjects/archivo',
        pathKey: '/home/nini/StudioProjects/archivo',
        name: 'archivo',
        openCount: 1,
        createdAt: now,
        lastUsedAt: now.subtract(const Duration(minutes: 15)),
      ),
    ];
    for (final workspace in workspaces) {
      await database.into(database.workspaces).insert(workspace);
    }
    await database.saveSetting('current_workspace_id', 'workspace');
    final navigatorObserver = _NextPopNavigatorObserver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          settingsCardLayoutProvider.overrideWithValue((
            fontScale: .9,
            compactCards: false,
          )),
          workspaceControllerProvider.overrideWith(
            () => _workspaceController(database, launcher: launcher),
          ),
          workspaceDirectoryPickerProvider.overrideWithValue((_) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.dark('cyan'),
          navigatorObservers: [navigatorObserver],
          home: const Scaffold(body: AccountsView()),
        ),
      ),
    );
    await tester.pump();
    final accountsContainer = ProviderScope.containerOf(
      tester.element(find.byType(AccountsView)),
    );
    expect(
      await accountsContainer.read(accountsControllerProvider.notifier).load(),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(AccountCard), findsNWidgets(2));
    for (final card in tester.widgetList<AccountCard>(
      find.byType(AccountCard),
    )) {
      expect(tester.getSize(find.byWidget(card)).height, closeTo(252, .1));
    }
    expect(find.text('Codex · Límite semanal'), findsOneWidget);
    expect(find.text('GPT-5.3-Codex-Spark · Límite semanal'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    await tester.pumpAndSettle();
    final accountGrid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final gridDelegate =
        accountGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(gridDelegate.crossAxisCount, 4);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(900, 620));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Nombre'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Disponibilidad'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Renovación'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Reinicio próximo'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Renovación'));
    await tester.pumpAndSettle();
    expect(
      accountsContainer.read(accountsControllerProvider).query.sort,
      AccountSortMode.renewal,
    );

    expect(find.text('Workspaces recientes'), findsNothing);
    expect(find.text('nini_hub'), findsNothing);
    expect(find.text('3 de 4'), findsNothing);
    expect(find.text('parla'), findsNothing);
    expect(find.text('bora_asai'), findsNothing);
    expect(find.text('archivo'), findsNothing);
    expect(find.byTooltip('Elegir destino'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Lanzar agente').first);
    await tester.pumpAndSettle();

    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.text('Cuenta para lanzar'), findsOneWidget);
    expect(find.text('nini_hub'), findsOneWidget);
    expect(find.byKey(const Key('launch-workspace-search')), findsOneWidget);

    final compactDialogSize = tester.getSize(find.byType(AlertDialog));
    var workspaceRect = tester.getRect(
      find.byKey(const Key('launch-workspace-panel')),
    );
    var accountRect = tester.getRect(
      find.byKey(const Key('launch-account-panel')),
    );
    expect(workspaceRect.right, lessThan(accountRect.left));
    expect(workspaceRect.height, accountRect.height);
    expect(workspaceRect.width, closeTo(accountRect.width, .1));

    var ariRect = tester.getRect(find.byKey(const Key('launch-account-ari')));
    var zoeRect = tester.getRect(find.byKey(const Key('launch-account-zoe')));
    expect(ariRect.top, lessThan(zoeRect.top));
    await tester.tap(find.byTooltip('Ordenar cuentas'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Disponibilidad'),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem,
        ),
      ),
    );
    await tester.pumpAndSettle();
    ariRect = tester.getRect(find.byKey(const Key('launch-account-ari')));
    zoeRect = tester.getRect(find.byKey(const Key('launch-account-zoe')));
    expect(zoeRect.top, lessThan(ariRect.top));

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpAndSettle();
    final largeDialogSize = tester.getSize(find.byType(AlertDialog));
    expect(largeDialogSize.width, greaterThan(compactDialogSize.width));
    expect(largeDialogSize.height, greaterThan(compactDialogSize.height));

    await tester.binding.setSurfaceSize(const Size(700, 620));
    await tester.pumpAndSettle();
    workspaceRect = tester.getRect(
      find.byKey(const Key('launch-workspace-panel')),
    );
    accountRect = tester.getRect(find.byKey(const Key('launch-account-panel')));
    expect(workspaceRect.bottom, lessThan(accountRect.top));

    await tester.binding.setSurfaceSize(const Size(900, 620));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('launch-workspace-search')),
      'archivo',
    );
    await tester.pumpAndSettle();
    expect(find.text('archivo'), findsNWidgets(2));
    expect(find.text('nini_hub'), findsNothing);
    expect(find.text('parla'), findsNothing);
    expect(find.text('Ari'), findsNWidgets(2));
    expect(find.text('Abrir en Inicio'), findsNothing);
    expect(
      tester
          .widget<ListView>(find.byKey(const Key('launch-workspace-list')))
          .scrollDirection,
      Axis.vertical,
    );
    var launchButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Lanzar agente').last,
    );
    expect(launchButton.onPressed, isNull);
    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pumpAndSettle();
    expect(find.text('nini_hub'), findsOneWidget);
    expect(find.text('parla'), findsOneWidget);
    expect(find.text('bora_asai'), findsOneWidget);
    launchButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Lanzar agente').last,
    );
    expect(launchButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('launch-workspace-search')),
      'archivo',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('launch-workspace-list')),
        matching: find.text('archivo'),
      ),
    );
    await tester.pumpAndSettle();
    launchButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Lanzar agente').last,
    );
    expect(launchButton.onPressed, isNotNull);

    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('launch-workspace-list')),
        matching: find.text('nini_hub'),
      ),
    );
    await tester.pumpAndSettle();
    final dialogClosed = navigatorObserver.waitForNextPop();
    await tester.tap(find.widgetWithText(FilledButton, 'Lanzar agente').last);
    await dialogClosed;
    await tester.pumpAndSettle();
    expect(find.byType(LaunchAgentDialog), findsNothing);
    expect(launcher.workingDirectories, [currentWorkspacePath]);
    expect(
      accountsContainer.read(accountsControllerProvider).selectedProfileId,
      'ari',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar lays out at the minimum desktop size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _usageController(
      UsageCalendar([
        UsageCalendarDay(
          day: DateTime(2026, 8, 12),
          tokens: 4500000,
          successfulChecks: 1,
          failedChecks: 0,
          lowestRemaining: 61,
          resetCount: 0,
          renewalCount: 0,
          accounts: const [
            UsageAccountDay(
              profileId: 'sol',
              displayName: 'Sol Team',
              email: 'sol@example.com',
              tokens: 4500000,
              successfulChecks: 1,
              failedChecks: 0,
              lowestRemaining: 61,
              resetCount: 0,
              renewalCount: 0,
            ),
          ],
        ),
        UsageCalendarDay(
          day: DateTime(2026, 8, 13),
          tokens: 322242242,
          successfulChecks: 2,
          failedChecks: 0,
          lowestRemaining: 42,
          resetCount: 1,
          renewalCount: 0,
          accounts: const [
            UsageAccountDay(
              profileId: 'ari',
              displayName: 'Ari Personal',
              email: 'ari@example.com',
              tokens: 322242242,
              successfulChecks: 2,
              failedChecks: 0,
              lowestRemaining: 100,
              resetCount: 1,
              renewalCount: 0,
            ),
          ],
        ),
      ]),
    );
    final container = ProviderContainer(
      overrides: [usageControllerProvider.overrideWith(() => controller)],
    );
    addTearDown(container.dispose);
    final usage = container.read(usageControllerProvider.notifier);
    usage.selectDay(DateTime(2026, 8, 13));
    expect(await usage.loadCalendar(), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark('cyan'),
          home: const Scaffold(body: UsageCalendarView()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Estadísticas de uso'), findsOneWidget);
    expect(find.text('Tokens en Agosto 2026'), findsOneWidget);
    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('Hoy'), findsAtLeastNWidgets(1));
    expect(find.byType(Dialog), findsNothing);
    expect(find.text(formatFullDate(DateTime(2026, 8, 13))), findsOneWidget);
    expect(find.text('322 M'), findsAtLeastNWidgets(1));
    expect(find.text('322.242.242 exactos'), findsAtLeastNWidgets(1));
    expect(
      find.byTooltip(formatTokenDetails(322242242)),
      findsAtLeastNWidgets(2),
    );
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-8-13')));
    await tester.pumpAndSettle();
    expect(find.text('Uso por cuenta'), findsOneWidget);
    expect(find.text('Ari Personal'), findsOneWidget);
    expect(find.text('Cuota disponible'), findsOneWidget);
    expect(find.text('100% disponible'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('calendar-availability-ari')),
          )
          .value,
      1,
    );
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-8-12')));
    await tester.pumpAndSettle();
    expect(find.text(formatFullDate(DateTime(2026, 8, 12))), findsOneWidget);
    expect(find.text('Sol Team'), findsOneWidget);
    expect(find.text('Ari Personal'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    final selectedDay = container.read(usageControllerProvider).selectedDay;
    final nextMonth = DateTime(selectedDay.year, selectedDay.month + 1);
    await tester.tap(find.byTooltip('Mes siguiente'));
    await tester.pumpAndSettle();
    expect(find.text(formatMonth(nextMonth)), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Hoy'));
    await tester.pumpAndSettle();
    expect(find.text(formatMonth(DateTime.now())), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

UsageController _usageController(UsageCalendar calendar) {
  const discovery = _EmptyProfileDiscovery();
  const provider = _UnusedUsageProvider();
  const repository = _UnusedUsageSnapshotRepository();
  const activity = _UnusedUsageActivityRecorder();
  final refreshProfile = RefreshProfileUsage(
    provider: provider,
    repository: repository,
    activity: activity,
  );
  return UsageController(
    refreshUsage: RefreshUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    ),
    refreshAllUsage: RefreshAllUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    ),
    loadUsageCalendar: LoadUsageCalendar(
      repository: _StaticUsageCalendarRepository(calendar),
    ),
  );
}

final class _EmptyProfileDiscovery implements ProfileDiscovery {
  const _EmptyProfileDiscovery();

  @override
  Future<List<Profile>> discover() async => const [];
}

final class _UnusedUsageProvider implements UsageProvider {
  const _UnusedUsageProvider();

  @override
  Future<UsageSnapshot> refresh(Profile profile) =>
      throw UnsupportedError('Refresh is outside this calendar test.');
}

final class _UnusedUsageSnapshotRepository implements UsageSnapshotRepository {
  const _UnusedUsageSnapshotRepository();

  @override
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  }) => throw UnsupportedError('Refresh is outside this calendar test.');
}

final class _UnusedUsageActivityRecorder implements UsageActivityRecorder {
  const _UnusedUsageActivityRecorder();

  @override
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) => throw UnsupportedError('Refresh is outside this calendar test.');
}

final class _StaticUsageCalendarRepository implements UsageCalendarRepository {
  const _StaticUsageCalendarRepository(this.calendar);

  final UsageCalendar calendar;

  @override
  Future<UsageCalendar> loadCalendar() async => calendar;
}

final class _ProviderDiscoveryRunner extends ProcessRunner {
  _ProviderDiscoveryRunner(super.database);

  @override
  Future<SafeProcessResult> run({
    required String executable,
    required List<String> arguments,
    required String summary,
    String? profileId,
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final command = arguments[1];
    final data = command == 'tools'
        ? '{"platform":"linux","tools":['
              '{"id":"claude-cli","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":true},'
              '{"id":"codex","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":true}'
              '],"count":2}'
        : '{"profiles":['
              '{"tool":"claude-cli","name":"research","type":"full","schemaVersion":1,"sizeBytes":1},'
              '{"tool":"codex","name":"team","type":"full","schemaVersion":2,"sizeBytes":1}'
              '],"count":2}';
    final now = DateTime.utc(2026, 8, 24);
    return SafeProcessResult(
      exitCode: 0,
      stdout:
          '{"schemaVersion":1,"command":"$command","ok":true,'
          '"data":$data,"error":null}',
      stderr: '',
      startedAt: now,
      completedAt: now,
    );
  }
}

WorkspaceController _workspaceController(
  AppDatabase database, {
  AgentLauncher? launcher,
}) {
  final repository = DriftWorkspaceRepository(database);
  final selectionStore = DriftWorkspaceSelectionStore(database);
  return WorkspaceController(
    loadWorkspaceHistory: LoadWorkspaceHistory(
      repository: repository,
      selectionStore: selectionStore,
    ),
    addWorkspace: AddWorkspace(
      repository: repository,
      selectionStore: selectionStore,
    ),
    selectWorkspace: SelectWorkspace(
      repository: repository,
      selectionStore: selectionStore,
    ),
    renameWorkspace: RenameWorkspace(repository: repository),
    forgetWorkspace: ForgetWorkspace(
      repository: repository,
      selectionStore: selectionStore,
    ),
    launchAgent: LaunchAgent(
      profileRepository: DriftAgentProfileRepository(database),
      workspaceRepository: repository,
      selectionStore: selectionStore,
      launcher:
          launcher ??
          NiniAgentsAgentLauncher(
            database,
            ProcessRunner(database),
            keepTerminalOpenAfterExit: () => false,
          ),
    ),
  );
}

LaunchProfileOption _launchProfileOptionForTest(Account account) {
  final provider = profileProvider(account.profile.toolKey);
  final subtitle = account.isDeactivated
      ? 'Desactivada en este equipo'
      : !account.profile.isAvailable
      ? 'Perfil no disponible'
      : !account.profile.hasAuthFile && provider.supportsDeviceAuth
      ? 'Cuenta sin vincular'
      : account.displayEmail.isNotEmpty
      ? account.displayEmail
      : account.profile.commandName ?? provider.executable;
  return LaunchProfileOption(
    id: account.profile.id,
    toolKey: account.profile.toolKey,
    displayName: account.profile.displayName,
    subtitle: subtitle,
    canLaunch:
        account.profile.isAvailable &&
        (account.profile.hasAuthFile || !provider.supportsDeviceAuth),
    availablePercent: account.lowestAvailablePercent,
  );
}

Account _domainAccount({
  required CliProfile profile,
  required ProfileMetadata? metadata,
  required Iterable<CostShare> costShares,
  required UsageCheck? currentCheck,
  required Iterable<QuotaWindow> currentWindows,
  required UsageCheck? lastSuccessfulCheck,
  required Iterable<QuotaWindow> lastSuccessfulWindows,
  required ResetCreditSnapshot? resetCredits,
}) => AccountMapper.fromRows(
  profile: profile,
  metadata: metadata,
  costShares: costShares,
  currentCheck: currentCheck,
  currentWindows: currentWindows,
  lastSuccessfulCheck: lastSuccessfulCheck,
  lastSuccessfulWindows: lastSuccessfulWindows,
  resetCredits: resetCredits,
);

final class _RecordingWorkspaceAgentLauncher implements AgentLauncher {
  final List<String> workingDirectories = [];

  @override
  Future<void> launch(
    AgentProfile profile, {
    required String workingDirectory,
  }) async {
    workingDirectories.add(workingDirectory);
  }
}

final class _NextPopNavigatorObserver extends NavigatorObserver {
  Completer<void>? _nextPop;

  Future<void> waitForNextPop() {
    if (_nextPop != null) {
      throw StateError('A route pop is already pending.');
    }
    final completer = Completer<void>();
    _nextPop = completer;
    return completer.future;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final completer = _nextPop;
    _nextPop = null;
    completer?.complete();
    super.didPop(route, previousRoute);
  }
}
