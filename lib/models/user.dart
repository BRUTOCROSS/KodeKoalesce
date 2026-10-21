class User{
  int id;
  String name;
  String email;
  String username;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.username
  });



    factory User.fromJson(Map<String, dynamic> json){
      return User(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        username: json['username'],
      );
    }
}
