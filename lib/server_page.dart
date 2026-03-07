import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:confetti/confetti.dart';
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

  late ConfettiController _confettiController;
  bool _confettiPlayed = false;

  // Preguntas de prueba
  final List<Question> _questions = [
    Question("¿Cuál es la capital de Francia?", ["Madrid", "París", "Roma", "Berlín"], 1),
    Question("¿Cuánto es 2 + 2?", ["3", "4", "5", "6"], 1),
    Question("¿De qué color es el cielo despejado?", ["Verde", "Azul", "Rojo", "Amarillo"], 1),
  ];

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _createGame();
  }

  @override
  void dispose() {
    _gameCodeController.dispose();
    _timer?.cancel();
    _answersSubscription?.cancel();
    _confettiController.dispose();
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
    _confettiPlayed = false; // Reset confederate flag for next run if needed
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
           if (mounted) {
             setState(() {
               _timeLeft = 0;
             });
           }
           _endQuestion();
        }
      }
    });
  }

  void _skipQuestion() {
    _timer?.cancel();
    _answersSubscription?.cancel();
    if (mounted) {
      setState(() {
        _timeLeft = 0;
      });
    }
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
      backgroundColor: const Color(0xFF46178f), // Kahoot Purple 
      appBar: AppBar(
        title: Text("Pin de la sala: $gameCode", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          Text(
            "Únete en www.kahoot.it\no con la app de Kahoot!",
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 4)],
            ),
            child: Text(
              gameCode,
              style: GoogleFonts.montserrat(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 8,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.white.withOpacity(0.1),
              child: gameCode == "Generando..."
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : StreamBuilder(
                      stream: _dbRef.child('partidas').child(gameCode).child('players').onValue,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                          return Center(
                            child: Text(
                              "Esperando jugadores...",
                              style: GoogleFonts.montserrat(fontSize: 24, color: Colors.white54, fontWeight: FontWeight.bold),
                            ),
                          );
                        }
                        Map<dynamic, dynamic> playersMap = snapshot.data!.snapshot.value as Map;
                        List<dynamic> playersList = playersMap.values.toList();
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(15.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                                    child: Text(
                                      "${playersList.length} Jugadores",
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: GridView.builder(
                                padding: const EdgeInsets.all(20),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 150,
                                  childAspectRatio: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: playersList.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 2), blurRadius: 2)],
                                    ),
                                    child: Text(
                                      playersList[index]['name'] ?? 'Incógnito',
                                      style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1368ce), // True Blue
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text("Empezar", style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameUI() {
    Question q = _questions[_currentQuestionIndex];
    // Kahoot Authentic Colors
    final List<Color> kahootColors = [
      const Color(0xFFe21b3c), // Red
      const Color(0xFF1368ce), // Blue
      const Color(0xFFd89e00), // Yellow
      const Color(0xFF26890c), // Green
    ];

    // Kahoot Dark Shadows for 3D effect
    final List<Color> darkColors = [
      const Color(0xFFb0102b), // Dark Red
      const Color(0xFF0a4ba3), // Dark Blue
      const Color(0xFFa67900), // Dark Yellow
      const Color(0xFF196105), // Dark Green
    ];

    // Kahoot Authentic Icons
    final List<IconData> kahootIcons = [
      Icons.change_history, // Triangle (Red)
      Icons.square_outlined, // Fake Diamond - rotated square (Blue)
      Icons.circle, // Circle (Yellow)
      Icons.square, // Square (Green)
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFf2f2f2), // Light gray background
      body: Column(
        children: [
          // Header with question and pin
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(top: 40, bottom: 20, left: 20, right: 20),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("PIN: $gameCode", style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54)),
                if (_timeLeft > 0)
                  ElevatedButton.icon(
                    onPressed: _skipQuestion,
                    icon: const Icon(Icons.skip_next, size: 20),
                    label: const Text("Omitir"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black12,
                      foregroundColor: Colors.black,
                      elevation: 0,
                    ),
                  ),
              ],
            ),
          ),
          
          Expanded(
            flex: 2,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  q.text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            ),
          ),
          
          // Center Info (Timer and Answers)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFF46178f),
                  child: Text(
                    "$_timeLeft",
                    style: GoogleFonts.montserrat(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 30),
                child: StreamBuilder(
                  stream: _dbRef.child('partidas').child(gameCode).child('current_answers').onValue,
                  builder: (context, snapshot) {
                    int count = 0;
                    if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                      count = (snapshot.data!.snapshot.value as Map).length;
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("$count", style: GoogleFonts.montserrat(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black)),
                        Text("respuestas", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
                      ],
                    );
                  }
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 30),

          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildTeacherOption(0, kahootColors[0], darkColors[0], kahootIcons[0], q)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildTeacherOption(1, kahootColors[1], darkColors[1], kahootIcons[1], q)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildTeacherOption(2, kahootColors[2], darkColors[2], kahootIcons[2], q)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildTeacherOption(3, kahootColors[3], darkColors[3], kahootIcons[3], q)),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1368ce),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                ),
                child: Text("Siguiente", style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTeacherOption(int index, Color color, Color shadowColor, IconData shape, Question q) {
    bool showCorrect = _timeLeft == 0 && index == q.correctIndex;
    bool showWrong = _timeLeft == 0 && index != q.correctIndex;
    
    // Si queremos el diamante inclinamos el icono de cuadrado
    Widget iconWidget = Icon(shape, size: 40, color: Colors.white);
    if (index == 1) { // Blue/Diamond
      iconWidget = Transform.rotate(angle: pi / 4, child: const Icon(Icons.square, size: 30, color: Colors.white));
    }
    
    return Container(
      decoration: BoxDecoration(
        color: showWrong ? Colors.grey[300] : color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: showWrong ? [] : [
          BoxShadow(
            color: shadowColor,
            spreadRadius: 0,
            blurRadius: 0,
            offset: const Offset(0, 6), // Premium bottom distinct shadow
          )
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          showWrong && _timeLeft == 0 
              ? const SizedBox(width: 40) // Placeholder
              : iconWidget,
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              q.options[index],
              style: GoogleFonts.montserrat(
                color: showWrong ? Colors.black38 : Colors.white, 
                fontSize: 28, 
                fontWeight: FontWeight.bold
              ),
            ),
          ),
          if (showCorrect)
            const Icon(Icons.check_circle, color: Colors.white, size: 40),
        ],
      ),
    );
  }

  Widget _buildScoreboardUI() {
    return Scaffold(
      backgroundColor: const Color(0xFF46178f),
      appBar: AppBar(title: Text("Podium", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0),
      body: Stack(
        children: [
          StreamBuilder(
            stream: _dbRef.child('partidas').child(gameCode).child('players').onValue,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              Map playersMap = snapshot.data!.snapshot.value as Map;
              List playersList = playersMap.values.toList();
              
              playersList.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
              int topCount = playersList.length > 5 ? 5 : playersList.length;
              List topPlayers = playersList.sublist(0, topCount);

              return Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text("Resultados Finales", style: GoogleFonts.montserrat(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 30),
                    Expanded(
                      child: ListView.builder(
                        itemCount: topPlayers.length,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 4)],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              leading: Text(
                                "${index + 1}", 
                                style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFF46178f))
                              ),
                              title: Text(
                                topPlayers[index]['name'], 
                                style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)
                              ),
                              trailing: Text(
                                "${topPlayers[index]['score']}", 
                                style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_currentQuestionIndex < _questions.length - 1)
                      ElevatedButton(
                        onPressed: _nextQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1368ce),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        child: Text("Siguiente Pregunta", style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold)),
                      )
                    else
                      Text("¡Fin del juego! 🎉", style: GoogleFonts.montserrat(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }
          ),
          
          // Confetti Cannons
          Align(
            alignment: Alignment.centerLeft,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: -pi / 4, // Up and Right
              maxBlastForce: 50,
              minBlastForce: 20,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.1,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: -3 * pi / 4, // Up and Left
              maxBlastForce: 50,
              minBlastForce: 20,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
