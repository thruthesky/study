# HelloGame 예제: 게임 맵(world)에 기물 배치하기 — 그리고 제대로 된 맵 만들기

이 문서는 `lib/main.dart`에 있는 Flame 예제 코드를 설명합니다.
[hello_game_walking_animation.md](hello_game_walking_animation.md)의 다음 단계로,
**움직이는 플레이어가 사는 "게임 맵(world)"에 나무·꽃나무·분수 같은 정지 기물을
배치**하는 방법을 다룹니다.

이전 단계까지는 화면에 **플레이어 한 명**만 있었습니다. 이번 단계는 그 플레이어가
**돌아다닐 수 있는 공간(맵)을 채우는 것**, 그리고 더 나아가 **"제대로 된 게임 맵은
어떻게 설계하는가"** 를 배우는 것이 목표입니다.

> **소스 코드 사본**: 이 문서가 설명하는 시점의 `lib/main.dart`는
> [hello_game_map_objects/lib/main.dart](hello_game_map_objects/lib/main.dart)에
> 그대로 복사되어 있습니다. 본 프로젝트의 `lib/main.dart`는 학습이 진행되며
> 계속 바뀌므로, 이 문서를 읽을 때는 사본 쪽을 참고하시면 됩니다.

---

## 0. 학습 목표

이 예제를 끝까지 따라가면 다음을 설명할 수 있게 됩니다.

1. **Flame에서 "게임 맵"의 정체는 무엇인가** — 왜 `world`가 곧 맵인가
2. **정지 기물에는 `SpriteComponent`, 움직이는 캐릭터에는 `SpriteAnimationGroupComponent`** 를 쓰는 이유
3. **`world.add(...)`로 맵에 기물을 놓는 패턴** — 플레이어를 추가한 것과 완전히 동일함
4. **`position`·`anchor`·`size`로 기물을 배치하고 크기를 정하는 법**
5. **(핵심) 게임 맵을 만드는 4가지 방법과 각각의 적합한 규모**
6. **맵이 커질 때 무너지지 않는 구조** — 데이터 분리, 렌더 순서, 타일맵, 청크/컬링

1~4가 이번 코드의 직접 설명이고, 5~6은 이 문서의 후반부에서 다루는
**"제대로 된 게임 맵 만들기"** 입니다.

---

## 1. 가장 먼저: "게임 맵"은 따로 있는 클래스가 아니다

Flame을 처음 배울 때 가장 자주 하는 오해가 **"맵을 그리려면 `GameMap` 같은 클래스를
따로 만들어야 한다"** 는 생각입니다. 결론부터 말하면 **아닙니다.**

`FlameGame`은 만들어지는 순간 다음 두 가지를 자동으로 갖춥니다.

```text
FlameGame (= MyGame)
├── world   ← 게임 세계(좌표 공간) 그 자체. 이것이 곧 "맵"이다.
│            모든 기물(플레이어, 나무, 분수…)이 이 안에 산다.
└── camera  ← world를 들여다보는 카메라. 플레이어를 따라다닌다.
```

즉 **`world`가 곧 게임 맵**입니다. 우리가 할 일은 새 맵 클래스를 만드는 게 아니라,
이 `world`에 기물을 `add()` 하는 것뿐입니다. 그리고 그 방식은 이전 단계에서
**플레이어를 추가한 것과 글자 그대로 똑같습니다.**

```dart
await world.add(player);   // 플레이어를 맵에 올린다 (이전 단계)
await world.add(Tree());   // 나무를 맵에 올린다 (이번 단계) — 패턴이 같다
```

> **카메라와 월드를 나누는 이유**: 만약 모든 것을 화면 좌표에 직접 그리면, 플레이어가
> 움직일 때 나무·분수의 좌표를 일일이 다시 계산해야 합니다. Flame은 "기물은 **월드
> 좌표**에 고정해 두고, **카메라만 움직여** 그 월드를 비춘다"는 구조라서, 플레이어가
> 이동해도 나무의 `position`은 영원히 그대로입니다. 화면에서 나무가 흘러가는 것처럼
> 보이는 건 **카메라가 움직이기 때문**이지 나무가 움직이는 게 아닙니다.

