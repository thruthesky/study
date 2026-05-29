# 서버 아키텍처 심화 — 시니어용 부록

> **대상**: 40년 경력의 서버 엔지니어가 MMO 게임 서버를 처음 설계할 때 빠르게 매핑할 수 있도록 작성된 부록.
> **목적**: 웹/모바일 백엔드 경험을 기반으로, 게임 서버의 **다른 점만** 명확히 짚는다.

---

## 0. 최신 기준 (2026-05-28)

본 부록은 Nakama 3.39.0 (+ nakama-common v1.46.0), Nakama Dart SDK 1.3.0, Go 1.26.3 (Green Tea GC), Protobuf 6.x / protoc v35.0 / Go protobuf v1.36.11, PostgreSQL 18.4(최신 메이저) 또는 17.10(이전 메이저), Redis 8.6.3 계열을 기준으로 다시 정리했습니다.

| 선택 | 결론 |
|---|---|
| Meta/Auth/Persist | **Nakama 3.39.0** (2026-05-20 출시). 계정, 세션, Storage, 친구, 그룹/길드, 채팅, 매치메이킹, 리더보드, Party. 매칭/파티 관련 핵심 기능(Party Listing API+Label, MatchmakerProcessor 훅)은 **2025-07의 v3.28~v3.29에 도입된 기존 기능**이며 3.39 신규가 아님. 3.39.0의 실제 신규는 *storage 객체 재시도 업데이트 런타임 함수* 와 *Satori 클라이언트 구성 가능 재시도* |
| Realtime Game Logic | **자체 Go 1.26.3 UDP Zone Server**. 30Hz tick, server authority, 이동/전투/스킬/AoI. Green Tea GC(1.26.0부터 기본 활성화)로 **GC 오버헤드 10~40% 감소** |
| Client SDK | Flutter는 `nakama: ^1.3.0`으로 메타 서버와 통신. ⚠️ Dart SDK는 약 11개월 정체(2025-06~07)라 3.39 신규 서버 기능 바인딩이 없을 수 있어 raw socket/RPC 우회 필요 |
| Go runtime module | `nakama-common v1.46.0` (2026-05-20, Nakama 3.39.0과 동일자 출시). ⚠️ 3.39.0 릴리즈 노트 본문엔 호환 버전 명시가 누락됐으나 직전 패턴(3.37.0→v1.44.2, 3.38.0→v1.45.0)상 동일자 v1.46.0이 짝. 설치: `go get github.com/heroiclabs/nakama-common@v1.46.0` |
| Packet | `.proto`를 Dart/Go가 공유 (Dart `protobuf 6.0.0`, Go `google.golang.org/protobuf v1.36.11`=APIv2, protoc v35.0). 위치 스냅샷은 unreliable, 거래/채팅/보상은 reliable |
| DB | **PostgreSQL 18.4(권장, 최신 메이저) 또는 17.10**. ⚠️ PostgreSQL 본체는 *LTS 개념이 없으며* 모든 메이저가 출시 후 5년 지원. Nakama Docker 기본 이미지가 오래된 postgres를 쓸 수 있으니 갱신 필수. Zone은 직접 write 금지 |
| Cache/Pub-Sub | **Redis 8.6.3** (2026-05-05 출시, 8.6 계열 최신 안정판) |
| 트랜스포트 | unreliable: raw UDP / reliable PvP: `kcp-go v5.6.64` Turbo / reliable 로비: `quic-go v0.59.1` / 웹: WebTransport(2026-03 Baseline 진입, Safari 26.4 포함) 또는 flutter_webrtc 1.4.1 DataChannel |

