import 'dart:convert';

/// Generates a **self-contained, loadable Mangayomi JavaScript source** from a
/// RepoForge detection/extension record, plus its `index.json` catalog row.
///
/// Why standalone JS (typeSource "single", sourceCodeLanguage 1):
/// Mangayomi runs `.js` sources in an embedded QuickJS engine at runtime — no
/// compiler needed. A standalone source embeds the site's CSS selectors
/// directly, so it works without depending on any externally-hosted shared
/// parser. Known CMS frameworks get accurate canonical selectors (pulled from
/// the community multisrc parsers); unknown sites get the selectors the
/// detector extracted, or generic fallbacks the user can tune in the editor.
///
/// Bridge API used by the emitted code (provided by Mangayomi at runtime):
///   new Client().get(url, headers) -> { body }
///   new Document(html) -> { select(css)->[el], selectFirst(css)->el|null }
///   element.text (getter), element.attr(name), element.getSrc, element.getHref
class MangayomiJsGenerator {
  /// The frameworks RepoForge emits a purpose-built (non-generic) source for.
  /// Surfaced in the RepoForge coverage browser. `kinds` = content it supports.
  static const List<Map<String, dynamic>> supportedFrameworks = [
    {'name': 'MangaDex', 'group': 'Manga API', 'kinds': ['manga'], 'note': 'Official api.mangadex.org JSON API'},
    {'name': 'HeanCMS', 'group': 'Manga API', 'kinds': ['manga'], 'note': 'Reaper-style /query + /series API'},
    {'name': 'KeyoApp', 'group': 'Manga API', 'kinds': ['manga'], 'note': 'Asura/KeyoApp /api/series'},
    {'name': 'FlameComics', 'group': 'Manga API', 'kinds': ['manga'], 'note': 'Next.js _next/data JSON'},
    {'name': 'Madara', 'group': 'Manga theme', 'kinds': ['manga', 'novel'], 'note': 'WordPress Madara (AJAX chapters)'},
    {'name': 'MangaThemesia', 'group': 'Manga theme', 'kinds': ['manga', 'novel'], 'note': 'MangaThemesia / LightNovel-WP'},
    {'name': 'MangaStream', 'group': 'Manga theme', 'kinds': ['manga', 'novel'], 'note': 'WP Manga Stream'},
    {'name': 'MangaBox', 'group': 'Manga theme', 'kinds': ['manga'], 'note': 'Manganato/Mangakakalot family'},
    {'name': 'MMRCMS', 'group': 'Manga theme', 'kinds': ['manga'], 'note': 'My Manga Reader CMS'},
    {'name': 'xVideos Engine', 'group': 'Video', 'kinds': ['anime'], 'note': 'Tube sites (categories + player)'},
    {'name': 'Custom', 'group': 'Generic', 'kinds': ['manga', 'anime', 'novel'], 'note': 'Heuristic + selector knowledge base'},
  ];

  /// Build the `.js` source text for [ext] (a RepoForge extension/detection map).
  static String generateSource(Map<String, dynamic> ext) {
    final spec = _Spec.fromMap(ext);
    final String template;
    if (spec.itemType == 2) {
      // Light novel: chapters are HTML text (getHtmlContent), not page images.
      // Novel sites reuse the same framework structures as manga for browsing —
      // only the chapter payload differs (text vs images). So pick the framework
      // body (which now also exposes getHtmlContent) and fall back to generic.
      if (spec.framework == 'Madara') {
        template = _header + _madaraBody;
      } else if (spec.framework == 'MangaThemesia' ||
          spec.framework == 'MangaStream') {
        template = _header + _mangaThemesiaBody;
      } else {
        template = _header + _novelBody;
      }
    } else if (spec.isApiFramework) {
      // JSON-API source (e.g. KeyoApp/Asura) — no HTML scraping.
      template = _apiHeader + _apiBodyFor(spec.framework);
    } else if (spec.isTubeFramework) {
      // Tube/video site (e.g. xVideos): single-video-per-page model.
      template = _header + _tubeBody;
    } else if (spec.framework == 'Madara') {
      // WordPress Madara: chapters via admin-ajax POST, pages via ?style=list.
      template = _header + _madaraBody;
    } else if (spec.framework == 'MangaThemesia' || spec.framework == 'MangaStream') {
      // MangaThemesia/WPMangaStream: reader pages in a JSON ts_reader blob.
      template = _header + _mangaThemesiaBody;
    } else if (spec.framework == 'MMRCMS') {
      // My Manga Reader CMS: /filterList browse, /search JSON, #arraydata pages.
      template = _header + _mmrcmsBody;
    } else if (spec.framework == 'FlameComics') {
      // Next.js _next/data/{buildId} JSON (FlameComics + clones).
      template = _apiHeader + _flameBody;
    } else {
      final body = spec.isAnime ? _animeBody : _mangaBody;
      template = _header + body;
    }
    return _fill(template, spec);
  }

  /// Pick the JSON-API body for an API framework. New API frameworks slot in
  /// here (each REST API has its own response schema, so each needs a body).
  static String _apiBodyFor(String framework) {
    switch (framework) {
      case 'MangaDex':
        return _mangaDexApiBody;
      case 'HeanCMS':
        return _heanApiBody;
      case 'KeyoApp':
        return _keyoApiBody;
      default:
        return _keyoApiBody;
    }
  }

  /// Build the Mangayomi catalog row (one entry of index.json / anime_index.json).
  static Map<String, dynamic> generateIndexEntry(
    Map<String, dynamic> ext, {
    String sourceCodeUrl = '',
  }) {
    final spec = _Spec.fromMap(ext);
    return {
      'name': spec.name,
      'id': spec.id,
      'baseUrl': spec.baseUrl,
      'lang': spec.lang,
      'typeSource': 'single',
      'iconUrl': spec.iconUrl,
      'dateFormat': '',
      'dateFormatLocale': '',
      'isNsfw': spec.isNsfw,
      'hasCloudflare': spec.hasCloudflare,
      'sourceCodeUrl': sourceCodeUrl,
      'apiUrl': '',
      'version': spec.version,
      'isManga': !spec.isAnime,
      'itemType': spec.itemType,
      'isFullData': false,
      'appMinVerReq': '0.5.0',
      'additionalParams': '',
      'sourceCodeLanguage': 1, // JavaScript
      'notes': spec.notes,
    };
  }

  /// The relative path a source occupies inside a repo (used for hosting).
  static String pkgPath(Map<String, dynamic> ext) {
    final spec = _Spec.fromMap(ext);
    return '${spec.itemFolder}/src/${spec.lang}/${spec.fileBase}.js';
  }

  // ── Template filling ──────────────────────────────────────────────────────