---

## 2. 이번 코드에서 추가된 것

이번 단계에서 [main.dart](hello_game_map_objects/lib/main.dart)에 추가된 것은 다음 두 가지뿐입니다.

**(1) `onLoad`에서 기물 3개를 맵에 추가**

```dart
await world.add(player);

// world가 곧 "게임 맵". 여기에 add() 하면 맵 위에 기물이 놓인다.
await world.add(Tree()..position = size / 2 + Vector2(150, -100));
await world.add(Fountain()..position = size / 2 + Vector2(-100, 50));
await world.add(FlowerTree()..position = size / 2 + Vector2(200, -80));

camera.follow(player);
```

**(2) 정지 기물 컴포넌트 3종 클래스 정의**

```dart
class Tree extends SpriteComponent with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    sprite = await game.loadSprite('tree.png');
    size = Vector2(64, 128);
    anchor = Anchor.center;
  }
}
// FlowerTree, Fountain도 로드하는 PNG와 size만 다를 뿐 구조가 동일하다.
```

이게 전부입니다. 맵을 그리는 데 특별한 마법은 없습니다.

---

## 3. 왜 `SpriteComponent`인가 — 플레이어와 무엇이 다른가

플레이어는 `SpriteAnimationGroupComponent`였는데, 나무·분수는 왜 더 단순한
`SpriteComponent`를 쓸까요? 기물의 **성격이 다르기 때문**입니다.

| | 플레이어 | 나무·꽃나무·분수 |
|---|---|---|
| 컴포넌트 | `SpriteAnimationGroupComponent` | `SpriteComponent` |
| 그림 | 상태별 여러 애니메이션 (idle/walk) | 정지 이미지 1장 |
| 움직임 | 매 프레임 `applyInput`으로 이동 | 고정 (한 번 놓으면 끝) |
| 입력 | 키보드 입력 처리 | 없음 |

**규칙은 간단합니다.**
- **그림 1장으로 충분하고 움직이지 않는다** → `SpriteComponent`
- **상태에 따라 그림이 바뀌거나 애니메이션이 필요하다** → `SpriteAnimationGroupComponent`

> **분수는 물이 흐르는데 정지 이미지여도 되나?** 지금은 정지 PNG입니다. 나중에
> 물이 찰랑이는 애니메이션을 넣고 싶으면 `Fountain`을 `SpriteAnimationComponent`로
> 바꾸고 스프라이트 시트를 물려 주면 됩니다. **기물의 클래스만 교체하면 되고,
> `world.add(Fountain())` 호출부는 그대로**라는 점이 컴포넌트 설계의 장점입니다.

### `loadSprite` vs `images.load` — 헷갈리는 한 줄

```dart
sprite = await game.loadSprite('tree.png');         // ✅ 바로 Sprite 반환
```

플레이어 코드에서는 `game.images.load('player.png')`로 `Image`를 받은 뒤
`SpriteAnimation.fromFrameData`에 넘겼습니다. 정지 기물은 애니메이션이 필요 없으니
한 단계 짧은 `loadSprite`를 씁니다.

```dart
// game.images.load는 Image를 반환 → 직접 Sprite로 감싸야 함
final image = await game.images.load('tree.png');
sprite = Sprite(image);
// game.loadSprite는 위 두 줄을 대신 해 줌 → 한 줄로 끝
sprite = await game.loadSprite('tree.png');
```

> **흔한 실수**: `sprite = Sprite(await game.loadSprite('tree.png'))` — `loadSprite`가
> 이미 `Sprite`를 반환하는데 또 `Sprite(...)`로 감싸면 타입 에러가 납니다.
> `Sprite()` 생성자는 `Image`를 받지 `Sprite`를 받지 않기 때문입니다.

---

## 4. `position`·`anchor`·`size` — 기물을 어디에, 어떻게 놓는가

```dart
await world.add(Tree()..position = size / 2 + Vector2(150, -100));
```

