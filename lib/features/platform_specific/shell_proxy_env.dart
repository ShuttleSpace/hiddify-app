import 'dart:io';

/// Terminal proxies configured through an exported HTTP_PROXY survive us
/// stopping. A running shell keeps the environment it was started with and no
/// other process can rewrite it, so the only thing left to do is to tell the user
/// what to run. That makes detection the whole problem: `Platform.environment`
/// reflects launchd for a Dock-launched app, not the user's interactive shell, so
/// we look at the shell profiles instead.
abstract class ShellProxyEnv {
  static const _profilePaths = <String>[
    '.zshrc',
    '.zprofile',
    '.zshenv',
    '.bash_profile',
    '.bashrc',
    '.profile',
    '.config/fish/config.fish',
  ];

  static const _exportedNames = <String>['http_proxy', 'https_proxy'];

  /// Whether any shell profile exports a proxy variable. An unreadable profile is
  /// not an error: this is advisory, so a missing file just means "no evidence".
  static Future<bool> anyProfileExportsProxy() async {
    final home = _homeDirectory();
    if (home == null) return false;
    for (final relativePath in _profilePaths) {
      try {
        final content = await File('$home/$relativePath').readAsString();
        final lowerCased = content.toLowerCase();
        if (_exportedNames.any(lowerCased.contains)) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  /// Clears the proxy variables in an already running shell. NO_PROXY is
  /// deliberately left alone: it keeps loopback traffic local and is harmless
  /// without a proxy to bypass.
  static String cleanupCommand() => 'unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy';

  static String? _homeDirectory() {
    try {
      return Platform.environment['HOME'];
    } catch (_) {
      return null;
    }
  }
}
