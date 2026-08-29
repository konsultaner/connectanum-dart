import 'dart:typed_data';

import 'package:flutter/material.dart';

abstract interface class StickerRenderer {
  Future<Uint8List> render(StickerDesign design);
}

final class BundledStickerRenderer implements StickerRenderer {
  const BundledStickerRenderer();

  static const _size = 256;
  static const _margin = 10;
  static const _radius = 52;

  static final List<int> _crcTable = List<int>.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 0 ? crc >> 1 : 0xedb88320 ^ (crc >> 1);
    }
    return crc & 0xffffffff;
  }, growable: false);

  @override
  Future<Uint8List> render(StickerDesign design) async {
    final pixels = Uint8List(_size * _size * 4);
    try {
      final start = design.startColor.toARGB32();
      final end = design.endColor.toARGB32();

      for (var y = 0; y < _size; y += 1) {
        for (var x = 0; x < _size; x += 1) {
          if (!_insideCard(x, y)) continue;
          final amount = (x + y) / ((_size - 1) * 2);
          _setPixel(
            pixels,
            x,
            y,
            _mixChannel(start >> 16, end >> 16, amount),
            _mixChannel(start >> 8, end >> 8, amount),
            _mixChannel(start, end, amount),
            255,
          );
        }
      }

      _blendCircle(pixels, 214, 42, 30, 255, 255, 255, 38);
      _blendCircle(pixels, 38, 218, 38, 255, 255, 255, 28);
      _drawText(
        pixels,
        design.mark,
        foreground: const Color(0x4D000000),
        offsetY: 3,
      );
      _drawText(pixels, design.mark, foreground: design.foregroundColor);
      return _encodePng(pixels);
    } finally {
      pixels.fillRange(0, pixels.length, 0);
    }
  }

  static bool _insideCard(int x, int y) {
    if (x < _margin ||
        y < _margin ||
        x >= _size - _margin ||
        y >= _size - _margin) {
      return false;
    }
    final left = _margin + _radius;
    final right = _size - _margin - _radius - 1;
    final top = _margin + _radius;
    final bottom = _size - _margin - _radius - 1;
    final centerX = x < left
        ? left
        : x > right
        ? right
        : x;
    final centerY = y < top
        ? top
        : y > bottom
        ? bottom
        : y;
    final dx = x - centerX;
    final dy = y - centerY;
    return (dx * dx) + (dy * dy) <= _radius * _radius;
  }

  static int _mixChannel(int start, int end, double amount) =>
      (((start & 0xff) * (1 - amount)) + ((end & 0xff) * amount)).round();

  static void _blendCircle(
    Uint8List pixels,
    int centerX,
    int centerY,
    int radius,
    int red,
    int green,
    int blue,
    int alpha,
  ) {
    final radiusSquared = radius * radius;
    for (var y = centerY - radius; y <= centerY + radius; y += 1) {
      for (var x = centerX - radius; x <= centerX + radius; x += 1) {
        if (x < 0 ||
            y < 0 ||
            x >= _size ||
            y >= _size ||
            ((x - centerX) * (x - centerX)) + ((y - centerY) * (y - centerY)) >
                radiusSquared) {
          continue;
        }
        _blendPixel(pixels, x, y, red, green, blue, alpha);
      }
    }
  }

  static void _drawText(
    Uint8List pixels,
    String text, {
    required Color foreground,
    int offsetY = 0,
  }) {
    final normalized = text.toUpperCase();
    final widthUnits = (normalized.length * 5) + (normalized.length - 1);
    final scale = ((_size - 34) ~/ widthUnits).clamp(5, 17);
    final textWidth = widthUnits * scale;
    final textHeight = 7 * scale;
    final startX = (_size - textWidth) ~/ 2;
    final startY = ((_size - textHeight) ~/ 2) + offsetY;
    final color = foreground.toARGB32();
    final alpha = color >> 24 & 0xff;
    final red = color >> 16 & 0xff;
    final green = color >> 8 & 0xff;
    final blue = color & 0xff;

    for (
      var characterIndex = 0;
      characterIndex < normalized.length;
      characterIndex += 1
    ) {
      final glyph = _glyphs[normalized[characterIndex]] ?? _glyphs['?']!;
      final glyphX = startX + (characterIndex * 6 * scale);
      for (var row = 0; row < glyph.length; row += 1) {
        for (var column = 0; column < glyph[row].length; column += 1) {
          if (glyph[row].codeUnitAt(column) != 49) continue;
          for (var py = 0; py < scale; py += 1) {
            for (var px = 0; px < scale; px += 1) {
              _blendPixel(
                pixels,
                glyphX + (column * scale) + px,
                startY + (row * scale) + py,
                red,
                green,
                blue,
                alpha,
              );
            }
          }
        }
      }
    }
  }

  static void _setPixel(
    Uint8List pixels,
    int x,
    int y,
    int red,
    int green,
    int blue,
    int alpha,
  ) {
    final index = ((y * _size) + x) * 4;
    pixels[index] = red;
    pixels[index + 1] = green;
    pixels[index + 2] = blue;
    pixels[index + 3] = alpha;
  }

  static void _blendPixel(
    Uint8List pixels,
    int x,
    int y,
    int red,
    int green,
    int blue,
    int alpha,
  ) {
    if (x < 0 || y < 0 || x >= _size || y >= _size) return;
    final index = ((y * _size) + x) * 4;
    final destinationAlpha = pixels[index + 3];
    final inverse = 255 - alpha;
    pixels[index] = ((red * alpha) + (pixels[index] * inverse)) ~/ 255;
    pixels[index + 1] =
        ((green * alpha) + (pixels[index + 1] * inverse)) ~/ 255;
    pixels[index + 2] = ((blue * alpha) + (pixels[index + 2] * inverse)) ~/ 255;
    pixels[index + 3] = alpha + ((destinationAlpha * inverse) ~/ 255);
  }

  static Uint8List _encodePng(Uint8List pixels) {
    final raw = Uint8List((_size * 4 + 1) * _size);
    try {
      final rowBytes = _size * 4;
      for (var row = 0; row < _size; row += 1) {
        final rawOffset = row * (rowBytes + 1);
        raw[rawOffset] = 0;
        raw.setRange(
          rawOffset + 1,
          rawOffset + 1 + rowBytes,
          pixels,
          row * rowBytes,
        );
      }

      final compressed = BytesBuilder(copy: false)..add(const [0x78, 0x01]);
      var offset = 0;
      while (offset < raw.length) {
        final length = (raw.length - offset).clamp(0, 65535);
        final finalBlock = offset + length == raw.length;
        final inverseLength = 0xffff ^ length;
        compressed
          ..add([
            finalBlock ? 1 : 0,
            length & 0xff,
            length >> 8,
            inverseLength & 0xff,
            inverseLength >> 8,
          ])
          ..add(Uint8List.sublistView(raw, offset, offset + length));
        offset += length;
      }
      compressed.add(_uint32(_adler32(raw)));

      final header = ByteData(13)
        ..setUint32(0, _size)
        ..setUint32(4, _size)
        ..setUint8(8, 8)
        ..setUint8(9, 6)
        ..setUint8(10, 0)
        ..setUint8(11, 0)
        ..setUint8(12, 0);
      return (BytesBuilder(copy: false)
            ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
            ..add(_pngChunk('IHDR', header.buffer.asUint8List()))
            ..add(_pngChunk('IDAT', compressed.takeBytes()))
            ..add(_pngChunk('IEND', Uint8List(0))))
          .takeBytes();
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
  }

  static Uint8List _pngChunk(String type, Uint8List data) {
    final typeBytes = Uint8List.fromList(type.codeUnits);
    final crcInput =
        (BytesBuilder(copy: false)
              ..add(typeBytes)
              ..add(data))
            .takeBytes();
    return (BytesBuilder(copy: false)
          ..add(_uint32(data.length))
          ..add(typeBytes)
          ..add(data)
          ..add(_uint32(_crc32(crcInput))))
        .takeBytes();
  }

  static Uint8List _uint32(int value) {
    final bytes = ByteData(4)..setUint32(0, value & 0xffffffff);
    return bytes.buffer.asUint8List();
  }

  static int _adler32(Uint8List bytes) {
    var first = 1;
    var second = 0;
    for (final byte in bytes) {
      first = (first + byte) % 65521;
      second = (second + first) % 65521;
    }
    return ((second << 16) | first) & 0xffffffff;
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static const _glyphs = <String, List<String>>{
    'A': ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
    'C': ['01111', '10000', '10000', '10000', '10000', '10000', '01111'],
    'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    'F': ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
    'G': ['01111', '10000', '10000', '10111', '10001', '10001', '01111'],
    'H': ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
    'I': ['11111', '00100', '00100', '00100', '00100', '00100', '11111'],
    'L': ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
    'M': ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
    'N': ['10001', '11001', '11001', '10101', '10011', '10011', '10001'],
    'O': ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
    'P': ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
    'R': ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
    'S': ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
    'T': ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
    'V': ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
    'W': ['10001', '10001', '10001', '10101', '10101', '11011', '10001'],
    'X': ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
    'Y': ['10001', '10001', '01010', '00100', '00100', '00100', '00100'],
    'Z': ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
    '!': ['00100', '00100', '00100', '00100', '00100', '00000', '00100'],
    '?': ['01110', '10001', '00001', '00010', '00100', '00000', '00100'],
  };
}

@immutable
final class StickerDesign {
  const StickerDesign({
    required this.id,
    required this.emoji,
    required this.mark,
    required this.label,
    required this.keywords,
    required this.startColor,
    required this.endColor,
    this.foregroundColor = Colors.white,
  });

  final String id;
  final String emoji;
  final String mark;
  final String label;
  final String keywords;
  final Color startColor;
  final Color endColor;
  final Color foregroundColor;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty ||
        label.toLowerCase().contains(normalized) ||
        keywords.contains(normalized) ||
        emoji.contains(normalized);
  }
}

