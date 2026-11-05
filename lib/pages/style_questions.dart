import 'package:flutter/material.dart';

import '../engine.dart';
import '../project.dart';
import '../ui.dart';
import 'exchange.dart';

/// Asks one question at a time before editing. Every answer changes the edit.
class StyleQuestionCard extends StatelessWidget {
  const StyleQuestionCard({super.key, required this.model});

  final ProjectModel model;

  @override
  Widget build(BuildContext context) {
    final chat = model.chat;
    final brief = chat?['brief'] as Json?;
    final asking = brief?['asking'] as Json?;
    if (asking == null || chat?['can_edit'] != true) return const SizedBox.shrink();
    final done = (brief!['answers'] as List).length;
    final key = asking['key'] as String;
    final suggested = asking['suggested'] as String?;
    void answer(String? value) => model.changeAssistant('answer_style', {'key': key, 'value': value}, 'Saving your answer');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(asking['text'] as String, style: Theme.of(context).textTheme.titleSmall)),
                Text('${done + 1} of ${brief['total']}', style: mono),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final choice in (asking['choices'] as List).cast<Json>())
                  ActionChip(
                    label: Text(choice['value'] == suggested ? '${choice['label']} (matches your reference)' : choice['label'] as String, style: small),
                    onPressed: model.busy ? null : () => answer(choice['value'] as String),
                  ),
                TextButton(onPressed: model.busy ? null : () => answer(null), child: const Text('Skip')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What the AI has been told about how this clip should be edited, and the reference behind it.
class EditBriefPanel extends StatelessWidget {
  const EditBriefPanel({super.key, required this.model});

  final ProjectModel model;

  @override
  Widget build(BuildContext context) {
    final brief = model.chat?['brief'] as Json?;
    final answers = ((brief?['answers'] as List?) ?? const []).cast<Json>();
    final style = model.style;
    final measured = style?['measured'] as Json?;
    final pace = measured?['cuts_per_minute'] as num?;
    return Section(
      'How to edit this',
      children: [
        if (answers.isEmpty && style == null) const Text('Answer the questions, or add a reference, and the AI edits to match.', style: tiny),
        for (final item in answers)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(item['label'] as String, style: small),
          ),
        if (style != null) ...[
          if (answers.isNotEmpty) const SizedBox(height: 4),
          Text('Reference: ${style['reference']}', style: tiny, overflow: TextOverflow.ellipsis),
          if (pace != null) Text('$pace cuts a minute', style: mono),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            ReferenceButtons(model, onAdded: model.loadChat),
            if (model.plan != null && answers.isNotEmpty)
              TextButton(onPressed: model.busy ? null : model.applyBrief, child: Text('Apply to ${(model.planId ?? '').replaceFirst('pln_', '')}')),
            if (answers.isNotEmpty)
              TextButton(onPressed: model.busy ? null : () => model.changeAssistant('reset_brief', {}, 'Clearing your answers'), child: const Text('Start over')),
          ],
        ),
      ],
    );
  }
}
