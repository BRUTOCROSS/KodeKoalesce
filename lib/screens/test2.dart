import 'package:flutter/material.dart';
import 'home_screen.dart';

class Test2Screen extends StatelessWidget{
  const Test2Screen({super.key});

  @override
  Widget build(BuildContext context){

    final fieldValue = ModalRoute.of(context)!.settings.arguments as String;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Test 2")
      ),

      body: Center(
        child: Column(
          children: [
            Text("Welcome $fieldValue"),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: (){
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HomeScreen()
                  ),
                  (route) => false,
                );
              },
              child: const Text("Start Over")
            )
          ],
        ),
      ),
    );
  }
}