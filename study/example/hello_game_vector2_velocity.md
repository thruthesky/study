# HelloGame 예제: Vector2와 velocity 이해하기

이 문서는 `Vector2`와 `velocity`라는 개념을 처음 익히기 위한 **기초 버전** 예제를 설명합니다.
특히 `Vector2`가 무엇인지, `velocity`라는 변수 이름이 왜 쓰였는지에 초점을 둡니다.

> 참고: 같은 저장소의 실제 `lib/main.dart`는 이 개념 위에 스프라이트 애니메이션, 카메라 추적,
> `onKeyEvent` 연결까지 얹은 더 발전된 버전입니다(클래스 이름은 `MyGame`). 그 발전된 코드는
> `study/example/hello_game_walking_animation.md`에서 따로 다룹니다. 이 문서는 거기로 가기 전,
> 벡터와 속도의 기초 골격만 떼어 보는 단계입니다.
>
> 버전 기준: 이 예제는 **flame 1.37.0**(2026-04-01 출시)과 그 안에 포함된 **vector_math 2.2.0**
> 기준으로 점검했으며, 아래 코드는 별도 수정 없이 그대로 컴파일·실행됩니다.
> flame 1.37.0은 Dart SDK `>=3.11.0 <4.0.0`, Flutter `>=3.41.0`을 요구합니다.

## import — 어떤 패키지에서 무엇을 가져오는가

게임 코드를 보기 전에, 위 클래스들이 어디서 오는지부터 정리합니다. Flutter 풀스택 경험이 있어도
Flame의 라이브러리 분할은 처음일 수 있어 import 경로를 먼저 명확히 둡니다.

```dart
// Vector2, PositionComponent, Anchor 등 게임 화면 컴포넌트와 보조 타입
import 'package:flame/components.dart';

// FlameGame, GameWidget 등 "게임 본체"를 만드는 핵심 클래스
import 'package:flame/game.dart';

// KeyboardEvents mixin 등 입력 처리 타입 (이 줄이 없으면 `with KeyboardEvents`가 컴파일 에러)
import 'package:flame/input.dart';

// runApp 등 Flutter 기본 도구
import 'package:flutter/material.dart';

// LogicalKeyboardKey, KeyEvent 등 키보드 입력 타입
import 'package:flutter/services.dart';
```

한 가지 헷갈리기 쉬운 점: `Vector2`는 Flame이 직접 정의한 타입이 아니라
**`vector_math` 패키지의 타입을 그대로 다시 내보낸(re-export) 것**입니다.
flame 내부 `src/extensions/vector2.dart`가 `export 'package:vector_math/vector_math.dart'`를 하고,
그 파일을 다시 `package:flame/components.dart`가 내보내므로, 위처럼 `flame/components.dart`만
import해도 `Vector2`를 바로 쓸 수 있습니다. 별도로 `vector_math`를 `pubspec.yaml`에 추가할 필요는 없습니다.

## 전체 구조

현재 코드는 크게 세 부분으로 나뉩니다.

1. `main()`
2. `HelloGame`
3. `Player`

```dart
void main() {
  runApp(GameWidget(game: HelloGame()));
}
```

`main()`은 Flutter 앱의 시작점입니다.

일반 Flutter 앱에서는 보통 `MaterialApp`을 `runApp()`에 넣지만,
Flame 게임에서는 `GameWidget`을 사용합니다.
`GameWidget`은 Flame 게임 객체를 Flutter 화면에 표시해 주는 연결 다리입니다.

```dart
runApp(GameWidget(game: HelloGame()));
```

이 코드는 `HelloGame`이라는 게임을 만들고, 그 게임을 Flutter 앱 화면에 올립니다.

## HelloGame 클래스

```dart
class HelloGame extends FlameGame with KeyboardEvents {
  late Player player;

  @override
  Future<void> onLoad() async {
    player = Player()..position = size / 2;
    add(player);
  }
}
```

`HelloGame`은 실제 게임을 나타내는 클래스입니다.

`FlameGame`은 Flame에서 제공하는 기본 게임 클래스입니다.
이 클래스를 상속하면 게임 화면, 게임 루프, 컴포넌트 관리 같은 기능을 사용할 수 있습니다.

`KeyboardEvents`는 키보드 입력을 받을 수 있게 해 주는 mixin입니다.
다만 현재 코드에는 아직 `onKeyEvent()`가 없기 때문에,
키 입력을 실제로 `Player.input()`에 넘기는 코드는 다음 단계에서 추가해야 합니다.