- **`position`** — 월드 좌표에서 기물의 위치. `size / 2`는 게임 시작 시
  플레이어가 있는 화면 중앙이고, 거기서 `Vector2(150, -100)`만큼(오른쪽 150,
  위로 100) 떨어뜨려 놓습니다. `position`을 안 주면 `(0, 0)`(월드 원점)에 놓입니다.
- **`anchor = Anchor.center`** — `position`이 기물의 **중심**을 가리키게 합니다.
  기본값은 `topLeft`라서, anchor를 안 바꾸면 `position`이 기물의 왼쪽 위 모서리가
  됩니다. 중심 기준이 배치 계산이 직관적입니다.
- **`size`** — 화면에 그릴 크기(픽셀). 원본 PNG 크기와 무관하게 이 값으로
  스케일됩니다. 나무는 `64×128`(세로로 긴 나무), 분수는 `256×256`(큰 구조물).

> **좌표 감각**: Flame의 y축은 **아래로 갈수록 커집니다**(화면 좌표 관례).
> 그래서 "위로 100" 이동은 `y - 100`, 즉 `Vector2(150, -100)`의 `-100`입니다.

---

이제부터가 이 문서의 핵심입니다. 위 코드는 "기물 3개를 손으로 놓은" 가장 작은
맵입니다. 실제 게임의 맵은 이것보다 훨씬 커지고 복잡해집니다. **어떻게 만들 수
있고, 어떻게 만들어야 좋으며, 커졌을 때 어떻게 감당하는가**를 차례로 봅니다.

---

## 5. 게임 맵을 "어떻게 만들 수 있는가" — 4가지 방법

같은 맵이라도 규모와 목적에 따라 만드는 방법이 다릅니다. 가장 단순한 것부터
가장 본격적인 것까지 4단계로 정리합니다.

### 5.1 방법 A — 손으로 하나씩 `add` (지금 방식)

```dart
await world.add(Tree()..position = Vector2(300, 100));
await world.add(Fountain()..position = Vector2(150, 250));
```

- **언제**: 기물이 몇 개 안 되는 프로토타입, 학습, 테스트 화면.
- **장점**: 가장 직관적. 지금 당장 이해되는 코드.
- **한계**: 기물이 20개만 넘어가도 `onLoad`가 `add` 호출로 도배됩니다. 좌표가
  코드에 흩어져 있어 "나무를 5px 옮겨 줘" 같은 요청에 코드를 뒤져야 합니다.

### 5.2 방법 B — 데이터로 기술하고 반복문으로 배치

좌표·종류를 **데이터(리스트/JSON)** 로 분리하고, 코드는 그 데이터를 순회하며
`add`만 합니다. **로직과 데이터를 분리**하는 첫걸음입니다.

```dart
// "무엇을 어디에"는 데이터로 기술한다
final mapObjects = [
  (type: 'tree',     pos: Vector2(300, 100)),
  (type: 'tree',     pos: Vector2(360, 140)),
  (type: 'fountain', pos: Vector2(150, 250)),
  (type: 'flower',   pos: Vector2(420, 80)),
];

// 코드는 데이터를 읽어 기물을 만들기만 한다
for (final o in mapObjects) {
  final component = switch (o.type) {
    'tree'     => Tree(),
    'fountain' => Fountain(),
    'flower'   => FlowerTree(),
    _          => throw 'unknown type: ${o.type}',
  };
  await world.add(component..position = o.pos);
}
```

- **언제**: 기물이 수십~수백 개. 맵을 자주 수정하는 단계.
- **장점**: 좌표 데이터를 JSON 파일로 빼면 **코드 수정 없이 맵을 바꿀 수** 있습니다.
  맵 여러 개(마을, 던전)를 데이터 파일만 갈아끼워 전환할 수 있습니다.
- **한계**: 좌표를 여전히 숫자로 손으로 적어야 합니다. 큰 맵은 눈으로 배치를
  가늠하기 어렵습니다 → 방법 D(타일맵 에디터)로 넘어갈 때.

### 5.3 방법 C — 커스텀 `World` 클래스로 맵을 캡슐화

