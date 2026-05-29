# Phase 3 — 2.5D Isometric (본 코스의 핵심) ⭐

> **기간**: 3주
> **목표**: 2.5D Isometric MMORPG의 시각적·구조적 토대를 완성한다. Depth Sorting, Tiled 맵 통합, 8방향 캐릭터, 카메라, 충돌, 청크 월드.
> **이 Phase의 산출물이 곧 MVP** — Phase 4~8의 기반이 된다.

---

## 1. 학습 목표

- [ ] Isometric 좌표계 ↔ 스크린 좌표계 변환 자유롭게
- [ ] Tiled로 맵을 만들고 `flame_tiled`로 로딩
- [ ] **Depth Sorting (Y-sort)** 으로 캐릭터가 건물/나무 뒤로 들어감
- [ ] 8방향 이동 + 8방향 SpriteAnimation
- [ ] Camera Bounds, Edge Pan, Click-to-Move
- [ ] Chunk 기반 대형 월드 로딩

---

## 2. 왜 2.5D Isometric이 본 코스의 핵심인가

| 이유 | 설명 |
|---|---|
| **MMORPG의 사실상 표준** | RO, Tibia, Tree of Savior, Diablo 2, Stardew Valley — 모두 이 패러다임 |
| **3D보다 제작비 1/10** | 모델링 없이 픽셀 아트, 8방향 + idle/walk/attack만 |
| **Flame이 잘 지원** | flame_tiled가 Orthogonal/Isometric/Staggered/Hexagonal 네 가지 투영 모두 지원 |
| **Depth Sorting이 MMO의 첫 난관** | 여기서 정확히 잡지 않으면 100명 동시 접속 시 렌더 깨짐 |

### 2.1 아름다운 2.5D 맵을 위한 기술 체크리스트

2.5D 맵은 "다이아몬드 타일을 배치한다"가 아니라 **시각 레이어와 게임 데이터 레이어를 분리해서 설계하는 일**입니다. Tiled에서 예쁜 장면을 만들고, Flame에서 그 장면이 움직이는 캐릭터/몬스터와 정확히 섞이게 해야 합니다.

| 영역 | 반드시 공부할 것 | 구현 규칙 |
|---|---|---|
| Projection | true isometric, staggered isometric, top-down 2.5D의 차이 | 프로젝트 초기에 하나만 선택. 중간 변경은 자산 전체 재작업 |
| Tile metric | 64×32, 96×48, 128×64 같은 2:1 타일 비율 | 캐릭터 foot point와 충돌 박스 기준을 문서화 |
| Layer contract | `ground`, `ground_detail`, `below_actor`, `ysort_object`, `above_actor`, `collision`, `nav`, `spawn`, `trigger` | Tiled 레이어 이름을 코드 enum처럼 취급 |
| Custom properties | `kind`, `asset`, `sortY`, `footX`, `footY`, `height`, `blocking`, `navCost`, `spawnGroup` | Object Layer의 property를 Flame component factory 입력으로 사용 |
| Occlusion | 나무/건물/절벽/다리의 가림 순서 | 큰 sprite는 base/body/roof slice로 분해 |
| Lighting | baked shadow, contact shadow, blob shadow, day-night overlay | 동적 광원보다 baked + overlay가 모바일 성능에 유리 |
| World streaming | Tiled infinite/chunk, 여러 TMX, 에셋 프리로드 | MVP는 50×50, 이후 chunk 단위 로딩 |
| Debug | foot point, sortY, collision, nav layer on/off | 개발 중 `F1` 디버그 오버레이 필수 |

### 2.2 Tiled 레이어 계약 예시

```text
map_village.tmx
├── ground              # 항상 먼저 그림. y-sort 대상 아님
├── ground_detail       # 꽃, 작은 돌, 길 가장자리. collision 없음
├── below_actor         # 낮은 담장, 바닥 장식. 캐릭터보다 뒤/아래
├── ysort_object        # 나무, 바위, NPC 표지판. World 자식으로 변환 후 Y-sort
├── above_actor         # 지붕, 높은 나뭇가지, 실내 천장. 필요 시 별도 slice
├── collision           # 보이지 않는 AABB/Polygon. 서버 collision 데이터와 맞춰야 함
├── nav                 # 이동 비용/금지 구역. 클릭 이동과 서버 path validation용
├── spawn               # player/npc/monster spawn point
└── trigger             # 포탈, 대화 시작, 존 이동, 상호작용
```

**중요한 원칙**:
- 캐릭터와 순서가 섞여야 하는 object는 `TiledComponent` 내부에 그대로 두지 말고 `World` 자식 `PositionComponent`로 변환합니다.
- 큰 건물은 하나의 PNG로 끝내지 말고 `base`, `wall`, `roof`, `front_occluder`처럼 slice합니다.
- 충돌은 예쁜 그림 기준이 아니라 **발밑 이동 영역** 기준입니다. 예쁜 나무 sprite 전체를 막으면 플레이어가 과하게 멀리서 막힙니다.
- Tiled custom property는 아트와 코드 사이의 API입니다. 이름을 자주 바꾸면 맵 전체가 깨집니다.

---

## 3. 좌표계 — 가장 중요

### 3.1 세 가지 좌표계

```
[월드 좌표 (Tile)]      [화면 좌표 (Pixel)]      [Flame World 좌표]
 (col, row)              (screenX, screenY)      (worldX, worldY)
```

세 좌표계 사이의 변환을 항상 명확히 구분해야 합니다.

### 3.2 Isometric 변환

타일 크기를 `tw × th` (예: 64×32, 표준 2:1 다이아몬드)라 하면:

**Tile → Pixel (Isometric)**:
```
pixelX = (col - row) * (tw / 2)
pixelY = (col + row) * (th / 2)
```

**Pixel → Tile**:
```
col = (pixelX / (tw/2) + pixelY / (th/2)) / 2
row = (pixelY / (th/2) - pixelX / (tw/2)) / 2
```

코드:
```dart
class IsoMath {
  static const tw = 64.0;
  static const th = 32.0;

  static Vector2 tileToPixel(int col, int row) =>
      Vector2((col - row) * (tw / 2), (col + row) * (th / 2));

  static Vector2 pixelToTile(Vector2 p) {
    final col = (p.x / (tw / 2) + p.y / (th / 2)) / 2;
    final row = (p.y / (th / 2) - p.x / (tw / 2)) / 2;
    return Vector2(col, row);
  }
}
```

