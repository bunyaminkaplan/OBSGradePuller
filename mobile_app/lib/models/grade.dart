class Grade {
  final String courseCode; // Added
  final String courseName;
  final String midterm;
  final String finalGrade;
  final String resit; // Butunleme
  final String letterGrade;
  final String average; // Ortalama column
  final String status; // Basarili/Basarisiz/Devamsiz
  final String termId; // Donem

  // Class Averages (Nullable)
  final String? midtermAvg;
  final String? finalAvg;
  final String? resitAvg;

  Grade({
    required this.courseCode, // Added
    required this.courseName,
    this.midterm = "-",
    this.finalGrade = "-",
    this.resit = "-",
    this.average = "-",
    this.letterGrade = "-",
    this.status = "-",
    this.termId = "",
    this.midtermAvg,
    this.finalAvg,
    this.resitAvg,
  });

  factory Grade.fromMap(Map<String, dynamic> map) {
    return Grade(
      courseCode: map['courseCode'] ?? "-", // Added
      courseName: map['courseName'] ?? "-",
      midterm: map['midterm'] ?? "-",
      finalGrade: map['finalGrade'] ?? "-",
      resit: map['resit'] ?? "-",
      average: map['average'] ?? "-",
      letterGrade: map['letterGrade'] ?? "-",
      status: map['status'] ?? "-",
      termId: map['termId'] ?? "",
      midtermAvg: map['midtermAvg'],
      finalAvg: map['finalAvg'],
      resitAvg: map['resitAvg'],
    );
  }
}
