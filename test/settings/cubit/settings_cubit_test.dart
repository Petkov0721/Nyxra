import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nyrna/apps_list/cubit/apps_list_cubit.dart';
import 'package:nyrna/autostart/autostart_service.dart';
import 'package:nyrna/hotkey/global/global.dart';
import 'package:nyrna/settings/settings.dart';
import 'package:nyrna/storage/storage_repository.dart';
import 'package:nyrna/window/app_window.dart';

@GenerateNiceMocks(<MockSpec>[
  MockSpec<AppsListCubit>(),
  MockSpec<AutostartService>(),
  MockSpec<HotkeyService>(),
  MockSpec<AppWindow>(),
  MockSpec<StorageRepository>(),
])
import 'settings_cubit_test.mocks.dart';

final appsListCubit = MockAppsListCubit();
final appWindow = MockAppWindow();
final autostartService = MockAutostartService();
final hotkeyService = MockHotkeyService();
final storage = MockStorageRepository();

/// Cubit being tested
late SettingsCubit cubit;
SettingsState get state => cubit.state;

void main() {
  setUp((() async {
    reset(appsListCubit);
    reset(appWindow);
    reset(autostartService);
    reset(hotkeyService);
    reset(storage);

    when(autostartService.enable()).thenAnswer((_) async {});
    when(autostartService.disable()).thenAnswer((_) async {});

    when(hotkeyService.addHotkey(any)).thenAnswer((_) async {});
    when(hotkeyService.removeHotkey(any)).thenAnswer((_) async {});

    when(storage.getValue('hotkey')).thenAnswer((_) async {});
    when(storage.deleteValue(any)).thenAnswer((_) async {});
    when(
      storage.saveValue(key: anyNamed('key'), value: anyNamed('value')),
    ).thenAnswer((_) async {});
    when(
      storage.saveValue(key: anyNamed('key'), value: anyNamed('value')),
    ).thenAnswer((_) async {});
    when(
      storage.saveValue(key: anyNamed('key'), value: anyNamed('value')),
    ).thenAnswer((_) async {});

    // StorageRepository
    when(
      storage.getValue(any, storageArea: anyNamed('storageArea')),
    ).thenAnswer((_) async => null);
    when(
      storage.saveValue(
        key: anyNamed('key'),
        value: anyNamed('value'),
        storageArea: anyNamed('storageArea'),
      ),
    ).thenAnswer((_) async {});

    cubit = await SettingsCubit.init(
      autostartService: autostartService,
      hotkeyService: hotkeyService,
      storage: storage,
    );
  }));

  group('SettingsCubit:', () {
    test('can be instantiated', () {
      expect(cubit, isA<SettingsCubit>());
    });

    test('instance variable is populated', () {
      expect(settingsCubit, isA<SettingsCubit>());
    });

    test('default state is as expected', () {
      expect(state.autoStart, false);
      expect(state.autoRefresh, true);
      expect(state.closeToTray, false);
      expect(state.hotKey.physicalKey, PhysicalKeyboardKey.pause);
      expect(state.suspendHotKey, isNull);
      expect(state.resumeHotKey, isNull);
      expect(state.refreshInterval, 5);
      expect(state.showHiddenWindows, false);
      expect(state.startHiddenInTray, false);
    });

    test('ignoring update works', () async {
      await cubit.ignoreUpdate('1.0.0');
      verify(storage.saveValue(key: 'ignoredUpdate', value: '1.0.0')).called(1);
    });

    test('setRefreshInterval works', () async {
      const defaultInterval = 5;
      const newInterval = 30;
      expect(state.refreshInterval, defaultInterval);
      await cubit.setRefreshInterval(newInterval);
      expect(state.refreshInterval, newInterval);
      verify(storage.saveValue(key: 'refreshInterval', value: newInterval)).called(1);
    });

    test('updating autoRefresh works', () async {
      expect(state.autoRefresh, true);
      await cubit.updateAutoRefresh(false);
      expect(state.autoRefresh, false);
      verify(storage.saveValue(key: 'autoRefresh', value: false)).called(1);
    });

    test('updateCloseToTray works', () async {
      expect(state.closeToTray, false);
      await cubit.updateCloseToTray(true);
      expect(state.closeToTray, true);
      verify(storage.saveValue(key: 'closeToTray', value: true)).called(1);
    });

    test('updateMinimizeWindows works', () async {
      // Default should be true.
      expect(state.minimizeWindows, true);
      await cubit.updateMinimizeWindows(false);
      expect(state.minimizeWindows, false);
      verify(storage.saveValue(key: 'minimizeWindows', value: false)).called(1);
      await cubit.updateMinimizeWindows(true);
      expect(state.minimizeWindows, true);
      verify(storage.saveValue(key: 'minimizeWindows', value: true)).called(1);
    });

    test('updateShowHiddenWindows works', () async {
      expect(state.showHiddenWindows, false);
      await cubit.updateShowHiddenWindows(true);
      expect(state.showHiddenWindows, true);
      verify(storage.saveValue(key: 'showHiddenWindows', value: true)).called(1);
    });

    test('updateStartHiddenInTray works', () async {
      expect(state.startHiddenInTray, false);
      await cubit.updateStartHiddenInTray(true);
      expect(state.startHiddenInTray, true);
      verify(storage.saveValue(key: 'startHiddenInTray', value: true)).called(1);
    });

    group('autostart:', () {
      test('disabled by default', () {
        expect(state.autoStart, false);
      });

      test('updating saves preference to storage', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        expect(state.autoStart, false);
        await cubit.toggleAutostart();
        expect(state.autoStart, true);
        verify(storage.saveValue(key: 'autoStart', value: true)).called(1);
        await cubit.toggleAutostart();
        expect(state.autoStart, false);
        verify(storage.saveValue(key: 'autoStart', value: false)).called(1);
        debugDefaultTargetPlatformOverride = null;
      });

      test('enabling autostart calls AutostartService.enable()', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        expect(state.autoStart, false);
        await cubit.toggleAutostart();
        verify(autostartService.enable()).called(1);
        debugDefaultTargetPlatformOverride = null;
      });

      test('disabling autostart calls AutostartService.disable()', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        when(storage.getValue('autoStart')).thenAnswer((_) async => true);
        cubit = await SettingsCubit.init(
          autostartService: autostartService,
          hotkeyService: hotkeyService,
          storage: storage,
        );
        expect(state.autoStart, true);
        await cubit.toggleAutostart();
        verify(autostartService.disable()).called(1);
        debugDefaultTargetPlatformOverride = null;
      });
    });

    group('settings loaded from storage on init:', () {
      test('minimizeWindows is loaded', () async {
        when(storage.getValue('minimizeWindows')).thenAnswer((_) async => false);
        cubit = await SettingsCubit.init(
          autostartService: autostartService,
          hotkeyService: hotkeyService,
          storage: storage,
        );
        expect(state.minimizeWindows, false);
      });

      test('refreshInterval is loaded', () async {
        when(storage.getValue('refreshInterval')).thenAnswer((_) async => 30);
        cubit = await SettingsCubit.init(
          autostartService: autostartService,
          hotkeyService: hotkeyService,
          storage: storage,
        );
        expect(state.refreshInterval, 30);
      });

      test('showHiddenWindows is loaded', () async {
        when(storage.getValue('showHiddenWindows')).thenAnswer((_) async => true);
        cubit = await SettingsCubit.init(
          autostartService: autostartService,
          hotkeyService: hotkeyService,
          storage: storage,
        );
        expect(state.showHiddenWindows, true);
      });

      test('closeToTray is loaded', () async {
        when(storage.getValue('closeToTray')).thenAnswer((_) async => true);
        cubit = await SettingsCubit.init(
          autostartService: autostartService,
          hotkeyService: hotkeyService,
          storage: storage,
        );
        expect(state.closeToTray, true);
      });
    });

    group('hotkey:', () {
      test('default hotkey is Pause', () {
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.pause);
        expect(state.hotKey.modifiers, null);
        expect(state.hotkeyFor(HotkeyAction.toggle), state.hotKey);
        expect(state.hotkeyFor(HotkeyAction.suspend), isNull);
        expect(state.hotkeyFor(HotkeyAction.resume), isNull);
      });

      test('removeHotkey works', () async {
        await cubit.removeHotkey();
        verify(hotkeyService.removeHotkey(any)).called(1);
      });

      test('removeHotkey targets each configured action', () async {
        final suspendHotkey = HotKey(key: PhysicalKeyboardKey.f6);
        final resumeHotkey = HotKey(key: PhysicalKeyboardKey.f7);
        await cubit.updateHotkey(suspendHotkey, HotkeyAction.suspend);
        await cubit.updateHotkey(resumeHotkey, HotkeyAction.resume);
        clearInteractions(hotkeyService);

        await cubit.removeHotkey(HotkeyAction.toggle);
        await cubit.removeHotkey(HotkeyAction.suspend);
        await cubit.removeHotkey(HotkeyAction.resume);

        verify(hotkeyService.removeHotkey(state.hotKey)).called(1);
        verify(hotkeyService.removeHotkey(suspendHotkey)).called(1);
        verify(hotkeyService.removeHotkey(resumeHotkey)).called(1);
      });

      test('resetting hotkey restores Pause default', () async {
        await cubit.updateHotkey(HotKey(key: PhysicalKeyboardKey.insert));
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.insert);
        await cubit.resetHotkey();
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.pause);
        verify(storage.deleteValue('hotkey')).called(1);
      });

      test('saved hotkey is loaded', () async {
        when(storage.getValue('hotkey')).thenAnswer(
          (_) async =>
              '{"keyCode":"insert","modifiers":[],"identifier":"7fe60a47-35b9-4d40-8f74-ec77b83687b3","scope":"system"}',
        );
        cubit = await SettingsCubit.init(
          autostartService: autostartService,
          hotkeyService: hotkeyService,
          storage: storage,
        );
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.insert);
        expect(state.hotKey.modifiers?.isEmpty, true);
      });

      test('all saved global hotkeys are loaded and registered', () async {
        final toggleHotkey = HotKey(key: PhysicalKeyboardKey.f9);
        final suspendHotkey = HotKey(key: PhysicalKeyboardKey.f10);
        final resumeHotkey = HotKey(key: PhysicalKeyboardKey.f11);
        when(
          storage.getValue('hotkey'),
        ).thenAnswer((_) async => jsonEncode(toggleHotkey.toJson()));
        when(
          storage.getValue('suspendHotkey'),
        ).thenAnswer((_) async => jsonEncode(suspendHotkey.toJson()));
        when(
          storage.getValue('resumeHotkey'),
        ).thenAnswer((_) async => jsonEncode(resumeHotkey.toJson()));
        clearInteractions(hotkeyService);

        cubit = await SettingsCubit.init(
          autostartService: autostartService,
          hotkeyService: hotkeyService,
          storage: storage,
        );

        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.f9);
        expect(state.suspendHotKey?.physicalKey, PhysicalKeyboardKey.f10);
        expect(state.resumeHotKey?.physicalKey, PhysicalKeyboardKey.f11);
        final registeredHotkeys = verify(
          hotkeyService.addHotkey(captureAny),
        ).captured.cast<HotKey>();
        expect(registeredHotkeys, hasLength(3));
        expect(
          registeredHotkeys.map((hotkey) => hotkey.physicalKey),
          containsAll([
            PhysicalKeyboardKey.f9,
            PhysicalKeyboardKey.f10,
            PhysicalKeyboardKey.f11,
          ]),
        );
      });

      test('updateHotkey & resetHotkey work', () async {
        final newHotkey = HotKey(key: PhysicalKeyboardKey.f12);
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.pause);
        await cubit.updateHotkey(newHotkey);
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.f12);
        verify(hotkeyService.addHotkey(newHotkey)).called(1);
        await cubit.resetHotkey();
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.pause);
        verify(storage.deleteValue('hotkey')).called(1);
      });

      test('updateHotkey saves hotkey to storage as JSON', () async {
        final newHotkey = HotKey(key: PhysicalKeyboardKey.f5);
        await cubit.updateHotkey(newHotkey);
        verify(storage.saveValue(key: 'hotkey', value: anyNamed('value'))).called(1);
      });

      test('suspend and resume hotkeys can be updated independently', () async {
        final suspendHotkey = HotKey(key: PhysicalKeyboardKey.f6);
        final resumeHotkey = HotKey(key: PhysicalKeyboardKey.f7);

        expect(await cubit.updateHotkey(suspendHotkey, HotkeyAction.suspend), true);
        expect(await cubit.updateHotkey(resumeHotkey, HotkeyAction.resume), true);

        expect(state.suspendHotKey, suspendHotkey);
        expect(state.resumeHotKey, resumeHotkey);
        expect(state.hotKey.physicalKey, PhysicalKeyboardKey.pause);
        verify(
          storage.saveValue(key: 'suspendHotkey', value: anyNamed('value')),
        ).called(1);
        verify(
          storage.saveValue(key: 'resumeHotkey', value: anyNamed('value')),
        ).called(1);
      });

      test('suspend and resume hotkeys reset to unconfigured', () async {
        final suspendHotkey = HotKey(key: PhysicalKeyboardKey.f6);
        final resumeHotkey = HotKey(key: PhysicalKeyboardKey.f7);
        await cubit.updateHotkey(suspendHotkey, HotkeyAction.suspend);
        await cubit.updateHotkey(resumeHotkey, HotkeyAction.resume);

        await cubit.resetHotkey(HotkeyAction.suspend);
        await cubit.resetHotkey(HotkeyAction.resume);

        expect(state.suspendHotKey, isNull);
        expect(state.resumeHotKey, isNull);
        verify(hotkeyService.removeHotkey(suspendHotkey)).called(1);
        verify(hotkeyService.removeHotkey(resumeHotkey)).called(1);
        verify(storage.deleteValue('suspendHotkey')).called(1);
        verify(storage.deleteValue('resumeHotkey')).called(1);
      });

      test('toggle reset rejects a binding used by another action', () async {
        final replacementToggle = HotKey(key: PhysicalKeyboardKey.f9);
        await cubit.updateHotkey(replacementToggle);
        await cubit.updateHotkey(defaultHotkey, HotkeyAction.suspend);
        clearInteractions(hotkeyService);

        final reset = await cubit.resetHotkey();

        expect(reset, false);
        expect(state.hotKey, replacementToggle);
        expect(state.suspendHotKey?.physicalKey, PhysicalKeyboardKey.pause);
        verify(hotkeyService.addHotkey(replacementToggle)).called(1);
        verifyNever(storage.deleteValue('hotkey'));
      });

      test('duplicate global bindings are rejected', () async {
        final suspendHotkey = HotKey(
          key: PhysicalKeyboardKey.f8,
          modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        );
        final duplicateBinding = HotKey(
          key: PhysicalKeyboardKey.f8,
          modifiers: [HotKeyModifier.shift, HotKeyModifier.control],
        );
        await cubit.updateHotkey(suspendHotkey, HotkeyAction.suspend);

        final updated = await cubit.updateHotkey(duplicateBinding, HotkeyAction.resume);

        expect(updated, false);
        expect(state.resumeHotKey, isNull);
        verifyNever(storage.saveValue(key: 'resumeHotkey', value: anyNamed('value')));
      });

      test('bindings used by app-specific hotkeys are rejected', () async {
        final appHotkey = HotKey(key: PhysicalKeyboardKey.f4);
        await cubit.addAppSpecificHotkey('example.exe', appHotkey);

        final updated = await cubit.updateHotkey(
          HotKey(key: PhysicalKeyboardKey.f4),
          HotkeyAction.resume,
        );

        expect(updated, false);
        expect(state.resumeHotKey, isNull);
        verifyNever(storage.saveValue(key: 'resumeHotkey', value: anyNamed('value')));
      });

      test('app-specific bindings used by global actions are rejected', () async {
        final suspendHotkey = HotKey(key: PhysicalKeyboardKey.f3);
        await cubit.updateHotkey(suspendHotkey, HotkeyAction.suspend);
        clearInteractions(storage);

        final added = await cubit.addAppSpecificHotkey(
          'example.exe',
          HotKey(key: PhysicalKeyboardKey.f3),
        );

        expect(added, false);
        expect(state.appSpecificHotKeys, isEmpty);
        verifyNever(
          storage.saveValue(
            key: 'appSpecificHotKeys',
            value: anyNamed('value'),
          ),
        );
      });
    });
  });
}
