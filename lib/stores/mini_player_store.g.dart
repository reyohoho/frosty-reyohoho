// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mini_player_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$MiniPlayerStore on MiniPlayerStoreBase, Store {
  Computed<bool>? _$hasSessionComputed;

  @override
  bool get hasSession => (_$hasSessionComputed ??= Computed<bool>(
    () => super.hasSession,
    name: 'MiniPlayerStoreBase.hasSession',
  )).value;

  late final _$videoStoreAtom = Atom(
    name: 'MiniPlayerStoreBase.videoStore',
    context: context,
  );

  @override
  VideoStore? get videoStore {
    _$videoStoreAtom.reportRead();
    return super.videoStore;
  }

  @override
  set videoStore(VideoStore? value) {
    _$videoStoreAtom.reportWrite(value, super.videoStore, () {
      super.videoStore = value;
    });
  }

  late final _$chatTabsStoreAtom = Atom(
    name: 'MiniPlayerStoreBase.chatTabsStore',
    context: context,
  );

  @override
  ChatTabsStore? get chatTabsStore {
    _$chatTabsStoreAtom.reportRead();
    return super.chatTabsStore;
  }

  @override
  set chatTabsStore(ChatTabsStore? value) {
    _$chatTabsStoreAtom.reportWrite(value, super.chatTabsStore, () {
      super.chatTabsStore = value;
    });
  }

  late final _$activeUserIdAtom = Atom(
    name: 'MiniPlayerStoreBase.activeUserId',
    context: context,
  );

  @override
  String? get activeUserId {
    _$activeUserIdAtom.reportRead();
    return super.activeUserId;
  }

  @override
  set activeUserId(String? value) {
    _$activeUserIdAtom.reportWrite(value, super.activeUserId, () {
      super.activeUserId = value;
    });
  }

  late final _$activeUserLoginAtom = Atom(
    name: 'MiniPlayerStoreBase.activeUserLogin',
    context: context,
  );

  @override
  String? get activeUserLogin {
    _$activeUserLoginAtom.reportRead();
    return super.activeUserLogin;
  }

  @override
  set activeUserLogin(String? value) {
    _$activeUserLoginAtom.reportWrite(value, super.activeUserLogin, () {
      super.activeUserLogin = value;
    });
  }

  late final _$activeUserNameAtom = Atom(
    name: 'MiniPlayerStoreBase.activeUserName',
    context: context,
  );

  @override
  String? get activeUserName {
    _$activeUserNameAtom.reportRead();
    return super.activeUserName;
  }

  @override
  set activeUserName(String? value) {
    _$activeUserNameAtom.reportWrite(value, super.activeUserName, () {
      super.activeUserName = value;
    });
  }

  late final _$sessionEpochAtom = Atom(
    name: 'MiniPlayerStoreBase.sessionEpoch',
    context: context,
  );

  @override
  int get sessionEpoch {
    _$sessionEpochAtom.reportRead();
    return super.sessionEpoch;
  }

  @override
  set sessionEpoch(int value) {
    _$sessionEpochAtom.reportWrite(value, super.sessionEpoch, () {
      super.sessionEpoch = value;
    });
  }

  late final _$presentationAtom = Atom(
    name: 'MiniPlayerStoreBase.presentation',
    context: context,
  );

  @override
  MiniPlayerPresentation get presentation {
    _$presentationAtom.reportRead();
    return super.presentation;
  }

  @override
  set presentation(MiniPlayerPresentation value) {
    _$presentationAtom.reportWrite(value, super.presentation, () {
      super.presentation = value;
    });
  }

  late final _$slotRectAtom = Atom(
    name: 'MiniPlayerStoreBase.slotRect',
    context: context,
  );

  @override
  Rect? get slotRect {
    _$slotRectAtom.reportRead();
    return super.slotRect;
  }

  @override
  set slotRect(Rect? value) {
    _$slotRectAtom.reportWrite(value, super.slotRect, () {
      super.slotRect = value;
    });
  }

  late final _$dockedSideAtom = Atom(
    name: 'MiniPlayerStoreBase.dockedSide',
    context: context,
  );

  @override
  MiniPlayerDockSide get dockedSide {
    _$dockedSideAtom.reportRead();
    return super.dockedSide;
  }

  @override
  set dockedSide(MiniPlayerDockSide value) {
    _$dockedSideAtom.reportWrite(value, super.dockedSide, () {
      super.dockedSide = value;
    });
  }

  late final _$isDraggingMiniAtom = Atom(
    name: 'MiniPlayerStoreBase.isDraggingMini',
    context: context,
  );

  @override
  bool get isDraggingMini {
    _$isDraggingMiniAtom.reportRead();
    return super.isDraggingMini;
  }

  @override
  set isDraggingMini(bool value) {
    _$isDraggingMiniAtom.reportWrite(value, super.isDraggingMini, () {
      super.isDraggingMini = value;
    });
  }

  late final _$draggingLeftPxAtom = Atom(
    name: 'MiniPlayerStoreBase.draggingLeftPx',
    context: context,
  );

  @override
  double? get draggingLeftPx {
    _$draggingLeftPxAtom.reportRead();
    return super.draggingLeftPx;
  }

  @override
  set draggingLeftPx(double? value) {
    _$draggingLeftPxAtom.reportWrite(value, super.draggingLeftPx, () {
      super.draggingLeftPx = value;
    });
  }

  late final _$MiniPlayerStoreBaseActionController = ActionController(
    name: 'MiniPlayerStoreBase',
    context: context,
  );

  @override
  void closeSession({String reason = 'manual'}) {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.closeSession',
    );
    try {
      return super.closeSession(reason: reason);
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void reportSlotRect(Rect? rect) {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.reportSlotRect',
    );
    try {
      return super.reportSlotRect(rect);
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void enterFull() {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.enterFull',
    );
    try {
      return super.enterFull();
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void minimizeAfterPop() {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.minimizeAfterPop',
    );
    try {
      return super.minimizeAfterPop();
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void requestExpand() {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.requestExpand',
    );
    try {
      return super.requestExpand();
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setDockedSide(MiniPlayerDockSide side) {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.setDockedSide',
    );
    try {
      return super.setDockedSide(side);
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void beginDrag() {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.beginDrag',
    );
    try {
      return super.beginDrag();
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void updateDrag(double leftPx) {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.updateDrag',
    );
    try {
      return super.updateDrag(leftPx);
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void endDrag(MiniPlayerDockSide settledSide) {
    final _$actionInfo = _$MiniPlayerStoreBaseActionController.startAction(
      name: 'MiniPlayerStoreBase.endDrag',
    );
    try {
      return super.endDrag(settledSide);
    } finally {
      _$MiniPlayerStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
videoStore: ${videoStore},
chatTabsStore: ${chatTabsStore},
activeUserId: ${activeUserId},
activeUserLogin: ${activeUserLogin},
activeUserName: ${activeUserName},
sessionEpoch: ${sessionEpoch},
presentation: ${presentation},
slotRect: ${slotRect},
dockedSide: ${dockedSide},
isDraggingMini: ${isDraggingMini},
draggingLeftPx: ${draggingLeftPx},
hasSession: ${hasSession}
    ''';
  }
}
