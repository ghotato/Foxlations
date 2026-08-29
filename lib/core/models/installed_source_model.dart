import 'source_model.dart';

enum InstallStatus { notInstalled, installing, installed, error }

/// Represents an installed source with its downloaded code.
class InstalledSource {
  final MangaSource source;
  final String sourceCode;
  final DateTime installedAt;
  InstallStatus status;

  InstalledSource({
    required this.source,
    required this.sourceCode,
    required this.installedAt,
    this.status = InstallStatus.installed,
  });
}
