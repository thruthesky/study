# HelloGame 예제: 키보드로 사각형 이동시키기

이 문서는 `lib/main.dart`에 있는 Flame 예제 코드를 설명합니다.
[hello_game_vector2_velocity.md](hello_game_vector2_velocity.md)의 다음 단계로,
실제로 **사각형을 화면에 그리고**, **매 프레임 위치를 갱신**하고,
**키보드 입력(화살표 키 + WASD)을 받아 이동**시키는 부분을 다룹니다.

이전 문서가 `Vector2`와 `velocity`의 *개념*을 설명했다면,
이 문서는 그것들을 *어떻게 화면에서 살아 움직이게 만드는가*를 설명합니다.

## 한 프레임 안에서 일어나는 일

코드를 보기 전에, 게임이 한 프레임 동안 무엇을 하는지 먼저 알면 이해가 쉽습니다.

```text
[키보드 이벤트 발생]
        ↓
HelloGame.onKeyEvent(event, keysPressed)
        ↓
Player.input(keysPressed)   → velocity 갱신 (방향 결정)
        ↓
[다음 프레임]
        ↓
Player.update(dt)            → position += velocity * speed * dt (위치 이동)
        ↓
Player.render(canvas)        → 새 position에 사각형을 다시 그림
        ↓
[화면에 반영]
```

핵심은 세 가지 메서드입니다.

1. `render()` — 사각형을 화면에 그린다
2. `update(dt)` — 매 프레임 위치를 옮긴다
3. `onKeyEvent()` + `input()` — 키 입력을 방향 벡터로 바꾼다

하나씩 살펴보겠습니다.

## 1. render() — 사각형을 화면에 그리기

```dart
@override
void render(Canvas canvas) {
  final rect = Rect.fromLTWH(0, 0, size.x, size.y);
  final paint = Paint()..color = Colors.blue;
  canvas.drawRect(rect, paint);
}
```

`render()`는 컴포넌트를 화면에 그리는 함수입니다.
Flame은 매 프레임마다 모든 컴포넌트의 `render()`를 자동으로 호출해 줍니다.

### canvas란?

`canvas`는 Flutter가 제공하는 **2D 그림판**입니다.
`drawRect`, `drawCircle`, `drawLine` 같은 메서드로 직접 도형을 그릴 수 있습니다.

### Rect.fromLTWH의 의미

```dart
Rect.fromLTWH(0, 0, size.x, size.y)
```

`LTWH`는 **L**eft, **T**op, **W**idth, **H**eight의 약자입니다.
즉 "왼쪽 0, 위쪽 0 위치에서 너비 `size.x`, 높이 `size.y`인 사각형"이라는 뜻입니다.

여기서 한 가지 헷갈리기 쉬운 점이 있습니다.

> `Rect`의 좌표 `(0, 0)`은 **화면의 (0, 0)이 아니라 컴포넌트 자기 자신의 (0, 0)** 입니다.

Flame은 `render()`를 호출하기 전에 캔버스를 컴포넌트의 `position`만큼 이미 이동시켜 놓습니다.
그래서 `render()` 안에서는 항상 "내 컴포넌트 기준 좌표"로 그리면 됩니다.
`position`이 바뀌면 사각형도 자동으로 그 위치로 따라갑니다.

### Paint란?

```dart
final paint = Paint()..color = Colors.blue;
```

`Paint`는 "어떻게 그릴지"를 정의하는 객체입니다.
색깔, 굵기, 채우기/외곽선 여부 등을 지정할 수 있습니다.
여기서는 파란색으로 채워서 그리도록 설정합니다.

`..color = Colors.blue`는 Dart의 **cascade 연산자(`..`)** 입니다.
`Paint()`를 만든 직후 그 객체의 `color` 속성을 이어서 설정한다는 뜻입니다.

## 2. update(dt) — 매 프레임 위치 옮기기

```dart
@override
void update(double dt) {
  position += velocity * speed * dt;
}
```

`update()`는 매 프레임마다 게임 로직을 갱신하는 함수입니다.
Flame은 `render()`처럼 `update()`도 매 프레임 자동으로 호출해 줍니다.

