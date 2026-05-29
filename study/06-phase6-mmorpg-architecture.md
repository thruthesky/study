# Phase 6 — MMORPG 구조 (대규모 월드)

> **기간**: 4주 이상
> **목표**: Phase 5의 2명 동기화를 **수백 명**으로 확장한다. Interest Management, Spatial Partitioning, Zone Server, Chunk Streaming, Cross-Zone 통신.

---

## 0. 2026-05 기준 서버 버전과 책임 경계

| 영역 | 기준 | 사용 방식 |
|---|---:|---|
| Nakama Server | **3.39.0** (2026-05-20) | 인증/계정/친구/길드/우편/채팅/매치메이킹/리더보드/Storage RPC. 3.39.0 실제 신규는 **storage 객체 재시도 업데이트 런타임 함수**와 **Satori 클라이언트 구성 가능 재시도** |
| nakama-common (Go module) | **v1.46.0** (2026-05-20) | Nakama Go 런타임 빌드 의존성 — `go get github.com/heroiclabs/nakama-common/runtime@v1.46.0` 로 정확한 버전 고정 필수 (⚠️ 3.39.0 릴리즈 노트 본문엔 호환 버전 명시 누락, 동일자 출시 v1.46.0이 짝) |
| Nakama Dart SDK | **1.3.0** (≈11개월 전, 2025-06~07) | Flutter 클라이언트에서 로그인, 세션, socket, RPC 호출. ⚠️ SDK 정체로 Nakama 3.39 서버 신기능은 raw RPC/socket 우회 필요 |
| Go | **1.26.3** (2026-05-07, 보안 패치) | Gateway와 UDP Zone Server 구현. **Green Tea GC** 기본 활성화(1.26.0=2026-02-10 도입)로 **GC 오버헤드 10~40% 감소**, cgo 호출 오버헤드 ~30% 감소 |
| Protobuf | Dart `protobuf 6.0.0` + Go `google.golang.org/protobuf v1.36.11`(APIv2) + protoc **v35.0** | UDP packet schema 공유. protoc(v35.x)와 Go 런타임(v1.36.x)은 버전 체계가 다르며 독립 릴리즈 주기(약 5개월 간극은 정상) |
| Redis | **8.x (8.6.3)** 이상 (2026-05-05) | zone ticket cache, pub/sub, transient session cache. 클러스터링·스트림 안정성 개선 |
| PostgreSQL | **18.x(18.4 권장) 또는 17.x(17.10)** | Nakama 영속 DB. PostgreSQL 본체는 **LTS 개념이 없고 모든 메이저가 출시 후 5년 지원**. Nakama Docker 기본 `postgres:12.2-alpine` 은 EOL이므로 갱신 필수 |

**절대 경계**:
- Nakama에 실시간 이동/전투 tick을 넣지 않습니다.
- Go Zone Server가 PostgreSQL에 직접 쓰지 않습니다.
- Zone Server는 Nakama에서 발급한 짧은 수명 `zone_join_ticket`만 검증합니다.
- 캐릭터/인벤토리/골드의 단일 영속 원천은 Nakama Storage/RPC입니다.

> **공식 입장(2026-05) — 정확한 뉘앙스**: Heroic Labs 공식 문서는 멀티플레이를 **relayed**(클라이언트 권위), **authoritative**(서버 권위, Match Handler), **session-based**, **turn-based** 의 여러 모델로 제시하며 *"즉시 사용 가능한 일반 시나리오는 없으니 게임 요구에 맞춰 직접 정의하라"* 고 안내합니다. 즉 "모든 게임에서 Match Handler를 1순위로 권장"한다는 단정은 과장이며, 정확히는 **조건부 권장**입니다.
>
> - **빠른 실시간 + 서버측 검증(치트 방지)이 필요** → authoritative **Match Handler**(서버 권위)
> - **검증이 덜 필요하고 지연 최소화가 우선** → **relayed**(클라이언트 권위, 서버는 메시지 중계만)
> - **턴제/세션 단위** → turn-based / session-based
>
> 본 코스의 자체 Go UDP Zone Server는 **Nakama Match의 단일 프로세스·GC 제약을 넘어서는 고부하 실시간**을 가정한 학습용 구성입니다. Nakama는 **오케스트레이션 레이어**(매치메이킹 → 인스턴스 할당 → 결과 보고)로 사용하고, tick 시뮬레이션만 외부 Zone Server로 분리합니다. 일반화된 표준이 아니라 학습 목적의 의도적 분리임을 유지하세요.
> 출처: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/

### 0.1 Nakama 신규 기능의 정확한 버전 매핑 (혼동 주의)

이 코스 초안과 많은 블로그가 매칭/파티 기능을 "3.39 신규"로 잘못 표기합니다. 실제 도입 버전은 다음과 같습니다.

| 기능 | 실제 도입 버전 | 출시일 |
|---|---|---|
| Party Listing API + Party Label | **v3.28.0** | 2025-07-14 |
| `MatchmakerProcessor` 훅(전체 티켓 풀 커스텀 매칭) | **v3.29.0** | 2025-07-29 |
| storage 객체 재시도 업데이트 런타임 함수 | **v3.39.0** | 2026-05-20 |
| Satori 클라이언트 구성 가능 재시도 | **v3.39.0** | 2026-05-20 |
| 매치메이커 엔트리 create time 런타임 노출 | **v3.39.0** | 2026-05-20 |

→ 매칭/파티 기능을 설명할 때는 **"3.28~3.29(2025-07)에 도입"** 으로 적고, "3.39 신규"라는 라벨은 제거하세요. 3.39.0의 실제 핵심은 storage 재시도와 Satori 재시도입니다.

> **빌드 의존성 고정**: Nakama 릴리즈 노트는 보통 버전별 호환 `nakama-common`을 `nakama-common @ vX.Y.Z must be used` 형식으로 명시합니다(3.37.0→v1.44.2, 3.38.0→v1.45.0). 3.39.0 본문엔 명시가 누락됐으나 동일자(2026-05-20) 출시된 v1.46.0이 짝입니다. Go 런타임 모듈은 반드시 정확히 고정하세요.
> ```bash
> go get github.com/heroiclabs/nakama-common/runtime@v1.46.0
> ```
> 출처: https://github.com/heroiclabs/nakama/releases , https://github.com/heroiclabs/nakama-common/releases

