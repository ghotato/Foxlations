import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/models/source_model.dart';
import '../../../core/providers/source_provider.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/app_theme.dart';

class BrowseSourceDetailSheet extends StatelessWidget {
  final MangaSource source;
  final bool isInstalled;

  const BrowseSourceDetailSheet({
    super.key,
    required this.source,
    required this.isInstalled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.6],
      builder: (_, scrollController) {
        return GestureDetector(
          onTap: () {}, // absorb taps on the sheet itself
          child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline.withAlpha(77),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),

              // Header: icon + info
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cs.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withAlpha(51),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        source.name.isNotEmpty
                            ? source.name[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.name,
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${source.lang.toUpperCase()} • v${source.version}',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: cs.outline,
                          ),
                        ),
                        if (isInstalled) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withAlpha(26),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusFull),
                              border: Border.all(
                                  color: AppTheme.success.withAlpha(102)),
                            ),
                            child: Text(
                              'Installed',
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Stats row
              Row(
                children: [
                  Expanded(
                    child: _StatChip(
                      icon: Icons.language_rounded,
                      label: source.lang.toUpperCase(),
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatChip(
                      icon: Icons.code_rounded,
                      label: source.framework,
                      color: cs.secondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // About section
              Text(
                'ABOUT',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.outline,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Source from ${source.baseUrl}\n'
                'Language: ${source.sourceCodeLanguage.toUpperCase()}\n'
                '${source.hasCloudflare ? 'Uses Cloudflare protection' : 'No Cloudflare'}\n'
                '${source.isNsfw ? '18+ Content' : 'Safe for work'}',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: cs.onSurface,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 24),

              // Features section
              Text(
                'FEATURES',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.outline,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FeaturePill(label: 'Popular', cs: cs),
                  _FeaturePill(label: 'Latest', cs: cs),
                  _FeaturePill(label: 'Search', cs: cs),
                  _FeaturePill(label: source.framework, cs: cs),
                  if (source.isNsfw)
                    _FeaturePill(label: '18+', cs: cs, isWarning: true),
                ],
              ),

              const SizedBox(height: 32),

              // Action buttons
              Row(
                children: [
                  if (isInstalled) ...[
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.explore_rounded, size: 18),
                        label: Text('Browse ${source.name}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(
                            context,
                            AppRoutes.sourceCatalog,
                            arguments: {
                              'sourceId': source.id,
                              'sourceName': source.name,
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _ActionButton(
                      source: source,
                      isInstalled: isInstalled,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ));
      },
    ));
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(64)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  final bool isWarning;

  const _FeaturePill({
    required this.label,
    required this.cs,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? AppTheme.error : cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final MangaSource source;
  final bool isInstalled;

  const _ActionButton({required this.source, required this.isInstalled});

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isInstalled
        ? AppTheme.error
        : Theme.of(context).colorScheme.primary;

    return OutlinedButton.icon(
      icon: _loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(
              widget.isInstalled
                  ? Icons.delete_outline_rounded
                  : Icons.download_rounded,
              size: 18,
            ),
      label: Text(_loading
          ? (widget.isInstalled ? 'Removing...' : 'Installing...')
          : (widget.isInstalled ? 'Remove' : 'Install')),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(128)),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: _loading ? null : _handleAction,
    );
  }

  Future<void> _handleAction() async {
    setState(() => _loading = true);
    try {
      final provider = context.read<SourceProvider>();
      if (widget.isInstalled) {
        await provider.uninstallSource(widget.source.id);
      } else {
        await provider.installSource(widget.source);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }
}
