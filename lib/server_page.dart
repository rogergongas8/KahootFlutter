import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

class Question {
  final String text;
  final List<String> options;
  final int correctIndex;

  Question(this.text, this.options, this.correctIndex);
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String gameCode = "Generando...";
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  bool gameStarted = false;

  int _currentQuestionIndex = 0;
  int _timeLeft = 20;
  Timer? _timer;

  // Preguntas de prueba
  final List<Question> _questions = [
    Question("¿Cuál es la capital de Francia?", ["Madrid", "París", "Roma", "Berlín"], 1),
    Question("¿Cuánto es 2 + 2?", ["3", "4", "5", "6"], 1),
    Question("¿De qué color es el cielo despejado?", ["Verde", "Azul", "Rojo", "Amarillo"], 1),
  ];

  @override
  void initState() {
    super.initState();
    _createGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    setState(() {
      gameStarted = true;
    });
    
    await _dbRef.child('partidas').child(gameCode).update({
      'status': 'playing',
    });
    
    _startQuestion();
  }

  int _questionStartTime = 0;

  void _startQuestion() async {
    setState(() {
      _timeLeft = 20;
    });

    Question q = _questions[_currentQuestionIndex];
    
    // Guardamos tiempo local aproximado de inicio para calcular los puntos después
    _questionStartTime = DateTime.now().millisecondsSinceEpoch;

    // Actualizamos la base de datos con la pregunta actual y el estado
    await _dbRef.child('partidas').child(gameCode).child('current_question').set({
      'text': q.text,
      'options': q.options,
      'correctIndex': q.correctIndex, // Enviamos el índice de la respuesta correcta
      'status': 'showing', // showing significa que la estamos mostrando y pueden responder
    });

    // Vaciamos las respuestas previas
    await _dbRef.child('partidas').child(gameCode).child('current_answers').remove();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() {
          _timeLeft--;
        });
      } else {
        _timer?.cancel();
        _endQuestion();
      }
    });
  }

  void _endQuestion() async {
    // 1. Cerramos la pregunta
    await _dbRef.child('partidas').child(gameCode).child('current_question').update({
      'status': 'finished',
    });

    // 2. Traemos las respuestas de los alumnos
    final answersSnapshot = await _dbRef.child('partidas').child(gameCode).child('current_answers').get();
    
    if (answersSnapshot.exists) {
      Map answersMap = answersSnapshot.value as Map;
      int correctIndex = _questions[_currentQuestionIndex].correctIndex;

      // Por cada alumno que respondió
      answersMap.forEach((playerName, data) async {
        int studentAnswer = data['answerIndex'];
        int answeredAt = data['answeredAt'] ?? _questionStartTime + 20000;

        // Si acertó, calculamos puntos (Máx 1000, Min 500) según lo rápido que fue
        if (studentAnswer == correctIndex) {
          int timeTakenMs = answeredAt - _questionStartTime;
          // Evitamos valores negativos si los relojes están un poco desincronizados
          if (timeTakenMs < 0) timeTakenMs = 0; 
          
          double timeRatio = timeTakenMs / 20000.0; // 20000ms = 20s
          if (timeRatio > 1.0) timeRatio = 1.0;

          // Fórmula típica de Kahoot: Rápido = 1000, Lento pero acertado = 500
          int pointsEarned = (1000 * (1 - (timeRatio / 2))).round();

          // Sumamos a Firebase
          DatabaseReference playerScoreRef = _dbRef.child('partidas').child(gameCode).child('players').child(playerName).child('score');
          
          // Usamos una transacción para simular sumas seguras (o leer y escribir si es simple)
          final scoreSnapshot = await playerScoreRef.get();
          int currentScore = 0;
          if (scoreSnapshot.exists) {
            currentScore = int.parse(scoreSnapshot.value.toString());
          }
          await playerScoreRef.set(currentScore + pointsEarned);
        }
      });
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
      });
      _startQuestion();
    } else {
      // Fin del Kahoot
    }
  }

  @override
  Widget build(BuildContext context) {
    if (gameStarted) {
      return _buildGameUI();
    }
    return _buildWaitingRoom();
  }

  Widget _buildWaitingRoom() {
    return Scaffold(
      appBar: AppBar(title: const Text("Servidor - Sala de espera")),
      body: Column(
        children: [
          const SizedBox(height: 30),
          const Text("CÓDIGO DE SALA:", style: TextStyle(fontSize: 20)),
          Text(
            gameCode,
            style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const Text("JUGADORES CONECTADOS:", style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: gameCode == "Generando..."
                ? const SizedBox()
                : StreamBuilder(
                    stream: _dbRef.child('partidas').child(gameCode).child('players').onValue,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                        return const Center(child: Text("Esperando alumnos..."));
                      }
                      Map<dynamic, dynamic> playersMap = snapshot.data!.snapshot.value as Map;
                      List<dynamic> playersList = playersMap.values.toList();
                      return ListView.builder(
                        itemCount: playersList.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(playersList[index]['name'] ?? 'Incógnito'),
                            trailing: Text("${playersList[index]['score']} pts"),
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

  Widget _buildGameUI() {
    Question q = _questions[_currentQuestionIndex];
    final colors = [Colors.red, Colors.blue, Colors.orange, Colors.green];

    return Scaffold(
      appBar: AppBar(title: Text("PIN: $gameCode"), centerTitle: true),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            child: Text(
              q.text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.purple,
            child: Text(
              "$_timeLeft",
              style: const TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          StreamBuilder(
            stream: _dbRef.child('partidas').child(gameCode).child('current_answers').onValue,
            builder: (context, snapshot) {
              int count = 0;
              if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                count = (snapshot.data!.snapshot.value as Map).length;
              }
              return Text("Respuestas: $count", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold));
            }
          ),
          const Spacer(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildTeacherOption(0, colors[0], q)),
                        const SizedBox(width: 15),
                        Expanded(child: _buildTeacherOption(1, colors[1], q)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildTeacherOption(2, colors[2], q)),
                        const SizedBox(width: 15),
                        Expanded(child: _buildTeacherOption(3, colors[3], q)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_timeLeft == 0 && _currentQuestionIndex < _questions.length - 1)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton(
                onPressed: _nextQuestion,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text("Siguiente Pregunta", style: TextStyle(fontSize: 20)),
              ),
            ),
          if (_timeLeft == 0 && _currentQuestionIndex >= _questions.length - 1)
             const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("¡Fin del juego!", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildTeacherOption(int index, Color color, Question q) {
    bool showCorrect = _timeLeft == 0 && index == q.correctIndex;
    bool showWrong = _timeLeft == 0 && index != q.correctIndex;
    
    return Container(
      decoration: BoxDecoration(
        color: showWrong ? Colors.grey : color,
        borderRadius: BorderRadius.circular(16), // Match radio con client_page
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 5), // Match sombra con client_page
          )
        ],
        border: showCorrect ? Border.all(color: Colors.white, width: 8) : null,
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          q.options[index],
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