## onLoad()

```dart
Future<void> onLoad() async {
  player = Player()..position = size / 2;
  add(player);
}
```

`onLoad()`는 게임이 처음 로드될 때 실행됩니다.

```dart
player = Player()..position = size / 2;
```

이 코드는 `Player` 객체를 만든 뒤, 그 위치를 화면 중앙으로 설정합니다.

여기서 `size`는 게임 화면의 크기입니다.
Flame에서 `size`는 `Vector2` 타입입니다.

예를 들어 화면 크기가 800 x 600이라면:

```dart
size == Vector2(800, 600)
```

그러면:

```dart
size / 2 == Vector2(400, 300)
```

즉 `player.position = size / 2`는 플레이어를 화면 중앙에 놓는다는 뜻입니다.

```dart
add(player);
```

`add()`는 플레이어 컴포넌트를 게임에 등록합니다.
등록된 컴포넌트는 Flame이 관리하며, 화면에 그리거나 업데이트할 수 있습니다.

## Vector2란?

`Vector2`는 x와 y, 두 숫자를 담는 2차원 벡터입니다.

```dart
Vector2(10, 20)
```

위 코드는 `x = 10`, `y = 20`인 2차원 값을 뜻합니다.

게임에서는 `Vector2`를 아주 자주 사용합니다.

```dart
position = Vector2(100, 200); // 위치
size = Vector2(40, 40);       // 크기
velocity = Vector2(1, 0);     // 오른쪽 방향
```

Flame에서 `Vector2`는 다음과 같은 값들을 표현할 때 많이 쓰입니다.

- 위치: 화면의 어디에 있는가
- 크기: 가로와 세로가 얼마인가
- 방향: 어느 쪽을 향하는가
- 이동량: x/y 방향으로 얼마나 움직이는가

내부적으로 Flame의 `Vector2`는 `vector_math` 패키지의 64비트(double) 버전입니다. x와 y가 `double`로
저장되므로 정수 좌표뿐 아니라 `123.4`, `-0.5` 같은 소수 좌표도 자연스럽게 다룹니다.
이동량을 매 프레임 `dt`(소수)와 곱해 더하는 게임 루프에서는 이 소수 정밀도가 사실상 필수입니다.

자주 쓰는 생성/연산자도 함께 익혀 두면 좋습니다.

```dart
Vector2(10, 20)        // x=10, y=20
Vector2.zero()         // (0, 0)
Vector2.all(40)        // (40, 40)  — 정사각형 크기 지정 등에 사용
Vector2(800, 600) / 2  // (400, 300) — 스칼라 나눗셈, 새 Vector2 반환
Vector2(1, 0) * 200    // (200, 0)   — 스칼라 곱셈, 새 Vector2 반환
Vector2(1, 0) + Vector2(0, 1) // (1, 1) — 벡터 덧셈
```

여기서 `+`, `-`, `*`(스칼라), `/`(스칼라)는 **새 `Vector2`를 만들어 반환**합니다(원본 불변).
반면 `+=`, `.setValues()`, `.normalize()`처럼 대상 객체 자체를 바꾸는 **제자리(in-place)** 연산도
따로 있습니다. 이 "새 객체 반환 vs 제자리 수정"의 구분은 아래 `normalize()` 설명에서 다시 중요해집니다.

## Player 클래스

```dart
class Player extends PositionComponent {
  static const double speed = 200;
  Vector2 velocity = Vector2.zero();

  Player() : super(size: Vector2.all(40), anchor: Anchor.center);

  void input(Set<LogicalKeyboardKey> keys) {
    velocity = Vector2.zero();

    if (keys.contains(LogicalKeyboardKey.arrowUp)) {
      velocity.y = -1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowDown)) {
      velocity.y = 1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowLeft)) {
      velocity.x = -1;
    }
    if (keys.contains(LogicalKeyboardKey.arrowRight)) {
      velocity.x = 1;
    }

    velocity.normalize();
  }
}
```

`Player`는 플레이어 오브젝트를 나타내는 컴포넌트입니다.

`PositionComponent`는 Flame에서 제공하는 기본 컴포넌트 중 하나입니다.
위치, 크기, 기준점 같은 2D 오브젝트의 기본 속성을 가지고 있습니다.

