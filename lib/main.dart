// flame/components.dart : SpriteAnimationGroupComponent, PositionComponent,
//   Vector2, Anchor 등 게임 화면에 등장하는 모든 컴포넌트와 보조 타입.
import 'package:flame/components.dart';

// flame/game.dart : FlameGame, GameWidget, World, CameraComponent 등
//   "게임 본체"를 만드는 데 필요한 핵심 클래스들.
import 'package:flame/game.dart';

// flame/input.dart : KeyboardEvents mixin 등 키보드 입력 처리에 필요한 타입.
//   이 줄이 빠지면 `with KeyboardEvents`에서 컴파일 에러가 납니다.
import 'package:flame/input.dart';

// flutter/material.dart : runApp, Colors 등 Flutter 기본 도구.
//   여기에서는 GameWidget을 Flutter 위젯 트리에 띄우기 위해 필요합니다.
import 'package:flutter/material.dart';

// flutter/services.dart : LogicalKeyboardKey, KeyEvent 등 키보드 입력 타입.
import 'package:flutter/services.dart';

// flutter/gestures.dart : 포인터 입력 타입 모음.
//   - PointerScrollEvent(마우스 휠) / PointerPanZoomUpdateEvent(트랙패드·매직 마우스)
//     → 데스크톱 줌(Listener)에 사용.
//   - ScaleGestureRecognizer
//     → 모바일 터치의 탭 이동 + 핀치 줌(RawGestureDetector)에 사용.
import 'package:flutter/gestures.dart';

/// 플레이어가 가질 수 있는 상태(state)를 표현하는 열거형입니다.
///
/// SpriteAnimationGroupComponent는 "상태별로 다른 애니메이션"을 들고 있다가
/// `current` 값이 바뀌면 자동으로 화면에 표시할 애니메이션을 전환합니다.
/// 이 enum의 값 하나하나가 그 키(key) 역할을 합니다.
///
/// 게임이 커지면 idle/running 외에 attack, hit, die 같은 상태가 추가됩니다.
/// 그때마다 이 enum에 값을 한 줄씩 더하고, animations 맵에 짝이 되는
/// SpriteAnimation을 등록해 주면 됩니다.
enum PlayerState { idle, running }