맵을 채우는 로직을 `MyGame.onLoad`에서 꺼내, **`World`를 상속한 전용 클래스**로
옮깁니다. 게임 본체와 맵 구성 책임을 분리합니다.

```dart
class VillageWorld extends World with HasGameReference<MyGame> {
  @override
  Future<void> onLoad() async {
    await add(Tree()..position = Vector2(300, 100));
    await add(Fountain()..position = Vector2(150, 250));
    // ... 마을 맵을 채우는 모든 로직이 여기에 모인다
  }
}

// MyGame에서는 기본 world 대신 이 월드를 끼운다
class MyGame extends FlameGame with KeyboardEvents {
  MyGame() : super(world: VillageWorld());
}
```

- **언제**: 맵이 여러 종류이고(마을/던전/필드), 맵마다 등장 기물·로직이 다를 때.
- **장점**: `world = DungeonWorld()`처럼 **맵 전체를 통째로 교체**할 수 있습니다.
  맵 전환(마을 → 던전)이 깔끔해집니다. 맵별 코드가 한 클래스에 모입니다.
- **한계**: 여전히 기물 배치는 코드/데이터로 해야 합니다. 이 방법은 "맵을 어떻게
  **구성·교체**하는가"의 해결책이지 "기물을 어떻게 **그리는가**"의 해결책은 아닙니다.

### 5.4 방법 D — 타일맵 에디터(Tiled) + `flame_tiled`

