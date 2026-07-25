import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../../../theme/app_theme.dart';

/// AI & Translation settings page.
/// Manages translation provider selection, API keys, and translation options.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Settings state
  String _selectedProvider = 'claude';
  bool _offlineMode = false;
  String _targetLanguage = 'en';
  bool _bubbleDetection = true;
  String _translationQuality = 'balanced';
  bool _translationEnabled = true;

  // API keys
  final Map<String, TextEditingController> _keyControllers = {};
  final Map<String, bool> _keyVisible = {};
  final _koharuUrlController = TextEditingController();

  static const _providers = [
    {'id': 'claude', 'name': 'Claude (Anthropic)', 'desc': 'Best for nuanced translation', 'icon': '🤖', 'badge': 'Recommended', 'hint': 'sk-ant-api03-...'},
    {'id': 'openai', 'name': 'OpenAI GPT-4o', 'desc': 'Fast & accurate', 'icon': '⚡', 'hint': 'sk-proj-...'},
    {'id': 'gemini', 'name': 'Google Gemini', 'desc': 'Multilingual specialist', 'icon': '💎', 'hint': 'AIza...'},
    {'id': 'deepl', 'name': 'DeepL', 'desc': 'High-quality European languages', 'icon': '🌐', 'hint': 'xxxxxxxx-xxxx-...'},
    {'id': 'huggingface', 'name': 'Hugging Face', 'desc': 'Open-source — Offline capable', 'icon': '🤗', 'badge': 'Offline', 'hint': 'hf_...'},
  ];

  static const _languages = {
    'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
    'pt': 'Portuguese', 'it': 'Italian', 'ru': 'Russian', 'zh': 'Chinese (Simplified)',
    'zh-TW': 'Chinese (Traditional)', 'ko': 'Korean', 'ja': 'Japanese',
    'ar': 'Arabic', 'tr': 'Turkish', 'pl': 'Polish',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    for (final p in _providers) {
      _keyControllers[p['id']!] = TextEditingController();
      _keyVisible[p['id']!] = false;
    }
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _keyControllers.values) c.dispose();
    _koharuUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedProvider = prefs.getString('ai_provider') ?? 'claude';
      _offlineMode = prefs.getBool('offline_translation') ?? false;
      _targetLanguage = prefs.getString('ai_target_language') ?? 'en';
      _bubbleDetection = prefs.getBool('ai_bubble_detection') ?? true;
      _translationQuality = prefs.getString('ai_translation_quality') ?? 'balanced';
      _translationEnabled = prefs.getBool('ai_translation_enabled') ?? false;
    });
    for (final p in _providers) {
      final key = prefs.getString('api_key_${p['id']}') ?? '';
      _keyControllers[p['id']]!.text = key;
    }
    _koharuUrlController.text = prefs.getString('koharu_server_url') ?? '';
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
  }

  Future<void> _saveApiKey(String providerId, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key_$providerId', key);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.translate_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('AI & Translation', style: GoogleFonts.manrope(
              fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
        ]),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.outline,
          indicatorColor: cs.primary,
          labelStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Translation'),
            Tab(text: 'API Keys'),
            Tab(text: 'Models'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTranslationTab(cs),
          _buildApiKeysTab(cs),
          _buildModelsTab(cs),
        ],
      ),
    );
  }

  Widget _buildTranslationTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SwitchTile(
            icon: Icons.translate_rounded, iconColor: cs.primary,
            title: 'Enable AI Translation', subtitle: 'Show translate button in the reader',
            value: _translationEnabled,
            onChanged: (v) { setState(() => _translationEnabled = v); _saveSetting('ai_translation_enabled', v); },
          ),
        ),
        const SizedBox(height: 8),
        _SectionHeader(title: 'Provider'),
        ..._providers.map((p) => _buildProviderCard(cs, p)),
        const SizedBox(height: 8),
        if (_selectedProvider == 'huggingface')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _SwitchTile(
              icon: Icons.wifi_off_rounded, iconColor: AppTheme.secondary,
              title: 'Offline Mode', subtitle: 'Use downloaded models without internet',
              value: _offlineMode,
              onChanged: (v) { setState(() => _offlineMode = v); _saveSetting('offline_translation', v); },
            ),
          ),
        _SectionHeader(title: 'Translation Settings'),
        // Target language
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: cs.primary.withAlpha(25), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.language_rounded, color: cs.primary, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Target Language', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                Text('Translate manga text into this language', style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
              ])),
              DropdownButton<String>(
                value: _targetLanguage,
                underline: const SizedBox(),
                style: GoogleFonts.manrope(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
                items: _languages.entries.map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) { if (v != null) { setState(() => _targetLanguage = v); _saveSetting('ai_target_language', v); } },
              ),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SwitchTile(
            icon: Icons.chat_bubble_outline_rounded, iconColor: cs.primary,
            title: 'Bubble Detection', subtitle: 'Auto-detect speech bubbles in manga pages',
            value: _bubbleDetection,
            onChanged: (v) { setState(() => _bubbleDetection = v); _saveSetting('ai_bubble_detection', v); },
          ),
        ),
        const SizedBox(height: 8),
        _SectionHeader(title: 'Quality'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: ['fast', 'balanced', 'high'].map((q) {
            final isSelected = _translationQuality == q;
            final label = q == 'fast' ? 'Fast' : q == 'balanced' ? 'Balanced' : 'High Quality';
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () { setState(() => _translationQuality = q); _saveSetting('ai_translation_quality', q); },
                child: AnimatedContainer(
                  duration: AppTheme.fastMicro,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? cs.primary.withAlpha(26) : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: isSelected ? cs.primary : Colors.transparent, width: 1.5),
                  ),
                  child: Text(label, textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? cs.primary : cs.outline)),
                ),
              ),
            ));
          }).toList()),
        ),
        const SizedBox(height: 8),
        _SectionHeader(title: 'Koharu Server'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('🖥️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('Server URL', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
              ]),
              const SizedBox(height: 4),
              Text('Full manga inpainting via local Docker server',
                  style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
              const SizedBox(height: 8),
              TextField(
                controller: _koharuUrlController,
                style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'http://localhost:4000',
                  hintStyle: GoogleFonts.manrope(fontSize: 12, color: cs.outline),
                  helperText: 'docker run -p 4000:4000 mayocream/koharu:latest',
                  helperStyle: GoogleFonts.manrope(fontSize: 10, color: cs.outline),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.outlineVariant)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.primary)),
                ),
                onChanged: (v) => _saveSetting('koharu_server_url', v),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildProviderCard(ColorScheme cs, Map<String, String> provider) {
    final isSelected = _selectedProvider == provider['id'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: GestureDetector(
        onTap: () { setState(() => _selectedProvider = provider['id']!); _saveSetting('ai_provider', provider['id']!); },
        child: AnimatedContainer(
          duration: AppTheme.fastMicro,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary.withAlpha(15) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: isSelected ? cs.primary : Colors.transparent, width: 1.5),
          ),
          child: Row(children: [
            Text(provider['icon'] ?? '', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(provider['name']!, style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: isSelected ? cs.primary : cs.onSurface)),
                if (provider['badge'] != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (provider['badge'] == 'Offline' ? AppTheme.secondary : AppTheme.success).withAlpha(51),
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                    child: Text(provider['badge']!, style: GoogleFonts.manrope(
                        fontSize: 9, fontWeight: FontWeight.w800,
                        color: provider['badge'] == 'Offline' ? AppTheme.secondary : AppTheme.success)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(provider['desc']!, style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
              if (provider['id'] != 'huggingface') ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.key_rounded, size: 10, color: AppTheme.warning),
                  const SizedBox(width: 3),
                  Text('API key required', style: GoogleFonts.manrope(
                      fontSize: 10, color: AppTheme.warning, fontWeight: FontWeight.w500)),
                ]),
              ],
            ])),
            if (isSelected) Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
          ]),
        ),
      ),
    );
  }

  Widget _buildApiKeysTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // Security notice
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: cs.primary.withAlpha(40)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Keys are stored locally on your device and never sent to our servers.',
                style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurface, height: 1.4),
              )),
            ]),
          ),
        ),
        ..._providers.where((p) => p['id'] != 'huggingface').map((p) =>
            _buildApiKeyField(cs, p['id']!, p['name']!, p['icon']!, p['hint']!)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildApiKeyField(ColorScheme cs, String id, String name, String icon, String hint) {
    final controller = _keyControllers[id]!;
    final visible = _keyVisible[id] ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(name, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: !visible,
            style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurface),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.manrope(fontSize: 12, color: cs.outline),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.outlineVariant)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.primary)),
              suffixIcon: IconButton(
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility, size: 18, color: cs.outline),
                onPressed: () => setState(() => _keyVisible[id] = !visible),
              ),
            ),
            onChanged: (v) => _saveApiKey(id, v),
          ),
        ]),
      ),
    );
  }

  Widget _buildModelsTab(ColorScheme cs) {
    return _OfflineModelManager(cs: cs);
  }
}

