import 'dart:html' as html;

/// Web platform export: trigger browser download.
Future<String?> exportPlatformFile(String content, String filename) async {
  final blob = html.Blob([content], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return filename;
}