본격적인 2D/2.5D 게임의 표준 방식입니다. [Tiled](https://www.mapeditor.org/)라는
**무료 맵 에디터**로 타일을 마우스로 칠해 맵을 그리고, `.tmx` 파일로 내보낸 뒤,
`flame_tiled` 패키지로 게임에 불러옵니다.

```dart
// pubspec.yaml: flame_tiled 의존성 추가 필요
import 'package:flame_tiled/flame_tiled.dart';

@override
Future<void> onLoad() async {
  final map = await TiledComponent.load('village.tmx', Vector2.all(32));
  await world.add(map);          // 타일맵 전체가 한 번에 맵에 깔린다
}
```

- **언제**: 진짜 게임 맵. 바닥 타일 + 장식물 + 충돌 영역 + NPC 스폰 지점까지
  한 에디터에서 그릴 때.
- **장점**:
  - **시각적 편집** — 좌표를 숫자로 적는 대신 마우스로 그립니다.
  - **레이어** — 바닥/장식/지붕을 레이어로 나눠 렌더 순서를 관리합니다.
  - **오브젝트 레이어** — "여기는 충돌", "여기서 적이 스폰" 같은 메타데이터를
    맵에 직접 표시하고 코드로 읽어옵니다.
  - 이 프로젝트가 목표하는 **2.5D 아이소메트릭 맵**도 Tiled가 지원합니다
    (자세한 내용은 [03-phase3-isometric-2.5d.md](../03-phase3-isometric-2.5d.md)).
- **한계**: 도구를 새로 배워야 합니다. 작은 화면 하나 만드는 데는 과합니다.

### 정리 — 규모에 맞는 방법 고르기

| 규모 | 방법 | 한 줄 요약 |
|---|---|---|
| 기물 ~10개, 학습/테스트 | A. 손으로 `add` | 지금 이 코드 |
| 기물 수십~수백, 맵 자주 수정 | B. 데이터 + 반복문 | 좌표를 데이터로 분리 |
| 맵이 여러 종류, 통째로 전환 | C. 커스텀 `World` | 맵을 클래스로 캡슐화 |
| 진짜 게임 맵 | D. Tiled + `flame_tiled` | 에디터로 그린다 |

**중요**: 이건 "넷 중 하나를 고르는" 문제가 아닙니다. 실전에서는 **D(타일맵)로
바닥·지형을 깔고, C(커스텀 World)로 맵을 캡슐화하며, B(데이터)로 NPC·아이템 스폰을
관리하는** 식으로 **함께 씁니다.**

---

## 6. 게임 맵을 "어떻게 만들면 좋은가" — 4가지 설계 원칙

방법을 알았다면, 이제 **잘 만드는 법**입니다. 작은 맵에서는 안 보이지만 맵이
커지면 반드시 발목을 잡는 4가지를 미리 지킵니다.

### 6.1 데이터와 코드를 분리하라 (좌표를 코드에 박지 마라)

방법 B에서 본 원칙입니다. 좌표·종류 같은 **"맵이 무엇으로 이뤄졌는가"는 데이터**,
**"기물을 어떻게 그리는가"는 코드**로 나눕니다. 그래야:

- 기획자/디자이너가 코드를 몰라도 맵(데이터 파일)을 수정할 수 있습니다.
- 맵 A/B/C를 데이터만 바꿔 전환할 수 있습니다.
- 코드는 "Tree를 그린다"는 한 가지 책임만 가집니다.

### 6.2 렌더 순서를 지배하라 — `priority`와 y-정렬

2D/2.5D 맵의 핵심 문제: **무엇을 먼저 그리고 무엇을 나중에 그리는가.**
나중에 그린 것이 위에 덮입니다. 순서를 방치하면 플레이어가 나무 **앞**에 있어야
하는데 나무에 가려지는 버그가 생깁니다.

```dart
// priority가 클수록 나중에(위에) 그려진다
await world.add(Floor()..priority = 0);    // 바닥 — 항상 맨 아래
await world.add(Tree()..priority = 1);
await world.add(player..priority = 2);     // 플레이어 — 기물 위에
```

2.5D에서는 한 걸음 더 나아가 **y좌표가 큰(화면 아래쪽 = 더 가까운) 기물을 나중에
그리는 "y-sorting"** 을 씁니다. 그래야 플레이어가 나무보다 위(뒤)에 서면 나무에
가려지고, 아래(앞)에 서면 나무를 가립니다.

```dart
// 매 프레임 또는 이동 시: y가 클수록 위에 그려지도록 priority 갱신
component.priority = component.position.y.toInt();
```

> 이 y-sorting은 2.5D 비주얼의 핵심이라 별도 문서에서 깊게 다룹니다 →
> [03-phase3-isometric-2.5d.md](../03-phase3-isometric-2.5d.md). 지금은 "맵에서
> 렌더 순서는 우연에 맡기지 말고 `priority`로 명시적으로 지배한다"만 기억하세요.

### 6.3 좌표계를 하나로 통일하라 — 월드 좌표 기준

기물의 `position`은 **월드 좌표**(맵 안에서의 절대 위치)여야 합니다. 화면 좌표
(`size / 2` 같은)로 배치하면, 카메라가 움직이는 순간 좌표 계산이 꼬입니다.

이번 예제는 학습 편의상 `size / 2`(화면 중앙)를 기준으로 기물을 놓았지만, 이건
"게임 시작 순간 플레이어가 화면 중앙에 있다"는 가정에 기댄 편법입니다. 맵이 커지면
**기물은 `Vector2(1200, 800)`처럼 월드 절대 좌표로 박고**, 플레이어 시작 위치도
월드 좌표로 정하는 것이 정석입니다.

### 6.4 맵에 경계를 줘라 — 카메라가 허공을 비추지 않게

맵은 무한하지 않습니다. 카메라가 맵 밖의 빈 공간을 비추지 않도록 **카메라에 경계**를
줍니다.

```dart
// 카메라가 (0,0)~(2000,1500) 월드 영역 밖으로 나가지 않도록 고정
camera.setBounds(Rectangle.fromLTRB(0, 0, 2000, 1500));
```

플레이어도 마찬가지로 맵 밖으로 못 나가게 `position.clamp(...)`로 가둡니다.

---

## 7. 맵이 "복잡해질 때" — 무너지지 않는 구조 만들기

맵에 기물이 수백, 수천 개가 되고, 맵 자체가 화면보다 수십 배 커지면, 위 원칙만으로는
부족합니다. **성능**과 **관리 가능성**이 동시에 무너지기 시작합니다. 이때 필요한
기법들입니다.

### 7.1 컬링(Culling) — 화면 밖 기물은 그리지 마라

기물이 10,000개라도 **화면에 보이는 건 수십 개**뿐입니다. 나머지를 매 프레임
그리려 시도하면 GPU가 낭비됩니다. **카메라 시야 밖 컴포넌트의 렌더를 건너뛰는 것**이
컬링입니다.

- Flame의 `CameraComponent`는 보이는 영역(viewfinder) 정보를 제공하므로, 기물의
  `position`이 그 영역 밖이면 렌더를 스킵하도록 처리할 수 있습니다.
- 핵심 효과: **렌더 비용이 "맵 전체 기물 수"가 아니라 "화면에 보이는 기물 수"에
  비례**하게 됩니다.

### 7.2 청크(Chunk) 분할 — 맵을 격자로 쪼개 필요한 부분만 로드

거대한 오픈월드는 통째로 메모리에 올리지 않습니다. 맵을 일정 크기 격자(청크)로
나누고, **플레이어 주변 청크만 로드**하고 멀어진 청크는 언로드합니다.

```text
┌────┬────┬────┬────┐
│    │ ▓▓ │ ▓▓ │    │   ▓▓ = 현재 로드된 청크 (플레이어 주변 3×3)
│    │ ▓▓ │ ▓▓ │    │   빈칸 = 언로드 (메모리에 없음)
│    │ ▓▓ │ 🧍 │    │   🧍 = 플레이어가 있는 청크
│    │    │    │    │
└────┴────┴────┴────┘
```

- 플레이어가 청크 경계를 넘으면 새로 보이게 될 청크를 로드, 뒤쪽 청크를 언로드.
- 이 프로젝트가 목표하는 MMORPG 규모에서는 필수입니다 →
  [06-phase6-mmorpg-architecture.md](../06-phase6-mmorpg-architecture.md),
  [07-phase7-optimization.md](../07-phase7-optimization.md).

### 7.3 객체 풀링(Object Pool) — 만들고 버리기를 반복하지 마라

투사체·이펙트·몬스터처럼 **끊임없이 생성·소멸**하는 기물을 매번 `new`/
`removeFromParent`로 처리하면 GC(가비지 컬렉션) 부담이 폭증해 프레임이 끊깁니다.
**미리 만들어 둔 객체를 재사용**하는 것이 풀링입니다.

- Flame 1.36.0+의 `ComponentPool`로 컴포넌트를 풀링할 수 있습니다.
- 같은 스프라이트를 쓰는 기물이 수백 개면 Flame 1.37.0의
  `HasAutoBatchedChildren` mixin으로 draw call을 묶어 렌더 비용을 낮춥니다.

### 7.4 정적/동적 기물 분리 — 안 바뀌는 것은 한 번만 그려라

나무·바위·건물처럼 **절대 안 움직이는 정적 기물**과 플레이어·몬스터처럼 **매 프레임
바뀌는 동적 기물**을 레이어로 나눕니다.

- 정적 레이어는 한 번 그린 결과를 **캐싱**해 매 프레임 다시 그리지 않습니다.
- 동적 레이어만 매 프레임 갱신합니다.
- 이번 예제의 나무·분수는 정적, 플레이어는 동적입니다. 지금은 수가 적어 구분이
  의미 없지만, 수천 개가 되면 이 분리가 성능을 좌우합니다.

### 7.5 충돌은 공간 분할로 — 전수 비교를 피하라

기물 N개의 충돌을 "모든 쌍을 비교"하면 N² 연산이라 수백 개만 돼도 느려집니다.
맵을 격자/쿼드트리로 나눠 **같은 칸(혹은 인접 칸)의 기물끼리만 비교**하면 비용이
급감합니다. Flame의 충돌 시스템(`HasCollisionDetection`)은 내부적으로 이런
broad-phase 최적화를 제공하므로, 직접 N² 루프를 짜지 말고 그 시스템을 쓰세요.

### 정리 — 복잡해질 때의 체크리스트

| 증상 | 처방 | 관련 문서 |
|---|---|---|
| 기물이 많아 렌더가 느림 | 컬링(화면 밖 스킵) | [07-phase7-optimization.md](../07-phase7-optimization.md) |
| 맵이 너무 커서 메모리 부족 | 청크 분할 로딩 | [06-phase6](../06-phase6-mmorpg-architecture.md) |
| 투사체/이펙트로 프레임 끊김 | 객체 풀링 | [07-phase7](../07-phase7-optimization.md) |
| 정적 기물이 많음 | 정적/동적 레이어 분리 | [03-phase3](../03-phase3-isometric-2.5d.md) |
| 충돌 검사가 느림 | 공간 분할(broad-phase) | [02-phase2-2d-action.md](../02-phase2-2d-action.md) |

---

## 8. 자주 만나는 함정

### 8.1 "Unable to load asset: assets/images/xxx.png"

새 기물 이미지를 추가했는데 `pubspec.yaml`의 `assets:`에 등록하지 않음.

**해결**: `pubspec.yaml`에 `- assets/images/tree.png`처럼 등록하고 **hot
restart**(hot reload 아님). 이번 예제는 `tree.png`·`fountain.png`·
`flower_tree.png` 세 개가 모두 등록되어 있어야 합니다.

### 8.2 기물이 화면에 안 보임

- `position`이 카메라 시야 밖일 수 있습니다. `size / 2` 근처로 두고 확인하세요.
- `size`를 설정하지 않아 `(0,0)` 크기로 그려졌을 수 있습니다.
- `await` 없이 `world.add`를 호출해 `onLoad`(이미지 로드) 완료 전에 렌더를
  시도했을 수 있습니다.

### 8.3 플레이어가 나무에 가려지거나, 나무를 통과함

- **가려짐**: 렌더 순서 문제 → 6.2의 `priority`/y-sorting으로 해결.
- **통과**: 충돌 처리가 없어서입니다. 지금 기물은 순수 그림일 뿐 물리적 벽이
  아닙니다. 막으려면 `HasCollisionDetection` + `RectangleHitbox`가 필요합니다
  → [02-phase2-2d-action.md](../02-phase2-2d-action.md).

### 8.4 카메라를 움직였더니 기물이 따라 움직임

기물을 화면 좌표 기준으로 배치하고 매 프레임 갱신하는 코드를 넣었을 때. 기물은
**월드 좌표에 고정**하고 카메라만 움직여야 합니다(6.3).

---

## 9. 다음 단계 확장 아이디어

이 예제가 이해되었다면 다음을 직접 해 보세요.

1. **방법 B로 리팩터링** — 기물 좌표를 리스트로 빼고 반복문으로 `add`해 보기.
2. **충돌 추가** — 나무에 `RectangleHitbox`를 달아 플레이어가 통과하지 못하게 하기.
3. **y-sorting** — 플레이어가 나무 위/아래에 설 때 가려짐이 자연스럽게 바뀌게 하기.
4. **Tiled 도입** — `flame_tiled`로 바닥 타일맵을 깔고 그 위에 기물을 올리기.
5. **맵 경계** — `camera.setBounds(...)`로 카메라가 맵 밖을 안 비추게 하기.

---

## 10. 관련 문서

- [hello_game_walking_animation.md](hello_game_walking_animation.md) — 이 예제의 전 단계(플레이어 애니메이션)
- [hello_game_keyboard_movement.md](hello_game_keyboard_movement.md) — 키보드로 캐릭터 움직이기
- [../02-phase2-2d-action.md](../02-phase2-2d-action.md) — 충돌(collision) 본격 학습
- [../03-phase3-isometric-2.5d.md](../03-phase3-isometric-2.5d.md) — 2.5D 맵, y-sorting, Tiled
- [../06-phase6-mmorpg-architecture.md](../06-phase6-mmorpg-architecture.md) — 대규모 맵, 청크
- [../07-phase7-optimization.md](../07-phase7-optimization.md) — 컬링·풀링·성능 최적화
- [../game-glossary.md](../game-glossary.md) — Component, World, Camera, priority 등 용어 정리

다음에는 이 맵 위의 기물에 **충돌 영역**을 붙여, 플레이어가 나무·분수에 막히도록
만드는 단계를 학습하시면 됩니다.
