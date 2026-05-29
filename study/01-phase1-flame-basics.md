# Phase 1 — Flame 엔진 기초

> **기간**: 1주 (집중 시 4~5일)
> **목표**: Flame의 Component / World / Camera 구조를 체득하고, 캐릭터 이동 + 카메라 follow + 줌이 작동하는 프로젝트를 완성한다.
> **⚠️ 금기**: MMORPG, 서버, 네트워크는 절대 손대지 않는다. **엔진 그릇 만들기에만 집중.**

---

## 1. 학습 목표 (Definition of Done)

- [ ] FlameGame 라이프사이클 (onLoad → update → render) 설명 가능
- [ ] Component 트리 구조와 부모-자식 좌표계 설명 가능
- [ ] CameraComponent + World 구조에서 follow/zoom 구현 가능
- [ ] 키보드/터치 입력을 Component에 연결 가능
- [ ] Sprite 로딩과 SpriteComponent 렌더링 가능

---

## 2. 사전 지식 매핑 (시니어 가속용)

| 게임 도메인 개념 | 서버/웹 도메인 비유 |
|---|---|
| Game Loop (`update(dt)`) | 이벤트 루프 (Node.js) / 메인 루프 — 단, 폴링 기반 60Hz |
| Component 트리 | DOM 트리 / Widget 트리 — 단, 매 프레임 update() 호출됨 |
| FlameGame | Express App 인스턴스 — 단일 진입점, 라이프사이클 보유 |
| World | DOM의 `<body>` — 모든 게임 오브젝트의 루트 |
| CameraComponent | 브라우저 뷰포트 + CSS transform — World 위의 창 |
| Sprite | `<img>` 태그 — 단, GPU 텍스처로 직접 그림 |
| Anchor | CSS `transform-origin` |
| priority | CSS `z-index` — 단, 매 프레임 갱신 가능 |

---

## 3. 핵심 구조

### 3.1 Component 트리

```
FlameGame
├── CameraComponent
│   ├── Viewport
│   ├── Viewfinder (zoom/translate)
│   └── HudComponent (UI)
└── World
    ├── Player (PositionComponent)
    │   └── SpriteAnimationComponent (자식)
    ├── Enemy (PositionComponent)
    ├── Tile (SpriteComponent)
    └── ...
```

핵심 규칙:
- **자식의 position은 부모 기준 상대 좌표**
- 부모가 회전/스케일되면 자식도 따라감
- World에 추가된 것만 CameraComponent를 통해 화면에 표시됨
- HUD(체력바, 미니맵)는 CameraComponent 내부에 추가 — 월드 좌표와 무관

### 3.2 라이프사이클

```
[엔진 시작]
  ↓
FlameGame.onLoad()       // async, 에셋 로딩
  ↓
[매 프레임 16.6ms 마다]
  ├── update(dt)         // 모든 Component 재귀 호출
  └── render(canvas)     // 모든 Component 재귀 호출
  ↓
[종료]
  └── onRemove()
```

### 3.3 핵심 클래스

| 클래스 | 역할 |
|---|---|
| `FlameGame` | 게임 루트, 라이프사이클 보유 |
| `Component` | 모든 게임 오브젝트의 베이스 (위치 없음) |
| `PositionComponent` | position, size, angle, anchor 보유 |
| `SpriteComponent` | 정적 이미지 |
| `SpriteAnimationComponent` | 스프라이트 시트 애니메이션 |
| `World` | 월드 컨테이너 (1.x에서 분리됨) |
| `CameraComponent` | 카메라, follow/zoom/bounds |
| `RectangleComponent`, `CircleComponent` | 도형 (디버깅·placeholder용) |

### 3.4 라이프사이클 메서드 vs 라이프사이클 Future

시니어에게 가장 헷갈리는 지점: Flame Component는 **오버라이드용 콜백 메서드**와 **await용 Future** 두 가지를 따로 제공합니다. 메서드는 "내 차례가 오면 호출돼"이고, Future는 "다른 컴포넌트가 그 시점을 기다리는 핸들"입니다.

| 콜백 메서드 (override) | 대응 Future (await) | 의미 |
|---|---|---|
| `onLoad()` (async, 1회) | `loaded` | 에셋 로딩 완료 |
| `onMount()` (트리 부착) | `mounted` | 부모 트리에 실제로 붙음 |
| `onRemove()` (트리 분리) | `removed` | 트리에서 제거됨 |
| `onGameResize(size)` | — | 게임 캔버스 크기 변경 |

