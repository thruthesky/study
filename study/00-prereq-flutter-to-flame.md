# Prereq — Flutter 개발자가 Flame으로 넘어오기

> **기간**: 2~3일
> **목표**: Flutter Widget 패러다임과 Flame Component 패러다임의 결정적 차이를 체득하고, Hello Flame 프로젝트를 60fps로 띄운다.
> **전제**: 본 코스는 100% Flutter로 개발합니다. 학습자는 이미 Flutter 풀스택을 운영해 본 경험이 있다고 가정합니다.

---

## 1. 왜 별도 Prereq가 필요한가

Flutter 위젯 기반의 일반 앱·웹 개발 경험은 풍부하지만 Flame은 처음인 개발자가 가장 흔히 하는 오해는 다음과 같습니다:

| 잘못된 직관 | 실제 |
|---|---|
| "Widget 트리에 GameWidget 하나 넣으면 끝" | 맞지만, **Widget은 정지 상태에서 단발성 렌더링**이고, Flame은 **매 프레임 update + render** |
| "setState로 캐릭터 위치 갱신" | Flame Component의 `position`은 직접 변경, setState 불필요 |
| "Provider/Riverpod으로 게임 상태 관리" | 게임 내부 상태는 **Component가 직접 보유**. Riverpod은 메뉴·HUD·메타 데이터에만 |
| "Future로 비동기 처리" | 게임 로직은 **동기 + dt 기반**. async는 네트워크·로딩에만 |
| "build()에서 위젯 트리 다시 만들면 됨" | Flame은 build()가 없음. **`update(dt)` 안에서 변경, `render(canvas)`는 자동** |
| "60fps는 알아서 되겠지" | 매 프레임 객체 생성, 큰 Widget rebuild → 즉시 프레임 드랍 |

**핵심 사고 전환**:
```
Flutter:  사용자 입력 → setState → 위젯 트리 rebuild → 렌더
Flame:    매 16.6ms마다 update(dt) → 좌표 변경 → render(canvas) (자동)
```

웹 개발 비유로 말하면:
- **Flutter Widget** = React 컴포넌트 (선언적, 이벤트 기반 rebuild)
- **Flame Component** = HTML5 Canvas + requestAnimationFrame 루프 (명령적, 매 프레임 폴링)

---

## 2. 사전 설치

```bash
flutter --version   # 공식 stable 기준 Flutter 3.44 이상 권장
flutter create flame_hello
cd flame_hello
flutter pub add flame
```

`pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flame: ^1.37.0
```

