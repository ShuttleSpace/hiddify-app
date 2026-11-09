/// The outbounds of a config that belong to the user.
///
/// The core builds outbounds of its own - the selector, the balancer and the
/// direct ones - and marks the ones it hides with a "§hide§". They belong to
/// the running config, not to the user's nodes, so the editor leaves them out
/// and a save does not write them back into the profile.
List<Map<String, dynamic>> userOutbounds(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return const [];

  return outbounds.whereType<Map<String, dynamic>>().where((outbound) {
    final type = outbound['type'];
    if (type is! String) return false;
    // The groups - the selector, the auto-select and the balancer - are the
    // core's to build, not nodes of their own.
    if (const ['selector', 'urltest', 'balancer', 'dns', 'block'].contains(type)) return false;
    return !_isCoreOutbound(outbound['tag']);
  }).toList();
}

/// Whether the tag belongs to an outbound the core builds itself.
///
/// The core marks the outbounds it hides with a "§hide§", so the tag of its
/// direct outbound is "direct §hide§" and not "direct".
bool _isCoreOutbound(Object? tag) {
  if (tag is! String) return false;
  final name = tag.split('§').first.trim();
  return const ['direct', 'bypass', 'direct-fragment', 'block'].contains(name);
}
