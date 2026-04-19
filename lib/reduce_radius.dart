import 'dart:io';

void main() {
  final directory = Directory('lib');
  if (!directory.existsSync()) {
    print('Directory lib does not exist.');
    return;
  }

  final replacements = {
    'BorderRadius.circular(8)': 'BorderRadius.circular(8)',
    'BorderRadius.circular(10)': 'BorderRadius.circular(10)',
    'Radius.circular(12)': 'Radius.circular(12)',
    'Radius.circular(10)': 'Radius.circular(10)',
  };

  directory.listSync(recursive: true).forEach((file) {
    if (file is File && file.path.endsWith('.dart')) {
      String contents = file.readAsStringSync();
      bool modified = false;

      replacements.forEach((pattern, replacement) {
        if (contents.contains(pattern)) {
          contents = contents.replaceAll(pattern, replacement);
          modified = true;
        }
      });

      if (modified) {
        print('Updating: ${file.path}');
        file.writeAsStringSync(contents);
      }
    }
  });
}
