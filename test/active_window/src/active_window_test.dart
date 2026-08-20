import 'package:flutter/foundation.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nyrna/active_window/active_window.dart';
import 'package:nyrna/argument_parser/argument_parser.dart';
import 'package:nyrna/logs/logs.dart';
import 'package:nyrna/native_platform/native_platform.dart';
import 'package:nyrna/storage/storage_repository.dart';
import 'package:nyrna/window/app_window.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
@GenerateNiceMocks(<MockSpec>[
  MockSpec<AppWindow>(),
  MockSpec<ArgumentParser>(),
  MockSpec<NativePlatform>(),
  MockSpec<ProcessRepository>(),
  MockSpec<StorageRepository>(),
])
import 'active_window_test.mocks.dart';

const kActiveWindowStorageArea = 'activeWindow';

const testProcess = Process(
  executable: 'code-insiders',
  pid: 45686,
  status: ProcessStatus.normal,
);

const testWindow = Window(
  id: '130023427',
  process: testProcess,
  title: 'Untitled-2 - Visual Studio Code - Insiders',
);

MockAppWindow appWindow = MockAppWindow();
MockArgumentParser argParser = MockArgumentParser();
MockNativePlatform nativePlatform = MockNativePlatform();
MockProcessRepository processRepository = MockProcessRepository();
MockStorageRepository storageRepository = MockStorageRepository();

late ActiveWindow activeWindow;