핵심 차이:
- `onLoad`는 컴포넌트가 트리에 **추가되기 전 1회만** 실행됩니다(무거운 에셋 로딩 자리). 같은 인스턴스를 remove 후 다시 add해도 `onLoad`는 재실행되지 않습니다.
- `onMount`/`onRemove`는 트리에 붙고 떨어질 때마다 매번 실행됩니다(리스너 등록/해제 자리).
- 1.29.0부터 **부모가 트리에서 제거돼도 자식은 부모와의 관계를 유지**합니다(BREAKING, #3602). 즉 부모를 다시 add하면 자식도 함께 복귀합니다 — 예전처럼 자식이 detach되어 사라지지 않습니다.

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

> ⚠️ `onLoad()` 안에서 `add(child)`를 호출하면 자식은 부모가 mount된 뒤에 처리됩니다. "add 직후 size/position이 0"으로 보이는 버그는 대부분 `mounted`를 기다리지 않고 즉시 접근해서 생깁니다.

---

## 4. 코드 패턴

### 4.1 FlameGame + World + Camera 기본 골격

```dart
class MyGame extends FlameGame {
  late final CameraComponent cam;
  late final World world;
  late final Player player;

  @override
  Future<void> onLoad() async {
    world = World();
    cam = CameraComponent(world: world);
    cam.viewfinder.zoom = 1.0;
    addAll([world, cam]);   // 둘 다 게임에 추가

    player = Player()..position = Vector2.zero();
    world.add(player);

    cam.follow(player);     // 카메라가 플레이어 따라감
  }
}
```

> Flame 1.10+ 에서 `FlameGame(world: ..., camera: ...)` 생성자 형태도 가능합니다. 본 코스는 명시적 add 방식으로 진행 — 학습용으로 더 명확합니다.
>
> 2026-05 기준 공식 docs는 `CameraComponent.withFixedResolution(width: 800, height: 600, world: world)` 헬퍼를 함께 권장합니다. 모바일 다양한 해상도를 한 번에 처리할 수 있어 출시 단계에서 유용합니다. 학습 단계에선 위 명시 add 방식이 더 직관적이므로 그대로 유지하고, Phase 7~8에서 fixed resolution으로 전환을 고려하세요. 참고: https://docs.flame-engine.org/latest/flame/camera_component.html

### 4.2 Sprite 로딩

```bash
# 프로젝트 구조
assets/
└── images/
    └── player.png
```

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/images/
```

```dart
class Player extends SpriteComponent with HasGameReference {
  @override
  Future<void> onLoad() async {
    sprite = await game.loadSprite('player.png');
    size = Vector2(64, 64);
    anchor = Anchor.center;
  }
}
```

> ⚠️ Flame **1.28.0** 에서 `HasGameRef`(및 `gameRef` getter)가 deprecate되었습니다(PR [#3559](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md) — "Deprecate HasGameRef in favor of HasGameReference"). **`HasGameReference<T>`** 를 사용하고 인스턴스 접근은 `game` getter로 하세요 (`gameRef`는 호환을 위해 남아있지만 새 코드에선 쓰지 마세요). 일부 자료에 "1.33부터 deprecate"라고 잘못 적혀 있으나 실제 도입 버전은 1.28.0입니다.

### 4.3 SpriteAnimation

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

### 4.4 키보드 입력

```dart
class MyGame extends FlameGame with KeyboardEvents {
  final keys = <LogicalKeyboardKey>{};

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> pressed) {
    keys
      ..clear()
      ..addAll(pressed);
    return KeyEventResult.handled;
  }

  @override
  void update(double dt) {
    super.update(dt);
    player.applyInput(keys, dt);
  }
}
```

> 입력 → Player 연결은 **Player가 keys를 polling**하는 방식이 일반적. 이벤트 콜백 안에서 직접 position을 바꾸지 마세요. dt가 없어서 프레임 레이트 종속이 됩니다.

### 4.5 카메라 follow / zoom / bounds

```dart
cam.follow(player, maxSpeed: 500);     // 부드러운 follow
cam.viewfinder.zoom = 1.5;             // 1.5배 줌
cam.setBounds(Rectangle.fromLTWH(0, 0, 2000, 2000));  // 월드 경계
```

마우스 휠 줌:
```dart
class MyGame extends FlameGame with ScrollDetector {
  @override
  void onScroll(PointerScrollInfo info) {
    final dy = info.scrollDelta.global.y;
    cam.viewfinder.zoom = (cam.viewfinder.zoom - dy * 0.001).clamp(0.5, 3.0);
  }
}
```

> 2026-05 기준 `ScrollDetector` + `onScroll(PointerScrollInfo)` 는 **여전히 valid** (Flame 1.37 공식 zoom_example.dart에서도 사용 중). 다만 Tap/Drag 시스템이 `TapDetector` → `TapCallbacks`로 이전된 흐름을 따라 향후 scroll도 콜백 기반(`PointerMoveCallbacks` 계열)으로 점진 이전될 가능성이 있으므로 새 입력 시스템 출시 시 마이그레이션을 검토하세요. 출처: https://github.com/flame-engine/flame/blob/main/examples/lib/stories/camera_and_viewport/zoom_example.dart

### 4.6 카메라 좌표 변환 & `visibleWorldRect`

CameraComponent 2.0(현 flame 1.x 표준)은 **World 좌표 ↔ 화면(전역) 좌표** 변환과 "지금 화면에 보이는 월드 영역"을 직접 노출합니다. 입력 좌표를 월드로 옮기거나, 화면 밖 오브젝트를 컬링(렌더 생략)할 때 핵심입니다.

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

> `visibleWorldRect`는 신기능이 아니라 **flame 1.6.0부터 있는 안정 API**입니다(`CameraComponent`에서 `Rect` 반환). deprecate된 적 없습니다. 예전 `gameRef.camera.visibleWorldRect` 표기만 `game.camera.visibleWorldRect`로 바뀌었을 뿐(이는 `HasGameRef` deprecate인 1.28.0과 함께 정리된 명명 변화). `viewfinder.angle`/`viewfinder.zoom` 동시 적용 역시 1.30 신기능이 아니라 1.x 초기부터 있는 표준 기능이므로, "특정 버전 이상에서만 가능"으로 오해하지 마세요. 출처: [Camera Component docs](https://docs.flame-engine.org/latest/flame/camera_component.html)

> `CameraComponent.withFixedResolution(width: 800, height: 600, world: world)`(§4.1 인용 참고)을 쓰면 `visibleWorldRect`가 항상 고정 논리 해상도를 기준으로 계산되어, 기기 해상도가 달라도 동일한 컬링/배치 로직을 재사용할 수 있습니다.

### 4.7 컴포넌트 쿼리 — `componentsAtPoint`

"이 화면 좌표 아래에 어떤 컴포넌트가 있나?"를 찾을 때 쓰는 표준 API입니다. 직접 클릭 판정을 짤 필요 없이, 보통은 `TapCallbacks`/`DragCallbacks` 믹스인이 내부적으로 이걸 사용해 적절한 컴포넌트에 이벤트를 라우팅합니다.

```dart
// game 또는 World에서 호출. 전역(화면) 좌표를 넘긴다.
for (final component in world.componentsAtPoint(screenPosition)) {
  if (component is Enemy) {
    component.onClicked();
    break; // 맨 위(최상단 priority)부터 순회됨
  }
}
```

- 반복자는 **위에 그려진(priority가 높은) 컴포넌트부터** 순서대로 내놓습니다 — DOM의 hit-testing과 동일한 직관.
- 좌표 변환을 자동 처리하므로 카메라 zoom/translate가 적용돼 있어도 그대로 동작합니다.
- 개별 컴포넌트에 클릭을 받게 하려면 직접 쿼리 대신 `with TapCallbacks` + `onTapDown(TapDownEvent event)`를 쓰는 편이 권장됩니다(Phase 2에서 본격 사용). 이때 `containsLocalPoint`를 오버라이드하면 사각형이 아닌 hit 영역(원형 등)도 정의할 수 있습니다.

### 4.8 `ComponentKey` — 컴포넌트 안정 참조

`late final Player player` 필드를 직접 들고 다니기 애매한 상황(예: 깊은 트리 어딘가의 컴포넌트를 다른 곳에서 찾아야 할 때)에서, 전역 키로 컴포넌트를 조회합니다. Flutter의 `GlobalKey`와 같은 발상입니다.

```dart
final playerKey = ComponentKey.named('player');

