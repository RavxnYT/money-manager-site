import 'package:flutter/material.dart';

import '../../core/ai/finance_numeric_snapshot.dart';
import '../../core/ai/gemini_insights_client.dart';
import '../../core/ui/glass_panel.dart';

/// Loads Google Gemini coaching text from [snapshot] only (no extra PII).
class GeminiCoachCard extends StatefulWidget {
  const GeminiCoachCard({super.key, required this.snapshot});

  final FinanceNumericSnapshot snapshot;

  @override
  State<GeminiCoachCard> createState() => _GeminiCoachCardState();
}

class _GeminiCoachCardState extends State<GeminiCoachCard> {
  Future<String?>? _future;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    if (GeminiInsightsClient.isConfigured) {
      _attempt = 1;
      _future = GeminiInsightsClient.generateCoachNarrative(widget.snapshot);
    }
  }

  @override
  void didUpdateWidget(GeminiCoachCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.toJsonString() != widget.snapshot.toJsonString() &&
        GeminiInsightsClient.isConfigured) {
      setState(() {
        _attempt++;
        _future = GeminiInsightsClient.generateCoachNarrative(widget.snapshot);
      });
    }
  }

  void _startLoad() {
    if (!GeminiInsightsClient.isConfigured) return;
    setState(() {
      _attempt++;
      _future = GeminiInsightsClient.generateCoachNarrative(widget.snapshot);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!GeminiInsightsClient.isConfigured) {
      return GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI coach (Gemini)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Add GEMINI_API_KEY to your .env file (and add .env as an asset in '
                'pubspec) so it ships in the app build. Only numeric summaries are '
                'sent—no names or merchants.',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI coach (Gemini)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  'Privacy-safe',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Uses only rounded totals and codes from this screen—not notes, names, or accounts.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<String?>(
              key: ValueKey(_attempt),
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final text = snap.data;
                if (text == null || text.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Couldn’t load AI tips right now. Your rule-based insights above still apply.',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Common causes: wrong or expired API key, no internet, Google AI Studio '
                        'quota/billing, or your region not supporting the Gemini API. '
                        'Run in debug to see logs from GeminiInsightsClient.',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _startLoad,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('Try again'),
                      ),
                    ],
                  );
                }
                return Text(
                  text,
                  style: const TextStyle(
                    height: 1.35,
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
