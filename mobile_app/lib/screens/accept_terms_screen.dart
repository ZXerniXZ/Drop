import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/legal_acceptance.dart';
import '../services/supabase_auth_service.dart';
import '../theme/drop_theme.dart';
import '../widgets/drop_logo.dart';
import '../widgets/legal_consent.dart';

class AcceptTermsScreen extends StatefulWidget {
  const AcceptTermsScreen({super.key});

  @override
  State<AcceptTermsScreen> createState() => _AcceptTermsScreenState();
}

class _AcceptTermsScreenState extends State<AcceptTermsScreen> {
  bool _accepted = false;
  bool _isSaving = false;

  Future<void> _submit() async {
    if (!_accepted || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await LegalAcceptance.saveTermsAcceptance();
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: DropColors.recordRed,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accettazione non salvata'),
          backgroundColor: DropColors.recordRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: DropLogo(height: 48)),
                  const SizedBox(height: 24),
                  Text(
                    'Condizioni aggiornate',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Per continuare accetta le condizioni e l’informativa di Drop.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: DropColors.muted(context),
                        ),
                  ),
                  const SizedBox(height: 28),
                  LegalConsent(
                    requireCheckbox: true,
                    accepted: _accepted,
                    onChanged: (value) => setState(() => _accepted = value),
                    leadIn: 'Accetto le ',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: !_accepted || _isSaving ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continua'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => SupabaseAuthService.instance.signOut(),
                    child: const Text('Esci'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
