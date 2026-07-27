import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'export_models.dart';

class ExportFileService {
  const ExportFileService();

  Future<ExportSavedFile> persistGeneratedFile(ExportGeneratedFile generated) async {
    final tempPath = await _writeTempFile(
      fileName: generated.fileName,
      bytes: generated.bytes,
    );

    String? savedPath;
    try {
      final location = await getSaveLocation(suggestedName: generated.fileName);
      if (location != null) {
        await XFile(
          tempPath,
          mimeType: generated.mimeType,
          name: generated.fileName,
        ).saveTo(location.path);
        savedPath = location.path;
      }
    } catch (_) {
      // If native save fails on a platform/permission edge case,
      // we still keep a temp file for sharing.
    }

    return ExportSavedFile(
      fileName: generated.fileName,
      mimeType: generated.mimeType,
      tempPath: tempPath,
      savedPath: savedPath,
    );
  }

  Future<String> _writeTempFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

