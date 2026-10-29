part of 'gastpruefung.dart';

/// Eine leere Dateisystemsicht mit ausdrücklich freigegebenen Laufzeitdateien.
class Abschottung {
  const Abschottung(this.vorsatz, {required this.ohneNetz});
  final List<String> vorsatz;
  final bool ohneNetz;

  static const _macBasis =
      '(version 1)(deny default)'
      '(allow process*)(allow sysctl-read)'
      '(deny sysctl-read (sysctl-name-regex #"^kern[.]proc"))'
      '(allow file-read-metadata)'
      '(allow file-read* (literal "/") (subpath "/System/Library") (subpath "/usr/lib")'
      ' (subpath "/usr/bin") (subpath "/bin") (subpath "/usr/local")'
      ' (subpath "/opt/homebrew") (subpath "/Library/Apple/System/Library")'
      ' (literal "/dev/urandom") (literal "/dev/random"))'
      '(allow file-write* (literal "/dev/null"))';

  static Future<Abschottung> erkenne() async {
    final befehl = Platform.isMacOS
        ? ['/usr/bin/sandbox-exec', '-p', _macBasis, '/usr/bin/true']
        : Platform.isLinux
        ? [
            'bwrap',
            '--unshare-all',
            '--unshare-user',
            '--die-with-parent',
            '--new-session',
            '--ro-bind',
            '/usr',
            '/usr',
            '--symlink',
            'usr/bin',
            '/bin',
            '--symlink',
            'usr/lib',
            '/lib',
            '--symlink',
            'usr/lib64',
            '/lib64',
            '--proc',
            '/proc',
            '--dev',
            '/dev',
            '--tmpfs',
            '/tmp',
            '/bin/true',
          ]
        : <String>[];
    if (befehl.isEmpty) return const Abschottung([], ohneNetz: false);
    try {
      final r = await Process.run(befehl.first, befehl.sublist(1));
      if (r.exitCode == 0) {
        return Abschottung(
          Platform.isMacOS
              ? befehl.take(3).toList()
              : befehl.take(befehl.length - 1).toList(),
          ohneNetz: true,
        );
      }
    } catch (_) {
      /* Verfügbarkeit ist Voraussetzung, kein stiller Rückfall. */
    }
    return const Abschottung([], ohneNetz: false);
  }

  Future<List<String>> fuer(
    File ein,
    Directory aus,
    List<String> command,
    List<String> verboten,
  ) async {
    if (!ohneNetz) throw StateError('pv_gast_abschottung');
    if (Platform.isMacOS) {
      String z(String p) => jsonEncode(p);
      final erlaubte = [
        ein.path,
        ...command.where((p) => File(p).existsSync()),
      ];
      final lib = Directory(
        p.normalize(p.join(p.dirname(command.first), '..', 'lib')),
      );
      final laufzeit = await lib.exists()
          ? '(allow file-read* (subpath ${z(lib.path)}))'
          : '';
      final profil =
          '$_macBasis$laufzeit'
          '(allow file-read* ${erlaubte.map((p) => '(literal ${z(p)})').join(' ')})'
          '(allow file-read* file-write* (subpath ${z(aus.path)}))'
          '${verboten.map((p) => '(deny file-read* file-write* (subpath ${z(p)}))').join()}';
      return ['/usr/bin/sandbox-exec', '-p', profil];
    }
    final args = <String>[
      ...vorsatz,
      '--ro-bind',
      ein.path,
      ein.path,
      '--bind',
      aus.path,
      aus.path,
    ];
    for (final f in command.where((f) => File(f).existsSync())) {
      if (!f.startsWith('/usr/') && !f.startsWith('/bin/')) {
        args.addAll(['--ro-bind', f, f]);
      }
    }
    final lib = Directory(
      p.normalize(p.join(p.dirname(command.first), '..', 'lib')),
    );
    if (await lib.exists()) {
      args.addAll(['--ro-bind', lib.absolute.path, lib.absolute.path]);
    }
    for (final f in verboten) {
      if (f == '/usr' || f == '/bin') throw StateError('pv_gast_laufzeit');
      args.addAll(['--tmpfs', f]);
    }
    return args;
  }
}

Future<String> _programmPfad(String name) async {
  if (p.isAbsolute(name)) {
    return File(name).existsSync() ? File(name).resolveSymbolicLinks() : name;
  }
  for (final dir in [
    '/usr/bin',
    '/bin',
    '/opt/homebrew/bin',
    '/usr/local/bin',
  ]) {
    final f = File(p.join(dir, name));
    if (await f.exists()) return f.resolveSymbolicLinks();
  }
  return name;
}

/// Nur im separaten Programm vor dem ersten Decoderaufruf ausführen.
void gastProzessEinrichten() {
  if (!Platform.isMacOS && !Platform.isLinux) {
    throw UnsupportedError('pv_gast_plattform');
  }
  final libc = DynamicLibrary.process();
  final setsid = libc.lookupFunction<Int32 Function(), int Function()>(
    'setsid',
  );
  final getpgrp = libc.lookupFunction<Int32 Function(), int Function()>(
    'getpgrp',
  );
  if (setsid() < 0 && getpgrp() != pid) {
    throw StateError('pv_gast_prozessgruppe');
  }
  final setrlimit = libc
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint64>),
        int Function(int, Pointer<Uint64>)
      >('setrlimit');
  final getrlimit = libc
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint64>),
        int Function(int, Pointer<Uint64>)
      >('getrlimit');
  final limit = calloc<Uint64>(2);
  try {
    for (final (nr, wert) in [
      (1, 2 * 1024 * 1024 * 1024),
      if (Platform.isLinux) (9, 8 * 1024 * 1024 * 1024),
      (4, 0),
    ]) {
      if (getrlimit(nr, limit) != 0) throw StateError('pv_gast_ressourcen');
      final grenze = limit[1] < wert ? limit[1] : wert;
      limit[0] = grenze;
      limit[1] = grenze;
      if (setrlimit(nr, limit) != 0) throw StateError('pv_gast_ressourcen_$nr');
    }
  } finally {
    calloc.free(limit);
  }
}

void _toeteGruppe(int pid) {
  final libc = DynamicLibrary.process();
  libc.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
    'kill',
  )(-pid, 9);
}

Future<Map<int, int>> _prozessbaum(int pid) async {
  final r = await Process.run('/bin/ps', ['-axo', 'pid=,ppid=,rss=']);
  if (r.exitCode != 0) throw StateError('pv_gast_aufsicht');
  final daten = <int, (int, int)>{};
  for (final line in '${r.stdout}'.split('\n')) {
    final z = line.trim().split(RegExp(r'\s+'));
    if (z.length == 3) {
      daten[int.parse(z[0])] = (int.parse(z[1]), int.parse(z[2]) * 1024);
    }
  }
  final ids = <int>{pid};
  var mehr = true;
  while (mehr) {
    mehr = false;
    for (final e in daten.entries) {
      if (ids.contains(e.value.$1) && ids.add(e.key)) mehr = true;
    }
  }
  return {for (final id in ids) id: daten[id]?.$2 ?? 0};
}

Future<void> _beendeBaum(Process kind) async {
  Map<int, int> ids = {};
  try {
    ids = await _prozessbaum(kind.pid);
  } catch (_) {
    /* Gruppe und Elternprozess trotzdem beenden. */
  }
  _toeteGruppe(kind.pid);
  for (final id in ids.keys.toList().reversed) {
    Process.killPid(id, ProcessSignal.sigkill);
  }
  kind.kill(ProcessSignal.sigkill);
}
