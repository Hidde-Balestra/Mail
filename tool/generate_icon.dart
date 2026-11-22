// Genereert de app-iconen in assets/icon/.
// Gebruik: dart run tool/generate_icon.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const size = 1024;
const ss = 4; // supersampling per as (4x4 = 16 samples per pixel)

// Kleurverloop (linksboven -> rechtsonder)
const c1 = [0x3B, 0x6F, 0xD8];
const c2 = [0x6C, 0x4C, 0xE0];

List<double> gradient(double x, double y) {
  final t = ((x + y) / 2).clamp(0.0, 1.0);
  return [for (var i = 0; i < 3; i++) c1[i] + (c2[i] - c1[i]) * t];
}

bool inRoundedRect(
  double x,
  double y,
  double cx,
  double cy,
  double w,
  double h,
  double r,
) {
  final dx = (x - cx).abs() - (w / 2 - r);
  final dy = (y - cy).abs() - (h / 2 - r);
  if (dx <= 0 || dy <= 0) return dx <= r && dy <= r;
  return dx * dx + dy * dy <= r * r;
}

double distToSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final vx = bx - ax, vy = by - ay;
  final t = (((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)).clamp(
    0.0,
    1.0,
  );
  final dx = px - (ax + t * vx), dy = py - (ay + t * vy);
  return math.sqrt(dx * dx + dy * dy);
}

/// Envelop gecentreerd op (0.5, 0.5); [s] = breedte als fractie van het canvas.
/// Geeft 0 = niets, 1 = wit papier, 2 = flap-lijn (achtergrondkleur).
int envelope(double x, double y, double s) {
  final w = s, h = s * 0.70, r = s * 0.09;
  const cx = 0.5, cy = 0.5;
  if (!inRoundedRect(x, y, cx, cy, w, h, r)) return 0;
  final top = cy - h / 2;
  final left = cx - w / 2, right = cx + w / 2;
  final inset = s * 0.13;
  final tipX = cx, tipY = top + h * 0.56;
  final stroke = s * 0.075 / 2;
  final d = math.min(
    distToSegment(x, y, left + inset, top + inset * 0.95, tipX, tipY),
    distToSegment(x, y, right - inset, top + inset * 0.95, tipX, tipY),
  );
  return d <= stroke ? 2 : 1;
}

img.Image render({
  required bool background,
  required double envWidth,
  bool cutFlap = false,
}) {
  final out = img.Image(width: size, height: size, numChannels: 4);
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      double r = 0, g = 0, b = 0, a = 0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final x = (px + (sx + 0.5) / ss) / size;
          final y = (py + (sy + 0.5) / ss) / size;
          final bgCol = gradient(x, y);
          final inBg =
              background && inRoundedRect(x, y, 0.5, 0.5, 1.0, 1.0, 0.225);
          final e = envelope(x, y, envWidth);
          List<double>? col;
          if (e == 1) {
            col = [255, 255, 255];
          } else if (e == 2 && !cutFlap) {
            col = bgCol;
          } else if (inBg) {
            // Subtiele lichte gloed linksboven
            final glow = math.max(
              0.0,
              1 - math.sqrt(math.pow(x - 0.2, 2) + math.pow(y - 0.15, 2)) / 0.7,
            );
            col = [for (final c in bgCol) c + (255 - c) * 0.18 * glow];
          }
          if (col != null) {
            r += col[0];
            g += col[1];
            b += col[2];
            a += 1;
          }
        }
      }
      if (a == 0) continue;
      // Kleuren zijn al per sample gemiddeld; deel door aantal gedekte samples.
      out.setPixelRgba(
        px,
        py,
        (r / a).round(),
        (g / a).round(),
        (b / a).round(),
        (a / (ss * ss) * 255).round(),
      );
    }
  }
  return out;
}

void main() {
  Directory('assets/icon').createSync(recursive: true);
  // Volledig icoon (legacy Android, Windows)
  File(
    'assets/icon/icon.png',
  ).writeAsBytesSync(img.encodePng(render(background: true, envWidth: 0.58)));
  // Voorgrond voor Android adaptive icon (binnen de 66% safe zone)
  File(
    'assets/icon/foreground.png',
  ).writeAsBytesSync(img.encodePng(render(background: false, envWidth: 0.44)));
  // Monochroom (Android 13 themed icons): flap uitgesneden
  File('assets/icon/monochrome.png').writeAsBytesSync(
    img.encodePng(render(background: false, envWidth: 0.44, cutFlap: true)),
  );
  // Achtergrond voor adaptive icon: volledig vlak met kleurverloop
  final bg = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final c = gradient(x / size, y / size);
      bg.setPixelRgb(x, y, c[0].round(), c[1].round(), c[2].round());
    }
  }
  File('assets/icon/background.png').writeAsBytesSync(img.encodePng(bg));
  stdout.writeln('Iconen geschreven naar assets/icon/');
}