### dt가 뭔가요?

`dt`는 **delta time**의 약자로, "지난 프레임 이후 흘러간 시간(초 단위)"입니다.

예를 들어 60FPS로 실행 중이라면:

```text
dt ≈ 1 / 60 = 0.0167초
```

30FPS로 실행 중이라면:

```text
dt ≈ 1 / 30 = 0.0333초
```

### 왜 dt를 곱해야 할까?

만약 `dt`를 곱하지 않고 `position += velocity * speed`로 쓰면 문제가 생깁니다.

```text
60FPS에서: 1초에 60번 이동 → 60 * speed 픽셀 이동
30FPS에서: 1초에 30번 이동 → 30 * speed 픽셀 이동
```

즉 **컴퓨터 성능에 따라 이동 속도가 달라집니다.**
빠른 컴퓨터에서는 캐릭터가 더 빠르게 움직이고, 느린 컴퓨터에서는 느리게 움직이게 됩니다.

`dt`를 곱하면 어떻게 될까요?

```text
60FPS에서: 60 * (speed * 1/60) = speed 픽셀/초
30FPS에서: 30 * (speed * 1/30) = speed 픽셀/초
```

**프레임 속도와 관계없이 1초에 `speed`픽셀씩 이동하게 됩니다.**
이것이 게임 개발의 기본 규칙입니다.

### 공식 다시 보기

```dart
position += velocity * speed * dt;
```

```text
position = 현재 위치 (Vector2)
velocity = 이동 방향 (Vector2, 길이 1)
speed    = 초당 이동 픽셀 수 (double)
dt       = 이번 프레임에 흐른 시간(초)
```

즉 "이번 프레임 동안 `velocity` 방향으로 `speed * dt` 픽셀만큼 이동"이라는 뜻입니다.

키를 누르지 않으면 `velocity`가 `Vector2.zero()`이므로 곱셈 결과도 0이 되어 움직이지 않습니다.

## 3. onKeyEvent() — 키보드 입력 받기

```dart
@override
KeyEventResult onKeyEvent(
  KeyEvent event,
  Set<LogicalKeyboardKey> keysPressed,
) {
  player.input(keysPressed);
  return KeyEventResult.handled;
}
```

`HelloGame`은 `KeyboardEvents` mixin을 사용하고 있어서 키 이벤트를 받을 수 있습니다.
키가 눌리거나 떼어질 때마다 Flame이 `onKeyEvent()`를 호출해 줍니다.

### 두 인자의 차이

- `event` — **이번에 발생한** 단 하나의 키 이벤트 (예: "W가 막 눌렸다")
- `keysPressed` — **현재 눌려 있는 모든 키들의 집합** (예: `{W, ArrowRight}`)

이 코드에서는 "지금 어떤 키들이 눌려 있는가"만 알면 되므로 `keysPressed`만 사용합니다.

### event의 세 가지 종류 (KeyEvent)

`event`의 타입인 `KeyEvent`는 Flutter의 `HardwareKeyboard` 기반 최신 키보드 API입니다.
예전 Flame/Flutter에서 쓰던 `RawKeyEvent`(그리고 `RawKeyboardListener`)는 deprecated되었고,
현재(Flame 1.37.0 기준)는 `KeyEvent` 계열을 사용합니다. 이 예제 코드는 이미 최신 API를 따르고 있습니다.

`KeyEvent`는 실제로는 세 종류 중 하나로 들어옵니다.

- `KeyDownEvent` — 키가 **막 눌린** 순간 한 번
- `KeyUpEvent` — 키가 **막 떼어진** 순간 한 번
- `KeyRepeatEvent` — 키를 **누르고 있는 동안** OS가 일정 간격으로 반복 발생시키는 이벤트

이 구분이 중요한 이유가 있습니다. 만약 `keysPressed` 대신 `event`를 직접 보고
"키를 한 번 누를 때마다 점프" 같은 **단발성 동작**을 구현한다면,
`KeyRepeatEvent`까지 잡으면 키를 길게 누르고 있을 때 점프가 연속으로 발생합니다.
그래서 단발 동작에서는 다음처럼 `KeyDownEvent`만 골라야 합니다.

