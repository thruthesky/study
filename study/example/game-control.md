# 게임 컨트롤(Game Control) — 키보드·탭·드래그·핀치·줌 종합

이 문서는 `lib/main.dart`에 들어 있는 게임의 **입력/조작(컨트롤) 전체**를 설명합니다.
즉 "사용자가 키를 누르거나 화면을 터치/드래그/핀치하면 → 무슨 일이 일어나는가"를
코드와 100% 일치하게 추적합니다.

[hello_game_walking_animation.md](hello_game_walking_animation.md)에서 **키보드로 캐릭터를
움직이고 애니메이션을 전환**하는 기초를 익혔다면, 이 문서는 그 위에 **탭 이동(클릭-투-무브),
카메라 패닝, 핀치 줌, 데스크톱 줌, 롱탭 리셋**까지 얹은 "완성형 컨트롤"을 다룹니다.

> **소스 코드 사본**: 이 문서가 설명하는 시점의 `lib/main.dart` 전체는 맨 아래
> [§6. 전체 소스 코드(부록)](#6-전체-소스-코드-부록)에 그대로 복사해 두었습니다. 본 프로젝트의
> `lib/main.dart`는 학습이 진행되며 계속 바뀌므로, 이 문서를 읽을 때는 부록 쪽을 기준으로 보세요.

관련 문서:
- [hello_game_walking_animation.md](hello_game_walking_animation.md) — idle/walk 애니메이션 전환 (이 예제의 전 단계)
- [hello_game_map_objects.md](hello_game_map_objects.md) — 게임 맵(world)에 나무·분수 기물 배치
- [hello_game_vector2_velocity.md](hello_game_vector2_velocity.md) — Vector2와 velocity의 기초
- [../cheat-sheet.md](../cheat-sheet.md) — §5.4(입력 시스템)·§5.7(카메라/줌)·§5.10(클릭-투-무브)·§5.11(좌표 변환)

---

## 0. 학습 목표

이 문서를 끝까지 따라가면 다음을 설명할 수 있게 됩니다.

1. **왜 입력을 3중 구조**(Listener + RawGestureDetector + `FlameGame with KeyboardEvents`)로 나누는가
2. **각 계층이 어떤 입력**(휠/트랙패드 · 탭/롱탭/드래그/핀치 · 키보드)을 담당하는가
3. **키보드 이동의 폴링 구조** — `onKeyEvent`의 "순간 이벤트"와 `update`의 "매 프레임"을 `keys` 집합이 잇는 방식
4. **탭 이동**(클릭-투-무브) — `globalToLocal`로 canvas→world 변환 후 `_target`까지 한 걸음씩 다가가고 도착 시 스냅
5. **키보드 vs 탭 이동의 우선순위** — `velocity.length > 0`이면 `_target = null`(키보드 우선)
6. **카메라 제어** — 1손가락 드래그 패닝, 2손가락 핀치 줌, 데스크톱 휠/트랙패드 줌, 롱탭 리셋
7. **제스처 아레나** — 왜 두 손가락 핀치 중에는 탭(=PC 이동)이 발동하지 않는가
8. **`supportedDevices`로 trackpad를 제외**해 "이중 줌"을 구조적으로 막는 이유

---

## 1. 입력 아키텍처 & 디바이스 매트릭스

### 1.1 한 화면 안에서 입력이 흘러가는 큰 그림

코드를 한 줄씩 보기 전에, 모든 입력이 어디로 들어와 어디로 흘러가는지를 한눈에 봅니다.

```text
┌──────────────────────────────────────────────────────────────┐
│                     사용자 입력 (하드웨어)                     │
│   키보드 │ 마우스 휠 │ 트랙패드/매직마우스 │ 터치 화면        │
└───────────────────────────┬──────────────────────────────────┘
                            │
      ┌─────────────────────┼─────────────────────┐
      ▼                     ▼                     ▼
┌───────────────┐   ┌────────────────────┐  ┌────────────────────┐
│ Listener      │   │ RawGestureDetector │  │ FlameGame           │
│ (OS 포인터)   │   │ (터치·마우스 제스처)│  │  with KeyboardEvents│
└──────┬────────┘   └─────────┬──────────┘  └─────────┬──────────┘
       │                      │                       │
  ┌────┴─────┐        ┌───────┴────────┐         onKeyEvent
  ▼          ▼        ▼       ▼        ▼              │
PointerScroll Pointer  Tap   Long    Scale       keys 집합 갱신
(휠)         PanZoom   탭    Press   (1손/2손)        │
  │         (트랙패드)  │     롱탭     │           (매 프레임 폴링)
  ▼          ▼        ▼      ▼      ┌─┴──┐            ▼
 zoomBy     zoomBy  handleTap reset │1손 │2손      update(dt)
 (×1.1)     (×1.03)  │       View   패닝  줌          │
            │        ▼              │    │      player.applyInput
            │   setTarget(_target)  │  zoomTo      (keys, dt)
            ▼        │              ▼    ▼            │
       ┌────────────┴──────────────┴────┴────────────┴───────┐
       │                       MyGame                         │
       └──────────────┬──────────────────────┬───────────────┘
                      ▼                       ▼
                 ┌─────────┐            ┌─────────────┐
                 │ camera  │            │ player      │
                 │ 줌/패닝 │            │ 이동/애니   │
                 └─────────┘            └─────────────┘
```

핵심은 입력 소스마다 **들어오는 경로가 물리적으로 다르다**는 점입니다. 그래서 한 가지
디텍터로 다 받지 않고, 성질에 맞는 세 계층으로 나눕니다.

### 1.2 왜 3중 구조인가 — 각 계층의 책임

#### 계층 ① Listener — 데스크톱 줌 (OS 포인터 신호)

`main()`에서 `GameWidget`을 감싸는 가장 바깥 위젯입니다. OS 레벨 포인터 신호를 직접 받습니다.

```dart
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
    final dy = event.panDelta.dy;
    if (dy != 0) game.zoomBy(dy < 0 ? 1.03 : 1 / 1.03);
  },
  child: RawGestureDetector( /* 아래 ② */ ),
)
```

- **마우스 휠**은 `PointerScrollEvent`로 들어옵니다(`onPointerSignal`). 한 번에 크게(1.1배).
- **트랙패드/매직 마우스**의 표면 스와이프는 `PointerScrollEvent`가 **아니라** `PointerPanZoomUpdateEvent`로
  들어옵니다(`onPointerPanZoomUpdate`). 작은 변화가 연속으로 오므로 조금씩(1.03배).

> **왜 Flame 기본 `ScrollDetector`를 안 쓰나?** `ScrollDetector`는 `PointerScrollEvent`만
> 받아 **트랙패드/매직 마우스를 통째로 놓칩니다.** 두 경로를 모두 잡으려면 OS 포인터 신호를
> 직접 받는 `Listener`가 필요합니다. (§5.7 카메라/줌 참고)

#### 계층 ② RawGestureDetector — 터치·마우스 제스처

3개의 제스처 recognizer를 등록합니다. 모두 `supportedDevices: {touch, mouse}`로,
**trackpad는 일부러 제외**했습니다(이유는 §4.4).

| recognizer | 콜백 | 호출 대상 | 동작 |
|---|---|---|---|
| `TapGestureRecognizer` | `onTapUp` | `game.handleTap(localPosition)` | 탭한 지점으로 PC 이동 |
| `LongPressGestureRecognizer` | `onLongPress` | `game.resetView` | 줌 1.0 + PC 중앙 복귀 + 추적 재개 |
| `ScaleGestureRecognizer` | `onStart` / `onUpdate` | `handleScaleStart` / `handleScaleUpdate` | 1손가락=패닝, 2손가락=핀치 줌 |

> **왜 Flame 기본 `TapCallbacks`를 안 쓰나?** 터치 핀치(두 손가락)를 `TapCallbacks`가
> **각 손가락의 "탭"으로 오인**해, 핀치 중에 캐릭터가 이동하는 버그가 있었습니다. 탭을
> `TapGestureRecognizer`로 분리하면, 탭은 본질적으로 단일 포인터라 두 손가락 핀치에서는
> **발동조차 하지 않아** 충돌이 사라집니다(§4 제스처 아레나). 참고로 [cheat-sheet §5.4/§5.10]
> 은 `TapCallbacks`/`MyWorld.onTapDown` 방식을 소개하지만, 현재 `main.dart`는 핀치 충돌을
> 없애기 위해 이 `RawGestureDetector` 방식으로 진화했습니다.

#### 계층 ③ FlameGame with KeyboardEvents — 키보드

`MyGame`이 `with KeyboardEvents` mixin을 달고 `onKeyEvent`를 오버라이드합니다.
키 입력은 위 두 계층(포인터 계열)과 **완전히 별개의 축**입니다.

```dart
class MyGame extends FlameGame with KeyboardEvents {
  final keys = <LogicalKeyboardKey>{}; // 현재 눌린 키 집합(입력↔루프의 다리)

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    keys
      ..clear()
      ..addAll(keysPressed); // 현재 눌린 키들로 통째로 교체
    return KeyEventResult.handled;
  }
}
```

### 1.3 디바이스 × 제스처 완전 매트릭스

각 입력 장치에서 각 제스처가 **정확히 어느 코드로** 처리되는지의 표입니다.
(이 표가 이 문서의 핵심 요약입니다.)

| 장치 | 제스처 | 처리 위치 | 호출 | 동작 |
|---|---|---|---|---|
| **PC 마우스** | 휠 위로 | `Listener.onPointerSignal` | `zoomBy(1.1)` | 확대 |
| **PC 마우스** | 휠 아래로 | `Listener.onPointerSignal` | `zoomBy(1/1.1)` | 축소 |
| **PC 마우스** | 클릭(탭) | `TapGestureRecognizer.onTapUp` | `handleTap(pos)` | PC를 클릭 지점으로 이동 |
| **PC 마우스** | 길게 누름 | `LongPressGestureRecognizer.onLongPress` | `resetView()` | 줌 1.0 + PC 중앙 복귀 |
| **PC 마우스** | 드래그(1포인터) | `ScaleGestureRecognizer.onUpdate` | `handleScaleUpdate(1, …)` | 카메라 패닝 |
| **트랙패드/매직마우스** | 표면 스와이프 위 | `Listener.onPointerPanZoomUpdate` | `zoomBy(1.03)` | 확대 |
| **트랙패드/매직마우스** | 표면 스와이프 아래 | `Listener.onPointerPanZoomUpdate` | `zoomBy(1/1.03)` | 축소 |
| **스마트폰** | 1손가락 탭 | `TapGestureRecognizer.onTapUp` | `handleTap(pos)` | PC를 탭 지점으로 이동 |
| **스마트폰** | 1손가락 길게 누름 | `LongPressGestureRecognizer.onLongPress` | `resetView()` | 줌 1.0 + PC 중앙 복귀 |
| **스마트폰** | 1손가락 드래그 | `ScaleGestureRecognizer.onUpdate`(pointerCount==1) | `handleScaleUpdate(1, …)` | 카메라 패닝 |
| **스마트폰** | 2손가락 핀치 | `ScaleGestureRecognizer.onUpdate`(pointerCount>=2) | `handleScaleUpdate(>=2, …)` | 카메라 줌 |
| **키보드** | WASD 또는 화살표 | `MyGame.onKeyEvent` → `update` | `player.applyInput(keys, dt)` | 캐릭터 이동 |

**읽는 법**: "스마트폰 + 2손가락 핀치" → `ScaleGestureRecognizer`가 `pointerCount>=2`로
`handleScaleUpdate`를 호출 → `zoomTo(...)`만 실행(탭=PC 이동은 아레나에서 reject되어 발동 안 함).

---

## 2. 키보드 이동 & 탭 이동

키보드 이동과 탭 이동은 **둘 다 결국 `Player.applyInput` 안에서 `velocity`로 합쳐져**
같은 위치 갱신 공식(`position += velocity.normalized() * speed * dt`)을 통과합니다.
차이는 "velocity가 어디서 왔는가"뿐입니다.

### 2.1 키보드 이동 — "순간 이벤트"를 "지속 상태"로 바꾸는 폴링

`onKeyEvent`는 **키 상태가 바뀌는 순간**에만 호출되고, `update`는 **매 프레임** 호출됩니다.

```text
사용자가 W 키를 1초 동안 꾹 누름
  ↓
onKeyEvent  — 처음 누른 순간 1회, 뗀 순간 1회 (OS 키 리피트로 더 자주 올 수도)
update      — 그 1초 동안 약 60번 호출됨
```

만약 `onKeyEvent`에서 곧바로 이동을 처리하면 누른 "순간"만 한 번 움직이고 멈춥니다.
"꾹 누르는 동안 계속 이동"하려면 **매 프레임 현재 입력 상태를 다시 읽어야** 합니다.
그래서 두 흐름을 `keys` 집합이라는 다리로 잇습니다.

```dart
// MyGame.onKeyEvent — 매 키 이벤트마다 keys를 "현재 눌린 키들"로 교체
keys
  ..clear()
  ..addAll(keysPressed);

// MyGame.update — 매 프레임 그 keys를 player에 전달(폴링)
@override
void update(double dt) {
  super.update(dt);                 // 부모가 자식들의 update를 순회(반드시 먼저!)
  player.applyInput(keys, dt);      // 현재 키 집합 + dt 전달
}
```

> **`keys = keysPressed`가 아니라 `clear()..addAll(...)`인 이유**: 같은 Set 인스턴스의
> 내용만 교체해 매 이벤트마다 새 Set을 만드는 GC 부담을 줄입니다. 차이는 미미하므로
> 가독성을 위해 `keys = keysPressed.toSet();`로 써도 무방합니다.

### 2.2 WASD + 화살표 — `+=`/`-=` 누적과 정규화

`applyInput`은 매 프레임 `velocity`를 0에서 다시 시작해, 눌린 방향키를 누적합니다.

```dart
final velocity = Vector2.zero();   // 매 프레임 0에서 시작(이전 방향이 남으면 안 됨)

// 같은 방향은 OR로 묶어 방향키(Arrow)와 WASD 둘 다 지원.
if (keys.contains(LogicalKeyboardKey.arrowUp) ||
    keys.contains(LogicalKeyboardKey.keyW)) {
  velocity.y -= 1;                 // Y축 음수 = 위쪽
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
```

**왜 `=`(대입)이 아니라 `+=`/`-=`(누적)인가?**

```text
시나리오 A: W + S 동시 누름(상하 충돌)
  velocity.y -= 1  → (0, -1)
  velocity.y += 1  → (0,  0)   ← 자동 상쇄, 캐릭터 멈춤(자연스러움)

시나리오 B: W + D 동시 누름(대각선)
  velocity.y -= 1  → (0, -1)
  velocity.x += 1  → (1, -1)
  normalized()     → (0.707, -0.707)  ← 길이 1로 정규화
```

마지막의 `velocity.normalized()`가 핵심입니다. 정규화하지 않으면 대각선 입력 `(1, -1)`의
길이가 `√2 ≈ 1.414`라서 대각선 이동이 상하좌우보다 약 1.4배 빨라집니다. 정규화로
어느 방향이든 동일하게 1초당 `speed`(300픽셀)만큼 움직입니다.

```dart
// 위치 갱신의 핵심 공식
position += velocity.normalized() * speed * dt;
//          ↑ 방향만(길이 1)        ↑ 1초당 픽셀  ↑ 이번 프레임 경과 시간(초)
```

`dt`(경과 시간)를 곱했으므로 **FPS가 60이든 30이든 1초에 항상 300픽셀**로 일정합니다.

### 2.3 탭 이동(클릭-투-무브) — canvas→world 변환과 도착 스냅

탭의 출발은 `TapGestureRecognizer.onTapUp`입니다. 콜백이 주는 `localPosition`은
**GameWidget(canvas) 좌표**(화면 픽셀)라서, 카메라의 패닝·줌을 반영한 **월드 좌표**로
변환해야 합니다. 그 변환을 `camera.globalToLocal`이 해 줍니다.

```dart
// onTapUp: localPosition은 게임 위젯(canvas) 좌표
instance.onTapUp = (d) {
  game.handleTap(Vector2(d.localPosition.dx, d.localPosition.dy));
};

// MyGame.handleTap: canvas → world 변환 후 목적지 설정
void handleTap(Vector2 canvasPoint) {
  player.setTarget(camera.globalToLocal(canvasPoint));
}

// Player.setTarget: 목적지(월드 좌표)를 _target에 저장. null이면 "탭 이동 중 아님".
void setTarget(Vector2 target) {
  _target = target;
}
```

> **좌표계 두 가지**: **canvas**(GameWidget 화면, 좌상단 0,0)와 **world**(게임 세계 원점).
> 카메라가 패닝/줌되어 있으면 같은 화면 픽셀이라도 월드 좌표는 달라지므로, `globalToLocal`로
> 반드시 변환해야 PC가 "내가 누른 그 지점"으로 갑니다. (§5.11 좌표 변환 참고)

저장된 `_target`을 향해 실제로 걸어가는 일은 `applyInput`이 매 프레임 처리합니다.

```dart
if (velocity.length > 0) {
  _target = null;                    // (A) 키보드 입력 있음 → 탭 목적지 취소(키보드 우선)
} else if (_target != null) {
  final toTarget = _target! - position;  // 목적지까지의 방향·거리
  final step = speed * dt;               // 이번 프레임에 갈 수 있는 거리
  if (toTarget.length <= step) {
    // (B) 한 프레임 안에 도착 가능 → 정확히 목적지에 스냅하고 멈춤
    position.setFrom(_target!);          //     (방향으로만 계속 밀면 목적지를 지나쳐
    _target = null;                      //      좌우로 떨리는데, 스냅이 그걸 막음)
    current = PlayerState.idle;
    return;
  }
  velocity.setFrom(toTarget);            // (C) 아직 멀면 목적지 방향을 이번 이동 방향으로
}
```

이후 `velocity`는 키보드와 동일하게 정규화되어 위치 갱신 공식으로 흘러갑니다.
도착 판정 `toTarget.length <= step`이 없으면 매 프레임 목적지를 살짝 지나쳐
앞뒤로 떨리므로, `position.setFrom(_target!)` 스냅이 필수입니다.

### 2.4 키보드 vs 탭 이동 — 우선순위 한눈에

| 상황 | 결과 |
|---|---|
| 키를 누르고 있음(`velocity.length > 0`) | `_target = null` → 탭 이동 즉시 취소, 키보드로만 이동 |
| 키 입력 없음 + `_target != null` | 탭 목적지로 매 프레임 한 걸음씩 접근, 도착하면 스냅 후 idle |
| 키 입력 없음 + `_target == null` | velocity 0 → idle(정지) |

```text
[프레임 N] D 키 누른 채 탭 이동 중
   keys = {keyD} → velocity.x = 1 → velocity.length > 0 → _target = null
   → 탭 무시, 계속 오른쪽 이동

[D 키 뗌] keys = {} → velocity = 0 → _target != null이면 그제서야 탭 목적지로 이동 재개
```

---

## 3. 카메라 제어 — 패닝·핀치줌·데스크톱줌·롱탭리셋

카메라는 `MyGame`이 기본으로 가진 `camera`를 사용합니다. `onLoad`에서 `camera.follow(player)`로
시작해, 처음엔 항상 플레이어를 따라갑니다(`_cameraFollowing = true`).

### 3.1 줌의 두 메서드 — `zoomTo`(절대) / `zoomBy`(상대)

```dart
// 절대값으로 설정 + 0.5~3.0 범위 제한
void zoomTo(double value) {
  camera.viewfinder.zoom = value.clamp(0.5, 3.0).toDouble();
}

// 현재 줌에 배율을 곱함(데스크톱 휠/트랙패드용)
void zoomBy(double multiplier) => zoomTo(camera.viewfinder.zoom * multiplier);
```

- 줌은 카메라의 **`viewfinder`**가 담당합니다(§5.7). `1.0`=원본, `2.0`=2배 확대, `0.5`=절반 축소.
- `clamp(0.5, 3.0)`으로 범위 제한. zoom은 0 이하가 되면 내부 assert로 크래시하므로 하한이 중요합니다.
  (`clamp`는 `num`을 반환하므로 `toDouble()`로 다시 맞춤.)
- **왜 곱셈(`zoomBy`)인가?** 덧셈(`+0.1`)은 1.0에서 10% 증가지만 2.0에서는 5% 증가로 체감이
  달라집니다. 곱셈(`×1.1`)은 어느 배율에서든 비율이 일정해 줌이 자연스럽습니다.

### 3.2 1손가락 드래그 → 카메라 패닝

`handleScaleUpdate`에서 `pointerCount == 1`(2 미만)인 경우입니다.

```dart
void handleScaleUpdate(int pointerCount, double scale, Vector2 canvasDelta) {
  if (pointerCount >= 2) {
    zoomTo(_gestureBaseZoom * scale);   // 핀치(§3.3)
    return;
  }

  // 한 손가락 드래그 → 카메라 패닝.
  // 처음 패닝하는 순간 추적을 끕니다. 안 끄면 FollowBehavior가 매 프레임
  // 카메라를 player로 되돌려 패닝이 곧바로 취소됩니다.
  if (_cameraFollowing) {
    camera.stop();                      // FollowBehavior 제거
    _cameraFollowing = false;
  }

  // 화면 이동량(canvasDelta)을 월드 이동량으로 변환. 줌이 클수록 같은 화면
  // 이동이 더 작은 월드 이동이 되도록 zoom으로 나눔. 손가락 반대로 움직여야
  // "맵을 손으로 끌어오는" 느낌이라 -=(재대입)으로 변경.
  camera.viewfinder.position -= canvasDelta / camera.viewfinder.zoom;
}
```

세 가지 포인트:

1. **첫 프레임에 `camera.stop()`** — `onLoad`의 `camera.follow(player)`가 부착한
   `FollowBehavior`를 떼지 않으면, 매 프레임 카메라가 플레이어로 되돌아가 패닝이 즉시 취소됩니다.
   `_cameraFollowing` 플래그로 "딱 한 번만" 끕니다.
2. **`/ camera.viewfinder.zoom`** — `canvasDelta`는 화면 픽셀. 2배 줌이면 화면 50px = 월드 25px이므로
   줌으로 나눠 월드 이동량으로 환산합니다.
3. **`-=`(빼기)** — 손가락 방향과 **반대로** 카메라를 옮겨야 "맵을 손으로 끌어오는" 직관이 됩니다.
   `viewfinder.position`의 getter는 계산값이라 `setFrom`이 아닌 `-=`(재대입)으로 변경합니다.

### 3.3 2손가락 핀치 → 줌

`handleScaleUpdate`에서 `pointerCount >= 2`인 경우입니다. 핀치는 "시작 줌 × 누적 배율"로 동작합니다.

```dart
// 드래그/핀치 시작 시 기준 줌 저장
void handleScaleStart(int pointerCount) {
  _gestureBaseZoom = camera.viewfinder.zoom;
}

// 핀치 진행: 시작 줌 × 누적 배율(scale)
if (pointerCount >= 2) {
  zoomTo(_gestureBaseZoom * scale);
  return;
}
```

```text
핀치 시작: 줌 = 1.5 라면 _gestureBaseZoom = 1.5 저장
손가락 20% 벌림: scale = 1.2 → zoomTo(1.5 * 1.2) = zoomTo(1.8)
더 벌림:        scale = 1.4 → zoomTo(1.5 * 1.4) = zoomTo(2.1)
```

`scale`은 "제스처 시작 대비 누적 배율"이므로, 시작 줌을 기억해 두고 곱해야 자연스럽게
이어집니다. 핀치 중에는 패닝도 탭도 일어나지 않습니다(`return`으로 즉시 빠져나감 + 탭은 아레나에서 reject).

### 3.4 데스크톱 줌 — 휠 / 트랙패드

데스크톱 줌은 제스처 계층이 아니라 **계층 ① Listener**가 전담합니다(§1.2).

- **마우스 휠**: `onPointerSignal`의 `PointerScrollEvent` → `zoomBy(1.1)` 또는 `zoomBy(1/1.1)`.
- **트랙패드/매직마우스**: `onPointerPanZoomUpdate` → `zoomBy(1.03)` 또는 `zoomBy(1/1.03)`.
  연속 이벤트라 변화량을 작게 둡니다.

### 3.5 롱탭 → `resetView` (줌·위치 초기화 + 추적 재개)

```dart
void resetView() {
  zoomTo(1.0);                                       // ① 줌 원복
  camera.stop();                                     // ② 패닝 잔여/혹시 남은 FollowBehavior 정리
  camera.viewfinder.position = player.position.clone(); // ③ 카메라를 PC 위치로 즉시 점프
  camera.follow(player);                             // ④ 다시 따라가기 시작
  _cameraFollowing = true;                           // ⑤ 추적 중 플래그 복구
}
```

각 줄이 다 필요합니다.

| 줄 | 빠지면 |
|---|---|
| `zoomTo(1.0)` | 줌이 그대로 남음 |
| `camera.stop()` | 이전 follow/패닝 효과가 겹쳐 동작이 꼬임 |
| `viewfinder.position = player.position.clone()` | follow 속도 때문에 카메라가 "천천히" 접근(즉시 중앙 아님) |
| `.clone()` | `player.position`은 mutable이라 참조를 넣으면 이후 PC가 움직일 때 카메라도 묶여 끌려가는 버그 |
| `camera.follow(player)` | 이후 플레이어를 추적하지 않음 |

---

## 4. 제스처 아레나 — 왜 충돌하지 않는가

Flutter의 **제스처 아레나(Gesture Arena)** 는 여러 recognizer가 같은 포인터를 두고 경합하는
메커니즘입니다. 이 게임이 "핀치 중 PC 이동" 같은 버그 없이 동작하는 핵심 이유입니다.

### 4.1 세 recognizer의 경합

```text
사용자가 화면을 터치하면, 같은 포인터를 두고 셋이 경합:

  TapGestureRecognizer       — 단일 포인터(PrimaryPointerGestureRecognizer 계열)
  LongPressGestureRecognizer — 일정 시간(Flutter 기본 약 0.5초) 고정되면 확신
  ScaleGestureRecognizer     — 드래그/다중 포인터에서 확신

→ 가장 먼저 확신한 recognizer가 "승리"하고, 나머지는 reject되어 콜백이 호출되지 않음
```

### 4.2 왜 핀치 중에는 탭(=PC 이동)이 발동하지 않는가

```text
[손가락 1개 DOWN]
  Tap   : "포인터 1개. 내 영역일 수 있다."
  Scale : "1개는 아직 내 영역 아님."

[손가락 2개째 DOWN]
  Tap   : "포인터가 2개? 나는 본질상 단일 포인터다. 포기(REJECT)."
  Scale : "2개 포인터 감지! 곧 확신한다."

[핀치 시작(거리 변화)]
  Scale : "스케일 변화 감지 → 아레나 승리"
  Tap   : 이미 REJECT → onTapUp 호출 안 됨  ← ✅ 핀치 중 PC가 이동하지 않음
```

핵심은 `TapGestureRecognizer`가 코드로 두 포인터를 막는 게 아니라, **본질적으로 단일 포인터만
인식**하기 때문에 2개 이상이 들어오면 자동으로 아레나에서 빠진다는 점입니다. 그래서
`handleScaleUpdate(pointerCount >= 2, …)`만 호출되어 줌만 일어납니다.

> **tap + scale 병용은 Flutter 표준**입니다. Flutter가 동시 인식을 금지하는 조합은
> `pan + scale`뿐이고, `tap + scale`은 함께 등록해도 됩니다. 이 게임이 `pan`을 직접 쓰지
> 않고 `scale`의 `pointerCount`로 패닝/핀치를 분기한 것도 이 표준에 맞춘 설계입니다.

### 4.3 `supportedDevices`로 trackpad를 제외하는 이유 — 이중 줌 방지

3개 recognizer 모두 `supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse}`로
선언되어 **trackpad가 빠져 있습니다.**

```text
만약 trackpad를 포함했다면 (트랙패드로 핀치 시):
  Listener.onPointerPanZoomUpdate → zoomBy(1.03)          ① 줌
  + ScaleGestureRecognizer도 trackpad 처리 → zoomTo(...)  ② 또 줌
  ⇒ 한 번의 핀치가 1.03 × 1.03 ≈ 1.06 배로 이중 적용(버그)

trackpad를 제외하면:
  트랙패드 표면 스와이프(PointerPanZoom)는 Listener가 전담
  ScaleGestureRecognizer는 {touch, mouse}만 받으므로 trackpad 핀치를 아예 무시
  ⇒ 정확히 한 번만 줌
```

즉 **트랙패드 줌은 Listener, 터치 핀치 줌은 ScaleGestureRecognizer**로 경로를 깔끔히 분리한
설계입니다.

---

## 5. 전체 코드 워크스루 & 함정 & 확장

### 5.1 한 화면 전체 흐름 따라가기

**상황: W 키를 누른 채, 화면을 탭하고, 드래그하고, 롱탭하고, 두 손가락으로 핀치**

```text
[t=0.0s] W 누름
  onKeyEvent → keys = {keyW}
  다음 update → applyInput({keyW}, dt)
    velocity = (0,-1), length>0 → _target=null, current=running
    position += (0,-1)*300*dt  → 위로 이동

[t=0.5s] W 뗌 + 탭
  onKeyEvent → keys = {}
  TapGestureRecognizer.onTapUp → handleTap(canvas) → globalToLocal → setTarget(world)
  다음 update → applyInput({}, dt)
    velocity=0, _target!=null → 목적지 방향으로 이동, current=running

[t=0.8s] 목적지 도착
  toTarget.length <= step → position.setFrom(_target), _target=null, current=idle

[t=0.9s] 1손가락 드래그
  ScaleGestureRecognizer.onStart → handleScaleStart(1) → _gestureBaseZoom 저장
  onUpdate(1, …) → handleScaleUpdate(1, …)
    camera.stop(); _cameraFollowing=false
    viewfinder.position -= canvasDelta / zoom  → 카메라만 패닝(PC는 그대로)

[t=1.2s] 롱탭
  LongPressGestureRecognizer.onLongPress → resetView()
    zoomTo(1.0); camera.stop(); viewfinder.position = player.position.clone();
    camera.follow(player); _cameraFollowing=true

[t=1.3s] 2손가락 핀치
  ScaleGestureRecognizer.onStart → handleScaleStart(2) → _gestureBaseZoom 저장
  onUpdate(>=2, scale) → handleScaleUpdate(>=2, …) → zoomTo(_gestureBaseZoom * scale)
  TapGestureRecognizer는 아레나에서 REJECT → PC 이동 없음
```

### 5.2 클래스·메서드 역할 요약표

| 위치 | 역할 |
|---|---|
| `main()`의 `Listener` | 데스크톱 휠/트랙패드 줌 (`zoomBy`) |
| `main()`의 `RawGestureDetector` | 탭/롱탭/드래그/핀치 등록 (trackpad 제외) |
| `MyGame.onKeyEvent` | 현재 눌린 키로 `keys` 집합 교체 |
| `MyGame.update` | 매 프레임 `player.applyInput(keys, dt)` 폴링 |
| `MyGame.zoomTo` / `zoomBy` | 절대/상대 줌(범위 0.5~3.0) |
| `MyGame.handleTap` | canvas→world 변환 후 `player.setTarget` |
| `MyGame.handleScaleStart` | 핀치 기준 줌 `_gestureBaseZoom` 저장 |
| `MyGame.handleScaleUpdate` | 1손가락=패닝 / 2손가락=핀치 줌 분기 |
| `MyGame.resetView` | 줌 1.0 + PC 중앙 + 추적 재개 |
| `Player.setTarget` | 탭 목적지 `_target` 저장 |
| `Player.applyInput` | velocity 계산, 키/탭 우선순위, 상태 전환, 위치 갱신 |

### 5.3 자주 만나는 함정

| 증상 | 원인 | 해결 |
|---|---|---|
| **핀치 중 PC가 이동** | `TapCallbacks`가 두 손가락을 각 탭으로 오인 | 탭을 `TapGestureRecognizer`로 분리(단일 포인터 → 아레나 reject). 현재 코드는 해결됨 |
| **트랙패드 줌이 두 배씩** | recognizer `supportedDevices`에 trackpad 포함 | trackpad 제외 → Listener가 전담(§4.3) |
| **트랙패드/매직마우스 줌이 아예 안 됨** | `ScrollDetector`만 사용(PointerScroll만 받음) | `Listener.onPointerPanZoomUpdate`로 PointerPanZoom 처리 |
| **드래그해도 카메라가 즉시 제자리** | 패닝 시작 시 `camera.stop()` 누락 → FollowBehavior가 되돌림 | 첫 프레임에 `camera.stop()` + `_cameraFollowing=false` |
| **탭한 곳과 다른 데로 이동** | canvas 좌표를 그대로 사용(줌·패닝 미반영) | `camera.globalToLocal(canvasPoint)`로 월드 변환 |
| **탭 목적지에서 좌우로 떨림** | 도착 판정/스냅 없이 방향으로만 계속 밀어 목적지를 지나침 | `toTarget.length <= step`일 때 `position.setFrom(_target!)` |
| **롱탭 후 카메라가 PC에 묶여 끌려감** | `viewfinder.position = player.position`(참조) | `player.position.clone()`으로 복사 |
| **대각선이 더 빠름** | 정규화 없이 더함 | `velocity.normalized()` 곱하기 |
| **키 떼도 계속 이동** | `applyInput` 시작의 `Vector2.zero()` 초기화 누락 | 매 프레임 velocity 0에서 시작 |

### 5.4 확장 아이디어

- **더블탭 줌**: `DoubleTapGestureRecognizer`를 추가해 `zoomTo(2.0)` 토글.
- **카메라 경계 제한**: 패닝 후 `viewfinder.position`을 맵 범위로 `clamp`(§5.11 `visibleWorldRect` 활용).
- **줌 범위 변경**: `zoomTo`의 `clamp(0.5, 3.0)` 값 조정.
- **탭 지점 마커**: 탭 시 목적지에 짧은 원형 이펙트 표시.
- **부드러운 줌**: `zoomTo`를 Effect/Tween으로 감싸 점진적 확대/축소.

### 5.5 실전 조작 콤보 — 줌·패닝·탭·롱탭 이어 쓰기

지금까지의 제스처(줌/패닝/탭/롱탭)는 따로따로가 아니라 **이어서 쓸 때** 진가가 납니다.
실제 플레이에서 자주 쓰는 두 가지 콤보입니다. (모두 **현재 코드로 동작**합니다.)

**콤보 ① 멀리 둘러보고 한 번에 이동**

```text
핀치 줌아웃(또는 휠 ↓)   → 맵을 넓게 본다 (zoom 0.5 쪽)
1손가락 드래그            → 카메라를 옮겨 원하는 영역을 찾는다 (follow 해제됨)
원하는 지점을 탭          → PC가 화면 밖이라도 그 월드 좌표로 걸어가기 시작
롱탭                      → zoom 1.0 + PC를 화면 정중앙 + follow 재개 (원래 시점 복귀)
```

- 드래그로 follow가 풀려 PC가 화면 중앙이 아니어도, 탭은 `camera.globalToLocal`로
  **지금 화면이 비추는 월드 좌표**를 정확히 집어 목적지로 삼습니다(§2.3).
- 롱탭(`resetView`)이 "한 방에 원위치(줌 1.0 + PC 중앙 + 추적 재개)" 역할을 합니다(§3.5).

**콤보 ② 이동 중에도 시점 자유**

```text
줌아웃 → 드래그로 위치 찾기 → 탭(이동 시작)
   → PC가 걸어가는 동안 다시 드래그로 다른 곳을 둘러보기
   → 또 탭해서 목적지 변경 (이동 중 재탭 = 목적지 즉시 교체)
   → 아무 때나 롱탭으로 PC에게 카메라 복귀
```

- 탭 목적지는 `_target` 한 값이라, **이동 중 다시 탭하면 목적지가 즉시 새 지점으로
  교체**됩니다(§2.3). "가다가 마음이 바뀌면 다시 탭"이 자연스럽습니다.
- 키보드(WASD/화살표)를 누르면 그 순간 `_target`이 취소되어(키보드 우선, §2.4)
  손으로 직접 조종으로 전환됩니다.

> **핵심**: 카메라(줌·패닝·롱탭)는 "보는 시점", 탭/키보드는 "PC 조종"으로 **완전히
> 분리**돼 있어 자유롭게 섞어 쓸 수 있습니다. 둘이 충돌하지 않는 건 §4 제스처 아레나
> 분리 덕분입니다.

#### 향후 확장 — 드래그 경로로 주위 몬스터 공격 (⚠️ 미구현 설계)

별도 분석 문서 [tech-auto-targeting.md](../tech-auto-targeting.md)는 **화면을 드래그해
그린 경로(줄) 주위의 몬스터들을 한 마리씩 번갈아 자동 공격**하고 죽으면 다음으로
넘어가는 메커니즘을 설계합니다. (`DragCallbacks`로 경로 점 누적 → 경로-몬스터 점·선분
최단거리 필터 → 타겟 큐 + 쿨다운 순차 공격.)

⚠️ **현재 코드에는 없습니다.** 도입하려면 두 가지를 먼저 정리해야 합니다.

- **선행 조건**: 지금 `lib/main.dart`에는 몬스터·충돌·전투가 없습니다(클릭-투-무브만).
  `Monster`/HP/`Hitbox`/데미지·사망 처리가 먼저 필요합니다([02-phase2-2d-action.md](../02-phase2-2d-action.md)).
- **제스처 역할 충돌**: 지금 **1손가락 드래그는 카메라 패닝**입니다(§3.2). 같은 드래그를
  "공격 경로"로도 쓰려면, 모드 전환(평소엔 패닝 / 전투·조준 모드에선 공격 경로)이나
  별도 제스처로 **역할을 분리**해야 합니다.

전체 단계·함정·구현 선택지는 [tech-auto-targeting.md](../tech-auto-targeting.md)를 참고하세요.

---

## 6. 전체 소스 코드 (부록)

> 아래는 이 문서를 작성한 시점의 `lib/main.dart` 전체 사본입니다. 위 설명의 모든 코드 인용은
> 이 원본과 100% 일치합니다.

```dart
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
```

---

## 7. 한 줄 요약

> **입력은 성질에 따라 3계층**(Listener=데스크톱 줌 · RawGestureDetector=터치/마우스 제스처 ·
> KeyboardEvents=키보드)으로 나뉘고, **키보드/탭은 `applyInput`의 velocity로 합쳐져** 같은
> 이동 공식을 타며(키보드 우선), **카메라(줌·패닝)는 PC와 독립**으로 움직이고, **제스처
> 아레나와 `supportedDevices` 분리**가 "핀치 중 PC 이동"과 "이중 줌"을 구조적으로 없앤다.