---

## 1. 학습 목표

- [ ] **Interest Management (AoI)** 구현 — 주변 entity만 전송
- [ ] **Spatial Partition** (Grid / QuadTree) — N×N 검색 제거
- [ ] **Chunk World** — 거대한 맵을 청크 단위 스트리밍
- [ ] **Zone Server** — 맵을 여러 프로세스로 분할
- [ ] **Cross-Zone Migration** — 플레이어가 zone 경계 넘기
- [ ] **Pub/Sub** (Redis/NATS) — Zone 간 메시지 버스
- [ ] **Login Server / Gateway Server** 패턴

---

## 2. 왜 Phase 5 구조로는 부족한가

Phase 5는 "한 프로세스 / 한 맵 / 모두에게 모두 송신". 100명 들어오면:

| 문제 | 영향 |
|---|---|
| 매 tick 100×100 entity 검사 | CPU 폭발 |
| 매 tick 100명에게 100개 entity 송신 = 10,000 메시지 | 대역폭 폭발 |
| 한 프로세스에 다 올림 | CPU 코어 1개만 사용, GC 폭발 |
| 한 서버 죽으면 모두 끊김 | 단일 장애점 |

→ **세 가지 분리 차원** 도입:
1. **Spatial** (공간) → AoI + QuadTree
2. **Logical** (논리) → Zone Server 분할
3. **Functional** (기능) → Login / Meta / Realtime / Chat 서버 분리

---

## 3. Interest Management (AoI)

### 3.1 개념
> "한 플레이어는 자기 주변 entity만 보면 된다."

플레이어 P 주변 반경 R 안에 있는 entity만 그 플레이어에게 송신.

### 3.2 단순 구현 (그리드 기반)
```
World를 cell 단위로 분할 (예: 256×256 픽셀)
각 cell은 안에 있는 entity 목록 보관
플레이어 P의 AoI = P의 cell ± 1 (= 9개 cell)
```

```go
type CellKey struct{ X, Y int }

type Grid struct {
    cells    map[CellKey]map[EntityID]struct{} // 셀별 entity 집합
    entityAt map[EntityID]CellKey              // entity의 현재 셀 (역인덱스)
    cellSize float64
}

func newGrid(cellSize float64) *Grid {
    return &Grid{
        cells:    map[CellKey]map[EntityID]struct{}{},
        entityAt: map[EntityID]CellKey{},
        cellSize: cellSize,
    }
}

func (g *Grid) toCell(x, y float64) CellKey {
    // 음수 좌표에서도 안정적으로 내림(floor)
    return CellKey{int(math.Floor(x / g.cellSize)), int(math.Floor(y / g.cellSize))}
}

// Move: entity가 이동할 때 셀이 바뀌면 역인덱스로 O(1) 재배치.
// 매 tick 모든 셀을 재구성하지 않는 것이 핵심 — entity 단위 증분 갱신.
func (g *Grid) Move(id EntityID, pos Vec2) {
    newC := g.toCell(pos.X, pos.Y)
    if oldC, ok := g.entityAt[id]; ok {
        if oldC == newC {
            return // 같은 셀 → 작업 없음 (대부분의 tick)
        }
        delete(g.cells[oldC], id)
        if len(g.cells[oldC]) == 0 {
            delete(g.cells, oldC) // 빈 셀 정리 (메모리 + iteration 비용)
        }
    }
    if g.cells[newC] == nil {
        g.cells[newC] = map[EntityID]struct{}{}
    }
    g.cells[newC][id] = struct{}{}
    g.entityAt[id] = newC
}

func (g *Grid) Remove(id EntityID) {
    if c, ok := g.entityAt[id]; ok {
        delete(g.cells[c], id)
        if len(g.cells[c]) == 0 {
            delete(g.cells, c)
        }
        delete(g.entityAt, id)
    }
}

// Neighbors9: 표준 AoI — 중심 셀 ±1 (= 3×3 = 9개 셀)만 순회.
// cellSize >= AoI 반경이면 9-cell 안에 시야 후보가 모두 들어온다.
func (g *Grid) Neighbors9(pos Vec2, out []EntityID) []EntityID {
    c := g.toCell(pos.X, pos.Y)
    out = out[:0] // caller가 슬라이스를 재사용해 할당 0
    for dx := -1; dx <= 1; dx++ {
        for dy := -1; dy <= 1; dy++ {
            for id := range g.cells[CellKey{c.X + dx, c.Y + dy}] {
                out = append(out, id)
            }
        }
    }
    return out
}
```