```dart
if (event is KeyDownEvent &&
    event.logicalKey == LogicalKeyboardKey.space) {
  player.jump(); // 길게 눌러도 한 번만 실행
}
```

반대로 이 예제처럼 **이동(연속 동작)** 은 "지금 눌려 있는 키 집합"만 알면 충분하므로
`event`의 종류를 신경 쓸 필요 없이 `keysPressed`만 그대로 사용합니다.
`keysPressed`는 Flame이 `HardwareKeyboard`의 현재 상태로 항상 최신화해서 넘겨주는 집합이라,
어떤 종류의 이벤트가 들어오든 그 시점에 눌려 있는 키 전체를 정확히 담고 있습니다.

### 왜 keysPressed를 그대로 넘기나?

`keysPressed`는 `Set<LogicalKeyboardKey>` 타입입니다.
즉 W, A, S, D, 화살표 등 여러 키가 동시에 들어 있을 수 있습니다.

이것을 `player.input(keysPressed)`로 그대로 넘기면,
`Player.input()` 내부에서 어떤 키가 눌려 있는지 하나씩 확인하면서 방향을 계산할 수 있습니다.

여러 키 동시 입력(예: 오른쪽 + 위쪽 → 대각선 이동)을 지원하기 위해
**하나의 키가 아니라 키들의 집합**을 넘기는 것입니다.

### KeyEventResult.handled가 뭔가요?

```dart
return KeyEventResult.handled;
```

`KeyEventResult`는 "이 키 이벤트를 처리했는지" Flame에게 알려 주는 값입니다.

- `KeyEventResult.handled` — 처리했음. 다른 위젯에게 전달하지 않음.
- `KeyEventResult.ignored` — 처리하지 않았음. 다른 위젯이 처리할 수 있게 둠.

게임에서 사용한 키 입력은 보통 다른 곳에 전달할 필요가 없으므로 `handled`를 반환합니다.

다만 게임 위에 Flutter 버튼이나 텍스트 입력 오버레이를 얹는 경우라면,
게임이 처리하지 않은 키는 `KeyEventResult.ignored`를 반환해서
Flutter 위젯이 그 키를 처리할 수 있도록 길을 열어 줘야 할 때도 있습니다.

### 이벤트 기반 입력 vs 폴링 입력

`onKeyEvent`는 **이벤트 기반**입니다. 즉 키가 눌리거나 떼어지거나 반복될 때만 호출되고,
아무 변화가 없는 프레임에서는 호출되지 않습니다. 그래서 이 예제는
"키 상태가 바뀔 때만 `velocity`를 다시 계산"하는 구조입니다.

게임 개발에는 이와 대비되는 **폴링(polling) 방식** 도 있습니다.
이벤트를 기다리지 않고, 매 프레임 `update()` 안에서 "지금 이 키가 눌려 있나?"를 직접 물어보는 방식입니다.
Flutter는 전역 키보드 상태를 `HardwareKeyboard.instance`로 노출하므로 다음처럼 폴링할 수 있습니다.

```dart
@override
void update(double dt) {
  final keys = HardwareKeyboard.instance.logicalKeysPressed; // 현재 눌린 키 집합
  velocity = Vector2.zero();
  if (keys.contains(LogicalKeyboardKey.arrowRight)) velocity.x = 1;
  // ... 나머지 방향도 동일
  velocity.normalize();
  position += velocity * speed * dt;
}
```

두 방식의 트레이드오프는 다음과 같습니다.

- **이벤트 기반(이 예제)** — 입력이 바뀔 때만 계산하므로 효율적이고, "키 down/up 순간"을 정확히 잡기 좋습니다.
  대신 뒤에서 설명하는 *stuck key*(포커스 상실 시 키가 눌린 채 멈춤) 같은 상태 관리 함정이 있습니다.