> 2026-05-28 기준 `flame 1.37.0`(**2026-04-01 출시**)은 `pubspec.yaml`의 `environment` 기준 Dart SDK `>=3.11.0 <4.0.0`, **Flutter `>=3.41.0`**(v1.36에서 bump)을 요구합니다. Flutter는 공식 stable 문서 기준 3.44 이상을 권장합니다. (흔히 보이는 'Dart `>=3.0.0`' 표기는 초기 1.x 기준 일반화로, 1.37.0에는 맞지 않습니다.) Flame은 0.x → 1.x로 바뀌면서 API가 크게 바뀌었으므로 **1.x 문서만 참고하세요.** 본 study 프로젝트의 `pubspec.yaml`은 `sdk: ^3.12.0` / `flame: ^1.37.0`이라 이 최소 요구를 자연히 충족합니다.
>
> **2026-05 권장 코드 패턴 변경**:
> - `HasGameRef<MyGame>` 은 v1.28.0부터 **`HasGameReference<MyGame>`** 으로 deprecate(GitHub CHANGELOG의 `FIX: Deprecate HasGameRef in favor of HasGameReference` #3559). 신규 코드는 `HasGameReference` 사용.
> - `with HasCollisionDetection` 은 `FlameGame` 뿐 아니라 **`World`에 직접 부여**하는 패턴이 최신 권장(CameraComponent + World 구조).
> - `NoiseEffectController` 는 `flame_noise` 패키지로 이전됨 (이미 본 코스 Phase 2부터 별도 패키지로 도입).
> 자세한 변경 이력: https://pub.dev/packages/flame/changelog · https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md

> **flame 1.37.0(2026-04-01)의 실제 신기능** — 출시일을 정정한 김에, 이 버전이 무엇을 더했는지도 알아두면 코스 후반 최적화·연출 단계에서 도움이 됩니다(전부 공식 CHANGELOG 기준).
> - `FEAT`: `SpriteBatch`에 **`bleed` 옵션** 추가(#3871) — 타일맵 경계의 seam(가는 흰 줄/이음새) artifact 방지. Phase 3 Isometric 맵 + Phase 7 atlas 렌더에서 유용.
> - `FEAT`: **`HueEffect` / `HueDecorator`** 추가(#3852) — 색조 변경 이펙트.
> - `FEAT`: **`HasAutoBatchedChildren`** mixin 추가(#3850) — draw call 자동 배칭으로 렌더 성능 최적화.
> - `FEAT`: `OverlayManager.setActive()` 추가(#3875) — 오버레이 활성화 제어.
> - `FEAT`: `Sprite`/`SpriteAnimation` 위젯에 `size` 파라미터 추가(#3870).
> - `FEAT`: `isometric_tile_map_component`에서 `Block` 분리 + 헬퍼 메서드(#3859).
> - `FIX`: `flame test` helper에서 async 제거(#3860, `flame_test 2.2.4`와 동기).
>
> ⚠️ **흔한 버전 오해 주의**: 아래는 1.37.0이 아니라 더 이전 버전 기능입니다(코스 본문에서 신기능으로 소개할 땐 버전을 정확히 표기하세요).
> - `SpawnComponent`의 `target`/`spawnCount`(#3635/#3634), `RasterSpriteComponent.fromImage`(#3627), 스프라이트 ghost-line 수정(#3590) → **1.30.0**.
> - "Children should retain parent after parent is removed from tree"(BREAKING, #3602) → **1.29.0**.
> - `HasGameRef` → `HasGameReference` deprecate(#3559) → **1.28.0**.

---

## 3. Flutter 위젯과의 결정적 차이 4가지

### 3.1 build() 가 없다 — 매 프레임 update(dt)

```dart
// 일반 Flutter 위젯 코드
class _MyWidgetState extends State<MyWidget> {
  double x = 0;
  @override
  Widget build(BuildContext context) {
    return Positioned(left: x, child: ...);
  }
  void moveRight() => setState(() => x += 10);
}

// Flame
class Player extends PositionComponent {
  @override
  void update(double dt) {
    super.update(dt);
    position.x += 100 * dt;   // dt = 약 0.0166초 (60fps)
    // setState 없음. 다음 프레임에 자동 render.
  }
}
```

**dt(delta time)의 의미**: 이전 프레임으로부터 경과한 초. 60fps라면 ~0.0166. 모든 이동·애니메이션 시간은 dt를 곱해야 프레임 레이트와 무관하게 일정 속도가 됩니다.

#### 게임 루프 vs 위젯 빌드 — 무엇이 언제 호출되는가

Flutter의 빌드 모델과 Flame의 게임 루프는 **"누가 다시 그리라고 시키는가"**가 근본적으로 다릅니다.

| 항목 | Flutter Widget | Flame 게임 루프 |
|---|---|---|
| 다시 그리는 트리거 | `setState`/Provider notify 등 **상태 변경 이벤트** (pull) | **매 vsync(프레임)** 자동 (push) |
| 한 사이클 단계 | `build()` 한 단계(선언적 트리 재생성) | **`update(dt)` → `render(canvas)`** 두 단계 분리 |
| 호출 빈도 | 변경이 없으면 0회 | 변경이 없어도 초당 ~60회 |
| 비용 모델 | rebuild diff(Element 트리 재조정) | 매 프레임 좌표 계산 + 캔버스 드로우 |
| 멈추는 법 | 그냥 setState를 안 부르면 됨 | `pauseEngine()` / 컴포넌트 제거 필요 |

Flame의 한 프레임은 **두 단계**로 명확히 나뉩니다. 이 분리가 Flutter와 가장 다른 점입니다.

```dart
class HelloGame extends FlameGame {
  @override
  void update(double dt) {      // ① 게임 로직: 좌표·상태·충돌·AI 계산만. 그리지 않음.
    super.update(dt);           //    super가 자식 Component들의 update(dt)를 재귀 호출
  }

  @override
  void render(Canvas canvas) {  // ② 그리기 전용: 위에서 계산된 상태를 캔버스에 출력
    super.render(canvas);       //    super가 자식들의 render(canvas)를 재귀 호출
  }
}
```

- `update`에서 **그리지 말고**, `render`에서 **상태를 바꾸지 마세요**. 이 둘을 섞으면 프레임 타이밍 버그가 생깁니다.
- `update`/`render`는 모두 **부모 → 자식으로 트리를 따라 재귀**됩니다. 그래서 직접 `super.update(dt)`/`super.render(canvas)`를 호출하지 않으면 자식들이 멈춥니다.
- **루프 제어 API**: `pauseEngine()` / `resumeEngine()`(엔진 전체 정지), 컴포넌트의 `paused` 플래그, `timeScale`(슬로우/패스트 모션) 등으로 흐름을 조절합니다. Flutter처럼 "안 부르면 멈춤"이 아니라 **명시적으로 멈춰야** 합니다.

> **고정 timestep(fixed update)**: 물리/네트워크 동기화처럼 dt 변동에 민감한 로직은 가변 dt 대신 일정 간격으로 처리해야 합니다. Flame은 `FixedUpdateComponent`(또는 직접 누산기 패턴)로 `fixedUpdate`를 구현할 수 있고, 멀티플레이의 서버 tick(§5.4 참고)도 이 고정 간격 원리를 따릅니다.

### 3.2 좌표계가 다르다

| | Flutter | Flame |
|---|---|---|
| 원점 | 부모 위젯의 left-top | World(또는 부모 Component)의 left-top |
| 단위 | logical pixel | 동일 (logical pixel) — 단, 카메라 줌에 따라 변환 |
| Y축 | 아래로 + | 아래로 + (동일) |

차이는 **카메라**입니다. Flame은 World 좌표 위에 Camera가 따로 있고, 카메라가 보는 영역만 화면에 그려집니다. 일반 Flutter의 `SingleChildScrollView` / `InteractiveViewer`와 개념은 비슷하지만, **줌/회전/follow가 GPU 변환**으로 처리됩니다.

### 3.3 상태관리: Component가 곧 상태

```dart
// Flutter: 상태와 UI 분리 (Provider)
class PlayerState extends ChangeNotifier { int hp = 100; }

// Flame: 상태 = Component 자체
class Player extends PositionComponent {
  int hp = 100;           // 그냥 필드. 외부에 노출할 필요 없음.
  Vector2 velocity = Vector2.zero();

  @override
  void update(double dt) {
    position += velocity * dt;
    if (hp <= 0) removeFromParent();   // setState 없이 자기 자신 제거
  }
}
```

> Riverpod이 필요한 시점: **게임 외부 UI** (메인 메뉴, 인벤토리 창의 Flutter Widget 부분, 설정 화면).
> 게임 내부 엔티티의 hp/position/state는 Riverpod에 넣지 마세요. 매 프레임 변경되는 값을 Provider에 넣으면 위젯 트리가 매 프레임 rebuild됩니다 → 즉사.

### 3.4 라이프사이클

| Flutter Widget | Flame Component |
|---|---|
| `initState()` | `onLoad()` (async 가능, 에셋 로딩) |
| `build()` | `render(canvas)` (직접 캔버스에 그림) |
| `dispose()` | `onRemove()` |
| (없음) | `update(dt)` ⭐ 매 프레임 호출 |
| (없음) | `onMount()` (World에 추가될 때) |

#### 3.4.1 Component 라이프사이클 정확한 호출 순서

Flutter의 `initState → didChangeDependencies → build → dispose` 흐름과 달리, Flame Component는 **트리에 붙는 시점**과 **떼어지는 시점**을 더 세분합니다. `add(component)`를 호출하면 다음 순서로 진행됩니다(공식 [Component lifecycle](https://docs.flame-engine.org/latest/flame/components.html) 기준):

```
add()  →  onLoad()  →  onGameResize()  →  onMount()  →  (매 프레임) update(dt) / render(canvas)  →  onRemove()
            ↑ 1회                          ↑ 1회                                                     ↑ removeFromParent() 시
```

- **`onLoad()`** — 컴포넌트 *인스턴스당 단 한 번*만 호출됩니다. `async`로 선언해 스프라이트·아틀라스·오디오 같은 **에셋을 await로 로딩**하는 곳입니다. 같은 인스턴스를 제거했다가 다시 add해도 `onLoad`는 재호출되지 않습니다(이미 로딩됨).
- **`onMount()`** — 부모 트리에 실제로 붙을 때 호출됩니다. `add` → `remove` → `add`를 반복하면 `onMount`/`onRemove`도 매번 반복 호출됩니다. **다른 컴포넌트(부모/형제)나 `game`/`world`를 참조하는 초기화**는 `onLoad`가 아니라 `onMount`에 두는 편이 안전합니다(이 시점엔 트리 연결이 완료되어 있음).
- **`onGameResize(Vector2 size)`** — 처음 마운트될 때 한 번, 이후 화면 크기가 바뀔 때마다 호출됩니다. 화면 크기에 의존하는 배치는 `size / 2` 같은 식으로 여기서 다시 계산합니다.
- **`onRemove()`** — `removeFromParent()` 또는 부모 제거 시 호출. Flutter `dispose()`처럼 리스너 해제·타이머 정리에 씁니다.

> Flame 1.29.0부터 **"부모가 트리에서 제거되어도 자식은 부모를 유지한다"**(BREAKING, #3602)로 동작이 바뀌었습니다. 즉 부모를 떼었다 다시 붙이면 자식 트리가 보존됩니다. 이 변경 때문에 `flame_jenny` 등 오래된 의존 패키지가 깨지기도 했습니다.

#### 3.4.2 `await component.loaded` / `mounted` — "준비될 때까지 기다리기"

Flutter에서 `Future`를 `await`하던 감각을 Flame에서도 쓸 수 있는 지점이 바로 컴포넌트 라이프사이클의 `Future` 핸들입니다. 모든 `Component`는 다음 `Future`(정확히는 `FutureOr`)를 노출합니다:

```dart
final boss = Boss();
await world.add(boss);     // add 자체는 Future를 반환 — onLoad 완료까지 대기 가능
await boss.loaded;         // onLoad 완료 시점까지 대기
await boss.mounted;        // 트리에 실제 마운트된 시점까지 대기

// 예: 보스 등장 연출 — 스프라이트 로딩이 끝난 뒤에 카메라를 붙이고 싶을 때
Future<void> spawnBoss() async {
  final boss = Boss();
  await world.add(boss);   // onLoad(스프라이트 await 포함)까지 끝난 뒤 진행
  camera.follow(boss);     // 이제 boss.position 등이 안전하게 준비됨
}
```

`add(...)`가 반환하는 `Future`를 그대로 `await`하면 됩니다. **이 await는 게임 루프(`update`) 밖, 즉 `onLoad`/이벤트 콜백/초기화 코드에서만** 쓰세요(아래 §5.4 원칙과 동일). `update(dt)` 안에서 `await`하면 안 됩니다.

---

## 4. Hello Flame — 최소 작동 예제

`lib/main.dart`:

```dart
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(GameWidget(game: HelloGame()));
}

class HelloGame extends FlameGame with KeyboardEvents {
  late Player player;

  @override
  Future<void> onLoad() async {
    player = Player()..position = size / 2;
    add(player);
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keys) {
    player.input(keys);
    return KeyEventResult.handled;
  }
}

class Player extends PositionComponent {
  static const speed = 200.0;
  Vector2 velocity = Vector2.zero();

  Player() : super(size: Vector2.all(40), anchor: Anchor.center);

  void input(Set<LogicalKeyboardKey> keys) {
    velocity = Vector2.zero();
    if (keys.contains(LogicalKeyboardKey.keyW)) velocity.y -= 1;
    if (keys.contains(LogicalKeyboardKey.keyS)) velocity.y += 1;
    if (keys.contains(LogicalKeyboardKey.keyA)) velocity.x -= 1;
    if (keys.contains(LogicalKeyboardKey.keyD)) velocity.x += 1;
    if (velocity.length > 0) velocity = velocity.normalized() * speed;
  }

  @override
  void update(double dt) {
    super.update(dt);
    position += velocity * dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = Colors.cyanAccent);
  }
}
```

**돌려보고 확인할 것**:
1. WASD로 사각형이 움직이는가
2. 대각선이 같은 속도로 움직이는가 (normalized 확인)
3. 창 크기를 바꿔도 화면 중앙에서 시작하는가

---

## 5. Dart 게임 코드 패턴 (일반 Flutter 앱에서 잘 안 쓰는 것들)

### 5.1 mixin 적극 활용
```dart
class Player extends PositionComponent
    with KeyboardHandler, HasGameReference<MyGame>, CollisionCallbacks { ... }
```
Flame은 **mixin으로 능력을 부여**하는 패턴이 많습니다. 일반 Flutter 앱 코드만 다뤘다면 낯설 수 있으나, OOP 다중 능력 합성으로 이해하면 자연스럽습니다.

> ⚠️ `HasGameRef`는 v1.28.0부터 deprecate. 신규 코드에서는 **`HasGameReference<MyGame>`** 을 쓰고, 게임 인스턴스 참조는 `game` getter로 접근합니다 (구버전의 `gameRef`도 동작은 하지만 새 코드에선 쓰지 마세요).

### 5.2 Vector2 산술
```dart
position += velocity * dt;             // 연산자 오버로딩
final dist = (a.position - b.position).length;
final dir = (target - position).normalized();
```

### 5.3 Component 트리 조작
```dart
add(child);              // 자식 추가
removeFromParent();      // 자기 자신 제거
parent?.add(sibling);    // 형제 추가
game.world.add(...);     // World에 직접 추가 (with HasGameReference<MyGame> 필요)
```

> ⚠️ `gameRef.world.add(...)` 는 v1.28.0부터 deprecate된 `HasGameRef`의 getter입니다. 신규 코드는 **`HasGameReference<MyGame>`** + **`game`** getter로 작성하세요.

### 5.4 입력 시스템 — Tap/Drag/Hover는 새 콜백 패턴 사용 (2026-05 권장)

본 코스에서 클릭 이동(Phase 3) 같은 입력을 도입할 때는 **반드시 새 콜백 mixin**을 쓰세요. 옛 `Tappable`/`Draggable`/`Hoverable` mixin은 이미 deprecated이며, 이벤트 객체 기반 `*Callbacks` API가 표준입니다. (이벤트 기반 API는 1.x 초·중반부터 도입·전환이 시작되었으므로 정확한 deprecate 버전을 단정하기보다 "구버전은 쓰지 않는다"로 기억하면 됩니다.)

| 옛 패턴(쓰지 마세요) | 신규 권장 |
|---|---|
| `with Tappable` / `HasTappables` / `HasTappableComponents` | **`with TapCallbacks`** + 게임은 별도 mixin 없이 자동 라우팅 |
| `with Draggable` / `HasDraggables` / `HasDraggableComponents` | **`with DragCallbacks`** |
| `with Hoverable` / `HasHoverables` | **`with HoverCallbacks`** |
| `MyGame with TapDetector` (전역) | 컴포넌트 레벨 `TapCallbacks` 권장. 전역 처리가 필요하면 게임 자체에 `TapCallbacks` 부여 |

콜백 시그니처:
```dart
class ClickableNpc extends PositionComponent with TapCallbacks {
  @override
  void onTapDown(TapDownEvent event) {
    // event.localPosition, event.canvasPosition 사용
    // event.continuePropagation = true; 로 상위 컴포넌트에도 전달 가능
  }
  @override
  void onTapUp(TapUpEvent event) { /* ... */ }
}
```

**키보드**는 위 포인터 이벤트와 별개 축입니다. **게임 전역**으로 받으려면 `FlameGame`에 `with KeyboardEvents`를 붙이고 `onKeyEvent(KeyEvent, Set<LogicalKeyboardKey>)`를 오버라이드합니다(§4 Hello Flame 예제가 이 방식). 특정 **컴포넌트가 직접** 키를 받게 하려면 컴포넌트에 `with KeyboardHandler`를 붙입니다. 단발 동작(점프 등)은 `KeyEvent`의 `KeyDownEvent`/`KeyUpEvent`로, 지속 이동(WASD)은 `update(dt)`에서 현재 눌린 키 집합을 폴링하는 방식이 자연스럽습니다.

- 출처: https://docs.flame-engine.org/latest/flame/inputs/tap_events.html · https://docs.flame-engine.org/latest/flame/inputs/drag_events.html · https://github.com/flame-engine/flame/issues/1733

### 5.5 절대 async/await 게임 루프에서 쓰지 말 것
```dart
// 잘못된 예
@override
void update(double dt) async {       // ❌ 매 프레임 Future 생성, GC 폭발
  await something();
  position.x += 1;
}
```

게임 루프는 **동기 + 상태 머신**으로 처리합니다. async는 onLoad, 네트워크 콜백, 파일 I/O 에만. (앞 §3.4.2의 `await component.loaded`/`mounted`/`add(...)`도 모두 **루프 밖**에서만 await하는 예입니다.)

멀티플레이에서 Server Authority + Prediction/Reconciliation을 쓰더라도 이 원칙은 유지됩니다. 클라는 조작감을 위해 `dt` 기반으로 예측 이동을 하고, 서버는 자기 fixed tick/dt로 최종 위치를 판정한 뒤 클라가 그 결과에 맞춰 보정합니다.

### 5.6 FlameGame 생성자 패턴 — World + CameraComponent 구성

본 코스의 §4 Hello Flame은 가장 단순한 형태(`add(player)`를 게임 루트에 바로 붙임)였습니다. 하지만 **Phase 2 이후의 모든 예제**(카메라 follow, World 기반 충돌, 줌)는 **`CameraComponent` + `World`** 구조를 전제로 합니다. 미리 이 생성자 패턴을 익혀 두세요.

`FlameGame`은 기본으로 `world`와 `camera` 두 컴포넌트를 갖습니다. 게임 콘텐츠(플레이어·적·타일맵)는 게임 루트가 아니라 **`world`에** 붙이고, 화면에 무엇을 어떻게 비출지는 **`camera`가** 결정합니다.

```dart
// 방법 A) 생성자 인자로 직접 구성 — 고정 해상도 + World 지정
class MyGame extends FlameGame {
  MyGame()
      : super(
          world: GameWorld(),                                  // 콘텐츠 루트
          camera: CameraComponent.withFixedResolution(         // 논리 해상도 고정(레터박스)
            width: 1280,
            height: 720,
          ),
        );
}

// 방법 B) onLoad에서 콘텐츠를 world에 추가하고 카메라를 붙임
class MyGame extends FlameGame {
  late final Player player;

  @override
  Future<void> onLoad() async {
    player = Player()..position = Vector2.zero();
    world.add(player);          // 게임 루트(add)가 아니라 world.add 에 주의
    camera.follow(player);      // 카메라가 플레이어를 따라감
    camera.viewfinder.zoom = 2; // 줌은 viewfinder에서 (angle/zoom은 flame 1.x 표준 API)
  }
}
```

- **`World`** 는 콘텐츠의 좌표 원점이자 컨테이너입니다. `HasCollisionDetection`을 붙일 때도 `FlameGame`이 아니라 **이 `World`(또는 커스텀 World 서브클래스)에 부여**하는 것이 최신 권장 패턴입니다(정적 오브젝트가 많으면 `HasQuadTreeCollisionDetection`).
- **`CameraComponent`** 는 `viewport`(화면상 영역)와 `viewfinder`(월드를 어떻게 비출지: `position`/`zoom`/`angle`)로 나뉩니다. `withFixedResolution(...)`은 다양한 화면 크기에 대해 논리 해상도를 고정하고 레터박스를 자동 처리합니다.
- 컴포넌트에서 `game`/`world`에 접근하려면 `with HasGameReference<MyGame>`(또는 `HasWorldReference`)을 부여하고 `game.world.add(...)` 형태로 씁니다(§5.3 참고, 구버전 `gameRef`/`HasGameRef`는 쓰지 않음).

> 정리: **"콘텐츠는 world, 시점은 camera"**. Flutter에서 `Stack` 안에 위젯을 쌓고 `SingleChildScrollView`로 보던 것을, Flame은 `world`에 컴포넌트를 쌓고 `camera`로 들여다보는 구조로 바꿔 생각하면 됩니다.

---

## 6. 시니어가 빠지기 쉬운 함정

1. **"비주얼 에디터로 화면 짜듯 게임도 만들 수 있겠지"** — 없습니다. 100% 코드. Tiled(맵 에디터)와 Aseprite(스프라이트 에디터)는 별도 툴이며 코드와 연결해서 사용합니다.
2. **"hot reload 되겠지"** — 됩니다. 단, Component 트리 구조 변경은 reload로 반영되지 않습니다. 게임 상태 변경 시 hot restart가 필요할 때가 많습니다.
3. **"Provider/Riverpod으로 게임 상태 다 관리"** — 위 3.3 참조. 매 프레임 변경되는 값은 Provider 금지.
4. **"앱에서 REST API 호출하던 것처럼 게임 네트워크도 쉽게"** — 게임 네트워크는 패러다임이 다릅니다. Phase 5까지 절대 손대지 마세요.

---

## 7. Prereq 산출물 체크리스트

- [ ] Flame 1.x(1.37.0) 설치 및 `flutter run` 성공
- [ ] Hello Flame WASD 이동 동작
- [ ] `update(dt)` 와 `render(canvas)` 의 호출 시점·역할 차이 설명 가능 (계산 단계 vs 그리기 단계)
- [ ] `dt`의 의미와 곱해야 하는 이유 설명 가능
- [ ] PositionComponent vs Flutter Widget 차이 한 문장으로 설명 가능
- [ ] 게임 루프에서 setState/async를 피해야 하는 이유 설명 가능
- [ ] `onLoad`(인스턴스당 1회) vs `onMount`(붙을 때마다)의 차이 설명 가능
- [ ] `await world.add(c)` / `await c.loaded` / `c.mounted` 가 무엇을 기다리는지 설명 가능
- [ ] "콘텐츠는 `world`, 시점은 `camera`" — World + CameraComponent 구조 이해
- [ ] `HasGameReference`(신규) vs `HasGameRef`(deprecated, 1.28.0~) 구분

---

## 8. 학습 후 메모 (직접 작성)

> Phase가 끝난 후 여기에 직접 작성하세요.

- 일반 Flutter 위젯 작업과 가장 달랐던 점:
- 의외였던 부분:
- 다음 Phase로 넘어가기 전 더 봐야 할 자료:

---

## 9. 다음 단계

[01-phase1-flame-basics.md](./01-phase1-flame-basics.md) — Flame의 Component/World/Camera 구조를 체계적으로 학습합니다.
