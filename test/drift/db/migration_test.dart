// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = Db(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // The following template shows how to write tests ensuring your migrations
  // preserve existing data.
  // Testing this can be useful for migrations that change existing columns
  // (e.g. by alterating their type or constraints). Migrations that only add
  // tables or columns typically don't need these advanced tests. For more
  // information, see https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
  // TODO: This generated template shows how these tests could be written. Adopt
  // it to your own needs when testing migrations with data integrity.
  test('migration from v1 to v2 does not corrupt data', () async {
    // Add data to insert into the old database, and the expected rows after the
    // migration.
    // TODO: Fill these lists
    final oldProfileEntriesData = <v1.ProfileEntriesData>[];
    final expectedNewProfileEntriesData = <v2.ProfileEntriesData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: Db.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.profileEntries, oldProfileEntriesData);
      },
      validateItems: (newDb) async {
        expect(
          expectedNewProfileEntriesData,
          await newDb.select(newDb.profileEntries).get(),
        );
      },
    );
  });

  group('_columnExists-backed migrations', () {
    test('migration from v3 to v4 adds test_url when missing', () async {
      final schema = await verifier.schemaAt(3);
      addTearDown(() => schema.rawDatabase.dispose());

      final oldDb = v3.DatabaseAtV3(schema.newConnection());
      final oldColumns = await oldDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();

      expect(
        oldColumns.where((row) => row.data['name'] == 'test_url'),
        isEmpty,
      );
      await oldDb.close();

      final migratedDb = Db(schema.newConnection());
      await verifier.migrateAndValidate(migratedDb, 4);
      await migratedDb.close();

      final newDb = v4.DatabaseAtV4(schema.newConnection());
      final newColumns = await newDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();
      expect(
        newColumns.where((row) => row.data['name'] == 'test_url'),
        hasLength(1),
      );
      await newDb.close();
    });

    test(
      'migration from v3 to v4 skips adding test_url when it already exists',
      () async {
        final schema = await verifier.schemaAt(3);
        addTearDown(() => schema.rawDatabase.dispose());

        schema.rawDatabase.execute(
          'ALTER TABLE profile_entries ADD COLUMN test_url TEXT NULL;',
        );

        final migratedDb = Db(schema.newConnection());
        await verifier.migrateAndValidate(migratedDb, 4);
        await migratedDb.close();

        final newDb = v4.DatabaseAtV4(schema.newConnection());
        final newColumns = await newDb
            .customSelect('PRAGMA table_info(profile_entries);')
            .get();
        expect(
          newColumns.where((row) => row.data['name'] == 'test_url'),
          hasLength(1),
        );
        await newDb.close();
      },
    );

    test('migration from v7 to v9 adds pinned to a fork-written v7', () async {
      // Upstream's 7 and the fork's 7 are different schemas under the same
      // version number, so a database the fork created reports 7 and the 6 to 7
      // step never runs on it. `pinned` is what it ends up missing, and reading
      // it back is a null on a non-nullable field, which surfaces as a black
      // screen rather than as a migration error.
      final schema = await verifier.schemaAt(7);
      addTearDown(() => schema.rawDatabase.dispose());

      // Rebuild the table without `pinned`, which is the fork's v7 verbatim.
      // DROP COLUMN is not on every SQLite the tests run, and rebuilding says
      // exactly which shape is meant.
      schema.rawDatabase.execute(
        'CREATE TABLE profile_entries_fork_v7 ("id" TEXT NOT NULL, "type" TEXT NOT NULL, '
        '"active" INTEGER NOT NULL CHECK ("active" IN (0, 1)), "name" TEXT NOT NULL, "url" TEXT NULL, '
        '"last_update" TEXT NOT NULL, "update_interval" INTEGER NULL, "upload" INTEGER NULL, '
        '"download" INTEGER NULL, "total" INTEGER NULL, "expire" TEXT NULL, '
        '"web_page_url" TEXT NULL, "support_url" TEXT NULL, "populated_headers" TEXT NULL, '
        '"user_override" TEXT NULL, PRIMARY KEY ("id"))',
      );
      schema.rawDatabase.execute(
        'INSERT INTO profile_entries_fork_v7 SELECT "id", "type", "active", "name", "url", '
        '"last_update", "update_interval", "upload", "download", "total", "expire", '
        '"web_page_url", "support_url", "populated_headers", "user_override" FROM profile_entries',
      );
      schema.rawDatabase.execute('DROP TABLE profile_entries');
      schema.rawDatabase.execute('ALTER TABLE profile_entries_fork_v7 RENAME TO profile_entries');

      // Opening a Db on a database whose version is behind runs the migration
      // chain, so the missing column cannot be observed through one first.
      final migratedDb = Db(schema.newConnection());
      await verifier.migrateAndValidate(migratedDb, 9);
      await migratedDb.close();

      // The column has to be readable, not merely present: that read is what
      // threw before.
      final newDb = Db(schema.newConnection());
      expect(await newDb.select(newDb.profileEntries).get(), isA<List<ProfileEntry>>());
      await newDb.close();
    });

    test('migration from v8 to v9 leaves an already-pinned table alone', () async {
      final schema = await verifier.schemaAt(8);
      addTearDown(() => schema.rawDatabase.dispose());

      final migratedDb = Db(schema.newConnection());
      await verifier.migrateAndValidate(migratedDb, 9);
      await migratedDb.close();

      final newDb = Db(schema.newConnection());
      expect(await newDb.select(newDb.profileEntries).get(), isA<List<ProfileEntry>>());
      await newDb.close();
    });
  });
}
