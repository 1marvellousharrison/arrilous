import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// The maximum decoded size the API accepts for a digital product file.
const int kDigitalFileMaxBytes = 6 * 1024 * 1024;

/// One file the owner chose to sell as a digital product.
class PickedDigitalFile {
  const PickedDigitalFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  /// The API travels the bytes as base64 inside the product JSON.
  Map<String, dynamic> toJson() => {
    'file_name': name,
    'mime_type': mimeType,
    'data_base64': base64Encode(bytes),
  };
}

/// Reads an arbitrary file from the device for a digital product.
///
/// Isolated behind an interface so tests can pick a file without a real picker,
/// the same way the logo service does for photos.
abstract class DigitalFileService {
  Future<PickedDigitalFile?> pick();
}

class DeviceDigitalFileService implements DigitalFileService {
  const DeviceDigitalFileService();

  @override
  Future<PickedDigitalFile?> pick() async {
    const typeGroup = XTypeGroup(label: 'Digital products');
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return PickedDigitalFile(
      name: file.name,
      mimeType: file.mimeType ?? mimeTypeForName(file.name),
      bytes: bytes,
    );
  }
}

String mimeTypeForName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'mp4' => 'video/mp4',
    'mp3' => 'audio/mpeg',
    'csv' => 'text/csv',
    'txt' => 'text/plain',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