/// Manages Google ML Kit's on-device translation models — the packs the
/// on-device translator (and "Offline Mode") actually use. Each language is a
/// standalone ~30 MB download that then works with no connection. ML Kit only
/// exists on Android/iOS, so elsewhere this explains that instead of offering
/// downloads that can't happen.
///
/// This replaced a mock catalogue of Hugging Face models whose only action was
/// a "coming soon" toast — those models have no on-device runtime here, so they
/// could never have been downloaded or run.
class _OfflineModelManager extends StatefulWidget {
  final ColorScheme cs;
  const _OfflineModelManager({required this.cs});

  @override
  State<_OfflineModelManager> createState() => _OfflineModelManagerState();
}

class _OfflineModelManagerState extends State<_OfflineModelManager> {
  final _manager = OnDeviceTranslatorModelManager();

  // Display name -> ML Kit language. English is the pivot every pair routes
  // through, so it is listed too; the manga source scripts (JA/KO/ZH) lead.
  static const _languages = <String, TranslateLanguage>{
    'Japanese': TranslateLanguage.japanese,
    'Korean': TranslateLanguage.korean,
    'Chinese': TranslateLanguage.chinese,
    'English': TranslateLanguage.english,
    'Spanish': TranslateLanguage.spanish,
    'French': TranslateLanguage.french,
    'German': TranslateLanguage.german,
    'Portuguese': TranslateLanguage.portuguese,
    'Italian': TranslateLanguage.italian,
    'Russian': TranslateLanguage.russian,
    'Arabic': TranslateLanguage.arabic,
    'Turkish': TranslateLanguage.turkish,
    'Polish': TranslateLanguage.polish,
  };

