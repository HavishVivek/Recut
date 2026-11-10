import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../engine.dart';
import '../motion.dart';
import '../project.dart';
import '../theme.dart';
import '../ui.dart';

/// Which form the account dialog shows.
enum AccountMode { signIn, signUp, reset }

/// An optional account: signed in, signed out, or a build with no account service. Only an email, a password and
/// tokens ever leave this Mac, and the app works the same without one.
class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key, required this.model, this.onStartTour});

  final ProjectModel model;
  final VoidCallback? onStartTour;

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  bool _busy = false;
  String? _problem;

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.model.api.account('logout');
      await widget.model.loadSettings();
    } on EngineError catch (error) {
      _problem = error.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await widget.model.api.account('refresh', {'force': true});
      await widget.model.loadSettings();
    } on EngineError catch (error) {
      _problem = error.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.model.settings ?? const {};
    final account = (settings['account'] as Json?) ?? const {'configured': false};
    final user = (settings['user'] as Json?) ?? const {};
    final signedIn = account['signed_in'] == true;
    return Section(
      'Account',
      children: [
        Swap(
          child: account['configured'] != true
              ? const Text('This build isn\'t connected to an account service, so sign in is off. Everything works without it, and a license key '
                  'still unlocks Pro.', key: ValueKey('off'), style: quiet)
              : signedIn
                  ? Row(
                      key: const ValueKey('in'),
                      children: [
                        const DrawnCheck(size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Signed in as ${account['email']}. Plan: ${account['plan'] == 'pro' ? 'Pro' : 'Free'}.', style: small),
                        ),
                        TextButton(onPressed: _busy ? null : _check, child: const Text('Check plan')),
                        TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
                      ],
                    )
                  : Row(
                      key: const ValueKey('out'),
                      children: [
                        const Expanded(child: Text('Sign in to unlock Pro on this Mac. The app works the same without an account.', style: quiet)),
                        TextButton(onPressed: () => showAccountDialog(context, widget.model, AccountMode.signIn), child: const Text('Sign in')),
                        const SizedBox(width: 6),
                        FilledButton(onPressed: () => showAccountDialog(context, widget.model, AccountMode.signUp), child: const Text('Create account')),
                      ],
                    ),
        ),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Alert(_problem!, color: bad)),
        const SizedBox(height: 12),
        if (user.isNotEmpty) ...[
          Fact('Name', user['name'] as String? ?? ''),
          Fact('Mac user', user['user'] as String? ?? '', exact: true),
        ],
        const Fact('Your footage', 'Stays on this Mac. An account only ever sends an email, a password and its sign-in tokens'),
        if (widget.onStartTour != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onStartTour,
              icon: const PhosphorIcon(PhosphorIconsRegular.compass, size: 14),
              label: const Text('Take the tour again'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Sign in, create an account, or send a reset link. Returns true once signed in.
Future<bool> showAccountDialog(BuildContext context, ProjectModel model, AccountMode mode) async {
  final done = await showDialog<bool>(context: context, builder: (context) => AccountDialog(model: model, mode: mode));
  return done == true;
}

class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key, required this.model, required this.mode});

  final ProjectModel model;
  final AccountMode mode;

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  late AccountMode _mode = widget.mode;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _problem;
  String? _said;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _title => switch (_mode) { AccountMode.signIn => 'Sign in', AccountMode.signUp => 'Create your account', AccountMode.reset => 'Reset your password' };
  String get _action => switch (_mode) { AccountMode.signIn => 'Sign in', AccountMode.signUp => 'Create account', AccountMode.reset => 'Send reset link' };

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _problem = null;
      _said = null;
    });
    try {
      final op = switch (_mode) { AccountMode.signIn => 'login', AccountMode.signUp => 'signup', AccountMode.reset => 'reset' };
      final reply = await widget.model.api.account(op, {'email': _email.text.trim(), if (_mode != AccountMode.reset) 'password': _password.text});
      await widget.model.loadSettings();
      if (!mounted) return;
      if (reply['signed_in'] == true) {
        Navigator.of(context).pop(true);
        return;
      }
      _said = reply['said'] as String?;
    } on EngineError catch (error) {
      _problem = error.message;
    } catch (error) {
      _problem = '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _switch(AccountMode mode) => setState(() {
        _mode = mode;
        _problem = null;
        _said = null;
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              onSubmitted: (_) => _mode == AccountMode.reset ? _submit() : null,
            ),
            if (_mode != AccountMode.reset) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: [_mode == AccountMode.signUp ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(labelText: 'Password', helperText: _mode == AccountMode.signUp ? 'At least 8 characters' : null),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_problem != null) Padding(padding: const EdgeInsets.only(top: 10), child: Alert(_problem!, color: bad)),
            if (_said != null) Padding(padding: const EdgeInsets.only(top: 10), child: Alert(_said!, color: good)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              children: [
                if (_mode != AccountMode.signIn) TextButton(onPressed: () => _switch(AccountMode.signIn), child: const Text('I have an account')),
                if (_mode != AccountMode.signUp) TextButton(onPressed: () => _switch(AccountMode.signUp), child: const Text('Create an account')),
                if (_mode == AccountMode.signIn) TextButton(onPressed: () => _switch(AccountMode.reset), child: const Text('Forgot password?')),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Only your email, password and sign-in tokens go to the account service. Your footage and projects never do.', style: tiny),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_action)),
      ],
    );
  }
}

