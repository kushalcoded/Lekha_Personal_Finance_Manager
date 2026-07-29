import 'dart:typed_data';

class ExportGeneratedFile {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String? previewText;

  const ExportGeneratedFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.previewText,
  });
}

class ExportSavedFile {
  final String fileName;
  final String mimeType;

  /// Empty on web, where there is no filesystem — [bytes] carries the data.
  final String tempPath;
  final String? savedPath;
  final Uint8List? bytes;

  const ExportSavedFile({
    required this.fileName,
    required this.mimeType,
    required this.tempPath,
    required this.savedPath,
    this.bytes,
  });

  bool get hasUserChosenLocation => savedPath != null && savedPath!.isNotEmpty;
}