  final Set<String> _downloaded = {}; // bcpCodes present on device
  final Set<String> _busy = {}; // bcpCodes mid download/delete
  bool _loading = true;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_supported) {
      _refresh();
    } else {
      _loading = false;
    }
  }

  Future<void> _refresh() async {
    final done = <String>{};
    for (final lang in _languages.values) {
      try {
        if (await _manager.isModelDownloaded(lang.bcpCode)) done.add(lang.bcpCode);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _downloaded
          ..clear()
          ..addAll(done);
        _loading = false;
      });
    }
  }

  Future<void> _download(TranslateLanguage lang) async {
    setState(() => _busy.add(lang.bcpCode));
    try {
      await _manager.downloadModel(lang.bcpCode);
      if (mounted) setState(() => _downloaded.add(lang.bcpCode));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(lang.bcpCode));
    }
  }

  Future<void> _delete(TranslateLanguage lang) async {
    setState(() => _busy.add(lang.bcpCode));
    try {
      await _manager.deleteModel(lang.bcpCode);
      if (mounted) setState(() => _downloaded.remove(lang.bcpCode));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(lang.bcpCode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    if (!_supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smartphone_rounded, size: 40, color: cs.outline),
              const SizedBox(height: 12),
              Text(
                'On-device translation models are available on Android and iOS.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13, color: cs.outline),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Download a language to translate it fully offline. Each pack is about '
            '30 MB and is also fetched automatically the first time you translate '
            'that language.',
            style: GoogleFonts.manrope(fontSize: 12, color: cs.outline),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('TRANSLATION LANGUAGES',
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 1.0)),
        ),
        ..._languages.entries.map((e) => _row(cs, e.key, e.value)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _row(ColorScheme cs, String name, TranslateLanguage lang) {
    final installed = _downloaded.contains(lang.bcpCode);
    final busy = _busy.contains(lang.bcpCode);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: installed ? cs.primary.withAlpha(15) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: installed ? Border.all(color: cs.primary.withAlpha(80)) : null,
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: GoogleFonts.manrope(
                      fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Text(installed ? 'Downloaded — available offline' : 'Not downloaded',
                  style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
            ]),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (installed)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
              tooltip: 'Delete',
              onPressed: () => _delete(lang),
            )
          else
            GestureDetector(
              onTap: () => _download(lang),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: cs.primary.withAlpha(38),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.download_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text('Download',
                      style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.primary)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title.toUpperCase(), style: GoogleFonts.manrope(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: cs.primary)),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.value, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        ])),
        Switch(value: value, onChanged: onChanged,
            activeThumbColor: cs.onPrimary, activeTrackColor: cs.primary),
      ]),
    );
  }
}
