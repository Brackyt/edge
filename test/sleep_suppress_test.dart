import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('calendarDays sleep suppress', () {
    test('overlapping auto window is dropped', () {
      final dayStart =
          DateTime(2026, 3, 10).millisecondsSinceEpoch ~/ 1000;
      final onset = dayStart + 3600;
      final wake = dayStart + 7200;
      final sub = Substrate(
        tsSec: [for (var i = 0; i < 7200; i++) dayStart + i],
        hr: [for (var i = 0; i < 7200; i++) 62],
        rrTsMs: const [],
        rrMs: const [],
        ax: [for (var i = 0; i < 7200; i++) 0.0],
        ay: [for (var i = 0; i < 7200; i++) 0.0],
        az: [for (var i = 0; i < 7200; i++) 1.0],
        spo2Red: const [],
        spo2Ir: const [],
        skinTemp: const [],
        skinContact: const [],
      );

      final days = calendarDays(
        sub,
        suppressRanges: [
          SleepSuppressRange(startSec: onset, endSec: wake),
        ],
      );

      expect(days, hasLength(1));
      final day = days.single;
      expect(day.hasSleep, isFalse);
      expect(day.sleepSource, 'none');
      expect(day.flags, contains('NO_SLEEP_DETECTED'));
    });

    test('non-overlapping suppress leaves manual override', () {
      final dayStart =
          DateTime(2026, 3, 10).millisecondsSinceEpoch ~/ 1000;
      final onset = dayStart - 3600;
      final wake = dayStart + 3600;
      final sub = Substrate(
        tsSec: [for (var i = 0; i < 7200; i++) dayStart + i],
        hr: [for (var i = 0; i < 7200; i++) 62],
        rrTsMs: const [],
        rrMs: const [],
        ax: [for (var i = 0; i < 7200; i++) 0.0],
        ay: [for (var i = 0; i < 7200; i++) 0.0],
        az: [for (var i = 0; i < 7200; i++) 1.0],
        spo2Red: const [],
        spo2Ir: const [],
        skinTemp: const [],
        skinContact: const [],
      );

      final days = calendarDays(
        sub,
        override: SleepWindowOverride(
          dayId: '2026-03-10',
          onsetSec: onset,
          offsetSec: wake,
          source: 'manual',
        ),
        suppressRanges: [
          // Daytime block only — does not overlap the forced night window.
          SleepSuppressRange(
            startSec: dayStart + 5000,
            endSec: dayStart + 6000,
          ),
        ],
      );

      expect(days.single.hasSleep, isTrue);
      expect(days.single.sleepSource, 'manual');
    });
  });

  group('DerivationEngine nap / period suppress filter', () {
    test('sleepOverlapsSuppress helper', () {
      expect(
        sleepOverlapsSuppress(100, 200, [
          const SleepSuppressRange(startSec: 150, endSec: 160),
        ]),
        isTrue,
      );
      expect(
        sleepOverlapsSuppress(100, 200, [
          const SleepSuppressRange(startSec: 200, endSec: 300),
        ]),
        isFalse,
      );
    });

    // Engine-level invariant (not unit-tested here — needs DerivationEngine +
    // LocalDb finalized/candidate fixtures): `_sleepCandidateForDay` must skip
    // the finalized `sleepSessionCandidate` cache whenever
    // `LocalDb.sleepSuppressRanges(dayId)` is non-empty (same as override), and
    // must not `putSleepSessionCandidate` for a suppress rebuild. Otherwise a
    // dismiss on a finalized day serves the pre-suppress cache, and Undo would
    // re-serve a suppressed cache after clear. See derivation_engine.dart
    // `_sleepCandidateForDay`. Overlap behavior itself is covered by
    // calendarDays above + sleepOverlapsSuppress.
  });

  group('LocalDb sleep_suppress CRUD', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_sleep_suppress_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    tearDownAll(() async {
      await LocalDb.close();
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    test('putSleepSuppress round-trip and clear', () async {
      await LocalDb.putSleepSuppress(
        dayId: '2026-03-10',
        startTs: 100,
        endTs: 200,
      );
      await LocalDb.putSleepSuppress(
        dayId: '2026-03-10',
        startTs: 500,
        endTs: 600,
      );
      final rows = await LocalDb.sleepSuppressRanges('2026-03-10');
      expect(rows, hasLength(2));
      expect(rows.first['start_ts'], 100);
      expect(await LocalDb.sleepSuppressDays(), contains('2026-03-10'));

      await LocalDb.clearSleepSuppress('2026-03-10');
      expect(await LocalDb.sleepSuppressRanges('2026-03-10'), isEmpty);
      expect(await LocalDb.sleepSuppressDays(), isEmpty);
    });
  });
}
