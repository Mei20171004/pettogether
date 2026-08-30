import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Full-screen camera scanner that returns the raw invitation value (a
/// `pettogether://invite/<id>` deep link) via [Navigator.pop].
class InvitationScannerView extends StatefulWidget {
  const InvitationScannerView({super.key});

  @override
  State<InvitationScannerView> createState() => _InvitationScannerViewState();
}

class _InvitationScannerViewState extends State<InvitationScannerView> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return Scaffold(
      backgroundColor: PawColors.ink,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: Text(L10n.text(language, 'Scan invitation', '招待をスキャン',
            '扫描邀请', '초대장 스캔')),
        // This screen is dark, so the app-wide dark status-bar glyphs would
        // disappear against it.
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_handled || capture.barcodes.isEmpty) return;
              final value = capture.barcodes.first.rawValue;
              if (value == null || value.isEmpty) return;
              _handled = true;
              Navigator.pop(context, value);
            },
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: 72,
            child: Text(
              L10n.text(
                language,
                'Point the camera at a pettogether invitation QR code.',
                'pettogether の招待 QR コードにカメラを向けてください。',
                '将相机对准 pettogether 邀请二维码。',
                'pettogether 초대 QR 코드에 카메라를 맞추세요.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
