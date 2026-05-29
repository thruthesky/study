# HelloGame 예제: 스프라이트 시트로 idle/walk 애니메이션 전환하기

이 문서는 `lib/main.dart`에 있는 Flame 예제 코드를 설명합니다.
[hello_game_keyboard_movement.md](hello_game_keyboard_movement.md)의 다음 단계로,
**키보드 입력에 따라 캐릭터의 애니메이션 상태(idle ↔ walk)를 전환**하고,
**스프라이트 시트를 잘라 8프레임 애니메이션을 재생**하는 방법을 다룹니다.

이전 단계까지는 사각형이나 정지 이미지가 평행 이동하는 수준이었다면,
이번 단계는 **진짜 게임 캐릭터처럼 움직임에 맞춰 그림이 살아나는 것**이
목표입니다.

> **소스 코드 사본**: 이 문서가 설명하는 시점의 `lib/main.dart`는
> [hello_game_walking_animation/lib/main.dart](hello_game_walking_animation/lib/main.dart)에
> 그대로 복사되어 있습니다. 본 프로젝트의 `lib/main.dart`는 학습이 진행되며
> 계속 바뀌므로, 이 문서를 읽을 때는 사본 쪽을 참고하시면 됩니다.

---

## 0. 학습 목표

이 예제를 끝까지 따라가면 다음을 설명할 수 있게 됩니다.

1. **스프라이트 시트(sprite sheet)란 무엇이며, `amount`/`stepTime`/`textureSize`는 무엇을 가리키는가**
2. **`SpriteAnimation`과 `SpriteAnimationGroupComponent`의 차이와 사용처**
3. **enum을 키로 상태별 애니메이션을 등록하고 `current`로 전환하는 패턴**
4. **`HasGameReference<T>` mixin이 컴포넌트 안에서 `game`을 제공하는 방식**
5. **자식 컴포넌트의 비동기 `onLoad`를 부모 `onLoad`에서 `await`해야 하는 이유**
6. **`MyGame.update`가 매 프레임 `player.applyInput`을 호출해 입력과 게임 루프를 잇는 흐름**

이 6가지가 모두 익숙해지면, Flame으로 캐릭터를 움직이는 데 필요한 기초 골격은
거의 완성된 셈입니다.

---

## 1. 한 프레임 안에서 일어나는 일

코드의 각 줄을 보기 전에, 한 프레임 동안 이 게임이 무엇을 하는지를
큰 그림으로 잡고 가겠습니다.

```text
[키 이벤트 발생]
        ↓
MyGame.onKeyEvent(event, keysPressed)
        ↓
keys 집합 = keysPressed       (현재 눌린 키 갱신)
        ↓
[다음 프레임]
        ↓
MyGame.update(dt)
   ├─ super.update(dt)                    (자식 컴포넌트들의 update 실행)
   └─ player.applyInput(keys, dt)
            ├─ velocity 계산
            ├─ current = idle / running   (애니메이션 상태 전환)
            └─ position += velocity*speed*dt  (이동)
        ↓
Player.render(canvas)                     (Flame이 자동 호출)
   └─ 현재 current의 SpriteAnimation에서 지금 프레임을 잘라 그림
        ↓
[화면에 반영]
```

핵심은 **입력은 `onKeyEvent`가 "최신 키 집합"으로만 갱신**하고,
**실제 이동·상태 전환은 매 프레임 `update`에서 수행**한다는 점입니다.
입력 이벤트와 게임 루프가 `keys` 집합을 통해 약하게 결합되어 있습니다.

---

## 2. 코드 전체 구조

`main.dart`는 크게 다섯 부분으로 나뉩니다.

```text
1. import들                        — 필요한 패키지 가져오기
2. enum PlayerState                — 플레이어의 상태(idle, running)
3. main()                          — Flutter 앱 시작점
4. class MyGame extends FlameGame  — 게임 본체
5. class Player extends SpriteAnimationGroupComponent  — 플레이어 컴포넌트
```

차례대로 살펴보겠습니다.

---

## 3. import — 어떤 패키지가 왜 필요한가

```dart
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
```

| 패키지 | 이 예제에서 필요한 이유 |
|---|---|
| `flame/components.dart` | `SpriteAnimationGroupComponent`, `PositionComponent`, `Vector2`, `Anchor`, `SpriteAnimation`, `SpriteAnimationData` 등 화면 위 객체와 보조 타입 |
| `flame/game.dart` | `FlameGame`, `GameWidget`, `World`, `CameraComponent` 등 게임 본체 |
| `flame/input.dart` | `KeyboardEvents` mixin. 이 줄을 빠뜨리면 `with KeyboardEvents`에서 컴파일 에러 |
| `flutter/material.dart` | `runApp`, `Colors` 등 Flutter 기본 진입점 |
| `flutter/services.dart` | `LogicalKeyboardKey`, `KeyEvent` 등 키보드 입력 타입 |

