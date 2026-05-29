# Flame 치트시트 (Cheat Sheet)

Flutter·웹앱 개발에 능숙한 개발자가 Flame을 처음 다룰 때 빠르게 참고·암기하기 위한
요약 모음입니다. 이미 아는 것(Dart·위젯·상태관리 일반론)은 생략하고, **Flame이라서
헷갈리는 지점**만 콕 집어 정리하며, 가능한 곳에는 웹/Flutter 비유를 덧붙입니다.
개념의 깊은 설명은 각 Phase 문서로 링크합니다.

---

## 1. 왜 별도 Prereq가 필요한가

Flutter 위젯 기반의 일반 앱·웹 개발 경험은 풍부하지만 Flame은 처음인 개발자가
가장 흔히 하는 오해는 다음과 같습니다.

| 잘못된 직관 | 실제 |
|---|---|
| "Widget 트리에 `GameWidget` 하나 넣으면 끝" | 맞지만, Widget은 정지 상태에서 단발성 렌더링이고, Flame은 **매 프레임 `update` + `render`** |
| "`setState`로 캐릭터 위치 갱신" | Flame Component의 `position`은 **직접 변경**, `setState` 불필요 |
| "Provider/Riverpod으로 게임 상태 관리" | 게임 내부 상태는 **Component가 직접 보유**. Riverpod은 메뉴·HUD·메타 데이터에만 |
| "Future로 비동기 처리" | 게임 로직은 **동기 + `dt` 기반**. `async`는 네트워크·로딩에만 |
| "`build()`에서 위젯 트리 다시 만들면 됨" | Flame은 `build()`가 **없음**. `update(dt)` 안에서 변경, `render(canvas)`는 자동 |
| "60fps는 알아서 되겠지" | 매 프레임 객체 생성, 큰 Widget rebuild → **즉시 프레임 드랍** |

**핵심 사고 전환:**

```text
Flutter:  사용자 입력 → setState → 위젯 트리 rebuild → 렌더
Flame:    매 16.6ms마다 update(dt) → 좌표 변경 → render(canvas) (자동)
```

> 더 자세한 패러다임 전환 설명은 [00-prereq-flutter-to-flame.md](00-prereq-flutter-to-flame.md)를,
> Component/World/Camera 기초는 [01-phase1-flame-basics.md](01-phase1-flame-basics.md)를 참고하세요.

---

## 3. Flutter 위젯과의 결정적 차이 4가지

Flutter 위젯과 Flame Component는 표면적으로 비슷해 보이지만, **그리는 방식·좌표계·
상태관리·라이프사이클** 네 가지가 근본적으로 다릅니다. 이 절을 이해하면 "왜 내
캐릭터가 안 움직이지?", "왜 매 프레임 rebuild가 일어나지?" 같은 문제의 90%가
해결됩니다.

### 3.1 `build()`가 없다 — 매 프레임 `update(dt)`

Flutter는 상태가 바뀔 때 `build()`로 위젯 트리를 다시 만듭니다. Flame은 `build()`가
아예 없고, **매 프레임 `update(dt)`에서 좌표·상태를 직접 바꾼 뒤 자동으로 그려집니다.**

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

> **`dt`(delta time)의 의미**: 이전 프레임으로부터 경과한 **초**. 60fps라면 약
> `0.0166`. 모든 이동·애니메이션 시간은 **`dt`를 곱해야** 프레임 레이트와 무관하게
> 일정 속도가 됩니다. (`dt`를 빼먹으면 120Hz 모니터에서 캐릭터가 2배 빨라집니다.)

#### 게임 루프 vs 위젯 빌드 — 무엇이 언제 호출되는가

Flutter의 빌드 모델과 Flame의 게임 루프는 **"누가 다시 그리라고 시키는가"** 가
근본적으로 다릅니다.

| 항목 | Flutter Widget | Flame 게임 루프 |
|---|---|---|
| 다시 그리는 트리거 | `setState`/Provider notify 등 상태 변경 이벤트 **(pull)** | 매 vsync(프레임) 자동 **(push)** |
| 한 사이클 단계 | `build()` **한 단계**(선언적 트리 재생성) | `update(dt)` → `render(canvas)` **두 단계 분리** |
| 호출 빈도 | 변경이 없으면 **0회** | 변경이 없어도 **초당 ~60회** |
| 비용 모델 | rebuild diff(Element 트리 재조정) | 매 프레임 좌표 계산 + 캔버스 드로우 |
| 멈추는 법 | 그냥 `setState`를 안 부르면 됨 | `pauseEngine()` / 컴포넌트 제거 **필요** |

Flame의 한 프레임은 **두 단계로 명확히 나뉩니다.** 이 분리가 Flutter와 가장 다른
점입니다.

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

**반드시 지켜야 할 4가지:**

- ⚠️ **`update`에서 그리지 말고, `render`에서 상태를 바꾸지 마세요.** 이 둘을 섞으면 프레임 타이밍 버그가 생깁니다.
- 🔁 **`update`/`render`는 모두 부모 → 자식으로 트리를 따라 재귀**됩니다. 그래서 직접 `super.update(dt)` / `super.render(canvas)`를 호출하지 않으면 **자식들이 멈춥니다.**
- ⏸️ **루프 제어 API**: `pauseEngine()` / `resumeEngine()`(엔진 전체 정지), 컴포넌트의 `paused` 플래그, `timeScale`(슬로우/패스트 모션) 등으로 흐름을 조절합니다. Flutter처럼 "안 부르면 멈춤"이 아니라 **명시적으로 멈춰야** 합니다.
- ⏱️ **고정 timestep(fixed update)**: 물리/네트워크 동기화처럼 `dt` 변동에 민감한 로직은 가변 `dt` 대신 **일정 간격**으로 처리해야 합니다. Flame은 `FixedUpdateComponent`(또는 직접 누산기 패턴)로 `fixedUpdate`를 구현할 수 있고, 멀티플레이의 서버 tick(§5.4 참고)도 이 고정 간격 원리를 따릅니다.

