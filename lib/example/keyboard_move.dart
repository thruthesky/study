import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  // GameWidget은 Flame 게임을 Flutter 위젯 트리에 올려 주는 위젯입니다.
  // 일반 Flutter 앱에서 MaterialApp을 runApp에 넣는 것처럼,
  // Flame 게임에서는 GameWidget에 게임 객체를 넣어 실행합니다.
  runApp(GameWidget(game: HelloGame()));
}

/// 이 클래스가 실제 게임의 시작점입니다.
///
/// FlameGame은 Flame에서 제공하는 기본 게임 클래스입니다.
/// 여기에 컴포넌트를 add() 하면 게임 화면 안에 배치되고,
/// Flame의 게임 루프에 따라 로드, 업데이트, 렌더링 대상이 됩니다.
///
/// KeyboardEvents mixin은 키보드 입력 이벤트를 받을 준비를 해 줍니다.
/// 이 예제 코드에는 아직 onKeyEvent() 구현이 없어서, 실제 입력 전달은
/// 다음 단계에서 추가해야 합니다.
class HelloGame extends FlameGame with KeyboardEvents {
  // late는 "지금 바로 값은 없지만, 사용하기 전에는 반드시 넣겠다"는 뜻입니다.
  // player는 onLoad()에서 생성됩니다.
  late Player player;

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

    // add()는 Player 컴포넌트를 게임에 등록합니다.
    // 등록된 컴포넌트는 Flame이 관리하며, 화면에 그려지고 업데이트됩니다.
    add(player);
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    // 키 이벤트가 발생할 때마다 input() 함수를 호출해서
    // 현재 눌린 키들에 따라 velocity를 업데이트합니다.
    player.input(keysPressed);

    // KeyEventResult.handled는 이 이벤트가 처리되었음을 Flame에 알립니다.
    // 다른 컴포넌트나 시스템이 이 이벤트를 더 이상 처리하지 않도록 합니다.
    return KeyEventResult.handled;
  }
}

/// 플레이어를 나타내는 컴포넌트입니다.
///
/// PositionComponent는 위치(position), 크기(size), 기준점(anchor) 같은
/// 2D 게임 오브젝트의 기본 속성을 제공하는 Flame 컴포넌트입니다.
class Player extends PositionComponent {
  // speed는 "얼마나 빠르게 움직일 것인가"를 나타내는 숫자입니다.
  // 보통 게임에서는 초당 픽셀 수처럼 사용합니다.
  // 예: speed가 200이면 1초에 200픽셀 이동한다는 의미로 쓸 수 있습니다.
  //
  // 현재 코드에는 아직 update()가 없어서 speed가 실제 이동에는 쓰이지 않습니다.
  // 다음 단계에서 보통 position += velocity * speed * dt 형태로 사용합니다.
  static const double speed = 200;

  // Vector2는 x와 y, 두 개의 숫자를 담는 2차원 벡터입니다.
  // 게임에서는 위치, 크기, 방향, 속도 등을 표현할 때 매우 자주 씁니다.
  //
  // velocity는 영어로 "속도"라는 뜻입니다.
  // 물리와 게임 개발에서는 단순한 빠르기(speed)와 구분해서,
  // "방향을 포함한 속도"라는 의미로 velocity라는 단어를 씁니다.
  //
  // 이 코드에서 speed는 이동의 크기이고,
  // velocity는 플레이어가 현재 어느 방향으로 움직이려 하는지를 담습니다.
  //
  // Vector2.zero()는 Vector2(0, 0)과 같습니다.
  // 즉 처음에는 x 방향도, y 방향도 움직이지 않는 상태입니다.
  Vector2 velocity = Vector2.zero();

  // Player() 생성자입니다.
  //
  // size: Vector2.all(40)
  //   x 크기와 y 크기를 모두 40으로 설정합니다.
  //   즉 플레이어의 기본 크기는 40 x 40입니다.
  //
  // anchor: Anchor.center
  //   position 좌표가 컴포넌트의 왼쪽 위가 아니라 중앙을 가리키게 합니다.
  //   그래서 position = size / 2로 놓으면 플레이어의 중심이 화면 중앙에 옵니다.
  Player() : super(size: Vector2.all(40), anchor: Anchor.center);

