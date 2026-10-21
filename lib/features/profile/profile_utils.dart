String profileHandleForName(String name) {
  final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final safeName = normalized.isEmpty ? 'developer' : normalized;
  return '@${safeName.length > 40 ? safeName.substring(0, 40) : safeName}';
}

List<String> profileSearchPrefixes(
  String name,
  String handle, [
  List<String> keywords = const [],
]) {
  final normalizedName = name.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  final normalizedHandle = handle.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  final words = name.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
  final terms = <String>{
    normalizedName,
    normalizedHandle,
    ...words.where((word) => word.isNotEmpty),
    ...keywords.map(
      (keyword) => keyword.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
    ),
    ...keywords.expand(
      (keyword) => keyword
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((word) => word.isNotEmpty),
    ),
  }..remove('');

  final prefixes = <String>{};
  for (final term in terms) {
    final maxLength = term.length < 24 ? term.length : 24;
    for (var length = 1; length <= maxLength; length++) {
      prefixes.add(term.substring(0, length));
    }
  }
  final sorted = prefixes.toList()..sort();
  return sorted.take(100).toList();
}
