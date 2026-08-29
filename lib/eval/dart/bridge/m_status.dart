import 'package:d4rt/d4rt.dart';
import '../../model/m_manga.dart';

class MangaStatusBridge {
  static BridgedEnumDefinition<MangaStatus> get bridgedEnum {
    return BridgedEnumDefinition<MangaStatus>(
      name: 'Status',
      values: MangaStatus.values,
    );
  }
}