> ⚠️ **반환값이 실수(double)임에 주의**. `pixelToTile`은 `Vector2(col, row)`를 실수로 돌려줍니다. 어떤 타일을 클릭했는지 알려면 `col.floor()`, `row.floor()`로 내림 처리해야 합니다(반올림 `round()`가 아니라 내림 `floor()`가 다이아몬드 셀의 경계와 일치). 발밑 한 점이 아니라 다이아몬드 셀 전체를 정확히 판정하려면 셀 내부에서 다시 분할 삼각형(상/하/좌/우 4분할)으로 어느 셀에 속하는지 재계산하는 "diamond hit test"가 필요합니다(클릭 정밀도가 중요한 RTS/타일 단위 이동에서만). 본 코스(픽셀 자유 이동)는 `floor` 수준으로 충분합니다.

#### 3.2.1 Staggered Isometric 변환

true isometric(다이아몬드)은 맵 전체가 마름모로 회전돼 캔버스 좌우에 빈 삼각형 여백이 생깁니다. **Staggered Isometric**은 각 행을 가로 직사각형 격자에 넣되 홀수 행을 반 타일만큼 가로로 밀어(offset) 다이아몬드 느낌을 내는 방식으로, 맵이 직사각형 캔버스에 꽉 차고 무한 맵/청크 분할에 유리합니다. Tiled의 `Isometric (Staggered)` 모드가 이것이며, `staggerAxis`(x 또는 y)와 `staggerIndex`(odd 또는 even)로 어느 축을 어느 패리티에서 미는지 결정합니다.

Y축 stagger(가장 흔한 형태, `staggerAxis = y`, `staggerIndex = odd`) 기준 변환:

```dart
class StaggeredIsoMath {
  static const tw = 64.0; // 타일 폭
  static const th = 32.0; // 타일 높이 (2:1이면 tw/2)

  // 홀수 행을 오른쪽으로 tw/2 만큼 민다 (staggerIndex = odd 기준)
  static Vector2 tileToPixel(int col, int row) {
    final isOdd = (row & 1) == 1;
    final x = col * tw + (isOdd ? tw / 2 : 0);
    final y = row * (th / 2); // 행 간격은 th의 절반
    return Vector2(x, y);
  }

  // 역변환: 먼저 거친 행을 추정한 뒤 인접 후보 셀을 비교해 정밀 보정
  static Vector2 pixelToTile(Vector2 p) {
    final row = (p.y / (th / 2)).floor();
    final isOdd = (row & 1) == 1;
    final col = ((p.x - (isOdd ? tw / 2 : 0)) / tw).floor();
    return Vector2(col.toDouble(), row.toDouble());
  }
}
```

> Staggered는 역변환 경계(행과 행 사이 톱니 영역)에서 한 셀씩 틀어지기 쉽습니다. 정확한 picking이 필요하면 추정 셀 ±1 행/열의 후보 다이아몬드를 만들어 클릭 점이 어느 다이아몬드 내부인지 점-다각형 판정으로 확정하세요. **권장**: 본 코스 MVP는 true isometric(§3.2)으로 시작하고, 무한 맵·청크가 필요해지는 Phase 6 단계에서 Staggered를 검토합니다. 한 번 정한 투영을 중간에 바꾸면 좌표 변환·자산·Tiled 맵을 전부 재작업해야 하므로 §2.1의 "초기에 하나만 선택" 원칙을 지키세요.

### 3.3 캐릭터 이동은 어디서?

**선택지 A — 픽셀(Flame World) 좌표로 이동, 충돌 시에만 타일 변환**:
- 부드러움 ✓
- 8방향이 자연스럽다 ✓
- **MMORPG에서 추천**

**선택지 B — 타일 단위 이동 (RO, 클래식)**:
- 그리드 강제, 클릭 위치로 이동
- 서버 동기화가 매우 단순 ✓
- 단, 부드러운 8방향 액션은 어색

본 코스는 **선택지 A**로 진행합니다. 자유로운 8방향 + 픽셀 좌표 + 충돌 검사 시 타일 변환.

---

## 4. Depth Sorting (Y-Sort) — 절대 이해 필수

### 4.1 문제

```
화면:
   [나무]
     ↑
     ?
   [캐릭터]
```

캐릭터가 나무 위쪽으로 이동하면, 나무가 캐릭터를 **가려야** 합니다.
즉, 캐릭터의 그리기 순서가 나무보다 **앞이어야 함** (먼저 그려져야 뒤로 들어감).

### 4.2 핵심 규칙

**모든 동적 객체의 priority(z-order) = 객체의 "발 위치(footY)"**

```dart
class Player extends PositionComponent {
  @override
  void update(double dt) {
    super.update(dt);
    // ... 이동 ...
    priority = position.y.round();   // 매 프레임 갱신
  }
}
```

마찬가지로 나무, 건물도:
```dart
class Tree extends PositionComponent {
  @override
  Future<void> onLoad() async {
    priority = position.y.round();
    anchor = Anchor.bottomCenter;  // 발(base) 기준
  }
}
```

> ⚠️ **함정**: anchor를 center로 두면 발 위치가 어긋남. Isometric에선 거의 항상 `bottomCenter`.

### 4.3 다층 객체 (2층 건물)

큰 객체는 **여러 슬라이스로 분할**:
```
[지붕]   priority = top.y
[2층]    priority = mid.y
[1층]    priority = bottom.y
[그림자] priority = bottom.y - 1
```

### 4.4 같은 priority 일 때

Flame의 `priority`는 **정수(int)** 입니다(소수 priority 같은 건 없습니다). 같은 priority를 가진 컴포넌트들의 상대 순서는 트리에 추가된 순서로 결정되며, priority가 바뀌면 Flame이 부모의 자식 리스트를 다시 정렬합니다. 문제는 같은 footY를 가진 두 캐릭터가 서로 스쳐 지나갈 때 추가 순서에 의존하면 한쪽이 다른 쪽을 가렸다 안 가렸다 **깜빡(flicker)** 한다는 점입니다.