void main() {
  // 게임 인스턴스를 먼저 만들어, GameWidget과 줌 처리 Listener가 함께 참조합니다.
  final game = MyGame();

  // GameWidget은 Flame 게임을 Flutter 위젯 트리에 올려 주는 위젯입니다.
  // 일반 Flutter 앱에서 MaterialApp을 runApp에 넣는 것처럼,
  // Flame 게임에서는 GameWidget에 게임 객체를 넣어 실행합니다.
  //
  // 입력은 장치·제스처마다 경로가 달라, Listener + RawGestureDetector로 나눠 처리합니다.
  //
  //   [데스크톱 전용]
  //   • 마우스 휠            → Listener.onPointerSignal (PointerScrollEvent) → 줌
  //   • 트랙패드/매직마우스   → Listener.onPointerPanZoomUpdate (PointerPanZoom) → 줌
  //   [터치·마우스 공통]
  //   • 단일 탭             → TapGestureRecognizer        → PC를 그 지점으로 이동
  //   • 롱탭               → LongPressGestureRecognizer  → 줌 1.0 + PC 중앙 복귀
  //   • 1손가락 드래그       → ScaleGestureRecognizer(1)   → 카메라 패닝(맵 둘러보기)
  //   • 2손가락 핀치         → ScaleGestureRecognizer(≥2)  → 줌
  //
  // 왜 Flame 기본 입력(ScrollDetector·TapCallbacks)을 안 쓰나?
  //   - ScrollDetector는 PointerScrollEvent만 받아 트랙패드/매직 마우스를 놓칩니다.
  //   - 터치 핀치(두 손가락)를 TapCallbacks가 각 손가락의 "탭"으로 오인해 캐릭터를
  //     이동시켰습니다. 탭을 TapGestureRecognizer로 분리하면, 탭은 본질적으로
  //     단일 포인터라 두 손가락 핀치에서는 발동조차 하지 않아 충돌이 사라집니다.
  runApp(
    Listener(
      // ① 데스크톱 마우스 휠 — PointerScrollEvent.
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // 휠을 위로 굴리면 dy < 0 → 확대, 아래로 굴리면 dy > 0 → 축소.
          game.zoomBy(event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
        }
      },
      // ② 데스크톱 트랙패드 / 매직 마우스 표면 스와이프 — PointerPanZoom 제스처.
      onPointerPanZoomUpdate: (event) {
        // 작은 변화량이 연속으로 들어오므로 한 번에 조금씩만(1.03배) 줌합니다.
        // 손가락을 위로 밀면 panDelta.dy < 0 → 확대.
        // (방향이 직관과 반대로 느껴지면 아래 부등호를 뒤집으면 됩니다.)
        final dy = event.panDelta.dy;
        if (dy != 0) game.zoomBy(dy < 0 ? 1.03 : 1 / 1.03);
      },
      // 아래 3개 제스처는 터치·마우스 공통입니다. trackpad는 모든 recognizer에서
      // 제외했습니다 — 트랙패드/매직 마우스의 표면 스와이프(PointerPanZoom)는 위
      // Listener가 줌으로 전담하므로, 여기서 또 받으면 "이중 줌"이 됩니다.
      child: RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          // ① 단일 탭 → 그 지점으로 PC 이동.
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            (TapGestureRecognizer instance) {
              // localPosition은 GameWidget(canvas) 좌표 → globalToLocal로 월드 변환.
              instance.onTapUp = (d) {
                game.handleTap(Vector2(d.localPosition.dx, d.localPosition.dy));
              };
            },
          ),
          // ② 롱탭 → 줌 1.0 + PC를 화면 중앙으로(추적 재개).
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            (LongPressGestureRecognizer instance) {
              instance.onLongPress = game.resetView;
            },
          ),
          // ③ 1손가락 드래그 → 카메라 패닝 / 2손가락 핀치 → 줌.
          //   탭이 위 TapGestureRecognizer로 분리됐으므로, 두 손가락 핀치에서는
          //   탭이 발동하지 않습니다(= 핀치 중 PC가 이동하지 않습니다).
          ScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
            () => ScaleGestureRecognizer(
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            (ScaleGestureRecognizer instance) {
              instance
                ..onStart = (d) {
                  game.handleScaleStart(d.pointerCount);
                }
                ..onUpdate = (d) {
                  // focalPointDelta = 직전 프레임 대비 focal 이동량(화면 픽셀).
                  game.handleScaleUpdate(
                    d.pointerCount,
                    d.scale,
                    Vector2(d.focalPointDelta.dx, d.focalPointDelta.dy),
                  );
                };
            },
          ),
        },
        child: GameWidget(game: game),
      ),
    ),
  );
}

/// 이 클래스가 실제 게임의 시작점입니다.
///
/// FlameGame은 Flame에서 제공하는 기본 게임 클래스입니다.
/// 여기에 컴포넌트를 add() 하면 게임 화면 안에 배치되고,
/// Flame의 게임 루프에 따라 로드, 업데이트, 렌더링 대상이 됩니다.
///
/// `with KeyboardEvents`는 키보드 입력 이벤트를 받기 위한 mixin입니다.
/// 이 mixin이 붙은 클래스에서 onKeyEvent()를 오버라이드하면,
/// 매 키 이벤트마다 Flame이 그 메서드를 자동으로 호출해 줍니다.
///
/// 줌(마우스 휠/트랙패드)은 Flame의 ScrollDetector 대신 main()의 Listener에서
/// 받아 zoomBy()를 호출합니다. (이유는 main() 주석 참고 — 매직 마우스/트랙패드는
/// PointerScrollEvent가 아니라 트랙패드 제스처로 들어오기 때문입니다.)
class MyGame extends FlameGame with KeyboardEvents {
  // late는 "지금 바로 값은 없지만, 사용하기 전에는 반드시 넣겠다"는 뜻입니다.
  // player는 onLoad()에서 생성됩니다.
  //
  // 참고: FlameGame은 이미 `world`와 `camera` 필드를 기본으로 가지고 있고
  // 생성 시점에 자동으로 만들어 트리에 추가합니다.
  // 따라서 여기서 같은 이름으로 새로 선언하면 부모의 getter를 가려서
  // LateInitializationError가 발생합니다. 부모의 것을 그대로 사용합니다.
  late final Player player;

