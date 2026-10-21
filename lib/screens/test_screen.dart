import 'package:flutter/material.dart';
import 'home_screen.dart';

class TestScreen extends StatelessWidget{

  const TestScreen({super.key});

  @override
  Widget build(BuildContext context){

    final department = ModalRoute.of(context)!.settings.arguments as String;

    final TextEditingController fieldController = TextEditingController();

    final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Testing App")
      ),

      body: Center(
        child: Column(
          children: [
            Text("Welcome to $department"),

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
            ),

            SizedBox(height: 20),


            Form(
              key: _formKey,
              child: SizedBox(
                width: 200,
                child: TextFormField(

                  validator: (value){
                    if(value == null || value.isEmpty){
                      return "Please enter some text!";
                    }
                    return null;
                  },
                  controller: fieldController,
                  obscureText: false,
                  decoration: InputDecoration(
                    labelText: 'Enter Your Field!',
                    border: OutlineInputBorder()
                  ),
                ),
              )
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () async {
                if(_formKey.currentState!.validate()){
                  final result = await Navigator.pushNamed(
                    context,
                    "/test2",
                    arguments: fieldController.text
                  );
                  print(result);
                }
              },
              child: const Text("Go to Test2"),
            )
          ],
        ),
      ),
    );
  }
}