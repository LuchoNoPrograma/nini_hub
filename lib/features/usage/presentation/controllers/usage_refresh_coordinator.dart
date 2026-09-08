import 'dart:async';

import 'package:nini_hub/features/usage/domain/usage_failure.dart';
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
  int _pendingSynchronizations = 0;

  Future<void> refreshOne(String profileId) async {
    final refreshed = await controller.refreshOne(profileId);
    if (!refreshed) {
      final failure = readState().failureForProfile(profileId);
      if (failure?.cause is UsageRefreshAppliedFailure) {
        await _synchronize(includeAccounts: true);
      }
      if (failure != null) throw StateError(failure.message);
      return;
    }
    await _synchronize(includeAccounts: true);
  }

  Future<void> refreshAll() async {
    final refreshed = await controller.refreshAll();
    if (!refreshed) {
      final state = readState();
      if (state.persistedBatchProfileIds.isNotEmpty) {
        await _synchronize(includeAccounts: true);
      }
      final failure = state.batchFailure;
      if (failure != null) throw StateError(failure.message);
      return;
    }
    await _synchronize(includeAccounts: true);
  }

  Future<void> synchronizePersistedUsage() =>
      _synchronize(includeAccounts: true);

  Future<void> synchronizeCore() => _synchronize(includeAccounts: false);

  Future<void> _synchronize({required bool includeAccounts}) async {
    _pendingSynchronizations++;
    controller.setSynchronizing(true);
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
      _pendingSynchronizations--;
      if (_pendingSynchronizations == 0) controller.setSynchronizing(false);
    }
  }
}
