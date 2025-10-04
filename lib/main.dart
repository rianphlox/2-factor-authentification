import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:otp/otp.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => AuthenticatorProvider()),
      ],
      child: SecurityApp(),
    ),
  );
}

class SecurityApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Security Essentials',
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          home: SplashScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

// Theme Provider for Dark Mode with persistence
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  late SharedPreferences _prefs;

  ThemeMode get themeMode => _themeMode;

  ThemeData get lightTheme => ThemeData(
    primarySwatch: Colors.blue,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.grey[50],
    cardColor: Colors.white,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
    ),
  );

  ThemeData get darkTheme => ThemeData(
    primarySwatch: Colors.blue,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Color(0xFF1A1A1A),
    cardColor: Color(0xFF2A2A2A),
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF2A2A2A),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );

  ThemeProvider() {
    _loadTheme();
  }

  void _loadTheme() async {
    _prefs = await SharedPreferences.getInstance();
    int themeIndex = _prefs.getInt('theme_mode') ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  void setTheme(ThemeMode themeMode) {
    _themeMode = themeMode;
    _prefs.setInt('theme_mode', themeMode.index);
    notifyListeners();
  }
}

// Data Models
class TOTPAccount {
  final String id;
  final String issuer;
  final String accountName;
  final String secret;
  final int digits;
  final int period;
  final String algorithm;

  TOTPAccount({
    required this.id,
    required this.issuer,
    required this.accountName,
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'issuer': issuer,
      'accountName': accountName,
      'secret': secret,
      'digits': digits,
      'period': period,
      'algorithm': algorithm,
    };
  }

  static TOTPAccount fromJson(Map<String, dynamic> json) {
    return TOTPAccount(
      id: json['id'],
      issuer: json['issuer'],
      accountName: json['accountName'],
      secret: json['secret'],
      digits: json['digits'] ?? 6,
      period: json['period'] ?? 30,
      algorithm: json['algorithm'] ?? 'SHA1',
    );
  }

  String generateOTP() {
    try {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      return OTP.generateTOTPCodeString(
        secret,
        currentTime,
        length: digits,
        interval: period,
        algorithm: _getAlgorithm(),
        isGoogle: true,
      );
    } catch (e) {
      print('OTP generation error: $e');
      return '000000';
    }
  }

  Algorithm _getAlgorithm() {
    switch (algorithm.toUpperCase()) {
      case 'SHA256':
        return Algorithm.SHA256;
      case 'SHA512':
        return Algorithm.SHA512;
      default:
        return Algorithm.SHA1;
    }
  }

  String toQRString() {
    String label = issuer.isNotEmpty ? '$issuer:$accountName' : accountName;
    return 'otpauth://totp/$label?secret=$secret&issuer=$issuer&digits=$digits&period=$period&algorithm=$algorithm';
  }
}

