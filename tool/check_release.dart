import 'dart:io';

/// Verifica os metadados antes dos builds; pubspec é a referência de versão.
void main() {
  final yaml = File('pubspec.yaml').readAsStringSync();
  final version = RegExp(
    r'^version: (\d+\.\d+\.\d+)\+(\d+)$',
    multiLine: true,
  ).firstMatch(yaml);
  if (version == null) {
    throw StateError('Use version: x.y.z+build em pubspec.yaml.');
  }
  final expected = '${version[1]}.${version[2]}';
  final msix = RegExp(
    r'^  msix_version: (.+)$',
    multiLine: true,
  ).firstMatch(yaml)?.group(1)?.trim();
  if (msix != expected) throw StateError('msix_version deve ser $expected.');
  final installer = File('installers/sixf_installer.iss').readAsStringSync();
  if (!installer.contains('GetVersionNumbersString') ||
      !installer.contains('v{#MyAppVersion}')) {
    throw StateError(
      'O instalador deve derivar a versão do executável compilado.',
    );
  }
  final logo = RegExp(
    r'^  logo_path: (.+)$',
    multiLine: true,
  ).firstMatch(yaml)!.group(1)!.trim();
  if (!File(logo).existsSync()) throw StateError('Logo MSIX inexistente.');
  stdout.writeln('Metadados consistentes: ${version[0]}; MSIX $expected.');
}
