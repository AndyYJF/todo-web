import 'package:prism_ui/icons/icons.dart';

abstract final class TodoGlyphs {
  static const today = Glyph([
    GlyphCircle(12, 12, 4, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 2),
      GlyphVertex(12, 4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 20),
      GlyphVertex(12, 22),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(2, 12),
      GlyphVertex(4, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(20, 12),
      GlyphVertex(22, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5, 5),
      GlyphVertex(6.5, 6.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(17.5, 17.5),
      GlyphVertex(19, 19),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5, 19),
      GlyphVertex(6.5, 17.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(17.5, 6.5),
      GlyphVertex(19, 5),
    ], role: GlyphRole.line),
  ]);
  static const tasks = Glyph([
    GlyphBox(4, 3, 20, 21, 3),
    GlyphPolyline([
      GlyphVertex(8, 8),
      GlyphVertex(16, 8),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8, 12),
      GlyphVertex(16, 12),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8, 16),
      GlyphVertex(13, 16),
    ], role: GlyphRole.detail),
  ]);
  static const quadrant = Glyph([
    GlyphBox(3, 3, 10, 10, 2),
    GlyphBox(14, 3, 21, 10, 2),
    GlyphBox(3, 14, 10, 21, 2),
    GlyphBox(14, 14, 21, 21, 2),
  ]);
  static const more = Glyph([
    GlyphCircle(5, 12, 1.7, solid: true),
    GlyphCircle(12, 12, 1.7, solid: true),
    GlyphCircle(19, 12, 1.7, solid: true),
  ]);
  static const subtract = Glyph([
    GlyphPolyline([
      GlyphVertex(5, 12),
      GlyphVertex(19, 12),
    ], role: GlyphRole.line),
  ]);
  static const add = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 5),
      GlyphVertex(12, 19),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5, 12),
      GlyphVertex(19, 12),
    ], role: GlyphRole.line),
  ]);
  static const lunchBreak = Glyph([
    GlyphPolyline([
      GlyphVertex(9, 5),
      GlyphVertex(9, 19),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15, 5),
      GlyphVertex(15, 19),
    ], role: GlyphRole.line),
  ]);
  static const calendar = Glyph([
    GlyphBox(3, 5, 21, 21, 3),
    GlyphPolyline([
      GlyphVertex(3, 10),
      GlyphVertex(21, 10),
    ], role: GlyphRole.detail),
    GlyphPolyline([GlyphVertex(8, 2), GlyphVertex(8, 7)], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16, 2),
      GlyphVertex(16, 7),
    ], role: GlyphRole.line),
  ]);
  static const edit = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 16),
      GlyphVertex(16, 4, 1),
      GlyphVertex(20, 8, 1),
      GlyphVertex(8, 20),
      GlyphVertex(3, 21),
      GlyphVertex(4, 16),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(13, 7),
      GlyphVertex(17, 11),
    ], role: GlyphRole.detail),
  ]);
  static const trash = Glyph([
    GlyphPolyline([
      GlyphVertex(5, 6),
      GlyphVertex(19, 6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8, 6),
      GlyphVertex(8, 3, 1),
      GlyphVertex(16, 3, 1),
      GlyphVertex(16, 6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(6, 6),
      GlyphVertex(7, 21, 2),
      GlyphVertex(17, 21, 2),
      GlyphVertex(18, 6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(10, 10),
      GlyphVertex(10, 17),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14, 10),
      GlyphVertex(14, 17),
    ], role: GlyphRole.detail),
  ]);
  static const cloud = Glyph([
    GlyphPath('M6 18a4.5 4.5 0 1 1 1-8.9A6 6 0 0 1 19 9a4.5 4.5 0 1 1-1 9Z'),
  ]);
}
