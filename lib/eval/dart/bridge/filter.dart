import 'package:d4rt/d4rt.dart';
import '../../model/filter.dart';

class FilterListBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: FilterList,
      name: 'FilterList',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return FilterList(positionalArgs[0] as List? ?? []);
        },
      },
      methods: {},
      getters: {
        'filters': (visitor, instance) => (instance as FilterList).filters,
      },
      setters: {},
    );
  }
}

class SelectFilterBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: SelectFilter,
      name: 'SelectFilter',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return SelectFilter(
            positionalArgs[0] as String,
            positionalArgs[1] as String,
            positionalArgs[2] as int,
            positionalArgs[3] as List,
            positionalArgs.length > 4 ? positionalArgs[4] as String : 'SelectFilter',
          );
        },
      },
      methods: {},
      getters: {
        'type': (visitor, instance) => (instance as SelectFilter).type,
        'name': (visitor, instance) => (instance as SelectFilter).name,
        'state': (visitor, instance) => (instance as SelectFilter).state,
        'values': (visitor, instance) => (instance as SelectFilter).values,
      },
      setters: {
        'state': (visitor, instance, value) =>
            (instance as SelectFilter).state = value as int,
      },
    );
  }
}

class CheckBoxFilterBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: CheckBoxFilter,
      name: 'CheckBoxFilter',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return CheckBoxFilter(
            positionalArgs[0] as String,
            positionalArgs[1] as String,
            positionalArgs[2] as bool,
            positionalArgs.length > 3 ? positionalArgs[3] as String : 'CheckBoxFilter',
          );
        },
      },
      methods: {},
      getters: {
        'type': (visitor, instance) => (instance as CheckBoxFilter).type,
        'name': (visitor, instance) => (instance as CheckBoxFilter).name,
        'state': (visitor, instance) => (instance as CheckBoxFilter).state,
      },
      setters: {
        'state': (visitor, instance, value) =>
            (instance as CheckBoxFilter).state = value as bool,
      },
    );
  }
}

class GroupFilterBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: GroupFilter,
      name: 'GroupFilter',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) {
          return GroupFilter(
            positionalArgs[0] as String,
            positionalArgs[1] as String,
            positionalArgs[2] as List,
            positionalArgs.length > 3 ? positionalArgs[3] as String : 'GroupFilter',
          );
        },
      },
      methods: {},
      getters: {
        'type': (visitor, instance) => (instance as GroupFilter).type,
        'name': (visitor, instance) => (instance as GroupFilter).name,
        'state': (visitor, instance) => (instance as GroupFilter).state,
      },
      setters: {},
    );
  }
}
