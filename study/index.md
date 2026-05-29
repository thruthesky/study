# Flutter Flame 2.5D MMORPG 개발 학습 로드맵

> **대상**: 40년 경력 시니어 개발자 (서버/웹/모바일 풀스택, Flutter 전문가)
> **목표**: 2.5D Isometric Open World MMORPG Prototype — **100% Flutter + Flame** 클라이언트
> **서버**: **Nakama 메타 서버** (인증/친구/길드/우편/매치메이킹/채팅) + **자체 Go UDP Zone Server** (실시간 이동·전투·동기화)
> **핵심 가치**: "엔진 API 암기"가 아니라 **"MMORPG 구조의 단계적 구현"**

---

## 0. 최신성 기준 (2026-05-28)

이 문서는 2026-05-28 기준으로 영역별 30개 이상의 인터넷 자료를 다시 검색해 업데이트했습니다. 버전 정보는 pub.dev, Flutter 공식 SDK archive, Heroic Labs Nakama 릴리즈 노트, Go 공식 릴리즈 히스토리, Tiled / PostgreSQL / Redis 공식 발표를 기준으로 합니다. 영역별 출처 목록은 [resources.md §0](./resources.md).

| 영역 | 최신 기준 | 문서 반영 |
|---|---:|---|
| Flutter | **Flutter 3.44.0 stable** | Flame 1.37.0의 최소 요구사항 Flutter >= 3.41.0 (v1.36에서 bump). 실제 개발은 Flutter 3.44 stable 권장 |
| Dart SDK | **Dart >= 3.11.0** | flame 1.37.0 `pubspec.yaml` 기준 `sdk: ">=3.11.0 <4.0.0"`. 본 study `pubspec.yaml`은 `sdk: ^3.12.0`이라 충족(초기 1.x는 더 낮은 Dart도 허용했으나 1.37.0은 3.11.0 필요) |
| Flame 엔진 | **flame 1.37.0** (2026-04-01 출시) | `^1.37.0`. Camera 2.0 정식, `HasGameRef` → **`HasGameReference`**(1.28.0 deprecate) 권장. 1.37 신기능: `HueEffect`/`HueDecorator`, `HasAutoBatchedChildren` mixin, `OverlayManager.setActive()`, `SpriteBatch` `bleed` 옵션 |
| Flame 공식 패키지 | **flame-engine.org 38종** | [flame-official-packages.md](./flame-official-packages.md). 3종은 dormant 주의(`flame_jenny`, `flame_shells`, `oxygen`) |
| Nakama 서버 | **Nakama 3.39.0** (2026-05-20) | 메타 서버 기준. Go runtime 빌드 시 **`nakama-common v1.46.0`** 필수 |
| Nakama Dart SDK | **nakama 1.3.0** (≈11개월 전) | 인증/메타 API. Dart SDK가 ≈11개월 정체되어 서버 신규 기능(MatchmakerProcessor 훅=v3.29.0·Party Listing/Label=v3.28.0, 둘 다 2025-07 도입 / 3.39.0의 storage 재시도 함수)은 raw RPC/socket로 우회해야 함 |
| Go | **Go 1.26.3** (2026-05-07) | 자체 UDP Zone Server 권장. **Green Tea GC** 기본 활성화(1.26.0부터) — 공식 표현은 GC 오버헤드 10~40% 감소, cgo 호출 오버헤드 ~30% 감소 |
| Protobuf | Dart `protobuf 6.0.0`, Go `google.golang.org/protobuf v1.36.11`, **protoc v35.0** | UDP 패킷 직렬화 |
| WebSocket | `web_socket_channel 3.0.3` | Phase 5 학습용. 이후 UDP/QUIC 전환 |
| PostgreSQL | **PostgreSQL 18.4**(최신 메이저) / 17.10 | Nakama 영속 DB. PostgreSQL 본체에는 LTS 개념이 없고 모든 메이저가 출시 후 5년 지원. Nakama Docker 기본 `postgres:12.2-alpine`은 EOL 직전이므로 갱신 |
| Redis | **Redis 8.x (8.6.3)** | 세션 캐시, Zone 간 Pub/Sub |
| Tiled 에디터 | **Tiled 1.12.2** (2026-05-27경, 1.12는 2026-03-13) | Orthogonal/Isometric/Staggered/Hexagonal, list-valued custom property, Oblique orientation, layer blending modes, capsule object, per-object opacity |
| WebTransport | **2026-03 Baseline 진입**(Safari 26.4 포함) | Flutter Web에서 표준 사용 가능. 단 Dart 공식 WebTransport 패키지가 없어 `dart:js_interop`으로 직접 바인딩 필요(이슈 [flutter#154465](https://github.com/flutter/flutter/issues/154465)는 Closed이나 공식 패키지는 여전히 부재). 구버전 Safari/레거시 브라우저 미지원이라 `flutter_webrtc` DataChannel fallback 병행 권장 |
| flutter_webrtc | **1.4.1** | iOS/Android/macOS/Web 모두 DataChannel 지원, 게임 P2P/저지연 채널 |

> 로컬 `flutter --version`이 더 앞선 preview/pre-release 형태로 보일 수 있어도, 본 스터디 문서의 권장 기준은 **공식 stable 문서와 pub.dev stable 패키지**입니다.
> 상세 출처와 30개 이상/영역별 검색 목록은 [resources.md §0](./resources.md)을 보세요.

### 0.1 이번 업데이트(2026-05-28)에서 보강된 핵심 사실

- Flame 1.37.0 생태계 일제 정렬: 거의 모든 `flame-engine.org` 공식 패키지가 2026-04경 동시 릴리스되어 `flame ^1.37.0`을 요구.
- Flame 1.37.0 실제 신기능(changelog 기준): `HueEffect`/`HueDecorator`(색조 이펙트), `HasAutoBatchedChildren` mixin(draw call 배칭 렌더 최적화), `OverlayManager.setActive()`, `SpriteBatch`의 `bleed` 옵션(타일맵 seam/이음새 artifact 방지 — Phase 3 Isometric 타일맵에 유용), sprite/sprite-animation 위젯의 `size` 파라미터, isometric tile map 컴포넌트에서 `Block` 분리. (직전 1.36.0의 `ComponentPool` 객체 풀링·`FlameGame.dispose()`·`IconComponent`·hitbox의 부모 scale/rotation 정확 반영은 Phase 3/7에 유용.) 참고: 흔히 1.37 신기능으로 오해되는 `SpawnComponent.target`/`spawnCount`·`RasterSpriteComponent.fromImage`는 1.30.0, children retain parent(BREAKING)는 1.29.0, `HasGameRef` deprecate는 1.28.0 도입임.
- API 변경: `HasGameRef` → `HasGameReference` (flame **1.28.0**에서 deprecate, PR #3559 — 문서 곳곳의 'v1.33' 표기는 오류). 본 코스는 신규 코드를 `HasGameReference`로 작성.
- 권장 패턴: `with HasCollisionDetection`을 `FlameGame`이 아니라 **`World`에 부여**하는 방식이 최신 권장. `FlameGame`에 두어도 동작은 함.
- 트랜스포트 매트릭스(2026): 실시간 PvP/이동은 **KCP Turbo**, 로비/매칭/채팅은 **QUIC/HTTP3**, 콘솔/Steam은 **ENet/Steam Networking Sockets**, 웹 클라는 **WebTransport** 또는 **flutter_webrtc DataChannel(unordered/unreliable)**. 본 코스 학습 최종은 UDP+자체 reliable 또는 KCP.
- 멀티플레이 사례 인용: **Valorant**는 128-tick 고정 timestep + 평균 0.5/1 프레임 버퍼 + backwards reconciliation으로 peeker advantage를 144fps에서 ~71ms(동일 35ms RTT/128-tick 조건에서 60fps는 ~141ms — 프레임레이트가 높을수록 업데이트를 더 빨리 받아 49% 감소)까지 압축. **SnapNet**(UE5 SDK)이 input delay vs rollback 트레이드오프의 실질적 신표준(기본값: min input delay 0ms, max input delay 50ms, max predicted time 100ms).
- AoI(2025~2026): **uniform grid + 9-cell**이 모바일 MMO 기본, 동적/희소 월드는 **non-blocking concurrent quadtree (Quadboost)**.
- 안티치트(2025): **Play Integrity API + Apple App Attest** platform attestation + 서버측 ML 행동분석 + Server Authority의 3중 레이어가 표준.
- Tiled 1.12 신기능: list-valued custom property, Oblique 투영, layer blending mode(Multiply/Screen/Overlay), capsule object, per-object opacity, Properties view 전면 재작성 — Phase 3에 반영. 최신 패치는 1.12.2(2026-05-27경, 1.12.1의 Properties view 회귀 수정). 단 layer parallax(scrolling factor)는 Tiled 1.5부터 있던 기능으로 1.12 신규가 아님.

---

## 1. 학습자 프로파일과 학습 전략

당신은 이미 다음을 보유하고 있습니다:

| 보유 역량 | 학습에 미치는 영향 |
|---|---|
| 40년 개발 경력 | 패턴, 추상화, SOLID, DDD, CAP — 모두 그대로 적용 가능 |
| 서버/웹 서버 경험 | TCP/UDP, HTTP/WS, 인증, 세션, 캐시, DB — **거의 그대로 재활용** |
| 모바일 앱 경험 | 라이프사이클, 빌드 파이프라인, 스토어 배포 — 그대로 적용 |
| Flutter 전문가 | Flutter Widget 트리, BuildContext, 상태관리, 라우팅 — 기초 학습 불필요. **Flame은 별도 패러다임이므로 Prereq 필요** |

**따라서 본 코스는 "초보용 입문"을 모두 생략**하고, 게임 도메인 특유의 다음 4가지에 집중합니다:

1. **게임 루프 패러다임** — 이벤트 드리븐(서버/UI)에서 60fps 폴링 루프로의 사고 전환
2. **2.5D 좌표계와 Depth Sorting** — 화면 좌표 ≠ 월드 좌표
3. **Server Authority 게임 서버** — REST/WebSocket 채팅 서버와는 본질이 다름 (tick, snapshot, prediction)
4. **MMO 규모 문제** — Interest Management, Spatial Partitioning, Zone Server

> **시니어에게 보내는 경고**: "Flutter 위젯으로 화면 만들듯 게임도 만들면 되겠지"라는 직관은 작동하지 않습니다. Flame은 Widget 트리가 아니라 **Component 트리 위에서 매 프레임 update(dt)가 실행되는 다른 패러다임**입니다. Phase 1은 짧지만 반드시 손으로 코딩해서 체득해야 합니다.

---

## 2. 최종 결과물 (Definition of Done)

```
[2.5D Isometric Open World MMORPG Prototype]
├── 클라이언트 (Flutter + Flame)
│   ├── Isometric 타일맵 (Tiled 에디터로 제작)
│   ├── 8방향 캐릭터 애니메이션
│   ├── Depth Sorting (캐릭터 ↔ 건물 ↔ 나무)
│   ├── Camera Follow + Zoom
│   ├── Prediction / Reconciliation
│   ├── Inventory / Skill / Chat UI (Flutter Widget으로)
│   └── 60fps 안정 유지
└── 서버 (Go)
    ├── Auth/Meta Server: **Nakama** (인증, 친구, 길드, 우편, 채팅, 매치메이킹, 리더보드)
    ├── Realtime Tick Server: **자체 Go UDP Zone Server** (이동, 전투, AoI, 30Hz)
    ├── Interest Management (AoI, QuadTree)
    ├── Zone Server (월드 분할)
    ├── PostgreSQL (영속 데이터)
    └── Redis (세션/캐시/Pub-Sub)
```

---

## 3. 전체 로드맵 (시니어 가속 버전)

| Phase | 기간 | 목표 | 산출물 | 문서 |
|---|---|---|---|---|
| **Prereq** | 3일 | Flutter 위젯→Flame 패러다임 전환, Dart 게임 코드 패턴 | 작동하는 Hello Flame | [00-prereq-flutter-to-flame.md](./00-prereq-flutter-to-flame.md) |
| **Phase 1** | 1주 | Flame 엔진 핵심 구조 (Component, GameLoop, Camera) | 캐릭터 이동 + 카메라 follow | [01-phase1-flame-basics.md](./01-phase1-flame-basics.md) |
| **Phase 2** | 1.5주 | 2D 액션 (Sprite, Animation, Collision, AI) | 2D RPG Battle | [02-phase2-2d-action.md](./02-phase2-2d-action.md) |
| **Phase 3** | 3주 ⭐ | **2.5D Isometric (가장 중요)** | 2.5D RPG Prototype | [03-phase3-isometric-2.5d.md](./03-phase3-isometric-2.5d.md) |
| **Phase 4** | 2주 | RPG 시스템 (Entity, Combat, Inventory) | 싱글플레이 RPG | [04-phase4-rpg-systems.md](./04-phase4-rpg-systems.md) |
| **Phase 5** | 4주 ⭐ | **Multiplayer (Server Authority, Prediction)** | 멀티플레이 이동 + 채팅 | [05-phase5-multiplayer.md](./05-phase5-multiplayer.md) |
| **Phase 6** | 4주+ | MMORPG 구조 (Interest, Chunk, Zone) | MMORPG Zone Server | [06-phase6-mmorpg-architecture.md](./06-phase6-mmorpg-architecture.md) |
| **Phase 7** | 지속 | 최적화 (Atlas, Culling, Pooling, QuadTree) | 100+ Entity 60fps | [07-phase7-optimization.md](./07-phase7-optimization.md) |
| **Phase 8** | 지속 | 라이브 서비스 (Live Ops, 모니터링, 패치) | 운영 가능 빌드 | [08-phase8-live-service.md](./08-phase8-live-service.md) |

**총 학습 기간 (집중 시): 약 4~5개월**
**부가 문서**:
- [game-glossary.md](./game-glossary.md) — **게임 개발 용어집** (Flutter 개발자를 위한 입문 — 프레임/스프라이트/시트/dt/Component 등을 한 곳에서 정리)
- [flame-official-packages.md](./flame-official-packages.md) — **Flame 공식 패키지 38종 SSOT** (각 Phase에 어떤 공식 패키지를 도입할지)
- [server-architecture.md](./server-architecture.md) — 서버 아키텍처 심화 (시니어용 — 게임 서버 vs 웹 서버)
- [resources.md](./resources.md) — 공식 문서, 툴, 도서, 커뮤니티, **2026-05 최신 인터넷 검색 출처**

> **패키지 선택 원칙**: 새 기능 추가 전 반드시 `flame-official-packages.md`를 먼저 확인하세요. **Flame 공식(pub.dev verified publisher `flame-engine.org`) 38종을 최우선**으로 검토하고, 자체 구현이나 비공식 패키지는 공식이 없는 영역에서만 사용합니다. (네트워크, JSON 직렬화, OAuth 등은 공식 부재 → 일반 pub.dev 사용)

---

## 4. 기술 스택 (확정)

### 클라이언트
| 기술 | 용도 | 시니어 코멘트 |
|---|---|---|
| **Flutter 3.44 stable 이상** | UI 셸, 메뉴, HUD, 인벤토리 창 | Flame 1.37.0은 Flutter >= 3.41.0 요구 |
| **flame 1.37.0** | 게임 엔진 (Component, Camera, GameLoop) | 본 코스의 핵심. Camera 2.0 정식, `HasGameReference` 사용 |
| **flame_tiled 3.1.1** | Tiled 맵 로딩 (Orthogonal/Isometric/Staggered/Hexagonal 4종) | Phase 3에서 필수. Tiled 1.12.2와 호환 |
| **flame_audio 2.12.1** | 사운드, BGM | Phase 2 후반에 도입 |
| **flame** 내장 `JoystickComponent` | 모바일 터치 가상 조이스틱 | 모바일 타깃이면 Phase 1부터 |
| **nakama 1.3.0** (Dart SDK) | Nakama 메타 서버 클라이언트 | Phase 5에서 인증/캐릭터/채팅. Nakama 3.39 신기능은 raw socket/RPC 우회 |
| **flutter_riverpod 3.3.1 / riverpod 3.2.1** | UI/메타 상태 (게임 외부) | 게임 내부 상태는 Component가 가짐 |
| **freezed 3.2.5 + json_serializable 6.14.0** | 패킷 DTO, 모델 | 서버 모델과 1:1 매핑 |
| **protobuf 6.0.0** (Dart) | UDP 패킷 직렬화 | Phase 5 후반부터. protoc v35.0과 짝 |
| **web_socket_channel 3.0.3** | WebSocket (Phase 5 초반 학습용) | UDP 전환 후엔 의존 X |
| **dart:io RawDatagramSocket** | UDP 패킷 송수신 | Phase 5 후반부터 |
| **flutter_webrtc 1.4.1** (선택) | Web 빌드용 P2P/저지연 DataChannel | Flutter Web 타깃 시 unordered/unreliable 채널 대안 |
| (선택) **forge2d** | 2D 물리 (Box2D) | MMORPG에는 과함, 직접 충돌 권장 |

### 서버 (확정 구성)
| 역할 | 기술 | 책임 범위 |
|---|---|---|
| **Meta Server** | **Nakama 3.39.0** (+ `nakama-common v1.46.0`) | 계정/인증, 캐릭터 CRUD, 친구, 길드, 우편, 글로벌 채팅, 매치메이킹, 리더보드, 거래 로그. **MatchmakerProcessor** 훅(v3.29.0/2025-07 도입)으로 커스텀 매칭 정책 가능. 3.39.0(2026-05-20)의 실제 신규는 storage 객체 재시도 함수와 Satori 클라이언트 재시도 |
| **Realtime Zone Server** | **자체 Go 1.26.3 (UDP)** | 30Hz tick, 이동/충돌/전투, AoI(Interest Mgmt), 스냅샷 송신, Server Authority, Reconciliation. Green Tea GC로 GC 오버헤드 10~40% 감소(공식 표현), cgo 호출 오버헤드 ~30% 감소 |
| **세션/캐시/Pub-Sub** | **Redis 8.x (8.6.3)** | 세션 토큰 캐시, Zone 간 메시지(채팅 fanout, 길드 이벤트) |
| **영속 DB** | **PostgreSQL 18.4**(권장) 또는 17.10 | Nakama가 관리하는 영속 데이터(계정/캐릭터/인벤토리). PostgreSQL은 LTS가 없고 모든 메이저가 출시 후 5년 지원. Zone 서버는 직접 쓰지 않고 Nakama RPC를 경유. Nakama Docker 기본값 `postgres:12.2-alpine`은 EOL 직전이므로 갱신 필수 |
| **Zone 간 버스(선택)** | **NATS** | 다수 Zone으로 확장 시 |
| **패킷 직렬화** | **Protobuf** (Dart 6.0.0 / Go v1.36.11 / protoc v35.0) | UDP 패킷 정의. WS 핸드셰이크/메타 호출은 JSON 가능 |
| **트랜스포트(UDP reliable)** | **KCP / QUIC** | 실시간 PvP는 `kcp-go v5.6.64`(Turbo 모드), 로비/매칭/채팅은 `quic-go v0.59.1` |

**서버 책임 분리 원칙**:
- **Nakama 메타에 절대 실시간 이동/전투 로직 넣지 않기.** Nakama는 stateful 게임 시뮬레이션에 맞지 않음(요청-응답 + 매치 핸들러). 본 코스는 실시간을 **자체 Go UDP Zone에서만** 처리.
- **자체 Go Zone에 영속 데이터 직접 쓰지 않기.** 인벤토리/골드 변동 등은 Nakama RPC를 통해 처리하거나, Zone이 한 번에 batch로 Nakama에 보고. 단일 진실 원천은 Nakama.
- 클라이언트는 **Nakama 클라이언트 SDK**(`pub.dev/packages/nakama`)로 로그인 → JWT/세션 토큰 획득 → Zone Server에 UDP 핸드셰이크 시 그 토큰으로 인증.

---

## 5. 2.5D 비주얼 핵심 학습 축

아름다운 2.5D MMORPG는 "타일맵을 로딩한다"에서 끝나지 않습니다. 아래 세 축을 별도 기술로 공부해야 화면이 실제 게임처럼 살아납니다.

| 축 | 공부할 기술 | 산출물 |
|---|---|---|
| **맵 아트 파이프라인** | Tiled isometric/staggered 맵, TMX/JSON 구조, custom property, object template, chunk streaming, collision/nav/trigger layer 분리 | `village.tmx` + 충돌/스폰/오브젝트 데이터 |
| **Depth/Occlusion** | foot point 기반 Y-sort, 큰 건물 sprite slicing, bridge/경사/높이 레이어, tie-breaker, sorting debug overlay | 캐릭터가 나무/건물/다리 뒤를 자연스럽게 통과 |
| **조명과 분위기** | baked shadow, contact shadow, blob shadow, palette 제한, color ramp, parallax background, particle ambience | "평면 타일"이 아니라 깊이가 있는 마을 |
| **캐릭터/몬스터 애니메이션** | 8방향 state sheet, idle/walk/attack/hit/death, anticipation-active-recovery 타이밍, hit-stop, afterimage, trail | 움직임만으로 직업/몬스터 성격이 읽힘 |
| **화려한 스킬/VFX** | Flame particles/effects, `flame_noise` 카메라 셰이크, sprite atlas, additive 느낌의 별도 이펙트 레이어, 타격 숫자/사운드 동기화 | 조작감과 타격감이 있는 전투 |
| **최적화** | atlas, culling, object pool, animation stride, priority 갱신 최소화, DevTools/pprof 측정 | 100+ entity에서도 60fps |

자세한 학습 내용은 [03-phase3-isometric-2.5d.md](./03-phase3-isometric-2.5d.md), [02-phase2-2d-action.md](./02-phase2-2d-action.md), [04-phase4-rpg-systems.md](./04-phase4-rpg-systems.md), [07-phase7-optimization.md](./07-phase7-optimization.md)에 나누어 반영합니다.

---

## 6. 단계별 핵심 함정 (시니어가 빠지기 쉬운 곳)

| Phase | 흔한 함정 | 회피 방법 |
|---|---|---|
| 1 | "Widget처럼 setState로 다시 그릴 것" | Flame은 매 프레임 자동 render — setState 개념 없음 |
| 1 | "모바일 입력을 키보드 기준으로 설계" | 처음부터 `JoystickComponent` + 입력 추상화 |
| 2 | "Future/async로 공격 처리" | 게임 로직은 동기, dt 기반 상태 머신으로 |
| 3 | "스크린 좌표 = 월드 좌표" | Isometric 변환 행렬 학습 필수 |
| 3 | "Z-order를 layer로 관리" | priority를 y좌표 기반으로 매 프레임 갱신 |
| 4 | "아이템/스킬을 코드에 하드코딩" | 처음부터 JSON 데이터로 분리, freezed 모델 |
| 4 | "Player.hp를 Riverpod에" | 매 프레임 변경값은 Provider 금지 |
| 5 | "서버 RTT가 50ms니까 그냥 보내고 받자" | Prediction + Reconciliation 없이는 50ms도 끊겨 보임 |
| 5 | "Nakama Match Handler로 실시간 이동까지" | Nakama=메타 전용. 실시간은 자체 Go UDP에서만 |
| 5 | "WebSocket이면 충분" | 학습 첫 주는 OK, 본 코스 최종은 UDP |
| 6 | "Zone Server가 PG에 직접 write" | 영속은 Nakama RPC 경유, 단일 진실 원천 |
| 6 | "한 서버에 다 올리자" | Interest Management 없으면 100명에서 무너짐 |
| 7 | "Dart GC가 알아서 하겠지" | 매 프레임 객체 생성 → 프레임 드랍, Pool 필수 |
| 8 | "모니터링 출시 후에" | 첫 출시 전 필수 — Nakama 메트릭 + Zone tick 메트릭 동시 |

---

## 7. 권장 학습 방식

### 1) Phase별 사이클
```
[읽기 30%] → [코드 직접 작성 50%] → [문서/노트 정리 10%] → [기존 코드 리뷰 10%]
```

### 2) 각 Phase 산출물은 GitHub에 분리 커밋
- `phase1-flame-basics/` 처럼 폴더 단위로 분리
- 다음 Phase가 이전 Phase 코드를 import — 학습 진행이 곧 프로젝트 진행

### 3) 학습 일지
- 매 Phase 종료 시 본 study/ 폴더 내 해당 문서의 **"학습 후 메모"** 섹션 직접 채우기
- 시니어로서 의외였던 점, Flutter 위젯 작업과의 결정적 차이 등 기록

### 4) 절대 금지
- Phase 5(멀티플레이) 전에 네트워크 코드 작성 — 게임 도메인을 모르면 프로토콜이 망가짐
- Phase 3(2.5D) 건너뛰고 Phase 6 직행 — Depth Sorting을 모르면 MMO 렌더링이 깨짐
- "완벽한 MMORPG 아키텍처 먼저 설계" — 시니어가 가장 빠지기 쉬운 함정, **반드시 점진 구축**

---

## 8. 가장 먼저 완성할 MVP (3주 데드라인)

**Phase 1 + Phase 3 압축판** — 멀티플레이 없는 2.5D 산책 게임:

- [ ] Tiled로 만든 Isometric 맵 1개 로딩
- [ ] 8방향 이동 캐릭터 1명
- [ ] Depth Sorting (캐릭터가 나무 뒤로 들어감)
- [ ] Camera Follow + Zoom
- [ ] 간단한 NPC (말걸기만)
- [ ] 60fps 유지

이 MVP가 완성되면 MMORPG 개발의 70%는 가시권에 들어옵니다. 나머지 30%는 네트워크와 운영입니다.

---

## 9. 문서 사용법

각 Phase 문서는 다음 구조를 따릅니다:

```
1. 학습 목표 (이 Phase를 마치면 무엇을 할 수 있는가)
2. 사전 지식 (Flutter/서버 경험과 연결)
3. 핵심 개념 (도메인 모델 위주)
4. 코드 패턴 (실제 작동 예시)
5. 실습 프로젝트 (산출물 정의)
6. 시니어가 빠지기 쉬운 함정
7. 학습 후 메모 (직접 작성)
8. 다음 Phase 연결
```

---

## 10. 진행 체크리스트

- [ ] Prereq — Flutter→Flame 패러다임 전환 완료, Hello Flame 동작
- [ ] Phase 1 — 캐릭터 이동 + 카메라 follow 동작
- [ ] Phase 2 — 2D RPG Battle (몬스터 처치) 동작
- [ ] Phase 3 ⭐ — 2.5D Isometric Prototype 동작 (MVP)
- [ ] Phase 4 — 싱글플레이 RPG 동작 (인벤토리, 레벨업)
- [ ] Phase 5 ⭐ — 2명 이상 동기화 이동 + 채팅
- [ ] Phase 6 — Zone Server에서 30+ 동시 접속 60fps
- [ ] Phase 7 — 100+ Entity 60fps 안정
- [ ] Phase 8 — Live Ops 파이프라인 구축

---

> **다음 단계**: [00-prereq-flutter-to-flame.md](./00-prereq-flutter-to-flame.md) 부터 시작하세요.