> **9-cell 설계 규칙**: `cellSize`를 **AoI 반경 이상**으로 잡으면, 어떤 위치에서든 시야 안 entity가 반드시 자신의 셀 + 인접 8셀(총 9셀) 안에 존재합니다. 그래서 임의 반경 박스(`minC..maxC`)를 도는 대신 **고정 3×3 순회**로 끝납니다. 셀이 시야보다 작으면 도는 셀 수가 늘고, 너무 크면 한 셀에 entity가 몰려(클러스터링) 9-cell이 비대해지므로, `cellSize ≈ AoI 반경` 근처가 sweet spot입니다. (zinx 기반 Go 레퍼런스: https://dev.to/aceld/11-mmo-online-game-aoi-algorithm-l7d )

### 3.3 Enter / Leave 이벤트
플레이어 P의 AoI에 새로 들어오는 entity → `entity_enter` 전송
나가는 entity → `entity_leave` 전송
그 외엔 위치 업데이트만.

```go
prevSet := lastAoI[playerID]
currSet := computeAoI(playerID) // = §3.2 Neighbors9 후보를 반경 R로 한 번 더 필터
for id := range currSet { if !prevSet[id] { send(playerID, "entity_enter", id) } }
for id := range prevSet { if !currSet[id] { send(playerID, "entity_leave", id) } }
for id := range currSet { send(playerID, "entity_update", id) }
```

- `computeAoI`는 §3.2의 `Neighbors9`로 9-cell 후보를 모은 뒤(저렴), 실제 거리 `R`로 한 번 더 걸러 정확한 시야를 만듭니다. cell이 시야보다 크면 후보에 시야 밖 entity가 섞이므로 이 거리 필터가 필요합니다.
- `entity_enter`는 §7.1의 **full state(Spawn)** 로 보냅니다(delta 기준이 없으므로). `entity_update`만 delta·bit pack 대상입니다.
- diff 비용을 줄이려면 `currSet`/`prevSet`을 `map[EntityID]struct{}` 대신 정렬된 슬라이스로 두고 병합 정렬식 diff를 쓰는 방법도 있으나, AoI 크기가 수십 단위면 map diff로 충분합니다.

### 3.4 AoI radius 결정
- 화면 크기 + 약간의 여유 (스크롤 시 안 끊기게)
- 너무 작으면 자주 enter/leave → 깜빡임
- 너무 크면 트래픽 폭발

---

## 4. Spatial Partition

### 4.1 Grid (Uniform Spatial Hash) — 2026 모바일 MMO 표준
- 구현 단순, 균일 분포에 최적
- **uniform grid + neighbor 9-cell** 검색이 2025~2026 모바일 MMO 기본
- 클러스터링 심하면 한 cell이 폭발 → 부분적으로 분할 필요
- 한국·중국 권에서 가장 많이 인용되는 zinx 기반 Go 레퍼런스: https://dev.to/aceld/11-mmo-online-game-aoi-algorithm-l7d

### 4.2 QuadTree
- 동적 분할, 클러스터링에 강함
- 구현 복잡, 갱신 비용 있음 (entity가 움직이면 노드 재배치)
- 동적/희소 월드에는 **non-blocking concurrent quadtree (Quadboost)** 권장 (arxiv:1607.03292)
- P2P/엣지 하이브리드에는 **Octopus-style multi-resolution grid**
- 연속 좌표 색인은 quad-tree(2D) / R-tree, 3D 월드는 **octree** 사용

```go
// 최소 QuadTree: 단일 goroutine(zone tick)에서만 접근한다는 전제.
// 멀티 goroutine 동시 접근이 필요하면 Quadboost류 lock-free 구조로 교체.
type Rect struct{ X, Y, W, H float64 }

func (r Rect) Contains(p Vec2) bool {
    return p.X >= r.X && p.X < r.X+r.W && p.Y >= r.Y && p.Y < r.Y+r.H
}
func (r Rect) Intersects(o Rect) bool {
    return r.X < o.X+o.W && r.X+r.W > o.X && r.Y < o.Y+o.H && r.Y+r.H > o.Y
}

const qtCapacity = 8 // 한 노드가 분할 전까지 담는 entity 수

type item struct {
    id  EntityID
    pos Vec2
}

type QuadNode struct {
    bounds   Rect
    items    []item
    children [4]*QuadNode // nil이면 leaf
}

func (n *QuadNode) Insert(it item) bool {
    if !n.bounds.Contains(it.pos) {
        return false
    }
    if n.children[0] == nil {
        if len(n.items) < qtCapacity {
            n.items = append(n.items, it)
            return true
        }
        n.subdivide()
    }
    for i := range n.children {
        if n.children[i].Insert(it) {
            return true
        }
    }
    // 경계 부동소수 오차 대비 fallback
    n.items = append(n.items, it)
    return true
}

func (n *QuadNode) subdivide() {
    b := n.bounds
    hw, hh := b.W/2, b.H/2
    n.children[0] = &QuadNode{bounds: Rect{b.X, b.Y, hw, hh}}
    n.children[1] = &QuadNode{bounds: Rect{b.X + hw, b.Y, hw, hh}}
    n.children[2] = &QuadNode{bounds: Rect{b.X, b.Y + hh, hw, hh}}
    n.children[3] = &QuadNode{bounds: Rect{b.X + hw, b.Y + hh, hw, hh}}
    // 기존 items를 자식으로 재분배
    old := n.items
    n.items = n.items[:0]
    for _, it := range old {
        placed := false
        for i := range n.children {
            if n.children[i].Insert(it) {
                placed = true
                break
            }
        }
        if !placed {
            n.items = append(n.items, it)
        }
    }
}

// Query: AoI 반경 사각형과 겹치는 노드만 재귀 → 전수검색 회피
func (n *QuadNode) Query(area Rect, out []EntityID) []EntityID {
    if !n.bounds.Intersects(area) {
        return out
    }
    for _, it := range n.items {
        if area.Contains(it.pos) {
            out = append(out, it.id)
        }
    }
    if n.children[0] != nil {
        for i := range n.children {
            out = n.children[i].Query(area, out)
        }
    }
    return out
}
```

> **이동 갱신 트레이드오프**: QuadTree는 entity가 이동할 때 노드 재배치(remove → re-insert)가 필요해 **고밀도·고빈도 이동**(전투 zone)에서는 매 tick 전체 트리를 다시 쌓는 편이 캐시 친화적일 때가 많습니다. 반대로 **희소·정적**(넓은 필드, 채집물·NPC)에서는 grid보다 메모리·검색이 유리합니다. 본 코스 권장은 *"실시간 전투 zone = Grid 증분 갱신, 희소 오픈필드 = QuadType 재구성"* 의 하이브리드입니다.

### 4.3 본 코스 권장
- **Grid부터 시작** (1주차) — uniform 256×256 픽셀 cell + 9-cell 인접 검색
- 동작 후 QuadTree로 전환 학습 (2주차)
- 둘 다 만들어 보면 trade-off 통찰

---

## 5. Chunk World

### 5.1 개념
거대한 맵 (예: 10000×10000)을 chunk(예: 256×256 픽셀) 단위로 분할.
- 클라: 카메라 주변 chunk만 로드
- 서버: entity가 있는 chunk만 활성화

### 5.2 클라 측 Chunk Streaming
```dart
class ChunkLoader {
  final Map<ChunkKey, ChunkComponent> loaded = {};
  static const radius = 2;   // 5x5 chunks

  void update(Vector2 cameraPos) {
    final center = _chunkOf(cameraPos);
    final wanted = <ChunkKey>{};
    for (var dx = -radius; dx <= radius; dx++)
      for (var dy = -radius; dy <= radius; dy++)
        wanted.add(ChunkKey(center.x + dx, center.y + dy));

    // 언로드
    loaded.keys.where((k) => !wanted.contains(k)).toList()
        .forEach((k) { loaded[k]!.removeFromParent(); loaded.remove(k); });
    // 로드
    for (final k in wanted) {
      if (!loaded.containsKey(k)) {
        final c = ChunkComponent(key: k);
        loaded[k] = c;
        world.add(c);
      }
    }
  }
}
```

### 5.3 서버 측 Chunk
- 비활성 chunk의 몬스터는 simulation 안 함
- 플레이어가 가까이 오면 활성화 (= 몬스터 spawn)

---

## 6. Zone Server (수평 확장)

### 6.1 개념
한 거대한 월드를 여러 zone(예: 마을 / 던전 A / 던전 B)으로 분할.
- Zone 1 → 프로세스 1 (서버 머신 1)
- Zone 2 → 프로세스 2 (서버 머신 1 또는 2)
- 플레이어가 zone 경계 통과 → 다른 프로세스로 이전

### 6.2 본 코스 확정 아키텍처

```
                         [Flutter Flame Client]
                          │                    │
                  HTTPS / WS                  UDP
                          │                    │
                  ┌───────▼────────┐    ┌──────▼──────────────┐
                  │ Nakama Meta    │    │ Gateway (Go)        │
                  │  - Auth / JWT  │    │  - Ticket 검증      │
                  │  - Character   │    │  - Zone Routing     │
                  │  - Friend/Mail │    └──────┬──────────────┘
                  │  - Chat (글로벌)│           │
                  │  - Matchmaking │     ┌─────┼─────┬─────┐
                  │  - Leaderboard │     ▼     ▼     ▼     ▼
                  └────────┬───────┘  [Zone1][Zone2][Zone3][Inst.D]
                           │                  Go UDP, 30Hz, AoI
                           │           ┌──────┴──────────────┐
                           │           │ Redis (Pub/Sub)     │
                           ▼           │  - zone 간 채팅      │
                  [PostgreSQL]         │  - 길드 이벤트       │
                   (Nakama 영속)        └─────────────────────┘
```

- **Nakama Meta Server**: 인증, 캐릭터, 친구, 길드, 우편, 글로벌 채팅, 매치메이킹, 리더보드. 영속 DB(PostgreSQL)를 직접 관리.
- **Gateway (자체 Go)**: 클라가 Nakama로부터 받은 zone-join ticket을 검증하고, 해당 zone으로 UDP 핸드셰이크를 중계. 부하 분산도 담당.
- **Zone Server (자체 Go UDP)**: 실시간 게임 로직(이동/전투/스킬), tick 30Hz, AoI. 영속 변경(아이템 획득, 골드 변동)은 **Nakama RPC**로 보고. PostgreSQL에 직접 쓰지 않음.
- **Redis Pub/Sub**: Zone 간 메시지(존 채팅, 길드 이벤트, 시스템 broadcast).

### 6.3 Zone Migration

```
1. 플레이어 P가 Zone1의 경계로 진입
2. Zone1: P 상태 직렬화 → Redis에 저장 → Gateway에 "migrate P → Zone2" 알림
3. Gateway: Zone2에게 P 정보 전달 → Zone2: P spawn → 클라에 "switch zone" 알림
4. 클라: Zone2 chunks 로딩 → 화면 전환
5. Zone1: P 제거
```

이게 매끄러우려면 **2~3초 로딩 화면** 또는 **seamless** (양쪽 zone에 잠깐 동시 존재) 패턴이 필요.

> 시니어 팁: 처음엔 **명시적 로딩 화면 zone 전환**으로 시작. Seamless는 후순위.

#### 6.3.1 Migration race condition — 분산 환경의 진짜 난관

이 5단계는 의사코드일 뿐이고, 실제로는 "P의 권위 소유권(authority)이 정확히 한 zone에만 있어야 한다"는 불변식을 깨는 race가 줄줄이 터집니다. 풀스택 경력자에게 익숙한 분산 트랜잭션 문제와 동일합니다.

**문제 1 — 이중 시뮬레이션(double-sim).** Zone1이 직렬화·송신하는 사이에도 tick은 계속 돕니다. Zone2가 P를 spawn한 순간부터 Zone1이 P를 제거하기 전까지 **두 zone이 동시에 P를 시뮬레이션**하면, 양쪽이 서로 다른 권위 상태를 만들고 클라는 둘 다 받습니다.
→ 해법: **handoff 토큰 + 상태 머신**. P의 상태를 `Active → Migrating(읽기전용) → Departed` 로 둡니다. `Migrating` 진입 즉시 Zone1은 P의 입력을 더 이상 적용하지 않고(freeze) 위치만 보간용으로 유지합니다. Zone2의 `MigrationAck`를 받은 tick에서만 `Departed`로 내려 완전 제거합니다.

**문제 2 — 분실(lost in transit).** "migrate" 알림이나 직렬화 payload가 유실되면 P가 어느 zone에도 없게 됩니다.
→ 해법: **migration 자체는 reliable 경로**(Redis 또는 gRPC, 위치 패킷의 unreliable UDP 아님)로 보내고, **ownership epoch(단조 증가 정수)** 를 함께 넘깁니다. Zone2는 더 낮은 epoch의 늦게 도착한 중복 handoff를 무시합니다(idempotent).

**문제 3 — in-flight 입력.** 클라가 "switch zone"을 받기 전에 보낸 입력 UDP 패킷이 Zone1에 늦게 도착합니다.
→ 해법: 패킷에 `zoneEpoch`(또는 zoneId)를 실어 보내고, zone은 자신의 현재 epoch과 다른 입력은 **조용히 버립니다**. 클라는 ack 받은 zone으로만 입력 송신.

**문제 4 — 동시 양방향 진입.** 두 플레이어가 동시에 서로 반대 경계를 넘거나, 한 플레이어가 경계에서 떨려(jitter) `migrate`를 연속 두 번 트리거.
→ 해법: 경계에 **히스테리시스(hysteresis)** 를 둡니다. 진입 임계선과 복귀 임계선을 다르게(예: x>1000에서 넘어가고 x<980에서만 되돌아옴) 잡아 떨림에 의한 핑퐁 마이그레이션을 막습니다. 또 `Migrating` 상태에서는 추가 migrate 트리거를 무시.

**문제 5 — 권위 소유권의 단일화.** epoch만으로 부족할 때는 **Redis 분산 락**(`SET owner:{playerId} {zoneId} NX EX 5`)으로 "지금 P를 시뮬레이션할 권리"를 1개 zone만 갖게 합니다. Zone2는 락 획득 후에만 spawn, Zone1은 락 소유 zone이 바뀌면 즉시 freeze.

```go
// 권위 상태 머신 (zone tick goroutine 안에서만 전이 → 자체적으로 직렬화됨)
type MigrationState int

const (
    Active    MigrationState = iota // 입력 적용 + 시뮬레이션 + 송신
    Migrating                       // 입력 무시(freeze), 위치만 유지, Ack 대기
    Departed                        // 제거 예약
)

type Player struct {
    ID       EntityID
    State    MigrationState
    Epoch    uint64 // ownership epoch, handoff마다 +1
    deadline time.Time
}

// 경계 진입 감지 (히스테리시스)
func (z *Zone) checkBoundary(p *Player, pos Vec2) {
    if p.State != Active {
        return // 이미 이전 중 → 재트리거 금지
    }
    if pos.X > z.exitX { // 진입 임계선
        p.State = Migrating
        p.Epoch++
        p.deadline = time.Now().Add(3 * time.Second) // 타임아웃 가드
        // reliable 경로로 handoff (epoch + 직렬화 상태)
        z.handoff <- MigrationRequest{
            Player: serialize(p), Epoch: p.Epoch, To: "zone2",
        }
    }
}

// Zone2가 MigrationAck를 보내면, 이 tick에서만 Departed로 내려 제거
func (z *Zone) onMigrationAck(ack MigrationAck) {
    p := z.players[ack.ID]
    if p == nil || ack.Epoch != p.Epoch {
        return // stale ack 무시 (idempotent)
    }
    p.State = Departed
}

// drainInputs 안: 자기 epoch과 다른 입력은 버린다
func (z *Zone) applyInput(in Input) {
    p := z.players[in.PlayerID]
    if p == nil || p.State != Active || in.ZoneEpoch != p.Epoch {
        return // in-flight / stale / freeze 상태 입력 폐기
    }
    // ... 정상 입력 적용
}
```

> **타임아웃 가드 필수**: `Migrating` 상태에서 `deadline`이 지나도 Ack가 없으면(Zone2 다운 등), Zone1은 P를 다시 `Active`로 복구하거나 안전 위치로 강제 텔레포트해야 합니다. 그렇지 않으면 P가 영영 freeze된 채 "유령"이 됩니다.

### 6.4 Go UDP Zone Server에서 반드시 공부할 것

| 주제 | 왜 필요한가 | 확인할 문서 |
|---|---|---|
| `net.PacketConn` / `net.UDPConn` | UDP read/write, client endpoint 관리 | Go `net` package |
| fixed tick loop | 30Hz authoritative simulation | `time.NewTicker`, tick drift 측정 |
| single goroutine simulation | lock 없는 결정론적 zone state | channel inbox/outbox 패턴 |
| packet MTU | fragmentation 회피 | IPv6 최소 MTU 1280 − IP 40 − UDP 8 = **1232B 페이로드 상한**. QUIC도 보수적으로 1200B initial datagram 사용 → 게임 페이로드 **1200~1232B** 권장 |
| sequence/ack | 중복/역전/손실 처리 | unreliable/reliable channel 분리 |
| `sync.Pool` | packet buffer와 snapshot 할당 감소 | Go GC pressure 완화 |
| `pprof` | tick CPU/heap 병목 확인 | `net/http/pprof`, `runtime/pprof`. **Go 1.26 신규 `goroutineleak` 프로파일**(영구 블록 goroutine 탐지)은 zone당 수천 goroutine 누수 진단에 유용 — 단 experiment라 `GOEXPERIMENT=goroutineleakprofile` 빌드 플래그 필요(1.27 기본화 목표) |
| `go test -race` | reader/writer goroutine의 경쟁 검출 | IO와 simulation 경계 검증 |
| Protobuf schema | Dart/Go 패킷 정의 공유 | schema version, reserved field |

권장 루프:

```go
func (z *Zone) Run(ctx context.Context) {
    ticker := time.NewTicker(time.Second / 30)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            z.flushAndShutdown()
            return
        case msg := <-z.inbox:
            z.queueInput(msg)
        case now := <-ticker.C:
            z.drainInputs()
            z.simulate(1.0 / 30.0)
            z.buildSnapshots(now)
            z.enqueueOutbound()
        }
    }
}
```

핵심은 socket goroutine이 게임 상태를 직접 만지지 않는 것입니다. 모든 입력은 `inbox`에 넣고, zone tick goroutine만 world state를 변경합니다.

#### 6.4.1 단일 goroutine tick의 함정과 견고한 루프

위 `select`는 학습용으로 명료하지만 두 가지 약점이 있습니다.

1. **starvation**: `inbox`와 `ticker.C`가 동시에 ready면 Go `select`는 둘 중 하나를 *무작위로* 고릅니다. 입력이 폭주하면 한 tick에 메시지 1개씩만 빼내다 tick이 밀립니다.
2. **tick drift 누적**: `simulate(1.0/30.0)` 처럼 고정 dt를 쓰면, GC·OS 스케줄링으로 실제 경과가 33ms를 넘었을 때 게임 시간이 실제 시간보다 뒤처집니다.

견고한 패턴은 **ticker는 깨우는 신호로만** 쓰고, tick 안에서 `inbox`를 **비차단으로 한꺼번에 drain**한 뒤, **accumulator로 catch-up**합니다.

```go
func (z *Zone) Run(ctx context.Context) {
    const dt = time.Second / 30
    ticker := time.NewTicker(dt)
    defer ticker.Stop()

    last := time.Now()
    var acc time.Duration

    for {
        select {
        case <-ctx.Done():
            z.flushAndShutdown()
            return
        case now := <-ticker.C:
            // 1) inbox를 비차단으로 전부 비운다 (starvation 방지)
            for {
                select {
                case msg := <-z.inbox:
                    z.queueInput(msg)
                default:
                    goto drained
                }
            }
        drained:
            // 2) 실제 경과만큼 고정 스텝을 반복 적용 (drift 보정)
            acc += now.Sub(last)
            last = now
            const maxCatchUp = 5 // 한 번에 5스텝 이상 따라잡지 않음 (death spiral 방지)
            steps := 0
            for acc >= dt && steps < maxCatchUp {
                z.drainInputs()
                z.simulate(dt.Seconds())
                acc -= dt
                steps++
            }
            if acc >= dt {
                acc = 0 // 너무 밀리면 시간을 버리고 현재로 점프 (서버가 멈추는 것보단 낫다)
            }
            // 3) 스냅샷은 tick당 1회만 (시뮬레이션 catch-up과 분리)
            z.buildSnapshots(now)
            z.enqueueOutbound()
        }
    }
}
```

- **lock-free 결정론**: world state를 이 goroutine 하나만 만지므로 `sync.Mutex`가 전혀 없습니다. `go test -race`로 IO goroutine과 tick goroutine의 경계(inbox/outbox 채널만 공유)를 검증하세요.
- **death spiral 방지**: `maxCatchUp`이 없으면 한 번 밀렸을 때 따라잡느라 더 밀리는 악순환에 빠집니다. 따라잡기 상한을 두고, 그래도 못 따라가면 시간을 버립니다(서버 정지보다 낫다).
- **버퍼 채널 + 백프레셔**: `inbox`는 버퍼 채널(`make(chan Msg, N)`)로 두고, 가득 차면 가장 오래된 위치 패킷부터 버리는(drop) 백프레셔를 socket goroutine에 둡니다. 위치는 unreliable이므로 버려도 다음 패킷이 곧 옵니다(§7.3).

---

## 7. 패킷 최적화 (Phase 5 → Phase 6 강화)

### 7.1 Delta Compression
```
Snapshot N에서 entity X의 (x=10, y=20, hp=100)
Snapshot N+1에서 X의 (x=11, y=20, hp=100)
→ N+1 송신: {id:X, dx:1}  (y, hp 생략)
```

**핵심 함정 — baseline을 클라마다 추적해야 한다.** Delta는 "어떤 스냅샷을 기준으로 한 차이인가"가 명확해야 풀립니다. UDP는 손실되므로 "직전에 보낸 스냅샷"을 기준으로 삼으면, 그 스냅샷이 유실된 클라는 delta를 풀 수 없습니다(영원히 깨진 상태). Quake3/Source 계열의 표준 해법은 **클라가 ack한 마지막 스냅샷을 baseline으로** 쓰는 것입니다.

```go
// 서버: 클라별 마지막 ack 스냅샷 번호를 추적
type ClientView struct {
    lastAckedTick uint32
    baseline      map[EntityID]EntityState // 그 시점 상태 (delta 기준)
}

func (z *Zone) buildDeltaFor(c *ClientView, cur map[EntityID]EntityState, tick uint32) Snapshot {
    snap := Snapshot{Tick: tick, BaseTick: c.lastAckedTick}
    for id, s := range cur {
        base, seen := c.baseline[id]
        switch {
        case !seen:
            snap.Spawns = append(snap.Spawns, s)        // 신규 → full state
        case s != base:
            snap.Deltas = append(snap.Deltas, diff(base, s)) // 변경 필드만 (changed-field bitmask)
        }
        // 변경 없으면 아예 보내지 않음 (가장 큰 절감)
    }
    for id := range c.baseline {
        if _, ok := cur[id]; !ok {
            snap.Despawns = append(snap.Despawns, id)   // AoI 이탈/사망
        }
    }
    return snap
}
```

- 각 delta는 **changed-field bitmask**(어떤 필드가 바뀌었는지 1비트씩)를 앞에 붙이고, 켜진 비트의 필드만 직렬화합니다.
- 클라가 `ack(tick)`을 보내오면 서버는 `baseline`을 그 tick 상태로 갱신합니다. ack 못 받으면 baseline을 그대로 둬, 다음 delta가 여전히 풀립니다(self-healing).
- entity가 AoI에 새로 들어오면(§3.3 `entity_enter`) 반드시 **full state(Spawn)** 로 보냅니다 — delta의 기준이 없기 때문입니다.

### 7.2 Bit Packing
- direction은 enum(8개) → 3비트
- bool은 1비트
- 좌표는 월드 한계를 알면 **양자화(quantization)**: 예) x ∈ [0, 8192], 0.25px 정밀도면 15비트로 충분 (float32 32비트 대비 절반 이하)
- → Protobuf, FlatBuffers, 또는 자체 비트 스트림

