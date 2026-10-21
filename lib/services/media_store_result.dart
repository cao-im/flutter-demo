class OpenResult {
  final String path;
  final bool opened;
  final String folder;
  final bool downloaded;

  const OpenResult({
    this.path = '',
    this.opened = false,
    this.folder = '',
    this.downloaded = false,
  });
}
