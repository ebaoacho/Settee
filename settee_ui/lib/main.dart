import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(SetteeApp());
}

class SetteeApp extends StatelessWidget {
  const SetteeApp({super.key}); 

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Settee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'SFPro',
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
      ),
      home: SplashScreen(),
    );
  }
}
