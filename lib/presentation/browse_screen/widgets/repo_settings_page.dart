import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/source_provider.dart';
import '../../../theme/app_theme.dart';

class RepoSettingsPage extends StatefulWidget {
  const RepoSettingsPage({super.key});

  @override
  State<RepoSettingsPage> createState() => _RepoSettingsPageState();
}

class _RepoSettingsPageState extends State<RepoSettingsPage> {
  final _urlController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    return DraggableScrollableSheet(
      initialChildSize: isKeyboardOpen ? 0.85 : 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.55, 0.85],
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: keyboardHeight,
            ),
            child: Column(
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
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primary.withAlpha(31),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                        child: Icon(Icons.folder_special_rounded,
                            size: 18, color: cs.primary),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Extension Repositories',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Add repo input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                          color: cs.primary.withAlpha(51), width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded,
                            size: 18, color: cs.outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            style: GoogleFonts.manrope(
                                fontSize: 13, color: cs.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Repository URL (index.json)',
                              hintStyle: GoogleFonts.manrope(
                                  fontSize: 13, color: cs.outline),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              filled: false,
                            ),
                            onSubmitted: (_) => _addRepo(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isAdding ? null : _addRepo,
                          child: AnimatedContainer(
                            duration: AppTheme.fastMicro,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusFull),
                            ),
                            child: _isAdding
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Add',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Divider(height: 1, color: cs.surfaceContainerHighest),

                // Repo list header
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'REPOSITORIES',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.outline,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<SourceProvider>(
                        builder: (_, p, __) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          child: Text(
                            '${p.repoUrls.length}',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: cs.outline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Repo list
                Expanded(
                  child: Consumer<SourceProvider>(
                    builder: (_, provider, __) {
                      final repos = provider.repoUrls;
                      if (repos.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_rounded,
                                  size: 32, color: cs.outline),
                              const SizedBox(height: 8),
                              Text(
                                'No repos added yet',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 32),
                        itemCount: repos.length,
                        itemBuilder: (_, i) {
                          final url = repos[i];
                          final index = provider.repoIndexes[url];
                          return _RepoItem(
                            url: url,
                            name: index?.repoName,
                            sourceCount: index?.totalCount ?? 0,
                            onRemove: () => provider.removeRepo(url),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addRepo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isAdding = true);
    try {
      await context.read<SourceProvider>().addRepo(url);
      _urlController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add repo: $e')),
        );
      }
    }
    if (mounted) setState(() => _isAdding = false);
  }
}

class _RepoItem extends StatelessWidget {
  final String url;
  final String? name;
  final int sourceCount;
  final VoidCallback onRemove;

  const _RepoItem({
    required this.url,
    this.name,
    required this.sourceCount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName =
        name?.isNotEmpty == true ? name! : Uri.tryParse(url)?.host ?? url;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        splashColor: cs.primary.withAlpha(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(20),
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Icon(Icons.folder_rounded,
                    size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sourceCount source${sourceCount == 1 ? '' : 's'}',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppTheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