  static String _fill(String template, _Spec s) {
    final sel = s.selectors;
    // Mangayomi expects `const mangayomiSources = [ {…} ]` — an ARRAY of source
    // objects, not a bare object.
    final manifest = const JsonEncoder.withIndent('  ').convert([
      {
        'name': s.name,
        'lang': s.lang,
        'baseUrl': s.baseUrl,
        'apiUrl': '',
        'iconUrl': s.iconUrl,
        'typeSource': 'single',
        'isManga': !s.isAnime,
        'itemType': s.itemType,
        'version': s.version,
        'dateFormat': '',
        'dateFormatLocale': '',
        'isNsfw': s.isNsfw,
        'hasCloudflare': s.hasCloudflare,
        'pkgPath': '${s.itemFolder}/src/${s.lang}/${s.fileBase}.js',
      },
    ]);

    // Dedupe categories (case-insensitive by name); drop the site's own "All"
    // and status browse links (we prepend our own "All").
    final seenCat = <String>{};
    final cats = s.categories.where((c) {
      final n = (c['name'] ?? '').trim();
      final key = n.toLowerCase();
      if (n.isEmpty || key == 'all') return false;
      if ((c['path'] ?? '').contains('state=')) return false;
      return seenCat.add(key);
    }).toList();
    final filters = cats.isEmpty
        ? '[]'
        : '[\n      {\n        type_name: "SelectFilter", name: "Category", state: 0,\n'
              '        values: [\n'
              '          { type_name: "SelectOption", name: "All", value: "" },\n'
              '${cats.map((c) => '          { type_name: "SelectOption", name: ${_jsStr(c['name']!)}, value: ${_jsStr(c['path']!)} }').join(',\n')}\n'
              '        ],\n      },\n    ]';

    final map = <String, String>{
      '__MANIFEST__': manifest,
      '__FILTERS__': filters,
      '__FRAMEWORK__': s.framework,
      '__API_BASE__': _js(s.apiBase),
      '__POPULAR_PATH__': _js(sel.popularPath),
      '__LATEST_PATH__': _js(sel.latestPath),
      '__SEARCH_PATH__': _js(sel.searchPath),
      '__ITEM_SEL__': _js(sel.item),
      '__TITLE_SEL__': _js(sel.title),
      '__COVER_SEL__': _js(sel.cover),
      '__COVER_ATTR__': _js(sel.coverAttr),
      '__NEXT_SEL__': _js(sel.nextPage),
      '__D_TITLE__': _js(sel.detailTitle),
      '__D_COVER__': _js(sel.detailCover),
      '__D_DESC__': _js(sel.detailDesc),
      '__D_AUTHOR__': _js(sel.detailAuthor),
      '__D_GENRE__': _js(sel.detailGenre),
      '__CH_LIST__': _js(sel.chapterList),
      '__CH_NAME__': _js(sel.chapterName),
      '__PAGE_IMG__': _js(sel.pageImages),
      '__PAGE_ATTR__': _js(sel.pageImageAttr),
      '__EP_LIST__': _js(sel.episodeList),
      '__EP_NAME__': _js(sel.episodeName),
      '__VIDEO_IFRAME__': _js(sel.videoIframe),
    };
    var out = template;
    map.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  /// Escape a selector for placement inside a JS double-quoted string.
  static String _js(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  static String _jsStr(String s) => '"${_js(s)}"';

  // Aggregated fallback selectors from the 1220-site selector KB
  // (assets/selector_kb.json `candidates`), filtered to what the html CSS engine
  // supports. Appended after framework selectors so the generated source tries
  // "every selector it can get" (via the try-each _qa/_q1 helpers).
  static const String _kbItem =
      'div.manga-item, .listupd .manga-card-v, div.card-body div.card, '
      'ul.manga-list-1-list li, .manga-list-1-list li, div.anipost, div.manga, '
      'div.manga-item-grid > div.uk-panel';
  static const String _kbChapters =
      'tbody > tr, div.listing-item > a.title, .wp-manga-chapter, '
      'ul.detail-main-list li a, ul.detail-main-list > li, '
      'div.w-full div.grid div.col-span-4, '
      '#list_chapters > div.collapse > div.list_chapters, .capitoli_cont > a, '
      'div.chapter-list > div.chapter-item, ul.list > li, '
      'ul#mh-chapter-list-ol-0 li.chapter__item';
  static const String _kbPages =
      '.entry-content img, div.entry-content img, #comic img, .page-image, '
      '.article-fulltext img, img.lazy.comic_img, .reader-page img, '
      'img.reader-image, #chapter-content img, #main img.block, .article-body img, '
      '.gallery-item img, img[fetchpriority=high], .mainleft img, '
      '.slideshow-container > img, .gallery-item > dt > img, '
      '.manga-detail__swiper-wrapper img, div.article-fulltext img[src]';

  // ── JS templates (raw strings: JS `$`/`${}` are literal, not Dart interp) ──

  static const String _header = r'''
// Generated by RepoForge — Framework: __FRAMEWORK__
// Self-contained Mangayomi source (CSS-selector based). Loadable as-is.
const mangayomiSources = __MANIFEST__;

class DefaultExtension extends MProvider {
  getHeaders(url) {
    return { "Referer": this.source.baseUrl, "User-Agent": "Mozilla/5.0" };
  }

  _abs(url) {
    if (!url) return "";
    if (url.startsWith("http")) return url;
    if (url.startsWith("//")) return "https:" + url;
    return this.source.baseUrl + (url.startsWith("/") ? url : "/" + url);
  }

  _text(el) { return el ? el.text.trim() : ""; }

  _img(el) {
    if (!el) return "";
    const a = el.attr("__COVER_ATTR__");
    return this._abs(a && a.length ? a : el.getSrc);
  }

  // Multi-selector helpers: a role's selector is a comma-separated candidate
  // list (framework selectors first, then KB fallbacks). Try each until one
  // matches — unsupported/no-match selectors just return empty and are skipped.
  _split(csv) { return (csv || "").split(",").map((s) => s.trim()).filter((s) => s.length); }
  _qa(node, csv) {
    for (const s of this._split(csv)) {
      try { const e = node.select(s); if (e && e.length) return e; } catch (x) {}
    }
    return [];
  }
  _q1(node, csv) {
    for (const s of this._split(csv)) {
      try { const e = node.selectFirst(s); if (e) return e; } catch (x) {}
    }
    return null;
  }
''';

  // ── JSON-API templates ────────────────────────────────────────────────────
  // Used when the detected framework is API-based (see _Spec._apiFrameworks).
  // These talk to the site's REST API and parse JSON instead of scraping HTML.

  static const String _apiHeader = r'''
// Generated by RepoForge — Framework: __FRAMEWORK__ (JSON API)
// Self-contained Mangayomi source. Talks to the site's REST API (no HTML scraping).
const mangayomiSources = __MANIFEST__;

class DefaultExtension extends MProvider {
  get apiBase() {
    const detected = "__API_BASE__";
    if (detected && detected.length) return detected.replace(/\/+$/, "");
    const base = this.source.baseUrl.replace(/\/+$/, "");
    const m = base.match(/^(https?:\/\/)(?:www\.)?(.+)$/);
    return m ? (m[1] + "api." + m[2]) : base;
  }

  _headers() { return { "Referer": this.source.baseUrl + "/", "User-Agent": "Mozilla/5.0" }; }
  getHeaders(url) { return this._headers(); }

  _abs(url) {
    if (!url) return "";
    if (url.startsWith("http")) return url;
    if (url.startsWith("//")) return "https:" + url;
    return this.source.baseUrl + (url.startsWith("/") ? url : "/" + url);
  }

  _m(str, re) { const x = str.match(re); return x ? x[1] : ""; }
''';

  // KeyoApp / Asura family: /api/series list + /api/series/{slug}(/chapters) detail.
  // Ported from the working Foxtensions Dart source.
  static const String _keyoApiBody = r'''
  _parseList(body) {
    let data;
    try { data = JSON.parse(body); } catch (e) { return { list: [], hasNextPage: false }; }
    const arr = (data && data.data) ? data.data : (Array.isArray(data) ? data : []);
    const list = [];
    for (const s of arr) {
      const title = (s.series_title || s.name || s.title || "").toString();
      if (!title) continue;
      let link = (s.public_url || s.url || "").toString();
      if (link && !link.startsWith("http")) link = this.source.baseUrl + (link.startsWith("/") ? link : "/" + link);
      const cover = (s.cover || s.cover_url || s.thumbnail || s.image || "").toString();
      list.push({ name: title, link: link, imageUrl: cover });
    }
    return { list: list, hasNextPage: arr.length >= 20 };
  }

  async _series(sort, page) {
    const offset = (page - 1) * 20;
    const url = this.apiBase + "/api/series?sort=" + sort + "&order=desc&offset=" + offset + "&limit=20";
    const res = await new Client().get(url, this._headers());
    return this._parseList(res.body);
  }

  async getPopular(page) { return await this._series("popular", page); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return await this._series("latest", page); }

  async search(query, page, filters) {
    const offset = (page - 1) * 20;
    const url = this.apiBase + "/api/series?search=" + encodeURIComponent(query) + "&offset=" + offset + "&limit=20&sort=rating&order=desc";
    const res = await new Client().get(url, this._headers());
    return this._parseList(res.body);
  }

  _slug(url) {
    let p = url.split(this.source.baseUrl).join("").split("/comics/").join("").split("/series/").join("");
    if (p.startsWith("/")) p = p.substring(1);
    if (p.endsWith("/")) p = p.substring(0, p.length - 1);
    return p;
  }

  async getDetail(url) {
    const path = this._slug(url);
    const slug = path.replace(/-[a-f0-9]{8}$/, "");
    const res = await new Client().get(this.apiBase + "/api/series/" + slug, this._headers());
    const body = res.body;
    let sj = body;
    const st = body.indexOf(',"series":{');
    if (st >= 0) {
      const after = body.substring(st);
      let end = after.indexOf(',"recommended_series"');
      if (end < 0) end = after.indexOf(',"chapters"');
      if (end < 0) end = after.length;
      sj = after.substring(0, end);
    }
    const name = this._m(sj, /"title"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    let desc = this._m(sj, /"description"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    desc = desc.split("\\n").join("\n").split('\\"').join('"');
    let cover = this._m(sj, /"cover"\s*:\s*"([^"]*)"/);
    if (!cover) cover = this._m(sj, /"cover_url"\s*:\s*"([^"]*)"/);
    const author = this._m(sj, /"author"\s*:\s*"([^"]*)"/);
    let status = 5;
    const stat = this._m(sj, /"status"\s*:\s*"([^"]*)"/).toLowerCase();
    if (stat.indexOf("ongoing") >= 0) status = 0;
    else if (stat.indexOf("completed") >= 0) status = 1;
    else if (stat.indexOf("hiatus") >= 0) status = 2;
    const genre = [];
    const gb = sj.match(/"genres"\s*:\s*\[([\s\S]*?)\]/);
    if (gb) { const re = /"name"\s*:\s*"([^"]*)"/g; let g; while ((g = re.exec(gb[1])) !== null) genre.push(g[1]); }

    const chapters = [];
    let off = 0, more = true, guard = 0;
    while (more && guard < 50) {
      guard++;
      const cr = await new Client().get(this.apiBase + "/api/series/" + slug + "/chapters?offset=" + off + "&limit=100", this._headers());
      const parts = cr.body.split('"series_id":');
      let found = 0;
      for (let i = 1; i < parts.length; i++) {
        const e = parts[i];
        const num = this._m(e, /"number"\s*:\s*(\d+)/);
        const cs = this._m(e, /"slug"\s*:\s*"([^"]*)"/);
        const t = this._m(e, /"title"\s*:\s*"((?:[^"\\]|\\.)*)"/);
        const d = this._m(e, /"published_at"\s*:\s*"([^"]*)"/);
        if (num && cs) {
          const nm = (t && t !== "null") ? ("Chapter " + num + ": " + t) : ("Chapter " + num);
          chapters.push({ name: nm, url: this.source.baseUrl + "/comics/" + path + "/" + cs, dateUpload: d ? String(Date.parse(d) || "") : "" });
          found++;
        }
      }
      more = found >= 100;
      off += 100;
      if (found === 0) break;
    }
    return { name: name, imageUrl: cover, description: desc, author: author, genre: genre, status: status, link: url, chapters: chapters };
  }

  async getPageList(url) {
    const path = this._slug(url);
    const parts = path.split("/");
    if (parts.length < 2) return [];
    const ss = parts[0].replace(/-[a-f0-9]{8}$/, "");
    const cs = parts[1];
    const res = await new Client().get(this.apiBase + "/api/series/" + ss + "/chapters/" + cs, this._headers());
    const pages = [];
    const re = /"(?:url|image_url|page_url|image|src)"\s*:\s*"([^"]*)"/g;
    let m;
    while ((m = re.exec(res.body)) !== null) {
      const img = m[1].split("\\/").join("/");
      if (/\.(jpg|jpeg|png|webp)/i.test(img)) pages.push(img);
    }
    return pages;
  }

  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // MangaDex: the official JSON API at api.mangadex.org. Manga list/search via
  // /manga, chapters via /manga/{id}/feed, page images via /at-home/server/{id}.
  // Covers come from uploads.mangadex.org. Clean JSON — parsed with JSON.parse.
  static const String _mangaDexApiBody = r'''
  get apiRoot() { return "https://api.mangadex.org"; }
  get uploads() { return "https://uploads.mangadex.org"; }
  get _lang() { return (this.source && this.source.lang) ? this.source.lang : "en"; }

  _title(attr) {
    const t = attr.title || {};
    if (t.en) return t.en;
    const alts = attr.altTitles || [];
    const keys = Object.keys(t);
    if (keys.length) return t[keys[0]];
    for (const a of alts) { const k = Object.keys(a); if (k.length) return a[k[0]]; }
    return "Unknown";
  }

  _cover(item) {
    for (const r of (item.relationships || [])) {
      if (r.type === "cover_art" && r.attributes && r.attributes.fileName) {
        return this.uploads + "/covers/" + item.id + "/" + r.attributes.fileName + ".256.jpg";
      }
    }
    return "";
  }

  _rating() { return "&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica" + (this.source.isNsfw ? "&contentRating[]=pornographic" : ""); }

  _mapList(body) {
    let data;
    try { data = JSON.parse(body); } catch (e) { return { list: [], hasNextPage: false }; }
    const arr = data.data || [];
    const list = [];
    for (const it of arr) {
      list.push({ name: this._title(it.attributes || {}), link: this.source.baseUrl + "/title/" + it.id, imageUrl: this._cover(it) });
    }
    return { list: list, hasNextPage: ((data.offset || 0) + (data.limit || arr.length)) < (data.total || 0) };
  }

  async _list(orderKey, page) {
    const off = (page - 1) * 20;
    const url = this.apiRoot + "/manga?limit=20&offset=" + off + "&includes[]=cover_art"
      + this._rating() + "&order[" + orderKey + "]=desc&hasAvailableChapters=true";
    const res = await new Client().get(url, this._headers());
    return this._mapList(res.body);
  }

  async getPopular(page) { return await this._list("followedCount", page); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return await this._list("latestUploadedChapter", page); }

  async search(query, page, filters) {
    const off = (page - 1) * 20;
    const url = this.apiRoot + "/manga?limit=20&offset=" + off + "&title=" + encodeURIComponent(query)
      + "&includes[]=cover_art" + this._rating();
    const res = await new Client().get(url, this._headers());
    return this._mapList(res.body);
  }

  _id(url) {
    const m = url.match(/title\/([0-9a-f-]{36})/i);
    if (m) return m[1];
    return url.replace(/\/+$/, "").split("/").pop();
  }

  async getDetail(url) {
    const id = this._id(url);
    const res = await new Client().get(this.apiRoot + "/manga/" + id + "?includes[]=cover_art&includes[]=author&includes[]=artist", this._headers());
    let data;
    try { data = JSON.parse(res.body).data; } catch (e) { data = null; }
    if (!data) return { name: "", link: url, chapters: [] };
    const attr = data.attributes || {};
    let desc = "";
    if (attr.description) { const dk = Object.keys(attr.description); desc = attr.description.en || (dk.length ? attr.description[dk[0]] : ""); }
    let status = 5;
    const st = (attr.status || "").toLowerCase();
    if (st === "ongoing") status = 0;
    else if (st === "completed") status = 1;
    else if (st === "hiatus") status = 2;
    else if (st === "cancelled") status = 3;
    const genre = [];
    for (const tg of (attr.tags || [])) { const n = tg.attributes && tg.attributes.name; if (n) genre.push(n.en || n[Object.keys(n)[0]]); }
    let author = "";
    for (const r of (data.relationships || [])) { if (r.type === "author" && r.attributes && r.attributes.name) { author = r.attributes.name; break; } }
    const chapters = await this._feed(id);
    return { name: this._title(attr), imageUrl: this._cover(data), description: desc, author: author, genre: genre, status: status, link: url, chapters: chapters };
  }

  async _feed(id) {
    const chapters = [];
    let off = 0, total = 1, guard = 0;
    while (off < total && guard < 40) {
      guard++;
      const url = this.apiRoot + "/manga/" + id + "/feed?limit=100&offset=" + off
        + "&translatedLanguage[]=" + this._lang + "&order[chapter]=desc&order[volume]=desc"
        + "&includes[]=scanlation_group" + this._rating() + "&contentRating[]=pornographic";
      const res = await new Client().get(url, this._headers());
      let data;
      try { data = JSON.parse(res.body); } catch (e) { break; }
      total = data.total || 0;
      const arr = data.data || [];
      if (!arr.length) break;
      for (const c of arr) {
        const a = c.attributes || {};
        if (a.externalUrl) continue;
        const num = a.chapter;
        let nm = (num !== null && num !== undefined && num !== "") ? ("Chapter " + num) : "Oneshot";
        if (a.title && a.title !== "null") nm += ": " + a.title;
        chapters.push({ name: nm, url: this.source.baseUrl + "/chapter/" + c.id, dateUpload: a.publishAt ? String(Date.parse(a.publishAt) || "") : "" });
      }
      off += 100;
    }
    return chapters;
  }

  async getPageList(url) {
    const m = url.match(/chapter\/([0-9a-f-]{36})/i);
    const cid = m ? m[1] : url.replace(/\/+$/, "").split("/").pop();
    const res = await new Client().get(this.apiRoot + "/at-home/server/" + cid, this._headers());
    let data;
    try { data = JSON.parse(res.body); } catch (e) { return []; }
    const base = data.baseUrl;
    const ch = data.chapter || {};
    if (!base || !ch.hash) return [];
    const pages = [];
    for (const f of (ch.data || [])) pages.push(base + "/data/" + ch.hash + "/" + f);
    return pages;
  }

  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // HeanCMS (Laravel + Next.js manhwa CMS: Reaper Scans, Perf Scans, ...).
  // Series via /query, detail via /series/{slug} (chapters nested in seasons),
  // pages via /series/{slug}/{chapterSlug} -> chapter.chapter_data.images.
  static const String _heanApiBody = r'''
  _img(u) {
    if (!u) return "";
    if (u.startsWith("http")) return u;
    if (u.startsWith("//")) return "https:" + u;
    return this.apiBase + (u.startsWith("/") ? u : "/" + u);
  }

  _mapList(body) {
    let data;
    try { data = JSON.parse(body); } catch (e) { return { list: [], hasNextPage: false }; }
    const arr = data.data || (Array.isArray(data) ? data : []);
    const list = [];
    for (const s of arr) {
      const title = (s.title || s.name || "").toString();
      if (!title) continue;
      const slug = (s.series_slug || s.slug || "").toString();
      list.push({ name: title, link: this.source.baseUrl + "/series/" + slug, imageUrl: this._img(s.thumbnail || s.cover || "") });
    }
    const meta = data.meta || {};
    const more = meta.current_page && meta.last_page ? (meta.current_page < meta.last_page) : (arr.length >= 12);
    return { list: list, hasNextPage: more };
  }

  async _query(orderBy, page) {
    const url = this.apiBase + "/query?page=" + page + "&perPage=18&series_type=Comic&order=desc&orderBy=" + orderBy + "&adult=true";
    const res = await new Client().get(url, this._headers());
    return this._mapList(res.body);
  }

  async getPopular(page) { return await this._query("total_views", page); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return await this._query("latest", page); }

  async search(query, page, filters) {
    const url = this.apiBase + "/query?page=" + page + "&perPage=18&series_type=Comic&query_string=" + encodeURIComponent(query) + "&adult=true";
    const res = await new Client().get(url, this._headers());
    return this._mapList(res.body);
  }

  _slug(url) {
    const m = url.match(/\/series\/([^\/?#]+)/);
    if (m) return m[1];
    return url.replace(/\/+$/, "").split("/").pop();
  }

  async getDetail(url) {
    const slug = this._slug(url);
    const res = await new Client().get(this.apiBase + "/series/" + slug, this._headers());
    let d;
    try { d = JSON.parse(res.body); } catch (e) { d = null; }
    if (d && d.data) d = d.data;
    if (!d) return { name: "", link: url, chapters: [] };
    let status = 5;
    const st = (d.status || d.series_status || "").toString().toLowerCase();
    if (st.indexOf("ongoing") >= 0) status = 0;
    else if (st.indexOf("completed") >= 0 || st.indexOf("end") >= 0) status = 1;
    else if (st.indexOf("hiatus") >= 0) status = 2;
    else if (st.indexOf("cancel") >= 0 || st.indexOf("drop") >= 0) status = 3;
    const genre = [];
    for (const t of (d.tags || d.genres || [])) { const n = (t && (t.name || t.title)) || t; if (n) genre.push(n.toString()); }

    // chapters: flat `chapters` OR nested in seasons
    let raw = [];
    if (Array.isArray(d.chapters)) raw = d.chapters;
    for (const se of (d.seasons || [])) { for (const c of (se.chapters || [])) raw.push(c); }
    const chapters = [];
    for (const c of raw) {
      const cslug = (c.chapter_slug || c.slug || "").toString();
      if (!cslug) continue;
      const nm = (c.chapter_name || c.name || c.chapter_title || ("Chapter " + (c.index || ""))).toString();
      chapters.push({ name: nm, url: this.source.baseUrl + "/series/" + slug + "/" + cslug, dateUpload: c.created_at ? String(Date.parse(c.created_at) || "") : "" });
    }
    return { name: (d.title || d.name || "").toString(), imageUrl: this._img(d.thumbnail || d.cover || ""),
      description: (d.description || "").toString(), author: (d.author || "").toString(), genre: genre, status: status, link: url, chapters: chapters };
  }

  async getPageList(url) {
    const parts = url.replace(this.source.baseUrl, "").split("/series/").join("").split("/");
    const slug = parts[0]; const cslug = parts[1] || "";
    const res = await new Client().get(this.apiBase + "/series/" + slug + "/" + cslug, this._headers());
    let d;
    try { d = JSON.parse(res.body); } catch (e) { return []; }
    if (d && d.data) d = d.data;
    const cd = (d && (d.chapter || d)) || {};
    let imgs = [];
    if (cd.chapter_data && Array.isArray(cd.chapter_data.images)) imgs = cd.chapter_data.images;
    else if (Array.isArray(cd.images)) imgs = cd.images;
    else if (Array.isArray(d.images)) imgs = d.images;
    return imgs.map(i => this._img((typeof i === "string") ? i : (i.url || i.src || ""))).filter(x => x);
  }

  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // MMRCMS (My Manga Reader CMS): /filterList browse, JSON /search suggestions,
  // chapters in ul.chapters, pages often in a hidden #arraydata textarea.
  static const String _mmrcmsBody = r'''
  async _list(path, page) {
    const res = await new Client().get(this._abs(path.split("{page}").join(String(page))), this.getHeaders());
    const doc = new Document(res.body);
    const list = [];
    for (const el of this._qa(doc, ".media, .manga-item, .col-sm-6")) {
      const a = this._q1(el, "a.chart-title, .caption h3 a, a.manga-title, h3 a, a[href*='/manga/']");
      if (!a) continue;
      const href = a.getHref;
      const name = a.text.trim();
      if (!href || !name) continue;
      list.push({ name: name, link: this._abs(href), imageUrl: this._img(this._q1(el, "img")) });
    }
    return { list: list, hasNextPage: list.length >= 10 };
  }

  async getPopular(page) { return await this._list("/filterList?page={page}&sortBy=views&asc=false", page); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return await this._list("/latest-release?page={page}", page); }

  async search(query, page, filters) {
    const res = await new Client().get(this._abs("/search?query=" + encodeURIComponent(query)), this.getHeaders());
    try {
      const data = JSON.parse(res.body);
      const list = [];
      for (const s of (data.suggestions || [])) {
        const name = (s.value || "").toString();
        const slug = (s.data || "").toString();
        if (name && slug) list.push({ name: name, link: this._abs("/manga/" + slug), imageUrl: "" });
      }
      return { list: list, hasNextPage: false };
    } catch (e) {
      return await this._list("/filterList?page={page}&sortBy=name&asc=true&alpha=" + encodeURIComponent(query), page);
    }
  }

  async getDetail(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const title = this._q1(doc, "h2.widget-title, h1.widget-title, .widget-title, h1, .listmanga-header");
    const coverEl = this._q1(doc, ".boxed img, img.img-responsive, .thumbnail img");
    const descEl = this._q1(doc, "div[itemprop=description], .well p, .manga-desc, .summary");
    const genre = [];
    for (const g of this._qa(doc, "a[href*='/category/'], .tag-links a, .genres a, [itemprop=genre]")) { const t = g.text.trim(); if (t) genre.push(t); }
    let author = "";
    const authEl = this._q1(doc, "a[href*='/author/'], [itemprop=author]");
    if (authEl) author = authEl.text.trim();
    const chapters = [];
    for (const li of this._qa(doc, "ul.chapters li, .chapters li")) {
      const a = this._q1(li, "h5 a, h3 a, .chapter-title-rtl a, a[href*='/manga/']");
      if (!a) continue;
      const href = a.getHref;
      if (!href) continue;
      let nm = a.text.trim();
      const em = this._q1(li, "em");
      if (em && em.text.trim()) nm = (nm + " " + em.text.trim()).trim();
      chapters.push({ name: nm, url: this._abs(href), dateUpload: "" });
    }
    return { name: title ? title.text.trim() : "", imageUrl: this._img(coverEl),
      description: descEl ? descEl.text.trim() : "", author: author, genre: genre, status: 5, link: this._abs(url), chapters: chapters };
  }

  async getPageList(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const arr = this._q1(doc, "#arraydata");
    if (arr && arr.text.trim()) return arr.text.trim().split(",").map((u) => this._abs(u.trim())).filter((u) => u);
    const pages = [];
    for (const img of this._qa(doc, "#all img, .viewer img, img.img-responsive")) {
      const src = img.getSrc;
      if (src) pages.push(this._abs(src));
    }
    return pages;
  }

  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // Tube/video sites (e.g. xVideos): a listing of `.thumb-block` cards, each a
  // single video; detail = one "Watch" chapter; stream from setVideoUrl* JS.
  // Ported from the working Foxtensions xvideos Dart source.
  static const String _tubeBody = r'''
  _tubePath(tpl, page) {
    let p = (tpl && tpl.length) ? tpl : "/new/{page}";
    p = p.split("{page}").join(String(page - 1)); // tube listings are 0-indexed
    p = p.split("{period}").join("month");
    p = p.split("{query}").join("");
    return p;
  }

  _tubeList(body) {
    const doc = new Document(body);
    const list = [];
    const seen = {};
    for (const el of this._qa(doc, "__ITEM_SEL__")) {
      const a = el.selectFirst("a");
      if (!a) continue;
      const href = a.getHref || "";
      if (href.indexOf("/video") < 0) continue;
      const link = this._abs(href);
      if (seen[link]) continue;
      seen[link] = 1;
      const t = this._q1(el, "__TITLE_SEL__");
      const name = (t ? t.text.trim() : "") || (a.text ? a.text.trim() : "") || "Video";
      list.push({ name: name, link: link, imageUrl: this._img(this._q1(el, "__COVER_SEL__")) });
    }
    return { list: list, hasNextPage: list.length > 0 };
  }

  async getPopular(page) {
    const res = await new Client().get(this.source.baseUrl + this._tubePath("__POPULAR_PATH__", page), this.getHeaders());
    return this._tubeList(res.body);
  }
  get supportsLatest() { return "__LATEST_PATH__".length > 0; }
  async getLatestUpdates(page) {
    const res = await new Client().get(this.source.baseUrl + this._tubePath("__LATEST_PATH__", page), this.getHeaders());
    return this._tubeList(res.body);
  }
  async search(query, page, filters) {
    const p = ("__SEARCH_PATH__" || "/?k={query}")
      .split("{query}").join(encodeURIComponent(query))
      .split("{page}").join(String(page - 1))
      .split("{period}").join("month");
    const res = await new Client().get(this.source.baseUrl + p, this.getHeaders());
    return this._tubeList(res.body);
  }

  async getDetail(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const title = this._q1(doc, "__D_TITLE__");
    const coverEl = this._q1(doc, "__D_COVER__");
    let imageUrl = coverEl ? (coverEl.attr("content") || this._img(coverEl)) : "";
    const genre = [];
    for (const g of this._qa(doc, "__D_GENRE__")) { const t = g.text.trim(); if (t) genre.push(t); }
    return {
      name: title ? title.text.trim() : "Video",
      imageUrl: this._abs(imageUrl),
      description: "",
      author: "",
      genre: genre,
      status: 5,
      link: url,
      chapters: [{ name: "Watch", url: this._abs(url) }],
    };
  }

  async getVideoList(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const body = res.body;
    const videos = [];
    const seen = {};
    const add = (u, q) => {
      if (u && !seen[u]) { seen[u] = 1; videos.push({ url: u, originalUrl: u, quality: q, headers: this.getHeaders() }); }
    };
    let m;
    m = body.match(/setVideoHLS\(['"]([^'"]+)['"]\)/); if (m) add(m[1], "HLS");
    m = body.match(/setVideoUrlHigh\(['"]([^'"]+)['"]\)/); if (m) add(m[1], "High");
    m = body.match(/setVideoUrlLow\(['"]([^'"]+)['"]\)/); if (m) add(m[1], "Low");
    // Generic fallbacks for other tube engines.
    if (videos.length === 0) {
      for (const mm of body.matchAll(/["']([^"']+\.m3u8[^"']*)["']/g)) add(mm[1], "HLS");
      for (const mm of body.matchAll(/["']([^"']+\.mp4[^"']*)["']/g)) add(mm[1], "MP4");
    }
    return videos;
  }

  async getCategories() {
    const res = await new Client().get(this.source.baseUrl + "/tags", this.getHeaders());
    const doc = new Document(res.body);
    const cats = [];
    const seen = {};
    // Select ALL anchors (reliable) and filter to category-ish hrefs in JS —
    // more robust than a CSS attribute selector across engines.
    for (const a of doc.select("a")) {
      const href = a.getHref || "";
      const name = (a.text || "").trim();
      if (!name || name.length > 30) continue;
      if (!/\/(c|tags?|categor(?:y|ies)|genres?|g)\/[^/]/i.test(href)) continue;
      const link = this._abs(href);
      if (seen[link]) continue;
      seen[link] = 1;
      cats.push({ name: name, link: link });
    }
    return cats;
  }

  async getListing(url, page) {
    let u = this._abs(url);
    if (page > 1) u = u.replace(/\/+$/, "") + "/" + (page - 1);
    const res = await new Client().get(u, this.getHeaders());
    return this._tubeList(res.body);
  }

  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // WordPress "Madara" theme (~150 sites). Chapters load via an admin-ajax POST
  // (not inline), pages via ?style=list. Ported from Mangayomi's madara.dart.
  static const String _madaraBody = r'''
  async getPopular(page) {
    const res = await new Client().get(this.source.baseUrl + "__POPULAR_PATH__".split("{page}").join(page), this.getHeaders());
    return this._mList(res.body);
  }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) {
    const res = await new Client().get(this.source.baseUrl + "__LATEST_PATH__".split("{page}").join(page), this.getHeaders());
    return this._mList(res.body);
  }
  async search(query, page, filters) {
    const res = await new Client().get(this.source.baseUrl + "/page/" + page + "/?s=" + encodeURIComponent(query) + "&post_type=wp-manga", this.getHeaders());
    return this._mList(res.body);
  }
  _mList(body) {
    const doc = new Document(body);
    const list = [];
    const seen = {};
    for (const el of this._qa(doc, "__ITEM_SEL__")) {
      const a = this._q1(el, "div.post-title a, h3.h5 a, h3 a") || el.selectFirst("a");
      if (!a) continue;
      const link = this._abs(a.getHref);
      if (!link || seen[link]) continue;
      seen[link] = 1;
      list.push({ name: a.text.trim(), link: link, imageUrl: this._img(el.selectFirst("img")) });
    }
    return { list: list, hasNextPage: list.length > 0 };
  }
  async getDetail(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const genre = [];
    for (const g of this._qa(doc, "div.genres-content a")) { const t = g.text.trim(); if (t) genre.push(t); }
    let chapters = this._mChapters(doc);
    if (chapters.length === 0) chapters = await this._mAjaxChapters(url, doc);
    return {
      name: this._text(this._q1(doc, "div.post-title h1, div.post-title h3, h1")),
      imageUrl: this._img(this._q1(doc, "div.summary_image img")),
      description: this._text(this._q1(doc, "div.summary__content, div.description-summary, div.manga-excerpt, div.summary_content")),
      author: this._text(this._q1(doc, "div.author-content a")),
      genre: genre,
      status: 5,
      link: url,
      chapters: chapters,
    };
  }
  _mChapters(doc) {
    const out = [];
    for (const el of this._qa(doc, "li.wp-manga-chapter")) {
      const a = el.selectFirst("a");
      if (!a) continue;
      out.push({ name: a.text.trim(), url: this._abs(a.getHref), dateUpload: "" });
    }
    return out;
  }
  async _mAjaxChapters(url, doc) {
    let body = "";
    const holder = doc.selectFirst("div[id^='manga-chapters-holder']");
    const mangaId = holder ? holder.attr("data-id") : "";
    const hdr = { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "X-Requested-With": "XMLHttpRequest", "Referer": this.source.baseUrl + "/" };
    if (mangaId) {
      try {
        const res = await new Client().post(this.source.baseUrl + "/wp-admin/admin-ajax.php", hdr, "action=manga_get_chapters&manga=" + mangaId);
        body = res.body || "";
      } catch (e) {}
    }
    if (body.indexOf("wp-manga-chapter") < 0) {
      try {
        const u = this._abs(url).replace(/\/+$/, "") + "/ajax/chapters";
        const res2 = await new Client().post(u, hdr, "");
        body = res2.body || "";
      } catch (e) {}
    }
    const out = [];
    if (body) {
      const cdoc = new Document(body);
      for (const el of this._qa(cdoc, "li.wp-manga-chapter")) {
        const a = el.selectFirst("a");
        if (!a) continue;
        out.push({ name: a.text.trim(), url: this._abs(a.getHref), dateUpload: "" });
      }
    }
    return out;
  }
  async getPageList(url) {
    let u = this._abs(url).split("?style=paged").join("");
    const sep = u.indexOf("?") >= 0 ? "&" : "?";
    const res = await new Client().get(u + sep + "style=list", this.getHeaders());
    const doc = new Document(res.body);
    const pages = [];
    for (const img of this._qa(doc, "div.page-break img, li.blocks-gallery-item img, div.reading-content img")) {
      const src = (img.attr("data-src") || img.attr("data-lazy-src") || img.getSrc || "").trim();
      if (src) pages.push(this._abs(src));
    }
    return pages;
  }
  async getHtmlContent(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const el = this._q1(doc, "div.reading-content, div.text-left, div.text-right, div.entry-content, .chapter-content, #chapter-content");
    return el ? el.innerHtml : "";
  }
  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // Light novel: HTML listing (framework selectors + KB) but chapters are text,
  // returned via getHtmlContent (the chapter's content div's inner HTML).
  static const String _novelBody = r'''
  async _list(pathTemplate, page) {
    const url = this.source.baseUrl + pathTemplate.split("{page}").join(page);
    const res = await new Client().get(url, this.getHeaders());
    const doc = new Document(res.body);
    const list = [];
    const seen = {};
    for (const el of this._qa(doc, "__ITEM_SEL__")) {
      const a = this._q1(el, "__TITLE_SEL__") || el.selectFirst("a");
      if (!a) continue;
      const link = this._abs(a.getHref);
      if (!link || seen[link]) continue;
      seen[link] = 1;
      list.push({ name: a.text.trim(), link: link, imageUrl: this._img(this._q1(el, "__COVER_SEL__")) });
    }
    return { list: list, hasNextPage: list.length > 0 };
  }
  async getPopular(page) { return await this._list("__POPULAR_PATH__", page); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return await this._list("__LATEST_PATH__", page); }
  async search(query, page, filters) {
    return await this._list("__SEARCH_PATH__".split("{query}").join(encodeURIComponent(query)), page);
  }
  async getDetail(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const genre = [];
    for (const g of this._qa(doc, "__D_GENRE__")) { const t = g.text.trim(); if (t) genre.push(t); }
    const chapters = [];
    for (const el of this._qa(doc, "__CH_LIST__")) {
      const a = this._q1(el, "__CH_NAME__") || el.selectFirst("a");
      if (!a) continue;
      chapters.push({ name: a.text.trim(), url: this._abs(a.getHref), dateUpload: "" });
    }
    return {
      name: this._text(this._q1(doc, "__D_TITLE__")),
      imageUrl: this._img(this._q1(doc, "__D_COVER__")),
      description: this._text(this._q1(doc, "__D_DESC__")),
      author: this._text(this._q1(doc, "__D_AUTHOR__")),
      genre: genre,
      status: 5,
      link: url,
      chapters: chapters,
    };
  }
  async getPageList(url) { return []; }
  async getHtmlContent(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const el = this._q1(doc, "div.reading-content, div.text-left, div.entry-content, #chapter-content, .chapter-content, .chapter-c, #chr-content, #novel-content, .chapter-inner, .text_story, .prose, .txt, .reader-content, .epcontent, #article, article");
    return el ? el.innerHtml : "";
  }
  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // FlameComics + clones: Next.js `_next/data/{buildId}/…json`. Ports the
  // Foxtensions flamecomics Dart source (validated live against flamecomics.xyz).
  static const String _flameBody = r'''
  async _bid() {
    if (this.__bid) return this.__bid;
    const res = await new Client().get(this.source.baseUrl, this.getHeaders());
    const m = (res.body || "").match(/"buildId":"([^"]+)"/);
    this.__bid = m ? m[1] : "";
    return this.__bid;
  }
  get _cdn() {
    const base = this.source.baseUrl.replace(/\/+$/, "");
    const mm = base.match(/^(https?:\/\/)(?:www\.)?(.+)$/);
    return mm ? (mm[1] + "cdn." + mm[2]) : base;
  }
  async _data(path) {
    const bid = await this._bid();
    const res = await new Client().get(this.source.baseUrl + "/_next/data/" + bid + "/" + path, this.getHeaders());
    try { return JSON.parse(res.body); } catch (e) { return {}; }
  }
  _seriesList(pp) {
    const arr = pp.series || pp.latestEntries || pp.popularEntries || pp.entries || pp.data || [];
    const list = [];
    for (const s of arr) {
      if (!s || !s.title) continue;
      const id = s.series_id;
      list.push({
        name: String(s.title),
        link: this.source.baseUrl + "/series/" + id,
        imageUrl: s.cover ? (this._cdn + "/uploads/images/series/" + id + "/" + s.cover) : "",
      });
    }
    return { list: list, hasNextPage: list.length >= 20 };
  }
  async getPopular(page) { return this._seriesList((await this._data("browse.json?page=" + page)).pageProps || {}); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return this._seriesList((await this._data("index.json")).pageProps || {}); }
  async search(query, page, filters) {
    return this._seriesList((await this._data("browse.json?search=" + encodeURIComponent(query) + "&page=" + page)).pageProps || {});
  }
  async getDetail(url) {
    const id = url.replace(/\/+$/, "").split("/").pop();
    const pp = (await this._data("series/" + id + ".json")).pageProps || {};
    const s = pp.series || {};
    const genre = Array.isArray(s.categories) ? s.categories.map((c) => String((c && c.name) ? c.name : c)) : [];
    const chapters = [];
    for (const c of (pp.chapters || [])) {
      chapters.push({
        name: "Chapter " + c.chapter + ((c.title && c.title !== "null") ? (": " + c.title) : ""),
        url: this.source.baseUrl + "/series/" + id + "/" + c.token,
        dateUpload: c.release_date ? String(c.release_date * 1000) : "",
      });
    }
    return {
      name: String(s.title || ""),
      imageUrl: s.cover ? (this._cdn + "/uploads/images/series/" + id + "/" + s.cover) : "",
      description: String(s.description || ""),
      author: String(s.author || ""),
      genre: genre,
      status: 5,
      link: url,
      chapters: chapters,
    };
  }
  async getPageList(url) {
    const parts = url.replace(/\/+$/, "").split("/");
    const token = parts.pop();
    const sid = parts.pop();
    const pp = (await this._data("series/" + sid + "/" + token + ".json")).pageProps || {};
    const ch = pp.chapter || {};
    const imgs = ch.images || {};
    const pages = [];
    const keys = Object.keys(imgs).sort((a, b) => parseInt(a) - parseInt(b));
    const cid = ch.series_id || sid;
    const ctok = ch.token || token;
    for (const k of keys) {
      const im = imgs[k];
      const name = (im && im.name) ? im.name : (typeof im === "string" ? im : "");
      if (name) pages.push(this._cdn + "/uploads/images/series/" + cid + "/" + ctok + "/" + name);
    }
    return pages;
  }
  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  // MangaThemesia / WPMangaStream (~95 sites). Reader pages arrive as a JSON
  // ts_reader blob. Ported from Mangayomi's mangareader.dart.
  static const String _mangaThemesiaBody = r'''
  async getPopular(page) {
    const res = await new Client().get(this.source.baseUrl + "__POPULAR_PATH__".split("{page}").join(page), this.getHeaders());
    return this._tsList(res.body);
  }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) {
    const res = await new Client().get(this.source.baseUrl + "__LATEST_PATH__".split("{page}").join(page), this.getHeaders());
    return this._tsList(res.body);
  }
  async search(query, page, filters) {
    const res = await new Client().get(this.source.baseUrl + "/page/" + page + "/?s=" + encodeURIComponent(query), this.getHeaders());
    return this._tsList(res.body);
  }
  _tsList(body) {
    const doc = new Document(body);
    const list = [];
    const seen = {};
    for (const el of this._qa(doc, "__ITEM_SEL__")) {
      const a = el.selectFirst("a");
      if (!a) continue;
      const link = this._abs(a.getHref);
      if (!link || seen[link]) continue;
      seen[link] = 1;
      const name = (a.attr("title") || "").trim() || this._text(this._q1(el, "div.tt, .tt")) || a.text.trim();
      list.push({ name: name, link: link, imageUrl: this._img(el.selectFirst("img")) });
    }
    return { list: list, hasNextPage: list.length > 0 };
  }
  async getDetail(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const genre = [];
    for (const g of this._qa(doc, "span.mgen a, div.gnr a, .seriestugenre a")) { const t = g.text.trim(); if (t) genre.push(t); }
    const chapters = [];
    for (const el of this._qa(doc, "#chapterlist li, div.bxcl li, div.cl li, ul.clstyle li")) {
      const a = el.selectFirst("a");
      if (!a) continue;
      const nm = this._text(this._q1(el, "span.chapternum, .lch a")) || a.text.trim();
      chapters.push({ name: nm, url: this._abs(a.getHref), dateUpload: "" });
    }
    return {
      name: this._text(this._q1(doc, "h1.entry-title, .entry-title")),
      imageUrl: this._img(this._q1(doc, "div.thumb img, .thumb img")),
      description: this._text(this._q1(doc, "div.entry-content, .desc")),
      author: "",
      genre: genre,
      status: 5,
      link: url,
      chapters: chapters,
    };
  }
  async getPageList(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const body = res.body;
    const pages = [];
    const m = body.match(/"images"\s*:\s*(\[[\s\S]*?\])/);
    if (m) {
      try {
        const arr = JSON.parse(m[1]);
        for (const s of arr) { if (s) pages.push(this._abs(String(s).split("\\/").join("/"))); }
      } catch (e) {}
    }
    if (pages.length === 0) {
      const doc = new Document(body);
      for (const img of this._qa(doc, "#readerarea img, div.reading-content img, .rdminimal img")) {
        const src = (img.attr("data-src") || img.attr("data-lazy-src") || img.getSrc || "").trim();
        if (src) pages.push(this._abs(src));
      }
    }
    return pages;
  }
  async getHtmlContent(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const el = this._q1(doc, "#readerarea, .epcontent, .entry-content, div.text-left, div.reading-content, .chapter-content");
    return el ? el.innerHtml : "";
  }
  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';

  static const String _mangaBody = r'''
  async _list(pathTemplate, page) {
    const url = this.source.baseUrl + pathTemplate.split("{page}").join(page);
    const res = await new Client().get(url, this.getHeaders());
    const doc = new Document(res.body);
    const list = [];
    for (const el of this._qa(doc, "__ITEM_SEL__")) {
      const a = this._q1(el, "__TITLE_SEL__");
      const img = this._q1(el, "__COVER_SEL__");
      const name = a ? a.text.trim() : this._text(el.selectFirst("a"));
      const link = a ? a.getHref : (el.selectFirst("a") ? el.selectFirst("a").getHref : "");
      if (!link) continue;
      list.push({ name: name, link: this._abs(link), imageUrl: this._img(img) });
    }
    const hasNextPage = "__NEXT_SEL__".length > 0
      ? this._q1(doc, "__NEXT_SEL__") != null
      : list.length > 0;
    return { list, hasNextPage };
  }

