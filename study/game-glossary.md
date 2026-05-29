# 게임 개발 용어집 — Flutter 개발자를 위한 입문

> **대상**: Flutter 풀스택 경험은 풍부하지만 게임 개발은 처음인 개발자
> **목적**: Flame 코드와 본 스터디 문서들을 읽을 때 끊임없이 마주치는 게임 도메인 용어를 한 곳에서 정리합니다. "이 단어는 들어 봤는데 정확히 뭘 가리키는지 모르겠다"를 없애는 것이 목표입니다.
> **읽는 법**: 처음부터 통독할 필요는 없습니다. Flame 코드를 읽다가 모르는 단어가 나오면 이 문서에서 검색하세요.

---

## 1. 그림과 이미지의 기본 단위

### 픽셀 (pixel)

화면을 구성하는 가장 작은 색 점 한 개. 일반 Flutter 앱에서 다루는 `logical pixel`과 같은 개념입니다. Flame에서도 좌표·크기는 모두 픽셀 단위입니다.

### 프레임 (frame)

> **사용자 질문 1: "프레임이 뭐 무슨 뜻인가요? 한 프레임에 캐릭터의 움직임이 들어가 있는 건가요?"**

**프레임은 "한 장의 그림"입니다.** 영화나 애니메이션에서 쓰는 표현과 동일합니다.

영화는 1초에 24장의 정지 사진을 빠르게 연달아 보여 줘서 사람 눈이 "움직이는 것"으로 인식하게 만듭니다. 그 한 장 한 장이 프레임입니다. 게임의 캐릭터 애니메이션도 똑같습니다.

캐릭터가 걷는 모습을 보여 주고 싶다면, 다음과 같은 그림 8장을 준비합니다.

```
프레임 0: 양발이 모두 땅에 있음
프레임 1: 오른발이 살짝 들림
프레임 2: 오른발이 앞으로 나가는 중
프레임 3: 오른발이 땅에 닿기 직전
프레임 4: 양발이 다시 땅에 모임
프레임 5: 왼발이 살짝 들림
프레임 6: 왼발이 앞으로 나가는 중
프레임 7: 왼발이 땅에 닿기 직전
```

이 8장을 0.1초 간격으로 순환해서 보여 주면 사용자에게는 캐릭터가 자연스럽게 걷는 것처럼 보입니다. 즉 **한 프레임에는 "캐릭터의 움직임"이 아니라, 움직임의 어느 한 순간의 정지된 모습** 한 장이 들어 있습니다. 움직임 자체는 "여러 프레임을 시간에 따라 갈아 끼우는 행위"입니다.

> Flutter 비유: `AnimatedSwitcher`나 `Image.asset`을 0.1초마다 8장 갈아끼우는 것과 같은 개념. 다만 Flame은 이걸 위해 위젯 트리를 rebuild하지 않고, **이미 메모리에 올라가 있는 한 장의 큰 PNG에서 보여 줄 영역(rect)만 바꿉니다.**

### 스프라이트 (sprite)

게임 화면에 표시되는 **2D 이미지 한 장** 또는 그 한 장을 화면에 그리는 단위 객체. 어원은 "유령처럼 배경 위에 떠 있는 작은 그림"이라는 의미에서 왔습니다.

Flame에서는 `Sprite` 클래스로 표현되며, "한 장의 정지 그림"을 가리킵니다.

```dart
final sprite = await game.loadSprite('player.png');  // 한 장짜리 정지 이미지
```

`SpriteComponent`에 sprite를 넣으면 화면에 그 그림이 표시됩니다.

### 스프라이트 시트 (sprite sheet) / 텍스처 아틀라스 (texture atlas)

> **사용자 질문 2: "Amount 8이라는 뜻은? 한 이미지에 8개가 들어가 있다는 뜻인가요?"**

**여러 장의 그림(여러 프레임 또는 여러 스프라이트)을 하나의 큰 PNG 파일에 격자 형태로 모아 놓은 것**이 스프라이트 시트입니다. "텍스처 아틀라스(texture atlas)"라고도 부르며 같은 말입니다.

예: 한 프레임이 32×32 픽셀이고 걷기 애니메이션이 8 프레임으로 구성되어 있다면, 다음과 같은 256×32 픽셀 PNG 한 장을 만듭니다.

```
player_walk.png (256 × 32)

┌────┬────┬────┬────┬────┬────┬────┬────┐
│ F0 │ F1 │ F2 │ F3 │ F4 │ F5 │ F6 │ F7 │   ← 세로 32
└────┴────┴────┴────┴────┴────┴────┴────┘
←─── 32×8 = 256 ────→
```

**왜 시트로 모으는가?**

- **로딩 비용**: PNG 8개를 따로 디스크에서 읽고 디코딩하는 것보다 1개를 읽는 것이 압도적으로 빠릅니다.
- **GPU 효율**: GPU에 텍스처를 업로드할 때 한 번에 큰 텍스처 1개를 올려 두고 영역만 다르게 잘라 쓰는 편이 훨씬 빠릅니다. 작은 텍스처를 매번 바꾸면 "draw call"이 늘어 프레임 드랍이 발생합니다.
- **메모리 정렬**: 텍스처는 보통 2의 제곱수(64, 128, 256, 512, 1024) 변 길이를 갖는 편이 GPU에 친화적입니다. 작은 그림을 모아서 큰 시트로 만들면 자연스럽게 그 크기에 맞출 수 있습니다.

