# QKey - Secure 2FA Authenticator 🔐

A modern, secure, and user-friendly two-factor authentication (2FA) app built with Flutter. QKey helps you protect your accounts with time-based one-time passwords (TOTP) and provides a seamless experience across all your devices.

## ✨ Features

### 🔒 Core Security
- **TOTP Authentication**: Generate secure 6-digit codes that refresh every 30 seconds
- **Biometric Protection**: Lock your app with fingerprint, Face ID, or device passcode
- **Secure Storage**: All secrets are encrypted and stored securely on your device
- **No Cloud Dependencies**: Everything stays on your device for maximum privacy

### 📱 User Experience
- **QR Code Scanning**: Quickly add accounts by scanning QR codes from services
- **Manual Entry**: Add accounts manually when QR codes aren't available
- **Dark Mode Support**: Automatic dark/light theme with system preference detection
- **Intuitive Interface**: Clean, modern design that's easy to navigate
- **Haptic Feedback**: Subtle vibrations for better user interaction

### 🛠 Advanced Features
- **Backup & Restore**: Create encrypted backups of your accounts
- **Bulk Export**: Export all QR codes at once for easy migration
- **Account Management**: Edit, delete, and organize your accounts
- **Progress Indicators**: Visual countdown timers for code expiration
- **Copy to Clipboard**: One-tap code copying with confirmation

### 🎨 Customization
- **Service Icons**: Automatic icons and colors for popular services (Google, GitHub, Microsoft, etc.)
- **Theme Options**: Light, Dark, or System theme modes
- **Persistent Settings**: Your preferences are saved and restored

## 📱 Screenshots

*Add screenshots of your app here when ready to publish*

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (>=3.0.0)
- Dart SDK
- iOS 11.0+ / Android API 21+
- Camera permission (for QR code scanning)

### Installation

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd auth_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

### Building for Release

#### Android
```bash
flutter build apk --release
# or for app bundle
flutter build appbundle --release
```

#### iOS
```bash
flutter build ios --release
```

## 🏗 Architecture

### Project Structure
```
lib/
└── main.dart          # Complete app implementation with all features
assets/
└── icon/
    └── app_icon.png    # App icon
```

### Key Components
- **AuthenticatorProvider**: State management for accounts and app security
- **ThemeProvider**: Dark/light mode theme management
- **TOTPAccount**: Data model for 2FA accounts
- **Secure Storage**: Encrypted local storage for sensitive data

### Dependencies
| Package | Purpose |
|---------|---------|
| `otp` | TOTP/HOTP code generation |
| `mobile_scanner` | QR code scanning |
| `flutter_secure_storage` | Encrypted local storage |
| `local_auth` | Biometric authentication |
| `provider` | State management |
| `qr_flutter` | QR code generation |
| `share_plus` | Sharing functionality |

## 🔧 Configuration

### Permissions

#### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.USE_FINGERPRINT" />
```

#### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan QR codes for adding 2FA accounts</string>
<key>NSFaceIDUsageDescription</key>
<string>Face ID is used to secure access to your authenticator codes</string>
```

## 📖 Usage

### Adding Accounts

#### Via QR Code (Recommended)
1. Tap the **+** button on the main screen
2. Select **"Open Camera"**
3. Point your camera at the QR code provided by the service
4. The account will be automatically added

#### Manual Entry
1. Tap the **+** button on the main screen
2. Scroll down to **"Manual Entry"**
3. Fill in:
   - **Service Name**: e.g., "Google", "GitHub"
   - **Account**: Your username or email
   - **Secret Key**: The secret provided by the service
4. Tap **"Add Account"**

### Managing Accounts
- **Copy Code**: Tap any account card to copy the current code
- **Delete Account**: Swipe left on an account and confirm deletion
- **View Options**: Long-press an account for export and sharing options

### Backup & Security
- **Create Backup**: Settings → Backup & Restore → Create Backup
- **Lock App**: Tap the lock icon or use Settings → Security → Lock App Now
- **Theme Settings**: Settings → Appearance → Theme

## 🔐 Security Features

### Data Protection
- All TOTP secrets are stored using Flutter Secure Storage
- Biometric authentication prevents unauthorized access
- No network requests - everything works offline
- Backup encryption protects exported data

### Supported Algorithms
- **SHA1** (most common)
- **SHA256**
- **SHA512**

### Supported Formats
- Standard TOTP with 30-second intervals
- 6-digit codes (configurable)
- Google Authenticator compatible

## 🛠 Development

### Running Tests
```bash
flutter test
```

### Code Generation
If you modify any model classes, run:
```bash
flutter packages pub run build_runner build
```

### Debugging
Enable debug mode for detailed logging:
```bash
flutter run --debug
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style
- Follow [Dart style guidelines](https://dart.dev/guides/language/effective-dart/style)
- Use meaningful variable and function names
- Add comments for complex logic
- Ensure all tests pass before submitting

## 📋 Roadmap

### Upcoming Features
- [ ] Account categories and folders
- [ ] Custom refresh intervals
- [ ] Import from other authenticator apps
- [ ] Wear OS / Apple Watch support
- [ ] Multiple backup destinations
- [ ] Account search and filtering

### Known Issues
- None currently reported

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Flutter](https://flutter.dev/) - The amazing cross-platform framework
- [OTP Package](https://pub.dev/packages/otp) - TOTP/HOTP implementation
- [Mobile Scanner](https://pub.dev/packages/mobile_scanner) - QR code scanning
- Icons from [Material Design Icons](https://material.io/design/iconography/)

## 📧 Support

If you encounter any issues or have questions:

1. Check the [Issues](../../issues) page for existing problems
2. Create a new issue with detailed information
3. Join our community discussions

## 🔗 Related Projects

- [Google Authenticator](https://github.com/google/google-authenticator) - Official Google 2FA app
- [Authy](https://authy.com/) - Commercial 2FA solution
- [andOTP](https://github.com/andOTP/andOTP) - Open-source Android authenticator

---

**Made with ❤️ using Flutter**

*Keep your accounts secure with QKey!*
