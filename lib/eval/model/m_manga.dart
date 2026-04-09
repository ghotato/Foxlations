import 'm_chapter.dart';

enum MangaStatus {
  ongoing,
  completed,
  onHiatus,
  canceled,
  publishingFinished,
  unknown,
}

class MManga {
  String? name;
  String? link;
  String? imageUrl;
  String? description;
  String? author;
  String? artist;
  MangaStatus? status;
  List<String>? genre;
  List<MChapter>? chapters;

  MManga({
    this.name,
    this.link,
    this.imageUrl,
    this.description,
    this.author,
    this.artist,
    this.status = MangaStatus.unknown,
    this.genre,
    this.chapters,
  });

  factory MManga.fromJson(Map<String, dynamic> json) {
    return MManga(
      name: json['name'] as String?,
      link: json['link'] as String?,
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      author: json['author'] as String?,
      artist: json['artist'] as String?,
      status: switch (json['status'] as int?) {
        0 => MangaStatus.ongoing,
        1 => MangaStatus.completed,
        2 => MangaStatus.onHiatus,
        3 => MangaStatus.canceled,
        4 => MangaStatus.publishingFinished,
        _ => MangaStatus.unknown,
      },
      genre: (json['genre'] as List?)?.map((e) => e.toString()).toList() ?? [],
      chapters: (json['chapters'] as List?)
              ?.map((e) => MChapter.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'link': link,
        'imageUrl': imageUrl,
        'description': description,
        'author': author,
        'artist': artist,
        'status': status?.index ?? 5,
        'genre': genre,
        'chapters': chapters?.map((c) => c.toJson()).toList() ?? [],
      };
}
