/// The action performed when a global hotkey is pressed.
enum HotkeyAction {
  /// Toggle the active application's suspended state.
  toggle,

  /// Ensure the active application is suspended.
  suspend,

  /// Ensure the previously suspended application is resumed.
  resume,
}
