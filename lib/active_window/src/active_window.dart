import 'package:flutter/foundation.dart';

import '../../argument_parser/argument_parser.dart';
import '../../logs/logs.dart';
import '../../native_platform/native_platform.dart';
import '../../storage/storage_repository.dart';
import '../../window/app_window.dart';

/// Manage the active window.
///
/// We use extra logging here in order to debug issues since this has
/// no user interface.
class ActiveWindow {
  final AppWindow _appWindow;
  final NativePlatform _nativePlatform;
  final ProcessRepository _processRepository;
  final StorageRepository _storageRepository;

  const ActiveWindow(
    this._appWindow,
    this._nativePlatform,
    this._processRepository,
    this._storageRepository,
  );

  /// Maximum number of retries to suspend the active window.
  static const int _maxRetries = 3;

  /// Toggle suspend / resume for the active, foreground window.
  Future<bool> toggle() async {
    log.i('Toggling active window.');

    final savedPid = await _storageRepository.getValue(
      'pid',
      storageArea: 'activeWindow',
    );

    bool successful;
    if (savedPid != null) {
      successful = await _ensureResumed(savedPid);
      if (!successful) log.e('Failed to resume successfully.');
    } else {
      successful = await _suspend();
      if (!successful) log.e('Failed to suspend successfully.');
    }

    return successful;
  }

  /// Ensure the tracked window is suspended.
  ///
  /// If there is no tracked window, the current foreground window becomes the
  /// target. A tracked process which was resumed outside Nyrna is suspended
  /// again without changing the target.
  Future<bool> ensureSuspended() async {
    log.i('Ensuring active window is suspended.');

    final savedPid = await _storageRepository.getValue(
      'pid',
      storageArea: 'activeWindow',
    );

    final bool successful;
    if (savedPid == null) {
      successful = await _suspend();
    } else {
      successful = await _ensureTrackedSuspended(savedPid);
    }

    if (!successful) log.e('Failed to ensure window is suspended.');
    return successful;
  }

  /// Ensure the tracked window is resumed.
  ///
  /// With no tracked window this is a successful no-op. If the tracked process
  /// was resumed outside Nyrna, its saved state is cleared and its window is
  /// restored without attempting to resume the process again.
  Future<bool> ensureResumed() async {
    log.i('Ensuring active window is resumed.');

    final savedPid = await _storageRepository.getValue(
      'pid',
      storageArea: 'activeWindow',
    );
    if (savedPid == null) {
      log.i('No suspended window is being tracked.');
      return true;
    }

    final successful = await _ensureResumed(savedPid);
    if (!successful) log.e('Failed to ensure window is resumed.');
    return successful;
  }

  Future<bool> _ensureTrackedSuspended(int savedPid) async {
    log.i('Ensuring tracked process is suspended, pid: $savedPid');

    if (!await _processRepository.exists(savedPid)) {
      log.w('Tracked process $savedPid no longer exists.');
      await _deleteSavedIds();
      return _suspend();
    }

    final status = await _processRepository.getProcessStatus(savedPid);
    switch (status) {
      case ProcessStatus.suspended:
        log.i('Tracked process $savedPid is already suspended.');
        return true;
      case ProcessStatus.normal:
        final suspended = await _processRepository.suspend(savedPid);
        if (!suspended) {
          log.e('Failed to suspend tracked process $savedPid.');
          return false;
        }
        log.i('Suspended tracked process $savedPid successfully.');
        return true;
      case ProcessStatus.unknown:
        log.e('Cannot suspend tracked process $savedPid: status is unknown.');
        return false;
    }
  }

  Future<bool> _ensureResumed(int savedPid) async {
    log.i('Ensuring tracked process is resumed, pid: $savedPid');

    if (!await _processRepository.exists(savedPid)) {
      log.w('Tracked process $savedPid no longer exists.');
      await _deleteSavedIds();
      return true;
    }

    final status = await _processRepository.getProcessStatus(savedPid);
    if (status == ProcessStatus.unknown) {
      log.e('Cannot resume tracked process $savedPid: status is unknown.');
      return false;
    }

    if (status == ProcessStatus.suspended) {
      final resumed = await _processRepository.resume(savedPid);
      if (!resumed) {
        log.e('Failed to resume! Try resuming process manually?');
        // Must delete here, or enter infinite loop of failing to resume.
        await _deleteSavedIds();
        return false;
      }
    } else {
      log.i('Tracked process $savedPid is already resumed.');
    }

    final windowId = await _storageRepository.getValue(
      'windowId',
      storageArea: 'activeWindow',
    );
    await _deleteSavedIds();
    if (windowId == null) {
      log.e('Failed to find saved windowId, cannot restore.');
    } else {
      await _restore(windowId);
    }

    log.i('Resumed $savedPid successfully.');

    return true;
  }

