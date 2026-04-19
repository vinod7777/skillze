import 'dart:io';

void main() {
  final d = Directory('lib');
  for (var f in d.listSync(recursive: true)) {
    if (f is File && f.path.endsWith('.dart')) {
      final s = f.readAsStringSync();
      var s2 = s.replaceAllMapped(RegExp(r'\.withOpacity\((.*?)\)'), (m) => '.withValues(alpha: ${m[1]})');
      if (s != s2) {
        f.writeAsStringSync(s2);
        print('Updated: ${f.path}');
      }
    }
  }
}