  async getPopular(page) { return await this._list("__POPULAR_PATH__", page); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return await this._list("__LATEST_PATH__", page); }

  async search(query, page, filters) {
    if (filters && filters.length && filters[0] && filters[0].state > 0) {
      const cat = filters[0].values[filters[0].state].value;
      if (cat) return await this._list(cat, page);
    }
    const path = "__SEARCH_PATH__".split("{query}").join(encodeURIComponent(query));
    return await this._list(path, page);
  }

  // OpenGraph/meta fallback: near-universal on content sites, so custom sites
  // still get a title/cover/description even when no CSS selector matches.
  _meta(doc, props) {
    for (const p of props) {
      let el = doc.selectFirst("meta[property='" + p + "']");
      if (!el) el = doc.selectFirst("meta[name='" + p + "']");
      if (el) { const c = el.attr("content"); if (c && c.trim()) return c.trim(); }
    }
    return "";
  }

  _statusFrom(doc) {
    const el = this._q1(doc, ".status, .imptdt, [class*='status'], .post-status");
    const t = ((el ? el.text : "") || "").toLowerCase();
    if (t.indexOf("ongoing") >= 0 || t.indexOf("publishing") >= 0) return 0;
    if (t.indexOf("completed") >= 0 || t.indexOf("finished") >= 0 || t.indexOf("end") >= 0) return 1;
    if (t.indexOf("hiatus") >= 0) return 2;
    if (t.indexOf("cancel") >= 0 || t.indexOf("dropped") >= 0) return 3;
    return 5;
  }