  Future<void> _deleteSavedIds() async {
    await _storageRepository.deleteValue('pid', storageArea: 'activeWindow');
    await _storageRepository.deleteValue(
      'windowId',
      storageArea: 'activeWindow',
    );
  }

  Future<bool> _suspend() async {
    log.i('Suspending');

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      await _nativePlatform.checkActiveWindow();
      final window = _nativePlatform.activeWindow;

      if (window == null) {
        log.w('No active window found, retrying.');
        if (attempt < _maxRetries - 1) {
          // checkActiveWindow() already waits internally (KDE Wayland uses a
          // polling loop with a 2-second timeout; X11 is synchronous), so no
          // additional delay is needed here.
          continue;
        }
        log.e('Failed to find active window after $_maxRetries attempts.');
        return false;
      }

      final String executable = window.process.executable;

      if (executable == 'nyrna' || executable == 'nyrna.exe') {
        log.w('Active window is Nyrna, hiding and retrying.');
        await _appWindow.hide();
        await Future.delayed(const Duration(milliseconds: 500));
        // checkActiveWindow() will be called at the top of the next iteration.
        continue;
      }

      log.i('Active window: $window');

      if (defaultTargetPlatform == TargetPlatform.windows) {
        // Once in a blue moon on Windows we get "explorer.exe" as the active
        // window, even when no file explorer windows are open / the desktop
        // is not the active element, etc. So we filter it just in case.
        if (window.process.executable == 'explorer.exe') {
          log.e('Only got explorer as active window!');
          return false;
        }
      }

      final pid = window.process.pid;
      if (!await _processRepository.exists(pid)) {
        log.w('Active process $pid no longer exists, retrying.');
        continue;
      }

      final status = await _processRepository.getProcessStatus(pid);
      if (status == ProcessStatus.unknown) {
        log.e('Cannot suspend active process $pid: status is unknown.');
        return false;
      }

      await _minimize(window.id);

      // Small delay on Windows to ensure the window actually minimizes.
      // Doesn't seem to be necessary on Linux.
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (status == ProcessStatus.normal) {
        final suspended = await _processRepository.suspend(pid);
        if (!suspended) {
          log.e('Failed to suspend active window.');
          return false;
        }
      } else {
        log.i('Active process $pid is already suspended.');
      }

      await _storageRepository.saveValue(
        key: 'pid',
        value: pid,
        storageArea: 'activeWindow',
      );
      await _storageRepository.saveValue(
        key: 'windowId',
        value: window.id,
        storageArea: 'activeWindow',
      );
      log.i('Ensured $pid is suspended successfully');

      return true;
    }

    log.e('Failed to suspend after $_maxRetries attempts.');
    return false;
  }

  Future<void> _minimize(String windowId) async {
    final shouldMinimize = await _getShouldMinimize();
    if (!shouldMinimize) return;

    log.i('Starting minimize');
    final minimized = await _nativePlatform.minimizeWindow(windowId);
    if (!minimized) log.e('Failed to minimize window.');
  }

  Future<void> _restore(String windowId) async {
    final shouldRestore = await _getShouldMinimize();
    if (!shouldRestore) return;

    log.i('Starting restore');
    final minimized = await _nativePlatform.restoreWindow(windowId);
    if (!minimized) log.e('Failed to restore window.');
  }

  /// Checks for a user preference on whether to minimize/restore windows.
  Future<bool> _getShouldMinimize() async {
    // If minimize preference was set by flag it overrides UI-based preference.
    final minimizeArg = ArgumentParser.instance.minimize;
    if (minimizeArg != null) {
      log.i('Received no-minimize flag, affecting window state: $minimizeArg');
      return minimizeArg;
    }

    bool? minimize = await _storageRepository.getValue('minimizeWindows');
    minimize ??= true;
    log.i('Minimizing / restoring window: $minimize');
    return minimize;
  }
}
