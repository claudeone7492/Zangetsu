/// Audio effects applied through mpv's `af` chain.
enum AudioFx { none, night, cinema, vocal }

class AudioFxChain {
  const AudioFxChain._();

  /// The `af` value for [fx], or null for "leave the audio alone".
  static String? filterFor(AudioFx fx) => switch (fx) {
    AudioFx.none => null,
    AudioFx.night =>
      'lavfi=[acompressor=threshold=-18dB:ratio=4:attack=5:release=250]',
    AudioFx.cinema =>
      'lavfi=[aecho=0.8:0.9:40|60:0.4|0.3,equalizer=f=100:t=q:w=1:g=3]',
    AudioFx.vocal =>
      'lavfi=[equalizer=f=2500:t=q:w=1.2:g=4,equalizer=f=200:t=q:w=1:g=-3]',
  };
}
