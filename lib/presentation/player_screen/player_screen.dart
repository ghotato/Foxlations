import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/models/player_settings.dart';
import '../../eval/model/m_video.dart';
import '../../eval/lib.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/services/app_logger.dart';

class PlayerScreen extends StatefulWidget {
  final String sourceId;
  final String episodeUrl;
  final String? episodeTitle;
  final String? animeTitle;

  /// The anime's library url. Needed to persist/restore playback position
  /// (episodes are stored as chapters). Null → progress isn't tracked.
  final String? mangaUrl;

  /// The full episode list ({url, name}, in the detail screen's order) and this
  /// episode's index in it, enabling in-player Next/Previous + autoplay. Null → single.
  final List<Map<String, dynamic>>? episodes;
  final int currentIndex;

  const PlayerScreen({
    super.key,
    required this.sourceId,
    required this.episodeUrl,
    this.episodeTitle,
    this.animeTitle,
    this.mangaUrl,
    this.episodes,
    this.currentIndex = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final FocusNode _focus = FocusNode();

  List<MVideo> _videos = [];
  int _currentVideoIndex = 0;

  // Current episode (mutable — Next/Previous swap it in place).
  late List<Map<String, dynamic>> _episodes;
  late int _epIndex;

  bool _isLoading = true;
  String? _error;
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  LibraryProvider? _lib;
  int _resumeSeconds = 0;
  Duration _lastSaved = Duration.zero;
  Duration _seekTarget = Duration.zero;

  PlayerSettings _settings = const PlayerSettings();
  double _speed = 1.0;
  double _subDelay = 0.0; // seconds
  BoxFit _fit = BoxFit.contain;
  bool _locked = false;

  // Skip intro/outro: the current video's markers, plus which one (if any) we're
  // inside right now and which have already been auto-skipped.
  List<MTimeStamp> _stamps = [];
  MTimeStamp? _activeStamp;
  final Set<int> _skipped = {};

  String get _epUrl => (_epIndex >= 0 && _epIndex < _episodes.length)
      ? (_episodes[_epIndex]['url'] as String? ?? widget.episodeUrl)
      : widget.episodeUrl;
  String? get _epTitle => (_epIndex >= 0 && _epIndex < _episodes.length)
      ? (_episodes[_epIndex]['name'] as String?)
      : widget.episodeTitle;
  bool get _hasPrev => _episodes.isNotEmpty && _epIndex > 0;
  bool get _hasNext =>
      _episodes.isNotEmpty && _epIndex >= 0 && _epIndex < _episodes.length - 1;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _episodes = widget.episodes ?? const [];
    _epIndex = widget.currentIndex;
    _lib = context.read<LibraryProvider>();
    _resumeSeconds = _lib?.episodeLastPosition(widget.sourceId, _epUrl) ?? 0;
    WakelockPlus.enable();
    _setupListeners();
    _init();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _init() async {
    final s = await PlayerSettings.load();
    if (mounted) setState(() { _settings = s; _speed = s.defaultSpeed; });
    await _loadVideoList();
  }

  void _setupListeners() {
    _subs.addAll([
      _player.stream.position.listen((pos) {
        _position = pos;
        _maybeSaveProgress(pos);
        _updateSkip(pos);
      }),
      _player.stream.duration.listen((dur) => _duration = dur),
      _player.stream.completed.listen((done) {
        if (done && _settings.autoplayNext && _hasNext) _playEpisode(_epIndex + 1);
      }),
      // Surface libmpv playback errors (bad codec, dead stream url, HLS failure) in the
      // in-app log so player problems are diagnosable, not just a silent stall.
      _player.stream.error.listen((e) {
        logger.error('Player error: $e', category: LogCategory.general);
      }),
    ]);
  }

  Future<void> _loadVideoList() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final sp = context.read<SourceProvider>();
      final installed = sp.getInstalledSource(widget.sourceId);
      if (installed == null) throw Exception('Source not installed');

      final videos = await withExtensionService(
        installed.source,
        installed.sourceCode,
        (service) => service.getVideoList(_epUrl),
      );
      if (videos.isEmpty) throw Exception('No video sources found');

      if (mounted) {
        setState(() {
          _videos = videos;
          _currentVideoIndex = 0;
          _stamps = videos.first.timestamps ?? [];
          _skipped.clear();
          _isLoading = false;
        });
        logger.info('Resume: saved position = ${_resumeSeconds}s for $_epUrl',
            category: LogCategory.general);
        if (_resumeSeconds > 10 && mounted) {
          final resume = await _askResume(_resumeSeconds);
          _seekTarget = resume ? Duration(seconds: _resumeSeconds) : Duration.zero;
        }
        await _openVideo(videos.first);
      }
    } catch (e, st) {
      logger.error('Video load failed: $e',
          category: LogCategory.extension, detail: st.toString());
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _openVideo(MVideo video) async {
    final seekTo = _seekTarget;
    _seekTarget = Duration.zero;
    final resuming = seekTo > Duration.zero;
    // Resume is platform-split: iOS resumes reliably only when opened PLAYING and then
    // sought; Android resumes reliably only when opened PAUSED, sought, then played —
    // seeking during active playback on Android is silently dropped and restarts at 0
    // (opening paused was the pre-rewrite behaviour that worked on Android; the media
    // still demuxes and reports a duration while paused).
    final openPlaying = !resuming || Platform.isIOS;
    await _player.open(Media(video.url, httpHeaders: video.headers ?? {}),
        play: openPlaying);
    await _player.setRate(_speed);
    // Some anime sources return a video-only stream plus a SEPARATE audio track
    // (Aniyomi's ExoPlayer merges these automatically). media_kit opens only the
    // video url, so without attaching the external audio the episode plays silent.
    // A source only populates `audios` when the stream lacks embedded audio, so
    // this is a no-op for normal muxed streams.
    final extAudio = video.audios;
    if (extAudio != null &&
        extAudio.isNotEmpty &&
        (extAudio.first.file?.isNotEmpty ?? false)) {
      await _player.setAudioTrack(
          AudioTrack.uri(extAudio.first.file!, title: extAudio.first.label));
    }
    if (resuming) {
      // Check the already-known duration first (the stream event can fire before we
      // subscribe), otherwise wait for it — a seek before the media is loaded is dropped.
      var dur = _player.state.duration;
      if (dur <= Duration.zero) {
        dur = await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 15), onTimeout: () => Duration.zero);
      }
      if (dur > Duration.zero && seekTo < dur) {
        await _player.seek(seekTo);
        if (!openPlaying) await _player.play(); // Android: start from the seeked point
        await _monitorResume(seekTo); // safety net: re-seek if it slips back to 0
      } else {
        logger.error(
            dur <= Duration.zero
                ? 'Resume seek skipped: media reported no duration'
                : 'Resume seek skipped: target ${seekTo.inSeconds}s >= duration ${dur.inSeconds}s',
            category: LogCategory.general);
        if (!openPlaying) await _player.play();
      }
    }
  }

