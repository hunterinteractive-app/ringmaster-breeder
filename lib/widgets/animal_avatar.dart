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
    final detail = Paint()
      ..color = BreederColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    if (cavy) {
      // Low, rounded body, blunt muzzle and folded ears distinguish a cavy.
      final body = Path()
        ..moveTo(9, 67)
        ..cubicTo(3, 48, 15, 31, 35, 30)
        ..cubicTo(48, 28, 60, 33, 68, 37)
        ..cubicTo(73, 32, 81, 35, 83, 42)
        ..cubicTo(87, 46, 91, 50, 94, 56)
        ..cubicTo(99, 63, 94, 70, 86, 72)
        ..lineTo(83, 79)
        ..quadraticBezierTo(78, 82, 71, 79)
        ..lineTo(70, 74)
        ..cubicTo(59, 78, 42, 80, 28, 75)
        ..lineTo(26, 81)
        ..quadraticBezierTo(20, 83, 16, 79)
        ..lineTo(16, 74)
        ..quadraticBezierTo(11, 72, 9, 67)
        ..close();
      canvas.drawPath(body, white);
      canvas.drawPath(
        Path()
          ..moveTo(68, 43)
          ..cubicTo(60, 33, 55, 39, 59, 48)
          ..quadraticBezierTo(63, 53, 68, 43),
        detail,
      );
      canvas.drawCircle(const Offset(81, 51), 2.5, maroon);
      canvas.drawPath(
        Path()
          ..moveTo(94, 60)
          ..lineTo(89, 60)
          ..moveTo(88, 65)
          ..quadraticBezierTo(84, 67, 81, 65),
        detail,
      );
      canvas.drawPath(
        Path()
          ..moveTo(22, 62)
          ..quadraticBezierTo(18, 66, 22, 72),
        detail,
      );
    } else {
      // A seated rabbit with a full hindquarter, tapered ears and forefeet.
      final body = Path()
        ..moveTo(16, 75)
        ..cubicTo(9, 59, 16, 43, 32, 42)
        ..cubicTo(42, 41, 49, 45, 53, 48)
        ..quadraticBezierTo(54, 39, 59, 34)
        ..cubicTo(54, 24, 50, 7, 55, 5)
        ..cubicTo(61, 3, 66, 24, 67, 30)
        ..cubicTo(69, 19, 76, 4, 81, 7)
        ..cubicTo(87, 11, 78, 29, 76, 34)
        ..cubicTo(84, 36, 88, 43, 87, 48)
        ..quadraticBezierTo(96, 52, 91, 58)
        ..quadraticBezierTo(87, 62, 77, 62)
        ..lineTo(72, 78)
        ..quadraticBezierTo(85, 79, 82, 84)
        ..lineTo(60, 84)
        ..quadraticBezierTo(51, 91, 33, 87)
        ..quadraticBezierTo(19, 87, 16, 75)
        ..close();
      canvas.drawPath(body, white);
      canvas.drawCircle(const Offset(12, 68), 8, white);
      canvas.drawCircle(const Offset(80, 46), 2.3, maroon);
      canvas.drawPath(
        Path()
          ..moveTo(58, 14)
          ..lineTo(63, 31)
          ..moveTo(78, 16)
          ..lineTo(72, 32),
        detail,
      );
      canvas.drawPath(
        Path()
          ..moveTo(34, 59)
          ..cubicTo(48, 55, 54, 72, 43, 77)
          ..quadraticBezierTo(55, 76, 60, 81),
        detail,
      );
      canvas.drawPath(
        Path()
          ..moveTo(67, 63)
          ..lineTo(63, 78)
          ..moveTo(89, 53)
          ..lineTo(92, 53),
        detail,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeciesPainter oldDelegate) => cavy != oldDelegate.cavy;
}