- **폴링 기반** — `update()`에서 매 프레임 현재 상태를 새로 읽으므로 상태가 꼬일 일이 적고 로직이 단순합니다.
  대신 키가 안 바뀌어도 매 프레임 검사하며, "막 눌린 그 한 순간"을 구분하기는 더 번거롭습니다.

실무에서는 **연속 이동은 폴링(또는 이벤트로 받은 키 집합을 필드에 저장해 두고 `update()`에서 읽기)**,
**점프·발사 같은 단발 동작은 이벤트(`KeyDownEvent`)** 로 처리하는 혼합 방식이 흔합니다.

### 입력을 받자마자 위치를 바꾸지 않는 이유 (render/update 분리)

이 예제에서 가장 눈여겨볼 설계는, `onKeyEvent`가 **`position`을 직접 바꾸지 않는다**는 점입니다.
`onKeyEvent` → `input()`은 오직 **방향(`velocity`)만 결정**하고,
실제 좌표 이동(`position += ...`)은 `update(dt)`가, 그리기는 `render(canvas)`가 맡습니다.

| 메서드 | 호출 시점 | 책임 |
| --- | --- | --- |
| `onKeyEvent` / `input` | 키 상태가 바뀔 때 | "어느 방향으로?" — `velocity`만 갱신 |
| `update(dt)` | 매 프레임 | "그 방향으로 얼마나?" — `dt` 기반 `position` 이동 |
| `render(canvas)` | 매 프레임 | "지금 상태를 어떻게 그릴까?" — 좌표 변경 없이 그리기만 |

만약 `onKeyEvent`에서 곧바로 `position`을 옮기면, 이동량이 **키 이벤트가 들어오는 빈도**에 묶여 버립니다.
키 이벤트 발생 빈도는 OS의 키 반복 속도에 따라 들쭉날쭉하므로 이동이 불규칙해지고,
앞에서 본 *프레임 독립적 이동(dt 곱하기)* 의 이점도 잃게 됩니다.
입력은 "의도(방향)"만 기록하고, 시간에 비례한 실제 이동은 `update(dt)`에 맡기는 것이 핵심 원칙입니다.

### 게임 레벨 입력 vs 컴포넌트 레벨 입력 (KeyboardHandler)

이 예제는 **게임(`HelloGame`) 레벨**에서 키를 받아 `player.input()`을 대신 호출해 주는 구조입니다.
컴포넌트가 하나뿐일 때는 가장 간단합니다.

게임이 커져 입력을 받는 컴포넌트가 여러 개가 되면, 게임이 일일이 호출을 중계하는 대신
**각 컴포넌트가 직접 키를 받도록** 하는 편이 깔끔합니다. 그때는 다음 두 가지를 씁니다.

- 게임(`FlameGame`)에 `HasKeyboardHandlerComponents` mixin을 부여 (이때는 `KeyboardEvents`를 **함께 쓰지 않습니다** — 둘을 동시에 mixin하면 Flame이 assertion으로 막습니다)
- 키를 받을 컴포넌트에 `KeyboardHandler` mixin을 부여하고 `bool onKeyEvent(...)`를 오버라이드

```dart
class HelloGame extends FlameGame with HasKeyboardHandlerComponents { /* ... */ }

class Player extends PositionComponent with KeyboardHandler {
  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    input(keysPressed);
    return true; // true = 이 컴포넌트가 처리함(KeyEventResult.handled와 같은 의미)
  }
}
```

게임 레벨 `KeyboardEvents`의 `onKeyEvent`는 `KeyEventResult`를 반환하지만,
컴포넌트 레벨 `KeyboardHandler`의 `onKeyEvent`는 `bool`을 반환한다는 차이에 주의하세요
(`true` = 처리함, `false` = 다른 컴포넌트로 전파). 이 예제는 단일 컴포넌트라 더 단순한
게임 레벨 방식을 택했을 뿐, 둘 다 Flame 1.37.0에서 유효한 정식 패턴입니다.

## 4. input() — 키 집합을 방향 벡터로 변환