@immutable
final class EmojiChoice {
  const EmojiChoice(this.emoji, this.label, this.keywords);

  final String emoji;
  final String label;
  final String keywords;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty ||
        label.toLowerCase().contains(normalized) ||
        keywords.contains(normalized) ||
        emoji.contains(normalized);
  }
}

const wampAppStickers = <StickerDesign>[
  StickerDesign(
    id: 'nice',
    emoji: '👍',
    mark: 'NICE',
    label: 'Nice!',
    keywords: 'yes approve good great thumbs up',
    startColor: Color(0xFF17806D),
    endColor: Color(0xFF57B88A),
  ),
  StickerDesign(
    id: 'love-it',
    emoji: '😍',
    mark: 'LOVE',
    label: 'Love it',
    keywords: 'heart eyes adore favorite',
    startColor: Color(0xFFC73A5F),
    endColor: Color(0xFFFF7A8A),
  ),
  StickerDesign(
    id: 'hooray',
    emoji: '🎉',
    mark: 'YAY!',
    label: 'Hooray!',
    keywords: 'party celebrate congratulations confetti',
    startColor: Color(0xFFE8872D),
    endColor: Color(0xFFFFC857),
    foregroundColor: Color(0xFF482716),
  ),
  StickerDesign(
    id: 'on-my-way',
    emoji: '🚀',
    mark: 'GO!',
    label: 'On my way',
    keywords: 'travel coming soon rocket',
    startColor: Color(0xFF2356A8),
    endColor: Color(0xFF55A9E8),
  ),
  StickerDesign(
    id: 'thank-you',
    emoji: '🙏',
    mark: 'THX',
    label: 'Thank you',
    keywords: 'thanks grateful please prayer',
    startColor: Color(0xFF7357A8),
    endColor: Color(0xFFC08ED9),
  ),
  StickerDesign(
    id: 'oops',
    emoji: '😅',
    mark: 'OOPS',
    label: 'Oops',
    keywords: 'sorry sweat awkward mistake',
    startColor: Color(0xFFB84B3E),
    endColor: Color(0xFFFF8F70),
  ),
  StickerDesign(
    id: 'laughing',
    emoji: '😂',
    mark: 'LOL',
    label: 'Too funny',
    keywords: 'lol laugh tears funny',
    startColor: Color(0xFFD36B18),
    endColor: Color(0xFFFFB347),
    foregroundColor: Color(0xFF42220C),
  ),
  StickerDesign(
    id: 'wow',
    emoji: '🤩',
    mark: 'WOW',
    label: 'Wow!',
    keywords: 'amazing star struck impressed',
    startColor: Color(0xFF087F8C),
    endColor: Color(0xFF5BC0BE),
  ),
  StickerDesign(
    id: 'good-morning',
    emoji: '☀️',
    mark: 'GM',
    label: 'Good morning',
    keywords: 'sun hello awake day',
    startColor: Color(0xFFE39717),
    endColor: Color(0xFFFFD166),
    foregroundColor: Color(0xFF4B3410),
  ),
  StickerDesign(
    id: 'good-night',
    emoji: '🌙',
    mark: 'ZZZ',
    label: 'Good night',
    keywords: 'moon sleep dreams evening',
    startColor: Color(0xFF283A69),
    endColor: Color(0xFF655A9E),
  ),
  StickerDesign(
    id: 'you-got-this',
    emoji: '💪',
    mark: 'STRONG',
    label: 'You got this',
    keywords: 'strong support encourage power',
    startColor: Color(0xFF16785F),
    endColor: Color(0xFF64B870),
  ),
  StickerDesign(
    id: 'coffee-time',
    emoji: '☕',
    mark: 'COFFEE',
    label: 'Coffee time',
    keywords: 'break cafe morning drink',
    startColor: Color(0xFF6B4226),
    endColor: Color(0xFFC18457),
  ),
];

