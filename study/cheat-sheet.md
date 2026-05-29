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

### 5.9 렌더링·`priority`·깊이 정렬(y-sorting)

"이미지를 add하면 알아서 그려지나? 누가 위에 보이나? 캐릭터가 나무 앞에 섰다
뒤로 가면?" — 한 묶음으로 답합니다. (모든 사실은 flame 1.37.0 공식 문서·소스로 확인)

#### ① add만 하면 Flame이 매 프레임 자동으로 그린다 — `render` 직접 호출 불필요

스프라이트 1장이든 애니메이션이든 똑같습니다. 게임 루프가 매 틱 트리를 따라
`renderTree`를 재귀 호출하므로, **트리에 `add`(mount)되어 있기만 하면** 자동으로
그려집니다. `SpriteComponent`·`SpriteAnimationComponent`는 `render()`가 이미 구현돼
있어 `sprite`/`animation`만 세팅하면 됩니다(애니메이션은 `update`에서 프레임도 자동 진행).

```dart
class Tree extends SpriteComponent with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    sprite = await game.loadSprite('tree.png'); // 세팅만 하면 끝. render 호출 X
    // size를 안 줘도 됨 — 아래 ✅ 참고
  }
}
```

> ✅ **size 걱정은 생각보다 적습니다.** `SpriteComponent`/`SpriteAnimationComponent`는
> **autoResize가 기본 켜짐**이라, `sprite`를 세팅하면 `size`를 생략해도 원본
> (`srcSize`)으로 자동 설정됩니다. "size가 0이라 안 보이는" 문제는 주로 **`PositionComponent`를
> 직접 상속**해 size를 안 준 경우입니다.

**그래도 안 보일 때 체크리스트**: ① 트리에 `add` 안 됨(부모 미마운트) ② `PositionComponent`
직접 상속인데 `size=0` ③ 이미지 로드 실패/경로 오타 ④ 화면 밖 `position`/`anchor`
⑤ `HasVisibility`로 `isVisible=false` ⑥ `opacity`/`scale` 0 ⑦ 다른 컴포넌트에 완전히 가려짐.

#### ② `priority` — 그리는 순서(z-index)

모든 `Component`는 `int priority`를 가집니다(기본 `0`, 음수도 가능).

- **값이 클수록 나중에 = 위에** 그려집니다(Flutter/CSS의 `z-index`와 같은 발상).
- **같은 값이면 add한 순서(FIFO)** — 먼저 넣은 게 아래, 나중에 넣은 게 위.
- ⚠️ **비교는 "같은 부모의 형제(sibling)끼리만".** 렌더 순서의 **1차 기준은 트리
  구조**(부모가 먼저 그려지고 그 위에 자식), priority는 그 안에서의 2차 기준입니다.
  → **다른 부모에 속한 컴포넌트는 priority를 아무리 높여도** 다른 가지를 넘어 앞으로
  나올 수 없습니다(부모 서브트리가 통째로 그려지므로).
- ⚠️ **`update()` 호출 순서도 priority를 따릅니다.** (흔한 오해 — priority가 "그리는
  순서 전용"이라고 알기 쉬운데, 실제로 `updateTree`와 `renderTree`가 **같은 정렬
  컬렉션**을 순회합니다. update에선 시각적 의미는 없고 처리 순서만 결정.)
- **런타임 변경**: `component.priority = n;` → 그 부모의 형제 리스트가 재정렬되어
  **같은 틱의 렌더 직전**에 반영됩니다. 단 재정렬은 **형제 전체를 다시 정렬**하므로
  **정적 기물은 한 번만**(생성 시) 설정하고 건드리지 않는 게 좋습니다.

#### ③ "통과(pass)"와 `priority`는 완전히 별개다 ⚠️

사용자가 묶어 물었지만, 둘은 **서로 무관한 시스템**입니다.

| 구분 | 결정하는 것 | 담당 |
|---|---|---|
| **통과/막힘** (겹쳐서 지나가나, 부딪혀 멈추나) | 충돌 시스템 | `Hitbox` + `CollisionType` + `CollisionCallbacks` |
| **겹쳤을 때 누가 위에 보이나** | 렌더 z-순서 | `priority` |

