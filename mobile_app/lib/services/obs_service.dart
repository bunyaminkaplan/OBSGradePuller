import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:html/parser.dart' show parse;
import '../core/constants.dart';
import 'storage_service.dart'; // Import storage service
import '../models/grade.dart';
import 'captcha_service.dart';

class ObsService {
  final Dio _dio = Dio(); // Changed from late to final and initialized
  late CookieJar _cookieJar;
  final CaptchaService _captchaService = CaptchaService();

  // Cache hidden inputs
  final StorageService _storageService = StorageService();

  String _baseUrl = "https://obs.ozal.edu.tr"; // Added
  final String _ozalUrl = "https://obs.ozal.edu.tr"; // Added
  final String _inonuUrl = "https://obs.inonu.edu.tr"; // Added

  // Cache hidden inputs for ViewState etc.
  Map<String, String> _hiddenInputs = {};

  Future<String> toggleUniversity() async {
    String newName;
    if (_baseUrl == _ozalUrl) {
      _baseUrl = _inonuUrl;
      newName = "İnönü Üniversitesi";
    } else {
      _baseUrl = _ozalUrl;
      newName = "Turgut Özal Üniversitesi";
    }
    // Save to storage
    await _storageService.saveUniversityUrl(_baseUrl);
    return newName;
  }

  Future<void> loadSavedUrl() async {
    String? saved = await _storageService.getUniversityUrl();
    if (saved != null && (saved == _ozalUrl || saved == _inonuUrl)) {
      _baseUrl = saved;
    }
  }

  ObsService() {
    // _dio = Dio(); // Removed as _dio is now final and initialized at declaration
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': "$_baseUrl/oibs/std/login.aspx",
      'Origin': _baseUrl,
      'Cache-Control': 'no-cache',
    };

    _cookieJar = CookieJar();
    _dio.interceptors.add(CookieManager(_cookieJar));

