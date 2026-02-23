import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:opencv_dart/opencv.dart' as cv;

class ScanerPage extends StatefulWidget {
  const ScanerPage({super.key});
  @override
  State<ScanerPage> createState() => _ScanerPageState();
}

class _ScanerPageState extends State<ScanerPage> {
  CameraController? controller;
  List<Offset> points = [];
  List<CameraDescription> cameras = [];

  @override
  void initState() async {
    super.initState();
    cameras = await availableCameras();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    controller!.initialize().then((_) async {
      if (!mounted) return;
      // capture current camera preview every half-second
      Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        final boundary =
            previewContainerKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();
        _processCameraImage(pngBytes);
      });
      setState(() {});
    });
  }

  void _processCameraImage(Uint8List cameraImage) async {
    try {
      final mat = cv.imdecode(cameraImage, cv.IMREAD_COLOR);
      final gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
      final blurred = cv.gaussianBlur(gray, (3, 3), 0);
      final edges = cv.canny(blurred, 100, 200);
      final nonZeroMat = cv.findNonZero(edges);
      if (nonZeroMat.isEmpty) return;
      final edgePoints = <Offset>[];
      for (int i = 0; i < nonZeroMat.rows; i++) {
        final row = nonZeroMat.row(i);
        final x = row.at<int>(0, 0);
        final y = row.at<int>(0, 1);
        edgePoints.add(Offset(x.toDouble(), y.toDouble()));
      }
      setState(() {
        points = getCorrectedCorners(edgePoints);
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  List<Offset> getCorrectedCorners(List<Offset> points) {
    double minX = points.map((p) => p.dx).reduce(min);
    double maxX = points.map((p) => p.dx).reduce(max);
    double minY = points.map((p) => p.dy).reduce(min);
    double maxY = points.map((p) => p.dy).reduce(max);
    Offset topLeft = Offset(minX, minY);
    Offset topRight = Offset(maxX, minY);
    Offset bottomLeft = Offset(minX, maxY);
    Offset bottomRight = Offset(maxX, maxY);
    Offset findClosestPoint(Offset target) {
      return points.reduce(
        (a, b) => (a - target).distance < (b - target).distance ? a : b,
      );
    }

    return [
      points.contains(topLeft) ? topLeft : findClosestPoint(topLeft),
      points.contains(topRight) ? topRight : findClosestPoint(topRight),
      points.contains(bottomRight)
          ? bottomRight
          : findClosestPoint(bottomRight),
      points.contains(bottomLeft) ? bottomLeft : findClosestPoint(bottomLeft),
    ];
  }

  GlobalKey previewContainerKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Live Edge Detection")),
      body: Stack(
        children: [
          RepaintBoundary(
            key: previewContainerKey,
            child: CameraPreview(controller!),
          ),
          CustomPaint(painter: LinePainter(points), child: Container()),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

class LinePainter extends CustomPainter {
  final List<Offset> points;
  LinePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    double pointerSize = 8.0;
    Paint circlePaint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 10
      ..style = PaintingStyle.fill;
    if (points.length >= 4) {
      drawDashedLine(canvas, points[0], points[1]);
      drawDashedLine(canvas, points[1], points[2]);
      drawDashedLine(canvas, points[2], points[3]);
      drawDashedLine(canvas, points[3], points[0]);
      for (final point in points) {
        canvas.drawCircle(point, pointerSize, circlePaint);
      }
    }
  }

  void drawDashedLine(Canvas canvas, Offset start, Offset end) {
    final delta = end - start;
    final length = delta.distance;
    final direction = delta / length;
    const dashLength = 15;
    double distance = 0;
    while (distance < length) {
      final currentStart = start + direction * distance;
      final currentEnd = start + direction * min(distance + dashLength, length);
      canvas.drawLine(
        currentStart,
        currentEnd,
        Paint()
          ..color = Colors.cyan
          ..strokeWidth = 4,
      );
      distance += dashLength * 2;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