```go
// 자체 비트 라이터 (최소 예시) — endianness/정렬을 직접 통제할 때
type BitWriter struct {
    buf  []byte
    cur  uint64
    nbit uint8
}

func (w *BitWriter) WriteBits(v uint64, n uint8) {
    w.cur |= (v & ((1 << n) - 1)) << w.nbit
    w.nbit += n
    for w.nbit >= 8 {
        w.buf = append(w.buf, byte(w.cur))
        w.cur >>= 8
        w.nbit -= 8
    }
}

// 좌표 양자화 예: world 8192px, 0.25 정밀도 → 32768단계 = 15비트
func quantize(x float64, max float64, bits uint8) uint64 {
    step := max / float64((uint64(1)<<bits)-1)
    return uint64(x / step)
}
```

> **선택 기준**: 학습·디버깅 단계는 **Protobuf**(스키마 진화·reserved 필드 안전)로 충분합니다. Protobuf varint는 작은 정수를 이미 잘 줄여줍니다. 자체 비트 스트림은 *대역폭이 진짜 병목이고 스키마가 안정된 뒤* 도입하세요 — 직접 만든 비트 패킹은 디버깅·버전 호환이 가장 비쌉니다.

### 7.3 Unreliable Channel for Position
- 위치는 UDP unreliable (잃어도 다음 패킷이 곧 옴)
- HP/스킬/아이템은 reliable (잃으면 안 됨)
- → **Channel 개념** 도입: 같은 UDP 위에 reliable 레이어를 얹습니다.

