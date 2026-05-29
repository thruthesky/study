// flame/components.dart : SpriteAnimationGroupComponent, PositionComponent,
//   Vector2, Anchor 등 게임 화면에 등장하는 모든 컴포넌트와 보조 타입.
import 'package:flame/components.dart';

// flame/game.dart : FlameGame, GameWidget, World, CameraComponent 등
//   "게임 본체"를 만드는 데 필요한 핵심 클래스들.
import 'package:flame/game.dart';

// flame/input.dart : KeyboardEvents mixin 등 입력 처리에 필요한 타입.
//   이 줄이 빠지면 `with KeyboardEvents`에서 컴파일 에러가 납니다.
import 'package:flame/input.dart';

// flutter/material.dart : runApp, Colors 등 Flutter 기본 도구.
//   여기에서는 GameWidget을 Flutter 위젯 트리에 띄우기 위해 필요합니다.
import 'package:flutter/material.dart';

// flutter/services.dart : LogicalKeyboardKey, KeyEvent 등 키보드 입력 타입.
import 'package:flutter/services.dart';

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
  // GameWidget은 Flame 게임을 Flutter 위젯 트리에 올려 주는 위젯입니다.
  // 일반 Flutter 앱에서 MaterialApp을 runApp에 넣는 것처럼,
  // Flame 게임에서는 GameWidget에 게임 객체를 넣어 실행합니다.
  //
  // GameWidget이 매 프레임 Flame의 게임 루프(update → render)를 자동으로
  // 돌려 주므로, 개발자는 setState 같은 호출 없이 좌표만 바꾸면
  // 다음 프레임에 알아서 화면이 갱신됩니다.
  runApp(GameWidget(game: MyGame()));
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
/// (HasGameRef는 Flame 1.28.0부터 deprecated. 현재 권장은 HasGameReference.)
class Player extends SpriteAnimationGroupComponent
    with HasGameReference<MyGame> {
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
    // 방향 벡터를 매 프레임 0에서 다시 시작합니다.
    // 이전 프레임의 방향이 남아 있으면 키를 떼도 캐릭터가 계속 흘러갑니다.
    final velocity = Vector2.zero();

    // 각 방향 키를 누적해서 더합니다.
    // 위쪽과 아래쪽을 동시에 누르면 -1 + 1 = 0 이 되어 상하 이동이 상쇄됩니다.
    // (== 연산 대신 +=/-=로 누적하는 이유)
    if (keys.contains(LogicalKeyboardKey.arrowUp)) {
      velocity.y -= 1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowDown)) {
      velocity.y += 1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowLeft)) {
      velocity.x -= 1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowRight)) {
      velocity.x += 1;
    }

    // ── 상태 전환의 핵심 ─────────────────────────────────────────────────
    //
    // velocity.length는 벡터의 길이(0 이상의 실수)입니다.
    // 0이면 어떤 방향 키도 눌리지 않은 상태이므로 idle,
    // 0보다 크면 이동 중이므로 running 으로 전환합니다.
    //
    // current에 같은 값을 매 프레임 대입해도 안전합니다(내부적으로 값이
    // 바뀔 때만 애니메이션을 리셋함). 그래서 if로 감쌀 필요가 없습니다.
    current = velocity.length > 0 ? PlayerState.running : PlayerState.idle;

    // ── 위치 갱신의 핵심 ─────────────────────────────────────────────────
    //
    // 공식: position += velocity * speed * dt
    //   velocity.normalized()  : 방향만 남기고 길이를 1로 (대각선 가속 방지)
    //   speed                  : 1초당 이동 픽셀 수
    //   dt                     : 이번 프레임에 흐른 시간(초)
    //
    // 결과: "이번 프레임 동안 normalized 방향으로 speed * dt 픽셀 이동".
    // dt를 곱했으므로 FPS가 바뀌어도 실제 이동 속도는 일정합니다.
    const double speed = 300;
    position += velocity.normalized() * speed * dt;
  }
}
