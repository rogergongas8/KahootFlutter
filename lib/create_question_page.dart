import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';

class CreateQuestionPage extends StatefulWidget {
  const CreateQuestionPage({super.key});

  @override
  State<CreateQuestionPage> createState() => _CreateQuestionPageState();
}

class _CreateQuestionPageState extends State<CreateQuestionPage> {
  final _preguntaController = TextEditingController();
  final List<TextEditingController> _respuestasControllers = List.generate(4, (_) => TextEditingController());
  final _dbRef = FirebaseDatabase.instance.ref();
  final _grupoController = TextEditingController();
  int _correctIndex = 0; // Por defecto la primera es la correcta



  void _guardarPregunta() async {
    // Verificamos que no haya campos vacíos
    if (_preguntaController.text.isEmpty || _respuestasControllers.any((c) => c.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rellena todos los campos")));
      return;
    }

    // Guardamos en Firebase en la colección 'banco_preguntas'
    String grupo = _grupoController.text.trim().isEmpty ? "General" : _grupoController.text.trim();
    await _dbRef.child('banco_preguntas').child(grupo).push().set({      'text': _preguntaController.text.trim(),
      'options': _respuestasControllers.map((c) => c.text.trim()).toList(),
      'correctIndex': _correctIndex,
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Pregunta guardada con éxito! 🎉")));
    
    // Limpiamos el formulario para la siguiente pregunta
    _preguntaController.clear();
    for (var c in _respuestasControllers) { c.clear(); }
    setState(() => _correctIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> kahootColors = [
      const Color(0xFFe21b3c), // Rojo
      const Color(0xFF1368ce), // Azul
      const Color(0xFFd89e00), // Amarillo
      const Color(0xFF26890c), // Verde
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFf2f2f2),
      appBar: AppBar(
        title: Text("Crear Pregunta", style: GoogleFonts.montserrat(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Campo de la pregunta
            TextField(
                controller: _grupoController,
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                    hintText: "Nombre del Grupo (Ej. Mates)",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                ),
                const SizedBox(height: 15),
            TextField(
              controller: _preguntaController,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "Escribe tu pregunta aquí",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 30),
            
            // Campos de las 4 respuestas
            ...List.generate(4, (index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kahootColors[index].withOpacity(0.1),
                  border: Border.all(color: kahootColors[index], width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Radio<int>(
                      value: index,
                      groupValue: _correctIndex,
                      onChanged: (val) => setState(() => _correctIndex = val!),
                      activeColor: kahootColors[index],
                    ),
                    Expanded(
                      child: TextField(
                        controller: _respuestasControllers[index],
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: "Respuesta ${index + 1} ${index == _correctIndex ? '(Correcta)' : ''}",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _guardarPregunta,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF46178f), // Morado Kahoot
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text("Guardar Pregunta", style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}