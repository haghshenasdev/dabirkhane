import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';

class CamScannerPathsTile extends StatefulWidget {
  const CamScannerPathsTile({super.key});

  @override
  State<CamScannerPathsTile> createState() => _CamScannerPathsTileState();
}

class _CamScannerPathsTileState extends State<CamScannerPathsTile> {
  String? path1;
  String? path2;
  bool _readWithoutGallerySave = true;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    path1 = await AppSettings.getCamScannerPath1();
    path2 = await AppSettings.getCamScannerPath2();
    _readWithoutGallerySave = await AppSettings.getReadWithoutGallerySave();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickDirectory(int index) async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'انتخاب پوشه CamScanner',
    );

    if (selectedPath == null) return;

    final dir = Directory(selectedPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await AppSettings.setCamScannerDirectories(
      path1: index == 1 ? selectedPath : path1!,
      path2: index == 2 ? selectedPath : path2!,
    );

    await _loadPaths();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.document_scanner),
          title: const Text("مسیر CamScanner تصاویر"),
          subtitle: Text(
            path1 ?? AppSettings.defaultCamScannerPath1,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.edit),
          onTap: () => _pickDirectory(1),
        ),
        ListTile(
          leading: const Icon(Icons.document_scanner),
          title: const Text("مسیر CamScanner pdf"),
          subtitle: Text(
            path2 ?? AppSettings.defaultCamScannerPath2,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.edit),
          onTap: () => _pickDirectory(2),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.photo_library_outlined),
          title: const Text("خواندن بدون ذخیره در گالری"),
          subtitle: const Text(
            "پس از اسکن، فایل بدون ذخیره در گالری ثبت شود.",
            style: TextStyle(fontSize: 12),
          ),
          value: _readWithoutGallerySave,
          onChanged: (value) async {
            setState(() {
              _readWithoutGallerySave = value;
            });

            await AppSettings.setReadWithoutGallerySave(value);
          },
        ),
      ],
    );
  }
}