- `priority`는 통과 여부에 **아무 영향이 없습니다.** 그냥 "겹친 그림 중 누가 위냐"만 정함.
- 게다가 **Flame의 충돌은 "감지/통지"만** 합니다. 부딪혔다고 자동으로 멈추지 않아요.
  막으려면 `onCollisionStart`/`onCollision`에서 **직접 위치 보정**을 구현해야 합니다.
  아무것도 안 하면 두 객체는 그냥 겹친 채 **통과**합니다. (충돌은 Phase 2에서 본격적으로)

#### ④ 캐릭터가 기물 앞↔뒤로 — y-sorting(깊이 정렬) ⭐

2.5D의 핵심입니다. **발끝 y가 클수록(화면에서 더 아래 = 더 가까움) priority를 높게**
주면, 캐릭터가 나무보다 아래에 서면 나무를 가리고, 나무 뒤(위)로 가면 나무에 가려집니다.
매 프레임 priority를 y로 다시 계산하면 그 **전환이 저절로** 일어납니다.

```dart
class Character extends SpriteComponent with HasGameReference<MyGame> {
  Character() : super(anchor: Anchor.bottomCenter); // 기준점을 '발끝'으로

  @override
  void update(double dt) {
    super.update(dt);
    priority = position.y.toInt();   // 발끝 y → priority. 깊이 정렬의 전부
  }
}
```

- **앵커는 `Anchor.bottomCenter`**(발끝)가 자연스럽습니다. priority는 `int`라 `y`를
  `toInt()`로 양자화하며, 겹침 깜빡임이 생기면 `(position.y * 10).toInt()`처럼 스케일을 곱합니다.
- ⚠️ **Flame에 y-sort 자동 컴포넌트는 없습니다(1.37 기준).** 위처럼 **수동 갱신이 표준**.
  (1.37의 `HasAutoBatchedChildren`은 draw call 배칭 최적화지 y-sort가 아님.)
- **정렬은 같은 부모(레이어) 안에서만** 일어납니다. y-sort에 참여할 캐릭터·기물은 **같은
  레이어**에 두고, 바닥 타일/하늘은 별도 레이어(고정 priority)로 분리하세요.
- **비용**: 정적 기물은 `onLoad`에서 1회만, **움직이는 객체만** 매 프레임 갱신. `int`
  값이 그대로면 재정렬이 자동 스킵되므로 멈춰 있는 객체는 사실상 공짜입니다.
- 완전한 공식·다층 정렬·tiebreaker는 [03-phase3-isometric-2.5d.md](03-phase3-isometric-2.5d.md) §4, 용어는 [game-glossary.md](game-glossary.md) Y-sort 항목 참고.

#### ⑤ 용어 — 기물·PC·몬스터는 모두 "Component"

맞습니다. Flame에는 **`game object`라는 별도 타입이 없습니다.** 화면에 나오는 모든
것은 `Component`(위치가 필요하면 `PositionComponent` 계열)입니다. `FlameGame`·`World`·
카메라조차 전부 `Component`입니다. (Unity의 GameObject에 빗댄 설명은 주석에만 등장할 뿐
Flame의 타입명이 아닙니다.)

> **한 줄 정리**: add만 하면 **자동 렌더**(스프라이트 컴포넌트는 size도 자동). 누가 위에
> 보이나는 **`priority`**(같은 부모 형제끼리, 클수록 위, update 순서까지 좌우). **통과
> 여부는 priority가 아니라 충돌 시스템**. 캐릭터 앞↔뒤 가림은 **`priority = 발끝 y`
> 매 프레임 갱신**(y-sorting, 수동). 그리고 모든 기물은 **Component**다.