> Flutter 비유: 여러 아이콘을 SVG sprite map으로 모으거나, 여러 폰트를 하나의 font atlas로 합치는 것과 같은 발상.

### 텍스처 (texture)

GPU 메모리에 올라간 이미지 데이터. 보통 PNG 한 장이 GPU에 업로드되면 그것이 "텍스처"입니다. 스프라이트 시트는 곧 "한 장의 큰 텍스처"입니다.

게임 코드에서 `Image`라는 단어는 보통 RAM의 디코딩된 픽셀 데이터를, `Texture`는 GPU 메모리의 그 사본을 가리키는 뉘앙스 차이가 있습니다. 다만 Flame 사용 레벨에서는 거의 구분 없이 써도 무방합니다.

---

## 2. 프레임 애니메이션과 Flame 옵션

이제 사용자의 질문에 직접 답할 수 있습니다.

```dart
SpriteAnimationData.sequenced(
  amount: 8,
  stepTime: 0.1,
  textureSize: Vector2(32, 32),
);
```

### amount — "시트에 들어 있는 프레임 개수"

> **사용자 질문**: "amount 8은 한 이미지에 8개가 들어가 있다는 뜻인가요?"

**그렇습니다.** 정확히는 "이 스프라이트 시트 PNG 안에 8개의 프레임이 격자로 들어 있다"는 뜻입니다. Flame은 이 값을 보고 "0번부터 7번까지 잘라서 순환시키면 되겠구나"라고 판단합니다.

`amount`는 행·열 개수가 아니라 **총 프레임 개수**입니다. 시트가 2D 그리드(예: 가로 4 × 세로 2)라면 `SpriteAnimationData.sequenced`에 `amountPerRow: 4`를 함께 넘겨서 Flame이 줄바꿈 위치를 알게 해 줍니다. 시트의 첫 프레임이 (0, 0)이 아니라 일정 오프셋에서 시작한다면 `texturePosition`으로 시작점을 지정할 수 있습니다.

### stepTime — "프레임 하나를 몇 초 동안 보여 줄 것인가"

`stepTime: 0.1`이면 한 프레임을 0.1초씩 보여 줍니다. 즉 초당 10프레임으로 애니메이션이 재생됩니다(`1 / 0.1 = 10`).

- 더 빠른 걷기: `0.05` (초당 20프레임)
- 더 느린 걷기: `0.2` (초당 5프레임)

### textureSize — "시트의 한 칸(한 프레임) 크기"

> **사용자 질문 3: "textureSize는 한 프레임당 사이즈란 뜻인가요?"**

**그렇습니다.** `Vector2(32, 32)`는 "한 프레임이 가로 32픽셀, 세로 32픽셀"이라는 의미입니다. Flame은 이 값을 가지고 시트를 자릅니다.

```
gridX = frameIndex * textureSize.x    // 자를 시작 x 좌표
gridY = 0                              // 가로 시트라면 y는 0
width = textureSize.x                  // 자를 폭
height = textureSize.y                 // 자를 높이
```

따라서 **`textureSize`는 반드시 실제 시트의 한 칸 크기와 정확히 일치해야 합니다.**

- 시트가 256×32이고 8 프레임이라면 → `textureSize = Vector2(32, 32)` ✅
- 시트가 512×64이고 8 프레임이라면 → `textureSize = Vector2(64, 64)` ✅
- 시트가 465×512인데 단일 일러스트라면 → 격자 시트가 아니므로 `textureSize`로 분할 자체가 불가능 ❌

> **사용자가 겪은 사례**: `player_walk.png`(465×512)는 정지 일러스트 한 장이었습니다. 그런데 코드의 `amount: 8, textureSize: Vector2(32, 32)`는 "256×32짜리 가로 8프레임 시트"를 가정한 값이었기 때문에 두 값이 완전히 어긋났습니다. 결과적으로 Flame이 왼쪽 위 32×32(투명 영역일 가능성이 큼)만 잘라 표시해서 캐릭터가 사라진 것처럼 보입니다. 시트와 코드 값은 항상 짝이 맞아야 합니다.

### 시각화

```
amount=8, stepTime=0.1, textureSize=Vector2(32, 32)

┌────┬────┬────┬────┬────┬────┬────┬────┐
│ F0 │ F1 │ F2 │ F3 │ F4 │ F5 │ F6 │ F7 │
└────┴────┴────┴────┴────┴────┴────┴────┘
 ▲                                       
 │  textureSize.x = 한 칸 폭 = 32
 │  textureSize.y = 한 칸 높이 = 32
 │  amount        = 칸 개수 = 8
 │  stepTime      = 한 칸을 보여 주는 시간 = 0.1초
 │
 └─ Flame이 frameIndex * 32 위치에서 32×32만큼 잘라 화면에 그림
    매 0.1초마다 frameIndex가 0 → 1 → 2 → ... → 7 → 0 → ...
```

### 그리드형(2D) 시트

