import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:helpers/helpers.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../autostart/autostart_service.dart';
import '../../core/core.dart';
import '../../hotkey/global/global.dart';
import '../../logs/logging_manager.dart';
import '../../storage/storage_repository.dart';

part 'settings_state.dart';
part 'settings_cubit.freezed.dart';

late SettingsCubit settingsCubit;

class SettingsCubit extends Cubit<SettingsState> {
  /// Service for managing autostart.
  final AutostartService _autostartService;
  final HotkeyService _hotkeyService;
  final StorageRepository _storage;

  SettingsCubit._(
    this._autostartService,
    this._hotkeyService,
    this._storage, {
    required SettingsState initialState,
  }) : super(initialState) {
    settingsCubit = this;
  }

  Future<void> _registerHotkeys() async {
    for (final action in HotkeyAction.values) {
      final hotkey = state.hotkeyFor(action);
      if (hotkey != null) await _hotkeyService.addHotkey(hotkey);
    }

    for (final hotkey in state.appSpecificHotKeys) {
      await _hotkeyService.addHotkey(hotkey.hotkey);
    }
  }

  static Future<SettingsCubit> init({
    required AutostartService autostartService,
    required HotkeyService hotkeyService,
    required StorageRepository storage,
  }) async {
    final List<String>? appSpecificHotkeysJson = await storage.getValue(
      'appSpecificHotKeys',
    );
    final List<AppSpecificHotkey> appSpecificHotKeys =
        appSpecificHotkeysJson
            ?.map((e) => AppSpecificHotkey.fromJson(jsonDecode(e)))
            .toList() ??
        [];

    final bool autoStart = await storage.getValue('autoStart') ?? false;
    final bool autoRefresh = await storage.getValue('autoRefresh') ?? true;
    final bool closeToTray = await storage.getValue('closeToTray') ?? false;

    final HotKey hotkey = await _loadHotkey(storage, 'hotkey') ?? defaultHotkey;
    final HotKey? suspendHotkey = await _loadHotkey(storage, 'suspendHotkey');
    final HotKey? resumeHotkey = await _loadHotkey(storage, 'resumeHotkey');

    final bool minimizeWindows = await storage.getValue('minimizeWindows') ?? true;
    final bool pinSuspendedWindows =
        await storage.getValue('pinSuspendedWindows') ?? false;
    final int refreshInterval = await storage.getValue('refreshInterval') ?? 5;
    final bool showHiddenWindows = await storage.getValue('showHiddenWindows') ?? false;
    final bool startHiddenInTray = await storage.getValue('startHiddenInTray') ?? false;

    final cubit = SettingsCubit._(
      autostartService,
      hotkeyService,
      storage,
      initialState: SettingsState(
        appSpecificHotKeys: appSpecificHotKeys,
        autoStart: autoStart,
        autoRefresh: autoRefresh,
        closeToTray: closeToTray,
        hotKey: hotkey,
        suspendHotKey: suspendHotkey,
        resumeHotKey: resumeHotkey,
        minimizeWindows: minimizeWindows,
        pinSuspendedWindows: pinSuspendedWindows,
        refreshInterval: refreshInterval,
        showHiddenWindows: showHiddenWindows,
        startHiddenInTray: startHiddenInTray,
        working: false,
      ),
    );
    await cubit._registerHotkeys();
    return cubit;
  }

  static Future<HotKey?> _loadHotkey(StorageRepository storage, String key) async {
    final String? savedHotkey = await storage.getValue(key);
    if (savedHotkey == null) return null;
    return HotKey.fromJson(jsonDecode(savedHotkey));
  }

  /// Add a new hotkey for a specific application.
  Future<bool> addAppSpecificHotkey(String executable, HotKey newHotKey) async {
    if (_isHotkeyAssigned(newHotKey)) return false;

    final List<AppSpecificHotkey> appSpecificHotkeys = [
      ...state.appSpecificHotKeys,
      AppSpecificHotkey(executable: executable, hotkey: newHotKey),
    ];

    emit(state.copyWith(appSpecificHotKeys: appSpecificHotkeys));
    await _hotkeyService.addHotkey(newHotKey);
    await _storage.saveValue(
      key: 'appSpecificHotKeys',
      value: appSpecificHotkeys.map((e) => jsonEncode(e.toJson())).toList(),
    );
    return true;
  }

