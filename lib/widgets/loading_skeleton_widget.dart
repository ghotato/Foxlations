import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LoadingSkeletonWidget extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const LoadingSkeletonWidget({
    super.key,
    this.width,
    this.height,
    this.borderRadius = AppTheme.radiusMedium,
  });

  @override
  State<LoadingSkeletonWidget> createState() => _LoadingSkeletonWidgetState();
}

class _LoadingSkeletonWidgetState extends State<LoadingSkeletonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _shimmerAnim = CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (_, _) {
        final opacity = 0.3 + (_shimmerAnim.value * 0.3);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(opacity),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

class LibraryGridSkeleton extends StatelessWidget {
  final int columnCount;
  const LibraryGridSkeleton({super.key, this.columnCount = 2});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        childAspectRatio: 0.62,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: columnCount * 3,
      itemBuilder: (_, _) => const LoadingSkeletonWidget(),
    );
  }
}

class ReaderPageSkeleton extends StatelessWidget {
  const ReaderPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          widthFactor: 1.0,
          child: LoadingSkeletonWidget(borderRadius: 0),
        ),
      ),
    );
  }
}
