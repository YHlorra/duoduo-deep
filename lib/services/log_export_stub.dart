import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Non-web platform export: save to application documents directory.
Future<String?> exportPlatformFile(String content, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content);
  return file.path;
}