| 전송 후보 | 특성 | 비고 |
|---|---|---|
| KCP (kcp-go **v5.6.64**) | ARQ 기반 reliable-UDP. lag 발생 시 ENet 대비 **약 3배** 회복 빠름(실측 RTT 40ms vs 139ms), TCP 대비 대역폭 10~20% 추가 | 과거 본문의 "10배"는 과장 — 실측은 ~3~3.5배 |
| QUIC (quic-go **v0.59.1**) | 멀티스트림 + 0-RTT, HTTP/3 호환 | 저손실 양호망에서는 TCP+TLS 대비 계산 효율↓ 보고 다수(수치는 출처 의존) |
| ENet | 검증된 게임용 reliable-UDP | C 라이브러리, Go 바인딩 |
| WebSocket | 방화벽 친화, Flutter Web | reliable·ordered만 — 위치엔 head-of-line blocking 손해 |

- 위치 채널은 **순서 없음(unordered) + 재전송 없음**으로 두고 시퀀스 번호로 stale 폐기만 합니다.
- reliable 채널(HP/스킬/거래)은 KCP/ENet/QUIC 중 하나를 얹거나, 메타 이벤트는 아예 Nakama socket(WS)으로 보냅니다.

---

## 8. 영속화 전략

### 8.1 절대 매 tick DB 저장 금지
- DB write 1ms × 30Hz × 100 player = 3000ms/sec → 폭발