### 3.2 좌표계가 다르다

| | Flutter | Flame |
|---|---|---|
| 원점 | 부모 위젯의 left-top | World(또는 부모 Component)의 left-top |
| 단위 | logical pixel | 동일 (logical pixel) — 단, 카메라 줌에 따라 변환 |
| Y축 | 아래로 + | 아래로 + (동일) |

차이는 **카메라**입니다. Flame은 **World 좌표 위에 Camera가 따로 있고**, 카메라가
보는 영역만 화면에 그려집니다. 일반 Flutter의 `SingleChildScrollView` /
`InteractiveViewer`와 개념은 비슷하지만, **줌/회전/follow가 GPU 변환으로** 처리됩니다.

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

> **Riverpod이 필요한 시점**: 게임 **외부** UI(메인 메뉴, 인벤토리 창의 Flutter
> Widget 부분, 설정 화면). 게임 **내부** 엔티티의 `hp`/`position`/`state`는 Riverpod에
> 넣지 **마세요.** 매 프레임 변경되는 값을 Provider에 넣으면 위젯 트리가 매 프레임
> rebuild됩니다 → **즉사.**

### 3.4 라이프사이클

| Flutter Widget | Flame Component |
|---|---|
| `initState()` | `onLoad()` (async 가능, 에셋 로딩) |
| `build()` | `render(canvas)` (직접 캔버스에 그림) |
| `dispose()` | `onRemove()` |
| (없음) | `update(dt)` ⭐ 매 프레임 호출 |
| (없음) | `onMount()` (World에 추가될 때) |

#### 3.4.1 Component 라이프사이클 정확한 호출 순서

Flutter의 `initState` → `didChangeDependencies` → `build` → `dispose` 흐름과 달리,
Flame Component는 **트리에 붙는 시점과 떼어지는 시점을 더 세분**합니다.
`add(component)`를 호출하면 다음 순서로 진행됩니다(공식 Component lifecycle 기준).

```text
add()  →  onLoad()  →  onGameResize()  →  onMount()  →  (매 프레임) update(dt) / render(canvas)  →  onRemove()
            ↑ 1회                          ↑ 1회                                                     ↑ removeFromParent() 시
```

- **`onLoad()`** — 컴포넌트 인스턴스당 **단 한 번만** 호출됩니다. `async`로 선언해 스프라이트·아틀라스·오디오 같은 에셋을 `await`로 로딩하는 곳입니다. 같은 인스턴스를 제거했다가 다시 `add`해도 `onLoad`는 **재호출되지 않습니다**(이미 로딩됨).
- **`onMount()`** — 부모 트리에 **실제로 붙을 때** 호출됩니다. `add → remove → add`를 반복하면 `onMount`/`onRemove`도 **매번 반복** 호출됩니다. 다른 컴포넌트(부모/형제)나 `game`/`world`를 참조하는 초기화는 `onLoad`가 아니라 **`onMount`에 두는 편이 안전**합니다(이 시점엔 트리 연결이 완료되어 있음).
- **`onGameResize(Vector2 size)`** — 처음 마운트될 때 한 번, 이후 **화면 크기가 바뀔 때마다** 호출됩니다. 화면 크기에 의존하는 배치는 `size / 2` 같은 식으로 여기서 다시 계산합니다.
- **`onRemove()`** — `removeFromParent()` 또는 부모 제거 시 호출. Flutter `dispose()`처럼 리스너 해제·타이머 정리에 씁니다.

> **flame 1.29.0 동작 변경**: 이 버전부터 **"부모가 트리에서 제거되어도 자식은 부모를
> 유지한다"**(BREAKING, [#3602](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md))로
> 동작이 바뀌었습니다. 즉 부모를 떼었다 다시 붙이면 자식 트리가 보존됩니다. 이 변경
> 때문에 `flame_jenny` 등 오래된 의존 패키지가 깨지기도 했습니다.

#### 3.4.2 라이프사이클 메서드 vs 라이프사이클 Future

시니어에게 가장 헷갈리는 지점입니다. Flame Component는 **오버라이드용 콜백 메서드**와
**`await`용 Future** 두 가지를 따로 제공합니다. 같은 생명주기 사건을 두 방향에서 본
것입니다.

- **메서드** = *"내 차례가 오면 (Flame이) 나를 호출해 줘"* — 내가 **반응**하는 쪽(override).
- **Future** = *"다른 컴포넌트가 그 시점을 기다리는 핸들"* — 남이 **기다리는** 쪽(await).

| 콜백 메서드 (override) | 대응 Future (await) | 의미 |
|---|---|---|
| `onLoad()` (async, 1회) | `loaded` | 에셋 로딩 완료 |
| `onMount()` (트리 부착) | `mounted` | 부모 트리에 실제로 붙음 |
| `onRemove()` (트리 분리) | `removed` | 트리에서 제거됨 |
| `onGameResize(size)` | — | 게임 캔버스 크기 변경 |

**핵심 차이:**

- **`onLoad`** 는 트리에 추가되기 **전 1회**만 실행됩니다(무거운 에셋 로딩 자리). 같은 인스턴스를 `remove` 후 다시 `add`해도 **재실행되지 않습니다**.
- **`onMount`/`onRemove`** 는 트리에 붙고 떨어질 때마다 **매번** 실행됩니다(리스너 등록/해제 자리).
- **1.29.0부터** 부모가 트리에서 제거돼도 자식은 부모와의 관계를 유지합니다(§3.4.1 참고). 부모를 다시 `add`하면 자식도 함께 복귀합니다 — 예전처럼 자식이 detach되어 사라지지 않습니다.