해결은 priority 자체에 결정적(deterministic) tiebreaker를 섞어 넣는 것입니다. footY를 1000배 한 뒤 하위 자리에 안정 ID를 더합니다:
```dart
// tiebreaker = 엔티티 고유 ID처럼 매 프레임 변하지 않는 값
priority = position.y.round() * 1000 + (entityId % 1000);
```
이렇게 하면 같은 Y라도 항상 같은 엔티티가 앞에 오므로 깜빡임이 사라집니다(완전한 공식은 §4.5 참조). `tiebreaker`로 `position.x`를 쓰는 방법도 있지만, X가 같아지는 순간 다시 모호해지므로 **변하지 않는 ID**가 가장 안전합니다.

### 4.5 Y-sort가 깨지는 대표 케이스와 해결

단순 `priority = footY`는 80%를 해결하지만, MMORPG 맵에서는 나머지 20%가 화면 품질을 결정합니다.

| 문제 | 증상 | 해결 |
|---|---|---|
| 큰 건물 하나짜리 sprite | 캐릭터가 건물 벽 뒤로 들어가야 하는데 지붕까지 같이 가려짐 | 건물을 base/wall/roof/front slice로 분해하고 slice별 priority 부여 |
| 다리/경사로 | 캐릭터가 다리 위/아래를 오갈 때 순서가 뒤집힘 | `heightLevel` 또는 `floor` property를 둬서 같은 Y라도 층을 분리 |
| 나무 캐노피 | 줄기 뒤는 가려져야 하지만 잎 앞에서는 캐릭터가 보여야 함 | trunk와 canopy를 분리. canopy는 `above_actor`로, trunk는 `ysort_object`로 |
| 같은 Y의 여러 캐릭터 | 서로 깜빡이거나 추가 순서에 따라 뒤집힘 | entity id 기반 stable tiebreaker 사용 |
| 반투명 오브젝트 | alpha blending 순서가 어색함 | 반투명 레이어는 가능한 고정 레이어로 빼고, y-sort 대상 최소화 |
| 수백 객체 sorting 비용 | 매 프레임 정렬로 프레임 드랍 | 움직인 객체만 priority 갱신, 정적 객체는 로딩 시 priority 고정 |

권장 priority 공식:

```dart
int ySortPriority({
  required double footY,
  int layer = 0,
  int heightLevel = 0,
  required int stableId,
}) {
  return layer * 100000000
      + heightLevel * 1000000
      + footY.round() * 1000
      + (stableId % 1000);
}
```

`layer`는 `ground < below_actor < ysort_object < actor < above_actor < hud`처럼 큰 단위 순서를 보장하고, `heightLevel`은 다리/2층/지하 같은 예외를 처리합니다.

> ⚠️ **공식 사용 시 두 가지 정확성 함정**:
> 1. **footY 음수**: 맵 원점보다 위쪽(=Y가 음수)에 객체가 놓이면 `footY.round()`가 음수가 되어 자릿수 구조가 무너지고 정렬이 뒤집힙니다. footY에 맵 높이만큼 상수 offset을 더해 **항상 0 이상**으로 만든 뒤 곱하세요(`(footY.round() + worldHeightPx)`).
> 2. **자릿수 충돌(overflow가 아닌 의미 충돌)**: 위 공식은 footY를 ×1000 자리에, stableId를 하위 1000 자리에 욱여넣습니다. 따라서 한 layer/heightLevel 안에서 footY가 픽셀 기준 ~100,000을 넘으면 heightLevel 자리(×1000000)를 침범합니다. Dart의 `int`는 64비트(웹은 별도)라 산술 오버플로 자체는 거의 없지만 **자릿수 폭은 직접 설계**해야 합니다. 대형 맵이면 각 필드의 자릿수 폭을 비트 시프트로 명시(예: `(layer << 48) | (heightLevel << 40) | (clampedFootY << 12) | (stableId & 0xFFF)`)하는 편이 안전합니다.

#### 4.5.1 큰 건물의 slice별 footY 산정

§4.3에서 건물을 base/wall/roof/front로 분해할 때, **각 slice의 정렬 기준 footY는 그 slice가 화면에서 "어느 깊이에 박혀 있어야 하는가"** 로 정합니다. slice의 그림 자체 위치가 아니라 정렬용 가상 발밑을 따로 둡니다.

```dart
// 같은 건물의 4개 slice — 정렬 기준 footY를 각각 다르게
final buildingBaseY = building.position.y; // 건물 발밑(바닥선)
base.priority  = ySortPriority(footY: buildingBaseY,        layer: kLayerActor, stableId: id);
wall.priority  = ySortPriority(footY: buildingBaseY,        layer: kLayerActor, stableId: id); // 벽도 발밑 기준
roof.priority  = ySortPriority(footY: buildingBaseY + 9999, layer: kLayerActor, stableId: id); // 항상 캐릭터보다 앞
front.priority = ySortPriority(footY: buildingBaseY + 9999, layer: kLayerActor, stableId: id); // 입구 가림막
```

핵심은 **지붕(roof)·전면 가림막(front_occluder)은 건물 발밑보다 큰 footY를 줘서 그 건물 영역 안에 있는 캐릭터보다 항상 앞**에 그려지게 하고, **벽(wall)·바닥(base)은 건물 발밑 footY를 그대로** 써서 캐릭터가 footY로 자연스럽게 앞뒤 판정되도록 하는 것입니다. 이렇게 하면 캐릭터가 건물 뒤를 지나면 벽에 가려지고, 입구로 들어가면 전면 가림막에 가려져 "안으로 들어간" 연출이 됩니다.

### 4.6 검증 시나리오 (반드시 통과)

- [ ] 캐릭터가 나무를 위↔아래로 통과할 때 가려짐/보임이 자연스럽게 전환
- [ ] 두 캐릭터가 같은 Y에 있을 때 한쪽이 다른 쪽을 가리지 않거나, 가리더라도 일관됨
- [ ] 캐릭터가 큰 건물 뒤로 완전히 사라졌다가 다시 나옴

---

## 5. Tiled 맵 통합