> flame 1.37.0 동작 점검: 위 `Player`는 그대로 컴파일·실행됩니다. 다만 `PositionComponent`만 상속하고
> `render()`를 따로 정의하지 않았으므로 **화면에는 아무것도 그려지지 않습니다**(위치/크기 정보만 존재).
> 학습 목적상 좌표 계산만 보기 위한 골격이며, 실제로 캐릭터를 보이게 하려면
> `SpriteComponent`/`SpriteAnimationGroupComponent`를 쓰거나 `render(Canvas canvas)`에서 직접 그려야 합니다.
> (발전된 `lib/main.dart`는 `SpriteAnimationGroupComponent`를 사용합니다.)

### `=` 대입 대신 `+=` / `-=` 누적이 더 안전한 이유

위 예제는 키마다 `velocity.y = -1;`처럼 **값을 통째로 대입**합니다. 단순해서 학습용으로는 좋지만,
"위쪽과 아래쪽을 동시에 누른" 경우 마지막 `if`가 이긴 값으로 덮어써져서 의도와 다르게 한쪽으로 움직입니다.

실전에서는 다음처럼 **누적(`-=`/`+=`)** 하는 편이 견고합니다.

```dart
if (keys.contains(LogicalKeyboardKey.arrowUp))    velocity.y -= 1;
if (keys.contains(LogicalKeyboardKey.arrowDown))  velocity.y += 1;
if (keys.contains(LogicalKeyboardKey.arrowLeft))  velocity.x -= 1;
if (keys.contains(LogicalKeyboardKey.arrowRight)) velocity.x += 1;
```

이렇게 하면 위+아래 동시 입력 시 `-1 + 1 = 0`이 되어 상하 이동이 자연스럽게 상쇄됩니다.
이 누적 방식이 실제 `lib/main.dart`가 채택한 방식입니다.

## speed와 velocity의 차이

```dart
static const double speed = 200;
Vector2 velocity = Vector2.zero();
```

`speed`는 "얼마나 빠른가"를 나타냅니다.
보통 게임에서는 초당 픽셀 수처럼 생각할 수 있습니다.

예를 들어 `speed = 200`이면,
나중에 이동 코드를 추가했을 때 1초에 200픽셀 정도 이동한다는 의미로 사용할 수 있습니다.

반면 `velocity`는 "어느 방향으로 얼마나 움직이는가"를 나타냅니다.

영어 단어 `velocity`는 물리에서 "속도"를 뜻합니다.
여기서 중요한 점은 `velocity`가 방향을 포함한다는 것입니다.

간단히 구분하면 다음과 같습니다.

```text
speed    = 빠르기만 나타내는 숫자
velocity = 방향을 포함한 속도
```

예를 들어:

```dart
speed = 200;
velocity = Vector2(1, 0);
```

이 조합은 "오른쪽으로 초당 200픽셀 이동"이라는 의미로 해석할 수 있습니다.

```dart
velocity = Vector2(0, -1);
```

이 값은 "위쪽으로 이동"이라는 뜻입니다.

```dart
velocity = Vector2.zero();
```

이 값은 `Vector2(0, 0)`과 같고, 움직이지 않는 상태입니다.

## 왜 변수 이름을 velocity로 했을까?

게임 개발에서는 위치를 업데이트할 때 보통 다음과 같은 공식을 씁니다.

```dart
position += velocity * speed * dt;
```

각 값의 의미는 다음과 같습니다.

```text
position = 현재 위치
velocity = 이동 방향
speed = 이동 속도
dt = 지난 프레임 이후 흐른 시간
```

즉 전체 의미는 다음과 같습니다.

```text
현재 위치 += 이동 방향 * 이동 속도 * 지난 시간
```

### 왜 `dt`를 곱해야 하는가 — 프레임레이트 독립성

`dt`(delta time)는 "지난 프레임 이후 흐른 시간(초)"입니다. 게임 루프인 `update(double dt)`가 매 프레임
이 값을 넘겨 줍니다. 60FPS면 약 `0.0167`, 30FPS면 약 `0.0333`, 144FPS면 약 `0.0069`가 들어옵니다.

`dt`를 곱하지 않고 `position += velocity * speed;`처럼 쓰면, **프레임이 많이 그려지는 기기일수록
더 빨리 움직입니다.** 144Hz 기기는 60Hz 기기보다 2.4배 빠르게 이동하는 셈이라, 같은 게임이 기기마다
다르게 동작합니다. `* dt`를 곱하면 "1초에 `speed`픽셀"이라는 **실제 시간 기준**으로 환산되므로,
프레임레이트가 달라져도 1초당 이동 거리는 항상 같습니다. 이것을 프레임레이트 독립성(frame-rate
independence)이라고 부르며, 모든 이동/회전/타이머 계산의 기본 원칙입니다.

