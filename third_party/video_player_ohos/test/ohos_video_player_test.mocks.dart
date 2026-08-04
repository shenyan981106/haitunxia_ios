import 'package:mockito/mockito.dart';
import 'package:video_player_ohos/src/messages.g.dart';

class MockOhosVideoPlayerApi extends Mock implements OhosVideoPlayerApi {
  @override
  Future<void> initialize() =>
      super.noSuchMethod(
            Invocation.method(#initialize, <Object?>[]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<TextureMessage> create(CreateMessage msg) =>
      super.noSuchMethod(
            Invocation.method(#create, <Object?>[msg]),
            returnValue: Future<TextureMessage>.value(
              TextureMessage(textureId: 0),
            ),
            returnValueForMissingStub: Future<TextureMessage>.value(
              TextureMessage(textureId: 0),
            ),
          )
          as Future<TextureMessage>;

  @override
  Future<void> dispose(TextureMessage playerId) =>
      super.noSuchMethod(
            Invocation.method(#dispose, <Object?>[playerId]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<void> setLooping(LoopingMessage msg) =>
      super.noSuchMethod(
            Invocation.method(#setLooping, <Object?>[msg]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<void> setVolume(VolumeMessage msg) =>
      super.noSuchMethod(
            Invocation.method(#setVolume, <Object?>[msg]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<void> setPlaybackSpeed(PlaybackSpeedMessage msg) =>
      super.noSuchMethod(
            Invocation.method(#setPlaybackSpeed, <Object?>[msg]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<void> play(TextureMessage playerId) =>
      super.noSuchMethod(
            Invocation.method(#play, <Object?>[playerId]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<PositionMessage> position(TextureMessage playerId) =>
      super.noSuchMethod(
            Invocation.method(#position, <Object?>[playerId]),
            returnValue: Future<PositionMessage>.value(
              PositionMessage(textureId: 0, position: 0),
            ),
            returnValueForMissingStub: Future<PositionMessage>.value(
              PositionMessage(textureId: 0, position: 0),
            ),
          )
          as Future<PositionMessage>;

  @override
  Future<void> seekTo(PositionMessage msg) =>
      super.noSuchMethod(
            Invocation.method(#seekTo, <Object?>[msg]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<void> pause(TextureMessage playerId) =>
      super.noSuchMethod(
            Invocation.method(#pause, <Object?>[playerId]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;

  @override
  Future<void> setMixWithOthers(MixWithOthersMessage mixWithOthers) =>
      super.noSuchMethod(
            Invocation.method(#setMixWithOthers, <Object?>[mixWithOthers]),
            returnValue: Future<void>.value(),
            returnValueForMissingStub: Future<void>.value(),
          )
          as Future<void>;
}