  /// Safety net after a resume seek: verify playback actually holds at [target] and
  /// re-seek if it slips. On Android, even the open-paused → seek → play path can slip
  /// back to 0 once buffering finishes; on iOS the first seek holds so this settles
  /// immediately.
  Future<void> _monitorResume(Duration target) async {
    // The caller already sought (and, on Android, opened paused → sought → played).
    // Android can still slip back to 0 once the initial buffer finishes, so watch the
    // real position stream for a while and re-seek whenever it falls back; only treat it
    // as settled once playback has ADVANCED past the target (proof it's genuinely playing
    // from the resume point, not just momentarily parked there).
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var reseeks = 0;
    var settled = false;
    final sub = _player.stream.position.listen((pos) {
      if (settled || !mounted) return;
      if (pos >= target + const Duration(seconds: 2)) {
        settled = true;
        logger.info(
            'Resume: settled at ${pos.inSeconds}s after $reseeks re-seek(s)',
            category: LogCategory.general);
      } else if (pos < target - const Duration(seconds: 10) && reseeks < 10) {
        reseeks++;
        logger.info(
            'Resume: fell back to ${pos.inSeconds}s, re-seeking to ${target.inSeconds}s',
            category: LogCategory.general);
        _player.seek(target);
      }
    });
    while (!settled && mounted && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await sub.cancel();
    if (!settled) {
      logger.error('Resume: never settled at ${target.inSeconds}s',
          category: LogCategory.general);
    }
  }

  /// Jump to another episode in-place: persist the current one, swap the target in,
  /// re-check its saved resume point, and reload.
  Future<void> _playEpisode(int index) async {
    if (index < 0 || index >= _episodes.length) return;
    _saveNow();
    setState(() {
      _epIndex = index;
      _seekTarget = Duration.zero;
      _lastSaved = Duration.zero;
      _position = Duration.zero;
    });
    _resumeSeconds = _lib?.episodeLastPosition(widget.sourceId, _epUrl) ?? 0;
    await _loadVideoList();
  }

  /// "Continue where you left off / Start from the beginning" prompt (anime only).
  Future<bool> _askResume(int seconds) async {
    final at = _fmt(Duration(seconds: seconds));
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Resume playback?',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text('You stopped watching at $at.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Start over')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Continue ($at)')),
        ],
      ),
    );
    return choice ?? true;
  }

  void _maybeSaveProgress(Duration pos) {
    if (pos.inSeconds <= 0) return;
    if ((pos - _lastSaved).abs() < const Duration(seconds: 5)) return;
    _lastSaved = pos;
    _saveNow();
  }

  void _saveNow({bool notify = false}) {
    final mangaUrl = widget.mangaUrl;
    if (mangaUrl == null || _lib == null || _position.inSeconds <= 0) return;
    final atEnd =
        _duration > Duration.zero && _position >= _duration - const Duration(seconds: 15);
    _lib!.updateEpisodeProgress(widget.sourceId, mangaUrl, _epUrl,
        atEnd ? 0 : _position.inSeconds,
        notify: notify);
  }

  void _updateSkip(Duration pos) {
    if (_stamps.isEmpty) {
      if (_activeStamp != null) setState(() => _activeStamp = null);
      return;
    }
    final secs = pos.inMilliseconds / 1000.0;
    MTimeStamp? active;
    int? idx;
    for (var i = 0; i < _stamps.length; i++) {
      final s = _stamps[i];
      if (secs >= s.start && secs < s.end) {
        active = s;
        idx = i;
        break;
      }
    }
    if (active != null && idx != null && _settings.autoSkipIntro && !_skipped.contains(idx)) {
      _skipped.add(idx);
      _player.seek(Duration(milliseconds: (active.end * 1000).round()));
      return;
    }
    if (active != _activeStamp) setState(() => _activeStamp = active);
  }

  void _seekBy(int seconds) {
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    _player.seek(target);
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _player.setRate(s);
  }

  void _cycleFit() {
    setState(() {
      _fit = _fit == BoxFit.contain
          ? BoxFit.cover
          : _fit == BoxFit.cover
              ? BoxFit.fill
              : BoxFit.contain;
    });
  }

  Future<void> _switchQuality(int index) async {
    final pos = _position;
    setState(() {
      _currentVideoIndex = index;
      _stamps = _videos[index].timestamps ?? _stamps;
    });
    await _openVideo(_videos[index]);
    await Future.delayed(const Duration(milliseconds: 500));
    await _player.seek(pos);
  }

  void _bumpVolume(double delta) {
    final v = (_player.state.volume + delta).clamp(0.0, 100.0);
    _player.setVolume(v);
  }

  void _setSubDelay(double seconds) {
    setState(() => _subDelay = seconds);
    // sub-delay isn't on the cross-platform Player API — reach the native handle.
    try {
      (_player.platform as dynamic)?.setProperty('sub-delay', _subDelay.toString());
    } catch (_) {}
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _locked) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(_settings.seekForwardSeconds);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-_settings.seekBackwardSeconds);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _bumpVolume(5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _bumpVolume(-5);
    } else if (k == LogicalKeyboardKey.keyM) {
      _bumpVolume(_player.state.volume > 0 ? -100 : 100);
    } else if (k == LogicalKeyboardKey.keyN && _hasNext) {
      _playEpisode(_epIndex + 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── pickers ─────────────────────────────────────────────────────────────────
  Widget _sheet(String title, List<Widget> children) => ConstrainedBox(
        // Landscape has little vertical room; cap the sheet and let the options
        // scroll so the last row (e.g. Subtitle delay) is never clipped off-screen.
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(title,
                  style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...children,
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  void _openSheet(Widget content) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      // Let the sheet grow past the default ~half-height so tall option lists fit
      // in landscape; _sheet caps + scrolls the content. SafeArea insets the bottom.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: content),
    );
  }

  void _showQualityPicker() => _openSheet(_sheet('Quality', [
        ..._videos.asMap().entries.map((e) => ListTile(
              title: Text(e.value.quality.isEmpty ? 'Source ${e.key}' : e.value.quality,
                  style: GoogleFonts.manrope(color: Colors.white)),
              trailing: e.key == _currentVideoIndex
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _switchQuality(e.key);
              },
            )),
      ]));

  void _showSubtitlePicker() {
    final subs =
        _videos.isNotEmpty ? (_videos[_currentVideoIndex].subtitles ?? []) : <MTrack>[];
    _openSheet(StatefulBuilder(
      builder: (ctx, setSheet) => _sheet('Subtitles', [
        ListTile(
          title: Text('Off', style: GoogleFonts.manrope(color: Colors.white)),
          onTap: () {
            Navigator.pop(context);
            _player.setSubtitleTrack(SubtitleTrack.no());
          },
        ),
        ...subs.map((t) => ListTile(
              title: Text(t.label ?? t.file ?? 'Unknown',
                  style: GoogleFonts.manrope(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                if (t.file != null) {
                  _player.setSubtitleTrack(SubtitleTrack.uri(t.file!, title: t.label));
                }
              },
            )),
        const Divider(color: Colors.white24),
        ListTile(
          title: Text('Subtitle delay',
              style: GoogleFonts.manrope(color: Colors.white)),
          subtitle: Text('${_subDelay.toStringAsFixed(1)}s',
              style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
              onPressed: () => setSheet(() => _setSubDelay(_subDelay - 0.5)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              onPressed: () => setSheet(() => _setSubDelay(_subDelay + 0.5)),
            ),
          ]),
        ),
      ]),
    ));
  }

  void _showAudioPicker() {
    final audios =
        _videos.isNotEmpty ? (_videos[_currentVideoIndex].audios ?? []) : <MTrack>[];
    _openSheet(_sheet('Audio', [
      ...audios.map((t) => ListTile(
            title: Text(t.label ?? t.file ?? 'Unknown',
                style: GoogleFonts.manrope(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              if (t.file != null) {
                _player.setAudioTrack(AudioTrack.uri(t.file!, title: t.label));
              }
            },
          )),
    ]));
  }

  void _showSpeedPicker() => _openSheet(_sheet('Playback speed', [
        for (final s in const [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
          ListTile(
            title: Text('${s}x', style: GoogleFonts.manrope(color: Colors.white)),
            trailing: s == _speed
                ? const Icon(Icons.check_rounded, color: Colors.white)
                : null,
            onTap: () {
              Navigator.pop(context);
              _setSpeed(s);
            },
          ),
      ]));

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _focus.dispose();
    WakelockPlus.disable();
    _saveNow(notify: true);
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null
                ? _buildError()
                : Stack(
                    children: [
                      Positioned.fill(child: _videoWithControls()),
                      if (_activeStamp != null && !_settings.autoSkipIntro)
                        _skipButton(),
                      if (_locked) Positioned.fill(child: _lockOverlay()),
                    ],
                  ),
      ),
    );
  }

  Widget _videoWithControls() {
    return MaterialVideoControlsTheme(
      normal: _controlsTheme(),
      fullscreen: _controlsTheme(),
      child: Video(
        controller: _controller,
        controls: MaterialVideoControls,
        fit: _fit,
      ),
    );
  }

  MaterialVideoControlsThemeData _controlsTheme() {
    final hasSubs =
        _videos.isNotEmpty && (_videos[_currentVideoIndex].subtitles?.isNotEmpty ?? false);
    final hasAudio =
        _videos.isNotEmpty && (_videos[_currentVideoIndex].audios?.isNotEmpty ?? false);
    // We drive our OWN immersive landscape (not media_kit's fullscreen), so media_kit
    // applies no safe-area padding and the controls sit flush at the screen edges —
    // the seek bar + time clip under the bottom/gesture area in landscape. Inset them
    // by the device's real system insets (plus a small floor for the bottom).
    final vp = MediaQuery.of(context).viewPadding;
    return MaterialVideoControlsThemeData(
      seekOnDoubleTap: true,
      seekOnDoubleTapBackwardDuration: Duration(seconds: _settings.seekBackwardSeconds),
      seekOnDoubleTapForwardDuration: Duration(seconds: _settings.seekForwardSeconds),
      speedUpOnLongPress: _settings.longPressSpeedUp,
      speedUpFactor: _settings.speedFactor,
      volumeGesture: _settings.volumeGesture,
      brightnessGesture: _settings.brightnessGesture,
      // `padding` wraps the ENTIRE controls column (top bar, center buttons, seek bar,
      // time), so putting the bottom inset here lifts the seek bar + time off the screen
      // edge regardless of media_kit's internal row order. Floor of 16 so it clears the
      // gesture area even when the OS reports viewPadding.bottom == 0 in immersive mode.
      padding: EdgeInsets.only(
          top: vp.top,
          left: 8 + vp.left,
          right: 8 + vp.right,
          bottom: 16 + vp.bottom),
      seekBarMargin: const EdgeInsets.symmetric(horizontal: 8),
      bottomButtonBarMargin: const EdgeInsets.only(left: 16, right: 16),
      seekBarThumbColor: Colors.white,
      seekBarColor: Colors.white24,
      seekBarPositionColor: Colors.white,
      seekBarBufferColor: Colors.white38,
      topButtonBar: [
        _topBtn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.animeTitle != null)
                Text(widget.animeTitle!,
                    style: GoogleFonts.manrope(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              if (_epTitle != null)
                Text(_epTitle!,
                    style: GoogleFonts.manrope(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (hasSubs) _topBtn(Icons.subtitles_outlined, _showSubtitlePicker),
        if (hasAudio) _topBtn(Icons.multitrack_audio_rounded, _showAudioPicker),
        if (_videos.length > 1) _topBtn(Icons.hd_outlined, _showQualityPicker),
        _topBtn(Icons.speed_rounded, _showSpeedPicker),
        _topBtn(Icons.aspect_ratio_rounded, _cycleFit),
        _topBtn(Icons.lock_open_rounded, () => setState(() => _locked = true)),
      ],
      primaryButtonBar: [
        if (_hasPrev)
          MaterialCustomButton(
            onPressed: () => _playEpisode(_epIndex - 1),
            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
            iconSize: 30,
          ),
        MaterialCustomButton(
          onPressed: () => _seekBy(-_settings.seekBackwardSeconds),
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
          iconSize: 30,
        ),
        const SizedBox(width: 8),
        MaterialPlayOrPauseButton(iconSize: 48),
        const SizedBox(width: 8),
        MaterialCustomButton(
          onPressed: () => _seekBy(_settings.seekForwardSeconds),
          icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
          iconSize: 30,
        ),
        if (_hasNext)
          MaterialCustomButton(
            onPressed: () => _playEpisode(_epIndex + 1),
            icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
            iconSize: 30,
          ),
      ],
      // No fullscreen button — the player already forces immersive landscape, so a
      // second media_kit fullscreen layer would just fight our orientation setup.
      bottomButtonBar: const [
        MaterialPositionIndicator(),
        Spacer(),
      ],
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onPressed) => MaterialCustomButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      );

  Widget _skipButton() {
    final s = _activeStamp!;
    return Positioned(
      right: 24,
      bottom: 96,
      child: SafeArea(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            foregroundColor: Colors.white,
          ),
          onPressed: () => _player.seek(Duration(milliseconds: (s.end * 1000).round())),
          icon: const Icon(Icons.fast_forward_rounded, size: 18),
          label: Text(s.isOutro ? 'Skip Outro' : 'Skip Intro'),
        ),
      ),
    );
  }

  Widget _lockOverlay() {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.lock_rounded, color: Colors.white),
              tooltip: 'Unlock controls',
              onPressed: () => setState(() => _locked = false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 52),
          const SizedBox(height: 16),
          Text(_error ?? 'Unknown error',
              style: GoogleFonts.manrope(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadVideoList,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
