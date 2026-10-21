import 'package:flutter/material.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {


  const ProfileScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {

    final username = ModalRoute.of(context)!.settings.arguments as String;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
      ),
      body: Center(
        child: Column(
          children: [
            Text("Welcome, $username"),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: (){
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen())
                );
              },
              child: const Text("Go to settings screen")
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: (){
                Navigator.pop(
                  context, "Got back to the Home..Congrats!"
                );
              },
              child: const Text("GO Back To Home"))
          ],
        ),
      ),
    );
  }
}