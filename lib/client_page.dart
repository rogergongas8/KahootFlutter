import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  void _joinGame() async {
    String code = _codeController.text.trim();
    String name = _nameController.text.trim();

    if (code.isEmpty || name.isEmpty) return;

    final snapshot = await _dbRef.child('partidas').child(code).get();

    if (snapshot.exists) {
      // 1. Guardamos al jugador
      await _dbRef.child('partidas').child(code).child('players').push().set({
        'name': name,
        'score': 0,
      });

      // 2. IMPORTANTE: Vamos a la Sala de Espera
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingRoom(gameCode: code, playerName: name),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Partida no encontrada")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Unirse a Kahoot")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Código"),
            ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Nombre"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _joinGame, child: const Text("ENTRAR")),
          ],
        ),
      ),
    );
  }
}

// --- NUEVA PANTALLA: SALA DE ESPERA ---
class WaitingRoom extends StatelessWidget {
  final String gameCode;
  final String playerName;

  const WaitingRoom({
    super.key,
    required this.gameCode,
    required this.playerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue,
      body: StreamBuilder(
        // Escuchamos el estado de la partida ('waiting' o 'playing')
        stream: FirebaseDatabase.instance
            .ref()
            .child('partidas')
            .child(gameCode)
            .child('status')
            .onValue,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.snapshot.value == 'playing') {
            // ¡SI EL JUEGO EMPIEZA, NAVEGAMOS AUTOMÁTICAMENTE!
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const Scaffold(
                    body: Center(
                      child: Text(
                        "¡PREGUNTA 1!",
                        style: TextStyle(fontSize: 40),
                      ),
                    ),
                  ),
                ),
              );
            });
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "¡Estás dentro!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Hola, $playerName",
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                const Text(
                  "Esperando al profesor...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
