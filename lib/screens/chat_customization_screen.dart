import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class ChatCustomizationScreen extends StatefulWidget {
  const ChatCustomizationScreen({super.key});

  @override
  State<ChatCustomizationScreen> createState() => _ChatCustomizationScreenState();
}

class _ChatCustomizationScreenState extends State<ChatCustomizationScreen> {
  final SettingsService _settingsService = SettingsService();
  late ChatCustomization _customization;

  final List<BackgroundOption> _backgroundOptions = [
    BackgroundOption('Мятный', const Color(0xFFE8F5E9), null),
    BackgroundOption('Нежно-голубой', const Color(0xFFE3F2FD), null),
    BackgroundOption('Лавандовый', const Color(0xFFF3E5F5), null),
    BackgroundOption('Персиковый', const Color(0xFFFFF3E0), null),
    BackgroundOption('Белый с точками', Colors.white, 'dots'),
    BackgroundOption('Серый с сеткой', const Color(0xFFF5F5F5), 'grid'),
    BackgroundOption('Синий с волнами', const Color(0xFFE1F5FE), 'waves'),
    BackgroundOption('Розовый с сердечками', const Color(0xFFFCE4EC), 'hearts'),
  ];

  @override
  void initState() {
    super.initState();
    _customization = _settingsService.chatCustomization;
  }

  void _updateCustomization(ChatCustomization newCustomization) {
    setState(() {
      _customization = newCustomization;
    });
    _settingsService.setChatCustomization(newCustomization);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Кастомизация чата'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreview(),
            const SizedBox(height: 24),
            _buildSectionTitle('Форма сообщений'),
            const SizedBox(height: 12),
            _buildBorderRadiusSelector(),
            const SizedBox(height: 24),
            _buildSectionTitle('Фон чата'),
            const SizedBox(height: 12),
            _buildBackgroundSelector(),
            const SizedBox(height: 24),
            _buildSectionTitle('Размер текста'),
            const SizedBox(height: 12),
            _buildTextSizeSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerTheme.color!),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.preview, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Предпросмотр',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: _customization.backgroundColor,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Stack(
              children: [
                if (_customization.patternType != null)
                  _buildPattern(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPreviewMessage(
                        'Привет! Как дела?',
                        true,
                        const Color(0xFF2196F3),
                      ),
                      const SizedBox(height: 12),
                      _buildPreviewMessage(
                        'Привет! Все отлично, спасибо!',
                        false,
                        Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPattern() {
    IconData iconData;
    Color patternColor = Colors.black.withOpacity(0.05);
    
    switch (_customization.patternType) {
      case 'dots':
        return CustomPaint(
          size: Size.infinite,
          painter: DotsPatternPainter(color: patternColor),
        );
      case 'grid':
        return CustomPaint(
          size: Size.infinite,
          painter: GridPatternPainter(color: patternColor),
        );
      case 'waves':
        return CustomPaint(
          size: Size.infinite,
          painter: WavesPatternPainter(color: patternColor),
        );
      case 'hearts':
        iconData = Icons.favorite;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Icon(
      iconData,
      color: patternColor,
      size: 24,
    );
  }

  Widget _buildPreviewMessage(String text, bool isSent, Color bgColor) {
    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isSent ? 16 : 4),
            bottomRight: Radius.circular(isSent ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSent ? Colors.white : Colors.black87,
            fontSize: _customization.messageTextSize,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _buildBorderRadiusSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Скругление углов'),
              Text(
                '${_customization.borderRadius.toInt()} px',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _customization.borderRadius,
            min: 0,
            max: 32,
            divisions: 32,
            onChanged: (value) {
              _updateCustomization(_customization.copyWith(borderRadius: value));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildRadiusPreview(0, 'Квадрат'),
              _buildRadiusPreview(8, 'Среднее'),
              _buildRadiusPreview(16, 'Скругленное'),
              _buildRadiusPreview(24, 'Сильное'),
              _buildRadiusPreview(32, 'Максимум'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusPreview(double radius, String label) {
    final isSelected = _customization.borderRadius == radius;
    return GestureDetector(
      onTap: () {
        _updateCustomization(_customization.copyWith(borderRadius: radius));
      },
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(radius),
              border: isSelected
                  ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _backgroundOptions.map((option) {
          final isSelected = _customization.backgroundColor == option.color &&
              _customization.patternType == option.patternType;
          return GestureDetector(
            onTap: () {
              _updateCustomization(_customization.copyWith(
                backgroundColor: option.color,
                patternType: option.patternType,
              ));
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: option.color,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : Border.all(
                        color: Theme.of(context).dividerTheme.color!,
                        width: 1,
                      ),
              ),
              child: option.patternType != null
                  ? Center(
                      child: _buildPatternIcon(option.patternType!),
                    )
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPatternIcon(String patternType) {
    IconData iconData;
    switch (patternType) {
      case 'dots':
        iconData = Icons.circle;
        break;
      case 'grid':
        iconData = Icons.grid_on;
        break;
      case 'waves':
        iconData = Icons.waves;
        break;
      case 'hearts':
        iconData = Icons.favorite;
        break;
      default:
        iconData = Icons.texture;
    }
    return Icon(iconData, color: Colors.black26, size: 32);
  }

  Widget _buildTextSizeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Размер текста сообщений'),
              Text(
                '${_customization.messageTextSize.toInt()} px',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _customization.messageTextSize,
            min: 12,
            max: 24,
            divisions: 12,
            onChanged: (value) {
              _updateCustomization(_customization.copyWith(messageTextSize: value));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BackgroundOption {
  final String name;
  final Color color;
  final String? patternType;

  BackgroundOption(this.name, this.color, this.patternType);
}

class DotsPatternPainter extends CustomPainter {
  final Color color;

  DotsPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GridPatternPainter extends CustomPainter {
  final Color color;

  GridPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const spacing = 30.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter) => false;
}

class WavesPatternPainter extends CustomPainter {
  final Color color;

  WavesPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    for (double y = 0; y < size.height; y += spacing) {
      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x < size.width; x += 20) {
        path.quadraticBezierTo(
          x + 10, y + 10,
          x + 20, y,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
