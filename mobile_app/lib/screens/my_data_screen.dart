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
import '../theme/drop_motion.dart';
import '../theme/drop_theme.dart';
import 'record_orb_preview_screen.dart';

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
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        children: [
          const _SettingsSectionLabel('Account'),
          const SizedBox(height: 8),
          _SettingsGroup(
            children: [
              _AccountRow(email: SupabaseAuthService.instance.currentUser?.email),
              _GroupDivider(),
              _SettingsActionRow(
                label: 'Esci',
                icon: Icons.logout,
                isDestructive: true,
                onTap: _signOut,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SettingsSectionLabel('Attività'),
          const SizedBox(height: 8),
          _UsageSummary(stats: _usage!),
          const SizedBox(height: 28),
          const _SettingsSectionLabel('Intelligenza artificiale'),
          const SizedBox(height: 8),
          _SettingsGroup(
            children: [
              _AiPreferencesSection(
                prefs: _aiPrefs,
                promptController: _promptController,
                onChanged: _saveAiPreferences,
              ),
              _GroupDivider(),
              _OpenRouterSection(
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
              _GroupDivider(),
              _NoteTagsSection(
                config: _noteTags,
                onChanged: _saveNoteTags,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SettingsSectionLabel('Tasto record'),
          const SizedBox(height: 8),
          _SettingsGroup(
            children: [
              _SettingsActionRow(
                label: 'Scegli animazione',
                icon: Icons.animation_outlined,
                onTap: () async {
                  await Navigator.of(context).push(
                    DropPageRoute<void>(
                      page: const RecordOrbPreviewScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SettingsSectionLabel('Sistema'),
          const SizedBox(height: 8),
          _SettingsGroup(
            children: [
              _StorageSection(
                storage: _storage!,
                isClearing: _isClearing,
                onClearCache: _clearCache,
                onExportBackup: _exportBackup,
              ),
              _GroupDivider(),
              _ServerStatusRow(status: _serverStatus),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: DropColors.muted(context),
          ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DropColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 20,
      endIndent: 20,
      color: DropColors.border(context),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 20, color: DropColors.muted(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email ?? 'Utente connesso',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Account Supabase',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? DropColors.recordRed : null;

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final minutesLabel = stats.minutesThisMonth >= 10
        ? stats.minutesThisMonth.round().toString()
        : stats.minutesThisMonth.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? DropColors.darkSurface : DropColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DropColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Minuti questo mese',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '$minutesLabel / ${stats.monthlyGoalMinutes} min',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${stats.notesThisMonth} note · \$${stats.estimatedApiCostUsd.toStringAsFixed(2)} API stimate',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 52,
            height: 52,
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
    );
  }
}

class _AiPreferencesSection extends StatelessWidget {
  const _AiPreferencesSection({
    required this.prefs,
    required this.promptController,
    required this.onChanged,
  });

  final AiPreferences prefs;
  final TextEditingController promptController;
  final Future<void> Function(AiPreferences) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(label: 'Modello'),
          const SizedBox(height: 8),
          _StyledDropdown<AiModel>(
            value: prefs.model,
            items: AiModel.values,
            labelBuilder: (m) => m.label,
            onChanged: (v) => onChanged(prefs.copyWith(model: v)),
          ),
          const SizedBox(height: 14),
          _FieldLabel(label: 'Lingua trascrizione'),
          const SizedBox(height: 8),
          _StyledDropdown<TranscriptionLanguage>(
            value: prefs.transcriptionLanguage,
            items: TranscriptionLanguage.values,
            labelBuilder: (l) => l.label,
            onChanged: (v) => onChanged(prefs.copyWith(transcriptionLanguage: v)),
          ),
          const SizedBox(height: 14),
          _FieldLabel(label: 'Prompt personalizzato'),
          const SizedBox(height: 8),
          TextField(
            controller: promptController,
            maxLines: 3,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
            decoration: _inputDecoration(
              context,
              hint: 'Es: Traduci sempre in inglese, usa un tono formale...',
            ),
            onChanged: (v) => onChanged(prefs.copyWith(customPrompt: v)),
          ),
        ],
      ),
    );
  }
}

class _OpenRouterSection extends StatelessWidget {
  const _OpenRouterSection({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _FieldLabel(label: 'OpenRouter'),
              ),
              Text(
                hasCustomKey ? 'Chiave personale' : 'Server Drop',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: hasCustomKey ? Colors.blue : Colors.green,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Lascia vuoto per usare il server Drop.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DropColors.muted(context),
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: apiKeyController,
            obscureText: obscureApiKey,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
            decoration: _inputDecoration(context, hint: 'sk-or-...').copyWith(
              isDense: true,
              suffixIcon: IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscureApiKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                      : const Text('Testa'),
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
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClear,
                child: const Text(
                  'Rimuovi chiave',
                  style: TextStyle(color: DropColors.recordRed),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteTagsSection extends StatefulWidget {
  const _NoteTagsSection({
    required this.config,
    required this.onChanged,
  });

  final NoteTagsConfig config;
  final Future<void> Function(NoteTagsConfig) onChanged;

  @override
  State<_NoteTagsSection> createState() => _NoteTagsSectionState();
}

class _NoteTagsSectionState extends State<_NoteTagsSection> {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel(label: 'Tag note'),
          const SizedBox(height: 4),
          Text(
            'L\'AI sceglie un tag da questa lista dopo ogni trascrizione.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DropColors.muted(context),
                  fontSize: 11,
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newTagController,
                  decoration: _inputDecoration(context, hint: 'Nuovo tag...'),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 4),
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

class _StorageSection extends StatelessWidget {
  const _StorageSection({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cache audio',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
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
          const SizedBox(height: 2),
          Text(
            '${storage.fileCount} file .m4a locali',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: isClearing ? null : onClearCache,
            icon: isClearing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, size: 16),
            label: const Text('Svuota cache audio'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DropColors.recordRed,
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(
                color: DropColors.recordRed.withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onExportBackup,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Esporta backup JSON'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: DropColors.border(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerStatusRow extends StatelessWidget {
  const _ServerStatusRow({required this.status});

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          Icon(Icons.cloud_outlined, size: 20, color: DropColors.muted(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server Drop',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  productionApiBaseUrl.replaceFirst('https://', ''),
                  style: Theme.of(context).textTheme.labelSmall,
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

InputDecoration _inputDecoration(BuildContext context, {required String hint}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return InputDecoration(
    hintText: hint,
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
    fillColor: isDark
        ? Colors.white.withValues(alpha: 0.02)
        : Colors.black.withValues(alpha: 0.02),
  );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DropColors.border(context)),
        color: isDark
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
