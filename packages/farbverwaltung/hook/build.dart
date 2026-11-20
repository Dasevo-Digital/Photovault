import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const version = '2.20';
const commit = '7717fce0d85447ef3b2df0cca2e99207c15eeecd';
const archivSha256 =
    '0bb5e2468da857d06218554effb99bb7cef66e85eeda658218283fae99ab99d1';
const quellSha256 =
    '9ffaf1b025b4c571e81969f9e52560f9ba1ed798271d1d5d1ffcd6e341e00e63';

Future<String> _quellHash(Directory quelle) async {
  final zeilen = <String, String>{};
  await for (final f in quelle.list(recursive: true, followLinks: false)) {
    if (f is Link) return '';
    if (f is! File) continue;
    final name = f.uri.path.substring(quelle.uri.path.length);
    if (name == 'geprueft') continue;
    if (zeilen.length >= 4096 || await f.length() > 32 * 1024 * 1024) return '';
    zeilen[name] = (await sha256.bind(f.openRead()).first).toString();
  }
  final namen = zeilen.keys.toList()..sort();
  return sha256
      .convert(
        utf8.encode([for (final n in namen) '$n\u0000${zeilen[n]}\n'].join()),
      )
      .toString();
}

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final gemeinsam = Directory.fromUri(input.outputDirectoryShared);
    await gemeinsam.create(recursive: true);
    final sperre = await File.fromUri(
      gemeinsam.uri.resolve('quelle.lock'),
    ).open(mode: FileMode.append);
    final quelle = Directory.fromUri(gemeinsam.uri.resolve('lcms-$commit/'));
    try {
      await sperre.lock(FileLock.exclusive);
      final marker = File.fromUri(quelle.uri.resolve('geprueft'));
      if (!await marker.exists() ||
          await marker.readAsString() != '$archivSha256:2' ||
          await _quellHash(quelle) != quellSha256) {
        final archiv = File.fromUri(
          gemeinsam.uri.resolve('lcms-$commit.tar.gz'),
        );
        if (!await archiv.exists() ||
            sha256.convert(await archiv.readAsBytes()).toString() !=
                archivSha256) {
          final http = HttpClient()
            ..connectionTimeout = const Duration(seconds: 20)
            ..findProxy = HttpClient.findProxyFromEnvironment;
          try {
            final request = await http.getUrl(
              Uri.parse(
                'https://codeload.github.com/mm2/Little-CMS/tar.gz/$commit',
              ),
            );
            final response = await request.close().timeout(
              const Duration(seconds: 40),
            );
            if (response.statusCode != 200) {
              throw StateError('Farbengine-Quelle nicht verfügbar');
            }
            final daten = BytesBuilder(copy: false);
            await for (final teil in response.timeout(
              const Duration(seconds: 40),
            )) {
              daten.add(teil);
              if (daten.length > 16 * 1024 * 1024) {
                throw StateError('Farbengine-Quelle zu groß');
              }
            }
            final bytes = daten.takeBytes();
            if (sha256.convert(bytes).toString() != archivSha256) {
              throw StateError('Farbengine-Prüfsumme stimmt nicht');
            }
            final temp = File('${archiv.path}.part');
            await temp.writeAsBytes(bytes, flush: true);
            await temp.rename(archiv.path);
          } finally {
            http.close(force: true);
          }
        }
        final entpackt = TarDecoder().decodeBytes(
          const GZipDecoder().decodeBytes(await archiv.readAsBytes()),
        );
        final temp = await gemeinsam.createTemp('quelle-');
        try {
          var gesamt = 0, anzahl = 0;
          for (final datei in entpackt) {
            if (++anzahl > 4096 || datei.isSymbolicLink) {
              throw StateError('Ungültiges Farbengine-Archiv');
            }
            final teile = datei.name.split('/');
            if (teile.any((t) => t == '..' || t.contains(r'\')) ||
                teile.first != 'Little-CMS-$commit') {
              throw StateError('Ungültiger Farbengine-Pfad');
            }
            final rest = teile.skip(1).join('/');
            if (!datei.isFile ||
                !(rest == 'LICENSE' ||
                    (rest.startsWith('src/') || rest.startsWith('include/')) &&
                        (rest.endsWith('.c') || rest.endsWith('.h')))) {
              continue;
            }
            gesamt += datei.size;
            if (gesamt > 32 * 1024 * 1024) {
              throw StateError('Farbengine-Quelle zu groß');
            }
            final f = File.fromUri(temp.uri.resolve(rest));
            await f.parent.create(recursive: true);
            await f.writeAsBytes(datei.content as List<int>);
          }
          await File.fromUri(
            temp.uri.resolve('geprueft'),
          ).writeAsString('$archivSha256:2', flush: true);
          if (await quelle.exists()) await quelle.delete(recursive: true);
          await temp.rename(quelle.path);
        } finally {
          if (await temp.exists()) await temp.delete(recursive: true);
        }
      }
    } finally {
      await sperre.unlock();
      await sperre.close();
    }
    final lizenz = await File.fromUri(
      quelle.uri.resolve('LICENSE'),
    ).readAsString();
    final lizenzC = File.fromUri(input.outputDirectory.resolve('lizenz.c'));
    final lizenzText =
        '''
#ifdef _WIN32
#define PV_EXPORT __declspec(dllexport)
#else
#define PV_EXPORT __attribute__((visibility("default")))
#endif
PV_EXPORT const char *pv_farbe_lizenz(void) { return ${jsonEncode(lizenz)}; }
''';
    if (!await lizenzC.exists() || await lizenzC.readAsString() != lizenzText) {
      await lizenzC.writeAsString(lizenzText);
    }
    final sources = [
      for (final f in await Directory.fromUri(
        quelle.uri.resolve('src/'),
      ).list().toList())
        if (f is File && f.path.endsWith('.c')) f.path,
      File.fromUri(input.packageRoot.resolve('src/farbverwaltung.c')).path,
      lizenzC.path,
    ]..sort();
    await CBuilder.library(
      name: 'pv_farbverwaltung',
      packageName: 'farbverwaltung',
      assetName: 'src/native.dart',
      sources: sources,
      includes: [
        Directory.fromUri(quelle.uri.resolve('include/')).path,
        Directory.fromUri(quelle.uri.resolve('src/')).path,
      ],
      defines: {
        if (input.config.code.targetOS == OS.windows) 'CMS_DLL_BUILD': null,
      },
      flags: [
        if (input.config.code.targetOS != OS.windows) '-fvisibility=hidden',
        if (input.config.code.targetOS == OS.linux) '-Wl,-Bsymbolic-functions',
      ],
      libraries: [
        if (input.config.code.targetOS == OS.linux ||
            input.config.code.targetOS == OS.android)
          'm',
      ],
    ).run(input: input, output: output);
    output.dependencies.add(input.packageRoot.resolve('src/farbverwaltung.c'));
  });
}