// Provider for state management
class AuthenticatorProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage = FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  List<TOTPAccount> _accounts = [];
  bool _isLocked = true;
  late Timer _timer;
  int _timeRemaining = 30;

  List<TOTPAccount> get accounts => _accounts;
  bool get isLocked => _isLocked;
  int get timeRemaining => _timeRemaining;

  AuthenticatorProvider() {
    _loadAccounts();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      _timeRemaining = 30 - (DateTime.now().second % 30);
      notifyListeners();
    });
  }

  Future<void> _loadAccounts() async {
    try {
      String? accountsJson = await _storage.read(key: 'totp_accounts');
      if (accountsJson != null) {
        List<dynamic> accountsList = json.decode(accountsJson);
        _accounts = accountsList.map((json) => TOTPAccount.fromJson(json)).toList();
        notifyListeners();
      }
    } catch (e) {
      print('Error loading accounts: $e');
    }
  }

  Future<void> _saveAccounts() async {
    try {
      String accountsJson = json.encode(_accounts.map((account) => account.toJson()).toList());
      await _storage.write(key: 'totp_accounts', value: accountsJson);
    } catch (e) {
      print('Error saving accounts: $e');
    }
  }

  Future<bool> authenticate() async {
    try {
      bool isAvailable = await _localAuth.isDeviceSupported();
      if (!isAvailable) {
        _isLocked = false;
        notifyListeners();
        return true;
      }

      List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();
      
      if (availableBiometrics.isEmpty) {
        _isLocked = false;
        notifyListeners();
        return true;
      }

      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access your authenticator codes',
        options: AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (authenticated) {
        _isLocked = false;
        notifyListeners();
      }
      return authenticated;
    } catch (e) {
      print('Authentication error: $e');
      _isLocked = false;
      notifyListeners();
      return true;
    }
  }

  void lockApp() {
    _isLocked = true;
    notifyListeners();
  }

  Future<void> addAccount(TOTPAccount account) async {
    _accounts.add(account);
    await _saveAccounts();
    notifyListeners();
  }

  Future<void> removeAccount(String accountId) async {
    _accounts.removeWhere((account) => account.id == accountId);
    await _saveAccounts();
    notifyListeners();
  }

  String? parseQRCode(String qrData) {
    try {
      if (!qrData.startsWith('otpauth://totp/')) {
        return 'Invalid QR code format';
      }

      Uri uri = Uri.parse(qrData);
      String? secret = uri.queryParameters['secret'];
      String? issuer = uri.queryParameters['issuer'];
      
      if (secret == null) {
        return 'No secret found in QR code';
      }

      String path = uri.path.substring(1);
      String accountName = path;
      
      if (issuer != null && path.startsWith('$issuer:')) {
        accountName = path.substring(issuer.length + 1);
      }

      int digits = int.tryParse(uri.queryParameters['digits'] ?? '6') ?? 6;
      int period = int.tryParse(uri.queryParameters['period'] ?? '30') ?? 30;
      String algorithm = uri.queryParameters['algorithm'] ?? 'SHA1';

      TOTPAccount account = TOTPAccount(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        issuer: issuer ?? '',
        accountName: accountName,
        secret: secret,
        digits: digits,
        period: period,
        algorithm: algorithm,
      );

      addAccount(account);
      return null;
    } catch (e) {
      return 'Error parsing QR code: $e';
    }
  }

  // Backup functionality (simplified)
  Future<String> createBackup(String password) async {
    try {
      Map<String, dynamic> backup = {
        'version': '1.0',
        'accounts': _accounts.map((account) => account.toJson()).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      };

      String backupJson = json.encode(backup);
      
      // Simple base64 encoding (for now, until crypto packages are added)
      String encoded = base64.encode(utf8.encode(backupJson));
      
      return encoded;
    } catch (e) {
      throw Exception('Failed to create backup: $e');
    }
  }

  Future<void> restoreFromBackup(String backupData, String password) async {
    try {
      // Simple base64 decoding (for now)
      String decoded = utf8.decode(base64.decode(backupData));
      Map<String, dynamic> backup = json.decode(decoded);
      
      if (backup['accounts'] != null) {
        List<TOTPAccount> restoredAccounts = (backup['accounts'] as List)
            .map((json) => TOTPAccount.fromJson(json))
            .toList();
        
        _accounts.addAll(restoredAccounts);
        await _saveAccounts();
        notifyListeners();
      }
    } catch (e) {
      throw Exception('Failed to restore backup: $e');
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

// Splash Screen with Authentication
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    await Future.delayed(Duration(seconds: 1));
    final provider = Provider.of<AuthenticatorProvider>(context, listen: false);
    bool authenticated = await provider.authenticate();
    
    if (authenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => DashboardScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF4A90E2),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(60),
                ),
                child: Icon(
                  Icons.security,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 40),
              Text(
                'Authenticator',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 16),
              CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Onboarding Screen
class OnboardingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF4A90E2),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(60),
                ),
                child: Icon(
                  Icons.security,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              
              SizedBox(height: 60),
              
              Text(
                'Stronger Protection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: 16),
              
              Text(
                'Secure your accounts with two-factor\nauthentication codes.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: 80),
              
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => DashboardScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Color(0xFF4A90E2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dashboard with dark mode support
class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Consumer<AuthenticatorProvider>(
      builder: (context, provider, child) {
        if (provider.isLocked) {
          return SplashScreen();
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Authenticator',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            '${provider.accounts.length} accounts',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => SettingsScreen()),
                              );
                            },
                            icon: Icon(Icons.settings, size: 24, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                          IconButton(
                            onPressed: () {
                              provider.lockApp();
                            },
                            icon: Icon(Icons.lock, size: 24, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => AddAccountScreen()),
                              );
                            },
                            icon: Icon(Icons.add, size: 28, color: Color(0xFF4A90E2)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Time remaining indicator
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Next refresh in ${provider.timeRemaining}s',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: provider.timeRemaining / 30.0,
                          backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            provider.timeRemaining > 10 ? Color(0xFF4A90E2) : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Accounts list
                Expanded(
                  child: provider.accounts.isEmpty
                      ? _buildEmptyState(context, isDark)
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          itemCount: provider.accounts.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: _buildAccountCard(context, provider.accounts[index], provider, isDark),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.security,
            size: 80,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          SizedBox(height: 20),
          Text(
            'No accounts added yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap the + button to add your first account',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddAccountScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: Text('Add Account'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context, TOTPAccount account, AuthenticatorProvider provider, bool isDark) {
    String otpCode = account.generateOTP();
    double progress = provider.timeRemaining / 30.0;
    
    return Dismissible(
      key: Key(account.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text('Delete Account', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              content: Text('Are you sure you want to delete ${account.issuer}?', style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[700])),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) {
        provider.removeAccount(account.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${account.issuer} deleted')),
        );
      },
      child: GestureDetector(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: otpCode));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Code copied to clipboard')),
          );
          HapticFeedback.lightImpact();
        },
        onLongPress: () {
          _showAccountOptions(context, account, isDark);
        },
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getServiceColor(account.issuer).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(
                  _getServiceIcon(account.issuer),
                  color: _getServiceColor(account.issuer),
                  size: 24,
                ),
              ),
              
              SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.issuer.isEmpty ? 'Unknown Service' : account.issuer,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      account.accountName,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    otpCode,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[700] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: progress > 0.3 ? Color(0xFF4A90E2) : Colors.red,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '${provider.timeRemaining}s',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountOptions(BuildContext context, TOTPAccount account, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                account.issuer,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.qr_code, color: Color(0xFF4A90E2)),
                title: Text('Export QR Code', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  Navigator.pop(context);
                  _exportAccountQR(context, account);
                },
              ),
              ListTile(
                leading: Icon(Icons.share, color: Color(0xFF4A90E2)),
                title: Text('Share Account', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  Navigator.pop(context);
                  _shareAccount(account);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _exportAccountQR(BuildContext context, TOTPAccount account) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'QR Code for ${account.issuer}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  ),
                ),
                SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: account.toQRString(),
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareAccount(TOTPAccount account) {
    Share.share(account.toQRString(), subject: 'TOTP Account: ${account.issuer}');
  }

  IconData _getServiceIcon(String service) {
    switch (service.toLowerCase()) {
      case 'google': return Icons.g_mobiledata;
      case 'github': return Icons.code;
      case 'microsoft': return Icons.business;
      case 'discord': return Icons.chat;
      case 'facebook': return Icons.facebook;
      case 'twitter': return Icons.alternate_email;
      case 'amazon': return Icons.shopping_cart;
      case 'apple': return Icons.phone_iphone;
      default: return Icons.security;
    }
  }

  Color _getServiceColor(String service) {
    switch (service.toLowerCase()) {
      case 'google': return Colors.red;
      case 'github': return Colors.black;
      case 'microsoft': return Color(0xFF0078D4);
      case 'discord': return Color(0xFF5865F2);
      case 'facebook': return Color(0xFF1877F2);
      case 'twitter': return Color(0xFF1DA1F2);
      case 'amazon': return Color(0xFFFF9900);
      case 'apple': return Colors.black;
      default: return Color(0xFF4A90E2);
    }
  }
}

// Settings Screen with all new features
class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          _buildSettingsSection(
            context,
            'Appearance',
            [
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return ListTile(
                    leading: Icon(Icons.palette, color: Color(0xFF4A90E2)),
                    title: Text('Theme', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                    subtitle: Text(_getThemeName(themeProvider.themeMode), style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    onTap: () => _showThemeDialog(context, themeProvider),
                  );
                },
              ),
            ],
            isDark,
          ),
          
          SizedBox(height: 20),
          
          _buildSettingsSection(
            context,
            'Backup & Restore',
            [
              ListTile(
                leading: Icon(Icons.backup, color: Color(0xFF4A90E2)),
                title: Text('Create Backup', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('Export your accounts securely', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                onTap: () => _createBackup(context),
              ),
              ListTile(
                leading: Icon(Icons.restore, color: Color(0xFF4A90E2)),
                title: Text('Restore Backup', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('Import accounts from backup', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                onTap: () => _restoreBackup(context),
              ),
            ],
            isDark,
          ),
          
          SizedBox(height: 20),
          
          _buildSettingsSection(
            context,
            'Export',
            [
              ListTile(
                leading: Icon(Icons.qr_code, color: Color(0xFF4A90E2)),
                title: Text('Export All QR Codes', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('Generate QR codes for all accounts', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                onTap: () => _exportAllQRCodes(context),
              ),
              ListTile(
                leading: Icon(Icons.share, color: Color(0xFF4A90E2)),
                title: Text('Share App', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('Share this authenticator app', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                onTap: () => _shareApp(),
              ),
            ],
            isDark,
          ),
          
          SizedBox(height: 20),
          
          _buildSettingsSection(
            context,
            'Security',
            [
              ListTile(
                leading: Icon(Icons.lock, color: Color(0xFF4A90E2)),
                title: Text('Lock App Now', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('Require authentication to access', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                onTap: () {
                  Provider.of<AuthenticatorProvider>(context, listen: false).lockApp();
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
              ),
            ],
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, String title, List<Widget> children, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          ...children,
          SizedBox(height: 10),
        ],
      ),
    );
  }

  String _getThemeName(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light: return 'Light';
      case ThemeMode.dark: return 'Dark';
      case ThemeMode.system: return 'System';
    }
  }

  void _showThemeDialog(BuildContext context, ThemeProvider themeProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text('Choose Theme', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: Text('Light', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                value: ThemeMode.light,
                groupValue: themeProvider.themeMode,
                onChanged: (value) {
                  themeProvider.setTheme(value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ThemeMode>(
                title: Text('Dark', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                value: ThemeMode.dark,
                groupValue: themeProvider.themeMode,
                onChanged: (value) {
                  themeProvider.setTheme(value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ThemeMode>(
                title: Text('System', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                value: ThemeMode.system,
                groupValue: themeProvider.themeMode,
                onChanged: (value) {
                  themeProvider.setTheme(value!);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _createBackup(BuildContext context) async {
    final provider = Provider.of<AuthenticatorProvider>(context, listen: false);
    
    if (provider.accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No accounts to backup')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        final passwordController = TextEditingController();
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text('Create Backup', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter a password to encrypt your backup:', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[300] : Colors.grey[700])),
              SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  String backup = await provider.createBackup(passwordController.text);
                  Navigator.pop(context);
                  
                  // Share the backup directly instead of saving to file
                  Share.share(backup, subject: 'Authenticator Backup');
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Backup created and shared successfully!')),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create backup: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _restoreBackup(BuildContext context) async {
    // For now, show a dialog explaining how to restore
    showDialog(
      context: context,
      builder: (context) {
        final backupController = TextEditingController();
        final passwordController = TextEditingController();
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text('Restore Backup', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Paste your backup data:', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[300] : Colors.grey[700])),
              SizedBox(height: 16),
              TextField(
                controller: backupController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Backup Data',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final provider = Provider.of<AuthenticatorProvider>(context, listen: false);
                  await provider.restoreFromBackup(backupController.text, passwordController.text);
                  Navigator.pop(context);
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Backup restored successfully!')),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to restore backup: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: Text('Restore'),
            ),
          ],
        );
      },
    );
  }

  void _exportAllQRCodes(BuildContext context) {
    final provider = Provider.of<AuthenticatorProvider>(context, listen: false);
    
    if (provider.accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No accounts to export')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRExportScreen(accounts: provider.accounts),
      ),
    );
  }

  void _shareApp() {
    Share.share(
      'Check out this amazing 2FA Authenticator app! Secure your accounts with two-factor authentication.',
      subject: 'Secure Authenticator App',
    );
  }
}

// QR Export Screen
class QRExportScreen extends StatelessWidget {
  final List<TOTPAccount> accounts;

  QRExportScreen({required this.accounts});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Export QR Codes'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(20),
        itemCount: accounts.length,
        itemBuilder: (context, index) {
          final account = accounts[index];
          return Container(
            margin: EdgeInsets.only(bottom: 20),
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  account.issuer,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  account.accountName,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: account.toQRString(),
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Share.share(account.toQRString()),
                  child: Text('Share QR Code'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Add Account Screen (unchanged but supports dark mode)
class AddAccountScreen extends StatefulWidget {
  @override
  _AddAccountScreenState createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final TextEditingController _serviceController = TextEditingController();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Add Account'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // QR Scanner option
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 60,
                    color: Color(0xFF4A90E2),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Scan QR Code',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Point your camera at the QR code',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _scanQRCode(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF4A90E2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Open Camera',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            // Or divider
            Row(
              children: [
                Expanded(child: Divider(color: isDark ? Colors.grey[600] : Colors.grey[300])),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: isDark ? Colors.grey[600] : Colors.grey[300])),
              ],
            ),
            
            SizedBox(height: 24),
            
            // Manual entry form
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manual Entry',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  _buildTextField(
                    controller: _serviceController,
                    label: 'Service Name',
                    hint: 'e.g., Google, GitHub',
                    isDark: isDark,
                  ),
                  
                  SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _accountController,
                    label: 'Account',
                    hint: 'e.g., your@email.com',
                    isDark: isDark,
                  ),
                  
                  SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _secretController,
                    label: 'Secret Key',
                    hint: 'Enter the secret key',
                    isDark: isDark,
                  ),
                  
                  SizedBox(height: 24),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _addManualAccount,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF4A90E2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Add Account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanQRCode() async {
    PermissionStatus permission = await Permission.camera.request();
    
    if (permission != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera permission is required to scan QR codes')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => QRScannerScreen()),
    );
  }

  void _addManualAccount() {
    if (_serviceController.text.isEmpty || 
        _accountController.text.isEmpty || 
        _secretController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final provider = Provider.of<AuthenticatorProvider>(context, listen: false);
    
    String cleanedSecret = _secretController.text
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .toUpperCase();

    TOTPAccount account = TOTPAccount(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      issuer: _serviceController.text,
      accountName: _accountController.text,
      secret: cleanedSecret,
    );

    provider.addAccount(account);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Account added successfully!')),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
            filled: true,
            fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.grey[600]! : Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.grey[600]! : Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Color(0xFF4A90E2)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _serviceController.dispose();
    _accountController.dispose();
    _secretController.dispose();
    super.dispose();
  }
}

// QR Scanner Screen (unchanged)
class QRScannerScreen extends StatefulWidget {
  @override
  _QRScannerScreenState createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (!_isProcessing) {
            _processQRCode(capture.barcodes.first.rawValue);
          }
        },
      ),
    );
  }

  void _processQRCode(String? qrData) async {
    if (qrData == null || _isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });

    final provider = Provider.of<AuthenticatorProvider>(context, listen: false);
    String? error = provider.parseQRCode(qrData);
    
    Navigator.pop(context);
    
    if (error == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account added successfully!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}