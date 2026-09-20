class AudioStorageInfo {
  const AudioStorageInfo({
    required this.bytesUsed,
    required this.fileCount,
    this.browserManaged = false,
  });

  final int bytesUsed;
  final int fileCount;
  final bool browserManaged;

  String get formattedSize {
    if (browserManaged) return 'Browser';
    if (bytesUsed < 1024) return '$bytesUsed B';
    if (bytesUsed < 1024 * 1024) {
      return '${(bytesUsed / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytesUsed / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get detailLabel {
    if (browserManaged) {
      return 'L\'audio resta sul server. Il browser non tiene una cache locale.';
    }
    return '$fileCount file audio locali';
  }
}
