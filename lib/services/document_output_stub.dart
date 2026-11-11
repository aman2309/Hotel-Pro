import 'dart:typed_data';

/// Native platforms: let the `printing` plugin handle it.
Future<bool> printPdf(Uint8List bytes, {required String name}) async => false;

Future<bool> sharePdf(Uint8List bytes, {required String filename}) async =>
    false;