```dart
// add()는 동기처럼 보이지만 onLoad/onMount는 다음 프레임 경계에서 처리됨.
// "추가가 끝난 뒤"를 기다리려면 Future를 await 한다.
final enemy = Enemy();
world.add(enemy);
await enemy.mounted;          // 이제 트리에 확실히 붙음 — 자식 추가/쿼리 안전
await enemy.loaded;           // onLoad(에셋 로딩)까지 완료를 보장하고 싶을 때

// add 자체를 기다리는 헬퍼도 있다 (mounted까지 await):
await world.add(enemy);       // FutureOr 반환 — 그대로 await 가능
```

> ⚠️ **`onLoad()` 안에서 `add(child)`를 호출하면 자식은 부모가 mount된 뒤에
> 처리됩니다.** "add 직후 `size`/`position`이 0"으로 보이는 버그는 대부분 `mounted`를
> 기다리지 않고 즉시 접근해서 생깁니다.

**실전 예 — 보스 스프라이트 로딩이 끝난 뒤 카메라를 붙이고 싶을 때:**

```dart
Future<void> spawnBoss() async {
  final boss = Boss();
  await world.add(boss);   // onLoad(스프라이트 await 포함)까지 끝난 뒤 진행
  camera.follow(boss);     // 이제 boss.position 등이 안전하게 준비됨
}
```

이 `await`는 **게임 루프(`update`) 밖**, 즉 `onLoad`/이벤트 콜백/초기화 코드에서만
쓰세요(§5.4 원칙과 동일). **`update(dt)` 안에서 `await`하면 안 됩니다.**

---

## 5. 자주 쓰는 API·패턴 빠른 참조

> 이 절은 **2026-05 기준 신규 권장 패턴만** 담습니다. deprecated된 옛 API는 의도적으로
> 싣지 않았으니, 여기 있는 형태 그대로 쓰면 최신 버전(flame 1.37.0)에서 안전합니다.

### 5.1 핵심 클래스

Flame에서 가장 자주 만나는 기본 클래스들입니다. 대부분은 **`Component`를 정점으로
하는 상속 트리**라서, 계층을 먼저 잡으면 "어떤 클래스에 `position`이 있고 없는지"가
명확해집니다.

| 클래스 | 역할 |
|---|---|
| `FlameGame` | 게임 루트, 라이프사이클 보유 |
| `Component` | 모든 게임 오브젝트의 베이스 (**위치 없음**) |
| `PositionComponent` | `position`, `size`, `angle`, `anchor` 보유 |
| `SpriteComponent` | 정적 이미지 |
| `SpriteAnimationComponent` | 스프라이트 시트 애니메이션 |
| `World` | 월드 컨테이너 (1.x에서 분리됨) |
| `CameraComponent` | 카메라, `follow`/`zoom`/`bounds` |
| `RectangleComponent`, `CircleComponent` | 도형 (디버깅·placeholder용) |

**상속 계층 — 누가 `position`을 갖는가:**

```text
Component                     ← 베이스. 위치 개념이 없음(로직 전용·컨테이너로도 씀)
├── PositionComponent         ← position/size/angle/anchor 추가 (화면에 놓이는 것의 부모)
│   ├── SpriteComponent       ← 정적 이미지 1장
│   ├── SpriteAnimationComponent  ← 스프라이트 시트 애니메이션
│   └── RectangleComponent / CircleComponent  ← 도형(placeholder·디버깅)
├── World                     ← 콘텐츠 컨테이너 (1.x에서 별도 컴포넌트로 분리)
└── CameraComponent           ← World를 비추는 시점(follow/zoom/bounds)
```

- **`Component`에 위치가 없다**는 점이 핵심입니다. 좌표가 필요한 화면 오브젝트는 거의 항상 **`PositionComponent` 이하**를 상속합니다. `Component` 자체는 순수 로직이나 다른 컴포넌트를 담는 컨테이너로 씁니다.
- **`World`와 `CameraComponent`는 형제 관계**입니다 — "콘텐츠는 `World`, 시점은 `CameraComponent`"(§5.5). 1.x에서 카메라/월드가 별도 컴포넌트로 분리되면서 이 구조가 표준이 되었습니다.
- **도형 컴포넌트**(`RectangleComponent` 등)는 이미지를 준비하기 전 **placeholder**나 hitbox 시각화 같은 **디버깅 용도**로 매우 유용합니다.

### 5.2 Vector2 산술

```dart
position += velocity * dt;                       // 연산자 오버로딩
final dist = (a.position - b.position).length;   // 두 점 사이 거리
final dir = (target - position).normalized();    // 방향 단위 벡터(길이 1)
```

### 5.3 Component 트리 조작

```dart
add(child);              // 자식 추가
removeFromParent();      // 자기 자신 제거
parent?.add(sibling);    // 형제 추가
game.world.add(...);     // World에 직접 추가 (with HasGameReference<MyGame> 필요)
```

> 컴포넌트에서 `game`/`world`에 접근하려면 클래스에 `with HasGameReference<MyGame>`
> (또는 `HasWorldReference`)을 부여하면 `game` getter가 생깁니다. 이후
> `game.world.add(...)` 형태로 씁니다.

### 5.4 입력 시스템 — Tap/Drag/Hover는 콜백 mixin 사용

클릭 이동(Phase 3) 같은 입력을 도입할 때는 **이벤트 객체 기반 `*Callbacks` mixin**을
씁니다. **컴포넌트 레벨에 직접 부여**하는 것이 표준이며, 좌표 변환·라우팅을 Flame이
자동 처리합니다.

