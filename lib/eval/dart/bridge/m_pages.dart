import 'package:d4rt/d4rt.dart';
import '../../model/m_manga.dart';
import '../../model/m_pages.dart';

class MPagesBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: MPages,
      name: 'MPages',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          // Support both positional: MPages(list, hasNext) and named: MPages(list: [], hasNextPage: false)
          if (positionalArgs.isNotEmpty) {
            final list = (positionalArgs[0] as List).cast<MManga>();
            final hasNext = positionalArgs.length > 1
                ? positionalArgs[1] as bool
                : false;
            return MPages(list: list, hasNextPage: hasNext);
          }
          final list = (namedArgs['list'] as List?)?.cast<MManga>() ?? [];
          final hasNext = namedArgs['hasNextPage'] as bool? ?? false;
          return MPages(list: list, hasNextPage: hasNext);
        },
      },
      methods: {},
      getters: {
        'list': (visitor, instance) => (instance as MPages).list,
        'hasNextPage': (visitor, instance) => (instance as MPages).hasNextPage,
      },
      setters: {
        'list': (visitor, instance, value) =>
            (instance as MPages).list = (value as List).cast<MManga>(),
        'hasNextPage': (visitor, instance, value) =>
            (instance as MPages).hasNextPage = value as bool,
      },
    );
  }
}