스프라이트 시트가 항상 가로 한 줄인 것은 아닙니다. 예를 들어 4×2 그리드(가로 4 × 세로 2 = 총 8프레임)도 흔합니다. 이런 경우는 `SpriteAnimationData`의 다른 변형이나 직접 인덱싱이 필요합니다. 본 스터디에서는 우선 "가로 한 줄"부터 익숙해진 뒤에 그리드형으로 확장합니다.

---

## 3. 게임 루프 관련 용어

### FPS (frames per second) — 프레임 레이트

**초당 화면이 다시 그려지는 횟수**. 60FPS면 1초에 60번, 30FPS면 1초에 30번 화면이 갱신됩니다.

게임은 보통 60FPS를 목표로 하며, 모바일 일부 기기는 120FPS도 지원합니다. 본 코스의 목표는 안정적인 60FPS입니다.

> Flutter 비유: Flutter도 기본적으로 60FPS로 화면을 vsync에 맞춰 그립니다. 다만 일반 앱은 화면이 변할 때만 다시 그리지만, 게임은 **변하지 않아도 매 프레임 다시 그립니다.** 캐릭터 정지 화면도 같은 그림을 60번/초로 다시 그리고 있는 셈입니다.

### 델타 타임 (delta time, dt)

**이전 프레임이 끝난 시점부터 지금까지 흘러간 시간(초 단위)**. Flame은 매 프레임마다 이 값을 `update(double dt)`의 인자로 넘겨 줍니다.

- 60FPS에서: `dt ≈ 0.0167` (1/60초)
- 30FPS에서: `dt ≈ 0.0333` (1/30초)
- 잠시 끊겨서 한 프레임이 0.1초 걸렸다면: `dt ≈ 0.1`

**왜 중요한가?** 이동 거리를 계산할 때 항상 `dt`를 곱해야 프레임 속도와 무관하게 일정한 속도가 유지됩니다.

```dart
position += velocity * speed * dt;   // ✅ 1초에 항상 speed 픽셀 이동
position += velocity * speed;        // ❌ 빠른 PC에서는 더 빠르게 이동
```

> **큰 dt 주의(스파이크)**: 앱이 백그라운드에 갔다 오거나 무거운 로딩 직후에는 한 프레임의 `dt`가 비정상적으로 커질 수 있습니다(예: 0.5초). 이 값을 그대로 물리에 곱하면 객체가 한 번에 크게 이동해 벽을 뚫고 지나가는 **터널링(tunneling)**이 생깁니다. 그래서 실무에서는 `dt`를 일정 상한으로 잘라 쓰거나(clamp), 큰 `dt`를 작은 고정 간격으로 나눠 여러 번 `update`하는 **고정 시간 간격(fixed timestep)** 기법을 씁니다.

### 게임 루프 (game loop)

게임이 동작하는 무한 반복 사이클. 일반적으로 다음 4단계를 매 프레임 반복합니다.

```
1. 입력 수집 (키보드, 마우스, 터치, 네트워크 패킷)
2. 상태 업데이트 (update(dt) — 좌표 갱신, AI, 물리)
3. 렌더 (render(canvas) — 화면에 그림)
4. 다음 vsync까지 대기
   ↑ 반복
```

Flame이 이 루프를 자동으로 돌려 주며, 개발자는 **2번(`update`)과 3번(`render`)만 작성**하면 됩니다.

> Flutter 비유: Flutter의 `WidgetsBinding.instance.addPersistentFrameCallback`을 매 프레임 호출하는 것과 비슷하지만, Flame은 그것을 `Component.update`/`Component.render`로 추상화하고 자동으로 호출해 줍니다.

### 틱 (tick)

게임 루프의 한 사이클. "60FPS는 60틱/초"라고 표현합니다. **클라이언트 측 프레임**과 **서버 측 시뮬레이션 단위** 양쪽에서 모두 쓰입니다.

- 클라이언트: 보통 60FPS = 60틱 (그래픽과 동기)
- 서버: 더 느림. 보통 20~30틱(=초당 20~30회 시뮬레이션 갱신)이 일반적. Valorant 같은 경쟁 FPS는 128틱.

### update vs render

| | update(dt) | render(canvas) |
|---|---|---|
| **하는 일** | 상태 변경 (좌표 이동, HP 감소, AI 결정) | 화면에 그림 |
| **호출 주기** | 매 프레임 | 매 프레임 (update 직후) |
| **input 인자** | `dt` (이번 프레임에 흐른 시간) | `Canvas` (그릴 캔버스) |
| **무엇을 만지면 안 되는가** | Canvas — 여기서 그리기 명령을 호출하지 않음 | 게임 상태 — 여기서 좌표를 바꾸지 않음 |

**원칙**: `update`에서 "다음 상태"를 결정하고, `render`에서 "현재 상태"를 그립니다. 두 함수의 책임을 섞지 마세요. 섞으면 디버깅이 매우 어려워집니다.

---

## 4. 좌표와 움직임

### Vector2

`(x, y)` 두 숫자를 묶은 2차원 벡터. Flame에서 **위치, 크기, 방향, 속도** 모두 `Vector2`로 표현합니다.

```dart
position = Vector2(100, 200);   // 위치
size = Vector2(40, 40);          // 크기
velocity = Vector2(1, 0);        // 방향 (오른쪽)
```

연산자가 오버로딩되어 있어 `+`, `-`, `*`, `/`를 그대로 사용할 수 있습니다.