  async getDetail(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const genre = [];
    for (const g of this._qa(doc, "__D_GENRE__, a[href*='/genre/'], a[href*='/genres/'], a[href*='/category/'], a[rel='tag']")) {
      const t = g.text.trim();
      if (t && t.length < 30 && genre.indexOf(t) < 0) genre.push(t);
    }
    const chapters = [];
    for (const el of this._qa(doc, "__CH_LIST__")) {
      const a = this._q1(el, "__CH_NAME__") || el.selectFirst("a");
      if (!a) continue;
      chapters.push({ name: a.text.trim(), url: this._abs(a.getHref) });
    }
    let name = this._text(this._q1(doc, "__D_TITLE__"));
    if (!name) name = this._meta(doc, ["og:title", "twitter:title"]);
    if (!name) { const h1 = doc.selectFirst("h1"); if (h1) name = h1.text.trim(); }
    // og:image is the most reliable cover for bespoke sites; the generic "img"
    // fallback often grabs a logo, so prefer meta first here.
    let cover = this._abs(this._meta(doc, ["og:image", "twitter:image", "twitter:image:src"]));
    if (!cover) cover = this._img(this._q1(doc, ".thumb img, .cover img, .summary_image img, [class*='cover'] img, [class*='thumb'] img, __D_COVER__"));
    let desc = this._text(this._q1(doc, "__D_DESC__"));
    if (!desc) desc = this._meta(doc, ["og:description", "description", "twitter:description"]);
    return {
      name: name,
      imageUrl: cover,
      description: desc,
      author: this._text(this._q1(doc, "__D_AUTHOR__, a[href*='/author/'], [itemprop='author']")),
      genre: genre,
      status: this._statusFrom(doc),
      link: this._abs(url),
      chapters: chapters,
    };
  }

