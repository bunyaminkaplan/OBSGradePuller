class AppConstants {
  static const String obsLoginUrl =
      "https://obs.ozal.edu.tr/oibs/std/login.aspx";

  // Slicing Coordinates (x_start, x_end)
  // Height is always 40
  static const List<List<int>> digitSlices = [
    [13, 29], // Digit 1 (Width: 16)
    [29, 52], // Digit 2 (Width: 23)
    [88, 110], // Digit 3 (Width: 22)
  ];
}