  /// If user wishes to ignore this update, save choice to storage.
  Future<void> ignoreUpdate(String version) async {
    await _storage.saveValue(key: 'ignoredUpdate', value: version);
  }

  Future<void> setRefreshInterval(int interval) async {
    if (interval > 0) {
      await _storage.saveValue(key: 'refreshInterval', value: interval);
      emit(state.copyWith(refreshInterval: interval));
    }
  }

  Future<void> updateAutoRefresh(bool? enabled) async {
    if (enabled == null) return;

    await _storage.saveValue(key: 'autoRefresh', value: enabled);
    emit(state.copyWith(autoRefresh: enabled));
  }

  Future<void> updateCloseToTray([bool? closeToTray]) async {
    if (closeToTray == null) return;

    await _storage.saveValue(key: 'closeToTray', value: closeToTray);
    emit(state.copyWith(closeToTray: closeToTray));
  }

  /// Update the preference for auto minimizing windows.
  Future<void> updateMinimizeWindows(bool value) async {
    emit(state.copyWith(minimizeWindows: value));
    await _storage.saveValue(key: 'minimizeWindows', value: value);
  }

  /// Update the preference for pinning suspended windows to the top of the list.
  Future<void> updatePinSuspendedWindows(bool value) async {
    emit(state.copyWith(pinSuspendedWindows: value));
    await _storage.saveValue(key: 'pinSuspendedWindows', value: value);
  }

  Future<void> updateShowHiddenWindows(bool value) async {
    await _storage.saveValue(key: 'showHiddenWindows', value: value);
    emit(state.copyWith(showHiddenWindows: value));
  }

  Future<void> updateStartHiddenInTray(bool value) async {
    await _storage.saveValue(key: 'startHiddenInTray', value: value);
    emit(state.copyWith(startHiddenInTray: value));
  }

