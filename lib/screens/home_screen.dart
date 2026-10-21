import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user.dart';

class HomeScreen extends StatefulWidget{
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum ProcessState {
  start,
  processing,
  completed,
}


class _HomeScreenState extends State<HomeScreen>{

  Future<void> fetchUsers() async {
    setState(() {
      isLoading = true;
    });

    await Future.delayed(
      const Duration(seconds: 5),
    );

    try{
      final response = await http.get(
        Uri.parse("https://jsonplaceholder.typicode.com/users")
      );

      if(response.statusCode == 200){
        print(response.body);

        final data = jsonDecode(response.body) as List<dynamic>;

        final parsedUsers = data
          .map<User>(
            (json) => User.fromJson(json as Map<String, dynamic>),
          ).toList();

          setState(() {
            users = parsedUsers;
            name = "Success: ${users.length} items fetched";
            isLoading = false;
          });
      } else {
        setState(() {
          if (response.statusCode == 404) {
            name = "Error: ${response.statusCode} Not Found";
          } else if (response.statusCode == 500) {
            name = "Error: ${response.statusCode} Internal Server Error";
          } else {
            name = "Error: ${response.statusCode} Something went wrong!";
          }
          isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      setState(() {
        name = "Network Error: Please check your internet connection. ";
        isLoading = false;
      });
    }
  }


  final TextEditingController nameController = TextEditingController();

  final TextEditingController departmentController = TextEditingController();

  bool isLoading = false;

  ProcessState processState = ProcessState.start;

  String name = "Ready";

  List<Map<String, dynamic>> datahold = [];

  List<User> users = [];

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            SizedBox(height: 20),

            SizedBox(
              width: 200,
              child: TextField(
                controller: nameController,
                obscureText: false,
                decoration: InputDecoration(
                  labelText: 'Enter Your Name!',
                  border: OutlineInputBorder()
                ),
              ),
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () async {
                final result = await Navigator.pushReplacementNamed(
                  context,
                  "/profile",
                  arguments: nameController.text,
                );
                print(result);
              },
              child: const Text("Go to Profile")
            ),

            SizedBox(height: 20),

            SizedBox(
              width: 200,
              child: TextField(
                obscureText: false,
                controller: departmentController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Enter The department test'
                ),
              ),
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  "/test",
                  arguments: departmentController.text
                );

              },
              child: const Text("Go to test Screen")
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () async{
                setState(() {
                  isLoading = true;

                });
                await Future.delayed(
                  const Duration(seconds: 3)
                );
                setState(() {
                  isLoading = false;
                });
              },
              child: const Text("Future Test")
            ),

            SizedBox(height: 20),

            Text(
              isLoading ? "Loading..." : "Not Loading",
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () async {
                setState(() {
                  processState = ProcessState.processing;
                });
                await Future.delayed(
                  const Duration(seconds: 2),
                );
                setState(() {
                  processState = ProcessState.completed;
                });
              },
              child: const Text("Future Test2"),
            ),

            SizedBox(height: 20),

            Text(
              processState == ProcessState.processing
                  ? "Processing..."
                  : processState == ProcessState.start
                    ? "Start"
                    : "Completed! ✅",
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: isLoading ? null : fetchUsers,
              child: const Text("HTTP Request Test"),
            ),

            SizedBox(height: 20),

            Text(
              isLoading ? "Loading..." : name,
            ),

            SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black),
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Name: ${users[index].name}"),
                        Text("Email: ${users[index].email}"),
                        Text("ID: ${users[index].id}"),
                        Text("Username: ${users[index].username}"),
                        SizedBox(height: 5),
                    ],
                    ));
                  },
                ),
              ),
          ],
        )
      )
    );
  }
  @override
  void dispose(){
    nameController.dispose();
    departmentController.dispose();
    super.dispose();
  }
}