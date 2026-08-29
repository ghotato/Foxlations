class FilterList {
  final List<dynamic> filters;
  const FilterList(this.filters);
}

class HeaderFilter {
  final String type;
  final String name;
  final String typeName;

  const HeaderFilter(this.type, this.name, this.typeName);
}

class SeparatorFilter {
  final String type;
  final String typeName;

  const SeparatorFilter(this.type, this.typeName);
}

class TextFilter {
  final String type;
  final String name;
  String state;
  final String typeName;

  TextFilter(this.type, this.name, this.state, this.typeName);
}

class CheckBoxFilter {
  final String type;
  final String name;
  bool state;
  final String typeName;

  CheckBoxFilter(this.type, this.name, this.state, this.typeName);
}

class TriStateFilter {
  final String type;
  final String name;
  int state; // 0=ignore, 1=include, 2=exclude
  final String typeName;

  TriStateFilter(this.type, this.name, this.state, this.typeName);
}

class SelectFilter {
  final String type;
  final String name;
  int state;
  final List<dynamic> values;
  final String typeName;

  SelectFilter(this.type, this.name, this.state, this.values, this.typeName);
}

class SortFilter {
  final String type;
  final String name;
  SortState state;
  final List<dynamic> values;
  final String typeName;

  SortFilter(this.type, this.name, this.state, this.values, this.typeName);
}

class SortState {
  int index;
  bool ascending;

  SortState({this.index = 0, this.ascending = true});

  factory SortState.fromJson(Map<String, dynamic> json) {
    return SortState(
      index: json['index'] as int? ?? 0,
      ascending: json['ascending'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'ascending': ascending,
      };
}

class GroupFilter {
  final String type;
  final String name;
  final List<dynamic> state;
  final String typeName;

  GroupFilter(this.type, this.name, this.state, this.typeName);
}

List<dynamic> filterValuesListToJson(List<dynamic> filters) {
  return filters.map((f) {
    if (f is TextFilter) {
      return {'type': f.type, 'name': f.name, 'state': f.state, 'typeName': f.typeName};
    } else if (f is CheckBoxFilter) {
      return {'type': f.type, 'name': f.name, 'state': f.state, 'typeName': f.typeName};
    } else if (f is TriStateFilter) {
      return {'type': f.type, 'name': f.name, 'state': f.state, 'typeName': f.typeName};
    } else if (f is SelectFilter) {
      return {'type': f.type, 'name': f.name, 'state': f.state, 'typeName': f.typeName};
    } else if (f is SortFilter) {
      return {
        'type': f.type,
        'name': f.name,
        'state': f.state.toJson(),
        'typeName': f.typeName,
      };
    } else if (f is GroupFilter) {
      return {
        'type': f.type,
        'name': f.name,
        'state': filterValuesListToJson(f.state),
        'typeName': f.typeName,
      };
    }
    return f;
  }).toList();
}

List<dynamic> fromJsonFilterValuesToList(List<dynamic> json) {
  return json.map((e) {
    if (e is! Map) return e;
    final map = e as Map<String, dynamic>;
    final type = map['type'] as String? ?? '';
    final name = map['name'] as String? ?? '';
    final typeName = map['typeName'] as String? ?? '';

    switch (typeName) {
      case 'TextFilter':
        return TextFilter(type, name, map['state'] as String? ?? '', typeName);
      case 'CheckBoxFilter':
        return CheckBoxFilter(type, name, map['state'] as bool? ?? false, typeName);
      case 'TriStateFilter':
        return TriStateFilter(type, name, map['state'] as int? ?? 0, typeName);
      case 'SelectFilter':
        return SelectFilter(
            type, name, map['state'] as int? ?? 0, map['values'] as List? ?? [], typeName);
      case 'SortFilter':
        return SortFilter(
          type,
          name,
          SortState.fromJson(map['state'] as Map<String, dynamic>? ?? {}),
          map['values'] as List? ?? [],
          typeName,
        );
      case 'GroupFilter':
        return GroupFilter(
          type,
          name,
          fromJsonFilterValuesToList(map['state'] as List? ?? []),
          typeName,
        );
      default:
        return e;
    }
  }).toList();
}
