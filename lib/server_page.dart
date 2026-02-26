import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String gameCode = "Generando...";
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  bool gameStarted = false;

  @override
  void initState() {
    super.initState();
    _createGame();
  }

  void _createGame() async {
    String newCode = (1000 + Random().nextInt(9000)).toString();
    await _dbRef.child('partidas').child(newCode).set({
      'status': 'waiting',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    if (mounted) {
      setState(() {
        gameCode = newCode;
      });
    }
  }

  void _startGame() async {
    // Cambiamos el estado a 'playing' en la base de datos
    await _dbRef.child('partidas').child(gameCode).update({
      'status': 'playing',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Servidor - Sala de espera")),
      body: Column(
        children: [
          const SizedBox(height: 30),
          const Text("CÓDIGO DE SALA:", style: TextStyle(fontSize: 20)),
          Text(
            gameCode,
            style: const TextStyle(
              fontSize: 50,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const Text(
            "JUGADORES CONECTADOS:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          // ESTA ES LA PARTE MÁGICA: Escucha la base de datos en tiempo real
          Expanded(
            child: gameCode == "Generando..."
                ? const SizedBox()
                : StreamBuilder(
                    stream: _dbRef
                        .child('partidas')
                        .child(gameCode)
                        .child('players')
                        .onValue,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData ||
                          snapshot.data!.snapshot.value == null) {
                        return const Center(
                          child: Text("Esperando alumnos..."),
                        );
                      }

                      // Convertimos los datos de Firebase (Map) a una lista
                      Map<dynamic, dynamic> playersMap =
                          snapshot.data!.snapshot.value as Map;
                      List<dynamic> playersList = playersMap.values.toList();

                      return ListView.builder(
                        itemCount: playersList.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(playersList[index]['name']),
                            trailing: const Text("0 pts"), // Puntuación inicial
                          );
                        },
                      );
                    },
                  ),
          ),

          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton.icon(
              onPressed: _startGame,
              icon: const Icon(Icons.play_arrow),
              label: const Text("EMPEZAR PARTIDA"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