### 5.1 Tiled 설치 & 맵 제작
- https://www.mapeditor.org
- **2026-05 기준 최신 에디터: Tiled 1.12.2** (2026-05-27경 출시). 마이너 1.12는 2026-03-13, 1.12.1은 2026-03-25, 패치 1.12.2가 최신입니다(1.12.1에서 발생한 Properties view 회귀와 list 타입 custom property 후속 버그를 수정). 1.12 마이너의 신기능:
  - **list-valued custom property** — 한 객체에 여러 태그/그룹 부착(예: `tags = ["npc", "trader", "town_guard"]`)
  - **Oblique orientation** — X/Y 축을 비스듬히 기울이는 새 투영 방향
  - **layer blending mode** (SVG 1.2 / CSS 호환: Multiply, Screen, Overlay 등) — 안개·그늘 레이어 표현
  - **Capsule object** — 물리/충돌 친화 모양
  - **per-object opacity** — 개별 오브젝트 불투명도(반투명 가림막·유령 미리보기에 유용)
  - **속성 뷰(Properties view) 전면 재작성** — 위젯에서 바로 편집
  - 출처: [Tiled 1.12 릴리스 노트](https://www.mapeditor.org/2026/03/13/tiled-1-12-released.html), [Tiled 1.12.2 devlog](https://thorbjorn.itch.io/tiled/devlog/1536048/tiled-1122-released)
- > ⚠️ **parallax는 1.12 신기능이 아닙니다.** 레이어 parallax scrolling factor는 Tiled 1.5부터 있던 기능이며 `flame_tiled`도 레이어의 parallax factor 속성을 지원합니다(§10.1의 "Parallax background"는 이 기능을 활용). 1.12의 진짜 신규는 위에 나열한 per-object opacity, Capsule object, Oblique orientation, layer blending mode, list-valued property입니다.
- New Map → Orientation: **Isometric** (또는 **Isometric (Staggered)**)
- Tile size: 64 × 32 (또는 본인 sprite에 맞게)
- 레이어:
  - `ground` (Tile Layer) — 잔디, 길
  - `objects_static` (Object Layer) — 나무, 바위 (Y-sort 대상)
  - `collision` (Object Layer) — 충돌 영역 (보이지 않음, 사각형/폴리곤)
  - `spawn` (Object Layer) — NPC, 몬스터 스폰 포인트

> custom property는 **Tiled 1.8+의 class/enum 강타입 속성**을 사용하세요. 본 코스의 Tiled 레이어 계약(§2.2)에서 정의한 `kind`/`asset`/`sortY`/`footX`/`footY`/`height`/`blocking`/`navCost`/`spawnGroup`이 그 대상입니다. 1.12부터는 list 타입으로 다중 태그도 가능.

### 5.2 flame_tiled 로딩

```bash
flutter pub add flame_tiled
```

```dart
import 'package:flame/collisions.dart';
import 'package:flame_tiled/flame_tiled.dart';

// 최신 권장: 충돌 감지는 FlameGame이 아니라 World에 부여한다.
// CameraComponent + World 구조에서 충돌 트리를 World 하위로 묶어
// 카메라/오버레이 컴포넌트가 충돌 계산에 섞이지 않게 한다.
class IsoWorld extends World with HasCollisionDetection {
  late TiledComponent map;

  @override
  Future<void> onLoad() async {
    // TiledComponent.load(파일명, destTileSize, {옵션})
    // destTileSize = Vector2(64, 32) — 타일을 화면에 그릴 목표 크기.
    // 대형 타일셋은 atlasMaxX/atlasMaxY로 내부 텍스처 아틀라스 한계를 넓힌다.
    map = await TiledComponent.load(
      'map_village.tmx',
      Vector2(64, 32),
      atlasMaxX: 9216,  // 기본값으로 atlas가 모자라면 키운다(타일셋 큰 경우)
      atlasMaxY: 9216,
      // useAtlas: false      // flip 타일이 많아 atlas 성능이 나쁘면 끌 수도 있음
    );
    add(map);

    // collision 레이어 파싱 (Object Layer)
    final col = map.tileMap.getLayer<ObjectGroup>('collision');
    for (final obj in col!.objects) {
      add(StaticCollider(
        position: Vector2(obj.x, obj.y),
        size: Vector2(obj.width, obj.height),
      ));
    }

    // spawn 파싱 — Tiled 오브젝트의 class(구버전 type) 필드로 분기
    final spawn = map.tileMap.getLayer<ObjectGroup>('spawn');
    for (final obj in spawn!.objects) {
      switch (obj.class_) {  // tiled 0.11.x: ObjectGroup의 객체는 class_ 게터 사용
        case 'slime':  add(Slime()..position = Vector2(obj.x, obj.y)); break;
        case 'tree':   add(Tree()..position = Vector2(obj.x, obj.y));  break;
      }
    }
  }
}
```

> **`TiledComponent.load`의 주요 옵션** (시그니처: `load(String fileName, Vector2 destTileSize, {atlasMaxX, atlasMaxY, prefix, priority, ignoreFlip, bundle, images, tsxPackingFilter, useAtlas, layerPaintFactory, atlasPackingSpacingX, atlasPackingSpacingY, key})`):
> - `atlasMaxX` / `atlasMaxY`: 큰 타일셋을 하나의 텍스처 아틀라스로 합칠 때의 최대 크기. 타일셋 합본이 이 한계를 넘으면 로딩 에러가 나므로 대형 맵에서 키웁니다. 예: `await TiledComponent.load('my_map.tmx', Vector2.all(32), atlasMaxX: 9216, atlasMaxY: 9216);`
> - `useAtlas`: flip(좌우/상하 반전)된 타일이 많으면 atlas 합본이 오히려 성능을 떨어뜨릴 수 있어 `false`로 끌 수 있습니다.
> - `ignoreFlip`: TMX의 flip 플래그를 무시.
> - `layerPaintFactory`: 레이어별 `Paint`를 주입해 blend mode/투명도 등을 코드로 제어.
> - 출처: [TiledComponent class 문서](https://pub.dev/documentation/flame_tiled/latest/flame_tiled/TiledComponent-class.html)

`assets/tiles/map_village.tmx` 와 사용된 `.tsx`(타일셋), 이미지들을 모두 `assets/` 에 등록해야 합니다. `getLayer<T>('name')`은 해당 이름의 레이어를 `T`(예: `ObjectGroup`, `TileLayer`, `ImageLayer`, `Group`)로 반환하거나, 없으면 `null`을 돌려줍니다(위 코드의 `!`는 레이어 존재를 가정한 것이며 실제 코드에선 null 체크 권장). 맵 전체 렌더 객체는 `RenderableTiledMap`이 담당합니다.

### 5.3 정적 객체의 Y-sort 통합

Tiled의 Object Layer로 만든 나무·건물을 **TiledComponent 안이 아닌, World 자식**으로 옮겨 넣어야 캐릭터와 같이 sort 됩니다.

```dart
final treeLayer = map.tileMap.getLayer<ObjectGroup>('objects_static');
for (final o in treeLayer!.objects) {
  add(Tree(position: Vector2(o.x, o.y), gid: o.gid));
}
// 그리고 Tiled의 objects_static 레이어는 invisible로
```

### 5.4 타일맵 seam(이음새) artifact 방지

Isometric/Staggered 타일맵을 텍스처 아틀라스/`SpriteBatch`로 렌더할 때, 카메라 zoom이나 서브픽셀 위치에서 타일 경계에 **가는 흰 줄(seam, ghost line)** 이 보이는 현상이 흔합니다(인접 타일의 텍스처 샘플링이 1픽셀 새는 문제). flame은 이 문제를 두 단계로 개선했습니다.

- flame 1.30.0: `Sprite`에 `measure` 기반 처리를 도입해 스프라이트 ghost-line/그래픽 artifact를 수정(#3590).
- flame 1.37.0: `SpriteBatch`에 **`bleed` 옵션**을 추가(#3871) — 타일맵 seam을 방지하도록 텍스처 가장자리를 미세 확장합니다.

Phase 3에서 Iso 타일맵을 만들고, Phase 7에서 atlas/`SpriteBatch`로 묶을 때 이 옵션을 함께 다루면 zoom·이동 중 깜빡이는 타일 경계 줄을 줄일 수 있습니다. 출처: [flame CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md)

---

## 6. 8방향 캐릭터

### 6.1 방향 enum

```dart
enum Dir8 { e, ne, n, nw, w, sw, s, se }

Dir8 dirFromVector(Vector2 v) {
  final angle = math.atan2(v.y, v.x);                  // -π ~ π
  final octant = ((angle / math.pi * 4) + 8.5).floor() % 8;
  return Dir8.values[octant];
}
```

### 6.2 8방향 SpriteSheet 구조

권장 스프라이트 시트 레이아웃:
```
행:    idle / walk / attack / hit / death
열:    각 행 안에서 8방향 × N프레임
```

또는 방향 × 상태로 인덱싱:
```dart
class IsoActor extends PositionComponent {
  late Map<(String, Dir8), SpriteAnimation> anims;
  late SpriteAnimationComponent sprite;
  Dir8 dir = Dir8.s;
  String state = 'idle';

  void play(String s, Dir8 d) {
    if (s == state && d == dir) return;
    state = s; dir = d;
    sprite.animation = anims[(s, d)];
  }
}
```

### 6.3 이동 방향 → 캐릭터 방향

```dart
@override
void update(double dt) {
  super.update(dt);
  if (velocity.length > 0) {
    dir = dirFromVector(velocity);
    play('walk', dir);
    position += velocity.normalized() * speed * dt;
  } else {
    play('idle', dir);
  }
  priority = position.y.round();
}
```

---

## 7. 충돌 (Isometric)

화면이 다이아몬드라도 **충돌 영역은 보통 AABB**로 처리합니다 (성능, 단순성).

```dart
class StaticCollider extends PositionComponent with CollisionCallbacks {
  StaticCollider({required Vector2 position, required Vector2 size})
      : super(position: position, size: size) {
    add(RectangleHitbox()..collisionType = CollisionType.passive);
  }
}

class Player extends PositionComponent with CollisionCallbacks {
  Vector2 _prev = Vector2.zero();

  @override
  void update(double dt) {
    _prev = position.clone();
    super.update(dt);
    position += velocity * dt;
  }

  @override
  void onCollision(Set<Vector2> pts, PositionComponent other) {
    if (other is StaticCollider) {
      position = _prev;   // 충돌 시 이전 위치 복귀 (간단한 처리)
    }
  }
}
```

> 더 정교한 처리: X/Y 분리 이동 후 각각 검사 (slide along wall).

> **충돌 감지를 어디에 부여하나 (최신 권장)**: `HasCollisionDetection` mixin은 `FlameGame`이 아니라 **`World`** 에 부여하는 것이 현행 권장입니다(§5.2의 `class IsoWorld extends World with HasCollisionDetection`). `CameraComponent + World` 구조에서 충돌 트리를 World 하위로 묶으면, HUD/오버레이/카메라 컴포넌트가 충돌 계산에 끼어들지 않습니다. **정적 충돌체가 많은 맵**(나무·벽 수백 개)이면 기본 sweep-and-prune 대신 `HasQuadTreeCollisionDetection`을 World에 부여해 정적 객체를 쿼드트리로 색인하면 검사 비용이 크게 줄어듭니다. flame 1.36.0부터 Hitbox가 부모의 scale·rotation을 정확히 반영하므로(#3834), Isometric에서 캐릭터를 스케일했을 때도 충돌 박스가 어긋나지 않습니다.
> 출처: [Flame Collision Detection 문서](https://docs.flame-engine.org/latest/flame/collision_detection.html)

---

## 8. 카메라 (Isometric 특화)

### 8.1 Bounds
맵 끝에서 카메라가 빈 영역을 보지 않도록:
```dart
cam.setBounds(Rectangle.fromLTWH(
  -map.size.x / 2, 0, map.size.x, map.size.y,
));
```

### 8.2 Edge Pan / Click-to-Move (옵션)
```dart
// 마우스가 화면 가장자리 → 카메라 이동
// 마우스 클릭 → 픽셀 좌표를 player.target 으로 설정
```

### 8.3 화면→월드 좌표

화면(글로벌) 좌표를 월드(로컬) 좌표로 바꾸는 표준 메서드는 `CameraComponent.globalToLocal`입니다(반대 방향은 `localToGlobal`). zoom·angle·bounds가 적용된 카메라를 통과한 좌표를 정확히 돌려줍니다.

```dart
// screenPos: TapDownEvent 등에서 받은 화면 좌표
final world = cam.globalToLocal(screenPos);   // 화면 → 월드(픽셀)
final tile = IsoMath.pixelToTile(world);      // 월드(픽셀) → 타일(실수)
final cell = Vector2(tile.x.floorToDouble(), tile.y.floorToDouble()); // 어느 셀인지
```

> 입력 처리는 구버전 `Tappable`/`Draggable` mixin이 아니라 **`TapCallbacks`/`DragCallbacks`** 를 사용하세요. 콜백은 단일 이벤트 객체를 받으며(`event.localPosition`, `event.canvasPosition`), 전파 제어는 `event.continuePropagation`으로 합니다. 클릭 이동(click-to-move)은 게임에 `TapCallbacks`를 달고 `onTapDown`에서 위 변환으로 목표 타일을 구해 `player.target`에 넣는 식으로 구현합니다.

### 8.4 Camera 2.0 회전·줌 (Isometric 회전 시야)

Flame 1.x의 표준 `CameraComponent`(이른바 Camera 2.0)의 `Viewfinder`는 회전(`angle`)·스케일(`zoom`)·평행이동(`position`)을 모두 지원합니다. `viewfinder.angle`/`viewfinder.zoom`은 flame 1.x 초기부터 있던 안정 API이므로 특정 마이너 버전 신기능이 아닙니다(1.37.0에서도 동일). Isometric 회전 시야(예: 캐릭터 등 뒤로 카메라가 살짝 도는 효과, 또는 90도 회전 뷰)도 한 줄로 가능합니다.

```dart
// 줌 & 회전 동시 적용
cam.viewfinder.zoom = 1.4;
cam.viewfinder.angle = math.pi / 12;   // 약 15도 회전 — Isometric 화면을 살짝 기울임

// 효과로 부드럽게 줌 전환
cam.viewfinder.add(
  ScaleEffect.to(Vector2.all(1.8), EffectController(duration: 0.4)),
);
```

> ⚠️ Isometric 화면을 회전하면 Y-sort 기준(footY)이 그대로면 어색해질 수 있습니다. 회전이 본격 콘텐츠라면 priority를 **카메라 기준의 회전된 footY**로 계산해야 합니다. 본 코스는 학습 안정성을 위해 **회전은 보너스 데모로만** 권장합니다.
> 출처: https://docs.flame-engine.org/latest/flame/camera_component.html

---

## 9. Chunk 기반 대형 월드 (선맛보기)

전체 맵 한 장이 4096×4096 픽셀을 넘으면 메모리·렌더링 부담.

### 9.1 청크 분할
- 16×16 타일 = 1 chunk
- 카메라 주변 3×3 청크만 로드, 나머지 unload
- Tiled 맵을 여러 .tmx 로 쪼개거나, 거대 .tmx + 동적 culling

### 9.2 본 Phase에선 작은 맵으로 시작
- 50×50 타일 정도면 충분
- Phase 6에서 본격적인 청크 스트리밍 다룸

### 9.3 청크 스트리밍 실전 패턴 (Phase 6 예고)

청크 스트리밍의 핵심은 **(1) 카메라 위치 → 어느 청크인지 계산, (2) 필요한 청크만 로드/불필요 청크 언로드, (3) 경계에서 깜빡이지 않게 히스테리시스(hysteresis)** 세 가지입니다.

```dart
// 청크 = chunkTiles × chunkTiles 타일. 청크 인덱스는 타일 좌표 기준으로 계산
const chunkTiles = 16;

(int, int) chunkOf(Vector2 tile) =>
    ((tile.x / chunkTiles).floor(), (tile.y / chunkTiles).floor());

class ChunkStreamer extends Component with HasGameReference<IsoGame> {
  final loaded = <(int, int), Component>{};
  (int, int)? _lastCenter;

  @override
  void update(double dt) {
    // 카메라 중심 픽셀 → 타일 → 청크
    final centerPixel = game.camera.viewfinder.position;
    final centerTile = IsoMath.pixelToTile(centerPixel);
    final center = chunkOf(centerTile);
    if (center == _lastCenter) return; // 같은 청크면 아무것도 안 함(불필요한 갱신 방지)
    _lastCenter = center;

    // 필요한 3×3 이웃 집합
    final need = <(int, int)>{
      for (var dx = -1; dx <= 1; dx++)
        for (var dy = -1; dy <= 1; dy++) (center.$1 + dx, center.$2 + dy),
    };

    // 새로 들어온 청크 로드
    for (final c in need) {
      loaded.putIfAbsent(c, () => _loadChunk(c)..addToParent(this));
    }
    // 범위 밖 청크 언로드
    loaded.removeWhere((c, comp) {
      if (!need.contains(c)) { comp.removeFromParent(); return true; }
      return false;
    });
  }

  Component _loadChunk((int, int) c) {/* TMX 일부 또는 별도 .tmx 로딩 */}
}
```

실전 주의:
- **Isometric의 청크 경계는 화면에서 다이아몬드**: 청크는 타일 좌표 기준 직사각형이지만 화면에선 마름모로 보입니다. 화면 가시 영역(`camera.visibleWorldRect`)을 그대로 청크 사각형에 매핑하면 모서리 청크가 누락될 수 있으니, **카메라 가시 영역 코너 4점을 모두 `pixelToTile`로 변환**해 그 bounding box를 덮는 청크를 로드하세요(단순 중심 ±1보다 정확).
- **히스테리시스**: 청크 경계를 왔다 갔다 할 때 로드/언로드가 깜빡이지 않도록, 로드 반경(3×3)보다 **언로드 반경을 한 칸 더 넓게**(예: 로드 3×3, 언로드 5×5 밖) 두면 경계 진동이 사라집니다.
- **비동기 로딩**: 청크 TMX/이미지 디코딩을 메인 isolate에서 하면 프레임이 끊깁니다. Phase 7에서 `flame_isolate`로 백그라운드 디코딩을 다루되, `flame_isolate`는 **Web 미지원**(Android/iOS/Linux/macOS/Windows)이라 Web 타깃이면 `compute`/청크 분할 점진 로딩으로 대체합니다.
- **Y-sort와의 상호작용**: 청크가 언로드/로드될 때 객체가 갑자기 사라졌다 나타나면 정렬이 튑니다. 화면 밖 여유분(1청크 패딩)을 항상 유지해 가시 영역 안에서는 절대 로드 경계가 보이지 않게 합니다.

---

## 10. 맵을 아름답게 만드는 실전 테크닉

### 10.1 평면감을 없애는 6가지 장치

1. **Contact shadow**: 캐릭터 발밑, 나무 밑, 바위 밑에 작은 반투명 타원 그림자를 둡니다.
2. **Baked ambient occlusion**: 건물 벽과 바닥이 만나는 곳, 절벽 아래, 큰 나무 아래를 타일에 미리 그립니다.
3. **Palette ramp**: 같은 녹색이라도 그림자/중간/하이라이트 색을 명확히 둬서 덩어리를 만듭니다.
4. **Edge detail**: 길과 잔디의 경계를 직선으로 두지 말고 깨진 타일, 꽃, 작은 돌로 부드럽게 섞습니다.
5. **Parallax background**: 멀리 보이는 산/하늘/안개는 카메라보다 느리게 움직입니다.
6. **Ambient particles**: 먼지, 반딧불, 낙엽, 물결 같은 작은 움직임을 적게, 그러나 꾸준히 둡니다.

### 10.2 Flame 구현 패턴

```dart
class BlobShadow extends PositionComponent {
  static final _paint = Paint()..color = const Color(0x55000000);

  BlobShadow({required Vector2 size}) : super(size: size, anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    canvas.drawOval(size.toRect(), _paint);
  }
}

class IsoActor extends PositionComponent {
  late final BlobShadow shadow;
  late final SpriteAnimationComponent body;

  @override
  Future<void> onLoad() async {
    shadow = BlobShadow(size: Vector2(38, 12))
      ..position = Vector2(0, -4)
      ..priority = -1;
    body = SpriteAnimationComponent(anchor: Anchor.bottomCenter);
    addAll([shadow, body]);
  }
}
```

> 그림자는 캐릭터 sprite 안에 baked하지 말고 별도 component로 두는 편이 좋습니다. 몬스터 크기, 지형 밝기, 은신/피격 효과에 따라 따로 조정할 수 있습니다.

### 10.3 아트 품질 게이트

- [ ] 0.75x, 1.0x, 1.5x 줌에서 캐릭터 실루엣이 읽힌다.
- [ ] 캐릭터 발 위치와 클릭 이동 목적지가 1타일 이상 어긋나지 않는다.
- [ ] 큰 건물 뒤/앞/옆을 지나갈 때 가림 전환이 튀지 않는다.
- [ ] 맵에 `collision`, `nav`, `spawn`, `trigger` debug overlay를 켜도 데이터가 설명 가능하다.
- [ ] 30개 이상의 y-sort object와 20개 이상의 actor가 있어도 60fps를 유지한다.

---

## 11. 실습 프로젝트 — "2.5D RPG Prototype"

### 11.1 요구사항
- Tiled로 만든 마을 맵 (50×50, ground/objects/collision/spawn)
- 8방향 캐릭터 (idle, walk 최소)
- WASD + 클릭 이동 (둘 다)
- Depth Sorting 완벽 작동 (검증 시나리오 4.5 참조)
- 카메라 follow + zoom + bounds
- 정적 충돌 (나무, 벽, 물)
- NPC 3명 배치 (말걸기는 단순 텍스트 표시)
- HUD: FPS, 미니맵 (단순한 사각형도 OK)

### 11.2 폴더 구조
```
phase3_iso/
├── lib/
│   ├── main.dart
│   └── game/
│       ├── iso_game.dart
│       ├── iso_math.dart          // 변환 함수
│       ├── world/
│       │   ├── iso_world.dart     // Tiled 로딩
│       │   ├── tree.dart
│       │   ├── building.dart
│       │   └── static_collider.dart
│       ├── actors/
│       │   ├── iso_actor.dart     // 8방향 베이스
│       │   ├── player.dart
│       │   └── npc.dart
│       └── hud/
└── assets/
    ├── tiles/*.tmx, *.tsx, *.png
    └── sprites/*.png
```

### 11.3 검증 시나리오 (반드시 통과)
- [ ] 캐릭터가 나무 뒤로 들어갈 때/나올 때 가려짐이 자연스러움
- [ ] 두 캐릭터가 교차할 때 Y가 큰 쪽이 앞 (= 화면 아래쪽이 앞)
- [ ] 8방향 walk 애니메이션이 이동 방향과 일치
- [ ] 클릭 위치를 정확히 월드 타일로 변환 (디버그 표시로 확인)
- [ ] 50×50 맵에서 60fps 유지
- [ ] 충돌 시 캐릭터가 벽을 통과하지 않음

---

## 12. 시니어가 빠지기 쉬운 함정

### 12.1 "스크린 좌표 = 월드 좌표"
- 클릭 이벤트의 좌표는 **스크린**. cam을 거쳐 월드로 변환 후, 다시 IsoMath로 타일로.

### 12.2 "anchor를 center로"
- Isometric에선 발(base) 기준. **bottomCenter** 필수. 안 그러면 Depth Sorting이 미묘하게 어긋남.

### 12.3 "priority를 정수 y로만"
- 같은 y에 객체 둘 있으면 깜빡임. `y * 1000 + uniqueOrder` 같이.

### 12.4 "Tiled의 모든 레이어를 TiledComponent에 맡김"
- 정적이지만 캐릭터와 sort 되어야 하는 객체는 **World 자식으로 분리** 필요. 안 그러면 항상 캐릭터 뒤에 그려짐.

### 12.5 "Isometric 변환을 매 프레임 모든 객체에"
- N개 객체 × 변환 비용 = 부담. 위치가 안 바뀌면 캐시.

### 12.6 "충돌 영역을 다이아몬드로"
- 이론적으로는 맞지만 코드/디버깅이 폭발. AABB로 충분, 시각적으로 발 부근에 작은 사각형.

### 12.7 "Tiled 맵이 너무 크면 그냥 .tmx 하나"
- 200×200 넘기면 로딩 시간 + 메모리 폭발. 처음부터 청크 단위 폴더 구조로.

### 12.8 "Stardew처럼 Top-Down에 가까운 2.5D 와 진짜 Iso 혼동"
- Stardew = top-down + 약간의 perspective. Diablo/RO = true isometric. **본인이 원하는 룩을 명확히** 정한 후 Tiled 설정.

---

## 13. 추천 학습 순서 (3주)

| 주차 | 내용 |
|---|---|
| 1주차 | IsoMath 구현 → 단일 캐릭터 + 단일 타일 1개 → 좌표 변환 디버그 |
| 2주차 | Tiled 맵 1개 만들고 로딩 → 정적 충돌 → 8방향 walk |
| 3주차 | Depth Sorting 완벽 → NPC + 미니맵 + 카메라 polish |

---

## 14. 이 Phase에서 도입할 Flame 공식 패키지

| 패키지 | 용도 | 코멘트 |
|---|---|---|
| **`flame_tiled`** | Tiled 맵 로딩 (Orthogonal/Isometric/Staggered/Hexagonal 모두 지원) | 본 Phase 필수. transitive로 `tiled`(0.11.1) 도 자동 |
| **`flame_kenney_xml`** | Kenney.nl CC0 자산 (UI 아이콘, 미니맵 마커, 디버그 아이콘) | UI 빠르게 채우기에 유용 |
| **`flame_fire_atlas`** *또는* **`flame_texturepacker`** | 스프라이트 atlas (Phase 3 후반) | 스프라이트 30+ 이상 도달 시. FireAtlas는 Flame 팀 자체 오픈 에디터, TexturePacker는 더 강력하나 유료 Pro |

```yaml
dependencies:
  flame_tiled: ^3.1.1
  flame_kenney_xml: ^0.1.2+1
  # 후반에:
  flame_fire_atlas: ^1.8.17
  # 또는
  # flame_texturepacker: ^5.1.1
```

> ⚠️ Atlas 도입 시 **이름 컨벤션 라벨링 SSOT 선행 작성** — `player_walk_e_0`, `slime_attack_n_2` 같은 키 규칙. 안 하면 row 인덱스보다 atlas 키가 더 디버깅 어려워집니다.

> 본 코스의 전체 패키지 카탈로그는 [flame-official-packages.md](./flame-official-packages.md) 참조.

### 14.1 flame 1.37.0의 Isometric·성능·연출 관련 신기능

flame **1.37.0**(2026-04-01 출시, Dart SDK `>=3.11.0 <4.0.0` / Flutter `>=3.41.0`)에서 본 Phase(및 Phase 7 최적화)에 유용한 변경:

- **Block을 isometric tile map component에서 분리**(#3859) — isometric 타일맵 컴포넌트 내부 구조 변경 + 헬퍼 메서드 추가.
- **`SpriteBatch`에 `bleed` 옵션**(#3871) — 타일맵 seam(이음새) 방지(§5.4 참조).
- **`HasAutoBatchedChildren` mixin**(#3850) — 자식 렌더를 자동 배칭해 draw call을 줄이는 성능 최적화. 타일/스프라이트가 많은 Iso 맵에 유리.
- **`HueEffect` + `HueDecorator`**(#3852) — 색조 이펙트. 낮/밤 전환, 피격 플래시, 존(zone)별 분위기 연출에 활용.
- **`OverlayManager.setActive()`**(#3875) — 오버레이(HUD/대화창) 활성 상태를 직접 제어.

> ⚠️ **버전 주의**: `SpawnComponent`의 `target`/`spawnCount`, `RasterSpriteComponent.fromImage`는 1.37.0이 아니라 **1.30.0** 신기능입니다. "부모가 트리에서 제거돼도 자식이 부모 참조 유지"(BREAKING)는 **1.29.0**, `HasGameRef → HasGameReference` deprecate(#3559)는 **1.28.0** 입니다. 신기능을 소개할 때 도입 버전을 정확히 명시하세요. 출처: [flame CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md)

> 객체 풀링이 필요한 투사체/이펙트 대량 생성·제거는 flame **1.36.0**의 `ComponentPool`(#3816)을 Phase 7에서 함께 다룹니다.

---

## 15. 학습 자료

- Tiled 공식: https://doc.mapeditor.org/en/stable/manual/introduction/
- flame_tiled docs: https://pub.dev/packages/flame_tiled
- flame_tiled 공식 가이드 (Orthogonal/Isometric/Staggered/Hexagonal 네 투영): https://docs.flame-engine.org/latest/bridge_packages/flame_tiled/tiled.html
- TiledComponent API (load 옵션 atlasMaxX/atlasMaxY, getLayer): https://pub.dev/documentation/flame_tiled/latest/flame_tiled/TiledComponent-class.html
- Flame Collision Detection (World에 HasCollisionDetection / QuadTree): https://docs.flame-engine.org/latest/flame/collision_detection.html
- Clint Bellanger "Isometric Math": https://clintbellanger.net/articles/isometric_math/
- Tiled TMX/JSON 포맷: https://doc.mapeditor.org/en/stable/reference/tmx-map-format/ / https://doc.mapeditor.org/en/stable/reference/json-map-format/
- Aseprite docs: https://www.aseprite.org/docs/
- TexturePacker docs: https://www.codeandweb.com/texturepacker/documentation
- Rive docs: https://rive.app/docs
- Spine user guide: https://esotericsoftware.com/spine-user-guide
- Spritesheet: KayKit, Cute Adventurers (itch.io)
- 전체 2.5D/아트/VFX 출처 목록: [resources.md §0.2](./resources.md)

---

## 16. 학습 후 메모 (직접 작성)

- Depth Sorting을 끝내고 얻은 통찰:
- Tiled로 맵 제작하며 알게 된 워크플로우:
- Phase 4로 가져갈 IsoActor 베이스 클래스 설계:

---

## 17. 다음 단계

[04-phase4-rpg-systems.md](./04-phase4-rpg-systems.md) — 위에서 만든 2.5D 그릇 위에 RPG 시스템(Entity, Stats, Combat, Inventory)을 쌓습니다.