```dart
position += velocity * speed * dt;
final dist = (a - b).length;
final dir = (target - position).normalized();
```

### 화면 좌표계

Flutter와 Flame 모두 **왼쪽 위가 (0, 0)** 이고 **y축은 아래로 갈수록 커집니다**. 수학에서 배운 좌표계(y가 위로 +)와 반대이므로 처음에 헷갈릴 수 있습니다.

```
(0, 0) ──── x+ ────►
  │
  │
 y+
  │
  ▼
```

그래서 "위로 이동"은 `y -= 1`이고 "아래로 이동"은 `y += 1`입니다.

### Position

컴포넌트가 화면(또는 부모 컴포넌트) 안에서 위치하는 좌표. `Vector2`로 표현됩니다.

### Anchor

**컴포넌트의 어느 점을 `position`의 기준점으로 삼을 것인가**를 정하는 설정.

- `Anchor.topLeft` (기본값) — 왼쪽 위가 기준. `position`이 (100, 100)이면 컴포넌트의 왼쪽 위 모서리가 (100, 100).
- `Anchor.center` — 중심이 기준. `position`이 (100, 100)이면 컴포넌트의 정중앙이 (100, 100).

캐릭터 같은 객체는 보통 `Anchor.center`를 씁니다. 회전을 시키면 중심을 축으로 돌게 되어 자연스럽습니다.

### Velocity vs Speed

| 단어 | 한국어 | 의미 |
|---|---|---|
| **speed** | 빠르기 | 크기만 (예: 200px/초). 방향 없음. 보통 `double` |
| **velocity** | 속도 | 방향 + 크기. 보통 `Vector2` |

물리에서도 정확히 같은 구분입니다. 한국어로는 일상에서 "속도"와 "빠르기"를 섞어 쓰지만, 게임 코드에서는 둘을 분리하는 편이 명확합니다.

```dart
const speed = 200.0;                // 1초에 200픽셀
final velocity = Vector2(1, 0);     // 오른쪽 방향
final move = velocity * speed * dt; // 이번 프레임에 이동할 양
```

### normalize / normalized

벡터의 **방향은 유지하고 길이를 1로 맞추는 연산**.

- `Vector2(1, 0)` — 이미 길이 1 → 그대로
- `Vector2(1, -1)` — 길이 약 1.414 → 정규화 후 `(0.707, -0.707)`

대각선 이동이 상하좌우보다 빨라지는 문제를 막을 때 항상 사용합니다.

- `normalize()` — 원본 벡터를 직접 변경
- `normalized()` — 새 벡터를 반환, 원본은 그대로

---

## 5. Flame 구조 용어

### Component

Flame에서 **화면에 존재하는 모든 것**의 단위. 캐릭터, 적, 총알, HUD, 배경, 카메라까지 전부 `Component`입니다.

- `PositionComponent` — 위치/크기/회전을 가진 컴포넌트
- `SpriteComponent` — 정지 이미지 한 장을 그리는 컴포넌트
- `SpriteAnimationComponent` — 프레임 애니메이션을 재생하는 컴포넌트
- `SpriteAnimationGroupComponent<T>` — 상태별 여러 애니메이션을 갖고 `current`로 전환하는 컴포넌트

컴포넌트는 트리 구조로 자식을 가질 수 있습니다(부모 컴포넌트 위에 자식 컴포넌트가 얹히는 식).

> Flutter 비유: Widget이 위젯 트리를 구성하듯 Component가 컴포넌트 트리를 구성합니다. 다만 위젯과 달리 컴포넌트는 **rebuild가 아니라 update**로 자기 자신을 갱신합니다.

**생명주기 콜백** — 컴포넌트는 위젯의 `initState`/`dispose`에 대응하는 생명주기 메서드를 가집니다.

| 콜백 | 언제 | Flutter 비유 |
|---|---|---|
| `onLoad()` | 트리에 추가되어 처음 준비될 때 (`async` 가능, 에셋 로딩에 사용) | `initState` + 비동기 초기화 |
| `onMount()` | 부모에 실제로 부착된 직후 | 첫 `build` 직후 |
| `update(dt)` | 매 프레임 | (게임 전용, 위젯엔 없음) |
| `onRemove()` | 트리에서 제거될 때 | `dispose` |