  // 현재 눌려 있는 키들을 모아 두는 집합입니다.
  //
  // onKeyEvent()는 "키가 눌리거나 떼어지는 순간"에만 호출되지만,
  // update()는 매 프레임 호출됩니다. 그래서 두 흐름을 연결할 "현재 상태"가
  // 필요합니다. onKeyEvent에서 이 집합을 keysPressed로 덮어 쓰고,
  // update에서는 이 집합을 매 프레임 player에 넘겨 줍니다.
  //
  // 결과적으로 키를 꾹 누르고 있는 동안에는 매 프레임 그 키가 들어 있는
  // 집합이 전달되므로 캐릭터가 계속 이동하게 됩니다.
  final keys = <LogicalKeyboardKey>{};

  @override
  Future<void> onLoad() async {
    // size는 현재 게임 화면의 크기입니다.
    // Flame에서 화면 크기, 위치, 이동 방향처럼 x/y 두 값을 가지는 데이터는
    // 대부분 Vector2로 표현합니다.
    //
    // 예를 들어 화면 크기가 800 x 600이면 size는 대략 Vector2(800, 600)입니다.
    // size / 2는 Vector2(400, 300)이 되므로 화면 중앙 좌표가 됩니다.
    //
    // Dart의 cascade 연산자(..)를 사용하면 Player()를 만든 직후
    // 그 객체의 position 값을 이어서 설정할 수 있습니다.
    player = Player()..position = size / 2;

    // FlameGame이 이미 만들어 둔 world에 player를 추가하고,
    // 기본 camera가 player를 따라가도록 설정합니다.
    //
    // 중요: await 없이 world.add(player)만 호출하면,
    // Player.onLoad()(이미지 로딩 등)가 끝나기 전에 MyGame.onLoad()가 종료되어
    // 게임 루프가 시작됩니다. 그 결과 update() → applyInput() → current = ...
    // 까지 실행되는데, Player의 animations가 아직 null이라
    // "Animations not set" assertion이 발생합니다.
    // await를 붙이면 자식의 onLoad 완료를 기다리므로 안전합니다.
    await world.add(player);

    // ── 게임 맵(world)에 나무 기물 추가 ─────────────────────────────────
    //
    // world가 곧 "게임 맵(게임 세계)"입니다. 여기에 add() 하면 맵 위에
    // 기물이 놓입니다. player를 추가한 것과 완전히 같은 방식입니다.
    //
    // position을 지정하지 않으면 (0,0) = 맵 원점에 놓입니다. 여기서는
    // 플레이어(화면 중앙 = size/2) 기준 오른쪽 위로 조금 떨어뜨려 둡니다.
    await world.add(Tree()..position = size / 2 + Vector2(150, -100));
    await world.add(Fountain()..position = size / 2 + Vector2(-100, 50));
    await world.add(FlowerTree()..position = size / 2 + Vector2(200, -80));

    // camera.follow(player)는 카메라가 player를 따라가도록 설정합니다.
    // player가 움직이면 카메라도 함께 움직여 화면 중앙에 항상 player가
    // 보이게 됩니다. (FollowBehavior가 자동으로 카메라에 부착됩니다.)
    camera.follow(player);
  }

  /// 키보드 이벤트가 발생할 때마다 Flame이 호출해 주는 메서드입니다.
  ///
  /// [event]      — 이번에 발생한 단일 키 이벤트 (예: "W가 막 눌렸다")
  /// [keysPressed] — 현재 시점에 눌려 있는 모든 키들의 집합
  ///
  /// 여기서는 "지금 어떤 키들이 눌려 있는가"만 알면 되므로
  /// keysPressed로 keys 집합을 통째로 덮어씁니다.
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    // ..(cascade)로 keys.clear() → keys.addAll(keysPressed) 를 연달아 호출.
    // 매번 새 Set을 만드는 것보다 기존 Set의 내용을 교체하는 편이 GC 부담이 작습니다.
    keys
      ..clear()
      ..addAll(keysPressed);