| 용도 | 신규 권장 mixin |
|---|---|
| 탭/클릭 | 컴포넌트에 `with TapCallbacks` |
| 드래그 | 컴포넌트에 `with DragCallbacks` |
| 호버 | 컴포넌트에 `with HoverCallbacks` |
| 전역 탭 처리가 필요할 때 | **게임 자체**에 `with TapCallbacks` 부여 (별도 전역 디텍터 불필요) |

**콜백 시그니처:**

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

**키보드는 위 포인터 이벤트와 별개 축입니다.**

- **게임 전역**으로 받으려면 `FlameGame`에 `with KeyboardEvents`를 붙이고 `onKeyEvent(KeyEvent, Set<LogicalKeyboardKey>)`를 오버라이드합니다(§4 Hello Flame 예제가 이 방식).
- **특정 컴포넌트**가 직접 키를 받게 하려면 컴포넌트에 `with KeyboardHandler`를 붙입니다.
- **단발 동작**(점프 등)은 `KeyDownEvent`/`KeyUpEvent`로, **지속 이동**(WASD)은 `update(dt)`에서 현재 눌린 키 집합을 **폴링**하는 방식이 자연스럽습니다.

### 5.5 FlameGame 생성자 패턴 — World + CameraComponent 구성

§4 Hello Flame은 가장 단순한 형태(`add(player)`를 게임 루트에 바로 붙임)였습니다.
하지만 Phase 2 이후의 모든 예제(카메라 follow, World 기반 충돌, 줌)는
**`CameraComponent` + `World` 구조**를 전제로 합니다. 미리 이 생성자 패턴을 익혀
두세요.

`FlameGame`은 기본으로 **`world`와 `camera` 두 컴포넌트**를 갖습니다. 게임 콘텐츠
(플레이어·적·타일맵)는 게임 루트가 아니라 **`world`에 붙이고**, 화면에 무엇을 어떻게
비출지는 **`camera`가 결정**합니다.

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

- **`World`** 는 콘텐츠의 좌표 원점이자 컨테이너입니다. `HasCollisionDetection`을 붙일 때도 `FlameGame`이 아니라 이 `World`(또는 커스텀 World 서브클래스)에 부여하는 것이 권장 패턴입니다(정적 오브젝트가 많으면 `HasQuadTreeCollisionDetection`).
- **`CameraComponent`** 는 `viewport`(화면상 영역)와 `viewfinder`(월드를 어떻게 비출지: `position`/`zoom`/`angle`)로 나뉩니다. `withFixedResolution(...)`은 다양한 화면 크기에 대해 논리 해상도를 고정하고 **레터박스를 자동 처리**합니다.
- 컴포넌트에서 `game`/`world`에 접근하려면 `with HasGameReference<MyGame>`(또는 `HasWorldReference`)을 부여하고 `game.world.add(...)` 형태로 씁니다(§5.3 참고).

> **한 줄 정리: "콘텐츠는 `world`, 시점은 `camera`".** Flutter에서 `Stack` 안에 위젯을
> 쌓고 `SingleChildScrollView`로 보던 것을, Flame은 **`world`에 컴포넌트를 쌓고
> `camera`로 들여다보는 구조**로 바꿔 생각하면 됩니다.

### 5.6 World 제대로 이해하기 — 자주 헷갈리는 4가지

`world`는 §5.5에서 "콘텐츠를 담는 곳"으로 소개했지만, 막상 쓰다 보면 "이게 맵인가?
하나뿐인가? 내가 만드나?" 같은 의문이 생깁니다. 실제로 가장 많이 묻는 4가지를
공식 문서(`docs.flame-engine.org/latest/flame/camera.html`) 기준으로 정리합니다.

| 질문 | 짧은 답 |
|---|---|
| ① `world.add()`는 기물·PC·몬스터를 넣는 것? | **그렇다.** 게임 안 모든 오브젝트를 World의 자식으로 등록 |
| ② 게임 맵 = `world`인가? | World는 맵을 **담는 그릇**(상위 컨테이너). 맵 그림 자체는 아님 |
| ③ `world`는 하나뿐인가? | 기본 1개 자동 제공. **여러 개 만들 수 있음** |
| ④ 직접 만드나, Flame이 주나? | **둘 다.** 기본은 Flame이 주고, 보통은 상속해서 키움 |

#### ① `world.add(component)` — 게임 안 오브젝트를 World의 자식으로 등록

플레이어·몬스터·나무 같은 기물(`PositionComponent`/`SpriteComponent` 등)을 넣는 게
정확히 맞습니다. World에 들어간 객체는 **"월드 좌표계"** 에 배치되어 카메라가 비춰
줍니다.

> ⚠️ **`add()`는 World 전용이 아닙니다.** 모든 `Component`가 가진 표준 메서드이고,
> "어디에 add 하느냐"가 의미를 가릅니다. HUD·버튼처럼 **화면에 고정**되어야 하는 UI는
> `world`가 아니라 **카메라의 `viewport.add(...)`** 나 게임 루트에 붙입니다(world에
> 붙이면 카메라가 움직일 때 같이 흘러가 버림).

#### ② 게임 맵 = `world`? — World는 맵을 "담는 그릇"이다

엄밀히는 **World ≠ 맵 그래픽**입니다. 타일맵·지형·배경은 World에 `add`되는 **콘텐츠
중 하나**이고, World는 그 맵과 그 위의 모든 오브젝트를 통째로 담는 **좌표 공간**입니다.

- 다만 실무에선 "**1 World = 1 맵/스테이지**"로 1:1 대응시켜 쓰는 일이 많아, 느슨하게는
  "world가 곧 맵"처럼 다뤄집니다(이 문서 다른 곳·`01-phase1`의 "world가 곧 맵"도 그 뜻).
