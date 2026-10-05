import '../models/audio_note.dart';

String processingNotificationText(NoteAnalysisPhase? phase) {
  return switch (phase) {
    NoteAnalysisPhase.uploading => 'Invio in corso',
    NoteAnalysisPhase.transcribing => 'Trascrizione in corso',
    NoteAnalysisPhase.analyzing => 'Analisi in corso',
    null => 'Elaborazione in corso',
  };
}
