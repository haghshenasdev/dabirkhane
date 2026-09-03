import 'package:flutter/material.dart';
import 'package:dabirkhane/utils/app_settings.dart';

class ScannerTypeTile extends StatefulWidget {
  const ScannerTypeTile({super.key});

  @override
  State<ScannerTypeTile> createState() => _ScannerTypeTileState();
}

class _ScannerTypeTileState extends State<ScannerTypeTile> {
  String _scannerType = AppSettings.scannerCamScanner;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadScannerType();
  }

  Future<void> _loadScannerType() async {
    final value = await AppSettings.getScannerType();

    if (!mounted) return;

    setState(() {
      _scannerType = value;
      _loading = false;
    });
  }

  Future<void> _setScannerType(String value) async {
    await AppSettings.setScannerType(value);

    if (!mounted) return;

    setState(() {
      _scannerType = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('روش اسکن'),
      );
    }

    return Column(
      children: [
        RadioListTile<String>(
          value: AppSettings.scannerCamScanner,
          groupValue: _scannerType,
          onChanged: (value) {
            if (value != null) {
              _setScannerType(value);
            }
          },
          secondary: const Icon(Icons.document_scanner),
          title: const Text('CamScanner'),
          subtitle: const Text(
            'استفاده از فرآیند فعلی اسکن',
          ),
        ),

        RadioListTile<String>(
          value: AppSettings.scannerFastScanner,
          groupValue: _scannerType,
          onChanged: (value) {
            if (value != null) {
              _setScannerType(value);
            }
          },
          secondary: const Icon(Icons.document_scanner_outlined),
          title: const Text('Fast Scanner'),
          subtitle: const Text(
            'استفاده از نرم‌افزار Fast Scanner',
          ),
        ),
      ],
    );
  }
}