- **중요**: World는 `PositionComponent`가 아니라 **`Component`를 직접 상속**합니다. 그래서
  **자체적인 `size`·`position`·경계가 없습니다.** "맵의 크기/이동 한계"는 World가 아니라
  **`camera.setBounds(...)`** 로 카메라 쪽에서 줍니다(§5.7).
- World는 **스스로 그려지지 않고** 카메라가 들여다봐야만 화면에 나옵니다.

> 웹/서버 비유: `world`는 **도메인 모델(데이터가 사는 공간)**, 화면 고정 HUD는 그 위에
> 얹는 **오버레이 레이어**. 둘을 한 그릇에 섞지 않는 것과 같은 분리입니다.

#### ③ `world`는 하나뿐? — 기본 1개, 여러 개 가능

`FlameGame`은 생성 시 **기본 `world` 1개와 `camera` 1개를 자동으로 만들어 짝지어** 둡니다.
하지만 하나로 제한되지 않습니다. 공식 문서: *"A game can have multiple World instances
that can be rendered either at the same time, or at different times."*

- **동시에**: 분할 화면 — 여러 카메라가 각자의 World를 비춤.
- **번갈아**: 스테이지/씬 전환 — 카메라 타깃을 World A→B로 바꾸면 **언마운트 없이 즉시**
  화면이 전환됨.

> ⚠️ **`game.world` getter의 함정**: 이건 "지금 화면에 보이는 활성 world"가 아니라
> **FlameGame이 기본으로 들고 있는 단일 `_world` 필드**를 돌려줍니다. 카메라 타깃
> (`camera.world`)을 다른 World로 바꿔도 `game.world`는 그대로라, 둘이 **어긋날 수**
> 있습니다. 기본 world 자체를 갈아끼우려면 `world` setter를 쓰세요.

#### ④ 직접 만드나, Flame이 주나? — 둘 다

`World`는 **Flame 내장 클래스**(`package:flame/components.dart`)이고, `FlameGame`을
만들면 인스턴스가 **자동 생성**됩니다. 그래서 아무것도 안 해도 `world.add(...)`가 됩니다.
동시에 공식 문서는 **상속해서 키우라**고 권장합니다 — *"For many games you want to
extend the world and create your logic in there."*

```dart
// (A) Flame이 준 기본 world를 그냥 사용 — 가장 단순
world.add(Player());

// (B) World를 상속해 커스텀 (이 프로젝트의 lib/main.dart도 이 방식)
class MyWorld extends World with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    await add(Player());
    await add(Tree()..position = Vector2(1200, 800));  // 맵 콘텐츠를 여기에 모음
  }
}

class MyGame extends FlameGame<MyWorld> {           // 제네릭으로 커스텀 타입 지정
  MyGame() : super(world: MyWorld());               // ⚠️ 지정했으면 인스턴스를 반드시 전달
}                                                    //    (안 넘기면 런타임 assertion 에러)

// (C) 여러 World로 맵 전환 — 카메라 타깃만 교체
camera.world = dungeonWorld;   // 화면이 즉시 던전으로 전환됨
```

**카메라 ↔ World 관계** (고정 1:1이 아님):

| 방향 | 관계 | 쓰임 |
|---|---|---|
| World ← 카메라 | 한 World를 **여러 카메라**가 동시에 비출 수 있음 (N:1) | 미니맵, 분할 화면 |
| 카메라 → World | 한 카메라는 한 시점에 **0개 또는 1개** World를 비춤 (런타임 교체 가능) | 스테이지 전환 |

> **한 줄 정리**: `world`는 Flame이 1개 깔아 주지만 **여러 개 가질 수 있고**, 보통
> **상속해서 키운다**. 그리고 world는 "맵을 담는 그릇"이지 **맵 그림 자체가 아니다** —
> 크기·경계는 카메라(`setBounds`)가 맡는다. 더 깊은 내용은
> [01-phase1-flame-basics.md](01-phase1-flame-basics.md) §4.10,
> [game-glossary.md](game-glossary.md)의 World 항목 참고.

### 5.7 카메라 심화 — `world` 지정, `viewport` vs `viewfinder`, zoom

§5.5에서 카메라를 "시점"으로 다뤘다면, 여기서는 **카메라를 직접 만들고 줌을 줄 때**
헷갈리는 두 줄을 풀어 둡니다. (웹/Flutter 비유 포함 — 개인 암기용)

```dart
cam = CameraComponent(world: world);   // 이 카메라가 "비출 대상" World를 생성자에서 지정
cam.viewfinder.zoom = 1.0;             // zoom은 cam이 아니라 viewfinder에. 1.0 = 원본 배율
```

#### 헷갈리는 점 1 — 왜 카메라에 `world`를 넘기나

카메라는 그 자체로 무언가를 담지 않습니다. **특정 `World`를 "비추는 뷰"** 일 뿐이라,
생성자에서 "무엇을 비출지(`world`)"를 지정합니다.

- **관계**: `World` = model(콘텐츠), `CameraComponent` = view(시점). 둘은 분리돼 있음.
- 한 `World`를 **여러 카메라로** 비출 수 있음 → 미니맵, 분할 화면이 여기서 나옵니다.
- 콘텐츠는 `world.add(...)`, "어떻게 보여줄지"는 `cam`이 담당. (이 둘을 섞지 말 것.)

> 웹 비유: `world`는 거대한 캔버스/문서, `cam`은 그걸 들여다보는 **뷰포트 + 변환행렬**.

#### 헷갈리는 점 2 — 왜 `cam.zoom`이 아니라 `cam.viewfinder.zoom`인가

`CameraComponent`는 책임이 둘로 쪼개져 있습니다. zoom·이동·회전은 전부
**viewfinder** 소관입니다.

