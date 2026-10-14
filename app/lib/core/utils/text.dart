/// A business name as it should read on screen: the first letter upper-cased,
/// so a name typed in lower case ("ada provisions") still presents properly
/// without changing how it was stored.
String capitalizeName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}
