class PageUrl {
  String url;
  String? fileName;
  Map<String, String>? headers;

  PageUrl(this.url, {this.fileName, this.headers});

  factory PageUrl.fromJson(Map<String, dynamic> json) {
    return PageUrl(
      json['url'].toString().trim(),
      headers: (json['headers'] as Map?)
          ?.map((key, value) => MapEntry(key.toString(), value.toString())),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        if (headers != null) 'headers': headers,
        if (fileName != null) 'fileName': fileName,
      };

  @override
  String toString() => 'PageUrl(url: $url, headers: $headers)';
}