| 구성 요소 | 의미 | 다루는 것 |
|---|---|---|
| `viewport` | **화면상의** 사각 영역 (어디에 그릴지) | 미니맵 위치, 분할 화면, HUD 영역 |
| `viewfinder` | **월드를 들여다보는 렌즈** (어떻게 비출지) | `zoom`, `position`(pan), `angle`(회전) |

그래서 줌은 항상 `cam.viewfinder.zoom`, 카메라 이동은 `cam.viewfinder.position`입니다.

> 웹/Flutter 비유: `viewport` = 화면에서 보이는 컨테이너 `div`의 위치·크기,
> `viewfinder` = 그 안 콘텐츠에 건 **CSS `transform: scale()/translate()/rotate()`**.
> Flutter로 치면 `InteractiveViewer`의 변환 행렬이 `viewfinder`에 해당.

#### `zoom` 값 감각

| 값 | 효과 |
|---|---|
| `1.0` | 원본 배율 (1 월드 픽셀 = 1 논리 픽셀) |
| `2.0` | 2배 **확대** — 더 가까이, 더 적은 영역이 보임 |
| `0.5` | **축소** — 더 멀리, 더 넓은 영역이 보임 |

- 줌 인/아웃 토글이 아니라 **연속 스칼라**입니다. 마우스 휠 줌은 이 값을 `clamp(0.5, 3.0)` 식으로 가감.
- `follow(target)`로 추적을 걸면 `viewfinder.position`은 Flame이 매 프레임 갱신하므로 직접 건드릴 필요 없습니다.

### 5.8 스프라이트 애니메이션 — `SpriteAnimationComponent`

스프라이트 시트(한 장의 PNG에 여러 프레임이 격자로 들어간 이미지) 한 장을 받아
**자동으로 순환 재생**해 주는 컴포넌트입니다. 걷기·날갯짓처럼 "한 종류 동작이
계속 반복"되는 오브젝트에 씁니다.

```dart
class Walker extends SpriteAnimationComponent with HasGameReference {
  @override
  Future<void> onLoad() async {
    final image = await game.images.load('player_walk.png');
    animation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: 8,                     // 8프레임
        stepTime: 0.1,                 // 프레임당 0.1초
        textureSize: Vector2(32, 32),  // 각 프레임 크기
      ),
    );
    size = Vector2(64, 64);
  }
}
```

**한 줄씩 풀어 보기:**

- **`extends SpriteAnimationComponent`** — 애니메이션 **1개**를 들고 자동 재생하는 컴포넌트. (정지 이미지 1장이면 `SpriteComponent`, idle/walk처럼 **상태별로 여러 애니메이션**을 전환해야 하면 `SpriteAnimationGroupComponent`. §5.1 계층 참고.)
- **`with HasGameReference`** — 컴포넌트 안에서 `game` getter를 쓰기 위한 mixin(§5.3). 제네릭 없이 쓰면 `game`이 기본 `FlameGame` 타입이 됩니다. 커스텀 게임의 필드에 접근하려면 `HasGameReference<MyGame>`처럼 타입을 박으세요.
- **`onLoad() async`** — 컴포넌트가 트리에 붙기 전 **한 번** 실행되는 비동기 초기화(§3.4.1). 이미지 로딩처럼 `await`가 필요한 작업을 여기서 합니다.
- **`game.images.load('player_walk.png')`** — `pubspec.yaml`의 `assets:`에 등록된 PNG를 디코딩해 `Image`(GPU 텍스처 원본)로 반환. 내부적으로 캐시되므로 같은 파일을 여러 번 불러도 한 번만 디코딩됩니다.
- **`SpriteAnimation.fromFrameData(image, ...)`** — 위 이미지 한 장을 **격자로 잘라 여러 프레임의 애니메이션**으로 만드는 헬퍼.
- **`SpriteAnimationData.sequenced(...)`** — "가로로 순서대로 `amount`개 잘라낸다"는 가장 흔한 시트 형태를 기술합니다.
  - **`amount: 8`** — 시트에 든 프레임 개수(8칸).
  - **`stepTime: 0.1`** — 한 프레임을 보여 주는 시간(초). `0.1`이면 초당 10프레임. 값이 작을수록 빠른 동작.
  - **`textureSize: Vector2(32, 32)`** — 시트에서 **한 칸(프레임)의 픽셀 크기**. 실제 시트의 칸 크기와 **정확히 일치**해야 합니다.
- **`animation = ...`** — `SpriteAnimationComponent`의 필드에 대입하는 순간 **자동으로 재생이 시작**됩니다. `update`에서 따로 프레임을 넘길 필요가 없습니다(Flame이 `dt`로 진행).
- **`size = Vector2(64, 64)`** — **화면에 그릴 크기**. 시트 한 칸은 32×32지만 64×64로 두면 GPU에서 2배 확대되어 그려집니다(원본 해상도와 표시 크기는 별개).

**시트 구조 — `amount`/`textureSize`가 가리키는 것:**

```text
player_walk.png  (가로 256 × 세로 32, 8칸이 가로로 나열)
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ F0 │ F1 │ F2 │ F3 │ F4 │ F5 │ F6 │ F7 │   ← 세로 32
└────┴────┴────┴────┴────┴────┴────┴────┘
  └32┘
   ▲ textureSize = Vector2(32, 32)  (한 칸 크기)
     amount      = 8                 (칸 개수)
     stepTime    = 0.1               (한 칸을 보여 주는 시간)
```

> **흔한 함정**: `textureSize`가 시트의 실제 칸 크기와 다르면 캐릭터가 잘리거나 두
> 프레임이 겹쳐 보입니다. 가로 시트라면 `textureSize = (시트 가로 ÷ amount, 시트 세로)`가
> 정답입니다. 한 줄에 다 안 들어가는 **그리드 시트**(예: 4×2)는
> `SpriteAnimationData.sequenced(..., amountPerRow: 4)`로 처리하고, **공격·사망처럼
> 한 번만 재생**해야 하는 모션은 `loop: false`를 줍니다.

