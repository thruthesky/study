# Phase 8 — 라이브 서비스 (운영)

> **기간**: 지속
> **목표**: 만든 게임을 **계속 운영**할 수 있는 토대. 모니터링, 패치, 분석, 백오피스, 장애 대응.
> **시니어 코멘트**: 웹/모바일 운영 경험이 80% 그대로 적용됩니다. 다른 20%는 "**상태가 in-memory에 있는 stateful 서비스**"라는 점에서 옵니다.

---

## 1. 학습 목표

- [ ] 클라이언트 패치 전략 (앱 업데이트 + 핫패치)
- [ ] 서버 무중단 배포 (Rolling, Blue/Green, Drain Connection)
- [ ] 메트릭 / 로그 / 트레이싱 (Prometheus, Loki, Tempo)
- [ ] 분석 (DAU, ARPU, Retention, Funnel)
- [ ] 백오피스 (GM 도구, 차단/지급)
- [ ] 장애 대응 플레이북
- [ ] A/B 테스트 / Feature Flag
- [ ] 보안 (anti-cheat, RPC validation, rate limit)

---

## 2. 라이브 서비스의 본질

| 일반 모바일/웹 서비스 | MMORPG 서비스 |
|---|---|
| stateless 서버 → 즉시 교체 | **stateful zone 서버** → drain & migrate 필요 |
| 데이터 불일치 = 보통 새로고침으로 회복 | 데이터 불일치 = 캐릭터/아이템 소실 가능 |
| 배포 5분 다운 OK | 게임 중 다운은 사용자 체감 크다 (전투 중 끊김) |
| 사용자 트래픽 패턴: 종 모양 | 게임은 저녁 8~11시 폭주, 점심 보조 피크 |

---

## 3. 패치 전략

### 3.1 클라이언트
**스토어 업데이트 (필수)**:
- iOS/Android 심사 1~7일
- 강제 업데이트는 신중히 (이탈 유발)

**핫패치 (선택)**:
- 에셋(이미지, 맵), 데이터(아이템, 스킬 수치) → 서버에서 다운로드
- Flutter 앱은 **Dart 코드 자체는 핫패치 불가** (Apple 정책)
- 대안: 데이터 드리븐 설계 → JSON 교체로 80% 변경 가능

> 시니어 팁: 처음부터 모든 게임 파라미터를 **서버 JSON**으로 분리. 하드코딩 시 패치 지옥.

### 3.2 서버
**Nakama 메타** (사실상 stateless 요청-응답): 표준 rolling 또는 blue/green deploy. PostgreSQL 마이그레이션은 별도.
**자체 Go Zone (stateful)**:
1. 새 zone 인스턴스 기동 (v2)
2. Gateway가 새 접속을 v2로 라우팅 (v1 신규 거부)
3. v1의 기존 플레이어가 zone 이동 / 로그아웃할 때까지 대기 (drain)
4. v1: 잔여 플레이어 상태를 Nakama RPC로 강제 flush → 안전 종료

> 일부 회사는 정해진 점검 시간(예: 매주 수요일 새벽 4시)에 전체 재시작. 운영 단순. 본 코스 학습엔 충분.

#### 3.2.1 Stateful Zone Drain의 실제 메커니즘 (k8s 기준)

위 4단계를 **Kubernetes에서 안전하게 구현**하려면 표준 종료 흐름을 정확히 이해해야 합니다. stateless 서비스는 SIGTERM 받고 바로 죽어도 되지만, **zone 서버는 in-memory에 플레이어 상태가 있어 "갑자기 죽으면 진행/아이템 소실"**이 핵심 차이입니다.