  async getPageList(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const pages = [];
    for (const img of this._qa(doc, "__PAGE_IMG__")) {
      const a = img.attr("__PAGE_ATTR__");
      const src = a && a.length ? a : img.getSrc;
      if (src) pages.push(this._abs(src));
    }
    return pages;
  }

  getFilterList() { return __FILTERS__; }
  getSourcePreferences() { return []; }
}
''';

  static const String _animeBody = r'''
  async _list(pathTemplate, page) {
    const url = this.source.baseUrl + pathTemplate.split("{page}").join(page);
    const res = await new Client().get(url, this.getHeaders());
    const doc = new Document(res.body);
    const list = [];
    for (const el of this._qa(doc, "__ITEM_SEL__")) {
      const a = this._q1(el, "__TITLE_SEL__");
      const img = this._q1(el, "__COVER_SEL__");
      const name = a ? a.text.trim() : this._text(el.selectFirst("a"));
      const link = a ? a.getHref : (el.selectFirst("a") ? el.selectFirst("a").getHref : "");
      if (!link) continue;
      list.push({ name: name, link: this._abs(link), imageUrl: this._img(img) });
    }
    const hasNextPage = "__NEXT_SEL__".length > 0
      ? this._q1(doc, "__NEXT_SEL__") != null
      : list.length > 0;
    return { list, hasNextPage };
  }

  async getPopular(page) { return await this._list("__POPULAR_PATH__", page); }
  get supportsLatest() { return true; }
  async getLatestUpdates(page) { return await this._list("__LATEST_PATH__", page); }

  async search(query, page, filters) {
    if (filters && filters.length && filters[0] && filters[0].state > 0) {
      const cat = filters[0].values[filters[0].state].value;
      if (cat) return await this._list(cat, page);
    }
    const path = "__SEARCH_PATH__".split("{query}").join(encodeURIComponent(query));
    return await this._list(path, page);
  }

  async getDetail(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const doc = new Document(res.body);
    const genre = [];
    for (const g of this._qa(doc, "__D_GENRE__")) genre.push(g.text.trim());
    const episodes = [];
    for (const el of this._qa(doc, "__EP_LIST__")) {
      const a = el.selectFirst("__EP_NAME__") || el;
      const href = a.getHref || (el.selectFirst("a") ? el.selectFirst("a").getHref : "");
      if (!href) continue;
      episodes.push({ name: (a.text || "").trim() || "Episode", url: this._abs(href) });
    }
    // Tube / single-video sites: the page itself is the playable item.
    if (episodes.length === 0) episodes.push({ name: "Video", url: this._abs(url) });
    return {
      name: this._text(this._q1(doc, "__D_TITLE__")),
      imageUrl: this._img(this._q1(doc, "__D_COVER__")),
      description: this._text(this._q1(doc, "__D_DESC__")),
      author: this._text(this._q1(doc, "__D_AUTHOR__")),
      genre: genre,
      status: 5,
      link: this._abs(url),
      episodes: episodes,
    };
  }

  async getVideoList(url) {
    const res = await new Client().get(this._abs(url), this.getHeaders());
    const body = res.body;
    const doc = new Document(body);
    const videos = [];
    const seen = {};
    const add = (u, q) => {
      u = this._abs(u);
      if (u && !seen[u]) { seen[u] = 1; videos.push({ url: u, originalUrl: u, quality: q }); }
    };
    // 1. Direct <video>/<source> tags.
    for (const v of doc.select("video source, video[src]")) add(v.attr("src"), "Direct");
    // 2. HLS / MP4 / player URLs embedded in the page's scripts.
    for (const m of body.matchAll(/["']([^"']+\.m3u8[^"']*)["']/g)) add(m[1], "HLS");
    for (const m of body.matchAll(/["']([^"']+\.mp4[^"']*)["']/g)) add(m[1], "MP4");
    for (const m of body.matchAll(/(?:file|source|src)\s*[:=]\s*["']([^"']+\.(?:m3u8|mp4)[^"']*)["']/g)) add(m[1], "Player");
    // 3. KVS player (common on tube sites): deobfuscate flashvars.video_url.
    const kvsLic = (body.match(/license_code\s*[:=]\s*['"]([^'"]+)['"]/) || [])[1];
    for (const m of body.matchAll(/video(?:_alt|_4k)?_url\s*[:=]\s*['"]([^'"]{6,})['"]/g)) {
      let u = m[1];
      if (u.startsWith("function/0/")) {
        if (!kvsLic) continue;
        u = this._kvsRealUrl(u, kvsLic);
        if (u.startsWith("function/0/")) continue; // deobfuscation failed
      }
      add(u, "KVS");
    }
    // 4. Iframe embed: generically resolve by fetching the embed page and
    //    extracting its stream (works for hosts that expose m3u8/mp4 in HTML or
    //    packed JS — filemoon/streamwish/vidhide/streamtape, etc.).
    if (videos.length === 0) {
      const iframe = doc.selectFirst("__VIDEO_IFRAME__") ||
        doc.selectFirst("iframe[src*=embed], iframe[src*=player], iframe[src*=video], iframe");
      const emb = iframe ? this._abs(iframe.attr("src")) : "";
      if (emb) {
        try {
          const r2 = await new Client().get(emb, { "Referer": this.source.baseUrl });
          let b2 = r2.body;
          if (typeof unpackJs === "function" && /eval\(function\(p,a,c,k,e/.test(b2)) {
            try { b2 += "\n" + unpackJs(b2); } catch (e) {}
          }
          for (const m of b2.matchAll(/["']([^"']+\.m3u8[^"']*)["']/g)) add(m[1], "HLS");
          for (const m of b2.matchAll(/["']([^"']+\.mp4[^"']*)["']/g)) add(m[1], "MP4");
        } catch (e) {}
        if (videos.length === 0) add(emb, "Embed"); // last resort: the embed URL
      }
    }
    return videos;
  }

  // KVS deobfuscation (ported from yt-dlp) — recovers the real MP4/HLS URL
  // from an obfuscated `function/0/...` flashvars.video_url.
  _kvsLicenseToken(code) {
    code = code.replace(/\$/g, "");
    const vals = code.split("").map((c) => parseInt(c, 10) || 0);
    let mod = code.replace(/0/g, "1");
    const center = Math.floor(mod.length / 2);
    const front = parseInt(mod.slice(0, center + 1), 10);
    const back = parseInt(mod.slice(center), 10);
    mod = String(4 * Math.abs(front - back)).slice(0, center + 1);
    const token = [];
    for (let i = 0; i < mod.length; i++) {
      const cur = parseInt(mod[i], 10);
      for (let o = 0; o < 4; o++) token.push(((vals[i + o] || 0) + cur) % 10);
    }
    return token;
  }

  _kvsRealUrl(videoUrl, licenseCode) {
    if (!videoUrl || !videoUrl.startsWith("function/0/")) return videoUrl;
    const rest = videoUrl.slice(11);
    const qi = rest.search(/[?#]/);
    const head = qi >= 0 ? rest.slice(0, qi) : rest;
    const tail = qi >= 0 ? rest.slice(qi) : "";
    const m = head.match(/^(https?:\/\/[^/]+)(\/.*)$/);
    if (!m) return videoUrl;
    const parts = m[2].split("/");
    if (parts.length < 4) return videoUrl;
    const token = this._kvsLicenseToken(licenseCode);
    const HL = 32;
    if (token.length < HL) return videoUrl;
    const seg = parts[3];
    if (seg.length < HL) return videoUrl;
    const hash = seg.slice(0, HL);
    const idx = [];
    for (let i = 0; i < HL; i++) idx.push(i);
    let accum = 0;
    for (let src = HL - 1; src >= 0; src--) {
      accum += token[src] || 0;
      const dest = (src + accum) % HL;
      const t = idx[src]; idx[src] = idx[dest]; idx[dest] = t;
    }
    let nh = "";
    for (const i of idx) nh += hash[i];
    parts[3] = nh + seg.slice(HL);
    return m[1] + parts.join("/") + tail;
  }

  getFilterList() { return __FILTERS__; }
  getSourcePreferences() { return []; }
}
''';
}

// ── Intermediate representation ────────────────────────────────────────────

class _Spec {
  final String name;
  final String baseUrl;
  final String lang;
  final String framework;
  final int itemType; // 0 manga, 1 anime, 2 novel
  final bool isNsfw;
  final bool hasCloudflare;
  final String version;
  final _Selectors selectors;
  final List<Map<String, String>> categories;
  final String apiBase;

  _Spec({
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.framework,
    required this.itemType,
    required this.isNsfw,
    required this.hasCloudflare,
    required this.version,
    required this.selectors,
    required this.categories,
    this.apiBase = '',
  });

  /// Frameworks whose sources should be generated as JSON-API (not HTML).
  /// Add new API frameworks here + a body in [_apiBodyFor].
  static const Set<String> _apiFrameworks = {
    'KeyoApp', 'MangaDex', 'HeanCMS',
    // lib-multisrc API/GraphQL/tRPC backends (build 25). Each hits a JSON API
    // rather than scraping HTML; they route through the generic API body with
    // the catalog endpoints the detector emits. Best-effort until on-device
    // validation — the response schemas vary and may need per-framework tuning.
    'LibGroup API', 'MangaHub API', 'Iken API', 'MangAdventure', 'MonochromeCMS',
    'PizzaReader', 'MCCMS', 'GreenShit API', 'MangoTheme API', 'SpicyTheme API',
    'EZManhwa API', 'Senkuro', 'Hiper (tRPC)', 'HotNovelPub API', 'Rulate API',
    'NovelCool API', 'UzayManga',
  };
  bool get isApiFramework => _apiFrameworks.contains(framework);

  /// Tube/video frameworks: one video per page, listing of `.thumb-block`
  /// cards, stream in a `setVideoUrl*` JS call. Generated with [_tubeBody].
  static const Set<String> _tubeFrameworks = {
    'xVideos Engine',
    'xHamster Engine',
    'ClipBucket',
    'PHPMotion',
    'KVS',
    'WP Ultimate Clips',
    'Generic Video Host',
  };
  bool get isTubeFramework => _tubeFrameworks.contains(framework);

  bool get isAnime => itemType == 1;
  String get itemFolder => isAnime ? 'anime' : (itemType == 2 ? 'novel' : 'manga');
  String get iconUrl => '$baseUrl/favicon.ico';
  String get notes =>
      'Generated by RepoForge from $framework. Host this .js and set '
      'sourceCodeUrl to its raw URL, then add the index.json as a repo.';

  String get fileBase {
    final b = name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    return b.isEmpty ? 'source' : b;
  }

  /// Stable id matching Mangayomi's convention for JS sources.
  int get id => 'mangayomi-js-"$lang"."$name"'.hashCode;

  factory _Spec.fromMap(Map<String, dynamic> m) {
    var framework = m['framework'] as String? ?? 'Custom';
    // Most generic WordPress manga sites are Madara — treat them as such.
    if (framework == 'WordPress (Generic)' || framework == 'WordPress') {
      framework = 'Madara';
    }
    final ct = (m['contentType'] as String? ?? 'manga').toLowerCase();
    // Tube frameworks are always video (anime) so the app opens the player.
    final itemType = _tubeFrameworks.contains(framework)
        ? 1
        : ct == 'anime'
            ? 1
            : ct == 'novel' || ct == 'light novel'
                ? 2
                : 0;
    final baseUrl = (m['sourceUrl'] as String? ?? '').trim();
    return _Spec(
      name: (m['name'] as String? ?? 'Source').trim(),
      baseUrl: baseUrl.isEmpty ? 'https://example.com' : baseUrl,
      lang: (m['language'] as String? ?? 'en').toLowerCase(),
      framework: framework,
      itemType: itemType,
      isNsfw: m['nsfw'] as bool? ?? false,
      hasCloudflare: (m['confidence'] as int? ?? 100) < 70 || framework == 'Custom',
      version: m['version'] as String? ?? '1.0.0',
      selectors: _Selectors.forSpec(m, framework, itemType),
      categories: _categoriesFrom(m['categories']),
      // Detected API base if the detector provided one; else the JS derives
      // api.<host> from baseUrl at runtime.
      apiBase: (m['apiUrl'] as String? ?? m['apiBase'] as String? ?? '').trim(),
    );
  }

  static List<Map<String, String>> _categoriesFrom(dynamic v) {
    if (v is! List) return const [];
    final out = <Map<String, String>>[];
    for (final e in v) {
      if (e is Map && e['name'] != null && e['path'] != null) {
        out.add({'name': e['name'].toString(), 'path': e['path'].toString()});
      }
    }
    return out.take(40).toList();
  }
}

class _Selectors {
  final String popularPath, latestPath, searchPath;
  final String item, title, cover, coverAttr, nextPage;
  final String detailTitle, detailCover, detailDesc, detailAuthor, detailGenre;
  final String chapterList, chapterName;
  final String pageImages, pageImageAttr;
  final String episodeList, episodeName, videoIframe;

  const _Selectors({
    required this.popularPath,
    required this.latestPath,
    required this.searchPath,
    required this.item,
    required this.title,
    required this.cover,
    required this.coverAttr,
    required this.nextPage,
    required this.detailTitle,
    required this.detailCover,
    required this.detailDesc,
    required this.detailAuthor,
    required this.detailGenre,
    required this.chapterList,
    required this.chapterName,
    required this.pageImages,
    required this.pageImageAttr,
    required this.episodeList,
    required this.episodeName,
    required this.videoIframe,
  });

  /// Build selectors: start from the framework's canonical table, then override
  /// with anything the detector actually extracted (endpoints + selector maps).
  factory _Selectors.forSpec(
    Map<String, dynamic> m,
    String framework,
    int itemType,
  ) {
    final base = _canonical[framework] ??
        (_Spec._tubeFrameworks.contains(framework)
            ? _canonical['__tube__']!
            : (itemType == 1
                ? _canonical['__anime__']!
                : _canonical['__default__']!));

    // Detected endpoint overrides (popular/latest/search paths).
    var popular = base.popularPath, latest = base.latestPath, search = base.searchPath;
    final endpoints = (m['endpoints'] as List?) ?? const [];
    for (final e in endpoints) {
      if (e is! Map) continue;
      final n = (e['name'] as String? ?? '').toLowerCase();
      final p = (e['path'] as String? ?? '').trim();
      if (p.isEmpty) continue;
      if (n.contains('popular')) popular = p;
      if (n.contains('latest')) latest = p;
      if (n.contains('search')) search = p;
    }

    // Novel-configured lightnovelwp sites browse their /series/ archive rather
    // than the MangaThemesia /manga/ one (reference: LNReader lightnovelwp
    // template). Madara novels keep the /manga/ archive path — Madara serves
    // novels under the same wp-manga post type, so the manga archive lists them.
    final isThemesiaNovel = itemType == 2 &&
        (framework == 'MangaThemesia' || framework == 'MangaStream');
    if (isThemesiaNovel) {
      popular = '/series/?page={page}&order=popular';
      latest = '/series/?page={page}&order=update';
      search = '/page/{page}/?s={query}';
    }

    // Detected selector overrides.
    final sel = _strMap(m['selectors']);
    final img = _strMap(m['imageSelectors']);
    final vid = _strMap(m['videoSelectors']);

    // lightnovelwp's /series/ archive lists novels as `article.maindet` (some
    // themes use `.utao .uta`) — prepend those so novel browsing matches.
    var itemSel = sel['popular'] ?? sel['item'] ?? base.item;
    if (isThemesiaNovel) {
      itemSel = 'article.maindet, .utao .uta, .listupd .bsx, $itemSel';
    }

    return _Selectors(
      popularPath: popular,
      latestPath: latest,
      searchPath: search,
      item: '$itemSel, ${MangayomiJsGenerator._kbItem}',
      title: sel['title'] ?? base.title,
      cover: sel['cover'] ?? base.cover,
      coverAttr: img['lazyAttr'] ?? base.coverAttr,
      nextPage: sel['nextPage'] ?? base.nextPage,
      detailTitle: sel['detailTitle'] ?? base.detailTitle,
      detailCover: img['cover'] ?? base.detailCover,
      detailDesc: base.detailDesc,
      detailAuthor: base.detailAuthor,
      detailGenre: base.detailGenre,
      chapterList:
          '${sel['chapters'] ?? base.chapterList}, ${MangayomiJsGenerator._kbChapters}',
      chapterName: base.chapterName,
      pageImages:
          '${sel['page_images'] ?? img['chapterImages'] ?? base.pageImages}, ${MangayomiJsGenerator._kbPages}',
      pageImageAttr: img['lazyAttr'] ?? base.pageImageAttr,
      episodeList: sel['episodes'] ?? base.episodeList,
      episodeName: base.episodeName,
      videoIframe: vid['iframe'] ?? base.videoIframe,
    );
  }

  static Map<String, String> _strMap(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val.toString()));
    }
    return const {};
  }
}

/// Canonical CSS selectors per framework, distilled from the community
/// multisrc parsers (Madara, MangaThemesia, MangaBox, MMRCMS, Zorotheme).
const Map<String, _Selectors> _canonical = {
  'Madara': _Selectors(
    popularPath: '/manga/page/{page}/?m_orderby=views',
    latestPath: '/manga/page/{page}/?m_orderby=latest',
    searchPath: '/?s={query}&post_type=wp-manga',
    item: 'div.page-item-detail, div.manga__item',
    title: 'h3.h5 a, .post-title a, h3 a',
    cover: 'img',
    coverAttr: 'data-src',
    nextPage: '.wp-pagenavi a.nextpostslink, a.next.page-numbers',
    detailTitle: 'div.post-title h1',
    detailCover: 'div.summary_image img',
    detailDesc: 'div.summary__content, div.description-summary div.summary__content',
    detailAuthor: 'div.author-content a',
    detailGenre: 'div.genres-content a',
    chapterList: 'li.wp-manga-chapter',
    chapterName: 'a',
    pageImages: 'div.reading-content img',
    pageImageAttr: 'data-src',
    episodeList: '',
    episodeName: 'a',
    videoIframe: '',
  ),
  'MangaStream': _mangaThemesia,
  'MangaThemesia': _mangaThemesia,
  'MMRCMS': _Selectors(
    popularPath: '/filterList?page={page}&sortBy=views&asc=false',
    latestPath: '/latest-release?page={page}',
    searchPath: '/search?query={query}',
    item: 'div.mangalist div.manga-item, div.media',
    title: 'h3 a, .media-heading a, .manga-heading a',
    cover: 'img',
    coverAttr: 'data-src',
    nextPage: 'ul.pagination a[rel=next], li.next a',
    detailTitle: 'h1.listmanga-header, h2.widget-title, .panel-heading',
    detailCover: 'img.img-responsive',
    detailDesc: 'div.well p, .manga-info p',
    detailAuthor: 'a[href*=author], .dl-horizontal dd',
    detailGenre: 'a[href*=category], .dl-horizontal a',
    chapterList: 'ul.chapters > li:not(.btn)',
    chapterName: '.chapter-title-rtl a, h5 a, a',
    pageImages: '#all img.img-responsive',
    pageImageAttr: 'data-src',
    episodeList: '',
    episodeName: 'a',
    videoIframe: '',
  ),
  'MangaBox': _Selectors(
    popularPath: '/manga-list/hot-manga?page={page}',
    latestPath: '/manga-list/latest-manga?page={page}',
    searchPath: '/search/story/{query}',
    item: '.list-truyen-item-wrap, .content-genres-item, .story_item, .list-story-item',
    title: 'h3 a, a.item-title, .story_name a',
    cover: 'img',
    coverAttr: 'src',
    nextPage: '.panel_page_number .go-p-end, a.page-select ~ a.page-blue',
    detailTitle: '.manga-info-text h1, .story-info-right h1, h1',
    detailCover: '.manga-info-pic img, .info-image img, .story-info-left img',
    detailDesc: '#panel-story-info-description, #contentBox, .panel-story-info-description',
    detailAuthor: '.manga-info-text li:contains(author) a, td:contains(Author) + td a',
    detailGenre: '.manga-info-text li.genres a, td:contains(Genres) + td a',
    chapterList: '.chapter-list .row, ul.row-content-chapter li',
    chapterName: 'a',
    pageImages: '.container-chapter-reader img',
    pageImageAttr: 'src',
    episodeList: '',
    episodeName: 'a',
    videoIframe: '',
  ),
  'Zorotheme (Anime)': _Selectors(
    popularPath: '/most-popular?page={page}',
    latestPath: '/recently-updated?page={page}',
    searchPath: '/search?keyword={query}&page={page}',
    item: 'div.flw-item',
    title: 'h3.film-name a, .dynamic-name',
    cover: 'img.film-poster-img',
    coverAttr: 'data-src',
    nextPage: 'li.page-item a[title=Next], .pagination .active + li a',
    detailTitle: 'h2.film-name, .anisc-detail .film-name',
    detailCover: 'div.film-poster img, .anisc-poster img',
    detailDesc: 'div.film-description, .anisc-detail .text',
    detailAuthor: 'div.item-title:contains(Studios) a, .item:contains(Producers) a',
    detailGenre: 'div.item-list a, .sy_detail .scd-genres a',
    chapterList: '',
    chapterName: 'a',
    pageImages: '',
    pageImageAttr: 'data-src',
    episodeList: 'a.ep-item, .ss-list a',
    episodeName: 'a',
    videoIframe: 'iframe#iframe-embed, div.player-embed iframe',
  ),
  '__default__': _Selectors(
    popularPath: '/?page={page}',
    latestPath: '/latest?page={page}',
    searchPath: '/?s={query}',
    item: 'article, div.item, li.item, .post',
    title: 'a',
    cover: 'img',
    coverAttr: 'data-src',
    nextPage: 'a[rel=next], a.next, li.next a',
    detailTitle: 'h1',
    detailCover: 'img',
    detailDesc: 'div.description, div.summary, meta[name=description]',
    detailAuthor: 'a[href*=author]',
    detailGenre: 'a[href*=genre], a[href*=category]',
    chapterList: 'li a[href*=chapter], a[href*=chapter]',
    chapterName: 'a',
    pageImages: 'div.reader img, div.content img, img',
    pageImageAttr: 'data-src',
    episodeList: '',
    episodeName: 'a',
    videoIframe: 'iframe',
  ),
  '__anime__': _Selectors(
    popularPath: '/popular?page={page}',
    latestPath: '/recent?page={page}',
    searchPath: '/search?keyword={query}&page={page}',
    item: 'div.item, article, li.item, .flw-item',
    title: 'a',
    cover: 'img',
    coverAttr: 'data-src',
    nextPage: 'a[rel=next], a.next, li.next a',
    detailTitle: 'h1',
    detailCover: 'img',
    detailDesc: 'div.description, div.synopsis, meta[name=description]',
    detailAuthor: 'a[href*=studio]',
    detailGenre: 'a[href*=genre]',
    chapterList: '',
    chapterName: 'a',
    pageImages: '',
    pageImageAttr: 'data-src',
    episodeList: 'a[href*=episode], .episodes a, ul.episodes a',
    episodeName: 'a',
    videoIframe: 'iframe',
  ),
  // Tube/video sites (xVideos & similar KVS engines).
  '__tube__': _Selectors(
    popularPath: '/?p={page}',
    latestPath: '/new/{page}',
    searchPath: '/?k={query}&p={page}',
    item: '.thumb-block, .mozaique .thumb, div.video-block, .video-item',
    title: 'p.title a, .thumb-under p a, .title a',
    cover: 'img',
    coverAttr: 'data-src',
    nextPage: 'a.next-page, .pagination a.no-page',
    detailTitle: 'h2.page-title, #video-title, h1',
    detailCover: 'meta[property="og:image"]',
    detailDesc: '',
    detailAuthor: '',
    detailGenre: '.video-tags-list a, .tags a, .video-metadata a[href*=tags]',
    chapterList: '',
    chapterName: '',
    pageImages: '',
    pageImageAttr: 'data-src',
    episodeList: '',
    episodeName: '',
    videoIframe: 'iframe',
  ),
};

/// MangaThemesia / MangaStream / (Mangayomi "mangareader") shared table.
const _Selectors _mangaThemesia = _Selectors(
  popularPath: '/manga/?page={page}&order=popular',
  latestPath: '/manga/?page={page}&order=update',
  searchPath: '/page/{page}/?s={query}',
  item: '.utao .uta .imgu, .listupd .bs .bsx, .listo .bs .bsx',
  title: 'a',
  cover: 'img',
  coverAttr: 'data-src',
  nextPage: 'a.r, .hpage a.r, div.pagination a.next',
  detailTitle: 'h1.entry-title',
  detailCover: '.thumb img, .infomanga > div[itemprop=image] img',
  detailDesc: '.desc, .entry-content[itemprop=description]',
  detailAuthor: '.infotable td:contains(Author) + td, .fmed b:contains(Author) + span',
  detailGenre: 'div.gnr a, .mgen a, .seriestugenre a',
  chapterList: 'div.bxcl li, div.cl li, #chapterlist li',
  chapterName: '.lch a, .chapternum',
  pageImages: 'div#readerarea img',
  pageImageAttr: 'data-src',
  episodeList: '',
  episodeName: 'a',
  videoIframe: '',
);
