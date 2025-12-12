import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';

class CaptchaService {
  Interpreter? _interpreter;

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/digit_model.tflite');
      print("TFLite model loaded successfully.");
    } catch (e) {
      print("Error loading model: $e");
    }
  }

  Future<String?> solveCaptcha(Uint8List imageBytes) async {
    if (_interpreter == null) await loadModel();
    if (_interpreter == null) return null;

    final img.Image? fullImage = img.decodeImage(imageBytes);
    if (fullImage == null) return null;

    // Convert to grayscale (luminance)
    final img.Image grayImage = img.grayscale(fullImage);

    List<int> digits = [];

    for (var slice in AppConstants.digitSlices) {
      int xStart = slice[0];
      int xEnd = slice[1];
      int width = xEnd - xStart;
      int height = fullImage.height;

      // 1. Crop
      img.Image cropped = img.copyCrop(grayImage, x: xStart, y: 0, width: width, height: height);

      // 2. Pad to Square
      int maxSize = (width > height) ? width : height;
      img.Image padded = img.Image(width: maxSize, height: maxSize);
      // Fill with black (0) or white (255)? In Python verify we used cv2.BORDER_CONSTANT, value=0 (black).
      // Dart image defaults to 0 (transparent/black) usually, but let's be safe.
      img.fill(padded, color: img.ColorRgb8(0, 0, 0)); 
      
      // Center the crop in the square
      int dstX = (maxSize - width) ~/ 2;
      int dstY = (maxSize - height) ~/ 2;
      img.compositeImage(padded, cropped, dstX: dstX, dstY: dstY);

      // 3. Resize to 32x32
      img.Image resized = img.copyResize(padded, width: 32, height: 32);

      // 4. Normalize & Prepare Input
      // Model expects [1, 32, 32, 1] float32
      var input = List.generate(1, (i) => List.generate(32, (j) => List.generate(32, (k) => List.filled(1, 0.0))));
      
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          img.Pixel pixel = resized.getPixel(x, y);
          // Grayscale so r=g=b. Normalize 0..1
          input[0][y][x][0] = pixel.r / 255.0;
        }
      }

      // 5. Inference
      var output = List.filled(1, List.filled(10, 0.0));
      _interpreter!.run(input, output);

      // 6. Argmax
      double maxVal = -1.0;
      int maxIdx = -1;
      for (int i = 0; i < 10; i++) {
        if (output[0][i] > maxVal) {
          maxVal = output[0][i];
          maxIdx = i;
        }
      }
      digits.append(maxIdx);
    }

    if (digits.length != 3) return null;

    // xx + x logic
    int num1 = (digits[0] * 10) + digits[1];
    int num2 = digits[2];
    return (num1 + num2).toString();
  }
}

extension ListAppend on List<int> {
  void append(int val) => add(val);
}