> **자식 컴포넌트에서 게임 객체 접근**: 자식이 부모 게임 인스턴스를 참조할 때는 `HasGameReference<MyGame>` mixin을 붙이고 `game` getter로 접근합니다. 예전 `HasGameRef` mixin과 `gameRef` getter는 flame **1.28.0**에서 deprecate되어, 현재는 `HasGameReference` + `game`이 권장 패턴입니다(결론만 같고 이름이 바뀐 것). ([CHANGELOG #3559](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md))

### World

게임 세상 자체. 캐릭터, 적, 맵 같은 게임 콘텐츠가 들어가는 컴포넌트입니다. **카메라가 보고 있는 대상**이 World입니다.

`FlameGame`은 생성 시점에 `World`를 자동으로 하나 만들어 줍니다. 그래서 `class MyGame extends FlameGame` 안에서 `world.add(player)`처럼 바로 쓸 수 있습니다.

> **최신 충돌 감지 패턴**: 충돌 판정 기능(`HasCollisionDetection`)은 예전처럼 `FlameGame` 본체가 아니라 **`World`에 부여**하는 것이 현재 권장 방식입니다. `CameraComponent` + `World` 구조에서 충돌은 월드 좌표계에서 일어나기 때문입니다. 정적 객체(벽·바닥)가 많은 맵에서는 `HasQuadTreeCollisionDetection`을 World에 부여하면 매 프레임 전수 비교를 피해 성능이 크게 좋아집니다. ([Flame 공식 문서](https://docs.flame-engine.org/latest/))
>
> ```dart
> class MyWorld extends World with HasCollisionDetection { ... }
> ```

### Camera (CameraComponent)

월드의 어느 영역을 화면에 보여 줄지 결정하는 컴포넌트. 캐릭터를 따라가거나(`camera.follow(player)`), 확대/축소(`camera.zoom`), 특정 영역에 가두기(`camera.setBounds(...)`) 등이 가능합니다.

`FlameGame`은 카메라도 자동으로 하나 만들어 줍니다. 미니맵처럼 추가 카메라가 필요할 때만 별도로 만들면 됩니다.

### Viewport

카메라가 그려진 결과를 **화면의 어느 영역에 보여 줄 것인가**를 정하는 부분. 보통 전체 화면을 차지하지만, "화면 오른쪽 위 200×200에 미니맵을 그린다" 같은 경우에는 작은 뷰포트를 만듭니다.

용어 위계:
```
World        — 게임 세상의 콘텐츠 (캐릭터, 맵 등)
  ↓ (어느 영역을 볼지)
Camera       — World를 보는 카메라
  ↓ (그 결과를 화면 어디에 그릴지)
Viewport     — 화면의 특정 사각형 영역
```

### Sprite vs SpriteAnimation

| | Sprite | SpriteAnimation |
|---|---|---|
| 본질 | 정지 이미지 한 장 | 여러 프레임이 시간에 따라 바뀜 |
| 데이터 | 한 장의 그림 영역 | 프레임 배열 + 각 프레임의 표시 시간 |
| 컴포넌트 | `SpriteComponent` | `SpriteAnimationComponent` 또는 `SpriteAnimationGroupComponent` |
| 사용 예 | 배경, 정적 오브젝트 | 걷기, 공격, 폭발 |

### SpriteAnimationGroupComponent\<T\>

**상태별로 서로 다른 애니메이션 여러 개를 미리 등록해 두고, 상태가 바뀔 때 `current` 한 줄로 전환하는 컴포넌트.** 캐릭터는 보통 idle(대기)·walk(걷기)·attack(공격)·hit(피격)·death(사망) 같은 여러 상태를 가지는데, 이를 각각 따로 컴포넌트로 만들지 않고 하나의 컴포넌트가 묶어서 관리합니다.

`<T>`는 상태를 식별하는 타입으로, 보통 `enum`을 씁니다.

```dart
enum HeroState { idle, walk, attack }

final hero = SpriteAnimationGroupComponent<HeroState>(
  animations: {
    HeroState.idle:   idleAnimation,
    HeroState.walk:   walkAnimation,
    HeroState.attack: attackAnimation,
  },
  current: HeroState.idle,
);

// 입력이 들어오면 상태만 바꾸면 끝 — 프레임 전환은 Flame이 알아서
hero.current = HeroState.walk;
```

> Flutter 비유: `Map<상태, 위젯>`을 만들어 두고 `AnimatedSwitcher`의 child를 상태에 따라 갈아끼우는 것과 같은 발상입니다. 다만 여기서는 위젯 rebuild 없이 `current` 필드만 바꾸면 다음 프레임부터 해당 애니메이션이 재생됩니다.

상태가 바뀔 때 애니메이션을 처음(프레임 0)부터 다시 시작하고 싶으면 전환 직후 해당 애니메이션 티커의 `reset()`을 호출합니다. 공격처럼 "한 번만 재생하고 끝나야 하는" 애니메이션은 만들 때 `loop: false`로 두고, 종료 시점에서 idle 상태로 되돌립니다.

---

## 6. 충돌과 게임 로직 용어

### Collider / Hitbox

**충돌 판정용 영역**. 캐릭터의 그림은 64×64일 수 있지만, 충돌 판정은 발 밑 20×10만 사용하는 식으로 분리합니다.

- `RectangleHitbox` — 사각형
- `CircleHitbox` — 원형
- `PolygonHitbox` — 다각형

용어 구분:
- **Collider** — 충돌을 일으키는 쪽 (벽, 바닥)
- **Hitbox** — 맞는 쪽의 판정 영역 (캐릭터의 몸)

다만 Flame에서는 둘을 굳이 구분하지 않고 `Hitbox` 계열을 양쪽 모두에 씁니다.

### Effect

컴포넌트의 속성을 시간에 따라 자동으로 바꾸는 객체. "1초에 걸쳐 위치를 (100, 100)으로 이동", "0.5초간 빨갛게 깜빡임" 같은 변화를 명령적으로 작성하지 않고 선언적으로 처리할 때 사용합니다.

```dart
component.add(MoveEffect.to(Vector2(100, 100), EffectController(duration: 1.0)));
```

> Flutter 비유: `AnimationController` + `Tween` 조합과 비슷한 발상.

### Layer / Priority

여러 컴포넌트가 겹쳐 있을 때 **누가 위에 그려질지** 결정하는 값.

- `priority` 값이 클수록 위에 그려집니다(나중에 그려져 위를 덮음).
- 같은 부모 안에서 형제 컴포넌트들은 `priority` 오름차순으로 렌더됩니다.

> Flutter 비유: `Stack`의 자식 순서(나중 자식이 위)나 `Material`의 `elevation`으로 그리는 순서를 정하는 것과 같은 개념입니다.

### Y-sort (깊이 정렬)

**2.5D(쿼터뷰/아이소메트릭) 게임에서 "화면 아래쪽에 있는 객체일수록 앞(위)에 그려져야" 자연스러운 가림 효과가 나는 규칙.** 캐릭터가 나무보다 화면 아래에 서 있으면 캐릭터가 나무 앞에 보여야 하고, 위에 서 있으면 나무 뒤로 가려져야 합니다.

이를 위해 매 프레임 각 객체의 **발 밑 y좌표**(보통 `position.y` 또는 anchor 기준 바닥 좌표)를 `priority`에 대입합니다.

```dart
@override
void update(double dt) {
  super.update(dt);
  priority = y.toInt();   // y가 큰(아래에 있는) 객체일수록 priority↑ → 앞에 그려짐
}
```

매 프레임 모든 객체의 `priority`를 바꾸면 정렬 비용이 들기 때문에, 실제로는 **움직이는 객체만** 갱신하고 고정 객체는 처음 한 번만 설정합니다. Tiled 맵을 쓸 때는 캐릭터가 들어가는 레이어에서만 Y-sort를 적용합니다. 자세한 정렬 전략은 [03-phase3-isometric-2.5d.md](./03-phase3-isometric-2.5d.md)에서 다룹니다.

### 입력 이벤트 (TapCallbacks / DragCallbacks / HoverCallbacks)

컴포넌트가 직접 탭·드래그·호버 입력을 받게 해 주는 **mixin**. 받고 싶은 컴포넌트에 붙이면 콜백 메서드를 오버라이드할 수 있습니다.

```dart
class Button extends PositionComponent with TapCallbacks {
  @override
  void onTapDown(TapDownEvent event) {
    // event.localPosition — 이 컴포넌트 기준 좌표
    // event.canvasPosition — 화면 기준 좌표
    // event.continuePropagation = true; // 아래(다른 컴포넌트)로도 이벤트 전달
  }
}
```

> 예전 `Tappable` / `Draggable` / `Hoverable` mixin은 deprecated이며, 현재는 단일 event 객체(`TapDownEvent` 등)를 받는 `TapCallbacks` / `DragCallbacks` / `HoverCallbacks`가 권장 API입니다. ([Flame 입력 문서](https://docs.flame-engine.org/latest/flame/inputs/tap_events.html))

> Flutter 비유: `GestureDetector`의 `onTapDown`/`onPanUpdate`에 대응합니다. 다만 위젯이 아니라 게임 컴포넌트 자체가 히트 영역을 갖고 이벤트를 받습니다.

---

## 7. 에셋(Asset) 관련 용어

### Asset

게임이 사용하는 외부 파일. 이미지, 사운드, 폰트, 데이터(JSON, TMX) 모두 에셋입니다.

Flutter처럼 `pubspec.yaml`의 `assets:` 항목에 등록해야 빌드 결과물에 포함됩니다.

### Atlas (다시)

스프라이트 시트의 다른 이름. **Texture Atlas**라고 부르면 GPU 텍스처 관점에서 같은 그림을 가리킵니다.

실전에서 atlas가 중요한 이유는 **draw call 배칭** 때문입니다. 같은 텍스처에서 잘라 그리는 스프라이트들은 GPU에 "이 텍스처로 이것들 한꺼번에 그려"라고 한 번에(=draw call 1회) 보낼 수 있습니다. 객체가 서로 다른 텍스처를 쓰면 텍스처를 바꿀 때마다 draw call이 새로 생겨 프레임이 떨어집니다. 그래서 함께 등장하는 객체들은 한 atlas에 모으는 것이 정석입니다.

- **만드는 도구**: 무료인 GDX Texture Packer, CodeAndWeb TexturePacker(유료), Flame 팀의 오픈 에디터 FireAtlas 등.
- **불러오는 패키지**: `flame_texturepacker`(TexturePacker 산출물 로딩), `flame_fire_atlas`(FireAtlas 산출물 로딩). 둘 다 atlas 메타데이터(각 스프라이트의 이름·위치·크기)를 읽어 이름으로 스프라이트를 꺼내 쓰게 해 줍니다.
- **seam(이음새) 주의**: 카메라를 확대하거나 서브픽셀 위치에 그릴 때, 인접 타일의 색이 한 줄 새어 나와 가는 흰 선이 보이는 artifact가 생길 수 있습니다. flame 1.37.0의 `SpriteBatch` `bleed` 옵션으로 이 seam을 줄일 수 있습니다. ([CHANGELOG #3871](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md))

### loadSprite / images.load

| 메서드 | 반환 | 용도 |
|---|---|---|
| `game.loadSprite('a.png')` | `Sprite` | 정지 이미지 한 장으로 바로 사용 |
| `game.images.load('a.png')` | `Image` | 스프라이트 시트처럼 직접 영역을 잘라 쓸 때. 보통 `SpriteAnimation.fromFrameData`와 함께 |

---

## 8. 멀티플레이 용어 (Phase 5 이후에 자주 등장)

지금은 외울 필요 없으나, 코드를 읽다 마주칠 때 이 표를 다시 보세요.

| 용어 | 의미 |
|---|---|
| **Client / Server Authority** | 게임 상태의 진실을 누가 결정하는가. MMO는 항상 Server Authority |
| **Tick / Tick rate** | 서버가 초당 몇 회 시뮬레이션을 갱신하는가 (20~60Hz가 일반) |
| **Snapshot** | 어느 시점의 서버 상태 전체 또는 일부를 직렬화한 패킷 |
| **Prediction** | 서버 응답을 기다리지 않고 클라가 자기 입력을 미리 적용 |
| **Reconciliation** | 서버 응답을 받은 뒤 클라의 예측이 빗나간 부분만 보정 |
| **Lag compensation** | 서버가 과거 시점으로 되감아 히트 판정을 다시 함 |
| **AoI (Area of Interest)** | 한 플레이어가 "볼 수 있어야 하는" 다른 엔티티들의 집합 |
| **Interest Management** | AoI를 효율적으로 계산하고 패킷 전송량을 줄이는 시스템 |
| **RTT (Round Trip Time)** | 패킷이 왕복하는 시간 (보통 30~150ms) |
| **Jitter** | RTT의 흔들림(분산). 핑이 평균은 좋아도 들쭉날쭉하면 보간이 깨짐 |

표만으로는 감이 안 오는 핵심 4가지를 풀어 설명합니다. 알고리즘 원형은 대부분 [Gabriel Gambetta의 "Fast-Paced Multiplayer" 시리즈](https://www.gabrielgambetta.com/client-server-game-architecture.html)에서 정립된 것입니다.

### Prediction & Reconciliation (예측과 보정)

네트워크 게임의 딜레마: 서버가 진실(Authority)인데, 입력을 서버에 보내고 결과를 받기까지 RTT(예: 100ms)를 기다리면 키를 눌러도 캐릭터가 0.1초 뒤에 움직여 답답합니다.

- **Client-side Prediction(예측)**: 클라이언트가 서버 응답을 기다리지 않고 **자기 입력을 즉시 화면에 반영**합니다. 이때 보낸 입력마다 **시퀀스 번호(sequence number)**를 붙여 두고, 아직 서버 확인을 못 받은 입력들을 `pending` 큐에 보관합니다.
- **Server Reconciliation(보정)**: 서버가 "네 입력 N번까지 처리했고 결과 위치는 여기야"라고 스냅샷을 보내면, 클라이언트는 ① 위치를 서버 값으로 되돌리고 ② `pending`에서 시퀀스 ≤ N인 입력을 제거한 뒤(`pending.removeWhere((p) => p.seq <= lastSeq)`) ③ **아직 처리 안 된 나머지 입력을 다시 적용(rollback & replay)**합니다. 예측이 맞았으면 화면이 안 튀고, 어긋났으면 그 차이만큼만 살짝 보정됩니다.

> Flutter 비유: optimistic UI 업데이트와 동일한 사고방식입니다. 버튼을 누르면 서버 응답 전에 UI를 먼저 바꾸고(예측), 서버 응답이 다르면 롤백·재적용(보정)하는 패턴.

### Entity Interpolation (다른 플레이어 보간)

내 캐릭터는 예측하지만, **남의 캐릭터는 예측하지 않고 과거를 부드럽게 재생**합니다. 스냅샷이 30Hz로 띄엄띄엄 오므로, 받은 스냅샷들 사이를 시간으로 보간해 매끄럽게 움직입니다.

- 이를 위해 일부러 **렌더링을 약간 과거로 지연**시킵니다(interpolation delay). 권장 버퍼는 보통 스냅샷 2개 간격 이상(예: 30Hz면 약 66ms) + jitter 여유. 실무에서는 100~200ms 구간에서 측정된 RTT/jitter에 맞춰 **adaptive**하게 조정하며, 고정 0.2초 하드코딩보다 측정 기반 조정을 권장합니다. 버퍼가 비면(언더런) 마지막 스냅샷을 외삽(extrapolation)합니다. ([Source Multiplayer Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking))

### Lag Compensation (지연 보상)

발사 판정 같은 즉시성 게임에서, 서버는 "쏜 클라이언트가 **그 순간 화면에서 봤던 과거 시점**"으로 다른 객체들을 되감아(rewind) 히트를 판정합니다. 그래서 핑이 높아도 "분명히 맞췄는데 안 맞는" 문제가 줄어듭니다.

- 되감기 한도는 무한하지 않습니다. 예로 [SnapNet](https://www.snapnet.dev/docs/core-concepts/input-delay-vs-rollback/)의 기본 튜닝값은 minimum input delay 0ms, maximum input delay 50ms(이를 넘으면 예측 시작), maximum predicted time 100ms입니다.
- **Peeker advantage(코너에서 먼저 본 사람이 유리한 현상)**: Riot의 Valorant 분석(128-tick, RTT 35ms 조건)에서 클라이언트 프레임레이트가 높을수록 업데이트를 더 빨리 받아 이 격차가 줄어듭니다.

  | 클라이언트 FPS | peeker advantage |
  |---|---|
  | 60 FPS | 약 141ms |
  | 144 FPS | 약 71ms (약 49% 감소) |

  ([Peeking into VALORANT's Netcode](https://www.riotgames.com/en/news/peeking-valorants-netcode))

### AoI & Interest Management (관심 영역)

MMO에서 1000명이 접속해도 한 플레이어에게는 주변 수십 명만 보내면 됩니다. **월드를 격자(uniform grid)로 나누고, 플레이어가 속한 셀과 인접 8개를 합친 9개 셀(3×3)만 검색**해 주변 엔티티를 추려 업데이트를 전송하는 방식이 표준입니다. 객체 좌표가 연속적이면 quad-tree(2D)·octree(3D)로 색인하고, 대규모에서는 zone server(영역별 담당 서버)로 분산합니다. ([Interest Management](https://www.dynetisgames.com/2017/04/05/interest-management-mog/))

### Clock Synchronization (시계 동기화)

예측·보간·지연 보상 모두 "클라이언트와 서버가 같은 시각을 공유한다"는 전제 위에 섭니다. NTP 방식으로 오프셋을 구합니다. 클라가 `t0`에 보내고, 서버가 `t1`에 받아 `t2`에 응답, 클라가 `t3`에 수신하면:

```
RTT          = (t3 - t0) - (t2 - t1)
clock offset = ((t1 - t0) + (t2 - t3)) / 2
serverTimeNow() = clientNow() + offset
```

여러 샘플 중 **RTT가 가장 작은 샘플의 offset**을 채택하면 jitter 영향을 줄일 수 있습니다.

### 신뢰성 UDP / KCP (참고)

실시간 게임은 순서·재전송을 보장하는 TCP의 head-of-line blocking을 피해 UDP 위에 자체 신뢰 계층을 얹기도 합니다. KCP가 대표적인데, 손실이 있는 환경에서 ENet 대비 **약 3~3.5배**(실측 평균 RTT 약 40ms vs 약 139ms) 빠르게 회복합니다. 대신 TCP보다 대역폭을 10~20% 더 씁니다. (흔히 "10배"라고 과장되지만 실측은 3배대입니다. [출처](https://paytonturnage.com/writing/latency-of-reliable-streams/))

---

## 9. Flutter 개발자가 가장 헷갈리는 5가지

| 헷갈림 | 정리 |
|---|---|
| **"위젯이 곧 컴포넌트인가?"** | 비슷한 위계지만 갱신 모델이 다름. 위젯은 rebuild, 컴포넌트는 `update(dt)`. setState 대신 좌표를 직접 변경 |
| **"setState 없이 어떻게 화면이 갱신되는가?"** | Flame이 매 프레임 자동으로 `render`를 호출하기 때문. 좌표만 바꾸면 다음 프레임에 그 자리로 그려짐 |
| **"Provider/Riverpod으로 캐릭터 HP를 관리해도 되는가?"** | 매 프레임 변하는 값은 Provider 금지. Provider는 메뉴/HUD/메타 데이터 전용. 게임 내부 상태는 Component가 직접 보유 |
| **"async/await로 공격 처리해도 되는가?"** | 게임 루프 안에서는 금지. async는 onLoad, 네트워크, 파일 I/O 전용. 게임 로직은 동기 + 상태 머신으로 |
| **"build()가 없으면 어디에 쓰는가?"** | build() 대신 `render(canvas)`. 단 그곳에선 좌표를 바꾸지 않고 **현재 좌표대로 그리기만** 함 |

---

## 10. 더 깊이 들어가고 싶다면

- [00-prereq-flutter-to-flame.md](./00-prereq-flutter-to-flame.md) — Flutter 위젯 패러다임과 Flame 컴포넌트 패러다임의 차이를 자세히
- [01-phase1-flame-basics.md](./01-phase1-flame-basics.md) — Component, GameLoop, Camera의 구조적 학습
- [02-phase2-2d-action.md](./02-phase2-2d-action.md) — Sprite, Animation, Collision의 실전 사용
- [03-phase3-isometric-2.5d.md](./03-phase3-isometric-2.5d.md) — Y-sort, Tiled, 아이소메트릭 좌표 변환
- [04-phase4-rpg-systems.md](./04-phase4-rpg-systems.md) — 상태 머신, SpriteAnimationGroupComponent, RPG 스탯/스킬 시스템
- [05-phase5-multiplayer.md](./05-phase5-multiplayer.md) — Prediction/Reconciliation/Interpolation/Lag compensation 실전
- [example/hello_game_vector2_velocity.md](./example/hello_game_vector2_velocity.md) — Vector2와 velocity 입문 예제
- [example/hello_game_keyboard_movement.md](./example/hello_game_keyboard_movement.md) — 키보드 입력으로 사각형 움직이기 전체 흐름

이 용어집은 학습 중에 새 단어를 마주칠 때마다 추가해 나가시면 됩니다. "여기 없는 단어를 만났는데 짚이는 게 없다"는 순간이 본 문서를 확장할 신호입니다.
