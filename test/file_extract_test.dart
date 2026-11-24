import 'dart:convert';
import 'dart:io';

import 'package:aichat/file_extract.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// ساخت یک DOCX حداقلی در حافظه (ZIP با word/document.xml).
List<int> makeDocx(List<String> paragraphs) {
  final body = paragraphs
      .map((p) => '<w:p><w:r><w:t>$p</w:t></w:r></w:p>')
      .join('');
  final xml =
      '<?xml version="1.0"?><w:document xmlns:w="urn:x"><w:body>$body</w:body></w:document>';
  final bytes = utf8.encode(xml);
  final archive = Archive();
  archive.addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  return ZipEncoder().encode(archive);
}

/// ساخت یک PDF حداقلی با یک استریم متنی (فشرده یا خام).
List<int> makePdf(String streamText, {bool deflate = true}) {
  final raw = utf8.encode(streamText);
  final data = deflate ? zlib.encode(raw) : raw;
  final out = <int>[];
  out.addAll(utf8.encode(
      '%PDF-1.4\n1 0 obj\n<< /Length ${data.length} >>\nstream\n'));
  out.addAll(data);
  out.addAll(utf8.encode('\nendstream\nendobj\n'));
  return out;
}

void main() {
  group('fileExtension / isDocumentFileName / isImageFileName', () {
    test('extension is lowercased without the dot', () {
      expect(fileExtension('Report.PDF'), 'pdf');
      expect(fileExtension('a.py'), 'py');
      expect(fileExtension('noext'), '');
      expect(fileExtension('archive.tar.gz'), 'gz');
    });

    test('web extension lists', () {
      expect(isDocumentFileName('notes.txt'), isTrue);
      expect(isDocumentFileName('main.py'), isTrue);
      expect(isDocumentFileName('doc.docx'), isTrue);
      expect(isDocumentFileName('doc.pdf'), isTrue);
      expect(isDocumentFileName('old.doc'), isTrue);
      expect(isDocumentFileName('setup.exe'), isFalse);
      expect(isImageFileName('pic.png'), isTrue);
      expect(isImageFileName('pic.jpg'), isTrue);
      expect(isImageFileName('pic.webp'), isTrue);
      expect(isImageFileName('notes.txt'), isFalse);
    });
  });

  group('extractTextFromDocxBytes', () {
    test('extracts w:t runs with a newline per paragraph', () {
      final bytes = makeDocx(['سلام دنیا', 'خط دوم']);
      expect(extractTextFromDocxBytes(bytes), 'سلام دنیا\nخط دوم');
    });

    test('returns empty for a non-docx zip', () {
      final archive = Archive();
      final bytes = ZipEncoder().encode(archive);
      expect(extractTextFromDocxBytes(bytes), '');
    });
  });

  group('extractTextFromPdfBytes', () {
    test('reads a FlateDecode stream with Tj', () {
      final bytes =
          makePdf('BT /F1 24 Tf 100 700 Td (Hello World) Tj ET');
      expect(extractTextFromPdfBytes(bytes), contains('Hello World'));
    });

    test('reads a TJ array', () {
      final bytes = makePdf('[(Hello) -120 (World)] TJ');
      expect(extractTextFromPdfBytes(bytes), contains('Hello World'));
    });

    test('reads an uncompressed stream', () {
      final bytes =
          makePdf('BT (Plain Text) Tj ET', deflate: false);
      expect(extractTextFromPdfBytes(bytes), contains('Plain Text'));
    });

    test('returns empty when there is no text', () {
      final bytes = makePdf('BT ET');
      expect(extractTextFromPdfBytes(bytes), '');
    });
  });

  group('extractTextFromFileBytes', () {
    test('plain text files are read as UTF-8', () {
      expect(
        extractTextFromFileBytes('a.txt', utf8.encode('  سلام  ')),
        'سلام',
      );
    });

    test('size cap uses the web message', () {
      final big = List<int>.filled(maxSingleFileBytes + 1, 0x61);
      expect(
        () => extractTextFromFileBytes('big.txt', big),
        throwsA(isA<FileExtractException>().having(
          (e) => e.message,
          'message',
          contains('۵ مگابایت'),
        )),
      );
    });

    test('.doc is rejected with the web message', () {
      expect(
        () => extractTextFromFileBytes('old.doc', [1, 2, 3]),
        throwsA(isA<FileExtractException>().having(
          (e) => e.message,
          'message',
          contains('فرمت قدیمی .doc'),
        )),
      );
    });

    test('empty extraction throws the web message', () {
      expect(
        () => extractTextFromFileBytes('empty.txt', []),
        throwsA(isA<FileExtractException>().having(
          (e) => e.message,
          'message',
          contains('متنی از این فایل استخراج نشد'),
        )),
      );
    });

    test('long text is truncated at 15000 chars', () {
      final text = 'x' * 16000;
      final out = extractTextFromFileBytes('a.txt', utf8.encode(text));
      expect(out.startsWith('x' * 15000), isTrue);
      expect(out.endsWith('[...متن به‌خاطر حجم زیاد، بریده شد...]'), isTrue);
    });
  });

  group('buildDocsBlock', () {
    test('web format with one and two docs', () {
      expect(buildDocsBlock([]), '');
      expect(
        buildDocsBlock([const AttachedDoc(name: 'a.txt', text: 'متن')]),
        '\n\n--- محتوای فایل «a.txt» ---\nمتن\n--- پایان فایل «a.txt» ---',
      );
      final two = buildDocsBlock([
        const AttachedDoc(name: 'a.txt', text: 'یک'),
        const AttachedDoc(name: 'b.md', text: 'دو'),
      ]);
      expect(two, contains('--- محتوای فایل «a.txt» ---'));
      expect(two, contains('--- محتوای فایل «b.md» ---'));
    });
  });
}
