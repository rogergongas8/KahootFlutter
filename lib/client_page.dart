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
      // 1. Guardamos al jugador en Firebase apuntando a su nombre
      await _dbRef.child('partidas').child(code).child('players').child(name).set({
        'name': name,
        'score': 0,
      });

      // 2. IMPORTANTE: Vamos a la Sala Wrapper
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoomWrapper(gameCode: code, playerName: name),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Partida no encontrada")));
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

// --- NUEVA PANTALLA: Observador Global del Juego ---
class RoomWrapper extends StatelessWidget {
  final String gameCode;
  final String playerName;

  const RoomWrapper({super.key, required this.gameCode, required this.playerName});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref().child('partidas').child(gameCode).child('current_question').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          Map qData = snapshot.data!.snapshot.value as Map;
          // Si el profe dictó una pregunta activa o terminada, vamos a la pantalla de botones
          return ClientGameScreen(gameCode: gameCode, playerName: playerName, questionData: qData);
        }

        // Diseño original de Sala de Espera
        return Scaffold(
          backgroundColor: Colors.blue,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("¡Estás dentro!", style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Text("Hola, $playerName", style: const TextStyle(color: Colors.white, fontSize: 20)),
                const SizedBox(height: 40),
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                const Text("Esperando al profesor...", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- NUEVA PANTALLA: Botones de Colores del Alumno ---
class ClientGameScreen extends StatelessWidget {
  final String gameCode;
  final String playerName;
  final Map questionData;

  const ClientGameScreen({super.key, required this.gameCode, required this.playerName, required this.questionData});

  void _submitAnswer(int index) async {
    // Solo puede responder si el estado es 'showing' y el tiempo corre
    if (questionData['status'] == 'showing') {
      await FirebaseDatabase.instance
          .ref()
          .child('partidas')
          .child(gameCode)
          .child('current_answers')
          .child(playerName)
          .set({
        'answerIndex': index,
        'answeredAt': ServerValue.timestamp, // Guarda la hora exacta del clic para la puntuación
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String status = questionData['status'];
    final colors = [Colors.red, Colors.blue, Colors.orange, Colors.green];

    return Scaffold(
      appBar: AppBar(title: const Text("Responde!"), automaticallyImplyLeading: false),
      body: StreamBuilder(
        // Escuchamos tu propia respuesta actual para bloquear la pantalla si ya respondiste
        stream: FirebaseDatabase.instance.ref().child('partidas').child(gameCode).child('current_answers').child(playerName).onValue,
        builder: (context, snapshot) {
          bool hasAnswered = snapshot.hasData && snapshot.data!.snapshot.value != null;
          int? answeredIndex;
          if (hasAnswered) {
             answeredIndex = (snapshot.data!.snapshot.value as Map)['answerIndex'] as int;
          }

          if (status == 'scoreboard') {
             return Container(
               color: Colors.deepPurple,
               alignment: Alignment.center,
               padding: const EdgeInsets.all(20),
               child: const Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(Icons.emoji_events, color: Colors.yellow, size: 100),
                   SizedBox(height: 20),
                   Text("¡Mira la pizarra!", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                   SizedBox(height: 10),
                   Text("El profesor está mostrando el Podium", style: TextStyle(color: Colors.white70, fontSize: 18), textAlign: TextAlign.center),
                 ],
               ),
             );
          }

          if (status == 'finished') {
             // El profesor acabó la pregunta (tiempo=0), verificamos si acertaste
             bool isCorrect = answeredIndex == questionData['correctIndex'];
             
             // Leemos el total de puntos y los ganados en esta ronda
             print("Buscando player stats");
             return StreamBuilder(
               stream: FirebaseDatabase.instance.ref().child('partidas').child(gameCode).child('players').child(playerName).onValue,
               builder: (context, playerSnapshot) {
                 int earned = 0;
                 int total = 0;
                 if (playerSnapshot.hasData && playerSnapshot.data!.snapshot.value != null) {
                   Map pData = playerSnapshot.data!.snapshot.value as Map;
                   earned = pData['lastRoundPoints'] ?? 0;
                   total = pData['score'] ?? 0;
                 }

                 return Container(
                   color: isCorrect ? Colors.green : Colors.red,
                   alignment: Alignment.center,
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: Colors.white, size: 100),
                       const SizedBox(height: 20),
                       Text(
                         isCorrect ? "¡CORRECTO!" : "INCORRECTO",
                         style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                       ),
                       const SizedBox(height: 20),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                         decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                         child: Text(isCorrect ? "+$earned pts" : "+0 pts", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                       ),
                       const SizedBox(height: 10),
                       Text("Puntuación Total: $total", style: const TextStyle(color: Colors.white, fontSize: 20)),
                     ],
                   ),
                 );
               }
             );
          }

          // Si ya respondió pero la pregunta sigue mostrándose en el servidor
          if (hasAnswered) {
             return const Center(child: Text("Esperando que termine el tiempo...", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center));
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildAnswerButton(0, colors[0], () => _submitAnswer(0)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildAnswerButton(1, colors[1], () => _submitAnswer(1)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildAnswerButton(2, colors[2], () => _submitAnswer(2)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildAnswerButton(3, colors[3], () => _submitAnswer(3)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildAnswerButton(int index, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(0, 5),
            )
          ],
        ),
      ),
    );
  }
}