- **`terminationGracePeriodSeconds`를 충분히 크게** — k8s 기본값은 30초입니다. 전투 중인 플레이어가 안전 지점으로 빠지거나 다른 zone으로 마이그레이트할 시간을 고려해 **수 분 단위(예: 300초)**로 늘립니다.
- **`preStop` hook으로 drain 시작** — Pod가 Terminating으로 바뀌면 k8s는 (1) Service Endpoints에서 Pod를 제거(신규 트래픽 차단)하면서 동시에 (2) `preStop` hook 실행 → (3) SIGTERM 전송 → (4) grace period 경과 시 SIGKILL 순으로 진행합니다. preStop에서 Gateway에 "이 zone은 draining"을 알리고 **신규 입장만 거부**, 기존 세션은 유지합니다.
- **SIGTERM 핸들링** — Go 서버는 `signal.Notify(ch, syscall.SIGTERM)`로 신호를 받아 **즉시 종료하지 말고**: 신규 입장 거부 → 잔여 플레이어 상태를 DB/Nakama로 flush(체크포인트) → 안전 지점 이동·강제 로그아웃 → 모든 세션 정리 후 `os.Exit(0)`. 이 과정이 grace period 안에 끝나야 SIGKILL로 강제 종료되지 않습니다.
- **endpoint 제거와 in-flight 요청의 경쟁 조건** — Endpoints 제거는 비동기라, 제거 직후에도 잠시 신규 연결이 들어올 수 있습니다. preStop에 짧은 `sleep`을 두어 라우팅 갱신이 전파될 시간을 확보하는 것이 흔한 관용구입니다.

```go
// SIGTERM 수신 → graceful zone drain (개념 코드)
sig := make(chan os.Signal, 1)
signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
<-sig

zone.RejectNewPlayers()        // 신규 입장 거부 (Gateway에도 통지)
zone.BroadcastShutdownNotice() // 클라에 "곧 이동/저장" 안내
zone.FlushAllPlayerState(ctx)  // in-memory 상태 → DB/Nakama 체크포인트
zone.MigrateOrLogoutRemaining(ctx)
os.Exit(0)
```

> 시니어 코멘트: 이것은 웹에서 익숙한 **connection draining/graceful shutdown**과 같은 패턴이지만, 차이는 "**flush할 상태가 있다**"는 점입니다. drain 타임아웃을 못 지키고 SIGKILL되면 마지막 체크포인트 이후 진행이 통째로 날아갑니다. 그래서 **상태 체크포인트 주기(예: N초마다 또는 주요 이벤트마다)**를 평소에 짧게 유지하는 설계가 drain 안전성의 진짜 토대입니다. 자세한 zone 마이그레이션은 [server-architecture.md](./server-architecture.md) 참고.

### 3.3 점검 모드
- Gateway에 "maintenance" flag → 모든 신규 접속에 안내문
- 백오피스에서 한 번에 토글

---

## 4. 모니터링

### 4.1 메트릭 (Prometheus + Grafana)
**클라이언트가 보낼 것** (1분 주기):
- FPS, 메모리, 평균 ping, 패킷 손실

**서버가 보낼 것** (10초 주기):
- 활성 connection 수, tick time(p50/p99), 메시지 in/out rate
- CPU, RAM, goroutine 수
- 에러 카운트, panic 카운트

### 4.2 로그 (Loki 또는 ELK)
- 구조화 로그 (JSON)
- 게임 이벤트: 로그인, 로그아웃, 사망, 거래
- 에러 / 경고

```go
// trace_id를 항상 포함시켜야 §4.5의 로그↔트레이스 점프가 가능
logger.Info("player_death", "id", id, "by", killerId, "zone", zone, "pos", pos, "trace_id", traceID)
```