    // KeyEventResult.handled는 이 이벤트가 처리되었음을 Flame에 알립니다.
    // 다른 컴포넌트나 시스템이 이 이벤트를 더 이상 처리하지 않도록 합니다.
    return KeyEventResult.handled;
  }

  /// 줌을 절대값 [value]로 설정하고 0.5~3.0 범위로 제한합니다.
  ///
  /// 줌은 카메라의 viewfinder가 담당합니다(치트시트 §5.6 참고).
  ///   1.0 = 원본 배율, 2.0 = 2배 확대, 0.5 = 절반 축소
  /// zoom은 0 이하가 될 수 없고(0 이하면 내부 assert로 크래시), 너무 크거나
  /// 작으면 화면이 깨지므로 범위를 제한합니다. (clamp는 num을 반환하므로
  /// toDouble()로 다시 double에 맞춥니다.)
  void zoomTo(double value) {
    camera.viewfinder.zoom = value.clamp(0.5, 3.0).toDouble();
  }

  /// 현재 줌에 배율 [multiplier]를 곱합니다. (데스크톱 휠/트랙패드용)
  /// 덧셈이 아니라 곱셈을 쓰는 이유: 어느 배율에서든 체감 변화가 비율로
  /// 일정해 줌이 자연스럽게 느껴집니다.
  void zoomBy(double multiplier) => zoomTo(camera.viewfinder.zoom * multiplier);

  // ── 카메라 추적 상태 ─────────────────────────────────────────────────
  //
  // 시작 시 카메라는 player를 따라갑니다(onLoad의 camera.follow). 1손가락
  // 드래그로 맵을 둘러보면 추적을 끄고, 롱탭(resetView)으로 다시 켭니다.
  bool _cameraFollowing = true;

  // 핀치 시작 시점의 줌. 핀치 진행 중 이 값에 누적 배율(scale)을 곱합니다.
  double _gestureBaseZoom = 1.0;

  /// 단일 탭 → 탭한 지점([canvasPoint], 게임 위젯 좌표)으로 PC를 이동시킵니다.
  /// globalToLocal이 현재 카메라(패닝·줌 반영) 기준으로 canvas→월드 변환을 해 줍니다.
  void handleTap(Vector2 canvasPoint) {
    player.setTarget(camera.globalToLocal(canvasPoint));
  }

  /// 드래그/핀치 제스처가 시작될 때 호출. 핀치 줌의 기준 줌을 저장합니다.
  void handleScaleStart(int pointerCount) {
    _gestureBaseZoom = camera.viewfinder.zoom;
  }

  /// 드래그/핀치 진행 중 호출됩니다.
  ///   [pointerCount] >= 2 → 핀치 줌 (시작 줌 × 누적 배율 [scale])
  ///   [pointerCount] == 1 → 카메라 패닝 ([canvasDelta]만큼 맵을 끌어 이동)
  void handleScaleUpdate(int pointerCount, double scale, Vector2 canvasDelta) {
    if (pointerCount >= 2) {
      // 두 손가락 핀치 → 줌만. (패닝·탭 없음)
      zoomTo(_gestureBaseZoom * scale);
      return;
    }

    // 한 손가락 드래그 → 카메라 패닝(맵 둘러보기).
    // 처음 패닝하는 순간 player 추적을 끕니다. 안 끄면 FollowBehavior가 매
    // 프레임 카메라를 player로 되돌려 패닝이 곧바로 취소됩니다.
    if (_cameraFollowing) {
      camera.stop(); // FollowBehavior 제거
      _cameraFollowing = false;
    }

    // 화면 이동량(canvasDelta)을 월드 이동량으로 변환합니다. 줌이 클수록 같은
    // 화면 이동이 더 작은 월드 이동이 되도록 zoom으로 나눕니다. 손가락 방향과
    // 반대로 카메라를 옮겨야 "맵을 손으로 끌어오는" 느낌이 됩니다(그래서 -=).
    // viewfinder.position의 getter는 계산값이라 setFrom이 아닌 -= (재대입)으로 변경합니다.
    camera.viewfinder.position -= canvasDelta / camera.viewfinder.zoom;
  }

  /// 롱탭 → 줌을 1.0으로 되돌리고, PC를 화면 중앙에 둔 뒤 추적을 재개합니다.
  void resetView() {
    zoomTo(1.0);
    camera.stop(); // 패닝 잔여/이펙트 정리(혹시 남아 있을 FollowBehavior 포함)
    camera.viewfinder.position = player.position.clone(); // 즉시 중앙으로 점프
    camera.follow(player); // 이후 다시 따라가기
    _cameraFollowing = true;
  }

  /// 매 프레임 Flame이 호출해 주는 게임 루프 메서드입니다.
  ///
  /// [dt]는 "지난 프레임 이후 흐른 시간(초)"입니다.
  /// 60FPS라면 약 0.0167, 30FPS라면 약 0.0333이 들어옵니다.
  ///
  /// super.update(dt)를 반드시 먼저 호출해야 합니다. 부모(FlameGame)가
  /// 자식 컴포넌트들의 update를 순회 실행하는 작업을 하기 때문입니다.
  /// 이걸 빼먹으면 자식 컴포넌트들이 갱신되지 않습니다.
  @override
  void update(double dt) {
    super.update(dt);
    // 현재 눌린 키 집합과 dt를 player에 전달.
    // player는 이 정보로 자신의 위치를 옮기고 애니메이션 상태를 전환합니다.
    player.applyInput(keys, dt);
  }
}