### 5.10 클릭-투-무브(click-to-move) — 탭으로 목적지까지 이동

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
| 탭한 곳과 캐릭터가 **살짝 어긋나** 멈춤 | `anchor`가 가리키는 점(프레임 중심 등)이 그림 속 캐릭터와 다름 | `anchor`를 발끝(`bottomCenter`)·캐릭터 위치로 맞춤 → 바로 아래 절 |

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

#### `anchor`와 발끝 정렬 — 클릭 지점에 "무엇"이 도착하나

여기까지는 "**어디**(월드 좌표)로 갈지"를 정확히 받는 법이었습니다. 마지막 퍼즐은 그
좌표에 **캐릭터의 어느 점**이 도착하느냐 — 바로 `anchor`입니다.

> **`position`은 "`anchor`가 가리키는 점이 도착할 좌표"입니다.** (공식 문서: *the
> position is where the anchor point will end up after the component is translated*)
> 그래서 클릭 지점에 무엇이 오는지는 **전적으로 `anchor`가 결정**합니다.

**증상**: 탭 좌표(`_target`)는 정확한데 캐릭터가 살짝 빗나가 멈춘다.
**원인**: `anchor`는 **컴포넌트(=텍스처 프레임 `size`)의 비율점**일 뿐, **그림 속 캐릭터
픽셀을 인식하지 않습니다.** `Anchor.center`(=`Anchor(0.5, 0.5)`)는 64×64 프레임의
`(32, 32)`를 가리키는데, 캐릭터가 프레임 안에서 한쪽에 치우쳐 그려져 있으면 그 점은
**캐릭터가 아니라 빈 패딩**입니다. 그래서 `position`은 정확해도 캐릭터가 그 차이만큼 밀려
보입니다.

```text
64×64 프레임 (anchor=center가 가리키는 점 ● = (32,32))
┌───────────────┐
│         ▓▓▓   │  ▓ = 실제 캐릭터 그림(상단 오른쪽에 치우침)
│         ▓▓▓   │  ● = position이 클릭 지점에 맞추는 점 = 빈 패딩
│      ●        │  → 클릭 지점엔 ●가 오고, 캐릭터(▓)는 우상단으로 밀려 보임
│  (빈 패딩)     │     어긋난 거리 = (캐릭터 기준점 − 프레임 비율점)
└───────────────┘
```

**해결**: 클릭 지점에 **발**을 맞추려면 `anchor`를 발끝으로 둡니다. 그 순간 `position`의
의미가 "발끝의 월드 좌표"로 바뀌어, §5.10 ④의 도착 스냅(`position.setFrom(_target!)`)이
그대로 발 기준이 됩니다.

```dart
// 발끝이 프레임 하단 중앙에 그려져 있을 때
class Player extends SpriteAnimationGroupComponent with HasGameReference<MyGame> {
  Player() : super(anchor: Anchor.bottomCenter); // = Anchor(0.5, 1.0) = 발끝
  // ...
}
// 이제 position = '발끝의 월드 좌표' → 탭 좌표를 그대로 써도 발이 정확히 그 지점에 섬
```

발끝이 하단 중앙이 **아니라** 프레임 안에서 어긋나 있으면(예: 텍스처 `(30, 63)` 픽셀),
맞추려는 픽셀을 프레임 크기로 나눠 **커스텀 앵커**를 만듭니다 — `Anchor(px/W, py/H)`:

```dart
super(anchor: const Anchor(30 / 64, 63 / 64)); // = Anchor(0.469, 0.984)
```

**세 가지 해결 방법** (상황에 맞게 선택):

| 방법 | 어떻게 | 장점 | 단점 |
|---|---|---|---|
| A. 이미지 수정 | 시트에서 캐릭터를 프레임 중앙/하단중앙에 재배치 | `Anchor.center`/`bottomCenter`만 쓰면 됨 | 원본 아트 수정, 프레임마다 작업 |
| B. 커스텀 anchor ✅ | 치우친 비율로 `Anchor(px/W, py/H)` | 이미지 안 건드림, 한 줄 | 매직넘버, 프레임마다 위치 같아야 함 |
| C. 부모/자식 분리 | 빈 `PositionComponent`(논리=발끝) + 자식 `SpriteComponent`를 **자식 `position`** 오프셋 | 로직·그림 분리, 그림자·체력바 부착 쉬움 | 구조 복잡 |