### 4.3 트레이싱 (Tempo / Jaeger)
- 요청이 Gateway → Zone → DB까지 어떻게 흘렀나
- 게임 서버는 1초간의 tick 트레이스가 더 의미 있음
- **수집은 OpenTelemetry로 통일** — Go 서버는 `go.opentelemetry.io/otel` SDK로 span을 만들고 OTLP로 내보냅니다(수집은 OpenTelemetry Collector → Tempo). 벤더 종속을 피하는 사실상 표준입니다.
- **trace context propagation** — Gateway에서 시작한 `traceparent`(W3C Trace Context)를 Zone·DB 호출까지 전파해야 한 요청의 전체 경로가 하나의 trace로 묶입니다. RPC 메시지 헤더에 trace context를 실어 넘기세요.
- **게임 서버 특유의 주의**: 매 프레임(틱)마다 span을 만들면 60fps × 수백 엔티티에서 trace가 폭증합니다. → **tail sampling**(느린/에러 trace만 보존)이나 **요청 단위(스킬 사용·거래·존 이동 등 의미 있는 액션) span**으로 제한하고, 상시 부하는 메트릭(§4.1)으로 보는 것이 실전적입니다.

### 4.4 알람
- p99 tick time > 30ms → Slack
- 에러 rate > 1% → Slack + 호출
- Zone 죽음 → PagerDuty 즉시
- 점심·저녁 피크 시간 동시 접속 50% 이상 감소 → 조사

### 4.5 세 신호 묶기 — Grafana 통합 스택

메트릭(Prometheus) · 로그(Loki) · 트레이스(Tempo)를 **Grafana 하나에서 상호 점프(correlation)**할 수 있게 묶는 것이 관측의 핵심입니다. 신호가 따로 놀면 장애 시 도구 사이를 헤매느라 MTTR(평균 복구 시간)이 늘어납니다.

- **메트릭 → 트레이스**: Prometheus의 **exemplar**(특정 샘플에 trace_id를 붙이는 기능)를 켜면 "p99 tick time이 튄 그 순간의 trace"로 바로 점프할 수 있습니다.
- **로그 → 트레이스**: 구조화 로그(§4.2)에 항상 `trace_id`를 함께 남기면, Loki 로그 한 줄에서 Tempo trace로 점프(derived field)합니다.
- **트레이스 → 로그**: Tempo의 trace에서 해당 span 시간대 Loki 로그로 역방향 점프.
- 따라서 §4.2의 구조화 로그 예시에는 **항상 `trace_id`/`span_id` 필드를 포함**시키는 것이 좋습니다.

**경보 설계 원칙 (RED / USE)**:
- **RED**(요청 기반 서비스): **R**ate(요청량) · **E**rrors(에러율) · **D**uration(지연). Gateway·Nakama 메타 같은 요청-응답 계층에 적합.
- **USE**(리소스 기반): **U**tilization · **S**aturation · **E**rrors. CPU/RAM/goroutine·tick 큐 같은 zone 서버 자원에 적합.
- 알람은 **증상(p99 tick·에러율) 기준**으로 걸고, 원인(CPU 등)은 대시보드로 파고드는 순서가 알람 피로를 줄입니다.

> 시니어 코멘트: 웹 운영의 SLO/에러버짓 개념이 그대로 적용됩니다. 다만 게임은 "**전투 중 1초 끊김**"이 평균 지연 그래프엔 안 보이고 사용자 체감엔 치명적이므로, **평균이 아니라 p99/p999와 짧은 윈도우(예: 1초 tick 분포)**를 봐야 합니다.

---

## 5. 분석 (Analytics)

### 5.1 핵심 지표
- **DAU/MAU** (Daily/Monthly Active Users)
- **Retention**: D1, D7, D30
- **ARPU/ARPPU**: 매출 / 결제 사용자
- **Session length / 빈도**

### 5.2 게임 특화
- **Funnel**: 회원가입 → 캐릭터 생성 → 튜토리얼 → 첫 사냥 → 첫 결제
- **Level distribution**: 어디서 사용자가 멈추는가
- **PvP/PvE rate**: 콘텐츠 소비 패턴
- **Item economy**: 아이템 가격 인플레이션, 골드 sink

### 5.3 도구
- 자체 (PostgreSQL + dbt + Metabase)
- Firebase Analytics, GameAnalytics
- BigQuery + Looker

### 5.4 절대 추적해야 할 것
```
event: login, logout, level_up, item_get, item_use,
       purchase, death, quest_complete, error_*
```

