import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:hotkey_manager/hotkey_manager.dart';

import '../../app/app.dart';
import '../../apps_list/apps_list.dart';
import '../../core/core.dart';
import '../../hotkey/hotkey.dart';
import '../../localization/app_localizations.dart';
import '../../native_platform/native_platform.dart';
import '../../theme/styles.dart';
import '../settings.dart';

// Quick hack, should be moved to a more appropriate place later.
bool _isWayland(BuildContext context) {
  final sessionType = context.read<AppCubit>().state.sessionType;
  return sessionType?.displayProtocol == DisplayProtocol.wayland;
}

/// Add shortcuts and icons for portable builds or autostart.
class IntegrationSection extends StatelessWidget {
  const IntegrationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Spacers.verticalMedium,
        Text(AppLocalizations.of(context)!.systemIntegrationTitle),
        Spacers.verticalXtraSmall,
        const _CloseToTrayTile(),
        const _AutostartTile(),
        const _StartHiddenTile(),
        const _HotkeyConfigWidget(),
        const _AppSpecificHotkeys(),
      ],
    );
  }
}

class _CloseToTrayTile extends StatelessWidget {
  const _CloseToTrayTile();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return SwitchListTile(
          title: Text(AppLocalizations.of(context)!.closeToTray),
          secondary: const Icon(Icons.bedtime),
          value: state.closeToTray,
          onChanged: (bool value) async {
            await settingsCubit.updateCloseToTray(value);

            if (state.startHiddenInTray && !value) {
              await settingsCubit.updateStartHiddenInTray(false);
            }
          },
        );
      },
    );
  }
}

class _AutostartTile extends StatelessWidget {
  const _AutostartTile();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return SwitchListTile(
          secondary: const Icon(Icons.start),
          title: Text(AppLocalizations.of(context)!.startAutomatically),
          value: state.autoStart,
          onChanged: (bool value) async {
            await settingsCubit.toggleAutostart();

            if (state.startHiddenInTray && !value) {
              await settingsCubit.updateStartHiddenInTray(false);
            }
          },
        );
      },
    );
  }
}

class _StartHiddenTile extends StatelessWidget {
  const _StartHiddenTile();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return SwitchListTile(
          secondary: const Icon(Icons.auto_awesome),
          title: Text(AppLocalizations.of(context)!.startInTray),
          value: state.startHiddenInTray,
          onChanged: (bool value) async {
            if (!state.closeToTray && value) {
              await settingsCubit.updateCloseToTray(true);
            }

            if (!state.autoStart && value) {
              await settingsCubit.toggleAutostart();
            }

            await settingsCubit.updateStartHiddenInTray(value);
          },
        );
      },
    );
  }
}

class _HotkeyConfigWidget extends StatelessWidget {
  const _HotkeyConfigWidget();

  @override
  Widget build(BuildContext context) {
    if (_isWayland(context)) {
      // Hotkey manager doesn't work on Wayland, so we hide the hotkey settings in that
      // case. Instead show a web link to the docs about how to setup a custom hotkey
      // through the DE.
      return ListTile(
        leading: const Icon(Icons.keyboard),
        title: Text(AppLocalizations.of(context)!.hotkey),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.waylandHotkeyMessage),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => context.read<AppCubit>().launchURL(kWaylandHotkeyDocsUrl),
              child: Text(AppLocalizations.of(context)!.waylandHotkeyDocsLink),
            ),
          ],
        ),
      );
    }

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final localizations = AppLocalizations.of(context)!;

        return Column(
          children: [
            _HotkeyTile(
              title: localizations.toggleHotkey,
              icon: Icons.sync,
              action: HotkeyAction.toggle,
              hotkey: state.hotkeyFor(HotkeyAction.toggle),
            ),
            _HotkeyTile(
              title: localizations.suspendHotkey,
              icon: Icons.pause,
              action: HotkeyAction.suspend,
              hotkey: state.hotkeyFor(HotkeyAction.suspend),
            ),
            _HotkeyTile(
              title: localizations.resumeHotkey,
              icon: Icons.play_arrow,
              action: HotkeyAction.resume,
              hotkey: state.hotkeyFor(HotkeyAction.resume),
            ),
          ],
        );
      },
    );
  }
}

class _HotkeyTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final HotkeyAction action;
  final HotKey? hotkey;

  const _HotkeyTile({
    required this.title,
    required this.icon,
    required this.action,
    required this.hotkey,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      leading: Icon(icon),
      trailing: ElevatedButton(
        onPressed: () => _showHotkeyDialog(
          context: context,
          action: action,
          initialHotkey: hotkey,
        ),
        child: Text(
          hotkey == null
              ? AppLocalizations.of(context)!.hotkeyNotSet
              : hotkeyLabel(hotkey!),
        ),
      ),
    );
  }
}

Future<void> _showHotkeyDialog({
  required BuildContext context,
  required HotkeyAction action,
  required HotKey? initialHotkey,
}) async {
  await settingsCubit.removeHotkey(action);

  if (!context.mounted) {
    if (initialHotkey != null) {
      await settingsCubit.updateHotkey(initialHotkey, action);
    }
    return;
  }

  final completed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _RecordHotKeyDialog(action: action, initialHotkey: initialHotkey),
  );

  // A dialog should only be closed through its buttons, but restore the old
  // registration if its route is removed unexpectedly.
  if (completed != true && initialHotkey != null) {
    await settingsCubit.updateHotkey(initialHotkey, action);
  }
}