> ⚠️ **C의 함정**: 오프셋은 반드시 **자식의 `position`**으로 줍니다. 부모 `anchor`를
> 바꿔 자식 위치를 맞추려 하면 실패합니다 — **자식의 로컬 원점은 부모 `anchor`와 무관하게
> 항상 부모의 top-left**이기 때문입니다(공식 문서가 명시한 흔한 함정).

> ⚠️ **`position`은 "부모 좌표계" 기준**입니다. 캐릭터가 `world`(루트)의 직속 자식인
> 일반적 구조에선 월드 좌표를 그대로 넣어도 되지만, **다른 컴포넌트의 자식으로 중첩**되면
> `position` 대신 `absolutePosition`을 써야 합니다.

> **§5.9 y-sorting과의 관계 — 같은 앵커가 두 문제를 동시에 해결**: 발끝 기준(`bottomCenter`)으로
> 두면 **가림 순서(누가 위에 보이나, §5.9)** 와 **클릭 도착(어디에 서나, 여기)** 이 둘 다
> 자연스러워집니다. 그래서 2.5D 캐릭터는 `Anchor.bottomCenter`가 사실상 기본값입니다.
> (참고: 현재 [lib/main.dart](lib/main.dart)는 `Player`·기물이 모두 `Anchor.center`라,
> 발 기준 도착·자연스러운 깊이를 원하면 `bottomCenter`로 바꾸고 배치 좌표를 함께 조정하세요.)

#### 확장 아이디어 (현재 코드와의 관계 표기)

| 기능 | 현재 코드 | 어디서 시작하나 |
|---|---|---|
| 이동 중 재탭으로 목적지 교체 | ✅ 이미 동작 | `setTarget`이 `_target`을 덮어쓰므로 별도 로직 불필요 |
| 탭 지점에 마커(이펙트) 표시 | ❌ 미구현 | `onTapDown`에서 그 위치에 임시 컴포넌트를 `world.add` 후 잠시 뒤 `removeFromParent` |
| 도착 시 콜백(`onArrive`) | ❌ 미구현 | `Player`에 `VoidCallback?` 필드 추가, 스냅 처리(`position.setFrom`) 직후 호출 |
| 드래그로 목적지 지정 | ❌ 미구현 | World에 `DragCallbacks`를 더해 `onDragEnd`의 `localPosition`을 목적지로 |
| 드래그 경로 주위 몬스터 **자동·순차 공격** | ❌ 미구현 | `DragCallbacks`로 경로 수집 → 선분-점 거리로 주위 몬스터 탐색 → 타겟 큐로 한 마리씩, 죽으면 다음. 상세 분석 → [tech-auto-targeting.md](tech-auto-targeting.md) |
| 장애물 회피·경로탐색 | ❌ 미구현 | 현재는 직선 이동(나무·분수를 통과). 타일맵+pathfinding 또는 콜라이더 필요 |

#### 한 줄 정리

> **World에 `TapCallbacks`를 붙여 탭 좌표(`localPosition`)를 월드 좌표로 받고,
> 그것을 `_target`에 저장한 뒤, `applyInput`이 매 프레임 한 걸음씩 다가가며 도착 순간
> `position.setFrom`으로 스냅한다. 키보드가 눌리면 `_target`을 비워 직접 조종을
> 우선한다.** (Flutter의 `onTapDown` + `setState`를, 게임에서는 "탭=목적지 저장"과
> "루프=이동"으로 분리한 형태.)

### 5.11 카메라 좌표 변환 & `visibleWorldRect`

`CameraComponent` 2.0(현 flame 1.x 표준)은 **World 좌표 ↔ 화면(전역) 좌표 변환**과
**"지금 화면에 보이는 월드 영역"** 을 직접 노출합니다. 입력 좌표를 월드로 옮기거나,
화면 밖 오브젝트를 컬링(렌더 생략)할 때 핵심입니다.

