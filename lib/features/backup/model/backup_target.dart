enum BackupTarget {
  local,
  webdav;

  String get label => switch (this) {
    local => 'Local',
    webdav => 'WebDAV',
  };
}