```dart
void input(Set<LogicalKeyboardKey> keys) {
  velocity = Vector2.zero();

  // 위쪽: 화살표 위(↑) 또는 W
  if (keys.contains(LogicalKeyboardKey.arrowUp) ||
      keys.contains(LogicalKeyboardKey.keyW)) {
    velocity.y = -1;
  }
  // 아래쪽: 화살표 아래(↓) 또는 S
  if (keys.contains(LogicalKeyboardKey.arrowDown) ||
      keys.contains(LogicalKeyboardKey.keyS)) {
    velocity.y = 1;
  }
  // 왼쪽: 화살표 왼쪽(←) 또는 A
  if (keys.contains(LogicalKeyboardKey.arrowLeft) ||
      keys.contains(LogicalKeyboardKey.keyA)) {
    velocity.x = -1;
  }
  // 오른쪽: 화살표 오른쪽(→) 또는 D
  if (keys.contains(LogicalKeyboardKey.arrowRight) ||
      keys.contains(LogicalKeyboardKey.keyD)) {
    velocity.x = 1;
  }

  velocity.normalize();
}
```

이 함수는 **현재 눌린 키 집합을 보고 이동 방향을 결정**합니다.

### 왜 처음에 velocity를 0으로 초기화하나?

```dart
velocity = Vector2.zero();
```

이 초기화를 하지 않으면, **이전 프레임에 눌렀던 키의 방향이 그대로 남아 있게 됩니다.**

예를 들어 오른쪽 화살표를 눌렀다가 떼면, 키를 떼는 순간 `input()`이 다시 호출됩니다.
이때 `velocity = Vector2.zero()`로 초기화한 뒤 if문을 검사하면,
아무 키도 눌려 있지 않으므로 velocity는 0인 상태로 유지되어 멈추게 됩니다.

만약 이 초기화가 없다면 velocity가 계속 `(1, 0)`인 채로 남아서,
키를 떼도 사각형이 계속 오른쪽으로 흘러가게 됩니다.

### LogicalKeyboardKey 명명 규칙

알파벳 키를 Flutter에서 표현할 때는 **`key` + 대문자 알파벳** 형식을 사용합니다.

```dart
LogicalKeyboardKey.keyW  // ✅ 올바름
LogicalKeyboardKey.keyA
LogicalKeyboardKey.keyS
LogicalKeyboardKey.keyD

LogicalKeyboardKey.W     // ❌ 컴파일 에러
LogicalKeyboardKey.KeyW  // ❌ 컴파일 에러
```

화살표 키는 다음과 같습니다.

```dart
LogicalKeyboardKey.arrowUp
LogicalKeyboardKey.arrowDown
LogicalKeyboardKey.arrowLeft
LogicalKeyboardKey.arrowRight
```

### `||`로 두 키를 묶는 이유

```dart
if (keys.contains(LogicalKeyboardKey.arrowUp) ||
    keys.contains(LogicalKeyboardKey.keyW)) {
  velocity.y = -1;
}
```

`||`(또는)로 묶으면 **두 키 중 어느 하나만 눌려 있어도** 같은 동작을 하게 됩니다.
즉 사용자가 화살표 키를 좋아하든 WASD를 좋아하든 둘 다 지원할 수 있습니다.

대부분의 PC 게임이 이렇게 두 입력 방식을 모두 지원합니다.

### 마지막 normalize()

```dart
velocity.normalize();
```

`normalize()`는 벡터의 **방향은 유지하면서 길이를 1로 맞춥니다.**

오른쪽만 누르면 `velocity = Vector2(1, 0)` — 길이 1.
오른쪽 + 위쪽을 동시에 누르면 `velocity = Vector2(1, -1)` — 길이 약 1.414.

그대로 두면 대각선 이동이 약 41% 더 빨라집니다.
`normalize()`를 호출하면 대각선 방향도 길이가 1이 되므로,
상하좌우 이동과 대각선 이동의 속도가 같아집니다.

자세한 이유는 [hello_game_vector2_velocity.md](hello_game_vector2_velocity.md)의
"normalize()가 필요한 이유" 절을 참고하세요.

