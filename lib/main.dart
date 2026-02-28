import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'server_page.dart';
import 'firebase_options.dart';
import 'client_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MainApp());
}

// 1. Esta clase solo configura la App y el tema
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(), // Llamamos a la nueva clase HomePage
    );
  }
}

// 2. Esta clase es la pantalla real
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Kahoot RGG")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ServerPage()),
                );
              },
              child: const Text("Crear Partida (Servidor)"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ClientPage()),
                );
              },
              child: const Text("Unirse (Cliente)"),
            ),
          ],
        ),
      ),
    );
  }
}