### 8.2 일반 패턴
```
[메모리 = 진실의 현재]
[Redis = 세션 / 잠시 lost 되어도 되는 캐시]
[PostgreSQL = 30초~5분 단위 스냅샷, 로그아웃 시 즉시 저장]
```

### 8.3 저장 트리거
- 로그아웃
- 30초 주기 (변경된 경우만)
- 의미 있는 사건 (레벨업, 아이템 획득, 거래 완료)
- 서버 graceful shutdown

---

## 9. 본 코스의 책임 분리 (확정)

본 코스는 Login/Meta를 별도로 만들지 않고 **Nakama에 위임**합니다. 이유:
- Nakama가 인증/캐릭터/친구/길드/우편/매치메이킹/리더보드를 모두 패키지로 제공
- 자체 구현 시 1~2개월 추가, 학습 가치 낮음
- 단, **실시간 게임 시뮬레이션**은 Nakama에 맡기지 않음 — 이것이 우리가 자체 Go Zone Server를 만드는 이유

### 9.1 Nakama가 담당 (Meta 영역)
- 계정 인증 (이메일/패스워드, OAuth 소셜)
- 캐릭터 CRUD, 직업 선택
- 친구, 길드, 우편
- 글로벌 / 길드 / 귓속말 채팅 (대역폭 부담 적음)
- 매치메이킹 (파티 던전 매칭) — **`MatchmakerProcessor` 훅**으로 커스텀 매칭 정책(레벨 가중, 대기시간 가중) 구현 가능. ⚠️ 이 훅은 **3.39 신규가 아니라 v3.29.0(2025-07-29)에서 도입**된 기능입니다(전체 티켓 풀에 접근해 커스텀 매칭 가능). 매치메이커 엔트리의 create time을 런타임에 노출하는 추가 기능은 3.39.0에 포함됨
- **Party Listing API + Party Label** — 공개 파티 검색·필터링. ⚠️ 이 역시 **3.39 신규가 아니라 v3.28.0(2025-07-14)에서 도입**된 기능입니다
- 리더보드, 토너먼트
- → Flutter는 `pub.dev/packages/nakama` SDK(**1.3.0**) 사용. ⚠️ SDK가 약 11개월 정체되어 3.28~3.39에 추가된 서버 신기능 바인딩이 없으므로 raw RPC/socket 으로 우회 필요

