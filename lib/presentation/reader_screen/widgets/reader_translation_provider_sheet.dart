import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/app_theme.dart';

enum TranslationProvider { claude, openai, gemini, deepl, huggingFace }

/// Two-page bottom sheet: Provider selection + Target language.
/// Syncs with SharedPreferences (same keys as AI settings page).
class ReaderTranslationProviderSheet extends StatefulWidget {
  final VoidCallback onChanged;

  const ReaderTranslationProviderSheet({super.key, required this.onChanged});

  @override
  State<ReaderTranslationProviderSheet> createState() => _State();

  /// Load current provider name from settings.
  static Future<String> getProviderName() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('ai_provider') ?? 'gemini';
    return const {
      'claude': 'Claude', 'openai': 'GPT-4o', 'gemini': 'Gemini',
      'deepl': 'DeepL', 'huggingface': 'HF',
    }[id] ?? 'Gemini';
  }

  /// Load current target language name from settings.
  static Future<String> getTargetLanguageName() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('ai_target_language') ?? 'en';
    return _languages[code] ?? 'English';
  }

  static const _languages = {
    'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
    'pt': 'Portuguese', 'it': 'Italian', 'ru': 'Russian', 'zh': 'Chinese',
    'zh-TW': 'Chinese (Trad)', 'ko': 'Korean', 'ja': 'Japanese',
    'ar': 'Arabic', 'tr': 'Turkish', 'pl': 'Polish',
  };
}

class _State extends State<ReaderTranslationProviderSheet> {
  int _page = 0; // 0 = provider, 1 = language
  String _selectedProvider = 'gemini';
  String _selectedLanguage = 'en';

  static const _providers = [
    {'id': 'claude', 'name': 'Claude (Anthropic)', 'icon': '🤖', 'badge': 'Recommended'},
    {'id': 'openai', 'name': 'OpenAI GPT-4o', 'icon': '⚡'},
    {'id': 'gemini', 'name': 'Google Gemini', 'icon': '💎', 'badge': 'Cheapest'},
    {'id': 'deepl', 'name': 'DeepL', 'icon': '🌐'},
    {'id': 'huggingface', 'name': 'Hugging Face', 'icon': '🤗', 'badge': 'Offline'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedProvider = prefs.getString('ai_provider') ?? 'gemini';
      _selectedLanguage = prefs.getString('ai_target_language') ?? 'en';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', _selectedProvider);
    await prefs.setString('ai_target_language', _selectedLanguage);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.8,
      snap: true,
      snapSizes: const [0.55],
      builder: (_, controller) => GestureDetector(
        onTap: () {},
        child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Drag handle
          Container(margin: const EdgeInsets.only(top: 12), width: 36, height: 4,
              decoration: BoxDecoration(color: cs.outline.withAlpha(128), borderRadius: BorderRadius.circular(2))),
          // Tab selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Expanded(child: _TabChip(label: 'Provider', isSelected: _page == 0, cs: cs,
                  onTap: () => setState(() => _page = 0))),
              const SizedBox(width: 8),
              Expanded(child: _TabChip(label: 'Language', isSelected: _page == 1, cs: cs,
                  onTap: () => setState(() => _page = 1))),
            ]),
          ),
          Divider(color: cs.surfaceContainerHighest, height: 1),
          // Content
          Expanded(
            child: _page == 0
                ? _buildProviderPage(cs, controller)
                : _buildLanguagePage(cs, controller),
          ),
        ]),
      )),
    ));
  }

  Widget _buildProviderPage(ColorScheme cs, ScrollController controller) {
    return ListView(controller: controller, padding: const EdgeInsets.all(12), children: [
      ..._providers.map((p) {
        final id = p['id'] as String;
        final isSelected = _selectedProvider == id;
        return GestureDetector(
          onTap: () { setState(() => _selectedProvider = id); _save(); },
          child: AnimatedContainer(
            duration: AppTheme.fastMicro,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? cs.primary.withAlpha(15) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: isSelected ? cs.primary : Colors.transparent, width: 1.5),
            ),
            child: Row(children: [
              Text(p['icon'] as String, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Row(children: [
                Text(p['name'] as String, style: GoogleFonts.manrope(fontSize: 13,
                    fontWeight: FontWeight.w700, color: isSelected ? cs.primary : cs.onSurface)),
                if (p.containsKey('badge')) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withAlpha(40),
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                    child: Text(p['badge'] as String, style: GoogleFonts.manrope(
                        fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.success)),
                  ),
                ],
              ])),
              if (isSelected) Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _buildLanguagePage(ColorScheme cs, ScrollController controller) {
    return ListView(controller: controller, padding: const EdgeInsets.all(12), children: [
      ...ReaderTranslationProviderSheet._languages.entries.map((e) {
        final isSelected = _selectedLanguage == e.key;
        return GestureDetector(
          onTap: () { setState(() => _selectedLanguage = e.key); _save(); },
          child: AnimatedContainer(
            duration: AppTheme.fastMicro,
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected ? cs.primary.withAlpha(15) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: isSelected ? cs.primary : Colors.transparent, width: 1.5),
            ),
            child: Row(children: [
              Expanded(child: Text(e.value, style: GoogleFonts.manrope(fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurface))),
              if (isSelected) Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
            ]),
          ),
        );
      }),
    ]);
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.isSelected, required this.cs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.fastMicro,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary.withAlpha(26) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(color: isSelected ? cs.primary : Colors.transparent, width: 1.5),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? cs.primary : cs.outline)),
      ),
    );
  }
}