```dart
// 화면(전역) 좌표 → 월드 좌표 (예: 터치 지점에 무언가 배치)
final worldPoint = cam.globalToLocal(screenPosition);
// 월드 좌표 → 화면 좌표 (예: 적 머리 위에 HUD 마커)
final screenPoint = cam.localToGlobal(enemy.position);

// 지금 카메라에 보이는 월드 영역(Rect). zoom/이동에 따라 매 프레임 갱신됨.
final Rect view = cam.visibleWorldRect;
if (!view.overlaps(enemy.toRect())) {
  // 화면 밖 → 무거운 연산/렌더 스킵 (수동 컬링)
}
```

- `visibleWorldRect`는 신기능이 아니라 **flame 1.6.0부터 있는 안정 API**입니다
  (`CameraComponent`에서 `Rect` 반환). deprecate된 적 없습니다. 예전
  `gameRef.camera.visibleWorldRect` 표기만 `game.camera.visibleWorldRect`로 바뀌었을
  뿐(이는 `HasGameRef` deprecate인 1.28.0과 함께 정리된 명명 변화).
- `viewfinder.angle`/`viewfinder.zoom` 동시 적용 역시 1.30 신기능이 아니라 **1.x 초기부터
  있는 표준 기능**(§5.7)이므로, "특정 버전 이상에서만 가능"으로 오해하지 마세요.
  (출처: Camera Component docs)
- `CameraComponent.withFixedResolution(width: 800, height: 600, world: world)`(§5.5)을
  쓰면 `visibleWorldRect`가 항상 **고정 논리 해상도를 기준으로** 계산되어, 기기 해상도가
  달라도 동일한 컬링/배치 로직을 재사용할 수 있습니다.

### 5.12 컴포넌트 쿼리 — `componentsAtPoint`

**"이 화면 좌표 아래에 어떤 컴포넌트가 있나?"** 를 찾을 때 쓰는 표준 API입니다. 직접
클릭 판정을 짤 필요 없이, 보통은 `TapCallbacks`/`DragCallbacks` 믹스인(§5.4)이
내부적으로 이걸 사용해 적절한 컴포넌트에 이벤트를 라우팅합니다.

```dart
// game 또는 World에서 호출. 전역(화면) 좌표를 넘긴다.
for (final component in world.componentsAtPoint(screenPosition)) {
  if (component is Enemy) {
    component.onClicked();
    break; // 맨 위(최상단 priority)부터 순회됨
  }
}
```

- 반복자는 **위에 그려진(priority가 높은) 컴포넌트부터** 순서대로 내놓습니다 — DOM의
  hit-testing과 동일한 직관(§5.9 priority 참고).
- **좌표 변환을 자동 처리**하므로 카메라 zoom/translate가 적용돼 있어도 그대로 동작합니다.
- 개별 컴포넌트에 클릭을 받게 하려면 직접 쿼리 대신 `with TapCallbacks` +
  `onTapDown(TapDownEvent event)`를 쓰는 편이 권장됩니다(§5.4). 이때 `containsLocalPoint`를
  오버라이드하면 사각형이 아닌 **hit 영역(원형 등)** 도 정의할 수 있습니다.

### 5.13 `ComponentKey` — 컴포넌트 안정 참조

`late final Player player` 필드를 직접 들고 다니기 애매한 상황(예: 깊은 트리 어딘가의
컴포넌트를 다른 곳에서 찾아야 할 때)에서, **전역 키로 컴포넌트를 조회**합니다. Flutter의
`GlobalKey`와 같은 발상입니다.

```dart
final playerKey = ComponentKey.named('player');

world.add(Player(key: playerKey));

// 이후 어디서든 (game 참조만 있으면) 안정적으로 조회
final player = game.findByKey<Player>(playerKey);
// 또는 모든 PositionComponent를 타입으로:
final allEnemies = world.children.query<Enemy>();
```