### 5.9 클릭-투-무브(click-to-move) — 탭으로 목적지까지 이동

화면을 한 번 탭하면 그 지점까지 캐릭터가 스스로 걸어가는 **디아블로·LoL·RTS식 이동**입니다.
핵심 사고 전환은 "**탭은 순간(1회), 이동은 지속(매 프레임)**"이라는 분리입니다. 탭 콜백은
목적지 좌표만 저장하고, 실제 이동은 게임 루프(`applyInput`)가 매 프레임 한 걸음씩 책임집니다.
(§5.4 입력 시스템·§5.5 World/Camera 구조를 먼저 보면 이해가 빠릅니다.)

#### 데이터 흐름 — 이벤트(저장) → 상태(보유) → 루프(실행)

이 셋을 명확히 분리하는 것이 "이벤트 기반"이 아니라 **상태 기반 게임 루프**의 본질입니다.

```text
탭 입력(1회)               상태(게임 진행 중 유지)       프레임 루프(매 ~16.6ms)
┌─────────────────┐        ┌────────────────────┐       ┌──────────────────────────┐
│ MyWorld         │        │ Player._target     │       │ Player.applyInput(keys,dt)│
│  .onTapDown     │ 저장→  │  (Vector2?)        │ 폴링→ │  키 없음 && _target!=null  │
│ event           │        │  null  = 이동 안 함 │       │   → 목적지로 한 걸음씩      │
│  .localPosition │        │  값    = 이 지점으로 │       │   → 도착하면 스냅 후 멈춤   │
└─────────────────┘        └────────────────────┘       └──────────────────────────┘
      ↑ 단발 콜백                 ↑ setTarget이 덮어씀            ↑ 매 프레임 호출
```

#### 핵심 코드 (현재 `lib/main.dart` 기준)

```dart
// ① 기본 world를 "탭 입력을 받는" MyWorld로 교체.
//    FlameGame 생성자의 world: 인자에 넘기면 부모의 world getter가 이 인스턴스를
//    가리켜, onLoad의 world.add(...)/camera.follow(...)가 그대로 동작합니다.
class MyGame extends FlameGame with KeyboardEvents {
  late final Player player;
  MyGame() : super(world: MyWorld());
  // ...
}

// ② World에 TapCallbacks를 붙여 탭을 받습니다. HasGameReference<MyGame>로
//    game.player에 접근해 탭 지점을 이동 목적지로 넘깁니다.
class MyWorld extends World with TapCallbacks, HasGameReference<MyGame> {
  @override
  void onTapDown(TapDownEvent event) {
    // event.localPosition : 이 World 좌표계 기준 = 곧 "월드 좌표".
    // 카메라 변환이 이미 끝나 있어, 그대로 목적지로 쓰면 됩니다.
    game.player.setTarget(event.localPosition);
  }
}

// ③ 플레이어는 목적지만 보관합니다(아직 이동하지 않음).
class Player extends SpriteAnimationGroupComponent with HasGameReference<MyGame> {
  // null = "탭 이동 중이 아님". 도착하거나 키보드로 직접 움직이면 다시 null로.
  Vector2? _target;

  void setTarget(Vector2 target) {
    _target = target; // 단순 대입 → 이동 중 재탭하면 목적지가 즉시 교체됩니다(아래 ⑦).
  }

  // ④ 매 프레임 호출. 키보드 처리는 §5.4와 동일하고, 여기서는 탭 부분만 발췌.
  void applyInput(Set<LogicalKeyboardKey> keys, double dt) {
    const double speed = 300;             // 1초당 이동 픽셀 수(키보드·탭 공용)
    final velocity = Vector2.zero();      // 방향 벡터는 매 프레임 0에서 다시 시작
    // ... (WASD/방향키를 velocity에 += / -= 로 누적: §5.4) ...

    // ── 키보드 vs 탭 우선순위 ──────────────────────────────────────────
    if (velocity.length > 0) {
      // 키가 하나라도 눌렸으면 "직접 조종"을 우선하고, 저장된 탭 목적지는 취소.
      _target = null;
    } else if (_target != null) {
      // 키 입력이 전혀 없을 때만 탭 목적지를 향해 한 걸음 다가갑니다.
      final toTarget = _target! - position; // 목적지까지의 방향·거리 벡터
      final step = speed * dt;              // 이번 프레임에 갈 수 있는 거리
      if (toTarget.length <= step) {
        // 한 프레임 안에 도착 가능 → 정확히 스냅하고 멈춤(아래 ⑤ 떨림 방지).
        position.setFrom(_target!);
        _target = null;
        current = PlayerState.idle;
        return;                            // 이번 프레임의 위치 갱신은 건너뜀
      }
      velocity.setFrom(toTarget);          // 아직 멀면, 목적지 방향을 이동 방향으로
    }

    // 키보드든 탭이든 결국 velocity가 0인지 아닌지로 상태를 정합니다.
    current = velocity.length > 0 ? PlayerState.running : PlayerState.idle;
    // 방향만 남기고(normalized) 속도·시간을 곱해 이동. dt 덕분에 FPS와 무관하게 일정.
    position += velocity.normalized() * speed * dt;
  }
}
```

> **`onTapDown`은 단발, `applyInput`은 폴링.** `onTapDown`에서 `position`을 직접
> 바꾸면 순간이동이 되어 걷는 애니메이션이 사라집니다. 좌표만 `_target`에 저장하고,
> 다가가는 일은 매 프레임 루프에 맡기는 것이 핵심입니다.

#### 헷갈리는 점 — 왜 `TapCallbacks`를 World에 붙이나

