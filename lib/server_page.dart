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
  final TextEditingController _gameCodeController = TextEditingController();
  String? gameCode;
  bool isGameReady = false;
  bool gameStarted = false; // Added from upstream
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  int _currentQuestionIndex = 0;
  int _timeLeft = 20;
  Timer? _timer;
  StreamSubscription? _answersSubscription;
  bool _questionEnded = false;

  final List<Question> _questions = [
    Question("¿Cuál es la capital de Francia?", ["Madrid", "París", "Roma", "Berlín"], 1),
    Question("¿Cuánto es 2 + 2?", ["3", "4", "5", "6"], 1),
    Question("¿De qué color es el cielo despejado?", ["Verde", "Azul", "Rojo", "Amarillo"], 1),
  ];

  @override
  void dispose() {
    _gameCodeController.dispose();
    _timer?.cancel();
    _answersSubscription?.cancel();
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
        isGameReady = true;
      });
    }
  }

  void _joinGame() async {
    String code = _gameCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor, introduce un código de partida.")),
      );
      return;
    }

    final snapshot = await _dbRef.child('partidas').child(code).get();
    if (snapshot.exists) {
      if (mounted) {
        setState(() {
          gameCode = code;
          isGameReady = true;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La partida no existe.")),
      );
    }
  }

  void _startGame() async {
    if (gameCode != null) {
      setState(() {
        gameStarted = true;
      });
      await _dbRef.child('partidas').child(gameCode!).update({
        'status': 'playing',
      });
      _startQuestion();
    }
  }

  void _exitGame() {
    setState(() {
      isGameReady = false;
      gameStarted = false;
      gameCode = null;
    });
  }

  int _questionStartTime = 0;

  void _startQuestion() async {
    _questionEnded = false;
    setState(() {
      _timeLeft = 20;
    });

    Question q = _questions[_currentQuestionIndex];
    _questionStartTime = DateTime.now().millisecondsSinceEpoch;

    await _dbRef.child('partidas').child(gameCode!).child('current_question').set({
      'text': q.text,
      'options': q.options,
      'correctIndex': q.correctIndex,
      'status': 'showing',
    });

    await _dbRef.child('partidas').child(gameCode!).child('current_answers').remove();

    _timer?.cancel();
    _answersSubscription?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() {
          _timeLeft--;
        });
      } else {
        _timer?.cancel();
        _answersSubscription?.cancel();
        _endQuestion();
      }
    });

    _answersSubscription = _dbRef.child('partidas').child(gameCode!).child('current_answers').onValue.listen((event) async {
      if (event.snapshot.value != null) {
        int answersCount = (event.snapshot.value as Map).length;
        final playersSnapshot = await _dbRef.child('partidas').child(gameCode!).child('players').get();
        int totalPlayers = 0;
        if (playersSnapshot.exists) {
          totalPlayers = (playersSnapshot.value as Map).length;
        }
        if (answersCount >= totalPlayers && totalPlayers > 0) {
           _timer?.cancel();
           _answersSubscription?.cancel();
           _endQuestion();
        }
      }
    });
  }

  void _skipQuestion() {
    _timer?.cancel();
    _answersSubscription?.cancel();
    setState(() {
      _timeLeft = 0;
    });
    _endQuestion();
  }

  void _endQuestion() async {
    if (_questionEnded) return;
    _questionEnded = true;

    await _dbRef.child('partidas').child(gameCode!).child('current_question').update({
      'status': 'finished',
    });

    final playersSnapshot = await _dbRef.child('partidas').child(gameCode!).child('players').get();
    final answersSnapshot = await _dbRef.child('partidas').child(gameCode!).child('current_answers').get();
    
    Map answersMap = answersSnapshot.exists ? answersSnapshot.value as Map : {};
    int correctIndex = _questions[_currentQuestionIndex].correctIndex;

    if (playersSnapshot.exists) {
      Map playersMap = playersSnapshot.value as Map;
      for (String playerName in playersMap.keys) {
        int pointsEarned = 0;
        if (answersMap.containsKey(playerName)) {
          var data = answersMap[playerName];
          int studentAnswer = data['answerIndex'];
          int answeredAt = data['answeredAt'] ?? _questionStartTime + 20000;
          if (studentAnswer == correctIndex) {
            int timeTakenMs = answeredAt - _questionStartTime;
            if (timeTakenMs < 0) timeTakenMs = 0;
            double timeRatio = timeTakenMs / 20000.0;
            if (timeRatio > 1.0) timeRatio = 1.0;
            pointsEarned = (1000 * (1 - (timeRatio / 2))).round();
          }
        }
        int currentScore = playersMap[playerName]['score'] ?? 0;
        await _dbRef.child('partidas').child(gameCode!).child('players').child(playerName).update({
          'score': currentScore + pointsEarned,
          'lastRoundPoints': pointsEarned,
        });
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _showScoreboard() async {
    await _dbRef.child('partidas').child(gameCode!).child('current_question').update({
      'status': 'scoreboard',
    });
    setState(() {});
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
      });
      _startQuestion();
    } else {
      // End of game
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isGameReady) {
      return _buildGameSetup();
    }
    if (gameStarted) {
      return StreamBuilder(
        stream: _dbRef.child('partidas').child(gameCode!).child('current_question').child('status').onValue,
        builder: (context, snapshot) {
          String status = "showing";
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            status = snapshot.data!.snapshot.value as String;
          }
          if (status == 'scoreboard') {
            return _buildScoreboardUI();
          }
          return _buildGameUI();
        }
      );
    }
    return _buildLobby();
  }

  Widget _buildGameSetup() {
    return Scaffold(
      appBar: AppBar(title: const Text("Configurar Partida")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("CREAR NUEVA PARTIDA"),
              onPressed: _createGame,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 30),
            const Text("O", style: TextStyle(fontSize: 20)),
            const SizedBox(height: 30),
            TextField(
              controller: _gameCodeController,
              decoration: const InputDecoration(
                labelText: "Introduce el código de la partida",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text("UNIRSE A PARTIDA EXISTENTE"),
              onPressed: _joinGame,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobby() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sala de Espera"),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _exitGame,
            tooltip: "Salir de la partida",
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 30),
          const Text("CÓDIGO DE SALA:", style: TextStyle(fontSize: 20)),
          Text(
            gameCode ?? "----",
            style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const Text("JUGADORES CONECTADOS:", style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: StreamBuilder(
              stream: _dbRef.child('partidas').child(gameCode!).child('players').onValue,
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
                      trailing: Text("${playersList[index]['score'] ?? 0} pts"),
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
            stream: _dbRef.child('partidas').child(gameCode!).child('current_answers').onValue,
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
          if (_timeLeft == 0)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton(
                onPressed: _showScoreboard,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text("Ver Podium", style: TextStyle(fontSize: 20)),
              ),
            ),
          if (_timeLeft > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: ElevatedButton.icon(
                onPressed: _skipQuestion,
                icon: const Icon(Icons.skip_next),
                label: const Text("Omitir"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 5),
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

  Widget _buildScoreboardUI() {
    return Scaffold(
      backgroundColor: Colors.deepPurple,
      appBar: AppBar(title: const Text("Ranking Top 5"), backgroundColor: Colors.transparent, elevation: 0),
      body: StreamBuilder(
        stream: _dbRef.child('partidas').child(gameCode!).child('players').onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          Map playersMap = snapshot.data!.snapshot.value as Map;
          List playersList = playersMap.values.toList();
          
          playersList.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
          
          int topCount = playersList.length > 5 ? 5 : playersList.length;
          List topPlayers = playersList.sublist(0, topCount);

          return Column(
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.leaderboard, size: 80, color: Colors.yellow),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  itemCount: topPlayers.length,
                  itemBuilder: (context, index) {
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Text("${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        title: Text(topPlayers[index]['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        trailing: Text("${topPlayers[index]['score']} pts", style: const TextStyle(fontSize: 20, color: Colors.purple, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
              if (_currentQuestionIndex < _questions.length - 1)
                Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: ElevatedButton(
                    onPressed: _nextQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.deepPurple,
                      minimumSize: const Size(double.infinity, 60),
                    ),
                    child: const Text("Siguiente Pregunta", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(30.0),
                  child: Text("¡Fin del juego! 🎉", style: TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ],
          );
        }
      ),
    );
  }
}