/// 플레이어를 나타내는 컴포넌트입니다.
///
/// `SpriteAnimationGroupComponent<T>`는 "상태 T를 키로 여러 SpriteAnimation을
/// 들고 있다가, current 값에 따라 자동으로 다른 애니메이션을 재생"해 주는
/// Flame 컴포넌트입니다. 여기서 T는 위에서 정의한 PlayerState 입니다.
/// (제네릭을 명시하지 않으면 dynamic으로 동작하지만, 타입 안전성을 위해
///  명시하는 편이 권장됩니다. 본 예제에서는 제네릭을 생략했지만 어차피
///  animations 맵의 키 타입으로 PlayerState가 결정됩니다.)
///
/// `with HasGameReference<MyGame>` mixin은 컴포넌트 안에서 `game` 프로퍼티로
/// 자기가 속한 게임 인스턴스에 접근할 수 있게 해 줍니다. MyGame 타입으로
/// 지정해 두면 game.someCustomField 같은 접근이 타입 검사를 통과합니다.
/// (Flame 1.33 이전의 HasGameRef는 deprecated. 현재 권장은 HasGameReference.)
class Player extends SpriteAnimationGroupComponent
    with HasGameReference<MyGame> {
  // 마우스 탭으로 지정된 이동 목적지(월드 좌표)입니다.
  // null이면 "탭 이동 중이 아님"을 뜻합니다. 목적지에 도착하거나, 키보드로
  // 직접 이동을 시작하면 다시 null로 비워집니다.
  Vector2? _target;

  /// 탭한 지점을 이동 목적지로 설정합니다. (MyGame.handleTap에서 호출)
  void setTarget(Vector2 target) {
    _target = target;
  }

  @override
  Future<void> onLoad() async {
    // ── 1. idle 애니메이션 로드 ─────────────────────────────────────────
    //
    // game.images.load는 PNG 파일을 디코딩해 dart:ui의 Image 객체를 반환합니다.
    // (Sprite/SpriteAnimation을 만들기 위한 원본 텍스처 역할.)
    final idelImage = await game.images.load('player.png');

    // SpriteAnimation.fromFrameData는 "이미지 한 장(스프라이트 시트)에서
    // 격자로 잘라 여러 프레임으로 만든 애니메이션"을 생성하는 헬퍼입니다.
    //
    // SpriteAnimationData.sequenced의 옵션:
    //   amount      : 시트에 들어 있는 프레임 개수
    //   stepTime    : 프레임 하나를 보여 주는 시간(초). 0.2면 초당 5프레임.
    //   textureSize : 시트의 한 칸(한 프레임) 크기. Vector2(32, 32)면 32×32픽셀.
    //
    // 즉 player.png는 가로 256(=32×8) × 세로 32 픽셀이고, 가로로 8프레임이
    // 나열된 스프라이트 시트라고 Flame에게 알려 주는 셈입니다.
    final idleAnimation = SpriteAnimation.fromFrameData(
      idelImage,
      SpriteAnimationData.sequenced(
        amount: 8,
        stepTime: 0.2,
        textureSize: Vector2(32, 32),
      ),
    );

    // ── 2. walk 애니메이션 로드 ─────────────────────────────────────────
    //
    // 구조는 idle과 동일. stepTime만 0.1로 더 빠르게 두어 "달리는 느낌"을 줍니다.
    final walkImage = await game.images.load('player_walk.png');
    final walkAnimation = SpriteAnimation.fromFrameData(
      walkImage,
      SpriteAnimationData.sequenced(
        amount: 8,
        stepTime: 0.1,
        textureSize: Vector2(32, 32),
      ),
    );

    // ── 3. animations 맵에 상태별 애니메이션을 등록 ─────────────────────
    //
    // animations는 SpriteAnimationGroupComponent의 필드로, "상태 → 애니메이션"
    // 의 짝(맵)을 받습니다. current가 그 키로 바뀌면 해당 애니메이션이
    // 자동으로 재생됩니다. 별도의 if/switch 없이도 상태 전환이 그림 전환으로
    // 이어집니다.
    animations = {
      PlayerState.idle: idleAnimation,
      PlayerState.running: walkAnimation,
    };

    // 초기 상태는 idle. (키를 누르지 않은 상태이므로)
    current = PlayerState.idle;

    // size는 컴포넌트의 화면 표시 크기(픽셀)입니다.
    // 시트 한 프레임이 32×32이지만, 여기서는 64×64로 확대해서 보여 줍니다.
    // Flame이 GPU에서 자동으로 스케일링합니다.
    size = Vector2(64, 64);

    // anchor는 position의 기준점입니다. center로 두면 position이 컴포넌트의
    // 중심을 가리키므로, 회전·확대 시 자연스럽게 중심을 축으로 변형됩니다.
    anchor = Anchor.center;
  }

  /// 매 프레임 MyGame.update에서 호출되어, 현재 눌린 키 집합과 dt를 받아
  /// 1) 이동 방향(velocity)을 계산하고
  /// 2) 상태(idle/running)를 전환하고
  /// 3) 실제 위치를 갱신합니다.
  void applyInput(Set<LogicalKeyboardKey> keys, double dt) {
    // 1초당 이동 픽셀 수. 키보드 이동과 탭 이동이 함께 사용합니다.
    const double speed = 300;

    // 방향 벡터를 매 프레임 0에서 다시 시작합니다.
    // 이전 프레임의 방향이 남아 있으면 키를 떼도 캐릭터가 계속 흘러갑니다.
    final velocity = Vector2.zero();

    // 각 방향 키를 누적해서 더합니다.
    // 위쪽과 아래쪽을 동시에 누르면 -1 + 1 = 0 이 되어 상하 이동이 상쇄됩니다.
    // (== 연산 대신 +=/-=로 누적하는 이유)
    // 방향키(Arrow)와 WASD를 모두 지원합니다. 같은 방향은 OR로 묶어
    // 둘 중 하나만 눌려도 동작하게 합니다. (W/A/S/D는 keyW/keyA/keyS/keyD)
    if (keys.contains(LogicalKeyboardKey.arrowUp) ||
        keys.contains(LogicalKeyboardKey.keyW)) {
      velocity.y -= 1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowDown) ||
        keys.contains(LogicalKeyboardKey.keyS)) {
      velocity.y += 1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowLeft) ||
        keys.contains(LogicalKeyboardKey.keyA)) {
      velocity.x -= 1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowRight) ||
        keys.contains(LogicalKeyboardKey.keyD)) {
      velocity.x += 1;
    }

    // ── 키보드 이동과 탭 이동의 우선순위 ─────────────────────────────────
    //
    // 키보드 입력이 하나라도 있으면(velocity != 0) 키보드를 우선하고
    // 저장돼 있던 탭 목적지는 취소합니다. 키 입력이 전혀 없을 때만
    // 탭으로 지정한 목적지를 향해 스스로 한 걸음씩 다가갑니다.
    if (velocity.length > 0) {
      _target = null;
    } else if (_target != null) {
      final toTarget = _target! - position; // 목적지까지의 방향·거리
      final step = speed * dt; // 이번 프레임에 이동할 수 있는 거리
      if (toTarget.length <= step) {
        // 한 프레임 안에 도착 가능 → 정확히 목적지에 스냅하고 멈춥니다.
        // (방향으로만 계속 밀면 목적지를 살짝 지나쳐 좌우로 떠는데,
        //  이 스냅 처리가 그 떨림을 막습니다.)
        position.setFrom(_target!);
        _target = null;
        current = PlayerState.idle;
        return;
      }
      // 아직 멀면, 목적지 방향을 이번 프레임의 이동 방향으로 삼습니다.
      velocity.setFrom(toTarget);
    }

    // ── 상태 전환의 핵심 ─────────────────────────────────────────────────
    //
    // velocity.length가 0이면 idle, 0보다 크면 running으로 전환합니다.
    // (키보드든 탭이든 결국 velocity가 0인지 아닌지로 판단합니다.)
    // current에 같은 값을 매 프레임 대입해도 안전합니다(값이 바뀔 때만
    // 애니메이션을 리셋함). 그래서 if로 감쌀 필요가 없습니다.
    current = velocity.length > 0 ? PlayerState.running : PlayerState.idle;

    // ── 위치 갱신의 핵심 ─────────────────────────────────────────────────
    //
    // 공식: position += velocity.normalized() * speed * dt
    //   velocity.normalized()  : 방향만 남기고 길이를 1로 (대각선 가속 방지)
    //   speed                  : 1초당 이동 픽셀 수
    //   dt                     : 이번 프레임에 흐른 시간(초)
    //
    // dt를 곱했으므로 FPS가 바뀌어도 실제 이동 속도는 일정합니다.
    position += velocity.normalized() * speed * dt;
  }
}

