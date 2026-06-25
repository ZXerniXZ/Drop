import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/ai_preferences.dart';
import '../models/note_tags_config.dart';
import '../services/app_preferences_service.dart';
import '../services/audio_storage_service.dart';
import '../services/local_database_service.dart';
import '../services/openrouter_client.dart';
import '../services/server_health_service.dart';
import '../services/supabase_auth_service.dart';
import '../services/usage_stats_service.dart';
import '../theme/drop_theme.dart';

class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  AiPreferences _aiPrefs = const AiPreferences();
  NoteTagsConfig _noteTags = const NoteTagsConfig();
  UsageStats? _usage;
  AudioStorageInfo? _storage;
  ServerStatus _serverStatus = ServerStatus.checking;
  bool _isLoading = true;
  bool _isClearing = false;
  bool _hasCustomApiKey = false;
  bool _isTestingApiKey = false;
  bool _obscureApiKey = true;
  final _promptController = TextEditingController();
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _serverStatus = ServerStatus.checking;
    });

    final notes = await LocalDatabaseService.instance.getAllNotes();
    final prefs = await AppPreferencesService.instance.loadAiPreferences();
    final tags = await AppPreferencesService.instance.loadNoteTags();
    final apiKey = await AppPreferencesService.instance.loadOpenRouterApiKey();
    final hasCustomKey = await AppPreferencesService.instance.hasCustomOpenRouterKey;
    final storage = await AudioStorageService.getStorageInfo();
    final server = await ServerHealthService.checkHealth();

    if (!mounted) return;
    _promptController.text = prefs.customPrompt;
    _apiKeyController.text = apiKey ?? '';
    setState(() {
      _usage = UsageStatsService.compute(notes);
      _aiPrefs = prefs;
      _noteTags = tags;
      _storage = storage;
      _serverStatus = server;
      _hasCustomApiKey = hasCustomKey;
      _isLoading = false;
    });
  }

  Future<void> _saveNoteTags(NoteTagsConfig config) async {
    await AppPreferencesService.instance.saveNoteTags(config);
    setState(() => _noteTags = config);
  }

  Future<void> _saveAiPreferences(AiPreferences prefs) async {
    await AppPreferencesService.instance.saveAiPreferences(prefs);
    setState(() => _aiPrefs = prefs);
  }

  Future<void> _saveOpenRouterApiKey() async {
    await AppPreferencesService.instance.saveOpenRouterApiKey(
      _apiKeyController.text,
    );
    final hasCustomKey =
        await AppPreferencesService.instance.hasCustomOpenRouterKey;
    if (!mounted) return;
    setState(() => _hasCustomApiKey = hasCustomKey);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasCustomKey
              ? 'Chiave OpenRouter salvata'
              : 'Uso server Drop ripristinato',
        ),
      ),
    );
  }

  Future<void> _clearOpenRouterApiKey() async {
    await AppPreferencesService.instance.clearOpenRouterApiKey();
    _apiKeyController.clear();
    if (!mounted) return;
    setState(() => _hasCustomApiKey = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chiave rimossa — uso server Drop')),
    );
  }

  Future<void> _testOpenRouterApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci una chiave API prima di testare')),
      );
      return;
    }

    setState(() => _isTestingApiKey = true);
    final ok = await OpenRouterClient.instance.testConnection(key);
    if (!mounted) return;
    setState(() => _isTestingApiKey = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Connessione OpenRouter riuscita' : 'Connessione fallita',
        ),
        backgroundColor: ok ? Colors.green : DropColors.recordRed,
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Svuota cache audio'),
        content: const Text(
          'Verranno eliminati tutti i file .m4a locali. '
          'Trascrizioni e riepiloghi nel database restano intatti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Svuota',
              style: TextStyle(color: DropColors.recordRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    final deleted = await AudioStorageService.clearAudioCache();
    final storage = await AudioStorageService.getStorageInfo();
    if (!mounted) return;

    setState(() {
      _storage = storage;
      _isClearing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Eliminati $deleted file audio')),
    );
  }

  void _exportBackup() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Esporta backup JSON — in arrivo')),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esci'),
        content: const Text('Vuoi disconnetterti dal tuo account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await SupabaseAuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        children: [
          _AccountCard(
            email: SupabaseAuthService.instance.currentUser?.email,
            onSignOut: _signOut,
          ),
          const SizedBox(height: 16),
          _UsageCard(stats: _usage!),
          const SizedBox(height: 16),
          _AiSettingsCard(
            prefs: _aiPrefs,
            promptController: _promptController,
            onChanged: _saveAiPreferences,
          ),
          const SizedBox(height: 16),
          _OpenRouterCard(
            apiKeyController: _apiKeyController,
            hasCustomKey: _hasCustomApiKey,
            obscureApiKey: _obscureApiKey,
            isTesting: _isTestingApiKey,
            onToggleObscure: () =>
                setState(() => _obscureApiKey = !_obscureApiKey),
            onSave: _saveOpenRouterApiKey,
            onClear: _clearOpenRouterApiKey,
            onTest: _testOpenRouterApiKey,
          ),
          const SizedBox(height: 16),
          _NoteTagsCard(
            config: _noteTags,
            onChanged: _saveNoteTags,
          ),
          const SizedBox(height: 16),
          _StorageCard(
            storage: _storage!,
            isClearing: _isClearing,
            onClearCache: _clearCache,
            onExportBackup: _exportBackup,
          ),
          const SizedBox(height: 16),
          _ServerStatusCard(status: _serverStatus),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.email,
    required this.onSignOut,
  });

  final String? email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.person_outline,
      title: 'Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            email ?? 'Utente connesso',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _ActionButton(
            label: 'Esci',
            icon: Icons.logout,
            isDestructive: true,
            onTap: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? DropColors.darkSurface
            : DropColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DropColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    final minutesLabel = stats.minutesThisMonth >= 10
        ? stats.minutesThisMonth.round().toString()
        : stats.minutesThisMonth.toStringAsFixed(1);

    return _SectionCard(
      icon: Icons.pie_chart_outline,
      title: 'Attività del mese',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Minuti registrati',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$minutesLabel / ${stats.monthlyGoalMinutes} min',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w300,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stats.notesThisMonth} note questo mese',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: stats.progress.clamp(0.0, 1.0),
                      strokeWidth: 3,
                      backgroundColor: DropColors.border(context),
                    ),
                    Text(
                      '${stats.progressPercent}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Costo API stimato',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${stats.estimatedApiCostUsd.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              Text(
                'Obiettivo personale',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: DropColors.muted(context),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteTagsCard extends StatefulWidget {
  const _NoteTagsCard({
    required this.config,
    required this.onChanged,
  });

  final NoteTagsConfig config;
  final Future<void> Function(NoteTagsConfig) onChanged;

  @override
  State<_NoteTagsCard> createState() => _NoteTagsCardState();
}

class _NoteTagsCardState extends State<_NoteTagsCard> {
  final _newTagController = TextEditingController();

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _addTag() async {
    final value = _newTagController.text.trim();
    if (value.isEmpty) return;
    final updated = [...widget.config.tags];
    if (!updated.any((t) => t.toLowerCase() == value.toLowerCase())) {
      updated.add(value);
    }
    _newTagController.clear();
    await widget.onChanged(NoteTagsConfig(tags: updated));
  }

  Future<void> _removeTag(String tag) async {
    final updated = widget.config.tags.where((t) => t != tag).toList();
    if (updated.isEmpty) return;
    await widget.onChanged(NoteTagsConfig(tags: updated));
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.label_outline,
      title: 'Tag note',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'L\'AI sceglie un tag da questa lista dopo ogni trascrizione.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DropColors.muted(context),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.config.tags.map((tag) {
              return InputChip(
                label: Text(tag),
                onDeleted: widget.config.tags.length > 1
                    ? () => _removeTag(tag)
                    : null,
                deleteIconColor: DropColors.muted(context),
                side: BorderSide(color: DropColors.border(context)),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newTagController,
                  decoration: InputDecoration(
                    hintText: 'Nuovo tag...',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: DropColors.border(context)),
                    ),
                  ),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addTag,
                icon: const Icon(Icons.add, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiSettingsCard extends StatelessWidget {
  const _AiSettingsCard({
    required this.prefs,
    required this.promptController,
    required this.onChanged,
  });

  final AiPreferences prefs;
  final TextEditingController promptController;
  final Future<void> Function(AiPreferences) onChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.memory_outlined,
      title: 'Intelligenza artificiale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(label: 'Modello di elaborazione'),
          const SizedBox(height: 8),
          _StyledDropdown<AiModel>(
            value: prefs.model,
            items: AiModel.values,
            labelBuilder: (m) => m.label,
            onChanged: (v) => onChanged(prefs.copyWith(model: v)),
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: 'Lingua trascrizione'),
          const SizedBox(height: 8),
          _StyledDropdown<TranscriptionLanguage>(
            value: prefs.transcriptionLanguage,
            items: TranscriptionLanguage.values,
            labelBuilder: (l) => l.label,
            onChanged: (v) => onChanged(prefs.copyWith(transcriptionLanguage: v)),
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: 'Prompt personalizzato'),
          const SizedBox(height: 8),
          TextField(
            controller: promptController,
            maxLines: 3,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Es: Traduci sempre in inglese, usa un tono formale...',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: DropColors.muted(context),
                  ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: DropColors.border(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: DropColors.border(context)),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.black.withValues(alpha: 0.02),
            ),
            onChanged: (v) => onChanged(prefs.copyWith(customPrompt: v)),
          ),
        ],
      ),
    );
  }
}

