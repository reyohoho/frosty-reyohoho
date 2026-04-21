// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'native_player_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$NativePlayerController on NativePlayerControllerBase, Store {
  late final _$stateAtom = Atom(
    name: 'NativePlayerControllerBase.state',
    context: context,
  );

  @override
  NativePlayerState get state {
    _$stateAtom.reportRead();
    return super.state;
  }

  @override
  set state(NativePlayerState value) {
    _$stateAtom.reportWrite(value, super.state, () {
      super.state = value;
    });
  }

  late final _$isPlayingAtom = Atom(
    name: 'NativePlayerControllerBase.isPlaying',
    context: context,
  );

  @override
  bool get isPlaying {
    _$isPlayingAtom.reportRead();
    return super.isPlaying;
  }

  @override
  set isPlaying(bool value) {
    _$isPlayingAtom.reportWrite(value, super.isPlaying, () {
      super.isPlaying = value;
    });
  }

  late final _$playWhenReadyAtom = Atom(
    name: 'NativePlayerControllerBase.playWhenReady',
    context: context,
  );

  @override
  bool get playWhenReady {
    _$playWhenReadyAtom.reportRead();
    return super.playWhenReady;
  }

  @override
  set playWhenReady(bool value) {
    _$playWhenReadyAtom.reportWrite(value, super.playWhenReady, () {
      super.playWhenReady = value;
    });
  }

  late final _$lastErrorAtom = Atom(
    name: 'NativePlayerControllerBase.lastError',
    context: context,
  );

  @override
  String? get lastError {
    _$lastErrorAtom.reportRead();
    return super.lastError;
  }

  @override
  set lastError(String? value) {
    _$lastErrorAtom.reportWrite(value, super.lastError, () {
      super.lastError = value;
    });
  }

  late final _$videoWidthAtom = Atom(
    name: 'NativePlayerControllerBase.videoWidth',
    context: context,
  );

  @override
  int get videoWidth {
    _$videoWidthAtom.reportRead();
    return super.videoWidth;
  }

  @override
  set videoWidth(int value) {
    _$videoWidthAtom.reportWrite(value, super.videoWidth, () {
      super.videoWidth = value;
    });
  }

  late final _$videoHeightAtom = Atom(
    name: 'NativePlayerControllerBase.videoHeight',
    context: context,
  );

  @override
  int get videoHeight {
    _$videoHeightAtom.reportRead();
    return super.videoHeight;
  }

  @override
  set videoHeight(int value) {
    _$videoHeightAtom.reportWrite(value, super.videoHeight, () {
      super.videoHeight = value;
    });
  }

  late final _$variantsAtom = Atom(
    name: 'NativePlayerControllerBase.variants',
    context: context,
  );

  @override
  ObservableList<NativeVariant> get variants {
    _$variantsAtom.reportRead();
    return super.variants;
  }

  @override
  set variants(ObservableList<NativeVariant> value) {
    _$variantsAtom.reportWrite(value, super.variants, () {
      super.variants = value;
    });
  }

  late final _$masterVariantsAtom = Atom(
    name: 'NativePlayerControllerBase.masterVariants',
    context: context,
  );

  @override
  ObservableList<TwitchHlsVariant> get masterVariants {
    _$masterVariantsAtom.reportRead();
    return super.masterVariants;
  }

  @override
  set masterVariants(ObservableList<TwitchHlsVariant> value) {
    _$masterVariantsAtom.reportWrite(value, super.masterVariants, () {
      super.masterVariants = value;
    });
  }

  late final _$selectedQualityAtom = Atom(
    name: 'NativePlayerControllerBase.selectedQuality',
    context: context,
  );

  @override
  String get selectedQuality {
    _$selectedQualityAtom.reportRead();
    return super.selectedQuality;
  }

  @override
  set selectedQuality(String value) {
    _$selectedQualityAtom.reportWrite(value, super.selectedQuality, () {
      super.selectedQuality = value;
    });
  }

  late final _$latencyMsAtom = Atom(
    name: 'NativePlayerControllerBase.latencyMs',
    context: context,
  );

  @override
  int? get latencyMs {
    _$latencyMsAtom.reportRead();
    return super.latencyMs;
  }

  @override
  set latencyMs(int? value) {
    _$latencyMsAtom.reportWrite(value, super.latencyMs, () {
      super.latencyMs = value;
    });
  }

  late final _$adActiveAtom = Atom(
    name: 'NativePlayerControllerBase.adActive',
    context: context,
  );

  @override
  bool get adActive {
    _$adActiveAtom.reportRead();
    return super.adActive;
  }

  @override
  set adActive(bool value) {
    _$adActiveAtom.reportWrite(value, super.adActive, () {
      super.adActive = value;
    });
  }

  late final _$applyQualityAsyncAction = AsyncAction(
    'NativePlayerControllerBase.applyQuality',
    context: context,
  );

  @override
  Future<void> applyQuality(TwitchHlsVariant? variant) {
    return _$applyQualityAsyncAction.run(() => super.applyQuality(variant));
  }

  late final _$NativePlayerControllerBaseActionController = ActionController(
    name: 'NativePlayerControllerBase',
    context: context,
  );

  @override
  void _applyPlayingEvent(Map<dynamic, dynamic> data) {
    final _$actionInfo = _$NativePlayerControllerBaseActionController
        .startAction(name: 'NativePlayerControllerBase._applyPlayingEvent');
    try {
      return super._applyPlayingEvent(data);
    } finally {
      _$NativePlayerControllerBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
state: ${state},
isPlaying: ${isPlaying},
playWhenReady: ${playWhenReady},
lastError: ${lastError},
videoWidth: ${videoWidth},
videoHeight: ${videoHeight},
variants: ${variants},
masterVariants: ${masterVariants},
selectedQuality: ${selectedQuality},
latencyMs: ${latencyMs},
adActive: ${adActive}
    ''';
  }
}