- `ComponentKey.named(...)`는 **같은 이름이면 동일 키**로 취급되고, `ComponentKey.unique()`는
  **매번 새 키**입니다.
- 남발하면 결합도가 올라가므로, 정말 트리를 가로질러 참조해야 하는 **핵심 객체(플레이어,
  보스)에만** 쓰세요. 단순 자식 접근은 필드 보관이나 `children.query<T>()`로 충분합니다.

### 5.14 Effects 기초 — 선언형 애니메이션

위치/회전/스케일/투명도 변화를 `update(dt)`에서 손으로 보간하지 않고, **`Effect`
컴포넌트를 `add`해서 선언형으로** 처리합니다. 끝나면 자동으로 트리에서 제거되도록 할 수
있습니다.

```dart
import 'package:flame/effects.dart';

// 0.4초 동안 (200, 0) 만큼 부드럽게 이동 (ease-in-out)
player.add(
  MoveEffect.by(
    Vector2(200, 0),
    EffectController(duration: 0.4, curve: Curves.easeInOut),
  ),
);

// 회전 + 반복 + 끝나면 자기 자신 제거
enemy.add(
  RotateEffect.by(
    2 * pi, // 1회전(라디안). pi는 dart:math
    EffectController(duration: 1, repeatCount: 3),
  )..removeOnFinish = true,
);

// 깜빡임(피격 표현 등): 투명도를 0↔1로 왕복
sprite.add(
  OpacityEffect.fadeOut(
    EffectController(duration: 0.1, alternate: true, repeatCount: 4),
  ),
);
```

