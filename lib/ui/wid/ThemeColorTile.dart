import '../../providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThemeColorTile extends StatelessWidget {
  ThemeColorTile({super.key});

  final colors = [
    Colors.blue,
    Colors.green,
    Colors.teal,
    Colors.deepPurple,
    Colors.orange,
    Colors.red,
    Colors.brown,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return ListTile(
      leading: const Icon(Icons.color_lens),
      title: const Text('رنگ تم برنامه'),
      subtitle: Wrap(
        spacing: 8,
        children: colors.map((color) {
          final selected = theme.seedColor.value == color.value;
          return GestureDetector(
            onTap: () {
              context.read<ThemeProvider>().setSeedColor(color);
            },
            child: CircleAvatar(
              radius: selected ? 18 : 16,
              backgroundColor: color,
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}
