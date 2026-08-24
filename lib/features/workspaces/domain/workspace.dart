final class Workspace {
  const Workspace({
    required this.id,
    required this.path,
    required this.name,
    required this.openCount,
    required this.createdAt,
    required this.lastUsedAt,
  });

  final String id;
  final String path;
  final String name;
  final int openCount;
  final DateTime createdAt;
  final DateTime lastUsedAt;
}