> **자주 빠뜨리는 import**: `flame/input.dart`가 가장 흔합니다. `KeyboardEvents`는
> `flame/game.dart`에 들어 있지 **않습니다**. 누락 시 "Undefined name
> 'KeyboardEvents'" 에러가 납니다.

---

## 4. enum PlayerState — 상태를 타입으로 만들기

```dart
enum PlayerState { idle, running }
```

플레이어가 가질 수 있는 상태를 enum으로 정의합니다.
지금은 두 가지뿐이지만, 게임이 자라면 다음처럼 늘어납니다.

```dart
enum PlayerState { idle, running, attacking, hit, dying }
```

### 왜 enum인가?

`SpriteAnimationGroupComponent`의 `animations` 맵은 **상태 → 애니메이션**의
짝을 받습니다. 이때 상태를 enum으로 두면 다음 이점이 있습니다.

- **타입 안전**: `current = PlayerState.running` 처럼 오타가 나면 컴파일러가 잡습니다. 문자열 키를 쓰면 `"runing"` 같은 오타가 런타임에 폭탄으로 돌아옵니다.
- **자동완성**: IDE가 가능한 상태 목록을 제안합니다.
- **switch 강제 망라**: `switch (state)`에 새 상태를 빠뜨리면 분석기가 경고합니다.

---

## 5. MyGame — 게임 본체

### 5.1 클래스 선언과 필드

```dart
class MyGame extends FlameGame with KeyboardEvents {
  late final Player player;
  final keys = <LogicalKeyboardKey>{};
}
```

- `FlameGame` 상속 → 게임 루프, world, camera가 자동으로 제공됨.
- `with KeyboardEvents` → 키보드 입력을 받기 위한 mixin.
- `late final Player player;` → onLoad에서 만들 예정. 부모가 이미 `world`, `camera` 같은 이름을 쓰고 있으니 그 이름은 **재선언하지 말 것**(LateInitializationError 원인).
- `final keys = <LogicalKeyboardKey>{};` → "현재 눌려 있는 키들의 집합". 입력 이벤트와 게임 루프를 잇는 다리.

### 5.2 keys 집합이 필요한 이유

`onKeyEvent`는 **키 상태가 바뀌는 순간**에만 호출되지만, `update`는 **매 프레임** 호출됩니다.

```text
사용자가 W 키를 1초 동안 꾹 누름
  ↓
onKeyEvent — 처음 누른 순간 1회, 뗀 순간 1회 (대개 OS 키 리피트로 더 자주 옴)
update    — 그 1초 동안 약 60번 호출됨
```

만약 `onKeyEvent`에서 직접 `player.move(...)`를 호출하면 키를 누른 순간에만
이동하고 그 다음에는 멈춥니다. 우리가 원하는 "꾹 누르고 있는 동안 계속 이동"은
**매 프레임 update에서 현재 입력 상태를 다시 읽는 방식**으로 구현해야 합니다.

그래서:
- `onKeyEvent` → `keys` 집합만 최신화
- `update` → 매 프레임 그 `keys`를 player에 전달

이 패턴이 Flame에서 매우 흔합니다.

### 5.3 onLoad — 게임 시작 시 1회 실행

```dart
@override
Future<void> onLoad() async {
  player = Player()..position = size / 2;
  await world.add(player);
  camera.follow(player);
}
```

세 줄이지만 각각 중요한 의미가 있습니다.

**`Player()..position = size / 2`**

- `Player()` 생성자만 호출. 이 시점에는 아직 onLoad가 실행되지 않음(이미지 로딩 전).
- cascade `..`로 `position`을 `size / 2`(화면 중앙)로 설정.
- `size`는 `FlameGame`이 제공하는 화면 크기(`Vector2`). 800×600이면 `size/2`는 `(400, 300)`.

**`await world.add(player)`**

여기서 `await`가 핵심입니다. 만약 `await` 없이 호출하면:

```text
1. player 인스턴스 생성됨
2. world.add(player) 호출됨 (내부에서 Player.onLoad를 비동기 시작)
3. MyGame.onLoad가 즉시 종료
4. Flame이 곧바로 게임 루프 시작 → MyGame.update 호출
5. update에서 player.applyInput → current = ...
6. 그러나 Player.onLoad가 아직 진행 중 → animations가 null
7. "Animations not set" AssertionError 발생 ❌
```

`await`를 붙이면 4번 시점이 Player.onLoad 완료 뒤로 미뤄지므로 안전합니다.

> **일반 규칙**: 자식 컴포넌트의 onLoad에서 무거운 비동기 작업(이미지/사운드 로드)을 한다면, 부모의 onLoad는 `await world.add(child);` 형태로 자식 로드를 기다려야 합니다.