/// The first thing a new Mac sees: what AI Editor is, and an account if they want one. Returns how they chose to go on.
enum WelcomeChoice { tour, skip }

Future<WelcomeChoice> showWelcome(BuildContext context, ProjectModel model) async {
  final choice = await showDialog<WelcomeChoice>(context: context, barrierDismissible: false, builder: (context) => WelcomeDialog(model: model));
  return choice ?? WelcomeChoice.skip;
}

class WelcomeDialog extends StatelessWidget {
  const WelcomeDialog({super.key, required this.model});

  final ProjectModel model;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: model, builder: (context, _) => _dialog(context));

  Widget _dialog(BuildContext context) {
    final account = (model.settings?['account'] as Json?) ?? const {};
    final configured = account['configured'] == true;
    final signedIn = account['signed_in'] == true;
    const points = [
      (PhosphorIconsRegular.filmStrip, 'Footage in, a finished edit out: it listens, cuts, titles and builds it in DaVinci Resolve.'),
      (PhosphorIconsRegular.sparkle, 'Ask in words, or describe a new video and get a draft with a storyboard first.'),
      (PhosphorIconsRegular.lockSimple, 'Everything runs on this Mac. Your footage never leaves it.'),
    ];
    return AlertDialog(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image(image: AssetImage('assets/brand/logo.png'), width: 72, height: 72, semanticLabel: 'AI Editor'),
          SizedBox(height: 10),
          Text('Welcome to AI Editor'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, (icon, text)) in points.indexed)
              Arrive(
                delay: Duration(milliseconds: 60 * index),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PhosphorIcon(icon, size: 18, color: Graphite.mint),
                      const SizedBox(width: 10),
                      Expanded(child: Text(text, style: small)),
                    ],
                  ),
                ),
              ),
            if (configured && signedIn)
              Row(children: [const DrawnCheck(size: 14), const SizedBox(width: 8), Expanded(child: Text('Signed in as ${account['email']}.', style: small))]),
            if (configured && !signedIn) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  OutlinedButton(onPressed: () => showAccountDialog(context, model, AccountMode.signUp), child: const Text('Create account')),
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => showAccountDialog(context, model, AccountMode.signIn), child: const Text('Sign in')),
                ],
              ),
              const SizedBox(height: 4),
              const Text('An account is optional. It unlocks Pro; everything else works without one.', style: tiny),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(WelcomeChoice.skip), child: const Text('Skip')),
        FilledButton(onPressed: () => Navigator.of(context).pop(WelcomeChoice.tour), child: const Text('Take the tour')),
      ],
    );
  }
}