  /// Remove the hotkey for a specific application.
  Future<void> removeAppSpecificHotkey(String executable) async {
    final AppSpecificHotkey appSpecificHotkey = state.appSpecificHotKeys.firstWhere(
      (e) => e.executable == executable,
    );

    final List<AppSpecificHotkey> appSpecificHotkeys = state.appSpecificHotKeys
        .where((e) => e.executable != executable)
        .toList();

    emit(state.copyWith(appSpecificHotKeys: appSpecificHotkeys));
    await _hotkeyService.removeHotkey(appSpecificHotkey.hotkey);
    await _storage.saveValue(
      key: 'appSpecificHotKeys',
      value: appSpecificHotkeys.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  /// Unregister the global hotkey for [action].
  ///
  /// The configured value remains in state so a recording dialog can restore
  /// it if the user cancels.
  Future<void> removeHotkey([HotkeyAction action = HotkeyAction.toggle]) async {
    final hotkey = state.hotkeyFor(action);
    if (hotkey == null) return;
    await _hotkeyService.removeHotkey(hotkey);
  }

  /// Reset the global hotkey for [action].
  ///
  /// Toggle retains the historical Pause default. Suspend and resume are
  /// optional, so resetting either removes its binding.
  Future<bool> resetHotkey([HotkeyAction action = HotkeyAction.toggle]) async {
    final currentHotkey = state.hotkeyFor(action);

    if (action == HotkeyAction.toggle &&
        _isHotkeyAssigned(defaultHotkey, excludingAction: action)) {
      // The recording dialog temporarily unregisters the current binding.
      if (currentHotkey != null) {
        await _hotkeyService.addHotkey(currentHotkey);
      }
      return false;
    }

    if (currentHotkey != null) {
      await _hotkeyService.removeHotkey(currentHotkey);
    }

    if (action == HotkeyAction.toggle) {
      await _hotkeyService.addHotkey(defaultHotkey);
      emit(state.copyWith(hotKey: defaultHotkey));
    } else {
      emit(_copyWithHotkey(action, null));
    }

    await _storage.deleteValue(_storageKeyFor(action));
    return true;
  }

  /// Set whether or not to show verbose logging.
  Future<void> setVerboseLogging(bool value) async {
    await LoggingManager.initialize(verbose: value);
    await _storage.saveValue(key: 'verboseLogging', value: value);
  }

  /// Toggle autostart on Desktop.
  Future<void> toggleAutostart() async {
    assert(defaultTargetPlatform.isDesktop);

    emit(state.copyWith(working: true));

    if (state.autoStart) {
      await _autostartService.disable();
    } else {
      await _autostartService.enable();
    }

    emit(state.copyWith(autoStart: !state.autoStart, working: false));
    await _storage.saveValue(key: 'autoStart', value: state.autoStart);
  }

  /// Updates the global hotkey for [action].
  ///
  /// Returns false when [newHotKey] is already used by another global action
  /// or by an app-specific binding. In that case no state or storage is
  /// changed, and the current binding is ensured to be registered again.
  Future<bool> updateHotkey(
    HotKey newHotKey, [
    HotkeyAction action = HotkeyAction.toggle,
  ]) async {
    if (_isHotkeyAssigned(newHotKey, excludingAction: action)) {
      final currentHotkey = state.hotkeyFor(action);
      if (currentHotkey != null) {
        await _hotkeyService.addHotkey(currentHotkey);
      }
      return false;
    }

    final currentHotkey = state.hotkeyFor(action);
    if (currentHotkey != null && _sameBinding(currentHotkey, newHotKey)) {
      // The recording dialog temporarily unregisters the current binding.
      // Remove first so the replacement is safe even outside that flow.
      await _hotkeyService.removeHotkey(currentHotkey);
    } else {
      await _hotkeyService.addHotkey(newHotKey);
      if (currentHotkey != null) {
        await _hotkeyService.removeHotkey(currentHotkey);
      }
    }

    if (currentHotkey != null && _sameBinding(currentHotkey, newHotKey)) {
      await _hotkeyService.addHotkey(newHotKey);
    }

    emit(_copyWithHotkey(action, newHotKey));
    await _storage.saveValue(
      key: _storageKeyFor(action),
      value: jsonEncode(newHotKey.toJson()),
    );
    return true;
  }

  bool _isHotkeyAssigned(
    HotKey newHotKey, {
    HotkeyAction? excludingAction,
  }) {
    for (final otherAction in HotkeyAction.values) {
      if (otherAction == excludingAction) continue;

      final otherHotkey = state.hotkeyFor(otherAction);
      if (otherHotkey != null && _sameBinding(newHotKey, otherHotkey)) {
        return true;
      }
    }

    return state.appSpecificHotKeys.any(
      (appHotkey) => _sameBinding(newHotKey, appHotkey.hotkey),
    );
  }

  SettingsState _copyWithHotkey(HotkeyAction action, HotKey? hotkey) {
    return switch (action) {
      HotkeyAction.toggle => state.copyWith(hotKey: hotkey!),
      HotkeyAction.suspend => state.copyWith(suspendHotKey: hotkey),
      HotkeyAction.resume => state.copyWith(resumeHotKey: hotkey),
    };
  }

  static String _storageKeyFor(HotkeyAction action) {
    return switch (action) {
      HotkeyAction.toggle => 'hotkey',
      HotkeyAction.suspend => 'suspendHotkey',
      HotkeyAction.resume => 'resumeHotkey',
    };
  }

  static bool _sameBinding(HotKey first, HotKey second) {
    if (first.physicalKey != second.physicalKey) return false;

    final firstModifiers = {...?first.modifiers};
    final secondModifiers = {...?second.modifiers};
    return firstModifiers.length == secondModifiers.length &&
        firstModifiers.containsAll(secondModifiers);
  }
}