> **protobuf 버전 체계 혼동 주의.** 컴파일러 `protoc`(저장소 protocolbuffers/protobuf)는 **v35.0**(2026-05-19)로 가고, Go 런타임 `google.golang.org/protobuf`(저장소 protobuf-go)는 **v1.36.11**(2025-12-12)이 최신입니다. **서로 독립 릴리즈 주기**라 버전 숫자 체계가 다르고(v35.x vs v1.36.x), 약 5개월 간극은 정상입니다. Go 신규 코드는 **APIv2(`google.golang.org/protobuf`)만** 사용하고 레거시 `github.com/golang/protobuf`(APIv1)는 피합니다. `protoc-gen-go` 플러그인도 v1.36.x 라인과 정합되게 맞춥니다. Dart 측은 런타임 `protobuf 6.0.0` + 코드 생성 `protoc_plugin` 조합입니다. (출처: [protobuf-go releases](https://github.com/protocolbuffers/protobuf-go/releases), [google.golang.org/protobuf](https://pkg.go.dev/google.golang.org/protobuf))

---

## 1. 웹 서버 vs 게임 서버 — 본질적 차이

### 1.1 패러다임 비교

| 차원 | 웹/모바일 서버 (당신이 익숙한) | 게임 서버 |
|---|---|---|
| 처리 모델 | 요청-응답 (request-driven) | **고정 tick 루프 (tick-driven)** + 입력 큐 |
| 상태 | DB가 진실, 서버는 stateless | **메모리가 진실** (in-process), DB는 백업 |
| 트랜잭션 | DB 트랜잭션 | tick = atomic unit |
| 확장 | 수평 (stateless replica) | **샤드** (zone, instance, channel) |
| 통신 | HTTP, gRPC | TCP/WebSocket → UDP |
| 일관성 | strong (DB) | **eventual + authoritative snapshot** |
| 지연 허용 | 100~500ms OK | 50ms도 인지 |
| 연결 수명 | 짧음 (요청 단위) | 길음 (세션 시작~종료) |

### 1.2 시니어가 가장 먼저 버려야 할 직관

1. **"각 요청은 독립적"** → 게임은 입력의 시퀀스가 의미를 가짐
2. **"DB가 진실"** → in-memory 상태가 진실, DB는 주기 백업
3. **"확장 = replica 추가"** → zone/instance 분할이 본질
4. **"REST/gRPC면 충분"** → 게임은 stream 기반 (UDP/WS)
5. **"트랜잭션으로 일관성"** → tick 안에서 결정, 외부 시스템과는 eventual

---

## 2. 본 코스의 MMORPG 백엔드 아키텍처 (확정)

```
                      [Client (Flutter + Flame)]
                       │                       │
                  HTTPS / WS                 UDP
                       │                       │
              ┌────────▼──────────┐    ┌───────▼──────────────┐
              │ Nakama Meta       │    │ Gateway (자체 Go)     │
              │  - Auth / Session │    │  - Ticket 검증        │
              │  - Character CRUD │    │  - Zone 라우팅        │
              │  - Friend / Mail  │    │  - drain / rate limit │
              │  - Chat (global)  │    └────────┬──────────────┘
              │  - Matchmaking    │             │
              │  - Leaderboard    │      ┌──────┼────────┬──────┐
              │  - Storage RPC    │      ▼      ▼        ▼      ▼
              └────────┬──────────┘    [Town] [Dungeon] [PvP] [Inst.Party]
                       │                  자체 Go UDP Zone, 30Hz tick, AoI
                       │              ┌──────┴────────────────────────┐
                       │              │ Redis (Pub/Sub + Cache)       │
                       │              │  - zone 간 채팅 fanout         │
                       │              │  - 세션 / 위치 cache           │
                       │              └───────────────────────────────┘
                       │
                       ▼
              [PostgreSQL]      ← Nakama가 관리. Zone은 직접 쓰지 않음
                       ▼
              [Object Storage (CDN)]   ← 클라 패치, 에셋, 데이터 JSON
```

### 2.1 본 코스 컴포넌트 매핑

| 컴포넌트 | 본 코스 선택 | 책임 |
|---|---|---|
| **Meta / Auth / Persist** | **Nakama** | 인증, 캐릭터, 친구, 길드, 우편, 매치메이킹, 글로벌 채팅, 리더보드. PostgreSQL 직접 관리 |
| **Gateway** | **자체 Go** | Nakama 세션 토큰 검증, zone 라우팅, UDP 핸드셰이크, drain |
| **Zone Server** | **자체 Go (UDP)** | 30Hz tick, 이동/충돌/전투, AoI, 스냅샷, Server Authority |
| **Pub/Sub** | **Redis** | Zone 간 메시지(채팅 fanout, 길드 이벤트) |
| **세션 캐시** | **Redis** | zone 입장 ticket 캐시, 짧은 수명 |
| **영속 DB** | **PostgreSQL** (Nakama 관리) | Zone은 RPC 경유로만 접근 |
| **CDN** | **AWS S3 / CloudFront** 또는 동급 | 클라 에셋, 데이터 JSON 핫패치 |

### 2.2 책임 분리 — 명시적 금지 사항

- **자체 Go Zone Server가 PostgreSQL에 직접 쓰지 않음.** 단일 진실 원천을 Nakama로 유지하기 위함. Zone은 인벤토리 변경, 골드 획득 등을 Nakama RPC `inventory_apply`로 보고.
- **Nakama Match Handler로 실시간 이동 시뮬레이션을 작성하지 않음.** Nakama Match는 tick은 가능하나 GC, 단일 프로세스 제약으로 100+ 동시 접속 시 한계. 본 코스의 실시간은 **자체 Go UDP Zone**만 담당.
- **Zone Server에 자체 계정/인증 시스템을 만들지 않음.** Nakama 발급 ticket만 검증.

> **공식 입장 정확화(2026-05).** Heroic Labs 공식 문서는 멀티플레이를 *relayed*(클라이언트 권위, 서버는 메시지 중계만), *authoritative*(서버 권위, Go/Lua/TS Match Handler), *turn-based* 등으로 제시하면서 "즉시 쓸 수 있는 일반 시나리오는 없으며 게임 요구에 맞춰 직접 정의하라"고 안내합니다. 즉 "모든 게임에 Match Handler를 1순위로 권장"하는 것이 아니라 **조건부**입니다 — 서버 검증이 중요한 빠른 실시간이면 *authoritative Match Handler*, 부정 위험이 낮고 단순 중계로 충분하면 *relayed*. 본 코스가 굳이 자체 Go UDP Zone을 두는 이유는, Nakama Match가 단일 프로세스·Go GC 영향을 받는 구조라 **수백~수천 동접의 고부하 실시간 시뮬레이션**을 가정할 때 한계가 있기 때문이며, 이는 "Nakama Match로는 불가능"이 아니라 **학습용으로 풀-권위 UDP 루프를 직접 구현해 보기 위한 의도적 구성**입니다. (출처: [Nakama Authoritative Multiplayer](https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/))

---

## 3. Zone Server의 내부 구조

### 3.1 단일 goroutine tick (강력 추천)

게임 서버의 가장 큰 함정은 "멀티 goroutine으로 동시성"입니다. **한 zone = 한 tick goroutine**이 락 없이 모든 상태를 다루는 것이 압도적으로 단순하고 빠릅니다.

```go
type Zone struct {
    players  map[ID]*Player
    monsters map[ID]*Monster
    grid     *SpatialGrid
    inbox    chan Msg              // 클라 입력, 외부 RPC
    outbox   map[ID]chan []byte    // 클라별 송신 큐
}

func (z *Zone) Run() {
    tick := time.NewTicker(33 * time.Millisecond)
    for {
        select {
        case msg := <-z.inbox:
            z.handle(msg)             // 입력 큐잉만, 시뮬레이션은 tick에서
        case <-tick.C:
            z.simulate()
            z.broadcast()
        }
    }
}
```

이 모델의 장점:
- 락 없음 → CPU cache friendly
- 결정론적 → 디버깅 용이
- 입력 순서 보장 → 동기화 단순

단점:
- 한 zone이 한 CPU 코어 → 코어를 다 쓰려면 zone을 분할

### 3.2 입력 큐 처리

- 입력은 `inbox`에 들어옴 (다른 goroutine이 socket에서 읽어 push)
- tick 시작 시 inbox를 drain
- 시뮬레이션
- 결과를 outbox에 push (다른 goroutine이 socket으로 송신)

### 3.3 IO 분리

```
[net.Conn] → [reader goroutine] → [zone.inbox] → [tick goroutine] → [outbox] → [writer goroutine] → [net.Conn]
```

reader/writer는 그냥 채널 push/pop만. 게임 로직 0.

### 3.4 goroutine 누수 진단 (Go 1.26 신규)

위 IO 분리 모델은 **연결 1개당 reader/writer goroutine 2개**가 생깁니다. 세션이 끊겼는데 채널 close/`context` 취소를 빠뜨리면 goroutine이 영구 블록되어 누수되고, 수만 동접 MMO에서는 이것이 OOM의 흔한 원인입니다.

Go 1.26.0(2026-02-10)에서 **goroutine leak profile**이 실험 기능으로 추가되었습니다. 영구 블록(예: 아무도 수신/송신하지 않는 채널, 절대 해제되지 않는 락 대기)된 goroutine을 탐지합니다.

```bash
# 빌드/실행 시 experiment 플래그가 필요(기본 비활성)
GOEXPERIMENT=goroutineleakprofile go build ./...
```

```go
// 코드에서 직접 덤프
import "runtime/pprof"
pprof.Lookup("goroutineleak").WriteTo(w, 0)

// 또는 net/http/pprof 등록 시
// http://<host>/debug/pprof/goroutineleak
```

- 활성화에는 빌드 플래그 `GOEXPERIMENT=goroutineleakprofile`가 **반드시** 필요합니다(1.26에서는 opt-in, 1.27 기본화 목표).
- Zone Server·Gateway의 reader/writer goroutine 누수를 운영 중 주기적으로 스냅샷해 회귀를 잡는 용도로 적합합니다.

(출처: [Go 1.26 Release Notes](https://go.dev/doc/go1.26))

---

## 4. 상태 일관성 모델

### 4.1 세 가지 상태 저장소

| 저장소 | 갱신 주기 | 손실 허용 | 용도 |
|---|---|---|---|
| Zone memory | 33ms (tick) | 짧은 시간이면 OK | 위치, 현재 HP, 전투 상태 |
| Redis | 1초 ~ 1분 | 분 단위 OK | 세션, 인벤토리 캐시, 채팅 |
| PostgreSQL | 30초 ~ 5분 | 거의 불가 | 영속 데이터 (캐릭터, 골드, 아이템) |

### 4.2 저장 트리거

```
- 로그아웃: 즉시 PG 저장
- 의미 있는 액션 (레벨업, 거래, 결제): 즉시 PG
- 주기 백업: 30~60초 마다 변경분만
- Graceful shutdown: 모든 zone state PG 저장 후 종료
- Crash: 마지막 백업 시점까지 복구 (사용자에게 작은 손실 통보)
```

### 4.3 거래·아이템 변동 — 분산 트랜잭션

여러 플레이어 간 거래는 **여러 zone**에 걸칠 수 있습니다.

권장 패턴: **Saga + Idempotent + Event Sourcing**
1. 거래 시작 → trade_id 생성, PG에 PENDING 기록
2. 양측 zone에서 아이템 lock
3. 양측 confirm 받으면 → 양측 아이템 swap → PG COMMITTED 기록
4. 실패 시 → 보상 트랜잭션으로 rollback

> 시니어에게 익숙한 패턴. 게임 특화 차이: **lock은 메모리에서만 짧게**, PG는 결과만.

#### 멱등성(Idempotency) — UDP/재시도 환경의 필수 전제

웹 백엔드와 달리 Zone↔Nakama 보고는 **UDP 재전송·재접속·crash 복구**로 같은 명령이 두 번 도착할 수 있습니다. 따라서 모든 영속 변경 RPC(`inventory_apply`, `gold_grant`, 거래 commit)는 **반드시 멱등**해야 합니다.

- 클라/Zone이 생성한 `operation_id`(UUID)를 RPC에 동봉.
- Nakama 측은 `applied_ops` 집합(또는 storage object의 버전/`op_id` 컬럼)에 이미 있으면 **no-op으로 성공 반환**, 없으면 적용+기록을 **하나의 PG 트랜잭션**으로 처리.
- 결과적으로 "골드 2배 지급", "아이템 복제"의 핵심 원인인 재시도 중복을 차단.

```go
// Nakama Go 런타임 모듈 (nakama-common v1.46.0)
// 멱등 인벤토리 적용 RPC: op_id가 이미 있으면 그대로 성공
func InventoryApply(ctx context.Context, logger runtime.Logger, db *sql.DB,
    nk runtime.NakamaModule, payload string) (string, error) {
    // 1) op_id 동봉 여부 검사 → 2) PG에서 op_id INSERT ... ON CONFLICT DO NOTHING
    // 3) RowsAffected==0 이면 이미 처리됨 → 현재 상태 그대로 반환(멱등)
    // 4) 신규면 인벤토리 변경 + op_id 기록을 같은 트랜잭션으로 commit
    return "", nil
}
```

#### Zone은 PG 직접 쓰기 금지 → Outbox로 비동기 보고

§2.2의 "Zone은 PG에 직접 쓰지 않음" 원칙과 결합하면, Zone tick 안에서 RPC를 **동기 호출**하면 tick이 막힙니다(§12.2). 대신 Zone은 변경 이벤트를 **메모리 outbox 큐**에 쌓고, 별도 goroutine이 Nakama RPC로 배치 전송하며, 실패 시 재시도(at-least-once)합니다. 멱등 RPC가 전제이므로 재시도가 안전합니다. 이 패턴이 곧 **transactional outbox**의 게임 서버 변형입니다.

---

## 5. 네트워크 프로토콜 설계

### 5.1 메시지 프레임

```
+----+--------+---------------+
| op | seq    | payload       |
| 2B | 4B     | variable      |
+----+--------+---------------+
```

- op: 메시지 타입 (1~65535)
- seq: 순서, 중복 검출
- payload: Protobuf / FlatBuffers / 자체 binary

### 5.2 신뢰성 채널

| 채널 | 신뢰성 | 순서 | 용도 |
|---|---|---|---|
| Unreliable | X | X | 위치 업데이트 (다음 패킷이 곧 옴) |
| Reliable Unordered | O | X | 이벤트 (사망, 아이템 획득) |
| Reliable Ordered | O | O | 채팅, 거래 |

UDP 위에서 직접 구현하거나 KCP/ENet/QUIC 라이브러리.

WebSocket으로 시작했다면 모두 Reliable Ordered. UDP로 전환 시 위 표대로 분리.

#### KCP(`kcp-go v5.6.64`)를 reliable PvP에 쓰는 근거 — 실측 수치

"KCP가 ENet보다 빠르다"는 흔히 과장됩니다(일부 자료의 "10배"는 근거 미약). 실측 기준은 다음과 같습니다.

- 독립 벤치([Latency of Reliable Streams]): KCP Turbo 평균 RTT **40.582ms**(표준편차 10.399) vs ENet **139.306ms**(표준편차 147.850) — 약 **3.4배** 우위. KCP는 편차도 훨씬 작아 jitter가 안정적.
- KCP 공식 README 요약: 평균 지연 **30~40% 감소**, 손실·lag 발생 시 최대 지연 **약 3배 감소**, 대신 **TCP 대비 대역폭 10~20% 추가 소모**(RTO를 지수 백오프가 아닌 1.5배로 잡아 빠르게 회복하는 trade-off).

즉 KCP는 "마법의 10배"가 아니라 **불안정한 망에서 ENet 대비 약 3배 낮은 지연·작은 jitter를 대역폭을 더 써서 얻는** 선택입니다. PvP처럼 신뢰+순서가 필요하면서도 지연 민감한 채널에 적합합니다. (출처: [paytonturnage.com](https://paytonturnage.com/writing/latency-of-reliable-streams/), [skywind3000/kcp README](https://github.com/skywind3000/kcp/blob/master/README.en.md))

### 5.3 패킷 크기 가이드

- **단편화(fragmentation)를 절대 피한다.** UDP 패킷이 경로 MTU를 넘으면 IP 단편화가 일어나고, 조각 하나만 유실돼도 전체 패킷이 버려져 손실률이 급증한다.
- IPv6 최소 MTU는 1280B. 여기서 헤더를 빼면 **단편화 없는 안전 페이로드 상한 = 1280 − IPv6 헤더 40 − UDP 헤더 8 = 1232B**.
- 실무 게임은 경로상 터널/PPPoE/VPN 오버헤드를 더 감안해 페이로드를 **1200B 근처**로 보수적으로 잡는다(QUIC도 initial datagram 기본값으로 1200B를 사용 — RFC 9000).
- 따라서 실전 권장은 **payload ≤ 1200~1232B**.
- 1 tick의 모든 송신 ≤ 1 패킷이 이상적.
- 큰 메시지는 chunking + reassembly(애플리케이션 레벨), 또는 reliable 채널(KCP/QUIC) 위임.

(출처: [RFC 9000 §14](https://datatracker.ietf.org/doc/html/rfc9000))

### 5.4 압축

- Protobuf 자체로 충분히 작음
- 추가로 LZ4 / Snappy로 zone 단위 batch 압축
- 전체적으로 메시지당 100바이트 이하 목표 (위치만이면 20바이트)

---

## 6. Sharding / Scaling

### 6.1 Vertical (단일 zone 강화)
- CPU 코어 1개 한계 → goroutine 분할은 거의 불가능 (락 지옥)
- 메모리 더 주고, 알고리즘 최적화 (Spatial Hash, Pool)
- 보통 **한 zone에 200~500명**이 한계 (게임 특성에 따라)

### 6.2 Horizontal (zone 분할)
- 지리적: 마을 / 던전 A / 던전 B
- 인스턴스: 같은 던전 여러 복사본 (party 단위)
- 채널: 같은 마을의 채널 1, 2, 3 (RO, Mabinogi 식)

### 6.3 Channel vs Zone
- Zone: 콘텐츠 단위 (마을, 던전), 사용자 선택 X
- Channel: 같은 콘텐츠의 복제본, 사용자가 선택 또는 자동 배정
- 둘 다 같은 메커니즘으로 구현 (zone server 여러 개)

### 6.4 Capacity Planning

```
1 zone server (8 core, 16GB) → 300명 평상시, 500명 피크
10만 DAU, 동접 1만 → 30~40 zone server
```

- 사전에 측정 → 봇 부하 테스트
- 자동 spin-up 정책 (k8s HPA + custom metric)

#### 산정 근거 — 추정 → 측정으로 보정

위 숫자는 출발점일 뿐이며, 반드시 **봇 부하 테스트로 보정**합니다. 추정 공식은 다음과 같습니다.

**상향 대역폭(서버→클라)**: 핵심 변수는 동시 인원이 아니라 **AoI 안에 보이는 평균 이웃 수 `k`**(§D AoI 9-cell 검색 결과)입니다.

```
플레이어 1명 수신량 ≈ k(평균 가시 이웃) × snapshot_per_entity(B) × tick_rate(Hz)
서버 1대 상향 대역폭 ≈ Σ(접속자별 위 값)

예) k=30, entity당 20B, 30Hz → 30 × 20 × 30 = 18,000 B/s ≈ 18 KB/s/인
    300명 → 약 5.4 MB/s ≈ 43 Mbps (상향). 500명 피크 → 약 72 Mbps
```

> 핵심 통찰: **인원이 N배여도 대역폭은 단순 N배가 아니다.** AoI로 가시 이웃 `k`를 상한으로 묶으면 밀집 구역(보스 레이드, 마을 광장)에서도 송신량이 폭주하지 않는다. delta/관심영역 압축(§5.4)으로 `snapshot_per_entity`를 줄이는 것이 대역폭 최적화의 본질.

**CPU**: tick당 비용 ≈ O(N×k)(이동·충돌 broadcast) + O(전투 이벤트 수). `tick_duration_p99 < 30ms`(§9.2 SLO, 33ms tick의 여유분)를 깨기 직전 인원이 그 서버의 실효 상한입니다. Green Tea GC(Go 1.26) 적용 시 GC 오버헤드가 줄어 같은 하드웨어에서 인원 상한이 다소 올라갑니다(§4.3 참조 — 단, "오버헤드 10~40% 감소"는 GC 부하가 큰 프로그램 기준).

**메모리**: 플레이어/몬스터 엔티티 구조체 + 인벤토리 캐시 + outbox 큐 버퍼가 주 소비처. 16GB면 엔티티 수천 단위는 여유이며, 메모리보다 **CPU/대역폭이 먼저 한계**에 닿는 것이 일반적입니다.

**언제 zone을 분할하나**: 단일 zone goroutine은 코어 1개만 쓰므로(§3.1), `tick_duration_p99`가 한계에 근접하면 채널(복제본) 또는 콘텐츠 분할로 넘어갑니다(§6.2~6.3). 수직 확장(코어 추가)은 거의 효과가 없습니다.

---

## 7. 인증 / 보안

### 7.1 인증 흐름 (본 코스 확정)

```
1. 클라 → Nakama: 이메일/패스워드 또는 OAuth
2. Nakama → 클라: 세션 토큰(JWT) + refresh 토큰 + 캐릭터 목록
3. 클라 → Nakama RPC `zone_join_ticket(character_id, zone)`: 짧은 수명 ticket(15초)
4. 클라 → Gateway: UDP 핸드셰이크 + ticket
5. Gateway: ticket 검증 (HMAC 서명 검증 또는 Redis 조회)
6. Gateway → Zone: 내부 채널로 player 등록 알림
7. Zone: 게임 시작, 스냅샷 송신 시작
```

핵심: **Zone Server는 자체 비밀번호/세션을 갖지 않습니다.** Nakama가 발급한 짧은 수명 ticket만 검증.

#### ticket 검증을 정확히 — 대칭 HMAC vs Redis 조회

> **주의(정확성).** Nakama 세션 토큰은 **대칭키 HMAC(HS256) JWT**입니다. 비대칭 "공개키"가 아니라 서버가 가진 **공유 secret**(`session.encryption_key`)으로 서명·검증합니다. 따라서 Gateway가 Nakama 세션 JWT를 직접 검증하려면 같은 secret을 공유해야 합니다.

설계상 두 가지 ticket 검증 방식이 있습니다.

1. **자기완결(stateless) ticket** — `zone_join_ticket` RPC가 `{character_id, zone, exp}`를 만들어 **공유 HMAC secret으로 서명**해 반환. Gateway는 같은 secret으로 서명·만료만 검증하면 되어 추가 조회가 없습니다(빠름). 단, 발급 후 강제 무효화(밴/킥)가 어렵습니다.
2. **상태기반(stateful) ticket** — RPC가 랜덤 토큰을 만들어 **Redis에 `tkt:{token} = {character_id, zone}` (TTL 15초)** 로 저장하고 클라에 토큰만 줌. Gateway는 `GETDEL`로 1회용 조회·소비(replay 차단). 즉시 무효화·1회성 보장이 강점, Redis 왕복이 비용.

본 코스 권장: **상태기반 + `GETDEL`**(replay 방지가 핵심이고 15초 TTL이라 Redis 부하도 미미). 1회용이므로 §7.3 rate limit과 함께 ticket 재사용 공격을 차단합니다.

### 7.2 핵 방어

| 공격 | 방어 |
|---|---|
| 위치 조작 | 서버 시뮬레이션 (Authority) |
| 속도 조작 | 서버에서 dt 검증, 속도 한계 |
| 데미지 조작 | 데미지 공식 서버 전용 |
| 패킷 위조 | 서명 + sequence + 재전송 검증 |
| DDoS | CloudFlare, WAF, rate limit |
| 봇 | 행동 패턴 분석, ML, 캡차 |
| 클라 디컴파일 | 어차피 됨. **Server Authority가 본질** |

### 7.3 Rate Limit

- 같은 IP에서 분당 N개 연결 시도 제한
- 같은 계정에서 초당 메시지 수 제한
- 거래 시 짧은 시간 다수 요청 거부

---

## 8. 데이터 모델 (시작 템플릿)

> **주의**: 본 코스에서는 **Nakama가 PostgreSQL을 자동 관리**합니다. 아래 테이블 중 계정(`users`), 친구(`user_edge`), 그룹(`groups`/길드), 우편(notification + storage) 등은 **Nakama 내장 스키마를 그대로 사용**하세요. 직접 만들 필요가 있는 것은 **게임 도메인 고유 데이터**(캐릭터, 인벤토리, 인스턴스 던전 진행 등)이며 이들은 Nakama의 `storage` 객체 또는 사용자 정의 테이블로 추가합니다.

### 8.1 Nakama 내장으로 처리되는 것
- `users` (계정) — Nakama가 관리. 이메일/소셜 인증 모두 자동
- `user_edge` (친구 관계) — Nakama 친구 API
- `groups` / `group_edge` (길드) — Nakama 그룹 API
- `notification` (우편/시스템 메시지) — Nakama notification API
- `leaderboard_record` (랭킹) — Nakama 리더보드 API
- `storage_object` (범용 KV 저장소) — JSON 객체 저장 (캐릭터 시트 등 권장 저장 위치)

> **낙관적 동시성 제어(OCC)를 반드시 쓴다.** Nakama `storage_object`는 객체마다 `version`(콘텐츠 해시=ETag)을 가집니다. 인벤토리·골드처럼 동시 수정 위험이 있는 데이터를 쓸 때 읽은 시점의 `version`을 write에 동봉하면, 그 사이 누가 바꿨을 경우 write가 거부됩니다(CAS). 충돌 시 read→merge→retry로 처리하세요. 이는 §4.3의 멱등 `op_id`와 함께 **아이템 복제·골드 중복**을 막는 두 번째 방어선입니다. (`version: "*"`는 "객체가 없을 때만 생성", 빈 version은 무조건 덮어쓰기.) 또한 Nakama가 자동 관리하는 `users` 등 내장 테이블에 애플리케이션 FK를 직접 거는 것은 Nakama 스키마 마이그레이션 시 깨질 수 있으므로, 게임 도메인 테이블은 가능하면 **storage object 또는 느슨한 참조(user_id 컬럼만 보관, DB FK 미설정)** 로 두는 편이 안전합니다.

### 8.2 게임 도메인 추가 테이블 (직접 정의)

```sql
-- 캐릭터 (Nakama storage object 또는 별도 테이블)
-- storage_object 사용 시 collection='character', key=character_id, value=JSONB
CREATE TABLE IF NOT EXISTS character_state (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users,            -- Nakama users.id
  name TEXT UNIQUE NOT NULL,
  class TEXT,
  level INT, exp BIGINT,
  position_x DOUBLE PRECISION,
  position_y DOUBLE PRECISION,
  zone TEXT,
  stats JSONB,
  equipment JSONB,
  last_login TIMESTAMPTZ
);

-- 인벤토리 (행당 1슬롯)
CREATE TABLE IF NOT EXISTS inventory (
  character_id UUID REFERENCES character_state(id),
  slot INT,
  item_id TEXT,
  quantity INT,
  plus INT,
  PRIMARY KEY (character_id, slot)
);

-- 멱등 처리 원장 (§4.3): 이미 적용된 변경 op_id 기록
CREATE TABLE IF NOT EXISTS applied_ops (
  op_id UUID PRIMARY KEY,            -- 클라/Zone이 생성한 멱등 키
  character_id UUID,
  kind TEXT,                         -- inventory_apply / gold_grant / trade_commit ...
  applied_at TIMESTAMPTZ DEFAULT now()
);
-- 적용 시: INSERT ... ON CONFLICT (op_id) DO NOTHING → RowsAffected==0 이면 중복(no-op)

-- 우편
CREATE TABLE mails (
  id UUID PRIMARY KEY,
  to_character UUID,
  from_name TEXT,
  subject TEXT, body TEXT,
  attachment JSONB,
  read_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ
);

-- 거래 로그 (감사용)
CREATE TABLE trade_log (
  id UUID PRIMARY KEY,
  trade_id UUID,
  giver UUID, receiver UUID,
  item_id TEXT, quantity INT,
  occurred_at TIMESTAMPTZ
);
```

### 8.3 Redis 키 스키마

```
sess:{token}            = JSON {account_id, character_id, zone, expires}
tkt:{token}             = JSON {character_id, zone}      (zone 입장 1회용 ticket, TTL 15s, GETDEL 소비 — §7.1)
char:{character_id}:pos = JSON {x, y, zone, updated}   (자주 갱신, 손실 OK)
zone:{zone}:players     = SET of character_id            (현재 zone의 사람)
chat:global             = STREAM (lastN 메시지 보관)
rate:{ip}               = INT (TTL 1m, 1초당 +1)
```

> Redis는 **재구성 가능**한 데이터만. 잃어도 PG에서 다시 만들 수 있어야 함.

---

## 9. 관측가능성 (Observability)

### 9.1 Three Pillars

| 종류 | 도구 | 게임 특화 메트릭 |
|---|---|---|
| Metric | Prometheus | tick_duration_p99, players_per_zone, snapshot_bytes/s |
| Log | Loki / ELK | 구조화 JSON, level=info/warn/error, event=login/death |
| Trace | Tempo / Jaeger | tick 안의 phase별 소요 시간 (input/sim/broadcast) |

### 9.2 Critical SLO 예시

```
SLO 1: tick_duration_p99 < 30ms (가용성 99.9%)
SLO 2: login latency p95 < 1초
SLO 3: zone available 99.9% (월 ~43분 다운 허용)
```

### 9.3 추적해야 할 이벤트

```
session_open, session_close, character_create, character_delete,
zone_enter, zone_leave, level_up, item_acquire, item_lose,
trade_complete, purchase_complete, purchase_refund,
death (by whom, where), kick (by GM), error_panic
```

---

## 10. 실전 운영 패턴

### 10.1 Graceful Shutdown
1. Gateway: 신규 접속 거부
2. Zone: 새 입장 거부, 안내 메시지 broadcast
3. Zone: 30초~5분 대기 (자발적 로그아웃 유도)
4. Zone: 강제 저장 → 모든 player를 PG에 flush
5. 종료

### 10.2 점검 패치
```
1. 공지 (3일 전 / 1일 전 / 1시간 전)
2. 점검 직전: 결제 시스템 차단
3. 점검 시작: 점검 모드 toggle
4. 패치 진행
5. 무결성 검증 (smoke test, 가짜 클라이언트)
6. 점검 종료 → 모니터링 강화
```

### 10.3 핫픽스 (점검 없이)
- 데이터(JSON) 패치: CDN 교체 → 클라 재접속 시 적용
- 서버 코드 패치: zone drain + replace 패턴

---

## 11. 비용 모델 (대략)

소규모 (~1만 동접):
- Zone server: AWS c6i.2xlarge × 10대 = $4,000/월
- PG: db.r6g.large + replica = $500/월
- Redis: cache.r6g.large = $200/월
- Gateway/LB: $200/월
- 트래픽: 100~500GB/일 → $300~1000/월
- 모니터링/스토리지: $200/월
- **합계: $5,000~6,000/월**

대규모(~10만 동접): 위의 10~20배. 자체 IDC 검토 시점.

---

## 12. 시니어가 가장 자주 하는 실수

### 12.1 "마이크로서비스로 처음부터"
- Zone server는 stateful + 시뮬레이션 단일 단위. 분해 X.
- Login/Meta는 stateless → 분리 OK.

### 12.2 "DB로 모든 일관성 해결"
- Zone tick에서 DB 호출(또는 동기 Nakama RPC) = 즉사. tick 안에서는 메모리만 만지고, 변경은 outbox 큐로 비동기 위임(§4.3) + 멱등 op_id로 at-least-once 재시도.

### 12.3 "Kubernetes에 그냥 올리면 됨"
- WebSocket / UDP 연결의 sticky session, 그리고 stateful zone의 drain 패턴이 추가 작업 필요.

### 12.4 "ECS / DOD 처음부터"
- 시니어 함정. 단순 OOP로 시작하고 병목이 보이면 그때.

### 12.5 "Anti-cheat을 클라 보안으로"
- 클라는 신뢰 0. **Server Authority가 안티치트의 90%.**

### 12.6 "서버 코드를 Dart로"
- Dart 서버는 게임에는 부적합. Go 권장. Rust도 가능하나 학습 비용.

---

## 13. 마무리

본 문서는 시니어가 MMO 서버 도메인을 빠르게 매핑하기 위한 보조 자료입니다. 본 코스의 Phase 5~6을 진행하며 이 문서를 옆에 두고 참조하세요.

핵심 메시지:
1. **상태는 메모리에**, DB는 백업
2. **tick 단위 결정**, 외부 시스템과는 eventual
3. **Server Authority가 안티치트의 본질**
4. **단일 goroutine tick + 큐 분리**가 동시성 함정 회피
5. **Zone으로 수평 확장**, replica로 수직은 불가
6. **모니터링은 첫 출시 전 필수**

---

## 14. 더 깊이 읽을 자료

- "Multiplayer Game Programming" (Joshua Glazer)
- "Designing Data-Intensive Applications" (Martin Kleppmann)
- "Site Reliability Engineering" (Google)
- 1024Cores.net (concurrency 깊이)
- GDC vault: "MMO architecture", "Server architecture"
- Nakama Open Source code (Go 게임 서버 reference)
- Nakama docs/release notes: https://heroiclabs.com/docs/nakama/ / https://heroiclabs.com/docs/nakama/getting-started/release-notes/
- Nakama Authoritative Multiplayer(권장 모델 조건부 선택): https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/
- Nakama 릴리스(버전 매핑·nakama-common 짝): https://github.com/heroiclabs/nakama/releases / https://github.com/heroiclabs/nakama-common/releases
- Go networking/pprof: https://pkg.go.dev/net / https://pkg.go.dev/net/http/pprof
- Go 1.26 릴리스 노트(Green Tea GC 기본 활성화, cgo ~30%↓, goroutineleak 프로파일): https://go.dev/doc/go1.26
- PostgreSQL 버전 정책(LTS 없음, 메이저당 5년 지원): https://www.postgresql.org/support/versioning/
- KCP vs ENet 실측: https://paytonturnage.com/writing/latency-of-reliable-streams/ / https://github.com/skywind3000/kcp/blob/master/README.en.md
- QUIC/UDP 페이로드 안전치(initial datagram 1200B): [RFC 9000](https://datatracker.ietf.org/doc/html/rfc9000)
- 전체 서버 출처 목록: [resources.md §0.3](./resources.md)