class _RecordHotKeyDialog extends StatefulWidget {
  final HotkeyAction action;
  final HotKey? initialHotkey;

  const _RecordHotKeyDialog({
    required this.action,
    required this.initialHotkey,
  });

  @override
  // ignore: library_private_types_in_public_api
  _RecordHotKeyDialogState createState() => _RecordHotKeyDialogState();
}

class _RecordHotKeyDialogState extends State<_RecordHotKeyDialog> {
  HotKey? _hotKey;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _reset() async {
    setState(() => _isSaving = true);
    final reset = await settingsCubit.resetHotkey(widget.action);

    if (!mounted) return;

    if (!reset) {
      setState(() {
        _isSaving = false;
        _errorMessage = AppLocalizations.of(context)!.hotkeyAlreadyAssigned;
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  Future<void> _cancel() async {
    setState(() => _isSaving = true);

    if (widget.initialHotkey != null) {
      await settingsCubit.updateHotkey(widget.initialHotkey!, widget.action);
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirm() async {
    final hotkey = _hotKey;
    if (hotkey == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final updated = await settingsCubit.updateHotkey(hotkey, widget.action);
    if (!mounted) return;

    if (updated) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSaving = false;
      _errorMessage = AppLocalizations.of(context)!.hotkeyAlreadyAssigned;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Row(
                children: [
                  Text(AppLocalizations.of(context)!.recordNewHotkey),
                  const Spacer(),
                  Tooltip(
                    message: AppLocalizations.of(context)!.resetHotkey,
                    child: IconButton(
                      icon: const Icon(Icons.restore),
                      onPressed: _isSaving ? null : _reset,
                    ),
                  ),
                ],
              ),
              Container(
                width: 100,
                height: 60,
                margin: const EdgeInsets.only(top: 20),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).primaryColor),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    HotKeyRecorder(
                      initalHotKey: widget.initialHotkey,
                      onHotKeyRecorded: (hotkey) {
                        setState(() {
                          _hotKey = hotkey;
                          _errorMessage = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _isSaving ? null : _cancel,
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: _hotKey == null || _isSaving ? null : _confirm,
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
  }
}

/// Hotkeys to toggle specific apps.
class _AppSpecificHotkeys extends StatelessWidget {
  const _AppSpecificHotkeys();

  @override
  Widget build(BuildContext context) {
    if (_isWayland(context)) {
      // Global hotkeys don't work on Wayland.
      return const SizedBox();
    }

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return Card(
          child: Column(
            children: [
              ListTile(
                title: Text(AppLocalizations.of(context)!.appSpecificHotkeys),
                leading: const Icon(Icons.keyboard),
                trailing: Tooltip(
                  message: AppLocalizations.of(context)!.appSpecificHotkeysTooltip,
                  child: const Icon(Icons.help_outline),
                ),
              ),
              for (var hotkey in state.appSpecificHotKeys)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      leading: Text(hotkeyLabel(hotkey.hotkey)),
                      title: Text(hotkey.executable),
                      trailing: ElevatedButton(
                        onPressed: () => settingsCubit.removeAppSpecificHotkey(
                          hotkey.executable,
                        ),
                        child: const Icon(Icons.delete),
                      ),
                    ),
                  ),
                ),
              ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const _AddAppSpecificHotkeyDialog(),
                  );
                },
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

class _AddAppSpecificHotkeyDialog extends StatelessWidget {
  const _AddAppSpecificHotkeyDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: BlocBuilder<AppsListCubit, AppsListState>(
        builder: (context, state) {
          final executables = state.windows
              .map((window) => window.process.executable)
              .toSet()
              .toList();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.of(context)!.addAppSpecificHotkey),
              const SizedBox(height: 20),
              DropdownButton<String>(
                value: null,
                hint: Text(AppLocalizations.of(context)!.selectApp),
                items: executables.map((executable) {
                  return DropdownMenuItem<String>(
                    value: executable,
                    child: Text(executable),
                  );
                }).toList(),
                isExpanded: true,
                onChanged: (executable) async {
                  if (executable == null) return;

                  final navigator = Navigator.of(context);

                  await showDialog(
                    context: context,
                    builder: (context) =>
                        _RecordAppSpecificHotkeyDialog(executable: executable),
                  );

                  navigator.pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordAppSpecificHotkeyDialog extends StatefulWidget {
  final String executable;

  const _RecordAppSpecificHotkeyDialog({required this.executable});

  @override
  _RecordAppSpecificHotkeyDialogState createState() =>
      _RecordAppSpecificHotkeyDialogState();
}

class _RecordAppSpecificHotkeyDialogState extends State<_RecordAppSpecificHotkeyDialog> {
  HotKey? _hotKey;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _confirm() async {
    final hotkey = _hotKey;
    if (hotkey == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final added = await settingsCubit.addAppSpecificHotkey(
      widget.executable,
      hotkey,
    );
    if (!mounted) return;

    if (added) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSaving = false;
      _errorMessage = AppLocalizations.of(context)!.hotkeyAlreadyAssigned;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Text(AppLocalizations.of(context)!.recordNewHotkey),
            Container(
              width: 100,
              height: 60,
              margin: const EdgeInsets.only(top: 20),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).primaryColor),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  HotKeyRecorder(
                    onHotKeyRecorded: (hotKey) {
                      setState(() {
                        _hotKey = hotKey;
                        _errorMessage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: _hotKey == null || _isSaving ? null : _confirm,
          child: Text(AppLocalizations.of(context)!.confirm),
        ),
      ],
    );
  }
}
