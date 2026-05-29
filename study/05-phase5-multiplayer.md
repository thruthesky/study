# Phase 5 — Multiplayer (Server Authority, Prediction, Reconciliation) ⭐

> **기간**: 4주
> **목표**: 두 명 이상이 같은 월드에서 동기화되어 이동하고 채팅하는 구조를 완성한다. **MMORPG 학습의 두 번째 큰 산.**
> **사고 전환**: Phase 4까지 "클라가 진실"이었다면, 지금부터 "**서버가 진실**(Source of Truth)".

---

## 0. 2026-05 기준 패키지

| 패키지 | 최신 기준 | 용도 |
|---|---:|---|
| `nakama` (Dart) | **1.3.0** | Nakama 메타 서버 클라이언트. ⚠️ 약 11개월 전 게시 — 서버측 매칭/파티 기능(Party Listing v3.28, MatchmakerProcessor v3.29)을 클라에서 쓰려면 raw RPC/socket으로 우회 |
| Nakama Server | **3.39.0** (2026-05-20) | Go 모듈은 `nakama-common`이 짝. 동일자(2026-05-20) 출시된 **v1.46.0**이 짝으로 추정되나 3.39.0 릴리즈 노트 본문에 호환 버전 명시가 없으므로 [nakama-common releases](https://github.com/heroiclabs/nakama-common/releases)에서 확정할 것 |
| `web_socket_channel` | **3.0.3** | 학습 첫 주 디버깅용 WebSocket |
| `protobuf` (Dart) | **6.0.0** | UDP packet DTO. 짝: protoc **v35.0**, Go `google.golang.org/protobuf v1.36.11` |
| `quic-go` | **v0.59.1** (2026-05-11) | Go QUIC. 로비/매칭/채팅 reliable 채널 |
| `kcp-go` | **v5.6.64** (2026-01-26) | UDP reliable layer (Turbo 모드 권장 — 손실↑ 환경에서 ENet 대비 실측 약 3~3.5배 빠름. §7.3 벤치마크 참조) |
| `flutter_webrtc` | **1.4.1** | Flutter Web/모바일 통합용 unordered/unreliable DataChannel |
| `flame_test` | **2.2.4** | prediction/reconciliation 결정론 테스트 |

최종 구조는 **Nakama = 메타**, **자체 Go UDP Zone Server = 실시간 권위 서버**입니다. WebSocket은 개념 검증 후 폐기합니다.

### 0.1 Nakama 버전별 멀티플레이 API (버전 매핑 주의)

> ⚠️ **흔한 오해 정정**: MatchmakerProcessor 훅과 Party Listing API는 2026-05의 3.39.0 신규 기능이 **아닙니다**. 이 둘은 모두 2025년 7월 릴리스 기능입니다. 코스 자료나 블로그에서 "3.39 신규"로 묶어 소개하는 경우가 있어 주의가 필요합니다.

| 기능 | 도입 버전 | 출시일 | 용도 |
|---|---|---|---|
| **Party Listing API + Party Label** | **v3.28.0** | 2025-07-14 | 파티의 공개 검색/필터링(label 기반) |
| **MatchmakerProcessor 훅** | **v3.29.0** | 2025-07-29 | 전체 티켓 풀에 접근하는 커스텀 매칭 로직. 파티 던전 매칭에 활용 |
| 매치메이커 티켓 `create time` 런타임 노출 | (해당 7월 라인) | — | 대기 시간 가중 매칭 |
| storage 객체 **재시도** 업데이트 런타임 함수 | **v3.39.0** | 2026-05-20 | 낙관적 동시성 충돌 시 재시도하며 쓰기 |
| Satori 클라이언트 구성 가능 **재시도** | **v3.39.0** | 2026-05-20 | Satori(라이브옵스) 호출 안정성 |

즉 **3.39.0(2026-05-20)의 실제 신규는 storage 객체 재시도 업데이트 함수와 Satori 클라이언트 재시도**입니다. 매칭/파티 기능을 쓰려면 **서버를 v3.28~v3.29 이상**으로 올리면 됩니다(3.39.0도 당연히 포함).

- 출처: [Nakama Release Notes](https://heroiclabs.com/docs/nakama/getting-started/release-notes/) · [nakama GitHub releases](https://github.com/heroiclabs/nakama/releases)

> ⚠️ **Nakama Dart SDK 1.3.0 정체 경고**: pub.dev 게시일이 약 11개월 전이라 위 서버측 매칭/파티 기능의 Dart 바인딩이 아직 없을 가능성이 큽니다. 클라이언트에서 쓰려면 (1) `socket.rpc('custom_matchmaker_join', ...)` 같은 사용자 정의 RPC로 우회하거나 (2) GitHub `heroiclabs/nakama-dart` issue/PR 상태를 먼저 확인하세요.

---

## 1. 학습 목표

- [ ] Server Authority가 왜 필요한지, 무엇을 검증해야 하는지 설명 가능
- [ ] Tick 기반 서버 루프(20~30Hz) 구현
- [ ] Snapshot 동기화 + Delta Compression
- [ ] **Client-side Prediction** (입력 즉시 적용)
- [ ] **Server Reconciliation** (서버 응답으로 보정)
- [ ] **Entity Interpolation** (타 플레이어를 부드럽게 보이게)
- [ ] WebSocket으로 시작, UDP로 전환할 수 있는 구조

---

## 2. 시니어를 위한 패러다임 전환

당신은 이미 REST/WebSocket/Push/Long Poll/SSE를 모두 만들어 봤습니다. 하지만 게임 서버는 다음 4가지가 다릅니다:

| 웹/모바일 서버 | 게임 서버 |
|---|---|
| 요청-응답 기반 | **고정 tick 루프 (20~30Hz)** + 비동기 입력 큐 |
| 상태는 DB | **상태는 메모리 (in-process)**, DB는 백업 |
| 사용자 입력 = 명령 | **사용자 입력 = 의도** (서버가 시뮬레이션 후 결과 산출) |
| 지연 = 사용자가 인내 | **지연 50ms도 사용자가 즉시 인지** → Prediction 필수 |

### 2.1 왜 클라이언트가 진실이면 안 되는가
- 핵: 클라이언트가 "내 HP = 9999"라고 보내면 그대로 적용됨
- 동기화 분기: 두 클라가 각자 다른 결과 계산 → 화면이 다름
- → **서버만 룰 적용, 클라는 입력 송신 + 결과 표시**

---

## 3. 핵심 개념 — 한 장 요약

```
[클라 입력] ──(input msg)──> [서버]
   ↓                            ↓ tick 30Hz
   ↓ 즉시 예측 적용(Prediction)   ├── 모든 입력 처리
   ↓                            ├── 시뮬레이션
   ↓                            └── 스냅샷 송신 (lastInputId 포함)
   ↓                              ↓
[서버 스냅샷 수신] <──────────────┘
   ├── 본인: lastInputId 기준 reconciliation
   │     (예측 결과와 서버 결과 비교, 차이만큼 보정)
   └── 타인: 200ms 버퍼링 + interpolation
```

세 개념을 분리해서 이해:

### 3.1 Server Authority
- 모든 룰(이동 속도, 충돌, 데미지) 판정은 서버.
- 클라는 "WASD 입력함" 같은 **의도** 만 송신.

### 3.2 Client-side Prediction
- 입력을 보내고 응답을 기다리면 50ms 지연 → 조작감 끔찍.
- 해결: 입력 즉시 클라가 자체적으로 시뮬레이션 (=서버와 같은 로직).

### 3.3 Server Reconciliation
- 서버 스냅샷이 오면 "내가 input #234까지 적용했을 때 서버는 (x,y)였다"를 받음.
- 클라는 input #234 이후 입력을 재적용 (rollback & replay).
- 차이가 작으면 보간으로 부드럽게 보정.

### 3.4 Entity Interpolation (타 플레이어)
- 30Hz 스냅샷 = 33ms 간격 → 그대로 표시하면 끊김.
- 해결: 두 스냅샷 사이를 보간. 그러려면 **200ms 정도 과거를 보여줌** (snapshot buffer).
- 즉, 본인은 미래(예측), 타인은 과거(보간) — 정상.

---

## 4. 프로토콜 설계

### 4.1 메시지 종류 (최소)

| 방향 | 타입 | 내용 |
|---|---|---|
| C→S | `input` | seq, dt, dx, dy, action (공격 등) |
| C→S | `chat` | text |
| S→C | `welcome` | yourEntityId, world info |
| S→C | `snapshot` | tick, entities[], lastInputSeq |
| S→C | `event` | damage, death, item drop |

### 4.2 직렬화
- 학습 단계: **JSON** (디버깅 쉬움)
- Phase 6+: **Protobuf** 또는 **MessagePack**

### 4.3 패킷 예시 (JSON)
```json
{ "t": "input", "seq": 234, "dt": 0.033, "dx": 1.0, "dy": 0.0, "a": null }
{ "t": "snapshot", "tick": 5621, "lastSeq": 234,
  "entities": [
    {"id":"u1","x":120.5,"y":80.3,"dir":"e","st":"walk","hp":100},
    {"id":"u2","x":140.0,"y":90.0,"dir":"s","st":"idle","hp":85}
  ]}
```

### 4.4 Delta Compression
- 매 tick 전체 entity 보내면 대역폭 폭발.
- 해결: 변경된 필드만, 또는 이전 스냅샷과의 차이만.
- Phase 5 학습 단계는 full snapshot OK, Phase 7에서 delta 도입.

---

## 5. 서버 — 본 코스의 확정 구성

본 코스는 두 가지 서버를 **명확히 분리**해서 만듭니다.

### 5.1 역할 분리 (확정)

| 서버 | 책임 | 통신 |
|---|---|---|
| **Nakama 메타 서버** | 인증, 캐릭터 CRUD, 친구, 길드, 우편, 글로벌 채팅, 매치메이킹, 리더보드 | HTTPS + Nakama 클라이언트 SDK |
| **자체 Go UDP Zone Server** | 30Hz tick, 이동/충돌/전투/스킬, AoI, 스냅샷 송신, Server Authority | UDP (또는 학습 초반은 WebSocket) |

### 5.2 Phase 5의 진행 방식

Phase 5는 **자체 Go 서버부터** 만듭니다. 이유:
- "Server Authority + Prediction + Reconciliation"의 모든 코드를 자기 손으로 작성해야 본질을 이해
- Nakama의 Match Handler로도 구현 가능하지만 추상화에 가려 학습 깊이가 얕음

다만 **인증/캐릭터 선택은 처음부터 Nakama 사용**합니다. 그래야 Phase 6에서 친구/길드/채팅을 자연스럽게 붙입니다.

### 5.3 클라이언트 접속 흐름 (확정)

```
1. 클라 → Nakama: email/password 로그인 → 세션 토큰
2. 클라 → Nakama: 내 캐릭터 목록 조회 → 선택
3. 클라 → Nakama RPC `zone_join_ticket`: zone 입장 티켓 발급 (서명된 짧은 수명 토큰)
4. 클라 → Go Zone Server (UDP): 핸드셰이크 패킷에 ticket 첨부
5. Zone Server: ticket 검증(Nakama 공개키 또는 Redis 조회) → 게임 시작
```

> Nakama 단일 진실 원천 + Zone Server는 그 신원으로 입장. **Zone Server가 자체 계정 시스템을 가지지 않습니다.**

### 5.4 Go 미니 서버 골격 — UDP 기반

```go
type Player struct {
    ID  string
    Pos Vec2
    Vel Vec2
    HP  int
    LastInputSeq int
}

type Server struct {
    players map[string]*Player
    inputs  chan InputMsg
    out     map[string]chan []byte
    mu      sync.Mutex
}

func (s *Server) Run() {
    ticker := time.NewTicker(33 * time.Millisecond)   // 30Hz
    for range ticker.C {
        s.tick()
    }
}

func (s *Server) tick() {
    s.mu.Lock()
    defer s.mu.Unlock()

    // 1. 큐의 모든 입력 처리
    drainInputs(s.inputs, s.players)

    // 2. 시뮬레이션 (이동, 충돌)
    for _, p := range s.players {
        p.Pos.X += p.Vel.X * 0.033
        p.Pos.Y += p.Vel.Y * 0.033
        // 충돌 검사 등
    }

    // 3. 스냅샷 송신
    snap := buildSnapshot(s.players)
    for id, ch := range s.out {
        snap.LastSeq = s.players[id].LastInputSeq
        ch <- encode(snap)
    }
}
```

> goroutine 한 개가 tick을 돌고, 다른 goroutine들이 입력을 채널에 넣는 구조. 락 최소화.

---

## 6. 클라 — Prediction + Reconciliation

### 6.1 dt와 서버 tick 기준

Prereq에서 말한 "게임 로직은 동기 + dt 기반" 원칙은 서버 권위 구조에서도 그대로 유지됩니다. 달라지는 것은 **누가 최종 판정을 내리느냐**입니다.

- 클라: 입력을 읽는 즉시 같은 이동 함수를 `dt`로 적용해서 화면을 먼저 움직입니다. 이것이 Prediction입니다.
- 서버: 클라가 보낸 위치나 `dt`를 진실로 믿지 않습니다. 서버 자신의 fixed tick, 예: 30Hz라면 `serverDt = 1 / 30`, 기준으로 이동과 충돌을 판정합니다.
- Reconciliation: 서버가 "input #234까지 처리한 authoritative position은 여기"라고 보내면, 클라는 그 위치로 되돌린 뒤 아직 서버가 처리하지 않은 input들을 다시 `dt`로 재적용합니다.

즉, **클라도 dt 기반으로 움직입니다.** 다만 클라의 이동은 조작감을 위한 예측이고, 서버의 tick/dt가 최종 진실입니다. 가능하면 클라 예측도 서버 tick과 같은 fixed timestep으로 맞추면 보정량이 줄어듭니다.

정리하면:

| 영역 | 시간 기준 | 목적 |
|---|---|---|
| 로컬 플레이어 렌더/애니메이션 | 클라 프레임 `dt` | 즉각적인 화면 반응 |
| 클라 Prediction | 서버 tick에 맞춘 fixed `dt` 권장 | 서버 결과와 최대한 같은 예측 |
| 서버 Authority | 서버 fixed tick/dt | 최종 위치, 충돌, 룰 판정 |
| 네트워크 async | 없음. 입력/스냅샷 큐에 넣기만 | 로딩·송수신 처리 |

> 서버에 보내는 핵심 데이터는 "나는 여기 있다"가 아니라 "input #234에서 오른쪽으로 이동했다"입니다. `dt`를 보내더라도 서버는 검증용 힌트로만 보고, 최종 시뮬레이션은 서버 시간 기준으로 처리하세요.

### 6.2 입력 버퍼 + Rollback & Replay

핵심은 **세 단계**입니다. 서버 스냅샷이 도착하면 (1) 권위 위치로 **되돌리고**(rollback), (2) 서버가 아직 처리하지 못한 미처리 입력을 **그 위에서 다시 시뮬레이션**하고(replay), (3) 그 결과와 화면에 보이던 예측 위치의 차이를 **부드럽게 흡수**합니다.

```dart
import 'dart:math' as math;   // 보정 잔차 감쇠(exp)에 사용

class PendingInput {
  final int seq;
  final double dt;
  final Vector2 axis;
  final String? action;
  PendingInput(this.seq, this.dt, this.axis, this.action);
}

class NetPlayer {
  Vector2 position = Vector2.zero();   // 화면에 그리는 위치(예측+보정 후)
  Vector2 _simPos = Vector2.zero();    // 시뮬레이션 위치(서버 권위 기준 재계산)
  Vector2 _smoothError = Vector2.zero(); // 아직 흡수 못 한 reconciliation 오차
  int nextSeq = 0;
  final List<PendingInput> pending = [];

  static const double speed = 120;
  static const double snapThreshold = 64;  // 이 이상 어긋나면 부드러운 보정 포기, 즉시 스냅

  void sendInput(Vector2 axis, double dt) {
    final pi = PendingInput(nextSeq++, dt, axis, null);
    pending.add(pi);
    _applyInput(pi);          // ← Prediction: 즉시 적용(조작감)
    net.send({'t': 'input', 'seq': pi.seq, 'dt': dt, 'dx': axis.x, 'dy': axis.y});
  }

  // ★ 클라/서버가 수학적으로 동일해야 하는 순수 함수. dt도 같은 fixed step 권장.
  void _applyInput(PendingInput i) {
    final move = i.axis.length2 > 0 ? i.axis.normalized() : Vector2.zero();
    _simPos += move * speed * i.dt;
    position = _simPos + _smoothError;   // 보정 잔차를 더해 그린다
  }

  void onSnapshot(SnapshotMsg s) {
    final me = s.entities.firstWhere((e) => e.id == myId);

    // (1) rollback: 시뮬레이션 위치를 서버 권위 위치로 되돌림
    final predictedBefore = _simPos.clone();
    _simPos = me.pos.clone();

    // (2) replay: 서버가 아직 처리 못 한 입력만 남기고 그 위에서 재시뮬레이션
    pending.removeWhere((p) => p.seq <= s.lastSeq);
    for (final p in pending) {
      final move = p.axis.length2 > 0 ? p.axis.normalized() : Vector2.zero();
      _simPos += move * speed * p.dt;
    }

    // (3) reconciliation error 흡수: 예측과 재계산 결과의 차이를 잔차로 누적
    final error = predictedBefore - _simPos;  // 화면이 얼마나 틀렸는지
    if (error.length > snapThreshold) {
      _smoothError = Vector2.zero();          // 너무 크면 텔레포트(치트/순간이동/큰 보정)
    } else {
      _smoothError = error;                    // 작으면 update()에서 서서히 0으로
    }
    position = _simPos + _smoothError;
  }

  // 매 프레임: 누적된 오차를 시간 상수로 0에 수렴시켜 "튐" 없이 보정
  void update(double dt) {
    if (_smoothError.length2 > 0.01) {
      final k = (1 - math.exp(-dt / 0.1));     // ~100ms 시간 상수
      _smoothError -= _smoothError * k;
    } else {
      _smoothError = Vector2.zero();
    }
    position = _simPos + _smoothError;
  }
}
```

> **왜 `_simPos`/`position`을 분리하나**: `_simPos`는 항상 서버 권위에서 재계산한 "정답에 가까운" 위치이고, `position`은 거기에 보정 잔차(`_smoothError`)를 더해 화면이 갑자기 튀지 않게 만든 표시용 위치입니다. 차이가 작으면 잔차가 100ms 안에 사라지므로 사용자는 보정을 인지하지 못합니다. 차이가 `snapThreshold`(예: 64px) 이상이면 부드러운 보정을 포기하고 즉시 스냅합니다 — 텔레포트/넉백/큰 패킷 손실 후 복구 상황입니다.

> **결정론 주의**: `_applyInput`(예측)과 서버 시뮬레이션이 같은 입력에 대해 같은 결과를 내야 reconciliation 보정량이 0에 수렴합니다. `axis.normalized()`의 부동소수점 미세 차이, `dt` 불일치, 입력 처리 순서가 어긋나면 매 스냅샷마다 작은 보정이 누적돼 떨림이 생깁니다. 가능하면 클라·서버 모두 **fixed timestep(예: 서버 30Hz면 `dt = 1/30`)** 으로 입력을 적분하세요.

### 6.3 타 플레이어 — Interpolation
```dart
class RemotePlayer {
  final List<Snapshot> buffer = [];   // [{tick, x, y, ...}]

  void onSnapshot(Snapshot s) {
    buffer.add(s);
    if (buffer.length > 30) buffer.removeAt(0);
  }

  double interpDelay = 0.1;   // 적응형. 고정 0.2 하드코딩 대신 측정값으로 갱신

  @override
  void update(double dt) {
    // 현재 시각으로부터 interpDelay 만큼 과거를 보여줌 (snapshot interpolation delay)
    final renderTime = serverTimeNow() - interpDelay;
    final pair = _findBracketing(renderTime);
    if (pair == null) {
      // 버퍼 언더런: 최신 스냅샷에서 짧게 extrapolation (과도하게 외삽하지 말 것)
      _extrapolateFromLatest(renderTime);
      return;
    }
    final (a, b) = pair;
    final alpha = ((renderTime - a.time) / (b.time - a.time)).clamp(0.0, 1.0);
    position = a.pos + (b.pos - a.pos) * alpha;
  }
}
```

#### Adaptive interpolation delay — 고정 200ms를 버리는 이유

위 §3.4에서 "200ms 정도 과거를 보여준다"고 했지만, 이는 **상한에 가까운 보수치**입니다. 고정 200ms는 회선이 좋을 때 불필요하게 큰 입력 지연(타 플레이어가 200ms 늦게 보임)을 만들고, 회선이 나쁠 때는 오히려 부족할 수 있습니다. 실무 권장은:

- **하한**: 스냅샷 2개 간격 이상. 30Hz(스냅샷 간격 33ms)면 최소 **~66ms**. 한 개만 버퍼링하면 패킷 하나만 늦어도 보간 구간이 비어 버립니다.
- **상한/실측**: 측정한 RTT·jitter에 여유를 더해 보통 **100~200ms** 구간에서 동적으로 조정.
- **언더런(버퍼 비었을 때)**: 마지막 스냅샷의 속도로 짧게 **extrapolation**. 단 오래 외삽하면 벽 통과·되감김이 생기므로 한두 프레임 한도로 제한.
- **오버런(버퍼 과다)**: `interpDelay`를 줄여 지연을 회수.

즉 **고정 `0.2s` 하드코딩 대신 jitter buffer 점유율과 RTT/jitter 측정값에 따라 `interpDelay`를 적응적으로 갱신**하는 것이 정확합니다. (Valve Source 네트워킹의 `cl_interp`/`cl_interp_ratio`가 같은 아이디어입니다 — 출처: [Source Multiplayer Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking))

### 6.4 시간 동기화 — NTP식 오프셋 계산

`serverTimeNow()`는 위의 prediction(예측 위치를 어느 서버 tick에 매핑할지)과 interpolation(과거 몇 ms를 그릴지) 양쪽에서 쓰이는 기준 시계입니다. 단순히 "서버 시각 - 클라 시각"으로 빼면 편도 지연만큼 오차가 생기므로, **NTP가 쓰는 4-타임스탬프 공식**으로 RTT를 제거하고 오프셋을 구합니다.

```
클라가 t0에 ping 송신
서버가 t1에 수신, t2에 pong 응답 (t1, t2를 패킷에 실어 보냄)
클라가 t3에 pong 수신

RTT    = (t3 - t0) - (t2 - t1)          // 왕복 시간에서 서버 처리 시간 제거
offset = ((t1 - t0) + (t2 - t3)) / 2    // 클라→서버 시계 차이
```

```dart
class TimeSync {
  double _offset = 0;          // serverNow ≈ clientNow + _offset
  double bestRtt = double.infinity;

  void onPong({required double t0, required double t1,
               required double t2, required double t3}) {
    final rtt = (t3 - t0) - (t2 - t1);
    final offset = ((t1 - t0) + (t2 - t3)) / 2;
    // ★ jitter를 줄이려면 '가장 RTT가 작았던' 샘플의 offset을 채택
    if (rtt < bestRtt) {
      bestRtt = rtt;
      _offset = offset;
    }
  }

  double serverTimeNow() => clientNow() + _offset;
}
```

- 여러 ping/pong 샘플 중 **최소 RTT 샘플의 offset**을 채택하면, 그 순간 큐잉 지연이 가장 적었다는 뜻이라 jitter 영향이 가장 작습니다(NTP의 표준 휴리스틱).
- 핸드셰이크 때 한 번이 아니라 수 초 간격으로 계속 ping을 보내 시계 드리프트를 따라가세요.
- 출처: [Gabriel Gambetta — Client-Server Game Architecture](https://www.gabrielgambetta.com/client-server-game-architecture.html)

---

## 7. 트랜스포트: 첫 1주만 WebSocket → 이후 UDP 확정

본 코스의 최종 트랜스포트는 **UDP**입니다 (Go Zone Server가 UDP 기반). 다만 Phase 5의 학습 초반 며칠은 WebSocket으로 시작해도 됩니다 — Prediction/Reconciliation의 본질을 트랜스포트 디버깅과 분리해서 익히기 위함입니다.

### 7.1 WebSocket으로 시작하는 이유 (선택적, 최대 1주)
- 디버깅 쉬움 (JSON 메시지, 텍스트 프레임)
- TCP 기반이라 순서 보장 → 학습 단순
- 브라우저/모바일 모두 지원

### 7.2 WebSocket의 한계 — UDP로 전환해야 하는 이유
- TCP 헤드-오브-라인 블로킹: 패킷 1개 늦으면 뒤가 다 밀림
- 게임은 **"늦은 패킷보다 빠진 패킷이 낫다"** — UDP가 자연스러움
- 모바일 셀룰러 환경에서 50~100ms 추가 지연
- 본 코스의 자체 Go Zone Server는 **UDP 기반으로 설계** — Phase 5 후반에 WS 코드를 폐기하고 UDP로 옮깁니다

### 7.3 UDP 위 신뢰성 레이어 선택 (2026 의사결정 매트릭스)

본 표는 2026-05 기준 게임 트랜스포트 선택의 실질 가이드입니다.

| 채널 사용 | 권장 | 이유 |
|---|---|---|
| 위치/스냅샷(unreliable) | **raw UDP** (`dart:io RawDatagramSocket` + Go `net.PacketConn`) | 다음 패킷이 곧 옴. 최저 지연 |
| 실시간 PvP/이동 reliable 보조 | **KCP (`kcp-go v5.6.64`, Turbo 모드)** | 손실↑ 환경에서 ENet 대비 **실측 약 3~3.5배** 빠름(아래 벤치마크). 모바일 셀룰러에 강함 |
| 로비/매칭/채팅 reliable+ordered | **QUIC (`quic-go v0.59.1`)** | UDP 위 TLS 1.3 + 멀티 스트림. 단 양호한 네트워크에서는 TCP+TLS 대비 **계산 효율/처리량이 낮다**는 보고가 있어(아래 주석) **in-match 실시간 트래픽엔 비권장** |
| 콘솔/Steam | **ENet 또는 Steam Networking Sockets** | 콘솔 SDK 친화 |
| Flutter Web 클라 | **WebTransport** 또는 **flutter_webrtc DataChannel(unordered/unreliable)** | UDP 불가. WebTransport는 2026-03 Baseline 진입(Safari 26.4 포함). flutter_webrtc 1.4.1은 모든 플랫폼 안정. 둘 다 두는 이중화 권장(§7.5) |
| 보안 핸드셰이크 | **mas-bandwidth/netcode** 레퍼런스 | Glenn Fiedler의 UDP 위 secure connect 표준 C 구현. Go 포팅 다수 |

#### KCP vs ENet — "10배"가 아니라 실측 ~3~3.5배

흔히 인용되는 "KCP가 ENet보다 10배 빠름"은 과장입니다. 공개 벤치마크 기준 실제 격차는 약 3~3.5배입니다.

| 구현 | 평균 RTT | 편차 |
|---|---:|---:|
| KCP (Turbo) | **40.582 ms** | 10.399 |
| ENet | **139.306 ms** | 147.850 |

즉 약 **3.4배** 차이입니다. KCP 공식 README도 "평균 지연 30~40% 감소, **최대 지연 약 3배 감소**, lag 발생 시 ENet 대비 약 3배 우수"라고 기술하며, 그 대가로 **TCP 대비 대역폭 10~20%를 더 소모**합니다(중복 전송으로 빠른 회복을 사는 trade-off). 또 KCP는 RTO를 지수 backoff 대신 **1.5배 증가**로 잡아 손실 후 회복이 빠릅니다.
출처: [Latency of Reliable Streams (paytonturnage)](https://paytonturnage.com/writing/latency-of-reliable-streams/) · [kcp README](https://github.com/skywind3000/kcp/blob/master/README.en.md)

> **QUIC 처리량 주석**: "TCP+TLS 대비 최대 45% 손실"이라는 수치는 단일 권위 출처로 확정되지 않았습니다. 다만 방향성(저손실·양호한 네트워크에서 QUIC이 TCP+TLS보다 **계산 효율·처리량이 낮을 수 있음**)은 여러 연구가 지지합니다. 예컨대 Fastly 측정은 QUIC이 TLS 1.3-over-TCP 대비 약 **40% 수준의 계산 효율**(≈60% 오버헤드)을 보였다고 보고했습니다 — 맥락이 "처리량 45% 손실"과는 다르므로 수치는 출처와 함께 인용하세요. 결론(in-match 실시간엔 raw UDP/KCP, 로비·채팅엔 QUIC)은 그대로 유효합니다. 출처: [Fastly — Measuring QUIC vs TCP](https://www.fastly.com/blog/measuring-quic-vs-tcp-computational-efficiency)

### 7.4 Dart에서 UDP
```dart
final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
socket.send(payload, serverAddr, serverPort);
socket.listen((e) {
  if (e == RawSocketEvent.read) {
    final dg = socket.receive();
    if (dg != null) _onPacket(dg.data);
  }
});
```

### 7.5 Flutter Web 대응 (WebTransport / WebRTC DataChannel)

Flutter Web에서는 `dart:io`의 UDP가 불가합니다. 2026-05 기준 권장:

- **WebTransport** — Chromium(97+) + Edge + Firefox(114+) + **Safari 26.4(2026-03-24)** + Opera + Samsung Internet에서 지원되며 2026-03~04 **Baseline에 진입**했습니다. HTTP/3 datagram(unreliable) + 양방향 스트림을 제공합니다.
  - ⚠️ **이슈 상태 정정**: Flutter의 WebTransport 통합 트래킹 이슈 [flutter/flutter#154465](https://github.com/flutter/flutter/issues/154465)는 현재 **Closed** 상태입니다(과거 "열려 있어 통합 미완"이라는 서술은 부정확). 다만 **Dart/Flutter 공식 WebTransport 바인딩 패키지는 여전히 부재**하므로, `dart:js_interop`으로 브라우저 `WebTransport` API를 직접 바인딩해야 한다는 결론은 그대로 유효합니다.
- **flutter_webrtc 1.4.1** — `RTCDataChannel(ordered: false, maxRetransmits: 0)`로 unreliable datagram을 만들 수 있습니다. iOS/Android/macOS/Windows/Linux/Web 모두 안정 지원. Cross-platform MMO는 **모바일 native UDP + 웹 WebRTC DataChannel의 듀얼 트랜스포트**가 현실적.

#### 운영상 권장: Baseline이라도 fallback 이중화

WebTransport가 Baseline이라고 해서 단독 의존은 위험합니다. **caniuse는 구버전 Safari·레거시 브라우저(IE, Opera Mini 등) 미지원을 이유로 "완전 Baseline은 아님"**으로 봅니다. 따라서 Flutter Web 게임은 다음 이중화를 권장합니다:

1. **1순위: WebTransport(HTTP/3 datagram)** — 가용하면 최저 지연.
2. **fallback: flutter_webrtc `RTCDataChannel(ordered: false, maxRetransmits: 0)`** — 미지원 단말/네트워크에서 unreliable 채널 확보.

런타임에 `WebTransport` 존재 여부를 feature-detect 해서 분기하세요. HTTP/3 datagram이 방화벽·프록시에 막히는 운영 환경도 있으므로 fallback 경로는 실제로 동작 검증까지 해 두는 것이 안전합니다.

- 출처: [WebTransport (caniuse)](https://caniuse.com/webtransport) · [flutter_webrtc](https://pub.dev/packages/flutter_webrtc) · [flutter#154465](https://github.com/flutter/flutter/issues/154465) · [Safari 26.4 features](https://9to5mac.com/2026/03/24/apple-details-safari-26-4-with-44-new-features-191-bug-fixes-more/)

---

## 8. 채팅

채팅은 가장 단순한 동기화 기능 → **첫 멀티플레이 기능으로 추천**.

```dart
// 클라
net.send({'t': 'chat', 'text': '안녕'});

// 서버
case "chat":
    broadcast({'t': 'chat', 'from': playerID, 'text': text})
```

전역 채팅 → 길드 채팅 → 귓속말 순으로 확장.

---

## 9. 실습 프로젝트 — "멀티플레이 이동 + 채팅"

### 9.1 요구사항
- 서버: Go 또는 Nakama, WebSocket, 30Hz tick
- 2~5명이 같은 맵에서 이동 → 서로 보임
- Prediction (본인은 즉시 반응)
- Reconciliation (서버와 차이 보정)
- Interpolation (타인은 부드럽게)
- 채팅 (전역)
- 디버그 HUD: ping, RTT, 보정 횟수, 입력 큐 길이

### 9.2 폴더 구조
```
phase5_mp/
├── client/                          # Flutter Flame
│   ├── lib/
│   │   ├── domain/                  # Phase 4의 domain 재사용
│   │   ├── net/
│   │   │   ├── connection.dart
│   │   │   ├── protocol.dart        # msg 직렬화
│   │   │   └── time_sync.dart
│   │   ├── entities/
│   │   │   ├── net_player.dart      # 본인 (prediction)
│   │   │   └── remote_player.dart   # 타인 (interpolation)
│   │   └── ...
├── server/                          # Go
│   ├── main.go
│   ├── world.go
│   ├── player.go
│   ├── tick.go
│   └── proto/
└── shared/                          # 가능하면 같은 메시지 정의
    └── protocol.json (or .proto)
```

### 9.3 검증 시나리오
- [ ] 2개 클라이언트가 같은 위치에서 +-1px 이내로 일치
- [ ] 50ms 인공 지연 추가해도 본인 조작감 그대로 (prediction 작동)
- [ ] 타인 이동이 끊김 없이 부드러움 (interpolation 작동)
- [ ] 연결 끊김 → 재연결 → 위치 복원
- [ ] 채팅 메시지가 1초 이내 전 클라에 도착

---

## 10. 시니어가 빠지기 쉬운 함정

### 10.1 "TCP라 순서 보장되니까 prediction 필요 없겠지"
- 지연이 곧 문제. 0ms RTT가 아닌 한 prediction 필수.

### 10.2 "서버와 클라의 시뮬레이션이 같아야 한다"는데 어떻게?
- 같은 Dart 코드 모듈 공유 (server도 Dart?) → 비추. Go 서버 권장.
- 대신: **수학적으로 동일한 결과**가 나오게 정수/고정소수점, deterministic random.
- 부동소수점 미세 차이로 분기되는 게임은 영원히 디버깅 불가 → 적은 차이는 reconcile에서 흡수.

### 10.3 "서버 tick rate를 60Hz로"
- 대역폭 2배. 20~30Hz면 충분. 클라 prediction이 보완.

### 10.4 "스냅샷에 전체 entity 매번"
- 대역폭 폭발. 변경된 entity만, 또는 본인 주변만 (Interest Management).

### 10.5 "Authoritative라며 클라 입력을 그대로 적용"
- 입력에도 검증: dt가 비정상이면 거부, 너무 빠른 이동 거부 등.

### 10.6 "이동만 prediction, 공격은 그냥 서버 응답 기다림"
- 공격도 prediction 필요 (애니메이션은 즉시, 데미지 적용은 서버 확정 후).
- → 이걸 위해 Phase 4에서 액션을 **선언적 데이터**로 만들어 둔 것이 빛납니다.

### 10.7 "프로토콜 버전 관리 없이 시작"
- 서버/클라 따로 배포되면 호환성 깨짐. 메시지에 `v` 필드 처음부터 박기.

### 10.8 "Nakama Match Handler로 실시간 이동까지"
- 정정해 두면: Nakama의 **authoritative Match Handler는 서버 권위 실시간 게임을 만드는 공식 지원 방식**입니다(잘못된 게 아님). 검증이 필요하면 authoritative, 검증이 덜 필요하면 relayed를 고르라는 게 공식 안내입니다(§12 참조).
- 다만 매치 핸들러는 **tick 루프가 추상화되어 있고, GC·단일 프로세스 제약**이 있어 수백 명 규모의 고부하 실시간 시뮬레이션에는 병목이 됩니다. 또 prediction/reconciliation의 본질을 직접 손으로 구현해 봐야 학습 깊이가 생깁니다.
- 그래서 본 코스는 학습 목적상 **Nakama = 메타 전용**, **자체 Go UDP = 실시간 전용**으로 분리합니다. 실제 상용에서 규모가 작다면 Nakama authoritative만으로 충분할 수 있습니다.

### 10.9 "Zone Server가 PG에 직접 write"
- Zone은 메모리 진실. 영속화는 **Nakama RPC로 위임**하거나 batch 보고. 그래야 trade/inventory가 단일 원천에서 일관됩니다.

---

## 11. 이 Phase의 패키지 — Flame 공식 부재 영역

Phase 5는 네트워크 통신·UDP·직렬화 영역으로 **Flame 공식 패키지에 해당이 없습니다** (verified publisher `flame-engine.org`에서 게임 네트워크 라이브러리를 제공하지 않음). 따라서 일반 pub.dev 패키지를 사용합니다 — 이는 본 코스의 "공식 우선" 원칙 (참조: [flame-official-packages.md](./flame-official-packages.md)) 의 **명시적 예외**입니다.

```yaml
dependencies:
  nakama: ^1.3.0                     # Nakama 클라이언트 SDK (메타 서버)
  web_socket_channel: ^3.0.3          # 학습 첫 1주 (WS), 이후 폐기
  protobuf: ^6.0.0                    # UDP 패킷 직렬화
  # dart:io RawDatagramSocket 은 SDK 내장
dev_dependencies:
  flame_test: ^2.2.4                  # prediction/reconciliation 결정론 검증 (Phase 2에서 도입)
```

- **Nakama Dart SDK 공식**: https://pub.dev/packages/nakama
- WebSocket은 학습 첫 1주만 사용 후 폐기 — 최종 트랜스포트는 UDP
- 패킷 정의(`.proto`)는 클라/Go 서버가 같은 파일을 공유 (monorepo 또는 git submodule)

> **공식 부재 영역에서 외부 패키지 도입 시 원칙**: 본 코스 [flame-official-packages.md §0.3](./flame-official-packages.md) 의 "Flame 공식이 없는 영역" 정책에 따라 일반 pub.dev 패키지 사용이 허용됩니다. 단, 신뢰성과 유지보수 활성도를 반드시 확인하세요.

---

## 12. 학습 자료

### 필수 (영어지만 시니어 이해 가능)
- **Gabriel Gambetta — Fast-Paced Multiplayer** (1~4편): https://www.gabrielgambetta.com/client-server-game-architecture.html
- **Valve — Source Multiplayer Networking**: https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking
- Gaffer On Games / Glenn Fiedler — "Networked Physics" 시리즈. 2024 이후 새 글은 https://mas-bandwidth.com (`netcode` 보안 핸드셰이크 레퍼런스 포함)

### 2024~2026 새 표준 (반드시 보세요)
- **SnapNet (UE5 SDK) 문서** — input delay vs rollback 결정 트리: https://www.snapnet.dev/docs/core-concepts/input-delay-vs-rollback/ , https://snapnet.dev/blog/performing-lag-compensation-in-unreal-engine-5/
  - ⚠️ **수치 정정**: 과거 본 자료가 적었던 "server rewind 기본 200ms 한도"는 공식 문서에서 확인되지 않습니다. SnapNet `input-delay-vs-rollback`의 실제 기본값은 **minimum input delay 0ms / maximum input delay 50ms(초과 시 prediction 시작) / maximum predicted time 100ms** 입니다. 결과적으로 50~150ms 지연 구간 플레이어는 "50ms 입력 지연 + 반응성 유지"를 얻습니다. 슈터 장르 권장값은 **양쪽 input delay 0ms + predicted time 1000ms**(로컬 플레이어만 예측), 격투/스포츠는 기본값 사용입니다.
- **Valorant 네트코드 (Riot 공개)** — 128-tick 고정 timestep + 평균 0.5 프레임 서버 버퍼 / 약 1 프레임 클라 버퍼 + backwards reconciliation: https://www.riotgames.com/en/news/peeking-valorants-netcode
  - 동일 조건(128-tick, RTT 35ms)에서 **프레임레이트가 높을수록 업데이트를 더 빨리 수신 → peeker advantage 감소**:

    | 클라 프레임레이트 | peeker advantage |
    |---|---:|
    | 60 FPS | **~141 ms** |
    | 144 FPS | **~71 ms** (60fps 대비 49% 감소) |

- **Heroic Labs Authoritative Multiplayer 가이드**: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/
  - ⚠️ **표현 정정**: Nakama 공식 문서는 멀티플레이를 **relayed(클라 권위)·authoritative(서버 권위, Match Handler)·turn-based** 등으로 제시하며 "즉시 쓸 일반 시나리오는 없고 게임 요구에 맞춰 직접 정의"할 것을 강조합니다. 따라서 "Match Handler를 1순위로 권장"은 과장이며, **빠른 실시간·서버 검증이 필요하면 authoritative(Match Handler), 검증이 덜 필요하면 relayed** 식의 조건부 선택이 정확합니다. 본 코스가 자체 Go UDP Zone을 따로 두는 것은 Nakama Match의 GC/단일 프로세스 제약을 넘는 고부하 실시간을 가정한 **학습용 구성**입니다(§10.8).

### 게임 서버 일반
- "Multiplayer Game Programming" (Joshua Glazer) — 단행본, 시니어에게 권장
- Nakama Docs: https://heroiclabs.com/docs/nakama/
- Nakama 3.39 Release Notes: https://heroiclabs.com/docs/nakama/getting-started/release-notes/
- Nakama Dart SDK: https://pub.dev/packages/nakama (⚠️ 11개월 정체, 3.39 신기능은 raw RPC 우회)
- Go `net` package: https://pkg.go.dev/net
- Go 1.26 Release Notes (Green Tea GC): https://go.dev/doc/go1.26
- Protobuf: https://protobuf.dev

### 코드
- Quake 3 source의 prediction 구현 (역사적, 짧음)
- `mas-bandwidth/netcode` (UDP 보안 핸드셰이크 C 레퍼런스): https://github.com/mas-bandwidth/netcode
- `quic-go` v0.59.1: https://github.com/quic-go/quic-go
- `kcp-go` v5.6.64: https://github.com/xtaci/kcp-go
- 전체 Nakama/Go UDP/MMO 네트워킹 출처 목록: [resources.md §0.3](./resources.md)

---

## 13. 학습 후 메모 (직접 작성)

- Prediction 구현 중 가장 헷갈렸던 점:
- 서버 시뮬레이션과 클라 시뮬레이션 분기를 잡은 방법:
- Nakama vs 자체 서버, 본인 프로젝트에 맞는 선택:

---

## 14. 다음 단계

[06-phase6-mmorpg-architecture.md](./06-phase6-mmorpg-architecture.md) — 2명에서 동작하는 것을 **수백 명**으로 확장합니다. Interest Management, Zone Server, Chunk Streaming이 본격 도입됩니다.
