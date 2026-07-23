import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const WifiDeviceFinderApp());
}

class WifiDeviceFinderApp extends StatelessWidget {
  const WifiDeviceFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wi-Fi Device Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
