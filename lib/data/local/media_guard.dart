/// Local persistence intentionally stores structured game data only.
/// Media files and references must stay in the future ephemeral media layer.
void assertNoPersistedMedia(Object? value, {String path = r'$'}) {
  const forbiddenKeys = <String>{
    'photo',
    'photos',
    'photo_url',
    'photo_path',
    'video',
    'videos',
    'video_url',
    'video_path',
    'media',
    'media_url',
    'media_path',
    'thumbnail',
    'binary',
    'bytes',
    'blob',
  };
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (forbiddenKeys.contains(key)) {
        throw ArgumentError(
          'Media field is forbidden in local history: $path.$key',
        );
      }
      assertNoPersistedMedia(entry.value, path: '$path.$key');
    }
  } else if (value is Iterable) {
    var index = 0;
    for (final item in value) {
      assertNoPersistedMedia(item, path: '$path[$index]');
      index++;
    }
  }
}
