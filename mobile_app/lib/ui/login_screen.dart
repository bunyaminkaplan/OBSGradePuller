import 'dart:math' as math; // For random shake
import 'dart:typed_data';
import 'dart:async'; // For Timer Easter Egg
import 'package:flutter/services.dart'; // For HapticFeedback
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../services/obs_service.dart';
import '../services/captcha_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import 'grades_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _captchaController = TextEditingController();
  final _aliasController = TextEditingController();
  final _storage = StorageService();

  late AnimationController _vibrationController;
  late AnimationController _buttonJitterController; // Continuous jitter
  late AnimationController _rippleController; // RIPPLE

  Uint8List? _captchaImage;
  bool _isLoading = false;
  String _status = "";

  List<Map<String, String>> _profiles = [];
  bool _showManualLogin = false;
  bool _rememberMe = false;

  // Linear Menu State
  bool _showMenu = false;
  int? _hoveredIndex;
  bool _showHint = true; // Show hint initially
  Timer? _easterEggTimer; // For 5s hold

  @override
  void initState() {
    super.initState();
    _loadProfiles();

    // Menu Item Shake: Fast, aggressive loop
    _vibrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: -1.0,
      upperBound: 1.0,
    );

    // Button Jitter: Slow, random-like loop
    _buttonJitterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..repeat();

    // Water Ripple: Slow, breathing loop
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _vibrationController.dispose();
    _buttonJitterController.dispose();
    _rippleController.dispose();
    _userController.dispose();
    _passController.dispose();
    _captchaController.dispose();
    _aliasController.dispose();
    _easterEggTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final list = await _storage.getProfiles();

    // RENAME Legacy replacement
    for (var p in list) {
      if (p['alias'] == 'Varsayılan' && p['username'] == '02230202057') {
        p['alias'] = 'Bunyamin';
      }
    }

    // Check persistence for hint
    final showHint = await _storage.shouldShowHint();

    // RESTORE SAVED UNIVERSITY
    if (mounted) {
      await context.read<ObsService>().loadSavedUrl();
    }

    if (mounted) {
      setState(() {
        _profiles = list;
        _showHint = showHint; // Set based on storage
        if (_profiles.isEmpty) {
          _showManualLogin = true;
          _loadCaptcha();
        } else {
          _showManualLogin = false;
        }
      });
    }
  }

  Future<void> _loadCaptcha() async {
    if (!mounted) return;
    setState(() {
      _status = "";
      _captchaImage = null;
    });

    final obs = context.read<ObsService>();
    final solver = context.read<CaptchaService>();

    final bytes = await obs.fetchLoginPage();

    if (bytes != null) {
      if (!mounted) return;
      setState(() => _captchaImage = bytes);

      // We can optionally show "Solving..." but user asked to remove text if possible or avoid jump.
      // Let's just keep status empty effectively unless error.
      // setState(() => _status = "AI Çözüyor...");
      final result = await solver.solveCaptcha(bytes);

      if (mounted) {
        if (result != null) {
          _captchaController.text = result;
          // setState(() => _status = "");
        } else {
          setState(() => _status = "AI Okuyamadı");
        }
      }
    } else {
      if (mounted) setState(() => _status = "Hata");
    }
  }

  Future<void> _login({String? user, String? pass}) async {
    bool isAuto = (user != null && pass != null);
    String username = user ?? _userController.text;
    String password = pass ?? _passController.text;
    String captcha = isAuto ? "" : _captchaController.text;

    setState(() {
      _isLoading = true;
      _status = "Giriş Yapılıyor...";
      _showMenu = false;
      _stopVibration();
    });

    final obs = context.read<ObsService>();
    bool success;

    if (isAuto) {
      var res = await obs.autoLogin(username, password);
      success = res['success'];
      if (!success) _status = res['message'] ?? "Hata";
    } else {
      success = await obs.login(username, password, captcha);
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        if (!isAuto && _rememberMe) {
          String alias = _aliasController.text.trim();
          if (alias.isEmpty) alias = username; // Default to username if empty
          await _storage.saveProfile(username, password, alias);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GradesScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GradesScreen()),
          );
        }
      } else {
        if (!isAuto) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Giriş Başarısız! Bilgileri kontrol edin."),
            ),
          );
          _loadCaptcha();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_status)));
        }
      }
    }
  }

  void _startVibration() {
    if (!_vibrationController.isAnimating) {
      _vibrationController.repeat(reverse: true);
    }
  }

  void _stopVibration() {
    _vibrationController.stop();
    _vibrationController.reset();
  }

  // Removed _askAliasAndSave

  // --- LINEAR MENU LOGIC ---

  // We assume the button is ~120height. The menu will appear at the "SEÇ" button position.
  // Actually, let's just center it on screen or below the button.
  // BUT: The user asked for it to open "right there".
  // Since we use a Stack, we can position it centrally in the stack or use ComposedTransformTarget.
  // For simplicity and robustness: Center of screen or fixed offset.
  // Let's rely on the Stack centering.

  @override
  Widget build(BuildContext context) {
    bool showProfiles = _profiles.isNotEmpty && !_showManualLogin;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: isDark ? Colors.grey[800] : Colors.black,
        child: Icon(
          isDark ? Icons.light_mode : Icons.dark_mode,
          color: Colors.white,
        ),
        onPressed: () {
          context.read<ThemeService>().toggleTheme();
        },
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // WATER RIPPLE LOGO
                    Listener(
                      onPointerDown: (_) {
                        _easterEggTimer?.cancel();
                        _easterEggTimer = Timer(
                          const Duration(seconds: 5),
                          () async {
                            // Trigger
                            final obs = context.read<ObsService>();
                            final uniName = await obs.toggleUniversity();
                            if (mounted) {
                              HapticFeedback.heavyImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("$uniName Moduna Geçildi"),
                                  backgroundColor: Colors.blueAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              // Refresh captcha immediately for new university
                              _loadCaptcha();
                            }
                          },
                        );
                      },
                      onPointerUp: (_) => _easterEggTimer?.cancel(),
                      onPointerCancel: (_) => _easterEggTimer?.cancel(),
                      child: SizedBox(
                        width: 180, // Slightly larger paint area
                        height: 180,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _rippleController,
                              builder: (context, child) {
                                return CustomPaint(
                                  painter: RipplePainter(
                                    _rippleController.value,
                                    Colors.blueAccent,
                                  ),
                                  child: Container(width: 180, height: 180),
                                );
                              },
                            ),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                size: 64,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text(
                      "OBS Ozal",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 48),

                    if (_isLoading && showProfiles)
                      const CircularProgressIndicator()
                    else if (showProfiles)
                      _buildLinearTrigger()
                    else
                      _buildManualLoginUI(),

                    if (_status.isNotEmpty &&
                        !_isLoading &&
                        _status != "Captcha Yükleniyor...") ...[
                      const SizedBox(height: 16),
                      Text(
                        _status,
                        style: TextStyle(color: Colors.red[600], fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          if (_showMenu)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 5.0),
                duration: const Duration(milliseconds: 200),
                builder: (context, sigma, child) {
                  return BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: Container(
                      color: Colors.black12.withOpacity(sigma / 5 * 0.12),
                      alignment: Alignment.center,
                      child: _buildLinearMenuVisual(),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinearTrigger() {
    return Column(
      children: [
        if (_showHint)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Hesap seçmek için basılı tutun",
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),

        Listener(
          onPointerDown: (_) {
            setState(() {
              _showMenu = true;
              _hoveredIndex = -1;
              _showHint = false; // Hide hint after interaction
            });
            _startVibration(); // Start shaking everything immediately
          },
          onPointerMove: (event) {
            final screenHeight = MediaQuery.of(context).size.height;
            final menuHeight = _profiles.length * 70.0;
            final menuTop = (screenHeight - menuHeight) / 2;

            double localY = event.position.dy - menuTop;

            int idx = (localY / 70.0).floor();
            if (idx < 0 || idx >= _profiles.length) idx = -1;

            // BUG FIX: Don't stop vibration if idx == -1.
            // Just update index so the builder handles the 0.5x logic.
            if (_hoveredIndex != idx) {
              setState(() => _hoveredIndex = idx);
            }
          },
          onPointerUp: (event) {
            _stopVibration(); // Stop animation
            if (_showMenu) {
              if (_hoveredIndex != null &&
                  _hoveredIndex! >= 0 &&
                  _hoveredIndex! < _profiles.length) {
                // User successfully used the feature
                _storage.setHintShown();
                final p = _profiles[_hoveredIndex!];
                _login(user: p['username'], pass: p['password']);
              }
              setState(() => _showMenu = false);
            }
          },
          onPointerCancel: (_) {
            _stopVibration();
            setState(() => _showMenu = false);
          },
          child: SizedBox(
            width: 200,
            height: 60,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Layer 0: Calmer Jitter Background
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _buttonJitterController,
                    builder: (context, child) {
                      // Reduced Amplitude: 6.0 -> 2.0
                      double offsetX = (math.Random().nextDouble() - 0.5) * 2.0;
                      double offsetY = (math.Random().nextDouble() - 0.5) * 2.0;

                      return Transform.translate(
                        offset: Offset(offsetX, offsetY),
                        child: Container(
                          decoration: BoxDecoration(
                            // Dark Mode: Transparent BG. Light Mode: White cards.
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.transparent
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withOpacity(0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                            border: Border.all(
                              color: Colors.blueAccent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Layer 1: Skewed Text Content
                Center(
                  child: AnimatedBuilder(
                    animation: _buttonJitterController,
                    builder: (context, child) {
                      // Skew Text: Random small skew based on jitter controller
                      // Range: -0.1 to 0.1
                      double skewX = (math.Random().nextDouble() - 0.5) * 0.2;
                      return Transform(
                        transform: Matrix4.skewX(skewX),
                        alignment: Alignment.center,
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.people_alt_rounded,
                          color: Colors.blueAccent,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Kayıtlı Kullanıcılar",
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 30),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _showManualLogin = true;
              _userController.clear();
              _passController.clear();
              _loadCaptcha();
            });
          },
          icon: const Icon(Icons.person_add),
          label: const Text("Farklı Hesapla Giriş"),
        ),
      ],
    );
  }

  Widget _buildLinearMenuVisual() {
    double itemHeight = 70.0;

    return Container(
      width: 280,
      constraints: BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]!.withOpacity(0.95)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 30, spreadRadius: 5),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_profiles.length, (index) {
          bool isHovered = (_hoveredIndex == index);
          final p = _profiles[index];

          // Item UI
          Widget itemContent = Container(
            height: itemHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isHovered
                  ? Colors.blueAccent.withOpacity(0.1)
                  : Colors.transparent,
              border: index < _profiles.length - 1
                  ? Border(
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
                    )
                  : null,
              borderRadius: BorderRadius.vertical(
                top: index == 0 ? Radius.circular(20) : Radius.zero,
                bottom: index == _profiles.length - 1
                    ? Radius.circular(20)
                    : Radius.zero,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isHovered
                      ? Colors.blueAccent
                      : Colors.grey[300],
                  foregroundColor: isHovered ? Colors.white : Colors.grey[700],
                  child: Text(p['alias']!.substring(0, 1).toUpperCase()),
                ),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['alias']!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isHovered
                            ? Colors.blueAccent
                            : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    Text(
                      p['username']!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const Spacer(),
                if (isHovered)
                  const Icon(Icons.check_circle, color: Colors.blueAccent),
              ],
            ),
          );

          // Shaking Logic
          return AnimatedBuilder(
            animation: _vibrationController,
            builder: (context, child) {
              // User requested 0.3x for inactive items.
              // Removed roundToDouble to allow micro-vibrations.
              double amplitude = isHovered ? 2.0 : 0.3;
              double offsetVal = _vibrationController.value * amplitude;

              return Transform.translate(
                offset: Offset(offsetVal, 0),
                child: child,
              );
            },
            child: itemContent,
          );
        }),
      ),
    );
  }

  Widget _buildManualLoginUI() {
    return Column(
      children: [
        if (_isLoading) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status),
        ] else ...[
          _buildTextField(
            controller: _userController,
            label: "Öğrenci No",
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _passController,
            label: "Şifre",
            icon: Icons.lock_outline,
            obscure: true,
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Container(
                height: 56,
                width: 120,
                decoration: BoxDecoration(
                  // Dark mode aware border and bg
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.withOpacity(0.3)
                        : Colors.grey[300]!,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]
                      : Colors.white,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: _captchaImage != null
                      ? Image.memory(
                          _captchaImage!,
                          fit: BoxFit.fill,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.red[100],
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.red,
                              ),
                            );
                          },
                        )
                      : Shimmer.fromColors(
                          baseColor: Colors.grey[300]!,
                          highlightColor: Colors.grey[100]!,
                          // Solid box for shimmer, no text
                          child: Container(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[700]
                                : Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _captchaController,
                  label: "Kod",
                  icon: Icons.vpn_key_outlined,
                  action: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadCaptcha,
                  ),
                ),
              ),
            ],
          ),

          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
              ),
              const Text("Beni Hatırla"),
            ],
          ),

          // INLINE ALIAS INPUT - Animated
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _rememberMe
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: TextField(
                      controller: _aliasController,
                      decoration: InputDecoration(
                        labelText: "Hesap İsmi (Örn: Okul)",
                        hintText: "Listede görünecek isim",
                        prefixIcon: const Icon(Icons.label_outline),
                        filled: true,
                        fillColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[800]
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 8), // Adjusted spacing
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => _login(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                "Giriş Yap",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (_profiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showManualLogin = false;
                  // No need to clear controllers here, but fine if we do.
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text("Kayıtlı Hesaplara Dön"),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? action,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        hintText: label == "Öğrenci No" ? "00000000000" : null, // Placeholder
        labelStyle: TextStyle(
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        hintStyle: TextStyle(
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
        prefixIcon: Icon(
          icon,
          size: 22,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
        suffixIcon: action,
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
      ),
    );
  }
}

class RipplePainter extends CustomPainter {
  final double animationValue;
  final Color color;

  RipplePainter(this.animationValue, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // 3 expanding rings
    for (int i = 0; i < 3; i++) {
      double startDelay = i * 0.35;
      double progress = (animationValue + startDelay) % 1.0;

      // Expand from OUTSIDE (0.5) to FAR (1.2)
      // Size is the paint canvas (180x180). Icon is approx 96px in center?
      // 0.5 * 180 = 90px radius. Wait, Container(16 pad + 64 icon) ~ 96px dia / 2 ~ 48px radius.
      // So 180 width is good.
      // Min radius should be slightly larger than icon container radius (approx 50).
      double maxRadius = size.width * 0.55;
      double minRadius = size.width * 0.32;

      double currentRadius = minRadius + (maxRadius - minRadius) * progress;

      // Ripple Fade Logic
      // 1. Fade IN (0.0 -> 1.0) during first 20%
      // 2. Fade OUT (1.0 -> 0.0) during remaining 80%
      double opacity = 0.5; // Base max opacity

      if (progress < 0.2) {
        // Fade In
        opacity *= (progress / 0.2);
      } else {
        // Fade Out
        opacity *= (1.0 - progress);
      }

      opacity = opacity.clamp(0.0, 1.0);

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(size.center(Offset.zero), currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(RipplePainter oldDelegate) => true;
}
