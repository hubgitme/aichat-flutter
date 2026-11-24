import 'dart:convert';

import 'package:aichat/file_extract.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(isDocumentFileName('setup.exe'), isFalse);
      expect(isImageFileName('pic.png'), isTrue);
      expect(isImageFileName('pic.jpg'), isTrue);
      expect(isImageFileName('pic.webp'), isTrue);
      expect(isImageFileName('notes.txt'), isFalse);
    });

    test('office files are not supported', () {
      expect(isDocumentFileName('doc.docx'), isFalse);
      expect(isDocumentFileName('doc.pdf'), isFalse);
      expect(isDocumentFileName('old.doc'), isFalse);
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

    test('office files are rejected', () {
      for (final name in ['a.docx', 'a.pdf', 'a.doc']) {
        expect(
          () => extractTextFromFileBytes(name, [1, 2, 3]),
          throwsA(isA<FileExtractException>().having(
            (e) => e.message,
            'message',
            contains('آفیس'),
          )),
        );
      }
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
