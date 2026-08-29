import 'm_manga.dart';

class MPages {
  List<MManga> list;
  bool hasNextPage;

  MPages({required this.list, this.hasNextPage = false});

  factory MPages.fromJson(Map<String, dynamic> json) {
    return MPages(
      list: (json['list'] as List?)
              ?.map((e) => MManga.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      hasNextPage: json['hasNextPage'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'list': list.map((v) => v.toJson()).toList(),
        'hasNextPage': hasNextPage,
      };
}
