import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

class BackupFileService {
  static const int schemaVersion = 1;

  const BackupFileService();

  /// Write a backup snapshot to a shareable `.json` file (in the exact
  /// `{schemaVersion, payload}` shape [readBackupPayload] expects) and return
  /// its path. The caller shares it so the user can keep it off-device.
  Future<String> writeBackupFile(Map<String, dynamic> payload) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/lekha_backup_$stamp.json');
    await file.writeAsString(
      jsonEncode({'schemaVersion': schemaVersion, 'payload': payload}),
    );
    return file.path;
  }

  Future<String?> pickBackupFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Backup',
          extensions: ['json'],
        ),
      ],
    );
    return file?.path;
  }

  Future<Map<String, dynamic>> readBackupPayload(String path) async {
    final content = await File(path).readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('Backup file is not a JSON object');
    }
    final map = Map<String, dynamic>.from(decoded);
    final version = map['schemaVersion'];
    if (version is! int || version != schemaVersion) {
      throw FormatException('Unsupported backup schemaVersion: $version');
    }
    final payload = map['payload'];
    if (payload is! Map) {
      throw const FormatException('Backup file payload is missing');
    }
    return Map<String, dynamic>.from(payload);
  }
}