- **자주 쓰는 Effect**: `MoveEffect.by/to`, `RotateEffect.by/to`, `ScaleEffect.by/to`,
  `OpacityEffect.fadeIn/fadeOut`, `SizeEffect.by/to`, 그리고 색조를 입히는 `ColorEffect`.
  flame 1.37.0에는 색조 변환 전용 `HueEffect`/`HueDecorator`도 추가되어(#3852) 스프라이트
  색감을 손쉽게 바꿀 수 있습니다.
- **`EffectController`가 타이밍/커브/반복을 전담**합니다(`duration`, `curve`,
  `reverseDuration`, `alternate`, `repeatCount`, `infinite`, `startDelay`).
- 카메라 셰이크는 별도 패키지 `flame_noise`의 `NoiseEffectController`를 `MoveEffect.by`와
  조합해 구현합니다(Phase 2에서 다룸).
- Effect는 **"한 번의 연출"** 에 적합하고, 지속적인 게임플레이 이동(WASD)은 §5.4처럼
  `update(dt)` 폴링으로 처리하는 것이 원칙입니다.

### 5.15 게임 맵에 기물 배치하기 — 나무·분수 같은 정지 오브젝트

게임 맵(나무·바위·건물 등)을 만드는 일은 **별도의 `GameMap` 클래스가 필요한 게
아닙니다.** `FlameGame`이 이미 들고 있는 `world`가 곧 맵이고(§5.6), 거기에 `add`만 하면
됩니다. 플레이어를 추가하는 것과 완전히 같은 패턴입니다.

```dart
class Tree extends SpriteComponent with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    sprite = await game.loadSprite('tree.png');  // 정지 이미지 1장
    size = Vector2(64, 128);
    anchor = Anchor.center;
  }
}

// onLoad 안에서: player를 add한 것과 동일하게 기물을 add
await world.add(player);
await world.add(Tree()..position = Vector2(1200, 800));  // 월드 절대 좌표
```

- **정지 기물 = `SpriteComponent`, 움직이는 캐릭터 = `SpriteAnimationGroupComponent`.**
  안 움직이고 그림 1장이면 가벼운 쪽(`SpriteComponent`)을 씁니다(§5.1 계층).
- **기물은 월드 좌표에 고정**합니다. 화면에서 흘러가 보이는 건 카메라가 움직여서지 기물이
  움직이는 게 아닙니다(카메라/월드 분리, §5.5). 따라서 `position`은 `Vector2(1200, 800)`처럼
  **맵 내 절대 좌표로** 박고, `size/2`(화면 중앙) 기준 배치는 학습용 편법으로만 쓰세요.

**맵을 만드는 4가지 방법** — 규모가 커질수록 아래로 내려갑니다.

| 규모 | 방법 | 요약 |
|---|---|---|
| 기물 ~10개 (학습) | 손으로 `world.add` 반복 | 위 코드 그대로 |
| 수십~수백, 자주 수정 | 좌표를 **데이터(JSON/리스트)** 로 빼고 반복문으로 add | 코드와 데이터 분리 |
| 맵 여러 종류, 통째 전환 | **`World` 상속한 커스텀 월드 클래스**(`VillageWorld` 등) | `super(world: VillageWorld())`로 끼움 |
| 진짜 게임 맵 | **Tiled 에디터 + `flame_tiled`** | `.tmx`를 마우스로 그려 `TiledComponent.load(...)` |

**좋은 맵의 4원칙**: ① 좌표를 코드에 박지 말고 **데이터로 분리** ② 렌더 순서를
**`priority`로 지배**(2.5D는 y-sorting → §5.9) ③ **월드 좌표계로 통일** ④
**`camera.setBounds(...)`로 맵 경계 부여**(§5.7).

**맵이 복잡해질 때**: 화면 밖 기물은 그리지 않는 **컬링**(§5.11 `visibleWorldRect`),
거대 맵은 **청크 분할 로딩**(Phase 6), 투사체·이펙트는 **객체 풀링**(`ComponentPool`,
Phase 7), **정적/동적 레이어 분리**로 정적 기물 캐싱.

### 5.16 게임 컨트롤 — 키보드·탭·드래그·핀치·줌 (3중 입력)

현재 `lib/main.dart`의 "입력→동작" 전체. 입력 소스마다 들어오는 경로가 물리적으로 달라
**성질에 맞는 3계층**으로 나눕니다.

- **Listener** (가장 바깥, OS 포인터) — 데스크톱 줌. 마우스 휠 `onPointerSignal`(PointerScrollEvent)→`zoomBy(1.1)`, 트랙패드/매직마우스 `onPointerPanZoomUpdate`(PointerPanZoom)→`zoomBy(1.03)`.
- **RawGestureDetector** — 터치·마우스 제스처. `TapGestureRecognizer`/`LongPressGestureRecognizer`/`ScaleGestureRecognizer` 3개를 등록(모두 `supportedDevices:{touch,mouse}`, **trackpad 제외**).
- **FlameGame with KeyboardEvents** — `onKeyEvent`가 `keys` 집합을 교체 → `update`가 매 프레임 `player.applyInput(keys,dt)`로 **폴링**.

**디바이스 × 제스처 매트릭스**

| 장치 | 제스처 | 처리 위치 | 동작 |
|---|---|---|---|
| PC 마우스 | 휠 | `Listener.onPointerSignal` → `zoomBy(1.1 또는 1/1.1)` | 줌 |
| PC 마우스 | 클릭(탭) | `TapGestureRecognizer.onTapUp` → `handleTap` | PC 이동 |
| PC 마우스 | 길게 누름 | `LongPressGestureRecognizer.onLongPress` → `resetView` | 줌1.0+PC중앙 |
| PC 마우스 | 드래그 | `ScaleGestureRecognizer`(pointerCount==1) | 카메라 패닝 |
| 트랙패드/매직마우스 | 표면 스와이프 | `Listener.onPointerPanZoomUpdate` → `zoomBy(1.03 또는 1/1.03)` | 줌 |
| 스마트폰 | 1손가락 탭 | `TapGestureRecognizer.onTapUp` → `handleTap` | PC 이동 |
| 스마트폰 | 1손가락 길게 | `LongPressGestureRecognizer.onLongPress` → `resetView` | 줌1.0+PC중앙 |
| 스마트폰 | 1손가락 드래그 | `ScaleGestureRecognizer`(pointerCount==1) | 카메라 패닝 |
| 스마트폰 | 2손가락 핀치 | `ScaleGestureRecognizer`(pointerCount>=2) → `zoomTo(_gestureBaseZoom*scale)` | 줌 |
| 키보드 | WASD/화살표 | `onKeyEvent` → `applyInput` | 캐릭터 이동 |

**키보드/탭은 `applyInput`의 velocity로 합류** — WASD·화살표를 OR로 묶어 `+=`/`-=` 누적(상하 동시=상쇄), `normalized()`로 대각선 가속 방지, `position += velocity.normalized()*speed(300)*dt`. 키 입력 있으면(`velocity.length>0`) `_target=null`로 탭 취소(키보드 우선), 없으면 `_target`까지 한 걸음씩 가고 `toTarget.length<=step`에서 `position.setFrom(_target!)`로 스냅. **카메라**는 PC와 독립: 1손가락 드래그 첫 프레임에 `camera.stop()`(FollowBehavior 제거) 후 `viewfinder.position -= canvasDelta/zoom`, 핀치는 `zoomTo`(clamp 0.5~3.0), 롱탭 `resetView`는 줌1.0→`stop`→`viewfinder.position=player.position.clone()`→`follow(player)`.

> **제스처 아레나 한 줄**: `TapGestureRecognizer`는 본질적으로 단일 포인터(PrimaryPointer 계열)라 두 번째 손가락이 닿는 순간 아레나에서 자동 REJECT → `ScaleGestureRecognizer`만 승리 → **핀치 중 PC가 이동하지 않음**. tap+scale 병용은 Flutter 표준(금지 조합은 pan+scale).

**흔한 함정**
- **핀치 중 PC 이동** → `TapCallbacks`가 두 손가락을 각 탭으로 오인. 탭을 `TapGestureRecognizer`로 분리하면 해결.
- **트랙패드 줌이 두 배** → recognizer `supportedDevices`에 trackpad 포함 시 Listener와 이중 처리. trackpad 제외 → Listener 전담.
- **드래그해도 카메라 제자리/탭한 곳과 다른 데로 이동** → 패닝 첫 프레임 `camera.stop()` 누락(FollowBehavior가 되돌림), 또는 canvas 좌표를 `camera.globalToLocal`로 월드 변환하지 않음.

**실전 콤보 (현재 동작)**
- **① 둘러보고 한 번에 이동**: 줌아웃 → 1손가락 드래그로 영역 찾기 → 탭(PC가 화면 밖이어도 그 지점으로 이동) → 롱탭(zoom 1.0 + PC 정중앙 + follow 재개로 원위치). follow가 풀려도 탭은 `globalToLocal`로 "지금 화면이 비추는 월드 좌표"를 정확히 집습니다.
- **② 이동 중에도 시점 자유**: 줌아웃 → 드래그 → 탭(이동 시작) → 가는 도중 다시 드래그로 둘러보고 **재탭으로 목적지 즉시 교체**(`_target` 한 값) → 롱탭으로 복귀. 키보드를 누르면 `_target`이 취소돼 직접 조종으로 전환됩니다.
- 카메라(줌·패닝·롱탭=시점)와 탭·키보드(PC 조종)가 분리돼 자유롭게 섞입니다.

> **향후(미구현)**: 드래그 경로로 **주위 몬스터를 순차 자동 공격**하는 설계가
> [tech-auto-targeting.md](tech-auto-targeting.md)에 있습니다(`DragCallbacks` 경로 누적 →
> 점·선분 거리 필터 → 타겟 큐 + 쿨다운). 단 **현재 드래그는 패닝**이고 몬스터·전투
> 시스템이 없으므로, 모드/제스처 분리 + 전투 도입(§Phase 2)이 선행돼야 합니다.

전체 설명은 [게임 컨트롤 전체 문서](example/game-control.md). 관련 절: §5.4(입력 시스템 — 단 현재 코드는 `TapCallbacks` 대신 `RawGestureDetector`로 진화), §5.7(viewfinder zoom/pan), §5.10(클릭-투-무브), §5.11(`globalToLocal` 좌표 변환).
