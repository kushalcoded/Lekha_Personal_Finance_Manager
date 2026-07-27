class CsvEncoder {
  final String delimiter;
  final String lineTerminator;

  const CsvEncoder({this.delimiter = ',', this.lineTerminator = '\r\n'});

  String encodeRow(List<Object?> values) {
    return values.map(_encodeField).join(delimiter);
  }

  String _encodeField(Object? value) {
    final text = value?.toString() ?? '';
    final needsQuote =
        text.contains(delimiter) ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    if (!needsQuote) return text;
    final escaped = text.replaceAll('"', '""');
    return '"$escaped"';
  }
}

