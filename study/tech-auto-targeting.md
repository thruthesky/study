# 기술 분석 — 드래그 경로 기반 자동·순차 몬스터 공격

**한 줄 요약**: 화면을 드래그해 그린 경로(줄) 주위의 몬스터들을, 한 마리씩 번갈아
자동 공격하고 죽으면 다음 마리로 넘어가는 메커니즘을 Flame(1.37.0)에서 어떻게
구현할 수 있는지 분석한다. (멀티 에이전트 조사 + Flame 공식 문서/소스 적대적 검증 기반)

> 이 문서는 **구현 가능성과 설계 분석**이다. 실제 코드는 아직 작성하지 않았다.
> 선행 기초(몬스터·충돌·전투)는 [02-phase2-2d-action.md](02-phase2-2d-action.md),
> 입력·클릭이동 기초는 [cheat-sheet.md](cheat-sheet.md) §5.4·§5.10을 참고.

---

## 0. 결론

요청 메커니즘 — ① 드래그 경로 주위 몬스터 자동 탐색, ② 한 마리씩 번갈아 공격,
③ 죽으면 다음으로 — 은 **세 가지 모두 구현 가능**하다. 이는 "**드래그 타게팅 +
오토배틀러(auto-targeting)**"라는 잘 알려진 조합이며, Flame이 필요한 빌딩블록을 대부분
제공한다. **단 한 곳, "경로 주위 영역 일괄 수집"만** 코어 기성 API가 없어 직접 구현
(또는 외부 패키지)이 필요하다.

```text
[드래그 제스처]                [경로 주위 몬스터]              [순차 자동 공격]
 onDragStart                   각 몬스터 ↔ 경로 최단거리        타겟 큐[0] 공격
 onDragUpdate(연속) → 점 누적 → ≤ 임계값이면 후보에 수집   →  쿨다운마다 1회
 onDragEnd          = 폴리라인  (거리/경로순 정렬)              죽으면 큐에서 제거 → 다음
   ①단계                          ②단계                          ③단계
```

---

## 1. ①단계 — 드래그 경로 수집 (난이도: 낮음)

`DragCallbacks` mixin이 정확히 이 일을 한다.

- 콜백 **4개**: `onDragStart` / `onDragUpdate` / `onDragEnd` / `onDragCancel`.
- **`onDragUpdate`는 포인터가 움직이는 동안 연속 호출**된다. 그때마다 좌표를 리스트에
  누적하면 **시작점 → 중간점들 → 끝점**의 폴리라인(꺾은선)이 만들어진다. 이것이
  "줄을 긋듯이"의 그 줄이다.
- 붙이는 곳은 클릭-투-무브와 같이 **`World`** 가 자연스럽다(좌표가 월드 좌표로 들어옴,
  [cheat-sheet.md](cheat-sheet.md) §5.10 참고).

### 함정 (검증으로 확인)

- 좌표는 **신 API `localStartPosition` / `localEndPosition` / `localDelta`** 를 쓴다.
  구식 `localPosition` / `delta` / `canvasPosition` / `devicePosition`은 **deprecated**.
- ⚠️ **포인터가 컴포넌트 영역 밖으로 나가면 `localPosition`이 `NaN`** 을 반환한다.
  경로 누적 시 **NaN 가드**가 필요하다.
- `World`에 붙이면 보통 월드 좌표지만, **자체 `position`/`scale`/`angle`을 가진 자식**에
  붙이면 그 컴포넌트 로컬 좌표가 들어온다. 월드 좌표가 필요하면 부모/카메라 변환을
  별도 적용한다("World면 무조건 월드 좌표"는 변환이 없을 때만 성립).

---

## 2. ②단계 — 경로 주위 몬스터 탐색 (난이도: 중간, **직접 구현 필요**)

여기가 **유일하게 코어 기성 API가 없는** 지점이다. 검증으로 확인한 도구 지형:

| 하고 싶은 것 | Flame 코어 제공 | 방법 |
|---|---|---|
| 특정 **점** 아래 컴포넌트 | ✅ `world.componentsAtPoint(p)` | `containsLocalPoint()`를 구현한 컴포넌트만 반환(`PositionComponent`는 기본 제공) |
| 두 객체 **거리** | ✅ `position.distanceTo(other)` / `PositionComponent.distance(other)` | 직접 거리 계산 |
| **반경/영역 일괄 수집** | ❌ **기성 표준 API 없음** | 몬스터를 순회하며 거리 임계값으로 직접 필터 |
| **선분(광선) 관통** | ✅ `raycast`/`raycastAll`(`maxDistance`,`ignoreHitboxes`) | 단 **CollisionDetection에 등록된 hitbox** 대상 |

→ **"드래그 폴리라인 주위 일정 거리 내 몬스터"** 전용 API는 없다. 정석은 **각 몬스터에서
드래그 폴리라인(여러 선분)까지의 최단거리(점-선분 거리)를 계산해 임계값 이하만 후보로
거르는** 것이다. 점-선분 거리 공식은 단순하다.

### 세 가지 구현 선택지

1. **거리 필터 직접 구현** (가장 단순) — `world.children.whereType<Monster>()`로 모아
   각자 폴리라인까지 거리를 재고 임계값으로 필터. 몬스터가 적을 때 충분.
2. **임시 hitbox + 충돌 콜백** — 드래그 경로를 따라 굵은 hitbox(캡슐/사각형)를 두고
   `onCollisionStart`로 겹친 몬스터를 수집. 이벤트 기반이라 깔끔.
3. **broadphase 패키지**(`flame_spatial_grid` 등) — 몬스터가 수백 마리로 많을 때.
   매 프레임 전수 순회를 공간 분할로 줄임.

> `raycast`는 "선을 따라 **가장 먼저 맞는** 하나(또는 정렬된 다수)"를 찾는 데 적합하고,
> "선 **주위 반경 내 전부**"를 모으는 것과는 다르다. 후자는 위 거리 필터가 맞다.

---

## 3. ③단계 — 순차 자동 공격 (난이도: 중간, 표준 패턴)

"한 마리씩 → 죽으면 다음"은 **타겟 큐 + 쿨다운 + 사망 전환**의 조합이며, 오토배틀러의
정석 구조다. (이 단계가 조사에서 가장 충실히 확보됨)

### (a) 타겟 큐 — "현재 타겟 단일 참조"와 "후보 리스트" 분리

②에서 수집한 몬스터를 정렬해 큐를 만들고 head를 현재 타겟으로 잡는다.

- 후보 수집: 거리순 정렬(`distanceTo`) **또는** 공격자에 원형 `CircleHitbox`를 붙이고
  `onCollisionStart`(추가)/`onCollisionEnd`(제거)로 **사정거리 안 후보 리스트를 이벤트로
  유지**(매 프레임 전수 순회 불필요).
- 우선순위는 `TargetMode` enum(가까운/먼/약한/강한)으로 **정렬 비교자만 교체**해 모드화.

### (b) 쿨다운 — 한 마리씩 일정 간격

- **`TimerComponent(period: 간격, repeat: true, onTick: 공격)`** — 선언적. 트리에
  `add`하면 Flame이 내부에서 `Timer.update(dt)`를 자동 호출. 타겟 없으면 `stop()`,
  생기면 `start()`.
- **`update(dt)` 누적**(`_cooldown += dt; if (_cooldown >= interval) {...}`) — 선딜/차지/
  애니메이션 동기화 등 상태가 얽힐 때 더 유연.

쿨다운 **1주기마다 현재 타겟 1체만** 때리므로 자연히 "한 마리씩 번갈아"가 된다.

### (c) 죽으면 다음으로 — 가장 주의할 함정

- 생존 확인 플래그: `isMounted` / `isRemoving` / `isRemoved` / `parent`.
- ⚠️ **`removeFromParent()`는 즉시가 아니라 "다음 틱" 제거(비동기)**. 죽은 그 프레임엔
  `isMounted`가 아직 `true`일 수 있다. → **죽음 판정은 `hp<=0` 즉시 플래그나 몬스터의
  `onRemove()` 콜백**으로 잡는 것이 안전.
