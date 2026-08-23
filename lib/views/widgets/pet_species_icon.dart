import 'package:flutter/material.dart';

import '../../models/models.dart';

/// A small, dependency-free vector glyph for each supported pet type
/// (ported from the Kate/care-paw build and remapped onto [PetType]).
class PetTypeIcon extends StatelessWidget {
  const PetTypeIcon({
    required this.type,
    required this.color,
    this.size = 24,
    super.key,
  });

  final PetType type;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _PetTypePainter(type: type, color: color),
  );
}

class _PetTypePainter extends CustomPainter {
  const _PetTypePainter({required this.type, required this.color});

  final PetType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = .065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (type) {
      case PetType.dog:
        _dog(canvas, stroke, fill);
      case PetType.cat:
        _cat(canvas, stroke, fill);
      case PetType.rabbit:
        _rabbit(canvas, stroke, fill);
      case PetType.bird:
        _bird(canvas, stroke, fill);
      case PetType.fish:
        _fish(canvas, stroke, fill);
      case PetType.hamster:
        _hamster(canvas, stroke, fill);
      case PetType.guineaPig:
        _guineaPig(canvas, stroke, fill);
      case PetType.ferret:
        _ferret(canvas, stroke, fill);
      case PetType.turtle:
        _turtle(canvas, stroke, fill);
      case PetType.reptile:
        _reptile(canvas, stroke, fill);
      case PetType.snake:
        _reptile(canvas, stroke, fill);
      case PetType.amphibian:
        _amphibian(canvas, stroke, fill);
      case PetType.horse:
        _horse(canvas, stroke, fill);
      case PetType.other:
        _paw(canvas, fill);
    }
    canvas.restore();
  }

  void _dog(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawPath(
      Path()
        ..moveTo(.3, .27)
        ..cubicTo(.16, .17, .12, .3, .2, .51)
        ..cubicTo(.23, .58, .29, .52, .32, .44),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.7, .27)
        ..cubicTo(.84, .17, .88, .3, .8, .51)
        ..cubicTo(.77, .58, .71, .52, .68, .44),
      stroke,
    );
    canvas.drawOval(const Rect.fromLTRB(.25, .22, .75, .82), stroke);
    canvas.drawCircle(const Offset(.39, .47), .035, fill);
    canvas.drawCircle(const Offset(.61, .47), .035, fill);
    canvas.drawOval(const Rect.fromLTRB(.43, .57, .57, .67), fill);
    canvas.drawPath(
      Path()
        ..moveTo(.5, .66)
        ..cubicTo(.46, .75, .38, .71, .37, .68)
        ..moveTo(.5, .66)
        ..cubicTo(.54, .75, .62, .71, .63, .68),
      stroke,
    );
  }

  void _cat(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawPath(
      Path()
        ..moveTo(.25, .4)
        ..lineTo(.27, .14)
        ..lineTo(.43, .29)
        ..cubicTo(.48, .26, .52, .26, .57, .29)
        ..lineTo(.73, .14)
        ..lineTo(.75, .4)
        ..cubicTo(.82, .62, .68, .82, .5, .82)
        ..cubicTo(.32, .82, .18, .62, .25, .4)
        ..close(),
      stroke,
    );
    canvas.drawCircle(const Offset(.39, .48), .03, fill);
    canvas.drawCircle(const Offset(.61, .48), .03, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.46, .59)
        ..lineTo(.54, .59)
        ..lineTo(.5, .64)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.43, .66)
        ..cubicTo(.46, .7, .48, .69, .5, .65)
        ..cubicTo(.52, .69, .54, .7, .57, .66)
        ..moveTo(.34, .6)
        ..lineTo(.14, .56)
        ..moveTo(.34, .66)
        ..lineTo(.14, .7)
        ..moveTo(.66, .6)
        ..lineTo(.86, .56)
        ..moveTo(.66, .66)
        ..lineTo(.86, .7),
      stroke,
    );
  }

  void _rabbit(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawOval(const Rect.fromLTRB(.28, .06, .44, .47), stroke);
    canvas.drawOval(const Rect.fromLTRB(.56, .06, .72, .47), stroke);
    canvas.drawOval(const Rect.fromLTRB(.24, .34, .76, .86), stroke);
    canvas.drawCircle(const Offset(.39, .55), .03, fill);
    canvas.drawCircle(const Offset(.61, .55), .03, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.45, .65)
        ..lineTo(.55, .65)
        ..lineTo(.5, .7)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.5, .7)
        ..lineTo(.5, .78)
        ..moveTo(.5, .74)
        ..cubicTo(.45, .79, .41, .77, .39, .74)
        ..moveTo(.5, .74)
        ..cubicTo(.55, .79, .59, .77, .61, .74),
      stroke,
    );
  }

  void _bird(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawOval(const Rect.fromLTRB(.16, .24, .72, .79), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(.7, .42)
        ..lineTo(.91, .5)
        ..lineTo(.7, .59)
        ..close(),
      stroke,
    );
    canvas.drawCircle(const Offset(.58, .4), .03, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.31, .51)
        ..cubicTo(.4, .43, .58, .51, .54, .67)
        ..cubicTo(.43, .71, .34, .64, .31, .51),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.33, .8)
        ..lineTo(.29, .9)
        ..moveTo(.52, .79)
        ..lineTo(.56, .9),
      stroke,
    );
  }

  void _fish(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawOval(const Rect.fromLTRB(.13, .3, .72, .72), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(.7, .5)
        ..lineTo(.91, .28)
        ..lineTo(.91, .74)
        ..close(),
      stroke,
    );
    canvas.drawCircle(const Offset(.28, .46), .03, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.46, .33)
        ..cubicTo(.52, .18, .63, .22, .64, .34)
        ..moveTo(.46, .68)
        ..cubicTo(.52, .83, .63, .79, .64, .67)
        ..moveTo(.46, .49)
        ..cubicTo(.54, .43, .59, .49, .55, .58),
      stroke,
    );
  }

  void _hamster(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(.3, .3), .14, stroke);
    canvas.drawCircle(const Offset(.7, .3), .14, stroke);
    canvas.drawOval(const Rect.fromLTRB(.2, .23, .8, .86), stroke);
    canvas.drawCircle(const Offset(.38, .49), .03, fill);
    canvas.drawCircle(const Offset(.62, .49), .03, fill);
    canvas.drawCircle(const Offset(.5, .62), .045, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.34, .65)
        ..cubicTo(.25, .62, .21, .66, .19, .72)
        ..moveTo(.66, .65)
        ..cubicTo(.75, .62, .79, .66, .81, .72)
        ..moveTo(.46, .71)
        ..cubicTo(.48, .76, .52, .76, .54, .71),
      stroke,
    );
  }

  void _guineaPig(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawPath(
      Path()
        ..moveTo(.16, .54)
        ..cubicTo(.16, .29, .39, .18, .67, .3)
        ..cubicTo(.87, .38, .9, .64, .72, .75)
        ..cubicTo(.49, .88, .16, .79, .16, .54)
        ..close(),
      stroke,
    );
    canvas.drawCircle(const Offset(.31, .32), .1, stroke);
    canvas.drawCircle(const Offset(.67, .35), .085, stroke);
    canvas.drawCircle(const Offset(.65, .47), .032, fill);
    canvas.drawCircle(const Offset(.82, .57), .032, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.3, .39)
        ..cubicTo(.39, .5, .37, .68, .3, .77),
      stroke,
    );
  }

  void _ferret(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawPath(
      Path()
        ..moveTo(.21, .66)
        ..cubicTo(.12, .48, .25, .29, .48, .35)
        ..cubicTo(.59, .18, .82, .22, .86, .43)
        ..cubicTo(.9, .65, .7, .77, .5, .69)
        ..cubicTo(.39, .83, .25, .8, .21, .66)
        ..close(),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.52, .34)
        ..lineTo(.55, .17)
        ..lineTo(.66, .27)
        ..moveTo(.75, .28)
        ..lineTo(.84, .18)
        ..lineTo(.85, .39),
      stroke,
    );
    canvas.drawCircle(const Offset(.65, .43), .028, fill);
    canvas.drawCircle(const Offset(.8, .46), .028, fill);
    canvas.drawCircle(const Offset(.87, .55), .035, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.22, .65)
        ..cubicTo(.08, .72, .1, .88, .27, .83),
      stroke,
    );
  }

  void _turtle(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawOval(const Rect.fromLTRB(.18, .29, .72, .75), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(.32, .33)
        ..lineTo(.45, .51)
        ..lineTo(.31, .7)
        ..moveTo(.58, .33)
        ..lineTo(.45, .51)
        ..lineTo(.6, .7),
      stroke,
    );
    canvas.drawCircle(const Offset(.8, .47), .12, stroke);
    canvas.drawCircle(const Offset(.84, .44), .022, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.25, .67)
        ..lineTo(.13, .82)
        ..moveTo(.64, .66)
        ..lineTo(.76, .81)
        ..moveTo(.24, .37)
        ..lineTo(.12, .23)
        ..moveTo(.65, .38)
        ..lineTo(.75, .23),
      stroke,
    );
  }

  void _reptile(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawOval(const Rect.fromLTRB(.34, .35, .73, .65), stroke);
    canvas.drawCircle(const Offset(.76, .42), .13, stroke);
    canvas.drawCircle(const Offset(.81, .39), .022, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.36, .48)
        ..cubicTo(.21, .38, .07, .39, .1, .55)
        ..cubicTo(.12, .66, .23, .71, .29, .64)
        ..moveTo(.45, .62)
        ..lineTo(.34, .78)
        ..lineTo(.25, .76)
        ..moveTo(.58, .63)
        ..lineTo(.68, .78)
        ..lineTo(.77, .76)
        ..moveTo(.45, .38)
        ..lineTo(.34, .23)
        ..lineTo(.25, .25)
        ..moveTo(.58, .37)
        ..lineTo(.68, .22)
        ..lineTo(.77, .24),
      stroke,
    );
  }

  void _amphibian(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(.31, .35), .13, stroke);
    canvas.drawCircle(const Offset(.69, .35), .13, stroke);
    canvas.drawOval(const Rect.fromLTRB(.18, .28, .82, .82), stroke);
    canvas.drawCircle(const Offset(.31, .35), .035, fill);
    canvas.drawCircle(const Offset(.69, .35), .035, fill);
    canvas.drawPath(
      Path()
        ..moveTo(.31, .62)
        ..cubicTo(.42, .73, .58, .73, .69, .62)
        ..moveTo(.22, .68)
        ..lineTo(.08, .83)
        ..lineTo(.2, .81)
        ..moveTo(.78, .68)
        ..lineTo(.92, .83)
        ..lineTo(.8, .81),
      stroke,
    );
  }

  void _horse(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawPath(
      Path()
        ..moveTo(.29, .3)
        ..lineTo(.25, .1)
        ..lineTo(.4, .24)
        ..cubicTo(.5, .17, .64, .2, .71, .3)
        ..lineTo(.8, .13)
        ..lineTo(.82, .4)
        ..cubicTo(.83, .66, .67, .85, .48, .82)
        ..cubicTo(.29, .79, .2, .56, .29, .3)
        ..close(),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.3, .31)
        ..cubicTo(.18, .4, .19, .65, .3, .75),
      stroke,
    );
    canvas.drawCircle(const Offset(.45, .46), .03, fill);
    canvas.drawCircle(const Offset(.68, .44), .03, fill);
    canvas.drawOval(const Rect.fromLTRB(.42, .62, .7, .77), stroke);
    canvas.drawCircle(const Offset(.49, .68), .018, fill);
    canvas.drawCircle(const Offset(.63, .68), .018, fill);
  }

  void _paw(Canvas canvas, Paint fill) {
    canvas.drawOval(const Rect.fromLTRB(.31, .5, .69, .84), fill);
    canvas.drawCircle(const Offset(.22, .42), .095, fill);
    canvas.drawCircle(const Offset(.4, .25), .09, fill);
    canvas.drawCircle(const Offset(.6, .25), .09, fill);
    canvas.drawCircle(const Offset(.78, .42), .095, fill);
  }

  @override
  bool shouldRepaint(covariant _PetTypePainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color;
}