const wampAppEmojis = <EmojiChoice>[
  EmojiChoice('😀', 'Grinning face', 'happy smile joy face'),
  EmojiChoice('😃', 'Big smile', 'happy grin face'),
  EmojiChoice('😄', 'Smiling eyes', 'happy laugh face'),
  EmojiChoice('😁', 'Beaming face', 'happy grin teeth'),
  EmojiChoice('😆', 'Laughing face', 'lol happy squint'),
  EmojiChoice('😂', 'Tears of joy', 'lol laugh funny cry'),
  EmojiChoice('🤣', 'Rolling laughing', 'rofl laugh funny'),
  EmojiChoice('😊', 'Warm smile', 'happy blush kind'),
  EmojiChoice('😇', 'Angel face', 'innocent halo'),
  EmojiChoice('🙂', 'Slight smile', 'happy friendly'),
  EmojiChoice('🙃', 'Upside-down face', 'silly ironic'),
  EmojiChoice('😉', 'Wink', 'playful friendly'),
  EmojiChoice('😌', 'Relieved face', 'calm peaceful'),
  EmojiChoice('😍', 'Heart eyes', 'love adore favorite'),
  EmojiChoice('🥰', 'Smiling hearts', 'love affection'),
  EmojiChoice('😘', 'Blowing a kiss', 'love kiss'),
  EmojiChoice('😋', 'Yummy face', 'food delicious'),
  EmojiChoice('😜', 'Winking tongue', 'silly playful'),
  EmojiChoice('🤪', 'Zany face', 'wild silly fun'),
  EmojiChoice('🤔', 'Thinking face', 'consider question hmm'),
  EmojiChoice('🫡', 'Saluting face', 'respect yes hello'),
  EmojiChoice('🤗', 'Hugging face', 'hug support'),
  EmojiChoice('🤭', 'Giggle', 'oops laugh secret'),
  EmojiChoice('🤩', 'Star struck', 'wow amazing impressed'),
  EmojiChoice('😎', 'Cool face', 'sunglasses confident'),
  EmojiChoice('🥳', 'Party face', 'celebrate birthday fun'),
  EmojiChoice('😕', 'Confused face', 'unsure question'),
  EmojiChoice('😢', 'Crying face', 'sad tear'),
  EmojiChoice('😭', 'Loudly crying', 'sad tears'),
  EmojiChoice('😤', 'Determined face', 'angry triumph'),
  EmojiChoice('😱', 'Screaming face', 'shock fear wow'),
  EmojiChoice('👍', 'Thumbs up', 'yes approve good nice'),
  EmojiChoice('👎', 'Thumbs down', 'no disapprove bad'),
  EmojiChoice('👏', 'Clapping hands', 'applause congrats'),
  EmojiChoice('🙌', 'Raised hands', 'hooray celebrate'),
  EmojiChoice('🙏', 'Folded hands', 'please thanks prayer'),
  EmojiChoice('🤝', 'Handshake', 'deal agreement hello'),
  EmojiChoice('💪', 'Strong arm', 'power support strength'),
  EmojiChoice('👋', 'Waving hand', 'hello goodbye hi'),
  EmojiChoice('🫶', 'Heart hands', 'love support'),
  EmojiChoice('❤️', 'Red heart', 'love favorite'),
  EmojiChoice('🧡', 'Orange heart', 'love warm'),
  EmojiChoice('💛', 'Yellow heart', 'love friendship'),
  EmojiChoice('💚', 'Green heart', 'love nature'),
  EmojiChoice('💙', 'Blue heart', 'love trust'),
  EmojiChoice('💜', 'Purple heart', 'love care'),
  EmojiChoice('💔', 'Broken heart', 'sad love'),
  EmojiChoice('💯', 'One hundred', 'perfect agree score'),
  EmojiChoice('✨', 'Sparkles', 'shine magic new'),
  EmojiChoice('🎉', 'Party popper', 'celebrate confetti'),
  EmojiChoice('🎂', 'Birthday cake', 'party food'),
  EmojiChoice('🏆', 'Trophy', 'winner success award'),
  EmojiChoice('🔥', 'Fire', 'hot great trending'),
  EmojiChoice('💡', 'Light bulb', 'idea smart'),
  EmojiChoice('👀', 'Eyes', 'look watch curious'),
  EmojiChoice('👌', 'OK hand', 'okay agree good'),
  EmojiChoice('✅', 'Check mark', 'done yes complete'),
  EmojiChoice('❌', 'Cross mark', 'no wrong cancel'),
  EmojiChoice('⚠️', 'Warning', 'careful alert'),
  EmojiChoice('🚀', 'Rocket', 'launch fast travel'),
  EmojiChoice('🚲', 'Bicycle', 'travel ride sport'),
  EmojiChoice('🚗', 'Car', 'travel drive'),
  EmojiChoice('✈️', 'Airplane', 'travel flight'),
  EmojiChoice('🌍', 'Earth', 'world planet global'),
  EmojiChoice('☀️', 'Sun', 'weather bright morning'),
  EmojiChoice('🌙', 'Moon', 'night sleep'),
  EmojiChoice('⭐', 'Star', 'favorite night'),
  EmojiChoice('🌈', 'Rainbow', 'weather color hope'),
  EmojiChoice('🌱', 'Seedling', 'plant nature grow'),
  EmojiChoice('🌻', 'Sunflower', 'flower nature'),
  EmojiChoice('🐶', 'Dog', 'pet animal'),
  EmojiChoice('🐱', 'Cat', 'pet animal'),
  EmojiChoice('🍎', 'Apple', 'food fruit'),
  EmojiChoice('🍕', 'Pizza', 'food dinner'),
  EmojiChoice('🍰', 'Cake', 'food dessert'),
  EmojiChoice('☕', 'Coffee', 'drink cafe morning'),
  EmojiChoice('🥂', 'Cheers', 'drink celebrate'),
  EmojiChoice('⚽', 'Football', 'soccer sport'),
  EmojiChoice('🎮', 'Game controller', 'gaming play'),
  EmojiChoice('🎵', 'Music note', 'song audio'),
  EmojiChoice('📷', 'Camera', 'photo picture'),
];

