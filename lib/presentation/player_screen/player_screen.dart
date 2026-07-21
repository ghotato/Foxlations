import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../../eval/model/m_video.dart';
import '../../eval/lib.dart';
import '../../core/providers/source_provider.dart';

class PlayerScreen extends StatefulWidget {
  final String sourceId;
  final String episodeUrl;
  final String? episodeTitle;
  final String? animeTitle;

  const PlayerScreen({
    super.key,
    required this.sourceId,
    required this.episodeUrl,
    this.episodeTitle,
    this.animeTitle,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  List<MVideo> _videos = [];
  int _currentVideoIndex = 0;

  bool _isLoading = true;
  String? _error;

  bool _showControls = true;
  Timer? _hideTimer;
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isBuffering = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _setupListeners();
    _loadVideoList();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _scheduleHide();
  }

  void _setupListeners() {
    _subs.addAll([
      _player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }),
      _player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
    ]);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
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
        (service) => service.getVideoList(widget.episodeUrl),
      );
      if (videos.isEmpty) throw Exception('No video sources found');

      if (mounted) {
        setState(() { _videos = videos; _isLoading = false; });
        await _openVideo(videos.first);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _openVideo(MVideo video) async {
    await _player.open(Media(video.url, httpHeaders: video.headers ?? {}));
    await _player.play();
  }

  Future<void> _switchQuality(int index) async {
    final pos = _position;
    setState(() => _currentVideoIndex = index);
    await _openVideo(_videos[index]);
    await Future.delayed(const Duration(milliseconds: 500));
    await _player.seek(pos);
  }

  void _showQualityPicker() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Quality',
                  style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            ..._videos.asMap().entries.map((e) {
              final idx = e.key;
              final video = e.value;
              return ListTile(
                title: Text(video.quality.isEmpty ? 'Source $idx' : video.quality,
                    style: GoogleFonts.manrope(color: Colors.white)),
                trailing: idx == _currentVideoIndex
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchQuality(idx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      },
    ).then((_) => _scheduleHide());
  }

  void _showSubtitlePicker() {
    final subs = _videos.isNotEmpty ? (_videos[_currentVideoIndex].subtitles ?? []) : <MTrack>[];
    if (subs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No subtitles available'), duration: Duration(seconds: 2)));
      return;
    }
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Subtitles',
                style: GoogleFonts.manrope(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ...subs.map((t) => ListTile(
            title: Text(t.label ?? t.file ?? 'Unknown',
                style: GoogleFonts.manrope(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              if (t.file != null) {
                _player.setSubtitleTrack(SubtitleTrack.uri(t.file!, title: t.label));
              }
            },
          )),
          const SizedBox(height: 8),
        ],
      ),
    ).then((_) => _scheduleHide());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
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
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Video
            Center(
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : _error != null
                      ? _buildError()
                      : Video(controller: _controller),
            ),

            // Buffering spinner (on top of video)
            if (!_isLoading && _isBuffering)
              const Center(child: CircularProgressIndicator(color: Colors.white70)),

            // Controls overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: _buildControls(),
            ),
          ],
        ),
      ),
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

  Widget _buildControls() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
          stops: [0.0, 0.25, 0.75, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.animeTitle != null)
                          Text(widget.animeTitle!,
                              style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                        if (widget.episodeTitle != null)
                          Text(widget.episodeTitle!,
                              style: GoogleFonts.manrope(color: Colors.white70, fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (_videos.isNotEmpty &&
                      (_videos[_currentVideoIndex].subtitles?.isNotEmpty ?? false))
                    IconButton(
                      icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
                      tooltip: 'Subtitles',
                      onPressed: _showSubtitlePicker,
                    ),
                  if (_videos.length > 1)
                    IconButton(
                      icon: const Icon(Icons.hd_rounded, color: Colors.white),
                      tooltip: 'Quality',
                      onPressed: _showQualityPicker,
                    ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Centre play/pause button
          if (!_isBuffering)
            IconButton(
              iconSize: 56,
              icon: Icon(
                _isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                color: Colors.white.withAlpha(220),
              ),
              onPressed: () {
                _isPlaying ? _player.pause() : _player.play();
                _scheduleHide();
              },
            ),

          const Spacer(),

          // Bottom seek bar + time
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      trackHeight: 2.5,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      value: _duration.inMilliseconds > 0
                          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0,
                      onChanged: _duration.inMilliseconds > 0
                          ? (v) {
                              _player.seek(Duration(
                                  milliseconds: (v * _duration.inMilliseconds).toInt()));
                              _scheduleHide();
                            }
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      Text(_fmt(_position),
                          style: GoogleFonts.manrope(color: Colors.white70, fontSize: 12)),
                      const Spacer(),
                      Text(_fmt(_duration),
                          style: GoogleFonts.manrope(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
