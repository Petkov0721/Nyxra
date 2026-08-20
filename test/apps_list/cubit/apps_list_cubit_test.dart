import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nyrna/app_version/app_version.dart';
import 'package:nyrna/apps_list/apps_list.dart';
import 'package:nyrna/hotkey/global/hotkey_action.dart';
import 'package:nyrna/hotkey/global/hotkey_service.dart';
import 'package:nyrna/logs/logs.dart';
import 'package:nyrna/native_platform/native_platform.dart';
import 'package:nyrna/settings/settings.dart';
import 'package:nyrna/storage/storage_repository.dart';
import 'package:nyrna/system_tray/system_tray_manager.dart';
import 'package:nyrna/window/app_window.dart';
import 'package:test/test.dart';

@GenerateNiceMocks(<MockSpec>[
  MockSpec<AppWindow>(),
  MockSpec<HotkeyService>(),
  MockSpec<NativePlatform>(),
  MockSpec<SettingsCubit>(),
  MockSpec<ProcessRepository>(),
  MockSpec<StorageRepository>(),
  MockSpec<SystemTrayManager>(),
  MockSpec<AppVersion>(),
])
import 'apps_list_cubit_test.mocks.dart';

late AppsListCubit cubit;
AppsListState get state => cubit.state;

final toggleHotkey = HotKey(key: PhysicalKeyboardKey.again);
final suspendHotkey = HotKey(key: PhysicalKeyboardKey.f11);
final resumeHotkey = HotKey(key: PhysicalKeyboardKey.f12);

const msPaintProcess = Process(
  executable: 'mspaint.exe',
  pid: 3716,
  status: ProcessStatus.normal,
);

const msPaintWindow = Window(
  id: '132334',
  process: msPaintProcess,
  title: 'Untitled - Paint',
);

Window get msPaintWindowState =>
    state //
        .windows
        .singleWhere((element) => element.id == msPaintWindow.id);

const mpvWindow1 = Window(
  id: '180355074',
  process: Process(
    executable: 'mpv',
    pid: 1355281,
    status: ProcessStatus.normal,
  ),
  title: 'No file - mpv',
);

Window get mpvWindow1State =>
    state //
        .windows
        .singleWhere((element) => element.id == mpvWindow1.id);

const mpvWindow2 = Window(
  id: '197132290',
  process: Process(
    executable: 'mpv',
    pid: 1355477,
    status: ProcessStatus.normal,
  ),
  title: 'No file - mpv',
);

Window get mpvWindow2State =>
    state //
        .windows
        .singleWhere((element) => element.id == mpvWindow2.id);

final appWindow = MockAppWindow();
final hotkeyService = MockHotkeyService();
final nativePlatform = MockNativePlatform();
final settingsCubit = MockSettingsCubit();
final processRepository = MockProcessRepository();
final storage = MockStorageRepository();
final systemTrayManager = MockSystemTrayManager();
final appVersion = MockAppVersion();
late StreamController<HotKey> hotkeyController;

class RecordingAppsListCubit extends AppsListCubit {
  RecordingAppsListCubit()
    : super(
        appWindow: appWindow,
        hotkeyService: hotkeyService,
        nativePlatform: nativePlatform,
        settingsCubit: settingsCubit,
        processRepository: processRepository,
        storage: storage,
        systemTrayManager: systemTrayManager,
        appVersion: appVersion,
        testing: true,
      );

  final List<HotkeyAction> actions = [];

  @override
  Future<bool> toggleActiveWindow() async {
    actions.add(HotkeyAction.toggle);
    return true;
  }

  @override
  Future<bool> suspendActiveWindow() async {
    actions.add(HotkeyAction.suspend);
    return true;
  }

  @override
  Future<bool> resumeActiveWindow() async {
    actions.add(HotkeyAction.resume);
    return true;
  }
}

class SerialRecordingAppsListCubit extends RecordingAppsListCubit {
  final suspendGate = Completer<void>();
  final List<String> sequence = [];

  @override
  Future<bool> suspendActiveWindow() async {
    sequence.add('suspend:start');
    await suspendGate.future;
    sequence.add('suspend:end');
    return true;
  }

  @override
  Future<bool> resumeActiveWindow() async {
    sequence.add('resume');
    return true;
  }
}

