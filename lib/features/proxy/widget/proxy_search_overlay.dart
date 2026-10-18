import 'package:flutter/material.dart';
import 'package:hiddify/features/proxy/domain/proxy_search.dart';
import 'package:hiddify/features/proxy/model/proxy_search_result.dart';

class ProxySearchOverlay extends StatelessWidget {
  const ProxySearchOverlay({super.key, required this.results, required this.onSelected});

  final List<ProxySearchResult> results;
  final ValueChanged<ProxySearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    return Material(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
            title: Text(result.groupTag),
            subtitle: Text('${result.nodeTag} - ${formatProxySearchDelay(result.delay)}'),
            onTap: () => onSelected(result),
          );
        },
      ),
    );
  }
}