`add()`가 반환하는 Future가 정확히 무엇을 기다리는지 알아두면 흔들리지 않습니다.
`world.add(player)`는 player의 `onLoad()`(이미지 로드 등)가 끝나는 순간 완료됩니다.
실제 화면 부착(`onMount`)과 트리 편입은 그 다음 게임 틱에 처리되지만, 우리가
`update`에서 의존하는 `animations`는 `onLoad`에서 세팅되므로 `await add`만으로 충분합니다.

여러 자식을 한꺼번에 기다려야 하면 `addAll`을 쓰면 됩니다. 내부적으로 모든
자식의 `onLoad`를 기다리므로 `Future.wait`를 직접 엮을 필요가 없습니다.

```dart
@override
Future<void> onLoad() async {
  player = Player()..position = size / 2;
  final hud = HudComponent();
  await world.addAll([player, hud]); // 둘 다 로드 완료까지 한 번에 대기
  camera.follow(player);
}
```

> **flame 1.29.0 동작 메모**: 1.29.0의 BREAKING 변경(#3602)으로 자식은 부모가
> 트리에서 제거되어도 부모 참조를 유지합니다. 즉 컴포넌트를 잠시 떼었다가
> (`removeFromParent()`) 다시 같은 부모에 붙이는 재사용 패턴이 더 예측 가능해졌습니다.
> 다중 캐릭터·투사체 재활용(9.5)에서 의미가 있습니다.
> (출처: [Flame CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md))

**`camera.follow(player)`**

카메라가 player를 따라가도록 설정합니다. 내부적으로는 `FollowBehavior`라는
컴포넌트가 카메라에 부착되어 매 프레임 카메라 위치를 player에 맞춰 갱신합니다.
별도의 코드 없이 한 줄로 카메라 follow가 구현됩니다.

### 5.4 onKeyEvent — 키 집합 갱신

```dart
@override
KeyEventResult onKeyEvent(
  KeyEvent event,
  Set<LogicalKeyboardKey> keysPressed,
) {
  keys
    ..clear()
    ..addAll(keysPressed);
  return KeyEventResult.handled;
}
```

- `event` — 이번에 발생한 단일 키 이벤트 (사용하지 않음).
- `keysPressed` — **현재 시점**에 눌려 있는 모든 키들의 집합.
- `keys`를 통째로 `keysPressed`로 교체. cascade로 한 줄에 두 호출 처리.

> **왜 `keys = keysPressed`가 아닌가?** `keys`를 새 Set으로 갈아끼우면 기존 참조가 망가질 수 있고, 매 키 이벤트마다 새 Set 객체를 만들어 GC 부담이 됩니다. clear + addAll은 **같은 인스턴스의 내용을 교체**해서 더 효율적입니다. 다만 차이는 미미하므로 가독성을 우선해 `keys = keysPressed.toSet();`처럼 써도 무방합니다.

- `KeyEventResult.handled` — "이 이벤트는 내가 처리했으니 다른 위젯에 전달하지 마라"는 신호.

### 5.5 update — 입력을 player에 전달

```dart
@override
void update(double dt) {
  super.update(dt);
  player.applyInput(keys, dt);
}
```

- `super.update(dt)` — **반드시 먼저 호출.** 부모(FlameGame)가 자식 컴포넌트들의 `update`를 순회 실행하는 작업을 합니다. 빼먹으면 자식들이 멈춥니다.
- `player.applyInput(keys, dt)` — 매 프레임 player에게 현재 키 집합과 dt를 넘김. player가 그 정보로 이동·상태 전환을 처리.

---

## 6. Player — 애니메이션 그룹 컴포넌트

### 6.1 클래스 선언

```dart
class Player extends SpriteAnimationGroupComponent
    with HasGameReference<MyGame> {
```

**`SpriteAnimationGroupComponent`**

Flame이 제공하는 컴포넌트 중 "**상태별로 다른 애니메이션을 들고 있다가
`current` 값에 따라 자동으로 화면에 그릴 애니메이션을 전환**"하는 컴포넌트입니다.

비교표:

| 컴포넌트 | 들고 있는 것 | 표시되는 것 |
|---|---|---|
| `SpriteComponent` | 정지 이미지 1장 (Sprite) | 항상 같은 그림 |
| `SpriteAnimationComponent` | 애니메이션 1개 (SpriteAnimation) | 한 종류의 애니메이션이 계속 재생 |
| `SpriteAnimationGroupComponent<T>` | 상태별 애니메이션 맵 | `current` 값에 해당하는 애니메이션이 재생 |

이번 예제는 idle과 walk 두 가지 상태가 필요하므로 그룹 컴포넌트를 씁니다.

**`with HasGameReference<MyGame>`**

이 mixin이 붙으면 컴포넌트 안에서 `game` 프로퍼티로 자기가 속한 게임 인스턴스에
접근할 수 있습니다. `game.images.load(...)`처럼 게임이 제공하는 자원을
편하게 부를 수 있게 됩니다.

제네릭 `<MyGame>`을 주면 `game`이 `MyGame` 타입으로 인식되어, MyGame에만 있는
필드/메서드도 캐스팅 없이 호출 가능합니다.

> **버전 메모(HasGameRef → HasGameReference)**: 옛 `HasGameRef` mixin(과 그 안의
> `gameRef` getter)은 flame **1.28.0**에서 `HasGameReference`(접근자 `game`)로
> deprecated 되었습니다(PR [#3559](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md)).
> 인터넷의 오래된 예제나 일부 문서에 "1.33부터 deprecated"로 적힌 경우가 있는데
> 이는 도입 버전 오류입니다. 결론은 동일합니다 — 신규 코드는 항상
> `HasGameReference`(+`game`)를 사용하세요. 본 코스 기준 flame은 **1.37.0**(2026-04-01
> 출시)이며 이 예제 코드는 1.37.0에서 그대로 동작합니다.

### 6.2 onLoad — 두 애니메이션 로드와 등록

```dart
@override
Future<void> onLoad() async {
  final idelImage = await game.images.load('player.png');
  final idleAnimation = SpriteAnimation.fromFrameData(
    idelImage,
    SpriteAnimationData.sequenced(
      amount: 8,
      stepTime: 0.2,
      textureSize: Vector2(32, 32),
    ),
  );
  final walkImage = await game.images.load('player_walk.png');
  final walkAnimation = SpriteAnimation.fromFrameData(
    walkImage,
    SpriteAnimationData.sequenced(
      amount: 8,
      stepTime: 0.1,
      textureSize: Vector2(32, 32),
    ),
  );
  animations = {
    PlayerState.idle: idleAnimation,
    PlayerState.running: walkAnimation,
  };
  current = PlayerState.idle;
  size = Vector2(64, 64);
  anchor = Anchor.center;
}
```

세 단계로 나눠서 봅니다.

#### 6.2.1 `game.images.load(...)` — 이미지 텍스처 로드

```dart
final idelImage = await game.images.load('player.png');
```

- `pubspec.yaml`의 `assets:`에 등록된 PNG를 디코딩해 `dart:ui`의 `Image` 객체를 반환.
- 결과는 GPU에 업로드될 텍스처의 원본.
- **비동기**이므로 `await` 필수.
- (변수명 `idelImage`는 `idleImage`의 오타이지만 사용자 코드를 그대로 보존했습니다.)

#### 6.2.2 `SpriteAnimation.fromFrameData(...)` — 시트를 잘라 애니메이션 생성

```dart
SpriteAnimation.fromFrameData(
  idelImage,
  SpriteAnimationData.sequenced(
    amount: 8,
    stepTime: 0.2,
    textureSize: Vector2(32, 32),
  ),
);
```

이 한 줄이 "큰 PNG 한 장을 8개의 프레임으로 잘라서 순환 재생하는 애니메이션"을
만듭니다. 옵션의 의미는 다음과 같습니다.

```text
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ F0 │ F1 │ F2 │ F3 │ F4 │ F5 │ F6 │ F7 │   ← 세로 32
└────┴────┴────┴────┴────┴────┴────┴────┘
  ▲                                       
  └─ textureSize = Vector2(32, 32)  한 칸의 가로×세로 크기
     amount      = 8                 칸의 개수
     stepTime    = 0.2 / 0.1         한 칸을 보여 주는 시간(초)
```

즉:
- `amount: 8` → 시트에 들어 있는 프레임은 8개.
- `stepTime: 0.2` → 한 프레임을 0.2초 동안 보여 줌(초당 5프레임). idle처럼 느린 호흡에 적합.
- `stepTime: 0.1` → 한 프레임을 0.1초 동안 보여 줌(초당 10프레임). walk처럼 빠른 발걸음에 적합.
- `textureSize: Vector2(32, 32)` → 시트의 한 칸이 32×32픽셀이라는 뜻. 시트의 실제 한 프레임 크기와 정확히 일치해야 함.

`SpriteAnimationData.sequenced`는 "가로로 순서대로 amount개 잘라낸다"의 의미입니다. 가로 배열 시트에 가장 자주 쓰이는 형태입니다.

> **textureSize가 실제와 다르면**: 캐릭터가 잘려서 보이거나 두 프레임이 겹쳐 보입니다. 예를 들어 실제는 64×64인데 32×32로 설정하면 왼쪽 위 머리만 보입니다. 시트의 실제 픽셀 크기를 먼저 확인하고 값을 맞추세요.

##### `sequenced`의 나머지 옵션 — loop / amountPerRow / texturePosition

`amount`·`stepTime`·`textureSize`만으로 단순 가로 시트는 충분하지만, `SpriteAnimationData.sequenced`에는 실전에서 꼭 쓰게 되는 옵션이 더 있습니다(flame 1.37.0 기준).

```dart
SpriteAnimationData.sequenced(
  amount: 8,
  stepTime: 0.1,
  textureSize: Vector2(32, 32),
  amountPerRow: 4,                  // 그리드 시트: 한 줄에 4칸 → 다음 줄로 자동 줄바꿈
  texturePosition: Vector2(0, 64),  // 시트 안에서 잘라내기 시작할 오프셋(픽셀)
  loop: true,                       // false면 마지막 프레임에서 멈춤(공격/사망에 사용)
);
```

- **`amountPerRow`** — **그리드(예: 4×2) 시트를 그대로 처리**합니다. 한 줄에 몇 칸인지를 주면 마지막 칸 다음에 자동으로 아랫줄 첫 칸으로 이어 자릅니다. 따라서 앞서 "그리드는 본 예제 범위 밖"이라고 미뤘던 케이스는 사실 `amountPerRow`만 주면 `sequenced`로 해결됩니다. 생략하면 "한 줄짜리 가로 시트"로 간주합니다.
- **`texturePosition`** — **여러 캐릭터/여러 모션이 한 장의 큰 아틀라스에 모여 있을 때**, 잘라내기 시작 좌표를 지정합니다. 예: 위 32px 줄은 idle, 아래 줄(`y=64`)은 walk처럼 한 PNG에서 두 모션을 뽑아낼 수 있습니다.
- **`loop`** — 기본값 `true`(무한 반복). `false`면 `amount`번째 프레임에서 멈춥니다. **공격·피격·사망처럼 "한 번만 재생되고 끝나야 하는" 모션**에 필수입니다(9.1에서 활용).

> **그리드 시트 예시(4×2, 한 칸 32×32)**: 8프레임을 한 줄에 4칸씩 두 줄로 배치한 PNG라면
> `SpriteAnimationData.sequenced(amount: 8, stepTime: 0.1, textureSize: Vector2.all(32), amountPerRow: 4)`로
> 한 번에 잘립니다. `range`/`variable`이나 수동 `SpriteAnimationFrameData` 배열은 칸마다 크기·간격이 다른 비정형 시트에서만 필요합니다.
> (출처: [Flame 공식 문서 — Animation](https://docs.flame-engine.org/latest/flame/rendering/images.html))

#### 6.2.3 `animations` 맵과 `current` 설정

```dart
animations = {
  PlayerState.idle: idleAnimation,
  PlayerState.running: walkAnimation,
};
current = PlayerState.idle;
```

- `animations`는 `SpriteAnimationGroupComponent`가 제공하는 setter. **상태 → 애니메이션** 짝을 등록합니다.
- `current`도 마찬가지로 setter. 현재 재생할 애니메이션의 키를 지정.
- 시작 시점에는 player가 가만히 있으므로 `idle` 상태.

이 시점부터 player는 idle 애니메이션을 0.2초씩 8프레임으로 무한 순환 재생합니다.

#### 6.2.4 size와 anchor 설정

```dart
size = Vector2(64, 64);
anchor = Anchor.center;
```

- `size = Vector2(64, 64)` → 화면 표시 크기를 64×64픽셀로. 시트의 한 프레임이 32×32라도, GPU에서 자동으로 2배 확대되어 그려집니다.
- `anchor = Anchor.center` → `position`이 컴포넌트의 정중앙을 가리키게 함. `size/2`로 정한 화면 중앙 좌표가 정확히 캐릭터의 중심에 오게 됩니다.

> **anchor 기본값은 `topLeft`** 입니다. 캐릭터처럼 회전·확대를 자연스럽게 하고 싶다면 거의 항상 `Anchor.center`로 두세요.

### 6.3 applyInput — 이동과 상태 전환의 핵심

```dart
void applyInput(Set<LogicalKeyboardKey> keys, double dt) {
  final velocity = Vector2.zero();
  if (keys.contains(LogicalKeyboardKey.arrowUp))    velocity.y -= 1;
  if (keys.contains(LogicalKeyboardKey.arrowDown))  velocity.y += 1;
  if (keys.contains(LogicalKeyboardKey.arrowLeft))  velocity.x -= 1;
  if (keys.contains(LogicalKeyboardKey.arrowRight)) velocity.x += 1;

  current = velocity.length > 0 ? PlayerState.running : PlayerState.idle;

  const double speed = 300;
  position += velocity.normalized() * speed * dt;
}
```

#### 6.3.1 velocity를 매 프레임 0에서 시작

```dart
final velocity = Vector2.zero();
```

이전 프레임의 방향이 남아 있으면 키를 떼도 캐릭터가 계속 흘러갑니다. 매 프레임
초기화가 필수.

#### 6.3.2 `+=`/`-=` 누적의 의미

```dart
if (keys.contains(LogicalKeyboardKey.arrowUp))    velocity.y -= 1;
if (keys.contains(LogicalKeyboardKey.arrowDown))  velocity.y += 1;
```

`+=`/`-=`로 누적하면 위쪽과 아래쪽을 동시에 누른 경우 `-1 + 1 = 0`이 되어
이동이 자연스럽게 상쇄됩니다. 직접 `velocity.y = -1` / `velocity.y = 1`로
대입하면 마지막 if만 적용되어 미묘한 차이가 생깁니다. 누적 방식이 더 견고합니다.

#### 6.3.3 상태 전환 — 1줄로 끝

```dart
current = velocity.length > 0 ? PlayerState.running : PlayerState.idle;
```

이 한 줄이 idle ↔ walk 전환의 전부입니다.

- `velocity.length`는 벡터의 길이(0 이상의 실수).
- 0이면 어떤 방향 키도 안 눌린 것 → idle.
- 0보다 크면 어딘가로 이동 중 → running.
- `current`에 같은 값을 매 프레임 대입해도 안전합니다(내부적으로 값이 바뀌는 순간에만 애니메이션을 리셋함). 그래서 `if (current != ...)` 같은 가드가 필요 없습니다.

#### 6.3.4 위치 갱신 — `position += velocity * speed * dt`

```dart
const double speed = 300;
position += velocity.normalized() * speed * dt;
```

- `velocity.normalized()` → 방향만 남기고 길이를 1로. 대각선 이동이 상하좌우보다 빨라지지 않게 합니다.
- `speed` → 1초당 이동할 픽셀 수.
- `dt` → 이번 프레임에 흐른 시간(초).
- 최종적으로 "이번 프레임 동안 normalized 방향으로 `speed * dt` 픽셀 이동".

dt를 곱했기 때문에 FPS가 60이든 30이든 1초에 항상 300픽셀씩 이동합니다.
이건 게임 개발의 가장 기본 공식 중 하나입니다.

---

## 7. 전체 흐름 다시 따라가기

**상황: D 키와 W 키를 동시에 꾹 누름.**

```text
[t = 0s]   사용자가 D, W 키를 누름

           Flame → MyGame.onKeyEvent(_, {keyD, keyW})
           keys = {keyD, keyW}

[t = 0s]   다음 프레임 (dt ≈ 0.0167s)

           Flame → MyGame.update(0.0167)
             super.update(0.0167)
             → Player.update(0.0167) (그룹 컴포넌트가 내부 frame을 갱신)
             → applyInput({keyD, keyW}, 0.0167)
                  velocity = (0, 0)
                  keyW match → velocity.y -= 1  → (0, -1)
                  keyD match → velocity.x += 1  → (1, -1)
                  velocity.length ≈ 1.414 > 0
                  current = PlayerState.running        ← walk 애니메이션으로 전환
                  position += (1,-1).normalized()*300*0.0167
                            ≈ (3.54, -3.54) 픽셀 이동

           Flame → Player.render(canvas)
             현재 running 애니메이션의 현재 프레임(F0)을 64×64로 잘라 그림

[t = 0.1s] walk의 stepTime이 0.1이므로 프레임이 F0 → F1로 자동 전환됨
           player는 그동안 약 213픽셀 이동한 상태

[t = 1s]   사용자가 키를 모두 뗌

           Flame → MyGame.onKeyEvent(_, {})
           keys = {}

[t = 1s+]  다음 프레임
           → applyInput({}, dt)
                velocity = (0, 0)
                velocity.length == 0
                current = PlayerState.idle           ← idle 애니메이션으로 전환
                position += (0,0).normalized()*... = position (이동 없음)
```

키 입력 한 번에 walk 시작/idle 복귀가 자연스럽게 일어나는 이유는
**`update`가 매 프레임 `keys`를 다시 읽어 velocity를 매번 새로 계산**하기 때문입니다.

---

## 8. 자주 만나는 함정

### 8.1 "LateInitializationError: Field 'camera' has not been initialized"

`MyGame` 안에 `late final CameraComponent camera;`를 선언했을 때. `FlameGame`이
이미 `camera`라는 getter를 가지고 있어서 자식의 선언이 그것을 가립니다. 부모가
내부에서 `camera`를 호출할 때 자식의 미초기화 필드를 보러 가서 폭발합니다.

**해결**: `world`, `camera`, `size` 같은 이름은 부모가 이미 제공하므로 **재선언하지 마세요.** 그냥 `world.add(...)`, `camera.follow(...)` 처럼 바로 쓰면 됩니다.

### 8.2 "Animations not set"

`MyGame.update`에서 `player.applyInput`을 호출했는데, `Player.onLoad`가 아직
끝나지 않아 `animations`가 null인 경우.

**해결**: `MyGame.onLoad`에서 `await world.add(player);`로 자식의 로드 완료를 기다리세요.

### 8.3 "Unable to load asset: assets/images/xxx.png"

`pubspec.yaml`의 `assets:` 항목에 해당 PNG가 등록되어 있지 않음.

**해결**: `pubspec.yaml`에 `- assets/images/your_file.png`를 추가하고 **hot restart**(hot reload 아님).

### 8.4 캐릭터가 잘리거나 깨져 보임

`textureSize`가 실제 시트의 한 프레임 크기와 다름.

**해결**: 시트의 실제 픽셀 크기를 `file your_sheet.png`로 확인하고, `textureSize`를 그 값에 맞추세요. 가로 시트라면 `(시트 가로 ÷ amount, 시트 세로)`가 정답입니다.

### 8.5 키를 떼도 캐릭터가 계속 이동

`applyInput` 시작 부분에서 `velocity = Vector2.zero()` 초기화를 빼먹음. 이전
프레임의 방향이 남아 있어 계속 이동하게 됨.

### 8.6 walk 상태인데 그림이 안 바뀜

- `super.update(dt)`를 호출하지 않으면 자식 컴포넌트의 내부 frame이 갱신되지 않아 애니메이션이 정지된 것처럼 보입니다. `MyGame.update`에서 `super.update(dt)`를 반드시 호출하세요.
- 혹은 `current`가 매 프레임 같은 값으로 계속 리셋되지는 않는지 확인. 본 예제처럼 같은 값 대입은 안전하지만, 다른 패턴에서 의도치 않게 frame을 reset하는 코드가 끼면 멈춰 보일 수 있습니다.

---

## 9. 다음 단계 확장 아이디어

이 예제가 이해되었다면 다음을 직접 추가해 보세요. 모두 비슷한 패턴의 변형입니다.

### 9.1 attack 상태 추가 (1회성 모션 + 자동 복귀)

```dart
enum PlayerState { idle, running, attacking }
```

스페이스바를 누르면 `attacking`으로 전환되고, 공격 모션이 **끝나면** 자동으로
`idle`/`running`으로 돌아오게 합니다. 핵심은 **공격 애니메이션은 한 번만 재생되고
멈춰야 한다**는 점입니다. idle/walk처럼 무한 반복하면 안 됩니다.

**(1) attack 애니메이션은 `loop: false`로 만든다**

```dart
final attackAnimation = SpriteAnimation.fromFrameData(
  attackImage,
  SpriteAnimationData.sequenced(
    amount: 6,
    stepTime: 0.06,
    textureSize: Vector2(32, 32),
    loop: false,           // 마지막 프레임에서 멈춤 → onComplete가 호출됨
  ),
);
animations = {
  PlayerState.idle: idleAnimation,
  PlayerState.running: walkAnimation,
  PlayerState.attacking: attackAnimation,
};
```

**(2) `animationTickers`로 "공격이 끝나는 순간"을 잡아 복귀**

`SpriteAnimationGroupComponent`는 상태마다 `SpriteAnimationTicker`(재생 위치를
추적하는 객체)를 자동으로 만들어 `animationTickers` 맵에 보관합니다. 그 ticker의
`onComplete` 콜백에 복귀 로직을 달면, "공격 모션이 끝난 순간"에만 호출됩니다.

```dart
@override
Future<void> onLoad() async {
  // ... animations 세팅 후 ...
  animationTickers?[PlayerState.attacking]?.onComplete = () {
    isAttacking = false;            // 공격 종료 플래그 내림
  };
}

bool isAttacking = false;
```

**(3) `applyInput`에서 공격 중에는 이동 상태 전환을 막는다**

```dart
void applyInput(Set<LogicalKeyboardKey> keys, double dt) {
  if (keys.contains(LogicalKeyboardKey.space) && !isAttacking) {
    isAttacking = true;
    current = PlayerState.attacking;
    animationTickers?[PlayerState.attacking]?.reset(); // 처음부터 다시 재생
    return;                                            // 공격 시작 프레임엔 이동·전환 생략
  }
  if (isAttacking) return;          // 공격 재생 중에는 idle/walk로 덮어쓰지 않음

  final velocity = Vector2.zero();
  // ... 기존 이동/상태 전환 로직 ...
}
```

- `loop: false`가 아니면 `onComplete`는 **영원히 호출되지 않습니다**(무한 루프는 "끝"이 없으므로). 이것이 가장 흔한 실수입니다.
- `reset()`을 호출해야 같은 키를 다시 눌렀을 때 처음 프레임부터 재생됩니다(이미 끝난 ticker는 마지막 프레임에 멈춰 있으므로).
- `TimerComponent`로 0.5초 후 강제 복귀하는 방식도 가능하지만, `onComplete`는 **애니메이션 길이와 복귀 시점이 항상 일치**한다는 장점이 있어 더 견고합니다.

> (출처: [Flame 공식 문서 — Animation / SpriteAnimationTicker](https://docs.flame-engine.org/latest/flame/rendering/images.html))

### 9.2 좌우 반전 (방향에 따라 sprite를 뒤집기)

```dart
if (velocity.x < 0) {
  scale.x = -1;        // 왼쪽 향함(수평 뒤집기)
} else if (velocity.x > 0) {
  scale.x = 1;         // 오른쪽 향함(원래 방향)
}
// velocity.x == 0(위/아래만, 또는 정지)일 때는 손대지 않음 → 마지막 향한 방향 유지
```

`PositionComponent`의 `scale`을 활용하면 별도 좌·우 시트 없이 한 시트로
양방향을 표현할 수 있습니다. 다만 게임답게 만들려면 디테일 두 가지를 기억하세요.

- **`anchor = Anchor.center` 전제에서만 위치가 안 틀어집니다.** `scale.x = -1`은
  컴포넌트의 `anchor` 기준으로 좌우를 뒤집습니다. 이 예제는 6.2.4에서 anchor를
  center로 두었으므로, 뒤집어도 캐릭터의 중심(=`position`)이 그대로 유지됩니다.
  만약 anchor가 기본값 `topLeft`라면 뒤집는 순간 캐릭터가 자기 폭만큼 옆으로
  순간이동하는 버그가 생깁니다. 가독성을 위해 `flipHorizontallyAroundCenter()`를
  쓰면 anchor와 무관하게 항상 중심 기준으로 뒤집어 더 안전합니다.
- **`velocity.x == 0`일 때 방향을 덮어쓰지 마세요.** 위 코드처럼 좌/우 입력이 없을
  때 `scale.x`를 건드리지 않으면, 위·아래로만 이동하거나 정지했을 때 **직전에 보던
  방향을 그대로 유지**합니다(예: 왼쪽을 보다 위로 걸어도 계속 왼쪽을 봄). `else`로
  무조건 `scale.x = 1`을 주면 멈출 때마다 오른쪽으로 홱 돌아 어색합니다.

이 두 줄을 `applyInput`의 상태 전환(`current = ...`) 바로 다음에 넣으면 됩니다.

### 9.3 화면 가장자리 제한

`position.clamp(...)` 또는 `position.x = position.x.clamp(0, worldWidth)` 같은 식으로 player가 월드 밖으로 나가지 않게 합니다.

### 9.4 호흡(idle) 시트 만들기

idle 시트를 진짜 호흡 애니메이션(2~4프레임)으로 바꾸면 캐릭터가 살아 있어
보입니다. 코드 변경 없이 PNG만 교체하면 됩니다.

### 9.5 다중 캐릭터

`Player`를 여러 개 만들어 `world.add` 하면 화면에 여러 캐릭터가 나타납니다.
다음 단계로 NPC, 적 캐릭터, 멀티플레이까지 확장할 수 있습니다.

> **성능 포인터(많아질 때)**: 적·투사체·이펙트처럼 **대량으로 생성·소멸하는**
> 객체는 매번 `new`/`removeFromParent`를 반복하면 GC 압력이 커집니다. flame
> **1.36.0**에 추가된 `ComponentPool`(#3816)로 객체를 풀링하면 재사용으로 이
> 부담을 줄일 수 있습니다. 또 같은 스프라이트를 쓰는 자식이 수십~수백 개라면
> flame **1.37.0**의 `HasAutoBatchedChildren` mixin(#3850)으로 draw call을 배칭해
> 렌더 비용을 낮출 수 있습니다. 입문 단계에선 몰라도 되지만, "캐릭터가 100마리가
> 되면 무엇을 쓰는가"의 답으로 기억해 두세요.
> (출처: [Flame CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md))

---

## 10. 관련 문서

- [hello_game_map_objects.md](hello_game_map_objects.md) — 게임 맵(world)에 나무·분수 등 기물 배치하기 (이 예제의 다음 단계)
- [hello_game_vector2_velocity.md](hello_game_vector2_velocity.md) — Vector2와 velocity의 기초 개념
- [hello_game_keyboard_movement.md](hello_game_keyboard_movement.md) — 키보드로 사각형 움직이기 (이 예제의 전 단계)
- [../game-glossary.md](../game-glossary.md) — 프레임, 스프라이트 시트, dt, Component 등 게임 용어 정리
- [../00-prereq-flutter-to-flame.md](../00-prereq-flutter-to-flame.md) — Flutter 위젯 패러다임과 Flame Component 패러다임의 차이
- [../01-phase1-flame-basics.md](../01-phase1-flame-basics.md) — Flame의 Component/World/Camera 본격 학습

다음에는 같은 player에 **공격 모션, 좌우 반전, 화면 경계 제한**을 추가하면서
캐릭터를 진짜 게임답게 만드는 단계를 학습하시면 됩니다.