class _OpenRouterCard extends StatelessWidget {
  const _OpenRouterCard({
    required this.apiKeyController,
    required this.hasCustomKey,
    required this.obscureApiKey,
    required this.isTesting,
    required this.onToggleObscure,
    required this.onSave,
    required this.onClear,
    required this.onTest,
  });

  final TextEditingController apiKeyController;
  final bool hasCustomKey;
  final bool obscureApiKey;
  final bool isTesting;
  final VoidCallback onToggleObscure;
  final Future<void> Function() onSave;
  final Future<void> Function() onClear;
  final Future<void> Function() onTest;

  @override
  Widget build(BuildContext context) {
    final modeColor = hasCustomKey ? Colors.blue : Colors.green;
    final modeLabel = hasCustomKey ? 'Chiave personale' : 'Server Drop';

    return _SectionCard(
      icon: Icons.key_outlined,
      title: 'OpenRouter',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Lascia vuoto per usare il server Drop.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DropColors.muted(context),
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  modeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: modeColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: apiKeyController,
            obscureText: obscureApiKey,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
            decoration: InputDecoration(
              hintText: 'sk-or-...',
              isDense: true,
              suffixIcon: IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscureApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: DropColors.border(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: DropColors.border(context)),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.black.withValues(alpha: 0.02),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isTesting ? null : onTest,
                  child: isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Testa connessione'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onSave,
                  child: const Text('Salva'),
                ),
              ),
            ],
          ),
          if (hasCustomKey) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClear,
              child: const Text(
                'Rimuovi chiave',
                style: TextStyle(color: DropColors.recordRed),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.storage,
    required this.isClearing,
    required this.onClearCache,
    required this.onExportBackup,
  });

  final AudioStorageInfo storage;
  final bool isClearing;
  final VoidCallback onClearCache;
  final VoidCallback onExportBackup;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.storage_outlined,
      title: 'Archiviazione',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spazio occupato (audio)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                    ),
              ),
              Text(
                storage.formattedSize,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${storage.fileCount} file .m4a',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 16),
          _ActionButton(
            label: 'Svuota cache audio',
            icon: Icons.delete_outline,
            isDestructive: true,
            isLoading: isClearing,
            onTap: onClearCache,
          ),
          const SizedBox(height: 10),
          _ActionButton(
            label: 'Esporta backup JSON',
            icon: Icons.download_outlined,
            onTap: onExportBackup,
          ),
        ],
      ),
    );
  }
}

class _ServerStatusCard extends StatelessWidget {
  const _ServerStatusCard({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final isOnline = status == ServerStatus.online;
    final isChecking = status == ServerStatus.checking;
    final color = isChecking
        ? Colors.orange
        : isOnline
            ? Colors.green
            : DropColors.recordRed;
    final label = isChecking
        ? 'Verifica...'
        : isOnline
            ? 'Online'
            : 'Offline';

    return _SectionCard(
      icon: Icons.wifi,
      title: 'Stato server',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.02)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DropColors.border(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Endpoint attivo',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    productionApiBaseUrl.replaceFirst('https://', ''),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.3,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DropColors.border(context)),
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(labelBuilder(item)),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? DropColors.recordRed : null;

    return OutlinedButton.icon(
      onPressed: isLoading ? null : onTap,
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(
          color: isDestructive
              ? DropColors.recordRed.withValues(alpha: 0.3)
              : DropColors.border(context),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
