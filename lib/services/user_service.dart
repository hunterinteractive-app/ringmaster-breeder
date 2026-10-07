class AppUser {
  final String id;
  final String email;

  AppUser({required this.id, required this.email});

  factory AppUser.fromAppwrite(dynamic user) {
    return AppUser(
      id: user.$id,
      email: user.email,
    );
  }
}