world.add(Player(key: playerKey));

// 이후 어디서든 (game 참조만 있으면) 안정적으로 조회
final player = game.findByKey<Player>(playerKey);
// 또는 모든 PositionComponent를 타입으로:
final allEnemies = world.children.query<Enemy>();
```

> `ComponentKey.named(...)`는 같은 이름이면 동일 키로 취급되고, `ComponentKey.unique()`는 매번 새 키입니다. 남발하면 결합도가 올라가므로, 정말 트리를 가로질러 참조해야 하는 핵심 객체(플레이어, 보스)에만 쓰세요. 단순 자식 접근은 필드 보관이나 `children.query<T>()`로 충분합니다.

### 4.9 Effects 기초 — 선언형 애니메이션

위치/회전/스케일/투명도 변화를 `update(dt)`에서 손으로 보간하지 않고, **Effect 컴포넌트를 add**해서 선언형으로 처리합니다. 끝나면 자동으로 트리에서 제거되도록 할 수 있습니다.

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
  OpacityEffect.fadeOut(EffectController(duration: 0.1, alternate: true, repeatCount: 4)),
);
```

자주 쓰는 Effect: `MoveEffect.by/to`, `RotateEffect.by/to`, `ScaleEffect.by/to`, `OpacityEffect.fadeIn/fadeOut`, `SizeEffect.by/to`, 그리고 색조를 입히는 `ColorEffect`. flame 1.37.0에는 색조 변환 전용 `HueEffect`/`HueDecorator`도 추가되어(#3852) 스프라이트 색감을 손쉽게 바꿀 수 있습니다.

> `EffectController`가 타이밍/커브/반복을 전담합니다(`duration`, `curve`, `reverseDuration`, `alternate`, `repeatCount`, `infinite`, `startDelay`). 카메라 셰이크는 별도 패키지 `flame_noise`의 `NoiseEffectController`를 `MoveEffect.by`와 조합해 구현합니다(Phase 2에서 다룸). Effect는 "한 번의 연출"에 적합하고, **지속적인 게임플레이 이동(WASD)은 §4.4처럼 `update(dt)` 폴링**으로 처리하는 것이 원칙입니다.

### 4.10 게임 맵에 기물 배치하기 — 나무·분수 같은 정지 오브젝트

게임 맵(나무·바위·건물 등)을 만드는 일은 **별도의 `GameMap` 클래스가 필요한 게 아닙니다.** `FlameGame`이 이미 들고 있는 **`world`가 곧 맵**이고, 거기에 `add`만 하면 됩니다. 플레이어를 추가하는 것과 **완전히 같은 패턴**입니다.

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

- **정지 기물 = `SpriteComponent`, 움직이는 캐릭터 = `SpriteAnimationGroupComponent`.** 안 움직이고 그림 1장이면 가벼운 쪽(`SpriteComponent`)을 씁니다.
- **기물은 월드 좌표에 고정**합니다. 화면에서 흘러가 보이는 건 카메라가 움직여서지 기물이 움직이는 게 아닙니다(카메라/월드 분리). 따라서 `position`은 `Vector2(1200, 800)`처럼 맵 내 절대 좌표로 박고, `size/2`(화면 중앙) 기준 배치는 학습용 편법으로만 쓰세요.

**맵을 만드는 4가지 방법** — 규모가 커질수록 아래로 내려갑니다.

| 규모 | 방법 | 요약 |
|---|---|---|
| 기물 ~10개 (학습) | 손으로 `world.add` 반복 | 위 코드 그대로 |
| 수십~수백, 자주 수정 | 좌표를 **데이터(JSON/리스트)** 로 빼고 반복문으로 `add` | 코드와 데이터 분리 |
| 맵 여러 종류, 통째 전환 | `World` 상속한 **커스텀 월드 클래스** (`VillageWorld` 등) | `super(world: VillageWorld())`로 끼움 |
| 진짜 게임 맵 | **Tiled 에디터 + `flame_tiled`** | `.tmx`를 마우스로 그려 `TiledComponent.load(...)` |

**좋은 맵의 4원칙**: ① 좌표를 코드에 박지 말고 데이터로 분리 ② 렌더 순서를 `priority`로 지배(2.5D는 y-sorting → Phase 3) ③ 월드 좌표계로 통일 ④ `camera.setBounds(...)`로 맵 경계 부여(§4.5).

**맵이 복잡해질 때**: 화면 밖 기물은 그리지 않는 **컬링**(§4.6 `visibleWorldRect`), 거대 맵은 **청크 분할 로딩**(Phase 6), 투사체·이펙트는 **객체 풀링**(`ComponentPool`, Phase 7), **정적/동적 레이어 분리**로 정적 기물 캐싱.

> 위 내용의 한 줄 한 줄을 입문자 눈높이로 풀어 쓴 워크스루(`Tree`/`Fountain`/`FlowerTree` 실제 코드 + 4가지 방법·설계 원칙·복잡도 대응)는 예제 문서에 정리해 두었습니다 → [example/hello_game_map_objects.md](example/hello_game_map_objects.md). 충돌(통과 방지)은 Phase 2, y-sorting·Tiled는 Phase 3에서 본격적으로 다룹니다.

---

## 5. 실습 프로젝트 — "캐릭터 이동 테스트"

### 5.1 요구사항
1. WASD 키로 8방향 이동 (대각선 시 normalized)
2. 카메라가 플레이어를 따라감
3. 마우스 휠로 줌 인/아웃
4. 플레이어 스프라이트 출력 (placeholder 사각형 OK)
5. 월드 경계 표시 (`RectangleComponent` 또는 background)
6. 60fps 유지 — 우상단에 `FpsTextComponent` 띄울 것

### 5.2 폴더 구조 예시
```
phase1_basics/
├── lib/
│   ├── main.dart
│   └── game/
│       ├── my_game.dart
│       ├── player.dart
│       └── background.dart
├── assets/images/
└── pubspec.yaml
```

### 5.3 FPS 카운터
```dart
import 'package:flame/components.dart';

class HudFps extends FpsTextComponent {
  HudFps() : super(position: Vector2(8, 8));
}

// 카메라에 추가 (월드가 아니라 viewport에)
cam.viewport.add(HudFps());
```

### 5.4 검증 시나리오
- [ ] 30초간 사방으로 이동 후 FPS가 58 이하로 떨어지지 않음
- [ ] 줌 0.5x ~ 3x 사이 동작
- [ ] 카메라가 플레이어를 부드럽게 따라감 (스냅 아님)
- [ ] 월드 경계를 시각적으로 인지 가능

---

## 6. 시니어가 빠지기 쉬운 함정

### 6.1 "Provider로 player.position 관리"
- ❌ Provider/Riverpod에 position 넣으면 매 프레임 위젯 트리 rebuild → 30fps도 위태
- ✅ position은 Component 필드. UI에 노출 필요하면 Component → Riverpod 단방향, 단 **변경 시점만** notify

### 6.2 "Future로 이동 처리"
```dart
// ❌ 절대 금지
void moveTo(Vector2 target) async {
  while ((target - position).length > 1) {
    await Future.delayed(Duration(milliseconds: 16));
    position += (target - position).normalized();
  }
}
```
→ 게임 루프와 분리된 비동기 루프가 됨. **상태 머신 + update(dt)** 로 처리:
```dart
Vector2? _target;
void moveTo(Vector2 target) => _target = target;

@override
void update(double dt) {
  super.update(dt);
  if (_target == null) return;
  final dir = _target! - position;
  if (dir.length < 1) { _target = null; return; }
  position += dir.normalized() * 200 * dt;
}
```

### 6.3 "render(canvas) 안에서 상태 변경"
- render는 **읽기만**. 변경은 update에서. (게임 엔진의 황금률)

### 6.4 "world와 camera 추가 순서 무관"
- 1.x에서 world와 camera는 **둘 다 FlameGame에 추가**해야 함. camera는 자체적으로 world를 참조하지만 add는 별도.

### 6.5 "매 프레임 Vector2() 새로 생성"
- 매 프레임 객체 생성 → GC 압박 → 프레임 드랍
- 해결: `Vector2.zero()..setFrom(other)` 또는 미리 만든 버퍼 재사용

### 6.6 "hot reload 됐으니까 코드 잘 반영됐겠지"
- Component 트리 구조 변경은 hot reload로 반영 안 됨. **앱 재시작 (hot restart)** 필요할 때 많음.

---

## 7. 이 Phase에서 도입할 Flame 공식 패키지

| 패키지 | 용도 | 적용 시점 |
|---|---|---|
| `flame` | 엔진 코어 | 즉시 |
| `flame_lint` (dev) | 코드 품질 lint. 0-cost 적용 | Phase 1 시작 시 |

```yaml
# pubspec.yaml
dependencies:
  flame: ^1.37.0
dev_dependencies:
  flame_lint: ^1.4.3
```

> 2026-05-28 기준 `flame 1.37.0`(GitHub Releases 기준 2026-04-01 출시)의 환경 제약은 정확히 **Dart SDK `>=3.11.0 <4.0.0`, Flutter `>=3.41.0`** 입니다. Flutter 최소 버전 bump는 직전 `1.36.0`에서 이루어졌습니다(CHANGELOG의 "Bump Flutter min version to 3.41.0", #3807). 따라서 일부 자료에 보이는 "flame 1.x는 Dart >=3.0.0" 같은 일반화는 1.37.0 기준으로는 부정확합니다 — 1.37.0은 최소 Dart 3.11.0을 요구합니다. 본 코스는 Flutter 공식 stable 3.44 이상에서 진행하는 것을 권장합니다(study 프로젝트 pubspec의 `sdk: ^3.12.0`은 이 요구를 충족). 출처: [flame 1.37.0 pubspec.yaml](https://raw.githubusercontent.com/flame-engine/flame/v1.37.0/packages/flame/pubspec.yaml)

```yaml
# analysis_options.yaml
include: package:flame_lint/analysis_options.yaml
```

> 본 코스의 패키지 선택 원칙과 전체 38종 카탈로그는 [flame-official-packages.md](./flame-official-packages.md) 참조.

### 7.1 flame 1.37.0에서 Phase 1과 관련된 신기능

코어를 학습하는 단계에서 알아두면 좋은 1.37.0(2026-04-01) 추가 항목입니다(전체 changelog는 [공식 CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md) 참조).

| 신기능 | 내용 | Phase 1 활용 맥락 |
|---|---|---|
| `HueEffect` / `HueDecorator` (#3852) | 색조 변환 이펙트/데코레이터 | §4.9 Effects — 스프라이트 색감 변경 |
| `HasAutoBatchedChildren` mixin (#3850) | 자식 렌더를 자동 배칭 | 같은 텍스처 자식이 많을 때 draw call 절감(성능은 Phase 7) |
| `SpriteBatch`의 `bleed` 옵션 (#3871) | 타일 경계 seam(이음새) artifact 방지 | 타일맵은 Phase 3, 여기선 개념만 |
| `sprite`/`sprite-animation` 위젯에 `size` 파라미터 (#3870) | Flutter 위젯으로 스프라이트 표시 시 크기 지정 | 게임 밖 UI에서 게임 에셋 미리보기 |
| `OverlayManager.setActive()` (#3875) | 오버레이 활성/비활성 토글 | 일시정지/메뉴 오버레이 제어 |

### 7.2 ⚠️ "1.37 신기능"으로 착각하기 쉬운 API들의 실제 도입 버전

아래 항목들은 **1.37.0이 아니라 더 이전 버전**에서 추가되었습니다. 어떤 자료가 이것들을 "최신 신기능"으로 소개하면 버전을 의심하세요(출처: [CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md)).

| API / 변경 | 실제 도입 버전 |
|---|---|
| `HasGameRef` → `HasGameReference` deprecate (#3559) | **1.28.0** (일부 자료의 "1.33"은 오류) |
| 부모 제거 후에도 자식이 부모 관계 유지 (BREAKING, #3602) | **1.29.0** |
| `SpawnComponent`의 `target` 인자(#3635) / `spawnCount`(#3634) | **1.30.0** |
| `RasterSpriteComponent.fromImage` 생성자 (#3627) | **1.30.0** |
| 스프라이트 ghost-line/그래픽 artifact 수정(measure 도입, #3590) | **1.30.0** |
| `CameraComponent.visibleWorldRect` (`Rect` 반환) | **1.6.0** (deprecate 이력 없음) |
| `ComponentPool`(객체 풀링, #3816) / `FlameGame.dispose()`(#3825) | **1.36.0** (최적화는 Phase 7) |

---

## 8. 학습 자료

### 공식
- Flame Docs: https://docs.flame-engine.org
- Flame Examples: https://github.com/flame-engine/flame/tree/main/examples
- Pub: https://pub.dev/packages/flame

### 추천 학습 순서 (공식 docs)
1. Getting Started → Structure
2. Component System (이게 80%)
3. Camera and Viewport
4. Inputs (Keyboard / Tap / Drag)
5. Sprite / SpriteAnimation
6. Effects (선택, 보너스)

### 추천 영상 (학습 시 확인 후 사용)
- "Flame Engine Crash Course" 유튜브 검색
- "Flame 1.x migration guide" — 0.x → 1.x 차이 이해

---

## 9. 학습 후 메모 (직접 작성)

> 본 Phase 학습 후 여기에 직접 작성하세요.

- 가장 시간을 많이 쓴 개념:
- 의외로 쉬웠던 부분:
- 다음 Phase에 가지고 갈 코드 구조:

---

## 10. 다음 단계

[02-phase2-2d-action.md](./02-phase2-2d-action.md) — Sprite 애니메이션, Collision, 간단한 AI를 도입하여 "게임다운" 형태로 발전시킵니다.
