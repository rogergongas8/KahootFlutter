import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';

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
      // Guardamos al jugador en Firebase
      await _dbRef.child('partidas').child(code).child('players').child(name).set({
        'name': name,
        'score': 0,
      });

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
      backgroundColor: const Color(0xFF46178f), // Kahoot Purple
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 4)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Kahoot!", 
                  style: GoogleFonts.montserrat(fontSize: 32, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "PIN del juego",
                    hintStyle: GoogleFonts.montserrat(color: Colors.grey[400], fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFcccccc), width: 2.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFF333333), width: 2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "Nombre",
                    hintStyle: GoogleFonts.montserrat(color: Colors.grey[400], fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFcccccc), width: 2.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFF333333), width: 2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _joinGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF333333), // Botón negro característico
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  child: Text("Ingresar", style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
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

        // Diseño original de Sala de Espera verde
        return Scaffold(
          backgroundColor: const Color(0xFF26890c), // Grass Green for joined
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("¡Estás dentro!", style: GoogleFonts.montserrat(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                const SizedBox(height: 20),
                Text("¿Ves tu nombre en la pantalla?", style: GoogleFonts.montserrat(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                const SizedBox(height: 60),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 4)],
                  ),
                  child: Text(playerName, style: GoogleFonts.montserrat(color: Colors.black, fontSize: 32, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- NUEVA PANTALLA: Botones de Colores del Alumno ---
class ClientGameScreen extends StatefulWidget {
  final String gameCode;
  final String playerName;
  final Map questionData;

  const ClientGameScreen({super.key, required this.gameCode, required this.playerName, required this.questionData});

  @override
  State<ClientGameScreen> createState() => _ClientGameScreenState();
}

class _ClientGameScreenState extends State<ClientGameScreen> {
  late ConfettiController _confettiController;
  bool _confettiPlayed = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _submitAnswer(int index) async {
    if (widget.questionData['status'] == 'showing') {
      await FirebaseDatabase.instance
          .ref()
          .child('partidas')
          .child(widget.gameCode)
          .child('current_answers')
          .child(widget.playerName)
          .set({
        'answerIndex': index,
        'answeredAt': ServerValue.timestamp,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String status = widget.questionData['status'];
    final List<Color> kahootColors = [
      const Color(0xFFe21b3c),
      const Color(0xFF1368ce),
      const Color(0xFFd89e00),
      const Color(0xFF26890c),
    ];

    final List<Color> darkColors = [
      const Color(0xFFb0102b),
      const Color(0xFF0a4ba3),
      const Color(0xFFa67900),
      const Color(0xFF196105),
    ];

    final List<IconData> kahootIcons = [
      Icons.change_history,
      Icons.square_outlined,
      Icons.circle,
      Icons.square,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFf2f2f2),
      appBar: AppBar(
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Text("PIN: ${widget.gameCode}", style: GoogleFonts.montserrat(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        backgroundColor: Colors.white, 
        elevation: 1,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder(
        stream: FirebaseDatabase.instance.ref().child('partidas').child(widget.gameCode).child('current_answers').child(widget.playerName).onValue,
        builder: (context, snapshot) {
          bool hasAnswered = snapshot.hasData && snapshot.data!.snapshot.value != null;
          int? answeredIndex;
          if (hasAnswered) {
             answeredIndex = (snapshot.data!.snapshot.value as Map)['answerIndex'] as int;
          }

          Widget currentScreen;

          if (status == 'scoreboard') {
             _confettiPlayed = false;
             currentScreen = Container(
               key: const ValueKey('scoreboard'),
               color: const Color(0xFF1368ce),
               alignment: Alignment.center,
               padding: const EdgeInsets.all(20),
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Text("Puntaje", style: GoogleFonts.montserrat(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                   const SizedBox(height: 20),
                   Container(
                     padding: const EdgeInsets.all(20),
                     decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                     child: const Icon(Icons.leaderboard, color: Colors.white, size: 80),
                   ),
                   const SizedBox(height: 20),
                   Text("El profesor está mostrando el Podium", style: GoogleFonts.montserrat(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                 ],
               ),
             );
          } else if (status == 'finished') {
             bool isCorrect = answeredIndex == widget.questionData['correctIndex'];
             
             if (isCorrect && !_confettiPlayed) {
               _confettiPlayed = true;
               _confettiController.play();
             }

             currentScreen = StreamBuilder(
               key: const ValueKey('finished'),
               stream: FirebaseDatabase.instance.ref().child('partidas').child(widget.gameCode).child('players').child(widget.playerName).onValue,
               builder: (context, playerSnapshot) {
                 int earned = 0;
                 int total = 0;
                 if (playerSnapshot.hasData && playerSnapshot.data!.snapshot.value != null) {
                   Map pData = playerSnapshot.data!.snapshot.value as Map;
                   earned = pData['lastRoundPoints'] ?? 0;
                   total = pData['score'] ?? 0;
                 }

                 return Stack(
                   alignment: Alignment.center,
                   children: [
                     Container(
                       color: isCorrect ? const Color(0xFF26890c) : const Color(0xFFe21b3c),
                       alignment: Alignment.center,
                       child: Column(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: [
                           Text(
                             isCorrect ? "Correcto" : "Incorrecto",
                             style: GoogleFonts.montserrat(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                           ),
                           const SizedBox(height: 20),
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                             decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                             child: Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 Icon(isCorrect ? Icons.local_fire_department : Icons.close, color: Colors.white, size: 30),
                                 const SizedBox(width: 10),
                                 Text(isCorrect ? "+$earned" : "+0", style: GoogleFonts.montserrat(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                               ],
                             ),
                           ),
                           const SizedBox(height: 50),
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                             decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4)),
                             child: Column(
                               children: [
                                 Text("Puntos totales", style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                                 Text("$total", style: GoogleFonts.montserrat(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                               ],
                             ),
                           ),
                         ],
                       ),
                     ),
                     if (isCorrect)
                       ConfettiWidget(
                         confettiController: _confettiController,
                         blastDirectionality: BlastDirectionality.explosive,
                         shouldLoop: false,
                         colors: kahootColors,
                       ),
                   ],
                 );
               }
             );
          } else if (hasAnswered) {
             currentScreen = Container(
               key: const ValueKey('waiting_others'),
               color: const Color(0xFFd89e00),
               alignment: Alignment.center,
               child: Text(
                 "¿Genio o golpe de suerte?\nEsperando a los demás...", 
                 style: GoogleFonts.montserrat(color: Colors.black, fontSize: 28, fontWeight: FontWeight.bold), 
                 textAlign: TextAlign.center
               ),
             );
          } else {
            currentScreen = Padding(
              key: const ValueKey('answering'),
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildAnswerButton(0, kahootColors[0], darkColors[0], kahootIcons[0], () => _submitAnswer(0))),
                        const SizedBox(width: 10),
                        Expanded(child: _buildAnswerButton(1, kahootColors[1], darkColors[1], kahootIcons[1], () => _submitAnswer(1))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildAnswerButton(2, kahootColors[2], darkColors[2], kahootIcons[2], () => _submitAnswer(2))),
                        const SizedBox(width: 10),
                        Expanded(child: _buildAnswerButton(3, kahootColors[3], darkColors[3], kahootIcons[3], () => _submitAnswer(3))),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: currentScreen,
          );
        }
      ),
    );
  }

  Widget _buildAnswerButton(int index, Color color, Color shadowColor, IconData shape, VoidCallback onTap) {
    return BouncyAnswerButton(
      index: index,
      color: color,
      shadowColor: shadowColor,
      shape: shape,
      onTap: onTap,
    );
  }
}

class BouncyAnswerButton extends StatefulWidget {
  final int index;
  final Color color;
  final Color shadowColor;
  final IconData shape;
  final VoidCallback onTap;

  const BouncyAnswerButton({
    super.key,
    required this.index,
    required this.color,
    required this.shadowColor,
    required this.shape,
    required this.onTap,
  });

  @override
  State<BouncyAnswerButton> createState() => _BouncyAnswerButtonState();
}

class _BouncyAnswerButtonState extends State<BouncyAnswerButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(widget.shape, size: 80, color: Colors.white);
    if (widget.index == 1) { 
      iconWidget = Transform.rotate(angle: pi / 4, child: const Icon(Icons.square, size: 60, color: Colors.white));
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: widget.shadowColor,
                spreadRadius: 0,
                blurRadius: 0,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Center(
            child: iconWidget,
          ),
        ),
      ),
    );
  }
}