> **아무 키도 안 눌렸을 때 `(0, 0)`을 `normalize()`하면 0으로 나누기가 되지 않나요?**
>
> 직관적으로는 "길이 0인 벡터를 길이 1로 맞추라"는 0으로 나누기처럼 보여서 `NaN`이 걱정됩니다.
> 하지만 Flame이 쓰는 `vector_math` 패키지의 `Vector2.normalize()`는 길이가 정확히 `0.0`이면
> **아무 일도 하지 않고 그대로 둡니다**(내부에서 `if (l == 0.0) return 0.0;`으로 빠져나감).
> 그래서 `velocity`는 `(0, 0)`으로 안전하게 유지되고, 플레이어는 멈춥니다.
> 즉 이 예제 코드는 키를 하나도 안 눌러도 `NaN`이나 폭주 없이 정상 동작합니다.

`velocity`를 in-place로 바꾸는 `normalize()` 대신,
원본은 두고 정규화된 새 벡터가 필요할 때는 `velocity.normalized()`(과거형, 새 `Vector2` 반환)를 씁니다.
이 두 메서드를 헷갈리면 "분명 정규화했는데 값이 안 변한다(반환값을 안 받음)"는 흔한 실수로 이어집니다.

## 전체 흐름을 다시 따라가기

이제 모든 조각을 모아서 한 사이클을 따라가 봅시다.

**상황:** 사용자가 D 키와 W 키를 동시에 누르고 있다.

1. **이벤트 발생** — Flutter가 키 이벤트를 잡아 Flame에 전달.
2. **`HelloGame.onKeyEvent` 호출** — `keysPressed = {keyD, keyW}`.
3. **`player.input({keyD, keyW})` 호출**
   - `velocity = Vector2.zero()` → `(0, 0)`
   - `keyW` 매칭 → `velocity.y = -1` → `(0, -1)`
   - `keyD` 매칭 → `velocity.x = 1` → `(1, -1)`
   - `normalize()` → 약 `(0.707, -0.707)` (오른쪽-위 대각선, 길이 1)
4. **다음 프레임에 `Player.update(dt)` 호출**
   - `position += (0.707, -0.707) * 200 * 0.0167` ≈ `(2.36, -2.36)`
   - 사각형이 오른쪽-위로 약 2.36픽셀 이동.
5. **`Player.render(canvas)` 호출** — 새 `position` 위치에 파란 사각형을 다시 그린다.
6. **다음 프레임에 다시 4번부터 반복** — 키가 계속 눌려 있는 한 사각형이 같은 방향으로 계속 이동.

키를 떼면 다음 `input()` 호출에서 `velocity`가 0이 되어 사각형이 멈춥니다.

## 자주 만나는 문제

### 1. 키를 눌러도 사각형이 움직이지 않는다

가장 흔한 원인 세 가지입니다.

- **`onKeyEvent()`가 빠져 있다.** `KeyboardEvents` mixin만 적어 두고 `onKeyEvent()`를 오버라이드하지 않으면 키 입력이 `Player.input()`에 전달되지 않습니다.
- **`update()`가 빠져 있다.** `velocity`가 계산되어도 `position`에 더해 주는 코드가 없으면 움직이지 않습니다.
- **게임 화면에 키보드 포커스가 없다.** 데스크톱이나 웹에서 실행할 때 게임 영역을 한 번 클릭해 줘야 키 이벤트가 들어오는 경우가 많습니다. `GameWidget(game: ..., autofocus: true)`로 시작 시 자동 포커스를 주면 클릭 없이도 키가 들어오게 만들 수 있습니다(여러 포커스 가능 위젯이 한 화면에 있을 때는 의도대로 동작하지 않을 수 있으니 직접 `FocusNode`를 관리하기도 합니다).

### 2. WASD를 눌러도 안 되는데 화살표는 된다

`LogicalKeyboardKey.keyW`가 아니라 `LogicalKeyboardKey.W`처럼 잘못 입력했을 가능성이 높습니다.
알파벳 키는 반드시 `key` + 대문자 형식을 사용해야 합니다.

