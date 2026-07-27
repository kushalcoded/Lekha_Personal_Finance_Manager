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
  final String tempPath;
  final String? savedPath;

  const ExportSavedFile({
    required this.fileName,
    required this.mimeType,
    required this.tempPath,
    required this.savedPath,
  });

  bool get hasUserChosenLocation => savedPath != null && savedPath!.isNotEmpty;
}