### 9.2 자체 Go Gateway 담당
- Nakama 세션 토큰 검증 (Zone 입장 시)
- 클라이언트 → 적절한 Zone 라우팅 (지리적/부하 기반)
- UDP 연결 관리, drain 처리

### 9.3 자체 Go Zone Server 담당 (Realtime 영역)
- 30Hz tick, 이동, 충돌, 전투, 스킬
- AoI(Interest Management), 스냅샷 송신
- 영속 변동(인벤토리, 골드)은 **Nakama RPC**로 보고
- 직접 PostgreSQL에 쓰지 않음 (단일 진실 원천 = Nakama)

### 9.4 책임 분리의 결과
- Nakama: stateful 메타 데이터, 영속, 인증 — request/response 모델에 잘 맞음
- Zone: stateful 실시간 시뮬레이션 — tick 모델
- 둘 사이는 비동기 RPC + 이벤트로 느슨하게 결합 (인벤토리 변경은 결과론적 일관성)

---

## 10. 실습 프로젝트 — "Nakama Meta + Go UDP Zone × 2"

### 10.1 요구사항
- **Nakama 1대** (Docker compose) — 인증, 캐릭터, 친구, 채팅(글로벌/길드), 우편
- **자체 Go Gateway 1대** — Nakama 토큰 검증, Zone 라우팅
- **자체 Go Zone Server 2대** — 마을(town), 던전(dungeon)
- **Redis** — Zone 간 메시지 fanout
- **PostgreSQL** — Nakama가 자동 관리
- 동시 30명 시뮬 (가짜 봇 클라이언트로 부하 테스트)
- AoI 작동 (자기 주변 entity만 수신)
- Zone 전환 (마을 ↔ 던전, 명시적 로딩 화면)
- 채팅 전역(Nakama) / Zone 내(Go Zone)
- 모니터링: Zone tick time, 메시지 카운트, Nakama latency

