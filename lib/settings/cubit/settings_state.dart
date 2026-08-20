part of 'settings_cubit.dart';

@freezed
abstract class SettingsState with _$SettingsState {
  const factory SettingsState({
    /// A list of configured app-specific hotkeys.
    required List<AppSpecificHotkey> appSpecificHotKeys,

    /// True if the app should be automatically started on login.
    ///
    /// This is only used on desktop platforms.
    required bool autoStart,

    /// Whether or not to automatically refresh the list of open windows.
    required bool autoRefresh,

    /// Whether the app should continue running in the tray when closed.
    required bool closeToTray,

    /// The hotkey to toggle active application suspend.
    required HotKey hotKey,

    /// The hotkey that ensures the active application is suspended.
    HotKey? suspendHotKey,

    /// The hotkey that ensures the previously suspended application is resumed.
    HotKey? resumeHotKey,

    /// If true the window will be automatically minimized when suspending and
    /// restored when resuming.
    required bool minimizeWindows,

    /// If true suspended windows will be shown at the top of the list.
    required bool pinSuspendedWindows,

    /// How often to automatically refresh the list of open windows, in seconds.
    required int refreshInterval,
    required bool showHiddenWindows,
    required bool startHiddenInTray,

    /// True if the app is currently working on something and a loading
    /// indicator should be shown.
    required bool working,
  }) = _SettingsState;

  /// Private constructor required for custom Freezed methods.
  const SettingsState._();

  /// Returns the configured hotkey for [action], if one is configured.
  HotKey? hotkeyFor(HotkeyAction action) {
    return switch (action) {
      HotkeyAction.toggle => hotKey,
      HotkeyAction.suspend => suspendHotKey,
      HotkeyAction.resume => resumeHotKey,
    };
  }

  factory SettingsState.initial() => SettingsState(
    appSpecificHotKeys: [],
    autoStart: false,
    autoRefresh: true,
    closeToTray: false,
    hotKey: defaultHotkey,
    suspendHotKey: null,
    resumeHotKey: null,
    minimizeWindows: true,
    pinSuspendedWindows: false,
    refreshInterval: 5,
    showHiddenWindows: false,
    startHiddenInTray: false,
    working: false,
  );
}
