import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../services/obs_service.dart';
import '../models/grade.dart';
import 'login_screen.dart';

class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  List<Grade> _grades = [];
  List<Map<String, String>> _terms = [];
  String _currentTermId = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData({String? termId}) async {
    setState(() => _isLoading = true);
    final obs = context.read<ObsService>();
    if (termId != null) _currentTermId = termId;

    // 1. Fetch Basic List + Terms
    final data = await obs.fetchGradesData(termId: _currentTermId);

    if (mounted) {
      setState(() {
        _grades = data['grades'];
        _terms = data['terms'];
        // Only update current term if it was empty or changed by server
        if (_currentTermId.isEmpty) {
          _currentTermId = data['currentTerm'];
        }

        // If still empty (server didn't return selected option), use the first term (usually active)
        if (_currentTermId.isEmpty && _terms.isNotEmpty) {
          _currentTermId = _terms.first['id'] ?? "";
          // We might need to fetch again for this term if the initial fetch was generic?
          // Actually, initial fetch without termID usually gets the default page.
          // However, if we want the dropdown to show a value, we must set it.
          // If the initial fetch returned grades for this term, we are good.
          // If we suspect mismatch, we could trigger valid refresh, but let's assume first term matches initial page.
        }

        _isLoading = false;
      });
    }

    // 2. Fetch Stats Incrementally for current list
    // Create a copy to iterate safely
    List<Grade> currentList = List.from(_grades);
    for (int i = 0; i < currentList.length; i++) {
      if (!mounted) break;
      // Only fetch if it has a target
      if (currentList[i].status.isNotEmpty) {
        Grade updated = await obs.fetchStatsForGrade(currentList[i]);
        if (mounted) {
          // Find index again in case list changed (unlikely unless term changed mid-process)
          // But if term changed, _grades would be replaced and loop might be invalid?
          // We should check if termId matches?
          // For simplicity, if _currentTerm matches updated.termId
          if (_currentTermId == updated.termId) {
            int idx = _grades.indexWhere(
              (g) => g.courseCode == updated.courseCode,
            );
            if (idx != -1) {
              setState(() {
                _grades[idx] = updated;
              });
            }
          }
        }
      }
    }
  }

  Future<void> _performLogout() async {
    final obs = context.read<ObsService>();
    await obs.logout();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "Notlar",
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _fetchData(termId: _currentTermId),
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _performLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Term Selector UI (Moved here)
          if (_terms.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20), // More rounded
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currentTermId.isEmpty ? null : _currentTermId,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.blueAccent,
                  ),
                  isExpanded: true,
                  dropdownColor: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20), // Rounded Menu
                  elevation: 4,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  items: _terms.map((t) {
                    return DropdownMenuItem<String>(
                      value: t['id'],
                      child: Text(
                        t['name'] ?? "",
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null && val != _currentTermId) {
                      _fetchData(termId: val);
                    }
                  },
                ),
              ),
            ),

          // Loading or List
          Expanded(
            child: _isLoading
                ? _buildShimmerList()
                : _grades.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.class_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Bu dönem için not bulunamadı.",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _grades.length,
                    itemBuilder: (context, index) {
                      return GradeCard(grade: _grades[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
          child: Container(
            height: 154,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      },
    );
  }
}

class GradeCard extends StatelessWidget {
  final Grade grade;
  const GradeCard({super.key, required this.grade});

  Color _getStatusColor(String letter) {
    if (letter.startsWith('A')) return const Color(0xFF43A047);
    if (letter.startsWith('B')) return const Color(0xFF7CB342);
    if (letter.startsWith('C')) return const Color(0xFFFDD835);
    if (letter.startsWith('D')) return const Color(0xFFFB8C00);
    if (letter.startsWith('F')) return const Color(0xFFE53935);
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(grade.letterGrade);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Choose appropriate background color for dark mode
    // Using a slightly lighter grey for cards in dark mode if cardColor is pure surface
    final cardBg = Theme.of(context).cardColor;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;

    bool hasResit = grade.resit != "-" && grade.resit.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.grey.withOpacity(0.2), // Stronger border
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey[100]!,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Align center vertically
              children: [
                Expanded(
                  child: Row(
                    // Nested Row for Name - Code layout
                    children: [
                      // Course Name
                      Flexible(
                        child: Text(
                          grade.courseName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15, // Slightly smaller to fit
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Course Code - Faint and Small - Middle Vertical
                      Text(
                        "- ${grade.courseCode}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    grade.letterGrade,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GradeItem(
                  label: "Ara Sınav",
                  value: grade.midterm,
                  avg: grade.midtermAvg,
                  showAvg: true,
                ),
                // Final acts as main unless Resit is present
                _GradeContainer(
                  label: "Final",
                  value: grade.finalGrade,
                  avg: grade.finalAvg,
                  isMain: !hasResit, // Main ONLY if no resit
                ),
                // Resit acts as main if present
                hasResit
                    ? _GradeContainer(
                        label: "Bütünleme", // Highlighted
                        value: grade.resit,
                        avg: grade.resitAvg,
                        isMain: true,
                      )
                    : _GradeItem(
                        label: "Bütünleme",
                        value: grade.resit,
                        avg: grade.resitAvg,
                        showAvg: true,
                      ),
              ],
            ),
          ),
          // Footer
          if (grade.average.isNotEmpty && grade.average != "-")
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black26
                    : Colors.grey[50], // Darker footer for dark mode
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    "Ortalama:", // Kept Ortalama per request? Or "Başarı Notu"
                    // User said: "her card in altina kac ile gectigimi de yazar misin"
                    // "Pass Grade Display": Ensure "Ortalama / Geçme Notu"
                    // Let's use "Ortalama" for the value, and add Status text.
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    grade.average,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 1,
                    height: 16,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    grade.status, // "Geçti" / "Kaldı"
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(grade.letterGrade),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GradeContainer extends StatelessWidget {
  final String label;
  final String value;
  final String? avg;
  final bool isMain;

  const _GradeContainer({
    required this.label,
    required this.value,
    this.avg,
    this.isMain = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GradeItem(
      label: label,
      value: value,
      avg: avg,
      isMain: isMain,
      showAvg: true,
    );
  }
}

class _GradeItem extends StatelessWidget {
  final String label;
  final String value;
  final String? avg;
  final bool isMain;
  final bool showAvg;

  const _GradeItem({
    required this.label,
    required this.value,
    this.avg,
    this.isMain = false,
    this.showAvg = false,
  });

  double? _parse(String s) {
    if (s.isEmpty || s == "-") return null;
    s = s.replaceAll(',', '.');
    s = s.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;

    double? myVal = _parse(value);
    double? avgVal = (avg != null && avg != "?" && avg != "-")
        ? _parse(avg!)
        : null;

    IconData? comparisonIcon;
    Color? comparisonColor;

    if (myVal != null && avgVal != null) {
      if (myVal > avgVal) {
        comparisonIcon = Icons.arrow_upward_rounded;
        comparisonColor = Colors.green;
      } else if (myVal < avgVal) {
        comparisonIcon = Icons.arrow_downward_rounded;
        comparisonColor = Colors.red;
      }
    }

    bool hasGrade = (value.isNotEmpty && value != "-" && value != "Girilmedi");

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: isMain ? 80 : 72,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isMain
                ? (isDark ? Colors.blue.withOpacity(0.1) : Colors.blue[50])
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isMain
                ? Border.all(
                    color: isDark
                        ? Colors.blueAccent.withOpacity(0.5)
                        : Colors.blue[100]!,
                  )
                : null,
          ),
          child: Column(
            children: [
              Text(
                value.isEmpty ? "-" : value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isMain ? 18 : 16,
                  color: isMain
                      ? Colors.blueAccent
                      : textColor, // Use blueAccent for better dark readability
                ),
              ),
              if (showAvg && hasGrade) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 16,
                  child: avg == null
                      ? Shimmer.fromColors(
                          baseColor: isDark
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                          highlightColor: isDark
                              ? Colors.grey[600]!
                              : Colors.grey[100]!,
                          child: Container(
                            width: 40,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              (avg == "?" || avg == "-") ? "-" : avg!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                            if (comparisonIcon != null) ...[
                              const SizedBox(width: 2),
                              Icon(
                                comparisonIcon,
                                size: 12,
                                color: comparisonColor,
                              ),
                            ],
                          ],
                        ),
                ),
              ] else if (showAvg && !hasGrade) ...[
                const SizedBox(height: 0),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
