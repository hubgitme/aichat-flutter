// صفحهٔ اصلیِ چت — لیست گفت‌وگوها (دراور)، پیام‌ها، استریم با دکمهٔ توقف،
// حالت‌های جست‌وجو/تصویر/ویدیو، پیوست عکس و همگام‌سازی.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../settings.dart';
import '../store.dart';
import '../sync_crypto.dart';
import '../sync_engine.dart';
import '../utils.dart';
import 'code_block.dart';
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

  Uint8List? _attachedBytes;
  String? _attachedDataUrl;

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
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/aichat-export-${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(json, encoding: utf8);
      _snack('خروجی ذخیره شد: ${file.path}');
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
      setState(() {
        _attachedBytes = bytes;
        _attachedDataUrl =
            'data:$mime;base64,${base64Encode(bytes)}';
      });
    } catch (e) {
      _snack('خطا در انتخاب عکس: $e');
    }
  }

  void _clearAttachment() {
    setState(() {
      _attachedBytes = null;
      _attachedDataUrl = null;
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
    if (text.isEmpty && _attachedDataUrl == null) return;
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

    final images = _attachedDataUrl != null ? [_attachedDataUrl!] : null;
    final userMsg = ChatMessage(
      role: 'user',
      content: text,
      images: images,
    );
    conv.messages.add(userMsg);
    if (isFirstUserMsg) {
      conv.title = text.length > 40 ? text.substring(0, 40) : text;
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
    if (needsSource && _attachedDataUrl == null) {
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
      images: _attachedDataUrl != null ? [_attachedDataUrl!] : null,
    );
    conv.messages.add(userMsg);
    _composerCtrl.clear();
    final src = _attachedDataUrl;
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
        title: Text(conv?.title ?? 'ای‌چت'),
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
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    settings: settings,
                    onSettingsChanged: _saveSettings,
                    onSyncNow: () => _syncNow(),
                    onDisconnectSync: () async {
                      final prefs =
                          await SharedPreferences.getInstance();
                      await TombstoneStore(prefs).clear();
                      setState(() => _lastSyncText = '');
                    },
                    lastSyncText: _lastSyncText,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          if (!settings.hasBackend)
            MaterialBanner(
              content: const Text(
                  'آدرس بک‌اند تنظیم نشده است — از تنظیمات، آدرس دیپلوی Vercel خودت را وارد کن.'),
              leading: const Icon(Icons.warning_amber),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsPage(
                          settings: settings,
                          onSettingsChanged: _saveSettings,
                          onSyncNow: () => _syncNow(),
                          onDisconnectSync: () {},
                          lastSyncText: _lastSyncText,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
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
            if (_attachedBytes != null)
              Align(
                alignment: Alignment.centerRight,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _attachedBytes!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: InkWell(
                        onTap: _clearAttachment,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'پیوست عکس',
                  onPressed: _streaming ? null : _pickImage,
                ),
                IconButton(
                  icon: Icon(
                    Icons.search,
                    color: _searchMode
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  tooltip: 'جست‌وجوی وب',
                  onPressed: _streaming ? null : _toggleSearchMode,
                ),
                IconButton(
                  icon: Icon(
                    Icons.image,
                    color: _imageMode
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  tooltip: 'حالت تصویر',
                  onPressed: _streaming ? null : _toggleImageMode,
                ),
                IconButton(
                  icon: Icon(
                    Icons.videocam,
                    color: _videoMode
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  tooltip: 'حالت ویدیو',
                  onPressed: _streaming ? null : _toggleVideoMode,
                ),
                Expanded(
                  child: TextField(
                    controller: _composerCtrl,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _imageMode
                          ? 'پرامپت تصویر…'
                          : _videoMode
                              ? 'پرامپت ویدیو…'
                              : 'پیام…',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
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
              ],
            ),
          ],
        ),
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
    final bg = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerLow;
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
              final dir = await getApplicationDocumentsDirectory();
              final file = File(
                  '${dir.path}/aichat-image-${DateTime.now().millisecondsSinceEpoch}.$ext');
              await file.writeAsBytes(bytes);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ذخیره شد: ${file.path}')),
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