탭 좌표가 곧바로 **월드 좌표**로 들어오기 때문입니다. Flame은 이벤트를 받은 컴포넌트의
좌표계로 위치를 자동 변환해 주는데, `World`가 받으면 그 로컬 좌표 = 게임 월드 좌표입니다.
카메라가 `follow`로 따라다녀도(§5.5) 추가 변환이 필요 없습니다.

| 붙이는 곳 | `event.localPosition` | 카메라 변환 | 추천 |
|---|---|---|---|
| `World` | **월드 좌표(자동 변환 완료)** | 불필요 | ✅ |
| `FlameGame`/위젯 `GestureDetector` | 게임 위젯 로컬(≈화면 픽셀) | 직접 `camera.globalToLocal(...)` 필요 | ❌ |

```dart
// ❌ 게임/위젯에서 받으면 화면 좌표라 카메라를 수동 역변환해야 함
//    final worldPos = camera.globalToLocal(event.position);
//    player.setTarget(worldPos);

// ✅ World에서 받으면 event.localPosition이 이미 월드 좌표
game.player.setTarget(event.localPosition);
```

> 웹/Flutter 비유: Flutter `GestureDetector.onTapDown`은 상위 위젯 기준 좌표라 직접
> 변환이 필요하지만, Flame은 컴포넌트 단계에서 좌표계를 맞춰 줍니다. `world`라는
> "거대한 문서"를 `camera`라는 "뷰포트"로 들여다보는 구조(§5.7)라, World가 받은 탭은
> 문서 좌표로 도착하는 셈입니다.

#### 흔한 함정 (증상 → 원인 → 해결)

| 증상 | 원인 | 해결 |
|---|---|---|
| 탭하면 엉뚱한 곳으로 감(카메라가 따라다니면 더 심함) | 게임/위젯에서 화면 좌표를 그대로 목적지로 씀 | `World`에 `TapCallbacks`를 붙여 `event.localPosition`(월드 좌표) 사용 |
| 목적지 근처에서 좌우로 떪(oscillation) | 방향으로만 계속 밀어 목적지를 살짝 지나침 | 도착 판정 시 `position.setFrom(_target!)`로 정확히 스냅 + `return` |
| 키보드로 움직이는데 탭이 끼어듦(또는 그 반대) | 두 입력이 같은 `velocity`를 두고 충돌 | `if (velocity.length > 0) _target = null;` — 키 입력이 있으면 탭 취소 |
| 키를 뗐는데 캐릭터가 계속 흘러감 | `velocity`가 이전 프레임 값을 유지 | `final velocity = Vector2.zero();`로 매 프레임 초기화(§5.4) |
| 대각선이 직선보다 빠름 | `(1, -1)`처럼 길이 √2인 벡터를 그대로 사용 | `velocity.normalized()`로 길이를 1로 정규화 |

> ⚠️ 스냅 처리에서 `return`을 빼면, 같은 프레임에서 아래의 `position += ...`가 한 번
> 더 실행되어 목적지를 지나칩니다. "도착했으면 즉시 끝낸다"가 떨림 방지의 핵심입니다.

#### `localPosition` vs `canvasPosition`

`TapDownEvent`는 같은 탭을 여러 좌표계로 제공합니다. **현재 코드는 `localPosition`만
사용**합니다(목적지가 월드 좌표여야 하므로). 둘을 헷갈리면 카메라 줌/이동 시 어긋납니다.

| 속성 | 기준 좌표계 | 카메라 변환 | 클릭-투-무브 용도 |
|---|---|---|---|
| `event.localPosition` | 이벤트를 받은 컴포넌트의 로컬(World면 **월드 좌표**) | 반영됨 | ✅ 그대로 `_target`으로 사용 |
| `event.canvasPosition` | 게임 캔버스(viewport) 픽셀 | 반영 안 됨 | HUD 등 화면 고정 UI 판정용(이동 목적지로는 부적합) |

> 줌이 2배여도 `localPosition`은 월드 좌표라 그대로 쓰면 되고, `canvasPosition`은
> 화면 픽셀이라 별도 역변환이 필요합니다.

#### 확장 아이디어 (현재 코드와의 관계 표기)

| 기능 | 현재 코드 | 어디서 시작하나 |
|---|---|---|
| 이동 중 재탭으로 목적지 교체 | ✅ 이미 동작 | `setTarget`이 `_target`을 덮어쓰므로 별도 로직 불필요 |
| 탭 지점에 마커(이펙트) 표시 | ❌ 미구현 | `onTapDown`에서 그 위치에 임시 컴포넌트를 `world.add` 후 잠시 뒤 `removeFromParent` |
| 도착 시 콜백(`onArrive`) | ❌ 미구현 | `Player`에 `VoidCallback?` 필드 추가, 스냅 처리(`position.setFrom`) 직후 호출 |
| 드래그로 목적지 지정 | ❌ 미구현 | World에 `DragCallbacks`를 더해 `onDragEnd`의 `localPosition`을 목적지로 |
| 장애물 회피·경로탐색 | ❌ 미구현 | 현재는 직선 이동(나무·분수를 통과). 타일맵+pathfinding 또는 콜라이더 필요 |

#### 한 줄 정리

> **World에 `TapCallbacks`를 붙여 탭 좌표(`localPosition`)를 월드 좌표로 받고,
> 그것을 `_target`에 저장한 뒤, `applyInput`이 매 프레임 한 걸음씩 다가가며 도착 순간
> `position.setFrom`으로 스냅한다. 키보드가 눌리면 `_target`을 비워 직접 조종을
> 우선한다.** (Flutter의 `onTapDown` + `setState`를, 게임에서는 "탭=목적지 저장"과
> "루프=이동"으로 분리한 형태.)
