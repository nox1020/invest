import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('apk-name-');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<ProcessResult> runScript(List<String> args) {
    return Process.run('bash', ['scripts/name_release_apk.sh', ...args]);
  }

  test('renames app-release.apk to invest-1.0.95.apk and deletes the default name',
      () async {
    await File('${dir.path}/app-release.apk').writeAsBytes(const [0x50, 0x4b]);
    final result = await runScript([dir.path, '1.0.95']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout.toString().trim(), '${dir.path}/invest-1.0.95.apk');
    expect(File('${dir.path}/invest-1.0.95.apk').existsSync(), isTrue);
    expect(File('${dir.path}/app-release.apk').existsSync(), isFalse);
  });

  test('is a no-op when the canonical file is already present', () async {
    await File('${dir.path}/invest-1.0.95.apk').writeAsBytes(const [1, 2, 3]);
    await File('${dir.path}/app-release.apk').writeAsBytes(const [9, 9]);
    final result = await runScript([dir.path, '1.0.95']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(File('${dir.path}/invest-1.0.95.apk').readAsBytesSync(), [1, 2, 3]);
    expect(File('${dir.path}/app-release.apk').existsSync(), isFalse);
  });

  test('rejects a version that is not 1.0.N', () async {
    final result = await runScript([dir.path, 'app-release']);
    expect(result.exitCode, isNot(0));
  });
}
