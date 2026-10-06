import 'package:flutter/foundation.dart';

import '../models/audio_note.dart';
import 'app_preferences_service.dart';
import 'audio_binary_store.dart';
import 'audio_storage_service.dart';
import 'cloud_sync_service.dart';
import 'local_database_service.dart';

/// Note pronte o fallite che non risultano sul server di questo account.
/// Quelle in elaborazione restano: possono essere una registrazione ancora
/// aperta su questo telefono.
Set<String> localNotesToForget({
  required Map<String, bool> processingById,
  required Set<String> remoteIds,
}) {
  return {
    for (final entry in processingById.entries)
      if (!entry.value && !remoteIds.contains(entry.key)) entry.key,
  };
}

/// Lo storage del telefono è unico. Senza questo, entrare con un altro
/// account rilegge chiavi e note di chi c'era prima.
class LocalAccountService {
  LocalAccountService._();

  static final LocalAccountService instance = LocalAccountService._();

  Future<void> prepareForUser(String userId) async {
    final current = userId.trim();
    if (current.isEmpty) return;

    final prefs = AppPreferencesService.instance;
    await prefs.init();
    final stored = prefs.boundLocalUserId();
    if (stored == current) return;

    if (stored != null) {
      await _resetLocalAccount();
      await prefs.setBoundLocalUserId(current);
      return;
    }

    final remoteIds = await CloudSyncService.instance.fetchRemoteNoteIds();
    if (remoteIds == null) return;

    final notes = await LocalDatabaseService.instance.getAllNotes();
    final forgetIds = localNotesToForget(
      processingById: {
        for (final note in notes) note.id: note.isProcessing,
      },
      remoteIds: remoteIds,
    );
    if (forgetIds.isEmpty) {
      await prefs.setBoundLocalUserId(current);
      return;
    }

    final readyIds = {
      for (final note in notes)
        if (!note.isProcessing) note.id,
    };
    final cacheBelongsToSomeoneElse =
        readyIds.isNotEmpty && readyIds.intersection(remoteIds).isEmpty;
    await _forgetNotes(
      notes.where((note) => forgetIds.contains(note.id)),
      clearSecrets: cacheBelongsToSomeoneElse,
    );
    await prefs.setBoundLocalUserId(current);
  }

  Future<void> _resetLocalAccount() async {
    final notes = await LocalDatabaseService.instance.getAllNotes();
    await _deleteAudio(notes);
    await AudioStorageService.clearAudioCache();
    await LocalDatabaseService.instance.deleteAllUserData();
    await AppPreferencesService.instance.clearAccountScopedPreferences();
  }

  Future<void> _forgetNotes(
    Iterable<AudioNote> notes, {
    required bool clearSecrets,
  }) async {
    final list = notes.toList();
    await _deleteAudio(list);
    for (final note in list) {
      await LocalDatabaseService.instance.deleteNote(note.id);
    }
    if (!clearSecrets) return;
    await LocalDatabaseService.instance.clearLibraryOrganization();
    await LocalDatabaseService.instance.clearDeletedNotes();
    await AppPreferencesService.instance.clearAccountScopedPreferences();
  }

  Future<void> _deleteAudio(Iterable<AudioNote> notes) async {
    for (final note in notes) {
      if (note.audioPath.isEmpty) continue;
      try {
        await AudioBinaryStore.instance.delete(note.audioPath);
      } catch (error, stack) {
        debugPrint('audio locale non rimosso: $error\n$stack');
      }
    }
  }
}