class ExpressionPicker extends StatefulWidget {
  const ExpressionPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onStickerSelected,
  });

  final ValueChanged<String> onEmojiSelected;
  final Future<bool> Function(StickerDesign design) onStickerSelected;

  @override
  State<ExpressionPicker> createState() => _ExpressionPickerState();
}

class _ExpressionPickerState extends State<ExpressionPicker> {
  var _query = '';
  String? _busyStickerId;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final availableHeight = (mediaQuery.size.height - keyboardInset).clamp(
      360.0,
      620.0,
    );
    final emojis = wampAppEmojis
        .where((choice) => choice.matches(_query))
        .toList(growable: false);
    final stickers = wampAppStickers
        .where((design) => design.matches(_query))
        .toList(growable: false);
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: SizedBox(
            height: availableHeight * 0.82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Emoji & stickers',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('expression-close'),
                        tooltip: 'Close emoji and stickers',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  TextField(
                    key: const Key('expression-search'),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search expressions',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const TabBar(
                    tabs: [
                      Tab(
                        key: Key('expression-emoji-tab'),
                        icon: Icon(Icons.emoji_emotions_outlined),
                        text: 'Emoji',
                      ),
                      Tab(
                        key: Key('expression-sticker-tab'),
                        icon: Icon(Icons.auto_awesome_outlined),
                        text: 'Stickers',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _EmojiGrid(
                          choices: emojis,
                          onSelected: widget.onEmojiSelected,
                        ),
                        _StickerGrid(
                          designs: stickers,
                          busyStickerId: _busyStickerId,
                          onSelected: _selectSticker,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectSticker(StickerDesign design) async {
    if (_busyStickerId != null) return;
    setState(() => _busyStickerId = design.id);
    final accepted = await widget.onStickerSelected(design);
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busyStickerId = null);
  }
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({required this.choices, required this.onSelected});

  final List<EmojiChoice> choices;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty) return const _NoExpressions();
    return GridView.builder(
      key: const Key('expression-emoji-grid'),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 64,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: choices.length,
      itemBuilder: (context, index) {
        final choice = choices[index];
        return Semantics(
          button: true,
          label: choice.label,
          child: Tooltip(
            message: choice.label,
            child: InkWell(
              key: ValueKey('emoji-${choice.emoji}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => onSelected(choice.emoji),
              child: Center(
                child: Text(choice.emoji, style: const TextStyle(fontSize: 30)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({
    required this.designs,
    required this.busyStickerId,
    required this.onSelected,
  });

  final List<StickerDesign> designs;
  final String? busyStickerId;
  final ValueChanged<StickerDesign> onSelected;

  @override
  Widget build(BuildContext context) {
    if (designs.isEmpty) return const _NoExpressions();
    return GridView.builder(
      key: const Key('expression-sticker-grid'),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.94,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: designs.length,
      itemBuilder: (context, index) {
        final design = designs[index];
        final busy = busyStickerId == design.id;
        return Semantics(
          button: true,
          label: '${design.label} sticker',
          child: InkWell(
            key: ValueKey('sticker-${design.id}'),
            borderRadius: BorderRadius.circular(24),
            onTap: busyStickerId == null ? () => onSelected(design) : null,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [design.startColor, design.endColor],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: busy
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                design.emoji,
                                style: const TextStyle(fontSize: 58),
                              ),
                      ),
                    ),
                    Text(
                      design.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: design.foregroundColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoExpressions extends StatelessWidget {
  const _NoExpressions();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No matching expressions',
        key: Key('expression-empty'),
        textAlign: TextAlign.center,
      ),
    );
  }
}