검산: `speed = 200`, 60FPS면 한 프레임에 `200 * 0.0167 ≈ 3.34`픽셀씩 60번 = 약 200픽셀/초.
144FPS면 `200 * 0.0069 ≈ 1.39`픽셀씩 144번 = 역시 약 200픽셀/초. 결과가 같습니다.

> 주의: `dt`는 항상 일정하지 않습니다. 창 크기 조절·백그라운드 복귀 등으로 한 프레임이 길게 늘어지면
> `dt`가 비정상적으로 커져 캐릭터가 벽을 통과(터널링)할 수 있습니다. 실전에서는 `dt`에 상한을 두거나
> (예: `dt = min(dt, 1/30)`), 물리 단계를 고정 timestep으로 쪼개는 기법을 쓰지만, 이 기초 예제 범위는 넘습니다.

그래서 플레이어의 이동 방향을 담는 변수 이름으로 `velocity`를 자주 사용합니다.

다만 현재 코드의 `velocity`는 실제 픽셀 단위 속도라기보다는
"이동 방향 벡터"에 더 가깝습니다.
따라서 더 엄밀하게 이름을 붙이면 `direction` 또는 `moveDirection`도 가능합니다.

하지만 이후에 `speed`와 곱해서 실제 이동 속도로 사용할 예정이라면,
`velocity`라는 이름도 게임 코드에서 자연스러운 선택입니다.

## 화면 좌표계와 방향 값

```dart
if (keys.contains(LogicalKeyboardKey.arrowUp)) {
  velocity.y = -1;
}
```

Flutter와 Flame의 기본 화면 좌표계에서는 x와 y가 다음처럼 움직입니다.

```text
x가 커지면 오른쪽으로 이동
x가 작아지면 왼쪽으로 이동

y가 커지면 아래쪽으로 이동
y가 작아지면 위쪽으로 이동
```

그래서 방향 값은 다음처럼 설정됩니다.

```dart
velocity.y = -1; // 위
velocity.y = 1;  // 아래
velocity.x = -1; // 왼쪽
velocity.x = 1;  // 오른쪽
```

## normalize()가 필요한 이유

```dart
velocity.normalize();
```

`normalize()`는 벡터의 방향은 유지하면서 길이를 1로 맞춥니다.

예를 들어 오른쪽으로만 이동하면:

```dart
velocity = Vector2(1, 0);
```

이 벡터의 길이는 1입니다.

그런데 오른쪽과 위쪽을 동시에 누르면:

```dart
velocity = Vector2(1, -1);
```

이 벡터의 길이는 약 1.414입니다.
그대로 사용하면 대각선 이동이 상하좌우 이동보다 더 빨라집니다.

`normalize()`를 호출하면 `Vector2(1, -1)`의 방향은 유지하되 길이는 1로 줄어듭니다.
그 결과 상하좌우 이동과 대각선 이동의 속도를 같게 만들 수 있습니다.

### `normalize()`(제자리)와 `normalized()`(복사본)의 결정적 차이

이 부분이 vector_math를 처음 쓰는 사람이 가장 자주 헷갈리는 지점입니다. 두 메서드는 이름은 비슷하지만
동작이 완전히 다릅니다.

```dart
// normalize() : 자기 자신을 그 자리에서 바꾼다(in-place). 반환값은 length(double).
final v = Vector2(3, 4);
final len = v.normalize(); // len == 5.0, 그리고 v 자체가 (0.6, 0.8)로 변함

// normalized() : 자신은 그대로 두고, 정규화된 "새 Vector2"를 돌려준다.
final v2 = Vector2(3, 4);
final unit = v2.normalized(); // unit == (0.6, 0.8), v2는 여전히 (3, 4)
```

vector_math 2.2.0 기준 `normalized()`의 내부 구현은 사실상 `clone()..normalize()`입니다.
즉 복제한 뒤 그 복제본을 제자리 정규화해서 돌려주는 것입니다. 그래서:

- 위 기초 예제처럼 `velocity` 자체를 단위 벡터로 만들어 두고 싶다면 `velocity.normalize();`가 맞습니다.
- "원본 방향은 보존하고, 한 줄에서 바로 속도를 곱하고 싶다"면 `normalized()`가 깔끔합니다.

  ```dart
  position += velocity.normalized() * speed * dt; // velocity 원본은 그대로 유지
  ```

  실제 발전된 `lib/main.dart`가 바로 이 `normalized()` 방식을 씁니다. 매 프레임 `velocity`를 새로
  계산하므로 원본을 보존할 필요는 없지만, "방향 계산"과 "위치 적용"을 한 줄로 분리해 읽기 좋게 만듭니다.

### 0 벡터에 `normalize()`를 호출해도 안전한가?

수학적으로 0 벡터(길이 0)는 방향이 없어서 정규화할 수 없습니다(1을 0으로 나누는 셈).
이 예제는 아무 키도 누르지 않으면 `velocity = Vector2.zero()`인 상태에서 `velocity.normalize()`를
호출하므로 0으로 나누기가 걱정될 수 있습니다.

다행히 vector_math 2.2.0의 `normalize()`는 길이가 `0.0`이면 나눗셈을 하지 않고 그대로 `0.0`을 반환하도록
구현되어 있어 `NaN`이 생기지 않습니다(`velocity`는 `(0, 0)`인 채로 남습니다). 따라서 이 코드는 안전합니다.

다만 이 안전장치는 라이브러리 구현에 기댄 것이므로, 직접 `1 / length`로 정규화를 구현하거나 다른 수학
라이브러리를 쓸 때는 0 벡터를 먼저 걸러 주는 습관이 좋습니다.

```dart
if (!velocity.isZero()) {
  velocity.normalize();
}
```

## 현재 코드에서 아직 빠진 부분

현재 `input()` 함수는 이동 방향을 계산하지만,
그 값을 실제 위치에 적용하는 코드는 아직 없습니다.

보통 다음 단계에서는 `update()`를 추가합니다.

```dart
@override
void update(double dt) {
  super.update(dt);
  position += velocity * speed * dt;
}
```

그리고 `HelloGame`에서 키보드 이벤트를 받아 `player.input(keys)`를 호출하도록 연결합니다.

### 키보드 입력 연결 — flame 1.37.0의 `onKeyEvent` 시그니처

`KeyboardEvents`는 `package:flame/input.dart`가 내보내는, `Game` 위에 적용되는 mixin입니다
(`mixin KeyboardEvents on Game`). 이 mixin을 단 게임에서 `onKeyEvent()`를 오버라이드하면 Flame이
키가 눌리거나 떼어질 때마다 호출해 줍니다. flame 1.37.0 기준 정확한 시그니처는 다음과 같습니다.

```dart
class HelloGame extends FlameGame with KeyboardEvents {
  // ...
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,                    // 이번에 발생한 단일 키 이벤트
    Set<LogicalKeyboardKey> keysPressed, // "지금 눌려 있는" 모든 키의 집합
  ) {
    player.input(keysPressed);         // 현재 눌린 키 집합을 그대로 넘김
    return KeyEventResult.handled;     // 이 이벤트를 처리했음을 Flame에 알림
  }
}
```

두 가지를 짚어 둡니다.

- 첫 인자는 옛 `RawKeyEvent`가 아니라 Flutter의 새 키보드 모델인 `KeyEvent`입니다
  (`package:flutter/services.dart`에서 옴). flame 1.37.0은 이 새 API를 사용합니다.
- `onKeyEvent`는 키 상태가 "바뀌는 순간"에만 호출되지만 `update(dt)`는 매 프레임 호출됩니다.
  그래서 보통 `onKeyEvent`에서 받은 `keysPressed`를 게임의 필드(예: `Set<LogicalKeyboardKey> keys`)에
  저장해 두고, `update`에서 매 프레임 그 필드를 player에 넘겨 "꾹 누르는 동안 계속 이동"을 구현합니다.

> 참고: 키 입력을 게임 본체가 아니라 개별 컴포넌트에서 받고 싶다면, 컴포넌트에는 `KeyboardHandler`
> mixin을, 게임에는 `HasKeyboardHandlerComponents`를 적용합니다. 이때는 게임에 `KeyboardEvents`를
> 함께 달면 안 됩니다(둘 중 하나만 사용). 이 기초 예제는 게임 본체가 직접 받는 단순한 구조입니다.

현재 코드는 `Vector2`, `speed`, `velocity`, `normalize()`를 이해하기 위한
기초 단계의 예제로 볼 수 있습니다.
