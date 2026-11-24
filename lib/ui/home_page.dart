// صفحهٔ اصلیِ چت — لیست گفت‌وگوها (دراور)، پیام‌ها، استریم با دکمهٔ توقف،
// حالت‌های جست‌وجو/تصویر/ویدیو، پیوست عکس و همگام‌سازی.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../downloads.dart';
import '../file_extract.dart';
import '../models.dart';
import '../settings.dart';
import '../store.dart';
import '../sync_crypto.dart';
import '../sync_engine.dart';
import '../utils.dart';
import 'code_block.dart';
import 'mode_selectors.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppSettings? _settings;
  ConversationStore? _store;
  TombstoneStore? _tombs;
  List<Conversation> _conversations = [];
  Conversation? _current;
  bool _loading = true;

  bool _searchMode = false;
  bool _imageMode = false;
  bool _videoMode = false;
  bool _streaming = false;
  bool _cancelled = false;
  http.Client? _activeChatClient;

  // پیوست‌ها — مثل نسخهٔ وب: عکس‌ها (vision) و فایل‌های سند (متنِ استخراج‌شده).
  final List<_AttachedImage> _attachedImages = [];
  final List<_AttachedDoc> _attachedDocs = [];

  /// فایل‌های سندِ معتبر (متن استخراج شده و بدون خطا).
  List<AttachedDoc> get _validDocs => _attachedDocs
      .where((d) => d.text != null && d.error == null)
      .map((d) => AttachedDoc(name: d.name, text: d.text!))
      .toList();

  List<String> get _attachedImageUrls =>
      _attachedImages.map((i) => i.dataUrl).toList();

  /// اولین عکسِ پیوستی — برای حالت «ویرایش عکس».
  String? get _firstImageDataUrl =>
      _attachedImages.isEmpty ? null : _attachedImages.first.dataUrl;

  final _composerCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();

  bool _syncing = false;
  String _lastSyncText = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    _scrollCtrl.dispose();
    _activeChatClient?.close();
    super.dispose();
  }

  Future<void> _init() async {
    final settings = await AppSettings.load();
    final prefs = await SharedPreferences.getInstance();
    final store = ConversationStore(prefs);
    final tombs = TombstoneStore(prefs);
    final convs = await store.listAll();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _store = store;
      _tombs = tombs;
      _conversations = convs;
      _current = convs.isNotEmpty ? convs.first : null;
      _loading = false;
    });
    final last = await getLastSyncAt(prefs);
    if (last > 0) {
      _lastSyncText =
          'آخرین همگام‌سازی: ${DateTime.fromMillisecondsSinceEpoch(last)}';
    }
    if (settings.autoSync && settings.syncCode.isNotEmpty) {
      _syncNow(silent: true);
    }
  }

  Future<void> _saveSettings() async {
    await _settings?.save();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _newConversation() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final conv = Conversation(
      id: 'c$now',
      title: 'گفت‌وگوی جدید',
      createdAt: now,
      updatedAt: now,
    );
    await _store?.putRaw(conv);
    setState(() {
      _conversations.insert(0, conv);
      _current = conv;
    });
  }

  Future<void> _refreshList() async {
    final convs = await _store?.listAll() ?? [];
    if (!mounted) return;
    setState(() => _conversations = convs);
  }

  Future<void> _openConversation(Conversation conv) async {
    setState(() => _current = conv);
    Navigator.of(context).maybePop();
  }

  Future<void> _renameConversation(Conversation conv) async {
    final ctrl = TextEditingController(text: conv.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغییر نام گفت‌وگو'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      conv.title = name;
      conv.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _store?.putRaw(conv);
      await _refreshList();
    }
  }

  Future<void> _deleteConversation(Conversation conv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف گفت‌وگو'),
        content: Text('«${conv.title}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store?.remove(conv.id);
    await _tombs?.add(conv.id);
    if (_current?.id == conv.id) {
      _current = null;
    }
    await _refreshList();
    if (_current == null && _conversations.isNotEmpty) {
      setState(() => _current = _conversations.first);
    }
  }

  Future<void> _exportConversations() async {
    try {
      final json = await _store?.exportAll() ?? '';
      final result = await saveTextToDownloads(
        text: json,
        filename:
            'aichat-export-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      _snack(result.isPublic
          ? 'خروجی در پوشهٔ Downloads ذخیره شد: ${result.displayPath}'
          : 'خروجی ذخیره شد: ${result.displayPath}');
    } catch (e) {
      _snack('خطا در خروجی: $e');
    }
  }

  Future<void> _importConversations() async {
    final ctrl = TextEditingController();
    final jsonText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بازیابی گفت‌وگوها'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'متن JSON خروجی را اینجا بچسبانید…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('بازیابی'),
          ),
        ],
      ),
    );
    if (jsonText == null || jsonText.trim().isEmpty) return;
    try {
      final n = await _store?.importAll(jsonText);
      await _refreshList();
      _snack('$n گفت‌وگو بازیابی شد.');
    } catch (e) {
      _snack('فایل نامعتبر است: $e');
    }
  }

  // --- همگام‌سازی ---

  Future<String> _syncNow({bool silent = false}) async {
    final settings = _settings;
    if (settings == null) return 'تنظیمات هنوز بارگذاری نشده است.';
    if (!settings.hasBackend) {
      return 'اول آدرس بک‌اند را در تنظیمات وارد کن.';
    }
    if (!isValidSyncCode(settings.syncCode)) {
      return 'کد همگام‌سازی معتبر نیست (۲۰ حرف).';
    }
    if (_syncing) return 'همگام‌سازی در حال انجام است…';
    setState(() => _syncing = true);
    try {
      final keys = deriveSyncKeys(settings.syncCode);
      final api = ApiClient(settings.backendBase);
      final result = await runSync(
        api: (action, payload) => api.syncCall(keys.syncId, action, payload),
        aesKey: keys.aesKey,
        local: _store!,
        tombstones: _tombs!,
        shouldSkip: (id) => _streaming && _current?.id == id,
      );
      api.close();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await setLastSyncAt(prefs, now);
      if (mounted) {
        setState(() {
          _lastSyncText = 'آخرین همگام‌سازی: ${DateTime.fromMillisecondsSinceEpoch(now)}';
        });
      }
      await _refreshList();
      if (result.errors.isNotEmpty) {
        return 'همگام‌سازی با خطا تمام شد: ${result.errors.first}';
      }
      final parts = <String>[];
      if (result.pulled.isNotEmpty) parts.add('${result.pulled.length} دریافت');
      if (result.pushed > 0) parts.add('${result.pushed} ارسال');
      if (result.deletedLocal.isNotEmpty) {
        parts.add('${result.deletedLocal.length} حذف محلی');
      }
      if (result.deletedRemote > 0) {
        parts.add('${result.deletedRemote} حذف از سرور');
      }
      if (result.tooLarge > 0) {
        parts.add('${result.tooLarge} گفت‌وگو خیلی بزرگ بود');
      }
      return parts.isEmpty ? 'همگام‌سازی انجام شد — تغییری نبود.' : 'همگام‌سازی انجام شد: ${parts.join('، ')}.';
    } catch (e) {
      return 'خطا در همگام‌سازی: $e';
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // --- پیوست عکس ---

  Future<void> _pickImage() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        _snack('عکس بزرگ‌تر از ۸ مگابایت است.');
        return;
      }
      final name = x.name.toLowerCase();
      final mime = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      if (mounted) {
        setState(() {
          _attachedImages.add(_AttachedImage(
            bytes: bytes,
            dataUrl: 'data:$mime;base64,${base64Encode(bytes)}',
            name: x.name,
          ));
        });
      }
    } catch (e) {
      _snack('خطا در انتخاب عکس: $e');
    }
  }

  // --- پیوست فایل (مثل نسخهٔ وب: عکس + سند/کد + PDF + Word) ---

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: pickableExtensions,
      );
      for (final f in files) {
        final name = f.name;
        final ext = fileExtension(name);
        if (imageExtensions.contains(ext)) {
          final bytes = await f.readAsBytes();
          if (bytes.length > 8 * 1024 * 1024) {
            _snack('عکس بزرگ‌تر از ۸ مگابایت است.');
            continue;
          }
          final lower = name.toLowerCase();
          final mime = lower.endsWith('.png')
              ? 'image/png'
              : lower.endsWith('.webp')
                  ? 'image/webp'
                  : lower.endsWith('.gif')
                      ? 'image/gif'
                      : 'image/jpeg';
          if (mounted) {
            setState(() {
              _attachedImages.add(_AttachedImage(
                bytes: bytes,
                dataUrl: 'data:$mime;base64,${base64Encode(bytes)}',
                name: name,
              ));
            });
          }
          continue;
        }
        if (!documentExtensions.contains(ext)) {
          _snack('نوع فایل «$name» پشتیبانی نمی‌شود.');
          continue;
        }
        // سقف حجم را قبل از خواندنِ کامل چک می‌کنیم (مثل وب).
        final size = await f.length();
        if (size != null && size > maxSingleFileBytes) {
          _snack('حجم فایل «$name» بیش از حد مجاز است (حداکثر ۵ مگابایت).');
          continue;
        }
        final doc = _AttachedDoc(name: name, loading: true);
        if (mounted) setState(() => _attachedDocs.add(doc));
        try {
          final bytes = await f.readAsBytes();
          final text = extractTextFromFileBytes(name, bytes);
          if (mounted) {
            setState(() {
              doc.text = text;
              doc.loading = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              doc.error = e.toString();
              doc.loading = false;
            });
          }
        }
      }
    } catch (e) {
      _snack('خطا در انتخاب فایل: $e');
    }
  }

  void _clearAttachment() {
    setState(() {
      _attachedImages.clear();
      _attachedDocs.clear();
    });
  }

  // --- ارسال پیام ---

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _saveCurrent() async {
    final conv = _current;
    if (conv == null) return;
    conv.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _store?.putRaw(conv);
    await _refreshList();
  }

  Future<void> _send() async {
    final settings = _settings;
    if (settings == null) return;
    final text = _composerCtrl.text.trim();
    if (text.isEmpty &&
        _attachedImages.isEmpty &&
        _validDocs.isEmpty) {
      return;
    }
    if (!settings.hasBackend) {
      _snack('اول آدرس بک‌اند را در تنظیمات وارد کن.');
      return;
    }
    var conv = _current;
    if (conv == null) {
      await _newConversation();
      conv = _current;
      if (conv == null) return;
    }
    final isFirstUserMsg =
        conv.messages.where((m) => m.role == 'user').isEmpty;

    if (_imageMode) {
      await _handleImageMode(conv, text);
      return;
    }
    if (_videoMode) {
      await _handleVideoMode(conv, text);
      return;
    }

    final images = _attachedImages.isEmpty ? null : _attachedImageUrls;
    // متنِ فایل‌های پیوستی به پیام اضافه می‌شود (همان docsBlock نسخهٔ وب)؛
    // content همان متنِ تایپ‌شده می‌ماند و docNames برای نمایش ذخیره می‌شود.
    final docs = _validDocs;
    final docsBlock = buildDocsBlock(docs);
    final userMsg = ChatMessage(
      role: 'user',
      content: text,
      apiContent: docsBlock.isEmpty ? null : text + docsBlock,
      images: images,
      docNames: docs.isEmpty ? null : docs.map((d) => d.name).toList(),
    );
    conv.messages.add(userMsg);
    if (isFirstUserMsg) {
      final titleBase = text.isNotEmpty
          ? text
          : (docs.isNotEmpty ? '📄 ${docs.first.name}' : 'گفت‌وگوی جدید');
      conv.title =
          titleBase.length > 40 ? titleBase.substring(0, 40) : titleBase;
    }
    _composerCtrl.clear();
    _clearAttachment();
    setState(() {});
    _scrollToBottom();

    // کانتکستِ جست‌وجو و خواندن لینک (همان نسخهٔ وب).
    String? combinedContext;
    try {
      String? searchContext;
      if (_searchMode && text.isNotEmpty) {
        try {
          final api = ApiClient(settings.backendBase);
          final results = await api.searchWeb(text);
          api.close();
          searchContext = buildSearchContextMessage(text, results);
        } catch (e) {
          searchContext = 'جست‌وجوی وب با خطا مواجه شد: $e. بر اساس دانش خودت جواب بده.';
        }
      }
      String? urlContext;
      final urls = extractUrls(text);
      if (urls.isNotEmpty) {
        try {
          final api = ApiClient(settings.backendBase);
          final data = await api.fetchUrl(urls.first);
          api.close();
          urlContext = buildUrlContextMessage(urls.first, data);
        } catch (e) {
          urlContext = buildUrlErrorContextMessage(urls.first, e.toString());
        }
      }
      final parts = [searchContext, urlContext]
          .where((c) => c != null && c.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) combinedContext = parts.join('\n\n');
    } catch (_) {}

    if (!settings.hasChatConfig) {
      conv.messages.add(ChatMessage(
        role: 'assistant',
        content: 'پروایدر/مدل/کلید چت در تنظیمات کامل نیست.',
        error: true,
      ));
      await _saveCurrent();
      setState(() {});
      return;
    }

    final apiMessages = buildApiMessages(conv,
        images: images, context: combinedContext);
    final assistantMsg = ChatMessage(role: 'assistant', content: '');
    conv.messages.add(assistantMsg);
    setState(() => _streaming = true);
    _cancelled = false;

    final api = ApiClient(settings.backendBase);
    try {
      final full = await api.streamChat(
        messages: apiMessages,
        settings: settings,
        onToken: (delta, fullText) {
          assistantMsg.content = fullText;
          if (mounted) setState(() {});
        },
        isCancelled: () => _cancelled,
        clientFactory: () {
          _activeChatClient = http.Client();
          return _activeChatClient!;
        },
      );
      assistantMsg.content = full;
    } on ApiException catch (e) {
      if (assistantMsg.content.isEmpty) {
        assistantMsg.content = 'خطا: ${e.message}';
        assistantMsg.error = true;
      }
    } catch (e) {
      if (assistantMsg.content.isEmpty) {
        assistantMsg.content = 'خطا: $e';
        assistantMsg.error = true;
      }
    } finally {
      api.close();
      _activeChatClient = null;
      if (mounted) setState(() => _streaming = false);
    }
    await _saveCurrent();
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  Future<void> _handleImageMode(Conversation conv, String text) async {
    final settings = _settings!;
    final needsSource = settings.imageEndpointType ==
            ImageEndpointType.edits ||
        settings.imageEndpointType == ImageEndpointType.editsJson;
    if (needsSource && _firstImageDataUrl == null) {
      _snack('برای «ویرایش عکس»، اول یک عکس پیوست کن.');
      return;
    }
    if (settings.imageProviderUrl.trim().isEmpty) {
      _snack('آدرس پروایدر تصویر در تنظیمات وارد نشده است.');
      return;
    }
    if (settings.imageEndpointType != ImageEndpointType.simpleGet &&
        (settings.imageModel.trim().isEmpty ||
            settings.imageApiKey.trim().isEmpty)) {
      _snack('مدل و کلید تصویر در تنظیمات وارد نشده است.');
      return;
    }
    final userMsg = ChatMessage(
      role: 'user',
      content: text,
      images: _attachedImages.isEmpty ? null : _attachedImageUrls,
    );
    conv.messages.add(userMsg);
    _composerCtrl.clear();
    final src = _firstImageDataUrl;
    _clearAttachment();
    setState(() {});
    _scrollToBottom();
    final api = ApiClient(settings.backendBase);
    try {
      final images = await api.generateImage(
        prompt: text,
        settings: settings,
        sourceImageDataUrl: src,
      );
      conv.messages.add(ChatMessage(
        role: 'assistant',
        content: 'تصویر ساخته شد:',
        images: images,
        generatedImage: true,
      ));
    } catch (e) {
      conv.messages.add(ChatMessage(
        role: 'assistant',
        content: 'خطا در ساخت تصویر: $e',
        error: true,
      ));
    } finally {
      api.close();
    }
    await _saveCurrent();
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  Future<void> _handleVideoMode(Conversation conv, String text) async {
    final settings = _settings!;
    if (settings.videoProviderUrl.trim().isEmpty) {
      _snack('آدرس پروایدر ویدیو در تنظیمات وارد نشده است.');
      return;
    }
    final userMsg = ChatMessage(role: 'user', content: text);
    conv.messages.add(userMsg);
    _composerCtrl.clear();
    setState(() {});
    _scrollToBottom();
    final api = ApiClient(settings.backendBase);
    try {
      final url = await api.generateVideo(prompt: text, settings: settings);
      conv.messages.add(ChatMessage(
        role: 'assistant',
        content: 'ویدیو آماده است:',
        videoUrl: url,
        generatedVideo: true,
      ));
    } catch (e) {
      conv.messages.add(ChatMessage(
        role: 'assistant',
        content: 'خطا در ساخت ویدیو: $e',
        error: true,
      ));
    } finally {
      api.close();
    }
    await _saveCurrent();
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _stopStreaming() {
    _cancelled = true;
    _activeChatClient?.close();
  }

  void _toggleImageMode() {
    setState(() {
      _imageMode = !_imageMode;
      if (_imageMode) {
        _videoMode = false;
        _searchMode = false;
      }
    });
  }

  void _toggleVideoMode() {
    setState(() {
      _videoMode = !_videoMode;
      if (_videoMode) {
        _imageMode = false;
        _searchMode = false;
      }
    });
  }

  void _toggleSearchMode() {
    setState(() {
      _searchMode = !_searchMode;
      if (_searchMode) {
        _imageMode = false;
        _videoMode = false;
      }
    });
  }

  /// بازگشت به گفت‌وگوی عادی (بدون حالت خاص).
  void _clearMode() {
    setState(() {
      _searchMode = false;
      _imageMode = false;
      _videoMode = false;
    });
  }

  bool get _isPlainChat => !_searchMode && !_imageMode && !_videoMode;

  String? get _activeModeLabel {
    if (_imageMode) return 'تولید تصویر';
    if (_videoMode) return 'تولید ویدیو';
    if (_searchMode) return 'جست‌وجوی وب';
    return null;
  }

  String get _composerHint {
    if (_imageMode) return 'پرامپت تصویر…';
    if (_videoMode) return 'پرامپت ویدیو…';
    if (_searchMode) return 'سؤال برای جست‌وجوی وب…';
    return 'پیام…';
  }

  /// انتخاب از منوی «+» کنار کامپوزر.
  void _onComposerMenuSelected(String value) {
    switch (value) {
      case 'chat':
        _clearMode();
        break;
      case 'attach':
        _pickImage();
        break;
      case 'file':
        _pickFiles();
        break;
      case 'search':
        _toggleSearchMode();
        break;
      case 'image':
        _toggleImageMode();
        break;
      case 'video':
        _toggleVideoMode();
        break;
    }
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: settings,
          onSettingsChanged: _saveSettings,
          onSyncNow: () => _syncNow(),
          onDisconnectSync: () async {
            final prefs = await SharedPreferences.getInstance();
            await TombstoneStore(prefs).clear();
            setState(() => _lastSyncText = '');
          },
          lastSyncText: _lastSyncText,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // --- رابط کاربری ---

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final settings = _settings!;
    final conv = _current;
    return Scaffold(
      appBar: AppBar(
        title: Text(conv?.title ?? 'AI CHAT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'همگام‌سازی',
            onPressed: _syncing
                ? null
                : () async {
                    final msg = await _syncNow();
                    _snack(msg);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'تنظیمات',
            onPressed: _openSettings,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildTopbarSelectors(settings),
          if (!settings.hasBackend)
            MaterialBanner(
              content: const Text(
                  'آدرس بک‌اند تنظیم نشده است — از تنظیمات، آدرس دیپلوی Vercel خودت را وارد کن.'),
              leading: const Icon(Icons.warning_amber),
              actions: [
                TextButton(
                  onPressed: _openSettings,
                  child: const Text('تنظیمات'),
                ),
              ],
            ),
          Expanded(
            child: conv == null
                ? const Center(
                    child: Text('از منوی کناری یک گفت‌وگوی جدید بساز.'),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: conv.messages.length,
                    itemBuilder: (ctx, i) =>
                        _MessageBubble(message: conv.messages[i]),
                  ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('گفت‌وگوی جدید'),
              onTap: () {
                Navigator.of(context).pop();
                _newConversation();
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _conversations.length,
                itemBuilder: (ctx, i) {
                  final c = _conversations[i];
                  final selected = _current?.id == c.id;
                  return ListTile(
                    selected: selected,
                    title: Text(
                      c.title.isEmpty ? 'گفت‌وگو' : c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openConversation(c),
                    onLongPress: () => _showConvActions(c),
                  );
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('خروجی'),
                      onPressed: _exportConversations,
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('بازیابی'),
                      onPressed: _importConversations,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConvActions(Conversation conv) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('تغییر نام'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('حذف'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      await _renameConversation(conv);
    } else if (action == 'delete') {
      await _deleteConversation(conv);
    }
  }

  /// نوارِ انتخابِ پروایدر/مدل و کلیدِ چت — مثل نوار بالای نسخهٔ وب.
  /// اگر هنوز پروایدر یا کلیدی ثبت نشده، دکمه‌ای برای رفتن به تنظیمات است.
  Widget _buildTopbarSelectors(AppSettings settings) {
    final theme = Theme.of(context);
    if (settings.providers.isEmpty && settings.apiKeys.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: InkWell(
          onTap: _openSettings,
          child: Text(
            'پروایدر و کلید چت تنظیم نشده — برای افزودن، اینجا بزن',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: ProviderModelDropdown(
              settings: settings,
              value: settings.chatProviderModel,
              dense: true,
              hintText: 'پروایدر / مدل',
              onChanged: (v) {
                if (v == null) return;
                setState(() => settings.chatProviderModel = v);
                _saveSettings();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ApiKeyDropdown(
              settings: settings,
              value: settings.chatKey,
              dense: true,
              hintText: 'کلید',
              onChanged: (v) {
                if (v == null) return;
                setState(() => settings.chatKey = v);
                _saveSettings();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // پیش‌نمایش پیوست‌ها — مثل نسخهٔ وب: بند انگشتی عکس‌ها و
            // چیپِ فایل‌های سند (با وضعیت خواندن/خطا)، هرکدام با ✕ برای حذف.
            if (_attachedImages.isNotEmpty || _attachedDocs.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _attachedImages.length; i++)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _attachedImages[i].bytes,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              child: InkWell(
                                onTap: () => setState(
                                    () => _attachedImages.removeAt(i)),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.errorContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child:
                                      const Icon(Icons.close, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      for (var i = 0; i < _attachedDocs.length; i++)
                        Chip(
                          label: Text(
                            _attachedDocs[i].loading
                                ? '⏳ ${_attachedDocs[i].name}'
                                : _attachedDocs[i].error != null
                                    ? '⚠️ ${_attachedDocs[i].name}'
                                    : '📄 ${_attachedDocs[i].name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () =>
                              setState(() => _attachedDocs.removeAt(i)),
                        ),
                    ],
                  ),
                ),
              ),
            if (_activeModeLabel != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Chip(
                    label: Text('حالت: $_activeModeLabel'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: _clearMode,
                  ),
                ),
              ),
            TextField(
              controller: _composerCtrl,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _composerHint,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _streaming
                    ? IconButton.filled(
                        icon: const Icon(Icons.stop),
                        tooltip: 'توقف',
                        onPressed: _stopStreaming,
                      )
                    : IconButton.filled(
                        icon: const Icon(Icons.send),
                        tooltip: 'ارسال',
                        onPressed: _send,
                      ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  tooltip: 'حالت و ابزار',
                  enabled: !_streaming,
                  onSelected: _onComposerMenuSelected,
                  itemBuilder: (ctx) => [
                    _composerMenuItem(
                        'chat', Icons.chat_bubble_outline, 'گفت‌وگوی عادی', _isPlainChat),
                    _composerMenuItem(
                        'attach', Icons.attach_file, 'پیوست عکس', false),
                    _composerMenuItem('file', Icons.insert_drive_file,
                        'پیوست فایل', false),
                    _composerMenuItem(
                        'search', Icons.search, 'جست‌وجوی وب', _searchMode),
                    _composerMenuItem(
                        'image', Icons.image, 'تولید تصویر', _imageMode),
                    _composerMenuItem(
                        'video', Icons.videocam, 'تولید ویدیو', _videoMode),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _composerMenuItem(
      String value, IconData icon, String title, bool active) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
          if (active) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }
}

/// حبابِ یک پیام.
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final align =
        isUser ? Alignment.centerRight : Alignment.centerLeft;
    // رنگ حباب‌ها از تم وب: کاربر = --bg-active، دستیار = --bg-panel.
    final bg = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    return Align(
      alignment: align,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: message.error ? theme.colorScheme.errorContainer : bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.images != null && message.images!.isNotEmpty)
              ...message.images!.map((src) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _InlineImage(src: src),
                  )),
            if (message.generatedVideo && message.videoUrl != null)
              _VideoCard(url: message.videoUrl!),
            // نام فایل‌های پیوستی — مثل docHint نسخهٔ وب.
            if (message.docNames != null && message.docNames!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '📄 پیوست: ${message.docNames!.join('، ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (message.content.isNotEmpty)
              isUser
                  ? SelectableText(message.content)
                  : MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ),
                      builders: {
                        'pre': CodeBlockBuilder(
                          onNotice: (msg) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                          },
                        ),
                      },
                    ),
            if (message.sources != null && message.sources!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: message.sources!
                      .map((s) => ActionChip(
                            label: Text(
                              s.title.isEmpty ? s.url : s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () async {
                              final uri = Uri.tryParse(s.url);
                              if (uri != null) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// عکسِ داخل پیام — data URL یا لینک، با دکمهٔ ذخیره.
class _InlineImage extends StatelessWidget {
  final String src;
  const _InlineImage({required this.src});

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (src.startsWith('data:')) {
      try {
        final b64 = src.split(',').last;
        img = Image.memory(
          base64Decode(b64),
          fit: BoxFit.contain,
        );
      } catch (_) {
        img = const Text('عکس قابل نمایش نیست.');
      }
    } else {
      img = Image.network(src, fit: BoxFit.contain);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: img,
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          icon: const Icon(Icons.download, size: 16),
          label: const Text('ذخیرهٔ عکس'),
          onPressed: () async {
            try {
              Uint8List bytes;
              String ext = 'png';
              if (src.startsWith('data:')) {
                bytes = base64Decode(src.split(',').last);
                final mime = src.split(';').first.replaceFirst('data:', '');
                ext = mime.contains('jpeg') || mime.contains('jpg')
                    ? 'jpg'
                    : mime.contains('webp')
                        ? 'webp'
                        : 'png';
              } else {
                final res = await HttpClient()
                    .getUrl(Uri.parse(src))
                    .then((r) => r.close());
                final chunks = <int>[];
                await for (final c in res) {
                  chunks.addAll(c);
                }
                bytes = Uint8List.fromList(chunks);
              }
              final filename =
                  'aichat-image-${DateTime.now().millisecondsSinceEpoch}.$ext';
              final result =
                  await saveToDownloads(bytes: bytes, filename: filename);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(result.isPublic
                          ? 'در پوشهٔ Downloads ذخیره شد: ${result.displayPath}'
                          : 'ذخیره شد: ${result.displayPath}')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطا در ذخیرهٔ عکس: $e')),
                );
              }
            }
          },
        ),
      ],
    );
  }
}

/// کارتِ ویدیو — لینکِ قابلِ بازشدن در مرورگر/پخش‌کننده.
class _VideoCard extends StatelessWidget {
  final String url;
  const _VideoCard({required this.url});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: const Icon(Icons.play_circle_filled, size: 36),
        title: const Text('پخش ویدیو'),
        subtitle: Text(
          url,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'کپی لینک',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('لینک کپی شد ✓')),
              );
            }
          },
        ),
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    );
  }
}

/// یک عکسِ پیوستی (بایت‌ها + data URL برای vision + نام فایل).
class _AttachedImage {
  final Uint8List bytes;
  final String dataUrl;
  final String name;
  const _AttachedImage({
    required this.bytes,
    required this.dataUrl,
    required this.name,
  });
}

/// یک فایلِ سندِ پیوستی (نام + متنِ استخراج‌شده یا وضعیت خواندن/خطا).
class _AttachedDoc {
  final String name;
  String? text;
  bool loading;
  String? error;
  _AttachedDoc({
    required this.name,
    this.loading = false,
  });
}
