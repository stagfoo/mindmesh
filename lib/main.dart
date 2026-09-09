import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'contexts_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MindMeshApp());
}

class MindMeshApp extends StatelessWidget {
  const MindMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindMesh',
      debugShowCheckedModeBanner: false,
      theme: buildMeshTheme(),
      home: const ContextsScreen(),
    );
  }
}