### 10.2 폴더 구조
```
phase6_mmo/
├── client/              # Flutter + Flame + nakama SDK
├── nakama/
│   ├── docker-compose.yml      # nakama + postgres
│   └── modules/                # Nakama Go/TS RPC 모듈
│       ├── zone_join_ticket.go # zone-join 티켓 발급 RPC
│       └── inventory_apply.go  # Zone이 호출하는 인벤토리 변경 RPC
├── gateway/
│   └── main.go                  # 티켓 검증 + Zone 라우팅
├── zone/                        # 자체 Go UDP Zone Server
│   ├── cmd/
│   │   └── zone/main.go         # zone 진입점 (env로 zone명 지정)
│   ├── grid.go                  # AoI (Spatial Hash)
│   ├── world.go                 # tick 루프
│   ├── packet.go                # 패킷 정의 (Protobuf)
│   ├── nakama_client.go         # Nakama RPC 호출
│   └── persist.go               # batch 보고
├── shared/proto/                # 클라/서버 공유 .proto
├── bot/                         # 부하 테스트 봇 (Go)
└── docker-compose.yml           # 전체 셋업 (nakama, gateway, zone-town, zone-dungeon, redis)
```

### 10.3 검증 시나리오 (반드시 통과)
- [ ] 30명 동시 접속 시 zone 서버 CPU 70% 미만, RAM 안정
- [ ] AoI 작동: 본인 시야 밖 entity는 클라에 전혀 안 옴 (네트워크 capture로 확인)
- [ ] Zone 전환이 정상 (state 손실 X)
- [ ] Zone 서버 1개 재시작 시 다른 zone은 정상
- [ ] Redis pub/sub 끊김 시 채팅만 끊기고 게임은 계속
- [ ] DB 백업으로 캐릭터 복구 가능

---

## 11. 시니어가 빠지기 쉬운 함정

### 11.1 "Microservice니까 zone마다 다른 언어로"
- 게임 서버는 시뮬레이션 코드를 공유해야 함. **언어 통일** (Go 권장).

### 11.2 "Zone 간 통신을 HTTP REST로"
- 1ms RTT의 in-process 호출에서 50ms HTTP로 전락. Redis pub/sub, NATS, gRPC streaming.

### 11.3 "Redis에 game state 직접 저장 후 매 tick 읽기"
- Redis도 ms 단위. tick은 in-memory. Redis는 zone 간 통신 + 세션 캐시 용도.

### 11.4 "Sticky session 없이 load balancing"
- 게임은 연결 단위 stateful. WebSocket이면 처음 연결된 zone에 고정.

### 11.5 "Zone 경계를 자유롭게 (seamless)"
- 어렵습니다. WoW급 회사도 고생. 초기엔 **명시적 zone 전환** (로딩 화면).
- 더 근본적으로, 권위 소유권(authority)이 한 zone에만 있어야 한다는 불변식을 깨면 double-sim·유령 플레이어가 생깁니다. 반드시 **ownership epoch + 상태 머신(Active/Migrating/Departed) + 히스테리시스 경계 + 타임아웃 가드**로 막으세요(§6.3.1).

### 11.6 "AoI를 Grid 없이 거리 계산만으로"
- N²로 폭발. 반드시 spatial partition 먼저.

### 11.7 "Snapshot에 모든 필드 매번"
- delta + bit pack 안 하면 100명도 못 견딤.

### 11.8 "한 서버 머신에 zone 다 올리기"
- 학습용은 OK. 실서비스는 zone 단위로 docker container로 분리.

### 11.9 "캐시(Redis)와 영속(DB) 사이 일관성"
- 분산 환경의 영원한 숙제. 핵심은: **DB가 truth, Redis는 hint**. 충돌 시 DB 우선.

---

## 12. 학습 자료

- "Massively Multiplayer Game Development" (Charles River Media) — 시리즈, 디자인 패턴
- Eric Schaefer의 "Tibia: Inside the Server"류 GDC 발표 검색
- Nakama Multiplayer Engine 소스 (Go)
- Wargaming, Riot, Blizzard 엔지니어링 블로그
- Nakama release notes: https://heroiclabs.com/docs/nakama/getting-started/release-notes/
- Nakama GitHub releases (버전별 nakama-common 호환 표기): https://github.com/heroiclabs/nakama/releases
- Nakama 멀티플레이 모델(relayed/authoritative): https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/
- Interest Management 표준 기법(grid 9-cell, quadtree, zone server): https://www.dynetisgames.com/2017/04/05/interest-management-mog/
- zinx 기반 MMO AoI 알고리즘(Go 레퍼런스): https://dev.to/aceld/11-mmo-online-game-aoi-algorithm-l7d
- Go 1.26 릴리즈 노트(Green Tea GC: GC 오버헤드 10~40%↓, cgo ~30%↓, goroutineleak 프로파일): https://go.dev/doc/go1.26
- PostgreSQL 버전 정책(LTS 없음, 5년 지원): https://www.postgresql.org/support/versioning/
- Go UDP/networking docs: https://pkg.go.dev/net
- 전체 Nakama/Go UDP/MMO 네트워킹 출처 목록: [resources.md §0.3](./resources.md)

---

## 13. 학습 후 메모 (직접 작성)

- AoI 구현 후 트래픽 감소량 (측정):
- Zone migration 구현 중 가장 어려웠던 race condition:
- 본인 프로젝트에 적용할 zone 분할 기준:

---

## 14. 다음 단계

[07-phase7-optimization.md](./07-phase7-optimization.md) — 동작은 하지만 100+ entity에서 프레임 드랍이 시작됩니다. 클라/서버 양측 최적화로 마무리합니다.