    // We will handle redirects manually for Login to ensure cookies stick
    _dio.options.followRedirects = true;
    _dio.options.validateStatus = (status) => status != null && status < 500;
  }

  /// Auto Login Loop with AI Captcha (Max 3 Attempts)
  Future<Map<String, dynamic>> autoLogin(String user, String pass) async {
    for (int i = 0; i < 3; i++) {
      print("Auto-Login Attempt ${i + 1}/3");

      // 1. Fetch Page & Captcha
      Uint8List? captchaImg = await fetchLoginPage();
      if (captchaImg == null) {
        print("Failed to fetch login page");
        await Future.delayed(Duration(seconds: 1));
        continue;
      }

      // 2. Solve Captcha (AI)
      String? code = await _captchaService.solveCaptcha(captchaImg);
      if (code == null) {
        print("AI failed to solve captcha");
        continue;
      }
      print("AI Predicted: $code");

      // 3. Attempt Login
      bool success = await login(user, pass, code);
      if (success) {
        return {'success': true, 'message': 'Success'};
      } else {
        print("Login failed (Wrong captcha or credentials)");
        // Wait a bit before retry
        await Future.delayed(Duration(milliseconds: 500));
      }
    }
    return {'success': false, 'message': 'Auto-login failed after 3 attempts'};
  }

  /// 1. Fetch Login Page
  Future<Uint8List?> fetchLoginPage() async {
    try {
      String loginUrl = "$_baseUrl/oibs/std/login.aspx";
      print("Fetching Login Page: $loginUrl");
      Response response = await _dio.get(loginUrl);

      var document = parse(response.data);

      _hiddenInputs.clear();
      var inputs = document.querySelectorAll('input[type="hidden"]');
      for (var input in inputs) {
        var name = input.attributes['name'];
        var value = input.attributes['value'];
        if (name != null) _hiddenInputs[name] = value ?? "";
      }

      // Extract Captcha
      var img = document.querySelector('#imgCaptchaImg');
      if (img != null) {
        String? src = img.attributes['src'];
        if (src != null) {
          String fullUrl = "$_baseUrl/oibs/captcha/CaptchaImg.aspx";
          if (!src.startsWith("..")) {
            fullUrl = "$_baseUrl/oibs/" + src.replaceAll("../", "");
          }
          Response<List<int>> imgResponse = await _dio.get<List<int>>(
            fullUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          return Uint8List.fromList(imgResponse.data!);
        }
      }
    } catch (e) {
      print("Login Page Error: $e");
    }
    return null;
  }

  /// 2. Login (Manual Redirect)
  Future<bool> login(String user, String pass, String captchaCode) async {
    if (_hiddenInputs.isEmpty) return false;

    try {
      Map<String, dynamic> payload = Map.from(_hiddenInputs);
      payload['txtParamT01'] = user;
      payload['txtParamT02'] = pass;
      payload['txtParamT1'] = pass;
      payload['txtSecCode'] = captchaCode;
      payload['__EVENTTARGET'] = 'btnLogin';
      payload['__EVENTARGUMENT'] = '';
      payload['txt_scrWidth'] = '1920';
      payload['txt_scrHeight'] = '1080';
      payload.remove('btnLogin');

      // Manual Redirect Step 1: POST
      Response response = await _dio.post(
        AppConstants.obsLoginUrl,
        data: FormData.fromMap(payload),
        options: Options(
          followRedirects: false, // Critical: Handle 302 manually
          validateStatus: (status) => true,
        ),
      );

      print("Login Status: ${response.statusCode}");

      if (response.statusCode == 302) {
        String? location = response.headers.value('location');
        print("Redirect Location: $location");
        if (location != null) {
          // Manual Redirect Step 2: GET Location
          // Cookies are auto-handled by CookieManager from the 302 response
          String fullUrl = location.startsWith("http")
              ? location
              : _baseUrl + location;

          Response nextResponse = await _dio.get(fullUrl);
          print("Redirect Target Status: ${nextResponse.statusCode}");
          print("Redirect Target URI: ${nextResponse.realUri}");

          if (!nextResponse.realUri.toString().contains("login.aspx")) {
            return true;
          }
        }
      } else if (response.statusCode == 200) {
        // Should have been a redirect on success, but check just in case
        if (!response.realUri.toString().contains("login.aspx")) return true;
      }

      return false; // Failed
    } catch (e) {
      print("Login Error: $e");
      return false;
    }
  }

  /// 3. Fetch Grades (Returns Grades + Terms Info)
  Future<Map<String, dynamic>> fetchGradesData({String? termId}) async {
    try {
      String gradesUrl = "$_baseUrl/oibs/std/not_listesi_op.aspx";
      _dio.options.headers['Referer'] = gradesUrl;

      // If a specific term is requested, we might need to POST
      // But typically we first GET the page, then if needed POST to change term.
      // Optimistically: If we pass 'cmbDonemler' in payload to a POST, it might switch.
      // But for safety:
      // 1. GET page.
      // 2. Check current term. If different from requested, POST to switch.
      // 3. Parse.

      Response response = await _dio.get(
        gradesUrl,
        options: Options(responseType: ResponseType.plain),
      );
      var document = parse(response.data);

      // Update hidden inputs
      _hiddenInputs.clear();
      for (var inp in document.querySelectorAll('input[type="hidden"]')) {
        var n = inp.attributes['name'];
        if (n != null) _hiddenInputs[n] = inp.attributes['value'] ?? "";
      }

      // Check Term and Switch if needed
      String currentTermId = "";
      var termSelect = document.querySelector('#cmbDonemler');

      // Extract Terms
      List<Map<String, String>> terms = [];
      if (termSelect != null) {
        var options = termSelect.querySelectorAll('option');
        for (var opt in options) {
          String val = opt.attributes['value'] ?? "";
          String text = opt.text.trim();
          bool isSelected = opt.attributes.containsKey('selected');
          if (val.isNotEmpty) {
            terms.add({'id': val, 'name': text});
            if (isSelected) currentTermId = val;
          }
        }
      }

      // If server didn't select one, pick the first (Usually active)
      if (currentTermId.isEmpty && terms.isNotEmpty) {
        currentTermId = terms.first['id']!;
      }

      // Switch Term Logic
      if (termId != null &&
          termId.isNotEmpty && // Prevent switching to empty
          termId != currentTermId &&
          _hiddenInputs.isNotEmpty) {
        // Perform POST to switch term
        print("Switching term from $currentTermId to $termId");
        Map<String, dynamic> payload = Map.from(_hiddenInputs);
        payload['__EVENTTARGET'] = 'cmbDonemler';
        payload['__EVENTARGUMENT'] = '';
        payload['cmbDonemler'] = termId;

        response = await _dio.post(
          gradesUrl,
          data: FormData.fromMap(payload),
          options: Options(responseType: ResponseType.plain),
        );
        document = parse(response.data);
        // Update inputs again
        _hiddenInputs.clear();
        for (var inp in document.querySelectorAll('input[type="hidden"]')) {
          var n = inp.attributes['name'];
          if (n != null) _hiddenInputs[n] = inp.attributes['value'] ?? "";
        }
        currentTermId = termId; // Assume success or re-check
      }

      var table = document.querySelector('#grd_not_listesi');
      List<Grade> grades = [];
      if (table != null) {
        var rows = table.querySelectorAll('tr');
        if (rows.length > 1) rows = rows.sublist(1);

        for (var row in rows) {
          var cells = row.querySelectorAll('td');
          if (cells.length < 7) continue;

          String getSafe(int idx) => cells[idx].text.trim();
          String courseCode = getSafe(1); // Explicitly separating Code
          String courseName = getSafe(2);
          String letterGrade = getSafe(6);
          String detailsText = getSafe(4);

          if (courseName.isEmpty) continue;

          String midterm = "-", finalG = "-", resit = "-";
          // Regex updated to support "Büt" as well as "Bütünleme"
          RegExp vizeReg = RegExp(
            r"(?:Ara Sınav|Vize)\s*:\s*([\d\w-]+)",
            caseSensitive: false,
          );
          RegExp finalReg = RegExp(
            r"(?:Yarıyıl Sonu|Final)\s*:\s*([\d\w-]+)",
            caseSensitive: false,
          );
          RegExp butReg = RegExp(
            r"(?:Bütünleme|Büt)\s*:\s*([\d\w-]+)",
            caseSensitive: false,
          );

          var vMatch = vizeReg.firstMatch(detailsText);
          if (vMatch != null) midterm = vMatch.group(1) ?? "-";
          var fMatch = finalReg.firstMatch(detailsText);
          if (fMatch != null) finalG = fMatch.group(1) ?? "-";
          var bMatch = butReg.firstMatch(detailsText);
          if (bMatch != null) resit = bMatch.group(1) ?? "-";

          // Find stats target string if available
          String? statsTarget;
          var statsBtn = row.querySelector("a[id*='btnIstatistik']");
          if (statsBtn != null) {
            String? href = statsBtn.attributes['href'];
            if (href != null) {
              RegExp pbReg = RegExp(r"__doPostBack\('([^']*)'");
              var match = pbReg.firstMatch(href);
              if (match != null) statsTarget = match.group(1);
            }
          }

          grades.add(
            Grade(
              courseCode: courseCode, // New field
              courseName: courseName,
              midterm: midterm,
              finalGrade: finalG,
              resit: resit,
              average: "",
              letterGrade: letterGrade,
              status: statsTarget ?? "",
              midtermAvg: null,
              finalAvg: null,
              resitAvg: null,
              termId: currentTermId,
            ),
          );
        }
      }

      return {'grades': grades, 'terms': terms, 'currentTerm': currentTermId};
    } catch (e) {
      // print("Fetch Grades Error: $e");
      return {
        'grades': <Grade>[],
        'terms': <Map<String, String>>[],
        'currentTerm': '',
      };
    }
  }

  // Deprecated alias for compatibility until fully refactored?
  // No, we will refactor usage in GradesScreen.
  Future<List<Grade>> fetchBasicGrades() async {
    var data = await fetchGradesData();
    return data['grades'];
  }

  /// 3b. Fetch Stats for a single Grade
  Future<Grade> fetchStatsForGrade(Grade grade) async {
    // Shimmer Fix: If no status (target), return with "-" averages so UI stops shimmering.
    if (grade.status.isEmpty || !grade.status.contains("btnIstatistik")) {
      return Grade(
        courseCode: grade.courseCode,
        courseName: grade.courseName,
        midterm: grade.midterm,
        finalGrade: grade.finalGrade,
        resit: grade.resit,
        average: grade.average,
        letterGrade: grade.letterGrade,
        status: "",
        termId: grade.termId,
        midtermAvg: "-", // Mark as empty/done
        finalAvg: "-",
        resitAvg: "-",
      );
    }

    String target = grade.status;
    String termId = grade.termId;

    try {
      // 1. Trigger AJAX
      String gradesUrl = "$_baseUrl/oibs/std/not_listesi_op.aspx";

      // ... (Logic from before)
      Map<String, dynamic> payload = Map.from(_hiddenInputs);
      payload['ScriptManager1'] = "UpdatePanel1|$target";
      payload['__EVENTTARGET'] = target;
      payload['__EVENTARGUMENT'] = '';
      payload['__ASYNCPOST'] = 'true';
      payload['cmbDonemler'] = termId;

      Map<String, dynamic> headers = Map.from(_dio.options.headers);
      headers['X-MicrosoftAjax'] = 'Delta=true';

      await _dio.post(
        gradesUrl,
        data: FormData.fromMap(payload),
        options: Options(headers: headers, responseType: ResponseType.plain),
      );

      // 2. Fetch Stats Page
      String statsUrl = "$_baseUrl/oibs/acd/new_not_giris_istatistik.aspx";
      Response statRes = await _dio.get(statsUrl);
      var soup = parse(statRes.data);
      var allRows = soup.querySelectorAll('tr');

      String? midtermAvg, finalAvg, resitAvg;
      String currentContext = ""; // Vize, Final, or But

      for (var row in allRows) {
        String t = row.text.trim();

        // Detect Context headers
        if (t.contains("Ara Sınav") || t.contains("Vize"))
          currentContext = "Vize";
        if (t.contains("Yarıyıl Sonu") || t.contains("Final"))
          currentContext = "Final";
        if (t.contains("Bütünleme") || t.contains("Büt"))
          currentContext = "Büt";

        // Check for Average Row
        // Matches "not ortalaması" OR "Sınava giren öğrencilerin not ortalaması"
        if (t.toLowerCase().contains("not ortalaması")) {
          var cols = row.querySelectorAll('td');
          // Value is usually in the 2nd column (index 1) or last column
          // User snippet: td[0] = text, td[1] = value (45,32)

          String val = "-";
          // Try finding the column with the value (usually aligns right or is 2nd)
          if (cols.length >= 2) {
            val = cols[1].text.trim();
          }

          if (val.isNotEmpty && val != "-") {
            if (currentContext == "Vize") midtermAvg = val;
            if (currentContext == "Final") finalAvg = val;
            if (currentContext == "Büt") resitAvg = val;
          }
        }
      }

      return Grade(
        courseCode: grade.courseCode,
        courseName: grade.courseName,
        midterm: grade.midterm,
        finalGrade: grade.finalGrade,
        resit: grade.resit,
        average: grade.average,
        letterGrade: grade.letterGrade,
        status: "", // Clear the target, it's processed.
        // If avg is null (not found), set to "-" to stop shimmer
        midtermAvg: midtermAvg ?? "-",
        finalAvg: finalAvg ?? "-",
        resitAvg: resitAvg ?? "-",
        termId: termId,
      );
    } catch (e) {
      print("Stats Error for ${grade.courseName}: $e");
      // Return with "-" so it stops loading
      return Grade(
        courseCode: grade.courseCode,
        courseName: grade.courseName,
        midterm: grade.midterm,
        finalGrade: grade.finalGrade,
        resit: grade.resit,
        average: grade.average,
        letterGrade: grade.letterGrade,
        status: "",
        midtermAvg: "-",
        finalAvg: "-",
        resitAvg: "-",
        termId: grade.termId,
      );
    }
  }

  /// 4. Logout (Unchanged)
  Future<void> logout() async {
    try {
      if (_hiddenInputs.isEmpty) return;

      print("Logging out...");
      Map<String, dynamic> payload = Map.from(_hiddenInputs);
      payload['__EVENTTARGET'] = 'btnLogout';
      payload['__EVENTARGUMENT'] = '';

      await _dio.post(
        "$_baseUrl/oibs/std/not_listesi_op.aspx",
        data: FormData.fromMap(payload),
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => true,
        ),
      );

      await _cookieJar.deleteAll();
      _hiddenInputs.clear();
      print("Logout complete.");
    } catch (e) {
      print("Logout Error: $e");
    }
  }
}