### 3. 키를 떼도 사각형이 계속 움직인다

`input()` 안에서 `velocity = Vector2.zero()`로 초기화하는 줄이 빠졌을 가능성이 높습니다.
이 초기화가 없으면 이전 프레임의 방향 값이 그대로 남아 사각형이 계속 흘러갑니다.

### 4. 대각선 이동이 더 빠르다

`velocity.normalize()` 호출이 빠져 있습니다.
또는 모든 if문이 끝나기 전에 `normalize()`를 호출하면 안 됩니다 — 모든 키 검사가 끝난 *뒤*에 호출해야 합니다.

### 5. 키를 누른 채로 창을 벗어났다 돌아오면 계속 움직인다 (stuck key)

이벤트 기반 입력의 가장 악명 높은 함정입니다.
키를 누른 상태에서 게임 창이 포커스를 잃으면(다른 창 클릭, `Alt`+`Tab`, 브라우저 탭 전환 등),
**`KeyUpEvent`가 게임에 도착하지 않습니다.** 그러면 게임 입장에서는 그 키가 아직 눌려 있는 줄 알고
`velocity`가 0으로 돌아가지 않아, 플레이어가 한 방향으로 계속 흘러갑니다.

대응책은 두 가지입니다.

- **폴링으로 보강**: `update()`에서 `HardwareKeyboard.instance.logicalKeysPressed`를 다시 읽어
  실제 현재 상태로 매 프레임 동기화하면, 포커스 복귀 시 자동으로 바로잡힙니다.
- **포커스 상실 처리**: 창/위젯이 포커스를 잃는 시점에 `velocity = Vector2.zero()`로 강제로 멈춥니다.

### 6. 점프·발사가 한 번 눌러도 여러 번 발동한다

`keysPressed` 대신 `event`를 직접 보고 단발 동작을 구현했는데
`KeyDownEvent`로 필터링하지 않은 경우입니다. 키를 누르고 있으면 OS가 `KeyRepeatEvent`를
연속으로 보내므로, 조건을 `if (event is KeyDownEvent && ...)`로 좁혀야 한 번만 발동합니다.

### 7. `normalize()`를 호출했는데 값이 그대로다

`velocity.normalized()`(과거형)는 새 벡터를 **반환**할 뿐 원본을 바꾸지 않습니다.
이 예제처럼 원본을 직접 바꾸려면 `velocity.normalize()`(현재형, 반환값 없음)를 써야 합니다.
반대로 원본을 보존하고 싶다면 `final dir = velocity.normalized();`처럼 반환값을 받아야 합니다.

## 다음 단계로 무엇을 해 볼 수 있을까?

이 예제를 이해했다면 다음과 같은 기능들을 직접 추가해 볼 수 있습니다.

- 화면 가장자리를 벗어나지 않도록 `position`을 제한하기
- 키를 떼면 즉시 멈추는 게 아니라 천천히 감속(마찰) 적용하기
- 스페이스바를 누르면 색이 바뀌거나 점프하는 기능 추가하기
- 사각형 대신 이미지(스프라이트)를 그리기 — `SpriteComponent`로 발전시키기

이 모든 응용은 `velocity`, `speed`, `dt`, `position`이라는 같은 도구로 만들어집니다.
이 네 가지를 자유롭게 다룰 수 있게 되면 2D 게임 캐릭터 이동의 90%는 이해한 셈입니다.

## 참고 자료

- Flame 공식 키보드 입력 문서: [Keyboard Input](https://docs.flame-engine.org/latest/flame/inputs/keyboard_input.html) — `KeyboardEvents`, `HasKeyboardHandlerComponents`, `KeyboardHandler` 사용법
- Flutter `HardwareKeyboard` / `KeyEvent` API (폴링 및 최신 키 이벤트): [HardwareKeyboard class](https://api.flutter.dev/flutter/services/HardwareKeyboard-class.html)
- `LogicalKeyboardKey` 키 상수 목록: [LogicalKeyboardKey class](https://api.flutter.dev/flutter/services/LogicalKeyboardKey-class.html)
