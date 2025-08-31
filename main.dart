import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Advanced Image Editor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ImageEditorPage(),
    );
  }
}

class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage({super.key});

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  File? _image;
  final GlobalKey _editorKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

  double _brightness = 0.0;
  double _contrast = 1.0;
  double _saturation = 1.0;

  final List<Offset?> _points = [];

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _captureImage() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _saveImage() async {
    try {
      RenderRepaintBoundary boundary =
          _editorKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      String filename = '${const Uuid().v4()}.png';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(pngBytes);

      await GallerySaver.saveImage(file.path);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Image Saved to Gallery')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  List<double> _colorMatrix() {
    final s = _saturation;
    final ls = 0.2126 * (1 - s);
    final ms = 0.7152 * (1 - s);
    final ns = 0.0722 * (1 - s);

    final sat = [
      ls + s, ms, ns, 0.0, 0.0,
      ls, ms + s, ns, 0.0, 0.0,
      ls, ms, ns + s, 0.0, 0.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];

    final c = _contrast;
    final t = (1.0 - c) * 0.5 * 255.0;
    final contrast = [
      c, 0.0, 0.0, 0.0, t,
      0.0, c, 0.0, 0.0, t,
      0.0, 0.0, c, 0.0, t,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];

    final b = _brightness * 255.0;
    final bright = [
      1.0, 0.0, 0.0, 0.0, b,
      0.0, 1.0, 0.0, 0.0, b,
      0.0, 0.0, 1.0, 0.0, b,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];

    return _matrixMultiply(bright, _matrixMultiply(contrast, sat));
  }

  List<double> _matrixMultiply(List<double> a, List<double> b) {
    List<double> result = List.filled(20, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        result[i * 5 + j] = 0.0;
        for (int k = 0; k < 4; k++) {
          result[i * 5 + j] += a[i * 5 + k] * b[k * 5 + j];
        }
        if (j == 4) result[i * 5 + j] += a[i * 5 + 4];
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Image Editor'),
        actions: [
          IconButton(
              icon: const Icon(Icons.camera),
              onPressed: _captureImage),
          IconButton(
              icon: const Icon(Icons.photo),
              onPressed: _pickImage),
          IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveImage),
        ],
      ),
      body: _image == null
          ? const Center(child: Text('Pick or Capture an Image'))
          : Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    key: _editorKey,
                    child: Stack(
                      children: [
                        ColorFiltered(
                          colorFilter: ColorFilter.matrix(_colorMatrix()),
                          child: Image.file(_image!, fit: BoxFit.contain),
                        ),
                        GestureDetector(
                          onPanUpdate: (details) {
                            RenderBox renderBox =
                                context.findRenderObject() as RenderBox;
                            setState(() {
                              _points.add(renderBox.globalToLocal(
                                  details.globalPosition));
                            });
                          },
                          onPanEnd: (details) => _points.add(null),
                          child: CustomPaint(
                            painter: DrawingPainter(_points),
                            child: Container(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Slider(
                  value: _brightness,
                  min: -1.0,
                  max: 1.0,
                  label: 'Brightness',
                  onChanged: (v) => setState(() => _brightness = v),
                ),
                Slider(
                  value: _contrast,
                  min: 0.0,
                  max: 4.0,
                  label: 'Contrast',
                  onChanged: (v) => setState(() => _contrast = v),
                ),
                Slider(
                  value: _saturation,
                  min: 0.0,
                  max: 2.0,
                  label: 'Saturation',
                  onChanged: (v) => setState(() => _saturation = v),
                ),
              ],
            ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset?> points;

  DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}