---

## 6. 백오피스 / GM 도구

### 6.1 필수 기능
- 계정 검색 / 차단 / 해제
- 캐릭터 상태 조회 (위치, 인벤토리)
- 아이템 지급 / 회수 (감사 로그 필수)
- 채팅 로그 검색 (신고 처리)
- 우편 발송 (전체, 개별)

### 6.2 보안
- GM 행동 모두 로그
- 2FA, IP 제한
- 권한 분리 (관전 / GM / 슈퍼)

### 6.3 도구
- 자체 (Vue/React + REST)
- 또는 Retool / Forest Admin 같은 SaaS

---

## 7. 보안 / 어뷰징 대응

### 7.1 안티치트 (모바일 MMO 기준, 2025~2026 표준 3중 레이어)

2025년 모바일 MMO 안티치트의 업계 표준은 **3중 레이어**입니다.

1. **Platform Attestation** — Android **Google Play Integrity API** + iOS **Apple App Attest**. 디바이스/앱 무결성을 OS가 서명한 토큰으로 증명. 클라가 루팅/잠금해제/리패키징됐는지 서버에서 검증. (구버전의 **SafetyNet Attestation API는 2025-01 완전 종료**되어, Android 측은 이제 Play Integrity API로 일원화됨. 자세한 verdict 해석은 §7.1.1 참고.)
2. **Server-side ML 행동 분석** — BotDetect, Anybrain 같은 서비스 또는 자체 ML. 입력 패턴, 행동 분포, 거래 패턴을 학습된 모델로 이상 탐지.
3. **Server Authority** — Phase 5에서 이미 구축. 클라이언트 입력을 의도로만 받아 서버가 시뮬레이션·룰 판정.

권장 도입 순서: Server Authority(필수) → Platform Attestation(출시 전) → ML 분석(운영 안정 후).

- 패킷 검증:
  - dt 비정상 (0.5초마다 한 번에 이동) → 거부
  - 이동 속도 한계 초과 → 거부 + 로그
  - 공격 쿨다운 위반 → 거부
