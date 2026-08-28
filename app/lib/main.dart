import "package:flutter/material.dart";

import "screens/home_screen.dart";
import "theme.dart";

void main() {
  runApp(const CharmScaleApp());
}

class CharmScaleApp extends StatelessWidget {
  const CharmScaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "振り返り",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
