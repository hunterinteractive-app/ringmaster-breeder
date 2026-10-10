import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AnimalAvatar extends StatelessWidget {
  final String species;
  final String? photoUrl;
  final double size;
  const AnimalAvatar({
    super.key,
    required this.species,
    this.photoUrl,
    this.size = 68,
  });
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: BreederColors.primary,
      child: Padding(
        padding: EdgeInsets.all(size * .16),
        child: CustomPaint(
          painter: _SpeciesPainter(species.toLowerCase() == 'cavy'),
        ),
      ),
    );
    return Semantics(
      label:
          '${species.toLowerCase() == 'cavy' ? 'Cavy' : 'Rabbit'} ${photoUrl == null ? 'silhouette' : 'photo'}',
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: photoUrl == null
              ? fallback
              : Image.network(
                  photoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _SpeciesPainter extends CustomPainter {
  final bool cavy;
  const _SpeciesPainter(this.cavy);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final white = Paint()..color = Colors.white;
    final maroon = Paint()..color = BreederColors.primary;
    if (cavy) {
      canvas.drawOval(const Rect.fromLTWH(10, 35, 70, 48), white);
      canvas.drawOval(const Rect.fromLTWH(61, 40, 32, 32), white);
      canvas.drawOval(const Rect.fromLTWH(63, 30, 16, 20), white);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(22, 73, 17, 14),
          const Radius.circular(5),
        ),
        white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(67, 72, 14, 14),
          const Radius.circular(5),
        ),
        white,
      );
      canvas.drawCircle(const Offset(82, 51), 3, maroon);
      canvas.drawOval(const Rect.fromLTWH(89, 57, 6, 5), maroon);
    } else {
      canvas.drawOval(const Rect.fromLTWH(16, 46, 57, 42), white);
      canvas.drawCircle(const Offset(64, 46), 17, white);
      canvas.drawOval(const Rect.fromLTWH(50, 3, 12, 38), white);
      canvas.drawOval(const Rect.fromLTWH(66, 7, 12, 34), white);
      canvas.drawCircle(const Offset(13, 69), 10, white);
      canvas.drawOval(const Rect.fromLTWH(49, 78, 33, 12), white);
      canvas.drawCircle(const Offset(70, 42), 3, maroon);
    }
  }

  @override
  bool shouldRepaint(_SpeciesPainter oldDelegate) => cavy != oldDelegate.cavy;
}
