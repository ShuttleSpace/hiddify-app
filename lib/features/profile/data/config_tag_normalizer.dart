import 'dart:convert';

/// Makes the tags in a sing-box config unique.
///
/// sing-box gives every outbound and endpoint a tag, and the two share one
/// namespace, so two of them with the same tag make the whole config invalid:
/// "duplicate outbound/endpoint tag: proxy". The core renames duplicates when
/// it reads a list of links, but a config that arrives as JSON is taken as
/// written, so the app has to do it before handing the config over.
///
/// The later duplicates get a name of their own ("proxy" becomes "proxy 2")
/// and the references that point at them follow, so both nodes survive.
class ConfigTagNormalizer {
  const ConfigTagNormalizer._();

  /// Returns [content] with unique outbound and endpoint tags.
  ///
  /// Content that is not a JSON config is returned unchanged: the core knows
  /// how to read links and clash configs, and it gives their nodes unique
  /// names on its own.
  static String normalize(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return content;
    }

    final List<Map<String, dynamic>> outbounds;
    final List<Map<String, dynamic>> endpoints;
    if (decoded is List) {
      // A bare list of outbounds is a config too.
      outbounds = decoded.whereType<Map<String, dynamic>>().toList();
      endpoints = const [];
    } else if (decoded is Map<String, dynamic>) {
      outbounds = _mapsOf(decoded['outbounds']);
      endpoints = _mapsOf(decoded['endpoints']);
    } else {
      return content;
    }

    final names = _renameDuplicates([...outbounds, ...endpoints]);
    if (names.isEmpty) return content;

    _rewriteMemberLists(outbounds, names);

    return jsonEncode(decoded);
  }

  static List<Map<String, dynamic>> _mapsOf(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

  /// Renames the outbounds and endpoints that share a tag.
  ///
  /// Returns the names each duplicated tag got, in the order the nodes with
  /// that tag appear, so a reference can be pointed at the node it meant.
  static Map<String, List<String>> _renameDuplicates(List<Map<String, dynamic>> items) {
    final used = <String>{};
    final names = <String, List<String>>{};

    for (final item in items) {
      final tag = item['tag'];
      if (tag is! String || tag.isEmpty) continue;

      if (!used.contains(tag)) {
        used.add(tag);
        names.putIfAbsent(tag, () => [tag]);
        continue;
      }

      final candidates = names[tag]!;
      var number = candidates.length + 1;
      var name = '$tag $number';
      while (used.contains(name)) {
        number++;
        name = '$tag $number';
      }
      candidates.add(name);
      used.add(name);
      item['tag'] = name;
    }

    return {for (final entry in names.entries) if (entry.value.length > 1) entry.key: entry.value};
  }

  /// Points the member list of a selector, urltest or balancer at the node it
  /// named.
  ///
  /// A member list that names a duplicated tag once per node is the only way
  /// to tell which node was meant, so the n-th mention follows the n-th node
  /// with that tag. A mention with no node to point at is left alone.
  static void _rewriteMemberLists(List<Map<String, dynamic>> outbounds, Map<String, List<String>> names) {
    for (final outbound in outbounds) {
      final members = outbound['outbounds'];
      if (members is! List) continue;

      final mentions = <String, int>{};
      outbound['outbounds'] = members.map((member) {
        if (member is! String || !names.containsKey(member)) return member;
        final index = mentions.update(member, (count) => count + 1, ifAbsent: () => 0);
        final alternatives = names[member]!;
        return index < alternatives.length ? alternatives[index] : member;
      }).toList();
    }
  }
}
