import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

const String _frameId = 'hotel-pro-print-frame';

bool get _isMobileBrowser {
  final String ua = web.window.navigator.userAgent;
  return ua.contains('Mobile') ||
      ua.contains('Android') ||
      ua.contains('iPhone') ||
      ua.contains('iPad');
}

web.Blob _pdfBlob(Uint8List bytes) => web.Blob(
  <JSAny>[bytes.toJS].toJS,
  web.BlobPropertyBag(type: 'application/pdf'),
);

String _pdfName(String name) =>
    name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';

/// Desktop browsers print the PDF from an off-screen (not zero-size) iframe so
/// the built-in PDF viewer actually renders it. Phone browsers cannot print a
/// PDF inside a page, so they get the share sheet (which has Print) or a
/// download that opens in the phone's PDF viewer.
Future<bool> printPdf(Uint8List bytes, {required String name}) async {
  final String filename = _pdfName(name);
  if (_isMobileBrowser) {
    if (await _shareFile(bytes, filename)) return true;
    _download(bytes, filename);
    return true;
  }
  try {
    await _printInFrame(bytes);
  } catch (error) {
    debugPrint('[DocumentOutput] iframe print failed: $error');
    _download(bytes, filename);
  }
  return true;
}

/// Uses the system share sheet (WhatsApp, mail, print…) where the browser
/// supports sharing files; otherwise downloads the PDF.
Future<bool> sharePdf(Uint8List bytes, {required String filename}) async {
  final String name = _pdfName(filename);
  if (await _shareFile(bytes, name)) return true;
  _download(bytes, name);
  return true;
}

Future<bool> _shareFile(Uint8List bytes, String filename) async {
  try {
    final web.File file = web.File(
      <JSAny>[bytes.toJS].toJS,
      filename,
      web.FilePropertyBag(type: 'application/pdf'),
    );
    final web.ShareData data = web.ShareData(
      files: <web.File>[file].toJS,
      title: filename,
    );
    final web.Navigator navigator = web.window.navigator;
    // Throws where the Web Share API is missing; treated as unsupported.
    if (!navigator.canShare(data)) return false;
    await navigator.share(data).toDart;
    return true;
  } catch (error) {
    // AbortError = the user closed the sheet; that is not a failure.
    if (error.toString().contains('AbortError')) return true;
    debugPrint('[DocumentOutput] share failed: $error');
    return false;
  }
}

void _download(Uint8List bytes, String filename) {
  final String url = web.URL.createObjectURL(_pdfBlob(bytes));
  final web.HTMLAnchorElement link = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(link);
  link.click();
  link.remove();
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}

Future<void> _printInFrame(Uint8List bytes) async {
  web.document.getElementById(_frameId)?.remove();
  final String url = web.URL.createObjectURL(_pdfBlob(bytes));
  final web.HTMLIFrameElement frame = web.HTMLIFrameElement()
    ..id = _frameId
    ..src = url;
  // Off-screen but real size: Chrome/Edge/Safari skip rendering 0x0 or
  // visibility:hidden PDF frames, which made print silently do nothing.
  frame.style.cssText =
      'position:fixed;right:0;bottom:0;width:800px;height:600px;'
      'opacity:0;pointer-events:none;border:0;z-index:-1;';
  final Completer<void> loaded = Completer<void>();
  frame.onload = ((web.Event _) {
    if (!loaded.isCompleted) loaded.complete();
  }).toJS;
  web.document.body!.append(frame);
  await loaded.future.timeout(const Duration(seconds: 15));
  // Give the PDF viewer a moment to lay out pages before printing.
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final web.Window? target = frame.contentWindow;
  if (target == null) throw StateError('Print frame has no window.');
  target.focus();
  target.print();
  // Keep the frame long enough for the print dialog to read it.
  Timer(const Duration(minutes: 2), () {
    frame.remove();
    web.URL.revokeObjectURL(url);
  });
}