- IP rate limit
- 의심 행동 → 자동 flag → GM 검토
- 사례: Bungie의 [Marathon: Networking and Security](https://www.bungie.net/7/en/News/Article/marathonsecurity) 공식 글(**2026-02-22** 게시)은 **서버 권위 중심 anti-cheat의 콘솔/PC 공개 사례**입니다. (Marathon은 PC/PlayStation 5/Xbox Series용 익스트랙션 슈터이며 **모바일 게임이 아닙니다** — '모바일/콘솔 통합 사례'라는 표현은 부정확합니다.) 핵심 구성: **풀-오소리티 전용 서버**(모든 판정을 서버가 수행) + **서버측 Fog of War**(클라에 보이지 않는 적 정보를 아예 전송하지 않아 월핵·ESP 무력화) + 자체 보안 스택 + **BattlEye** + 영구밴 정책. 2026-04 시점에 detection tool 개선이 라이브로 추가되었습니다.
  - 시니어 코멘트: 모바일 MMO에 그대로 옮길 수 없는 콘솔/PC 전용 기법(커널 안티치트 등)도 섞여 있지만, **"보이면 안 되는 정보는 애초에 클라로 보내지 않는다"(서버측 Fog of War)** 원칙은 §6.4(Interest Management)와 직결되는, 우리 코스에서 바로 차용할 만한 교훈입니다.
- 출처: https://developer.android.com/google/play/integrity/verdicts · https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service · https://www.bungie.net/7/en/News/Article/marathonsecurity

#### 7.1.1 Google Play Integrity API verdict 해석 (2026-05 현행)

Play Integrity API 응답은 서버가 해석해야 하는 여러 **verdict 필드**로 구성됩니다. 핵심은 다음 세 가지입니다.

- **`deviceIntegrity`** — 기기·OS 무결성 신호. 라벨 의미:
  - `MEETS_DEVICE_INTEGRITY`: Google Play 서비스가 있는 정상 인증 기기.
  - `MEETS_BASIC_INTEGRITY`: 기본 신뢰만 충족(에뮬레이터·일부 변조 가능성).
  - `MEETS_STRONG_INTEGRITY`: 하드웨어 기반 신호 + **최근 1년 내 보안 패치**까지 충족한 가장 강한 등급.
- **`appIntegrity`** — 설치된 앱이 Play 스토어에서 받은 정품(`PLAY_RECOGNIZED`)인지, 리패키징·미인식(`UNRECOGNIZED_VERSION`)인지.
- **`accountDetails`** — 해당 앱에 대한 라이선스(`LICENSED` / `UNLICENSED`) 여부.

> **2025-05 verdict 강화**: Android 13(API 33)+ 기기에서는 강화된 device verdict가 전 앱에 자동 적용됩니다. `MEETS_STRONG_INTEGRITY`가 '최근 1년 내 보안 패치'를 요구하고, device verdict가 하드웨어 기반 신호를 사용하도록 바뀌었습니다.

선택적으로 켤 수 있는 보조 신호도 있습니다: `playProtectVerdict`(Google Play Protect 상태), `appAccessRiskVerdict`(화면 캡처·접근성 악용 등 런타임 위험), `recentDeviceActivity`(최근 무결성 토큰 발급 빈도 — 토큰 farming 탐지), `deviceRecall`(기기 단위 재사용 추적).

라이브러리 측면에서는 **Play Integrity library 1.5.0(2025-08)**에서 `GET_INTEGRITY` / `GET_STRONG_INTEGRITY` **remediation dialog**(무결성 미달 시 사용자에게 복구 안내를 띄우는 `showDialog`)가 추가되었습니다.

> 시니어 코멘트: verdict는 **불리언이 아니라 점수형 신호**로 다루세요. `MEETS_STRONG_INTEGRITY` 미달이라고 즉시 차단하면 정상 사용자(구형 기기·커스텀 ROM)를 대량 이탈시킵니다. **고가치 행동(결제, 거래, 랭킹 제출)에만 strong 요구**하고, 일반 플레이는 basic 통과 + 행동 분석(§7.1.2/§7.2)으로 보완하는 단계적 정책이 안전합니다.

출처: https://developer.android.com/google/play/integrity/verdicts

#### 7.1.2 Apple App Attest 서버 구현 함정 (2026-05 현행)

App Attest는 **iOS 14에서 DeviceCheck 프레임워크의 일부로 도입**되었습니다. 클라가 생성한 attestation/assertion을 서버가 Apple 인증 체인으로 검증해 "이 요청이 정품 앱·정품 기기에서 왔다"를 보장합니다. 서버 구현 시 흔히 빠지는 함정:

- **nonce 재생(replay) 공격** — attestation/assertion 검증에 쓰는 nonce(서버가 발급한 랜덤 챌린지)의 **일회성(one-time)과 시간창(time window)을 엄격히 강제**하지 않으면, 공격자가 한 번 캡처한 유효 attestation을 반복 제출해 우회할 수 있습니다. → 서버는 **요청마다 새 nonce 발급 + 짧은 만료 + 사용 후 폐기(소비 처리)**를 반드시 강제해야 합니다.
- **fraud bit의 한계** — DeviceCheck의 fraud bit는 앱 재설치·재계정 후에도 기기 단위로 상태가 유지되지만 **2비트(상태 4종)**라 표현력이 매우 낮습니다. 단독 차단 근거로 쓰지 말고 **ML 행동 분석(§7.2)을 보완 레이어**로 두세요.

> 출처(현행 경로): [서버 검증](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server) · [App Attest 준비](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service) · [사기 위험 평가](https://developer.apple.com/documentation/devicecheck/assessing-fraud-risk) — 과거 `establishing_your_app_s_integrity` 경로는 문서 재구성으로 더 이상 유효하지 않습니다.

### 7.2 매크로 / 봇
- 입력 패턴 분석 (완전 등간격 = 봇)
- 행동 분포 (24시간 사냥)
- 캡차 (이상 행동 시)

### 7.3 결제 보안

대원칙은 변하지 않습니다: **클라이언트가 "결제 완료"라고 보낸 것은 절대 믿지 말 것.** 검증은 항상 서버가 스토어 API와 직접 통신해 수행합니다. 다만 **양 스토어 모두 검증 방식이 신형 API로 전환**되어, 2026 기준 권장 구성이 과거(영수증 문자열 검증)와 다릅니다.

**App Store (iOS) — 신형 서버 API로 전환**:
- **레거시 `verifyReceipt` 엔드포인트와 App Store Server Notifications v1은 deprecated**입니다(신규 기능 없음, EOL 미정). 영수증 문자열을 통째로 검증 서버에 POST하던 옛 방식은 더 이상 권장되지 않습니다.
- 현행 권장: **App Store Server API** + **App Store Server Notifications V2** + **App Store Server Library**(공식). 클라가 보낸 `transactionId`로 서버가 Apple에서 **Apple-signed `Transaction` / `AppTransaction`(JWS 형식)**을 받아 **서버에서 서명을 검증**합니다. 환불·구독 갱신·만료 등 상태 변화는 Notifications V2(서버 푸시)로 비동기 수신.
- 출처: https://developer.apple.com/documentation/appstoreserverapi · (deprecated 안내: https://developer.apple.com/documentation/appstorereceipts/verify-receipt )

**Google Play (Android) — 3종 조합이 현행 표준**:
1. **RTDN(Real-time Developer Notifications)** — Google Cloud **Pub/Sub** 토픽으로 entitlement **변경 알림만** 전달합니다. 알림 자체에는 상세 상태가 없으므로 **이것만 신뢰하면 안 됩니다**.
2. **Google Play Developer API** — RTDN을 받으면 반드시 `purchases.products` / `purchases.subscriptionsv2`를 호출해 **권위 상태를 재조회**합니다.
3. **Voided Purchases API** — 환불·취소·차지백으로 회수해야 할 구매를 별도로 보강 폴링합니다.
- 즉 **RTDN(알림) + Developer API(재조회) + Voided Purchases(회수)** 3종을 함께 써야 누락·우회 없이 entitlement를 관리할 수 있습니다.
- 출처: https://developer.android.com/google/play/billing/rtdn-reference

> 시니어 코멘트: 게임은 결제 → 재화 지급이 **즉시·되돌리기 어려운** 액션이라 영수증 검증 실패/재생/환불 처리가 곧 자산 사고입니다. **(a) 멱등키(orderId/transactionId)로 중복 지급 방지, (b) 지급은 검증 성공 이후, (c) 환불 웹훅으로 재화 회수**를 백오피스(§6) 감사 로그와 묶어 두세요. §12.4의 "Server Authority가 본질" 원칙이 결제에도 그대로 적용됩니다.

---

## 8. A/B 테스트 / Feature Flag

```go
if feature.Enabled("new_skill_balance", userID) {
    // 새 밸런스 적용
}
```

도구: LaunchDarkly, Unleash, 자체 구현.

게임 특화:
- 사용자 단위 A/B (UI, 보상, UX)
- 서버 단위 (밸런스 패치 일부 zone에만)

### 8.1 두 가지를 구분: Feature Flag vs A/B 실험

같은 도구로 구현되지만 목적이 다릅니다.
- **Feature Flag(운영 안전장치)** — "켜고 끄는" 스위치. 점진 출시(percentage rollout), **kill switch**(문제 발생 시 재배포 없이 즉시 비활성), 점검 모드(§3.3) 토글이 본질. 운영자 보호용.
- **A/B 실험(의사결정)** — 두 변형(A/B)을 통계적으로 비교해 **무엇이 더 좋은지 측정**. 사용자를 일관 버킷으로 나누고, §5의 지표(retention·ARPU·funnel)로 결과를 판정.

### 8.2 게임 특유의 함정

- **stateful 서버에서의 일관성** — flag를 런타임에 토글하면 같은 zone의 플레이어가 서로 다른 룰로 시뮬레이션될 수 있습니다. 전투/밸런스에 영향을 주는 flag는 **존 단위·매치 단위로 고정(스냅샷)**해서 한 전투 안에서는 값이 바뀌지 않게 하세요.
- **버킷팅 안정성** — `userID` 해시 기반으로 버킷을 정하면 세션·기기가 바뀌어도 **같은 사용자는 항상 같은 그룹**에 들어갑니다(sticky bucketing). 로그인할 때마다 그룹이 바뀌면 실험이 오염됩니다.
- **밸런스 A/B의 경제 오염** — 아이템 가격·드롭률 같은 **공유 경제(item economy, §5.2)**에 A/B를 걸면 두 그룹이 같은 거래소를 통해 섞여 실험이 깨집니다. 경제에 영향을 주는 실험은 **서버(샤드)/거래소 단위로 격리**해야 합니다.
- **공정성 인식** — PvP 보상·확률을 사용자별로 A/B하면 "차별" 논란이 생깁니다. 민감한 항목은 사용자 단위가 아니라 **시즌·서버 단위**로 돌리는 편이 안전합니다.

> 시니어 코멘트: 웹의 feature flag 경험은 거의 그대로 옵니다. 차이는 "**한 전투 안에서 룰이 흔들리면 안 된다**"(stateful 일관성)와 "**A/B가 공유 경제를 오염시킨다**"는 두 가지뿐입니다. 신규 밸런스는 §3.2의 zone 단위 배포와 묶어 **일부 zone에 먼저 적용 → 지표 확인 → 전체 확대** 순서로 가세요.

---

## 9. 장애 대응 플레이북

### 9.1 사전 준비
- on-call 로테이션
- Runbook (장애별 대응 절차)
- 비상 연락망

### 9.2 흔한 시나리오
| 장애 | 즉시 대응 | 사후 |
|---|---|---|
| Zone 서버 다운 | 자동 재시작 (k8s) + 백오피스로 사용자 안내 | RCA, 로그 분석 |
| DB 마스터 다운 | replica failover | DB scale-up, 백업 검증 |
| 인증 서버 다운 | 점검 모드 | 분산 처리 |
| DDoS | CloudFlare / WAF | 결제 방어 우선 |
| 핵 발견 | 핫픽스 또는 일시 비활성 | 보상, 사후 보고 |

### 9.3 사후 (Post-mortem)
- Blameless 원칙
- Timeline + Root cause + Action items

---

## 10. CI/CD

### 10.1 클라이언트
```
push → CI (test) → flutter build apk/ipa → Firebase App Distribution (QA) → store
```

### 10.2 서버
```
push → CI (test) → docker build → registry → ArgoCD / k8s rolling
```

### 10.3 데이터 패치
```
JSON 변경 → CI 검증 (스키마, 밸런스 sanity) → CDN 업로드 → 클라 다음 로딩 시 적용
```

---

## 11. 실습 — Live Ops 미니 셋업

### 11.1 최소 운영 환경
- Prometheus + Grafana (서버 메트릭)
- Loki + Promtail (로그)
- Sentry (클라 에러)
- 자체 GM 페이지 (React + REST)
- Slack webhook (알람)

### 11.2 시나리오 시뮬레이션
- [ ] 가짜 장애 일으키고 알람 도착 확인
- [ ] 봇 30개 띄워서 대시보드 보기
- [ ] 클라이언트 핫픽스 데이터 (JSON) 교체 시 자동 반영
- [ ] GM이 캐릭터 위치 강제 변경 → 동작 확인

---

## 12. 시니어가 빠지기 쉬운 함정

### 12.1 "모니터링 나중에"
- 출시 후 사고 나면 원인 파악 불가. **첫 출시 전 필수**.

### 12.2 "GM 도구는 SQL로 충분"
- 사고 납니다. 누군가 prod DB에서 실수로 UPDATE. 백오피스 + 감사 로그 필수.

### 12.3 "보상 우편을 수동으로"
- 작업 실수 = 자산 손실. 도구 + 워크플로우(승인) 필수.

### 12.4 "안티치트 = 패킷 암호화"
- 클라 코드는 어차피 디컴파일됨. Server Authority가 본질.

### 12.5 "패치 = 점검 + 재시작"
- 잦은 점검은 이탈 유발. Stateful drain 패턴 학습.

### 12.6 "데이터 분석은 출시 후"
- 출시 전부터 이벤트 트래킹 코드를 박아둬야 비교가 가능. 일관된 스키마.

### 12.7 "오픈 직후 트래픽 견디면 끝"
- 첫 1주 ≠ 30일 retention. 콘텐츠 소비 속도 측정해서 다음 패치 일정.

---

## 13. 학습 자료

- "Site Reliability Engineering" (Google) — 무료, 시니어가 보지 않았다면 필독
- "Designing Data-Intensive Applications" — 게임 백엔드에도 적용
- GDC vault: "Live Ops" 검색
- AWS GameTech Blog
- Game Server Programming Patterns

**안티치트 / 무결성 (2026 현행)**:
- [Google Play Integrity API verdict 레퍼런스](https://developer.android.com/google/play/integrity/verdicts)
- [Apple App Attest 준비](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service) · [서버 검증](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server) · [사기 위험 평가](https://developer.apple.com/documentation/devicecheck/assessing-fraud-risk)
- [Bungie — Marathon: Networking and Security](https://www.bungie.net/7/en/News/Article/marathonsecurity) (서버 권위 + 서버측 Fog of War 사례, 2026-02)

**결제 검증 (2026 현행)**:
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) (레거시 verifyReceipt 대체)
- [Google Play RTDN 레퍼런스](https://developer.android.com/google/play/billing/rtdn-reference) (+ Developer API / Voided Purchases API)

**관측 (Observability)**:
- [OpenTelemetry 공식 문서](https://opentelemetry.io/docs/) — trace context 전파·OTLP 표준
- [Grafana LGTM 스택](https://grafana.com/docs/) — Loki(로그) · Grafana · Tempo(트레이스) · (Prometheus/Mimir 메트릭) 통합 correlation

---

## 14. 학습 후 메모 (직접 작성)

- 운영 도구 셋업에서 가장 시간을 쓴 부분:
- 사고 시뮬레이션으로 깨달은 부족한 점:
- 다음 단계 운영 자동화 우선순위:

---

## 15. 마무리

본 코스 8개 Phase를 모두 마치면, 당신은:
- 2.5D Isometric Open World MMORPG의 **클라이언트 전체**를 직접 만들 수 있고,
- Server Authority + Interest Management + Zone Server 의 **서버를 설계·구현**할 수 있고,
- 100명 동시 접속 환경에서 **운영**할 수 있는 토대를 갖춥니다.

이후의 방향은 게임 디자인(콘텐츠, 밸런스), 비즈니스(BM, 마케팅), 또는 더 깊은 엔지니어링(자체 엔진, 3D 전환)으로 나뉩니다.

> **시니어로서 가장 강력한 자산**: 40년의 시스템 설계 경험. 게임 도메인 4~5개월 학습으로 충분히 합쳐집니다. 가장 어려운 것은 **점진 구축의 인내** — 처음부터 완벽한 MMORPG를 설계하려는 유혹을 이겨내세요.

---

## 16. 추가 참고

- [server-architecture.md](./server-architecture.md) — 서버 아키텍처 심화 (시니어용)
- [resources.md](./resources.md) — 전체 학습 자료 모음
- 최신 운영/관측 출처: [resources.md §0.3](./resources.md)