  // 현재 눌려 있는 키 목록을 받아 플레이어의 이동 방향을 계산합니다.
  //
  // keys는 현재 눌린 키들의 집합입니다.
  // 예를 들어 위쪽 화살표와 오른쪽 화살표를 동시에 누르면
  // keys 안에 arrowUp과 arrowRight가 함께 들어올 수 있습니다.
  void input(Set<LogicalKeyboardKey> keys) {
    // 매번 입력을 다시 계산하기 위해 먼저 velocity를 0으로 초기화합니다.
    // 이 초기화를 하지 않으면 이전 프레임의 방향 값이 남아 있을 수 있습니다.
    velocity = Vector2.zero();

    // 위쪽: 화살표 위(↑) 또는 W
    if (keys.contains(LogicalKeyboardKey.arrowUp) ||
        keys.contains(LogicalKeyboardKey.keyW)) {
      // Flutter/Flame 화면 좌표계에서는 y 값이 아래로 갈수록 커집니다.
      // 그래서 위로 이동하려면 y를 -1로 설정합니다.
      velocity.y = -1;
    }
    // 아래쪽: 화살표 아래(↓) 또는 S
    if (keys.contains(LogicalKeyboardKey.arrowDown) ||
        keys.contains(LogicalKeyboardKey.keyS)) {
      // 아래로 이동하려면 y를 +1로 설정합니다.
      velocity.y = 1;
    }
    // 왼쪽: 화살표 왼쪽(←) 또는 A
    if (keys.contains(LogicalKeyboardKey.arrowLeft) ||
        keys.contains(LogicalKeyboardKey.keyA)) {
      // 왼쪽으로 이동하려면 x를 -1로 설정합니다.
      velocity.x = -1;
    }
    // 오른쪽: 화살표 오른쪽(→) 또는 D
    if (keys.contains(LogicalKeyboardKey.arrowRight) ||
        keys.contains(LogicalKeyboardKey.keyD)) {
      // 오른쪽으로 이동하려면 x를 +1로 설정합니다.
      velocity.x = 1;
    }

    // normalize()는 벡터의 방향은 유지하고 길이를 1로 맞춥니다.
    //
    // 왜 필요할까요?
    // 오른쪽만 누르면 velocity는 Vector2(1, 0)이고 길이는 1입니다.
    // 오른쪽 + 위쪽을 동시에 누르면 Vector2(1, -1)이 되는데,
    // 이 벡터의 길이는 약 1.414라서 대각선 이동이 더 빨라집니다.
    //
    // normalize()를 호출하면 대각선 방향도 길이가 1인 벡터가 되므로,
    // 상하좌우와 대각선 이동 속도를 균일하게 만들 수 있습니다.
    velocity.normalize();
  }

  @override
  void render(Canvas canvas) {
    // render()는 컴포넌트를 화면에 그리는 함수입니다.
    // canvas는 Flutter의 2D 그래픽을 그리는 도구입니다.
    //
    // 이 예제에서는 간단히 플레이어를 파란색 사각형으로 그립니다.
    // Rect.fromLTWH(0, 0, size.x, size.y)는 왼쪽 위가 (0, 0)이고
    // 너비가 size.x, 높이가 size.y인 사각형을 만듭니다.
    // paint는 사각형을 채울 때 사용할 색과 스타일을 정의합니다.
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final paint = Paint()..color = Colors.blue;
    canvas.drawRect(rect, paint);
  }

  @override
  void update(double dt) {
    // update()는 매 프레임마다 게임 로직을 업데이트하는 함수입니다.
    // dt는 "delta time"의 약자로, 마지막 프레임이 끝난 후부터 지금까지
    // 경과한 시간(초 단위)을 나타냅니다.
    //
    // velocity는 방향만 담고 있고 길이가 1이므로,
    // speed를 곱해서 실제 이동 거리를 계산합니다.
    // 그리고 dt를 곱해서 프레임 속도에 관계없이 일정한 이동 속도를 유지합니다.
    position += velocity * speed * dt;
  }
}
