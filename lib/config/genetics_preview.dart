/// Temporary visibility rule for the unreleased Genetics interface.
/// Use the signed-in identity, never the selected family's owner/profile email.
class GeneticsPreview {
  static bool allowsEmail(String? email) =>
      email?.trim().toLowerCase() == 'zaynetort2@gmail.com';

  static const disclaimer =
      'These predictions are estimates, not guarantees. Rabbit genetics can be '
      'complicated, and unexpected colors or other variations may occur. Results '
      'depend on the accuracy and completeness of the information recorded for '
      'both rabbits.';
}
