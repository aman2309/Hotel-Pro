import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'document_output_stub.dart'
    if (dart.library.js_interop) 'document_output_web.dart'
    as platform;

/// Print / share a generated PDF.
///
/// Mobile and desktop use the `printing` plugin. On the web that plugin prints
/// from a zero-size hidden iframe (Chrome often renders nothing) and "share"
/// only triggers a download, so the web app uses its own browser path.
class DocumentOutput {
  DocumentOutput._();

  static Future<void> printPdf(Uint8List bytes, {required String name}) async {
    if (await platform.printPdf(bytes, name: name)) return;
    await Printing.layoutPdf(
      name: name,
      dynamicLayout: false,
      onLayout: (_) async => bytes,
    );
  }

  static Future<void> sharePdf(
    Uint8List bytes, {
    required String filename,
  }) async {
    if (await platform.sharePdf(bytes, filename: filename)) return;
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
