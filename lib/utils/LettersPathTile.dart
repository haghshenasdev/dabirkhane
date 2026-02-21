import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'app_settings.dart';

class LettersPathTile extends StatefulWidget {
  const LettersPathTile({super.key});

  @override
  State<LettersPathTile> createState() => _LettersPathTileState();
}

class _LettersPathTileState extends State<LettersPathTile> {
  String? currentPath;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    currentPath = await AppSettings.getSavedLettersPath();
    setState(() {});
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'انتخاب پوشه ذخیره نامه‌ها',
    );

    if (path != null) {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await AppSettings.setLettersDirectory(path);
      setState(() => currentPath = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder),
      title: const Text('مسیر پوشه نامه‌ها'),
      subtitle: Text(
        currentPath ?? 'مسیر پیش‌فرض برنامه',
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.edit),
      onTap: _pickDirectory,
    );
  }
}
