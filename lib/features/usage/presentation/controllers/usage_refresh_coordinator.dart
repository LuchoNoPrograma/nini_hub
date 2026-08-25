import 'dart:async';

import 'package:nini_hub/features/usage/presentation/controllers/usage_controller.dart';
import 'package:nini_hub/features/usage/presentation/state/usage_state.dart';

final class UsageRefreshCoordinator {
  UsageRefreshCoordinator({
    required this.controller,
    required this.readState,
    required this.reloadActivity,
    required this.reloadAccounts,
  });

  final UsageController controller;
  final UsageState Function() readState;
  final Future<void> Function() reloadActivity;
  final Future<void> Function() reloadAccounts;
  Future<void> _synchronizationTail = Future.value();

  Future<void> refreshOne(String profileId) async {
    final refreshed = await controller.refreshOne(profileId);
    if (!refreshed) {
      final failure = readState().failureForProfile(profileId);
      if (failure != null) throw StateError(failure.message);
      return;
    }
    await _synchronize(includeAccounts: true);
  }

  Future<void> refreshAll() async {
    final refreshed = await controller.refreshAll();
    if (!refreshed) {
      final failure = readState().batchFailure;
      if (failure != null) throw StateError(failure.message);
      return;
    }
    await _synchronize(includeAccounts: true);
  }

  Future<void> synchronizeCore() => _synchronize(includeAccounts: false);

  Future<void> _synchronize({required bool includeAccounts}) async {
    final predecessor = _synchronizationTail;
    final release = Completer<void>();
    _synchronizationTail = release.future;
    try {
      await predecessor;
      await reloadActivity();
      final loaded = await controller.loadCalendar();
      if (!loaded) {
        final failure = readState().calendarFailure;
        if (failure != null) throw StateError(failure.message);
      }
      if (includeAccounts) await reloadAccounts();
    } finally {
      release.complete();
    }
  }
}
