class AppUser {
  final String id;
  final String email;
  final String username;
  final String? arbaNumber;

  AppUser({
    required this.id,
    required this.email,
    required this.username,
    this.arbaNumber,
  });

  factory AppUser.fromMap(Map<String, dynamic> data) {
    return AppUser(
      id: data['id'],
      email: data['email'],
      username: data['username'],
      arbaNumber: data['arba_number'],
    );
  }
}