- 타겟이 죽으면 `currentTarget = null`로 끊고(**dangling 참조 방지**) 큐에서 제거 후
  다음 head로 전환. 후보 리스트도 `removeWhere((e) => !e.isMounted)`로 주기적 청소.
- 연출까지: `SequenceEffect` 끝에 `RemoveEffect`를 넣어 "히트 연출 → 제거"를 한 번에.

### (d) 전체 제어 — 상태머신(FSM)

`Idle(타겟 없음) → Acquiring(탐색) → Attacking(공격 중) → Retargeting(타겟 소실)`.
재타게팅은 **"적 진입 / 적 이탈 / 모드 변경 / 현재 타겟 사망" 4시점**에만 이벤트로
재계산하고, 필요 시 0.2~0.5초 폴링으로 보정(타겟 고착 방지). "죽으면 다음"은
`Attacking ↔ Retargeting` 전이로 자연스럽게 표현된다.

---

## 4. 종합 — 난이도·작업량

| 단계 | 가능? | Flame이 제공 | 직접 구현 | 난이도 |
|---|---|---|---|---|
| ① 드래그 경로 수집 | ✅ | `DragCallbacks` 4콜백 | 점 누적 + NaN 가드 | 낮음 |
| ② 경로 주위 탐색 | ✅ | `distanceTo`/`raycast`/충돌 | **선분-점 거리 필터** | 중간 |
| ③ 순차 자동 공격 | ✅ | `TimerComponent`/충돌/라이프사이클 | 타겟 큐 + FSM | 중간 |

### 선행 조건

현재 [lib/main.dart](../lib/main.dart)에는 **몬스터·공격·충돌 시스템이 없다**(클릭-투-무브만
있음). 이 기능 전에 다음이 먼저 필요하다 — 이는 [02-phase2-2d-action.md](02-phase2-2d-action.md)
범위:

1. `Monster` 컴포넌트 + `hp`
2. `HasCollisionDetection` + `Hitbox`
3. 데미지/사망 처리

### 가장 큰 설계 결정 두 가지

1. **"경로 주위"의 정의** — 선분에서 몇 px 이내인가(공격 범위 폭). **게임 손맛을 좌우**한다.
2. **공격 순서** — 드래그한 **경로 순서**(그은 순서대로)인가, **거리순**인가? 질문의
   "번갈아"는 경로순이 직관적이다.

---

## 5. 출처 (공식 문서·API·소스로 검증)

- DragCallbacks / 드래그 이벤트 — https://docs.flame-engine.org/latest/flame/inputs/drag_events.html
- 충돌 감지 · raycast/raycastAll/raytrace · CollisionCallbacks — https://docs.flame-engine.org/latest/flame/collision_detection.html
- Component 라이프사이클(`isMounted`/`isRemoving`/`isRemoved`/`parent`, remove는 다음 틱) — https://pub.dev/documentation/flame/latest/components/Component-class.html , https://docs.flame-engine.org/latest/flame/components.html
- Timer / TimerComponent(`period`/`repeat`/`onTick`) — https://docs.flame-engine.org/latest/flame/other/util.html
- 트리 쿼리(`componentsAtPoint`, `children`, `descendants`) — https://pub.dev/documentation/flame/latest/components/World-class.html
- Effects(`SequenceEffect`/`RemoveEffect`) — https://docs.flame-engine.org/latest/flame/effects/

---

## 6. 관련 문서

- [02-phase2-2d-action.md](02-phase2-2d-action.md) — 몬스터·충돌·공격(선행 기초)
- [cheat-sheet.md](cheat-sheet.md) §5.4(입력)·§5.10(클릭-투-무브)·§5.9(priority/충돌 구분)
- [03-phase3-isometric-2.5d.md](03-phase3-isometric-2.5d.md) — y-sorting, 2.5D
- [game-glossary.md](game-glossary.md) — 충돌·hitbox·타게팅 용어