/// 게임 맵(world)에 고정 배치되는 "나무" 기물입니다.
///
/// SpriteComponent는 "이미지 한 장을 그대로 화면에 그려 주는" 컴포넌트입니다.
/// 나무는 움직이거나 애니메이션할 필요가 없으므로, 플레이어가 쓰는
/// SpriteAnimationGroupComponent보다 단순한 이 컴포넌트가 적합합니다.
class Tree extends SpriteComponent with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    // game.loadSprite()는 PNG를 로드해 곧바로 Sprite 객체를 반환합니다.
    // (game.images.load()는 Image를 반환하므로 Sprite(...)로 감싸야 하지만,
    //  loadSprite는 그 과정까지 대신 해 줍니다.)
    sprite = await game.loadSprite('tree.png');

    // 화면에 표시할 크기(픽셀). 이미지 원본 크기와 무관하게 이 값으로 그려집니다.
    size = Vector2(64, 128);

    // position이 나무의 중심을 가리키도록 합니다.
    anchor = Anchor.center;
  }
}

/// 게임 맵(world)에 고정 배치되는 "꽃 나무" 기물입니다.
///
/// SpriteComponent는 "이미지 한 장을 그대로 화면에 그려 주는" 컴포넌트입니다.
/// 꽃 나무는 움직이거나 애니메이션할 필요가 없으므로, 플레이어가 쓰는
/// SpriteAnimationGroupComponent보다 단순한 이 컴포넌트가 적합합니다.
class FlowerTree extends SpriteComponent with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    // game.loadSprite()는 PNG를 로드해 곧바로 Sprite 객체를 반환합니다.
    // (game.images.load()는 Image를 반환하므로 Sprite(...)로 감싸야 하지만,
    //  loadSprite는 그 과정까지 대신 해 줍니다.)
    sprite = await game.loadSprite('flower_tree.png');

    // 화면에 표시할 크기(픽셀). 이미지 원본 크기와 무관하게 이 값으로 그려집니다.
    size = Vector2(128, 168);

    // position이 나무의 중심을 가리키도록 합니다.
    anchor = Anchor.center;
  }
}

/// 게임 맵(world)에 고정 배치되는 "분수" 기물입니다.
///
/// SpriteComponent는 "이미지 한 장을 그대로 화면에 그려 주는" 컴포넌트입니다.
/// 분수는 움직이거나 애니메이션할 필요가 없으므로, 플레이어가 쓰는
/// SpriteAnimationGroupComponent보다 단순한 이 컴포넌트가 적합합니다.
class Fountain extends SpriteComponent with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    // game.loadSprite()는 PNG를 로드해 곧바로 Sprite 객체를 반환합니다.
    // (game.images.load()는 Image를 반환하므로 Sprite(...)로 감싸야 하지만,
    //  loadSprite는 그 과정까지 대신 해 줍니다.)
    sprite = await game.loadSprite('fountain.png');

    // 화면에 표시할 크기(픽셀). 이미지 원본 크기와 무관하게 이 값으로 그려집니다.
    size = Vector2(256, 256);

    // position이 나무의 중심을 가리키도록 합니다.
    anchor = Anchor.center;
  }
}