void main() {
  setUpAll(() async {
    await LoggingManager.initialize(verbose: false);
  });

  setUp(() {
    reset(appWindow);
    reset(argParser);
    ArgumentParser.instance = argParser;
    reset(nativePlatform);
    reset(processRepository);
    reset(storageRepository);

    // Setup initial dummy responses for mocks.

    // AppWindow
    when(appWindow.hide()).thenAnswer((_) async => true);

    // NativePlatform
    when(nativePlatform.activeWindow).thenReturn(testWindow);
    when(nativePlatform.minimizeWindow(any)).thenAnswer((_) async => true);
    when(nativePlatform.restoreWindow(any)).thenAnswer((_) async => true);

    // ProcessRepository
    when(processRepository.exists(any)).thenAnswer((_) async => true);
    when(
      processRepository.getProcessStatus(any),
    ).thenAnswer((_) async => ProcessStatus.normal);
    when(processRepository.resume(any)).thenAnswer((_) async => true);
    when(processRepository.suspend(any)).thenAnswer((_) async => true);

    // StorageRepository
    when(
      storageRepository.deleteValue(any, storageArea: anyNamed('storageArea')),
    ).thenAnswer((_) async {});
    when(
      storageRepository.getValue(any, storageArea: anyNamed('storageArea')),
    ).thenAnswer((_) async => null);
    when(
      storageRepository.saveValue(
        key: anyNamed('key'),
        value: anyNamed('value'),
        storageArea: anyNamed('storageArea'),
      ),
    ).thenAnswer((_) async {});
    when(storageRepository.close()).thenAnswer((_) async {});

    activeWindow = ActiveWindow(
      appWindow,
      nativePlatform,
      processRepository,
      storageRepository,
    );
  });

  group('ActiveWindow:', () {
    test('suspends normal window', () async {
      final successful = await activeWindow.toggle();
      expect(successful, true);
      verify(processRepository.suspend(testWindow.process.pid)).called(1);
      verify(
        storageRepository.saveValue(
          key: 'pid',
          value: testWindow.process.pid,
          storageArea: kActiveWindowStorageArea,
        ),
      ).called(1);
      verify(
        storageRepository.saveValue(
          key: 'windowId',
          value: testWindow.id,
          storageArea: kActiveWindowStorageArea,
        ),
      ).called(1);
    });

    test('explorer.exe executable aborts on Win32', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      when(nativePlatform.activeWindow).thenReturn(
        testWindow.copyWith(
          process: testProcess.copyWith(executable: 'explorer.exe'),
        ),
      );
      final successful = await activeWindow.toggle();
      expect(successful, false);
      verifyNever(processRepository.suspend(any));
      // Restore global platform variable.
      debugDefaultTargetPlatformOverride = null;
    });

    test('suspend failure returns false', () async {
      when(processRepository.suspend(any)).thenAnswer((_) async => false);
      final successful = await activeWindow.toggle();
      expect(successful, false);
    });

    group('ensureSuspended:', () {
      test(
        'does not suspend an already-suspended tracked process again',
        () async {
          when(
            storageRepository.getValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).thenAnswer((_) async => testProcess.pid);
          when(
            processRepository.getProcessStatus(testProcess.pid),
          ).thenAnswer((_) async => ProcessStatus.suspended);

          final successful = await activeWindow.ensureSuspended();

          expect(successful, true);
          verify(processRepository.exists(testProcess.pid)).called(1);
          verify(processRepository.getProcessStatus(testProcess.pid)).called(1);
          verifyNever(processRepository.suspend(any));
          verifyNever(nativePlatform.checkActiveWindow());
        },
      );

      test(
        're-suspends the tracked process if it was externally resumed',
        () async {
          const trackedPid = 13579;
          when(
            storageRepository.getValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).thenAnswer((_) async => trackedPid);
          when(
            processRepository.getProcessStatus(trackedPid),
          ).thenAnswer((_) async => ProcessStatus.normal);

          final successful = await activeWindow.ensureSuspended();

          expect(successful, true);
          verify(processRepository.suspend(trackedPid)).called(1);
          verifyNever(processRepository.suspend(testProcess.pid));
          verifyNever(nativePlatform.checkActiveWindow());
          verifyNever(
            storageRepository.saveValue(
              key: anyNamed('key'),
              value: anyNamed('value'),
              storageArea: anyNamed('storageArea'),
            ),
          );
        },
      );

      test(
        'clears a dead target and suspends the current foreground process',
        () async {
          const deadPid = 24680;
          when(
            storageRepository.getValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).thenAnswer((_) async => deadPid);
          when(processRepository.exists(deadPid)).thenAnswer((_) async => false);

          final successful = await activeWindow.ensureSuspended();

          expect(successful, true);
          verify(
            storageRepository.deleteValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
          verify(
            storageRepository.deleteValue(
              'windowId',
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
          verifyNever(processRepository.getProcessStatus(deadPid));
          verify(processRepository.suspend(testProcess.pid)).called(1);
        },
      );

      test('does not suspend a target whose status is unknown', () async {
        when(
          storageRepository.getValue(
            'pid',
            storageArea: kActiveWindowStorageArea,
          ),
        ).thenAnswer((_) async => testProcess.pid);
        when(
          processRepository.getProcessStatus(testProcess.pid),
        ).thenAnswer((_) async => ProcessStatus.unknown);

        final successful = await activeWindow.ensureSuspended();

        expect(successful, false);
        verifyNever(processRepository.suspend(any));
      });

      test(
        'tracks an already-suspended foreground process without suspending again',
        () async {
          when(
            processRepository.getProcessStatus(testProcess.pid),
          ).thenAnswer((_) async => ProcessStatus.suspended);

          final successful = await activeWindow.ensureSuspended();

          expect(successful, true);
          verifyNever(processRepository.suspend(any));
          verify(
            storageRepository.saveValue(
              key: 'pid',
              value: testProcess.pid,
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
          verify(
            storageRepository.saveValue(
              key: 'windowId',
              value: testWindow.id,
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
        },
      );
    });

    test(
      'active window being Nyrna calls hide on window and tries again (Linux)',
      () async {
        final nyrnaWindow = testWindow.copyWith(
          process: testProcess.copyWith(executable: 'nyrna'),
        );
        when(nativePlatform.activeWindow).thenAnswerInOrder([nyrnaWindow, testWindow]);
        final successful = await activeWindow.toggle();
        expect(successful, true);
        verify(nativePlatform.checkActiveWindow()).called(2);
        verify(appWindow.hide()).called(1);
      },
    );

    test(
      'active window being Nyrna calls hide on window and tries again (Windows)',
      () async {
        final nyrnaWindow = testWindow.copyWith(
          process: testProcess.copyWith(executable: 'nyrna.exe'),
        );
        when(nativePlatform.activeWindow).thenAnswerInOrder([nyrnaWindow, testWindow]);
        final successful = await activeWindow.toggle();
        expect(successful, true);
        verify(nativePlatform.checkActiveWindow()).called(2);
        verify(appWindow.hide()).called(1);
      },
    );

    group('minimizing & restoring:', () {
      test('no flag or preference defaults to minimizing', () async {
        expect(argParser.minimize, null);
        final successful = await activeWindow.toggle();
        expect(successful, true);
        verify(nativePlatform.minimizeWindow(any)).called(1);
      });

      test('no flag & preference=false does not minimize', () async {
        when(
          storageRepository.getValue('minimizeWindows'),
        ).thenAnswer((_) async => false);
        expect(argParser.minimize, null);
        final successful = await activeWindow.toggle();
        expect(successful, true);
        verifyNever(nativePlatform.minimizeWindow(any));
      });

      test(
        'no-minimize flag received & no preference does not minimize',
        () async {
          when(argParser.minimize).thenReturn(false);
          final successful = await activeWindow.toggle();
          expect(successful, true);
          verifyNever(nativePlatform.minimizeWindow(any));
        },
      );

      test(
        'no-minimize flag received & preference=true does not minimize',
        () async {
          when(
            storageRepository.getValue('minimizeWindows'),
          ).thenAnswer((_) async => true);
          when(argParser.minimize).thenReturn(false);
          final successful = await activeWindow.toggle();
          expect(successful, true);
          verifyNever(nativePlatform.minimizeWindow(any));
        },
      );
    });

    group('resuming:', () {
      late Process suspendedProcess;
      late Window suspendedWindow;

      setUp(() {
        suspendedProcess = testProcess.copyWith(
          status: ProcessStatus.suspended,
        );
        suspendedWindow = testWindow.copyWith(process: suspendedProcess);
        when(
          storageRepository.getValue(
            'pid',
            storageArea: kActiveWindowStorageArea,
          ),
        ).thenAnswer((_) async => suspendedWindow.process.pid);
        when(
          storageRepository.getValue(
            'windowId',
            storageArea: kActiveWindowStorageArea,
          ),
        ).thenAnswer((_) async => suspendedWindow.id);
        when(
          processRepository.getProcessStatus(suspendedProcess.pid),
        ).thenAnswer((_) async => ProcessStatus.suspended);
      });

      test('resumes suspended window', () async {
        when(
          processRepository.resume(suspendedProcess.pid),
        ).thenAnswer((_) async => true);
        final successful = await activeWindow.toggle();
        expect(successful, true);
        verify(processRepository.resume(suspendedProcess.pid)).called(1);
        verify(
          storageRepository.getValue(
            'windowId',
            storageArea: kActiveWindowStorageArea,
          ),
        ).called(1);
        verify(
          storageRepository.deleteValue(
            'pid',
            storageArea: kActiveWindowStorageArea,
          ),
        ).called(1);
        verify(
          storageRepository.deleteValue(
            'windowId',
            storageArea: kActiveWindowStorageArea,
          ),
        ).called(1);
      });

      test('failed resume returns false', () async {
        when(
          processRepository.resume(suspendedProcess.pid),
        ).thenAnswer((_) async => false);
        final successful = await activeWindow.toggle();
        expect(successful, false);
        verify(processRepository.resume(suspendedProcess.pid)).called(1);
        verifyNever(
          storageRepository.getValue(
            'windowId',
            storageArea: kActiveWindowStorageArea,
          ),
        );
        verify(
          storageRepository.deleteValue(
            'pid',
            storageArea: kActiveWindowStorageArea,
          ),
        ).called(1);
        verify(
          storageRepository.deleteValue(
            'windowId',
            storageArea: kActiveWindowStorageArea,
          ),
        ).called(1);
      });
    });

    group('ensureResumed:', () {
      test('is a successful no-op when no process is tracked', () async {
        final successful = await activeWindow.ensureResumed();

        expect(successful, true);
        verifyNever(processRepository.exists(any));
        verifyNever(processRepository.getProcessStatus(any));
        verifyNever(processRepository.resume(any));
        verifyNever(
          storageRepository.deleteValue(
            any,
            storageArea: anyNamed('storageArea'),
          ),
        );
        verifyNever(nativePlatform.restoreWindow(any));
      });

      test(
        'clears and restores an externally-resumed tracked process',
        () async {
          const trackedPid = 97531;
          const trackedWindowId = 'tracked-window';
          when(
            storageRepository.getValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).thenAnswer((_) async => trackedPid);
          when(
            storageRepository.getValue(
              'windowId',
              storageArea: kActiveWindowStorageArea,
            ),
          ).thenAnswer((_) async => trackedWindowId);
          when(
            processRepository.getProcessStatus(trackedPid),
          ).thenAnswer((_) async => ProcessStatus.normal);

          final successful = await activeWindow.ensureResumed();

          expect(successful, true);
          verifyNever(processRepository.resume(any));
          verify(
            storageRepository.deleteValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
          verify(
            storageRepository.deleteValue(
              'windowId',
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
          verify(nativePlatform.restoreWindow(trackedWindowId)).called(1);
        },
      );

      test(
        'clears a dead tracked process without trying to resume it',
        () async {
          const deadPid = 86420;
          when(
            storageRepository.getValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).thenAnswer((_) async => deadPid);
          when(processRepository.exists(deadPid)).thenAnswer((_) async => false);

          final successful = await activeWindow.ensureResumed();

          expect(successful, true);
          verifyNever(processRepository.getProcessStatus(deadPid));
          verifyNever(processRepository.resume(any));
          verify(
            storageRepository.deleteValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
          verify(
            storageRepository.deleteValue(
              'windowId',
              storageArea: kActiveWindowStorageArea,
            ),
          ).called(1);
          verifyNever(nativePlatform.restoreWindow(any));
        },
      );

      test(
        'does not resume or clear a target whose status is unknown',
        () async {
          when(
            storageRepository.getValue(
              'pid',
              storageArea: kActiveWindowStorageArea,
            ),
          ).thenAnswer((_) async => testProcess.pid);
          when(
            processRepository.getProcessStatus(testProcess.pid),
          ).thenAnswer((_) async => ProcessStatus.unknown);

          final successful = await activeWindow.ensureResumed();

          expect(successful, false);
          verifyNever(processRepository.resume(any));
          verifyNever(
            storageRepository.deleteValue(
              any,
              storageArea: anyNamed('storageArea'),
            ),
          );
        },
      );
    });
  });
}