void main() {
  setUpAll(() async {
    await LoggingManager.initialize(verbose: false);
  });

  setUp(() {
    reset(hotkeyService);
    reset(nativePlatform);
    reset(settingsCubit);
    reset(processRepository);
    reset(storage);
    reset(systemTrayManager);
    reset(appVersion);
    hotkeyController = StreamController<HotKey>.broadcast();

    when(
      hotkeyService.hotkeyTriggeredStream,
    ).thenAnswer((_) => hotkeyController.stream);

    when(appVersion.latest()).thenAnswer((_) async => '1.0.0');
    when(appVersion.running()).thenReturn('1.0.0');
    when(appVersion.updateAvailable()).thenAnswer((_) async => false);

    when(nativePlatform.minimizeWindow(any)).thenAnswer((_) async => true);
    when(nativePlatform.restoreWindow(any)).thenAnswer((_) async => true);
    when(
      nativePlatform.windows(showHidden: anyNamed('showHidden')),
    ).thenAnswer((_) async => []);

    when(storage.getValue('ignoredUpdate')).thenAnswer((_) async {});

    when(settingsCubit.state).thenReturn(
      SettingsState(
        appSpecificHotKeys: [],
        autoStart: false,
        autoRefresh: false,
        closeToTray: false,
        hotKey: toggleHotkey,
        suspendHotKey: suspendHotkey,
        resumeHotKey: resumeHotkey,
        minimizeWindows: true,
        pinSuspendedWindows: false,
        refreshInterval: 5,
        showHiddenWindows: false,
        startHiddenInTray: false,
        working: false,
      ),
    );

    when(
      processRepository.getProcessStatus(any),
    ).thenAnswer((_) async => ProcessStatus.normal);
    when(processRepository.resume(any)).thenAnswer((_) async => true);
    when(processRepository.suspend(any)).thenAnswer((_) async => true);

    // StorageRepository
    when(storage.getValue('minimizeWindows')).thenAnswer((_) async => true);

    cubit = AppsListCubit(
      appWindow: appWindow,
      hotkeyService: hotkeyService,
      nativePlatform: nativePlatform,
      settingsCubit: settingsCubit,
      processRepository: processRepository,
      storage: storage,
      appVersion: appVersion,
      systemTrayManager: systemTrayManager,
      testing: true,
    );
  });

  tearDown(() async {
    await cubit.close();
    await hotkeyController.close();
  });

  group('AppCubit:', () {
    test('initial state has no windows', () {
      expect(state.windows.length, 0);
    });

    group('global hotkey actions:', () {
      test('routes toggle, suspend, and resume bindings separately', () async {
        await cubit.close();
        final recordingCubit = RecordingAppsListCubit();
        cubit = recordingCubit;
        await pumpEventQueue();

        await recordingCubit.handleHotkey(toggleHotkey);
        await recordingCubit.handleHotkey(suspendHotkey);
        await recordingCubit.handleHotkey(resumeHotkey);

        expect(
          recordingCubit.actions,
          [HotkeyAction.toggle, HotkeyAction.suspend, HotkeyAction.resume],
        );
      });

      test('serializes rapid opposing hotkey commands', () async {
        await cubit.close();
        final recordingCubit = SerialRecordingAppsListCubit();
        cubit = recordingCubit;
        await pumpEventQueue();

        hotkeyController
          ..add(suspendHotkey)
          ..add(resumeHotkey);
        await pumpEventQueue(times: 5);

        expect(recordingCubit.sequence, ['suspend:start']);

        recordingCubit.suspendGate.complete();
        await pumpEventQueue();

        expect(recordingCubit.sequence, ['suspend:start', 'suspend:end', 'resume']);
      });
    });

    test('new window is added to state', () async {
      expect(state.windows.length, 0);

      when(
        nativePlatform.windows(showHidden: anyNamed('showHidden')),
      ).thenAnswer((_) async => [msPaintWindow]);

      await cubit.manualRefresh();
      expect(state.windows.length, 1);
    });

    test('process changed externally updates state', () async {
      when(
        nativePlatform.windows(showHidden: anyNamed('showHidden')),
      ).thenAnswer((_) async => [msPaintWindow]);

      await cubit.manualRefresh();

      // Verify we have one window, and it has a normal status.
      var windows = state.windows;
      expect(windows.length, 1);
      expect(windows[0].process.status, ProcessStatus.normal);

      // Simulate the process being suspended outside Nyrna.
      reset(processRepository);
      when(
        processRepository.getProcessStatus(any),
      ).thenAnswer((_) async => ProcessStatus.suspended);

      // Verify we pick up this status change.
      await cubit.manualRefresh();
      windows = state.windows;
      expect(windows.length, 1);
      expect(windows[0].process.status, ProcessStatus.suspended);
    });

    test('app version information populates to cubit', () async {
      // Verify initial state is unpopulated.
      expect(state.runningVersion, '');
      expect(state.updateVersion, '');
      expect(state.updateAvailable, false);

      // Stubbed data propogates.
      await cubit.fetchVersionData();
      expect(state.runningVersion, '1.0.0');
      expect(state.updateVersion, '1.0.0');
      expect(state.updateAvailable, false);

      // Simulate an update being available.
      when(appVersion.latest()).thenAnswer((_) async => '1.0.1');
      when(appVersion.updateAvailable()).thenAnswer((_) async => true);
      await cubit.fetchVersionData();
      expect(state.runningVersion, '1.0.0');
      expect(state.updateVersion, '1.0.1');
      expect(state.updateAvailable, true);
    });

    test('windows are sorted', () async {
      when(nativePlatform.windows(showHidden: anyNamed('showHidden'))).thenAnswer(
        (_) async => [
          Window(
            id: '7363',
            process: Process(
              executable: 'kate',
              pid: 836482,
              status: ProcessStatus.normal,
            ),
            title: 'Kate',
          ),
          Window(
            id: '29347',
            process: Process(
              executable: 'evince',
              pid: 94847,
              status: ProcessStatus.normal,
            ),
            title: 'Evince',
          ),
          Window(
            id: '89374',
            process: Process(
              executable: 'ark',
              pid: 9374623,
              status: ProcessStatus.normal,
            ),
            title: 'Ark',
          ),
        ],
      );

      await cubit.manualRefresh();
      final windows = state.windows;
      expect(windows[0].process.executable, 'ark');
      expect(windows[1].process.executable, 'evince');
      expect(windows[2].process.executable, 'kate');
    });

    group('toggle:', () {
      test('suspends correctly', () async {
        expect(state.windows.isEmpty, true);
        when(
          nativePlatform.windows(
            showHidden: anyNamed('showHidden'),
          ),
        ).thenAnswer((_) async => [msPaintWindow]);
        await cubit.manualRefresh();
        expect(state.windows.length, 1);
        expect(state.windows.first.process.status, ProcessStatus.normal);

        when(
          processRepository.getProcessStatus(msPaintProcess.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        await cubit.toggle(msPaintWindow);
        expect(state.windows.length, 1);
        expect(state.windows.first.process.status, ProcessStatus.suspended);
      });

      test('resumes correctly', () async {
        expect(state.windows.isEmpty, true);
        when(
          nativePlatform.windows(
            showHidden: anyNamed('showHidden'),
          ),
        ).thenAnswer((_) async => [msPaintWindow]);
        when(
          processRepository.getProcessStatus(msPaintProcess.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        await cubit.manualRefresh();
        expect(state.windows.length, 1);
        expect(state.windows.first.process.status, ProcessStatus.suspended);

        when(
          processRepository.getProcessStatus(msPaintProcess.pid),
        ).thenAnswer((_) async => ProcessStatus.normal);
        await cubit.toggle(msPaintWindow);
        expect(state.windows.length, 1);
        expect(state.windows.first.process.status, ProcessStatus.normal);
      });

      test('adds InteractionError to window on failure', () async {
        expect(state.windows.isEmpty, true);
        when(
          nativePlatform.windows(
            showHidden: anyNamed('showHidden'),
          ),
        ).thenAnswer((_) async => [msPaintWindow]);
        when(
          processRepository.getProcessStatus(msPaintProcess.pid),
        ).thenAnswer((_) async => ProcessStatus.normal);
        await cubit.manualRefresh();
        expect(state.windows.length, 1);
        expect(state.windows.first.process.status, ProcessStatus.normal);

        when(processRepository.suspend(any)).thenAnswer((_) async => false);
        when(
          processRepository.getProcessStatus(msPaintProcess.pid),
        ).thenAnswer((_) async => ProcessStatus.normal);
        await cubit.toggle(msPaintWindow);
        expect(state.windows.length, 1);
        expect(state.windows.first.process.status, ProcessStatus.normal);
        final interactionError =
            state //
                .interactionErrors
                .singleWhereOrNull((e) => e.windowId == msPaintWindow.id);
        expect(interactionError, isNotNull);
        expect(interactionError!.interactionType, InteractionType.suspend);
        expect(interactionError.statusAfterInteraction, ProcessStatus.normal);
      });
    });

    group('toggleAll', () {
      test('suspends multiple instances correctly', () async {
        // Initial setup.
        expect(state.windows.isEmpty, true);
        when(
          nativePlatform.windows(
            showHidden: anyNamed('showHidden'),
          ),
        ).thenAnswer(
          (_) async => [
            msPaintWindow,
            mpvWindow1,
            mpvWindow2,
          ],
        );
        await cubit.manualRefresh();
        expect(state.windows.length, 3);
        expect(msPaintWindowState.process.status, ProcessStatus.normal);
        expect(mpvWindow1State.process.status, ProcessStatus.normal);
        expect(mpvWindow2State.process.status, ProcessStatus.normal);

        // Trigger toggleAll() to suspend mpv instances and verify.
        await cubit.toggleAll(mpvWindow1);
        when(
          processRepository.getProcessStatus(mpvWindow1.process.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        when(
          processRepository.getProcessStatus(mpvWindow2.process.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        await cubit.manualRefresh();
        expect(state.windows.length, 3);
        expect(msPaintWindowState.process.status, ProcessStatus.normal);
        expect(mpvWindow1State.process.status, ProcessStatus.suspended);
        expect(mpvWindow2State.process.status, ProcessStatus.suspended);
      });

      test('resumes multiple instances correctly', () async {
        // Initial setup.
        expect(state.windows.isEmpty, true);
        when(
          processRepository.getProcessStatus(mpvWindow1.process.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        when(
          processRepository.getProcessStatus(mpvWindow2.process.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        when(
          nativePlatform.windows(
            showHidden: anyNamed('showHidden'),
          ),
        ).thenAnswer(
          (_) async => [
            msPaintWindow,
            mpvWindow1.copyWith(
              process: mpvWindow1.process.copyWith(
                status: ProcessStatus.suspended,
              ),
            ),
            mpvWindow2.copyWith(
              process: mpvWindow2.process.copyWith(
                status: ProcessStatus.suspended,
              ),
            ),
          ],
        );
        await cubit.manualRefresh();
        expect(state.windows.length, 3);
        expect(msPaintWindowState.process.status, ProcessStatus.normal);
        expect(mpvWindow1State.process.status, ProcessStatus.suspended);
        expect(mpvWindow2State.process.status, ProcessStatus.suspended);

        // Trigger toggleAll() to resume mpv instances and verify.
        await cubit.toggleAll(mpvWindow1);
        when(
          processRepository.getProcessStatus(mpvWindow1.process.pid),
        ).thenAnswer((_) async => ProcessStatus.normal);
        when(
          processRepository.getProcessStatus(mpvWindow2.process.pid),
        ).thenAnswer((_) async => ProcessStatus.normal);
        await cubit.manualRefresh();
        expect(state.windows.length, 3);
        expect(msPaintWindowState.process.status, ProcessStatus.normal);
        expect(mpvWindow1State.process.status, ProcessStatus.normal);
        expect(mpvWindow2State.process.status, ProcessStatus.normal);
      });

      test('only suspends if some are already suspended', () async {
        // Initial setup.
        expect(state.windows.isEmpty, true);
        when(
          processRepository.getProcessStatus(mpvWindow2.process.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        when(
          nativePlatform.windows(
            showHidden: anyNamed('showHidden'),
          ),
        ).thenAnswer(
          (_) async => [
            msPaintWindow,
            mpvWindow1,
            mpvWindow2.copyWith(
              process: mpvWindow2.process.copyWith(
                status: ProcessStatus.suspended,
              ),
            ),
          ],
        );
        await cubit.manualRefresh();
        expect(state.windows.length, 3);
        expect(msPaintWindowState.process.status, ProcessStatus.normal);
        expect(mpvWindow1State.process.status, ProcessStatus.normal);
        expect(mpvWindow2State.process.status, ProcessStatus.suspended);

        // Trigger toggleAll() to suspend mpv instances and verify,
        // the already suspended instance should not have resumed.
        await cubit.toggleAll(mpvWindow1);
        when(
          processRepository.getProcessStatus(mpvWindow1.process.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        when(
          processRepository.getProcessStatus(mpvWindow2.process.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
        await cubit.manualRefresh();
        expect(state.windows.length, 3);
        expect(msPaintWindowState.process.status, ProcessStatus.normal);
        expect(mpvWindow1State.process.status, ProcessStatus.suspended);
        expect(mpvWindow2State.process.status, ProcessStatus.suspended);
      });
    });

    group('showHiddenWindows:', () {
      test('fetchWindows passes showHidden: false by default', () async {
        await cubit.manualRefresh();
        verify(
          nativePlatform.windows(showHidden: false),
        ).called(greaterThanOrEqualTo(1));
      });

      test('fetchWindows passes showHidden: true when setting is enabled', () async {
        when(settingsCubit.state).thenReturn(
          SettingsState(
            appSpecificHotKeys: [],
            autoStart: false,
            autoRefresh: false,
            closeToTray: false,
            hotKey: HotKey(key: PhysicalKeyboardKey.again),
            suspendHotKey: suspendHotkey,
            resumeHotKey: resumeHotkey,
            minimizeWindows: true,
            pinSuspendedWindows: false,
            refreshInterval: 5,
            showHiddenWindows: true,
            startHiddenInTray: false,
            working: false,
          ),
        );
        await cubit.manualRefresh();
        verify(
          nativePlatform.windows(showHidden: true),
        ).called(greaterThanOrEqualTo(1));
      });
    });

    group('favorites:', () {
      test('setFavorite(true) persists executable to storage', () async {
        when(
          nativePlatform.windows(showHidden: anyNamed('showHidden')),
        ).thenAnswer((_) async => [msPaintWindow]);
        when(storage.getValue('favorites')).thenAnswer((_) async => <String>[]);
        await cubit.manualRefresh();
        await cubit.setFavorite(msPaintWindow, true);
        final captured = verify(
          storage.saveValue(
            key: 'favorites',
            value: captureAnyNamed('value'),
          ),
        ).captured;
        expect(captured.single, contains(msPaintProcess.executable));
      });

      test('setFavorite(false) removes executable from storage', () async {
        when(
          nativePlatform.windows(showHidden: anyNamed('showHidden')),
        ).thenAnswer((_) async => [msPaintWindow]);
        when(storage.getValue('favorites')).thenAnswer(
          (_) async => <String>[msPaintProcess.executable],
        );
        await cubit.manualRefresh();
        await cubit.setFavorite(msPaintWindow, false);
        final captured = verify(
          storage.saveValue(
            key: 'favorites',
            value: captureAnyNamed('value'),
          ),
        ).captured;
        expect(captured.single, isNot(contains(msPaintProcess.executable)));
      });

      test('windows marked as favorite after refresh when stored', () async {
        when(
          nativePlatform.windows(showHidden: anyNamed('showHidden')),
        ).thenAnswer((_) async => [msPaintWindow]);
        when(storage.getValue('favorites')).thenAnswer(
          (_) async => <String>[msPaintProcess.executable],
        );
        await cubit.manualRefresh();
        expect(state.windows.first.process.isFavorite, true);
      });
    });

    group('refreshWindows:', () {
      test('manualRefresh fetches updated window list from NativePlatform', () async {
        when(
          nativePlatform.windows(showHidden: anyNamed('showHidden')),
        ).thenAnswer((_) async => [msPaintWindow]);
        await cubit.manualRefresh();
        expect(state.windows.length, 1);

        when(
          nativePlatform.windows(showHidden: anyNamed('showHidden')),
        ).thenAnswer((_) async => []);
        await cubit.manualRefresh();
        expect(state.windows.length, 0);
      });
    });
  });
}
