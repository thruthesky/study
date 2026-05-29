# Phase 2 — 2D 액션 게임

> **기간**: 1.5주
> **목표**: 게임다운 게임을 만든다. Sprite 애니메이션, Collision, 간단한 AI, 전투, HP, 사망 처리를 구현한다.
> **산출물**: "2D RPG Battle Test" — 플레이어 1명 + 몬스터 N마리 + 공격 + HP 바 + death.

---

## 1. 학습 목표

- [ ] `SpriteAnimationGroupComponent`로 idle / walk / attack / hit / death 상태 표현 (enum 키 + `current` 전환)
- [ ] 상태 머신(FSM)으로 캐릭터/몬스터 행동 제어
- [ ] `World` 기반 `HasCollisionDetection` + `CollisionType`(active/passive/inactive) + Hitbox(`RectangleHitbox`, `CircleHitbox`)와 `CollisionCallbacks` 사용
- [ ] 투사체/시야용 `raycast` / `raytrace` API 이해
- [ ] 간단한 AI (Idle → Detect → Chase → Attack → Return)
- [ ] HP 시스템 + 데미지 + 사망 + 리스폰
- [ ] HUD (체력바, 점수)

---

## 2. 사전 지식 매핑

| 게임 개념 | 서버/웹 비유 |
|---|---|
| Finite State Machine | XState / 상태 다이어그램 — 단, 매 프레임 평가 |
| Collision Detection | DB 인덱스 충돌 검사 — 단, 공간 자료구조 위 |
| AI Tick | 백엔드 워커 폴링 — 단, 60Hz |
| Hitbox | API endpoint의 validation 영역 — 단, 좌표상 |

---

## 3. 핵심 개념

### 3.1 Finite State Machine (FSM)

캐릭터/몬스터는 항상 **단 하나의 상태**에 있습니다.

```
[Idle] --(target detected)--> [Chase]
[Chase] --(in attack range)--> [Attack]
[Chase] --(target lost)----->  [Idle]
[Attack] --(cooldown end)----> [Chase]
[*] --(hp <= 0)--> [Death]
```

코드:
```dart
enum MonsterState { idle, chase, attack, hit, death }

class Slime extends PositionComponent with CollisionCallbacks {
  MonsterState state = MonsterState.idle;
  double stateTime = 0;
  Player? target;

  @override
  void update(double dt) {
    super.update(dt);
    stateTime += dt;

    switch (state) {
      case MonsterState.idle:    _idle(dt);   break;
      case MonsterState.chase:   _chase(dt);  break;
      case MonsterState.attack:  _attack(dt); break;
      case MonsterState.hit:     _hit(dt);    break;
      case MonsterState.death:   _death(dt);  break;
    }
  }

  void _setState(MonsterState s) {
    if (state == s) return;
    state = s;
    stateTime = 0;
    // 애니메이션 교체 등 진입 액션 (3.2에서 current = s로 구체화)
  }
}
```

> 위 골격은 FSM 로직만 보여줍니다. 실제 `Slime`은 **3.2처럼 `SpriteAnimationGroupComponent<MonsterState>`를 상속**해 상태 enum을 표시 애니메이션의 키로 직접 재사용하는 것이 권장 구조입니다. 그러면 `_setState()` 안의 "진입 액션"이 곧 `current = s` 한 줄이 됩니다.

### 3.2 SpriteAnimation 상태별 교체 — `SpriteAnimationGroupComponent`

상태마다 `SpriteAnimationComponent`를 트리에 add/remove하는 수동 방식(아래 "구식 패턴" 참고)은 매 전환마다 컴포넌트 라이프사이클(`onMount`/`onRemove`)을 다시 타서 비효율적입니다. Flame은 이 용도로 **`SpriteAnimationGroupComponent<T>`** 전용 컴포넌트를 제공하며, 이것이 2026-05 기준 권장 패턴입니다.

```dart
// FSM의 enum을 그대로 제네릭 키로 사용 → 타입 안전한 상태↔애니메이션 매핑
class Slime extends SpriteAnimationGroupComponent<MonsterState>
    with HasGameReference<MyGame>, CollisionCallbacks {

  @override
  Future<void> onLoad() async {
    animations = {
      MonsterState.idle:
          await game.loadSpriteAnimation('slime_idle.png',
              SpriteAnimationData.sequenced(amount: 4, stepTime: 0.2, textureSize: Vector2.all(32))),
      MonsterState.chase:
          await game.loadSpriteAnimation('slime_walk.png',
              SpriteAnimationData.sequenced(amount: 6, stepTime: 0.1, textureSize: Vector2.all(32))),
      // attack은 1회 재생(loop: false) — 끝나면 FSM이 다음 상태로 보냄
      MonsterState.attack:
          await game.loadSpriteAnimation('slime_attack.png',
              SpriteAnimationData.sequenced(
                  amount: 5, stepTime: 0.08, textureSize: Vector2.all(32), loop: false)),
    };
    current = MonsterState.idle;        // ★ current setter 하나로 교체 완료

    add(RectangleHitbox());
  }
}
```

`current`에 enum 값을 대입하는 것만으로 표시 애니메이션이 바뀝니다. 트리 조작이 없어 GC 압력도 없습니다.

**1회성 애니메이션(attack/hit/death)의 완료 감지** — `animationTickers` 맵으로 각 상태의 `SpriteAnimationTicker`에 접근해 콜백을 겁니다. 공식 API상 ticker에는 `void Function()? onComplete`, `void Function()? onStart`, `void Function(int currentIndex)? onFrame` 콜백과 `reset()`/`done()` 메서드, 그리고 `Future<void> get completed`가 있습니다.

```dart
// onLoad 끝에서 한 번만 등록
animationTickers![MonsterState.attack]!
  ..onStart = () => _spawnAttackHitbox()          // active 프레임에서 판정 생성
  ..onComplete = () => _setState(MonsterState.chase);  // 후딜 종료 → 복귀

void _setState(MonsterState s) {
  if (state == s) return;
  state = s;
  stateTime = 0;
  current = s;                                    // FSM 상태 = 표시 애니메이션
  // loop:false 애니메이션을 다시 재생하려면 ticker를 reset()
  animationTickers?[s]?.reset();
}
```

> 패턴: **FSM `_setState()` → `current = s`**. attack처럼 끝나야 하는 동작은 `onComplete`(또는 `await animationTickers![s]!.completed`)로 다음 상태 전이 시점을 잡습니다. 함정 6.6("애니 끝나기 전 상태 진입")이 구조적으로 사라집니다.

<details><summary>구식 패턴(수동 add/remove) — 레거시 참고용</summary>

```dart
// SpriteAnimationGroupComponent 도입 이전에 쓰던 방식. 신규 코드에는 비권장.
class AnimatedActor extends PositionComponent {
  final Map<String, SpriteAnimationComponent> anims = {};
  String current = 'idle';

  void play(String name) {
    if (current == name) return;
    anims[current]?.removeFromParent();
    current = name;
    add(anims[name]!);
  }
}
```
</details>

### 3.3 캐릭터/몬스터를 멋지게 만드는 액션 타이밍

화려한 전투는 고해상도 그림보다 **타이밍과 피드백**에서 나옵니다. 모든 공격과 스킬은 아래 3단계를 가져야 합니다.

| 단계 | 의미 | 구현 포인트 |
|---|---|---|
| Windup | 공격 전 준비 동작 | 몸을 뒤로 빼거나 무기를 들어 "곧 맞는다"를 보여줌 |
| Active | 실제 판정 프레임 | hitbox 생성, 서버 authoritative 판정과 맞춰야 함 |
| Recovery | 공격 후 후딜 | 다음 입력 가능 시점, cancel 가능 여부를 명확히 |

```dart
class AttackTimeline {
  final double windup;
  final double active;
  final double recovery;
  final int damageFrame;
}
```

몬스터/캐릭터 품질을 올리는 최소 장치:

- **Silhouette**: zoom out에서도 직업/몬스터 종류가 읽혀야 합니다.
- **Anticipation**: 공격 직전 2~4프레임의 준비 동작을 반드시 둡니다.
- **Hit-stop**: 타격 순간 40~80ms 정도 공격자/피격자 애니메이션을 멈춰 충격을 줍니다.
- **Screen shake**: `flame_noise`를 카메라에 짧게 적용합니다. 보스/크리티컬만 강하게.
- **Afterimage / trail**: 돌진, 대시, 빠른 베기에는 별도 이펙트 sprite를 0.1~0.2초만 남깁니다.
- **Damage number**: 숫자는 Flame component로 pool 재사용. 매 타격마다 Flutter Widget 생성 금지.
- **SFX sync**: 사운드는 active frame 또는 impact frame에 맞춥니다.
- **Telegraph**: 보스/정예 몬스터는 공격 범위를 바닥에 먼저 표시합니다.

```dart
void triggerImpactFeedback({required bool critical}) {
  game.camera.viewfinder.add(
    MoveEffect.by(
      critical ? Vector2(8, 0) : Vector2(4, 0),
      NoiseEffectController(duration: critical ? 0.16 : 0.08),
    ),
  );
  spawnDamageText(critical ? DamageTextStyle.critical : DamageTextStyle.normal);
  audioPool.play();
}
```

> 멀티플레이 이후에는 **이펙트와 애니메이션은 클라이언트가 즉시 재생**하지만, 실제 데미지/넉백/사망 판정은 Go Zone Server의 결과를 따릅니다.

### 3.4 Collision (flame 1.x, 2026-05 권장 패턴)

```dart
class MyWorld extends World with HasCollisionDetection { ... }  // ★ 2026-05 권장
class MyGame extends FlameGame { /* world: MyWorld() */ }

class Player extends PositionComponent with CollisionCallbacks {
  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());           // 본인 크기 기반
    // 또는 add(CircleHitbox(radius: 20)..position = Vector2(...));
  }

  @override
  void onCollisionStart(Set<Vector2> pts, PositionComponent other) {
    if (other is Monster) { ... }
  }
}
```

핵심:
- `HasCollisionDetection` mixin을 **`World`에 부여** (Flame 공식 docs 최신 권장). `FlameGame`에 직접 부여하던 기존 패턴도 동작은 하지만, `CameraComponent` + `World` 구조에서는 World 단위 부여가 권장됨. 규칙: **히트박스는 가장 가까운 `HasCollisionDetection` 부모의 충돌 시스템에만 연결**되므로, 게임 객체를 모두 World 아래에 두면 World의 시스템 하나로 일관 처리됩니다.
- `CollisionCallbacks` mixin을 Component에 추가
- `Hitbox`를 자식으로 추가 (Rectangle / Circle / Polygon)
- 콜백 시그니처(주의: `onCollisionEnd`만 교점 인자가 없음):
  - `void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other)`
  - `void onCollision(Set<Vector2> intersectionPoints, PositionComponent other)`
  - `void onCollisionEnd(PositionComponent other)`
- 출처: https://docs.flame-engine.org/latest/flame/collision_detection.html

#### CollisionType — 충돌 비용을 결정하는 3-상태

모든 `Hitbox`는 `collisionType`을 가지며, **이 조합이 N×N 검사량을 좌우**합니다(함정 6.5와 직결).

| `CollisionType` | 충돌 검사 대상 | 용도 |
|---|---|---|
| `active` (기본값) | 다른 `active` **및** `passive` 모두와 검사 | 플레이어, 몬스터처럼 능동적으로 움직이며 부딪히는 주체 |
| `passive` | `active`와만 검사 (`passive`끼리는 **검사 안 함**) | 벽, 함정, 공격 판정 영역 등 "맞기만 하는" 대상 |
| `inactive` | 어떤 것과도 검사 안 함 | 일시 비활성(사망 연출 중, 무적 프레임 등) |

비용 핵심: **`passive`는 `active`하고만 비교**되므로, 정적/수동 객체를 `passive`로 두면 자기들끼리의 불필요한 비교가 사라집니다. 벽 50개를 모두 `active`로 두면 벽끼리도 비교하지만, `passive`면 플레이어/몬스터(active)와만 비교합니다. 무적 프레임 동안엔 히트박스를 제거하지 말고 `collisionType = CollisionType.inactive`로 토글하세요(컴포넌트 재생성 비용 회피).

```dart
add(RectangleHitbox()..collisionType = CollisionType.passive); // 벽/공격판정
```

#### Hitbox 그룹핑(충돌 필터링) — `onComponentTypeCheck`

"아군 공격은 아군에게 안 맞게", "투사체는 벽과 적에만" 같은 **충돌 그룹 필터링**은 `ShapeHitbox.onComponentTypeCheck`를 오버라이드해 구현합니다. `false`를 반환하면 그 쌍은 충돌 후보에서 제외됩니다.

```dart
class EnemyAttackHitbox extends RectangleHitbox {
  @override
  bool onComponentTypeCheck(PositionComponent other) {
    // 적의 공격은 플레이어에게만 — 다른 적/투사체와는 검사 생략
    if (other is Monster) return false;
    return super.onComponentTypeCheck(other);
  }
}
```

> 주의: `onComponentTypeCheck` 결과는 **캐시**됩니다. HP·상태 같은 동적 값으로 판단하면 안 되고, **타입(그룹) 기반 순수 판정**에만 쓰세요. 동적 조건은 `onCollisionStart` 안에서 거르십시오.

#### 정적 객체가 많을 때 — `HasQuadTreeCollisionDetection`

선형(브로드페이즈 없는) 검사 대신 쿼드트리를 쓰려면 `World`(또는 게임)에 `HasQuadTreeCollisionDetection`을 부여하고 `onLoad`에서 초기화합니다.

```dart
class MyWorld extends World with HasQuadTreeCollisionDetection {
  @override
  Future<void> onLoad() async {
    initializeCollisionDetection(
      mapDimensions: const Rect.fromLTWH(0, 0, 4096, 4096),
      minimumDistance: 10,   // 이 거리 미만이면 같은 셀로 간주
      // maxObjects: 25(기본), maxDepth: 10(기본)
    );
  }
}
```

본 Phase의 몬스터 수십 마리 규모에서는 기본 선형 검사로 충분합니다. 쿼드트리는 Phase 7 최적화에서 정적 타일/장애물이 수백~수천 개로 늘 때 도입합니다.

> Forge2D는 강체 물리(중력, 마찰)가 필요할 때만. MMORPG에선 **직접 AABB 충돌**이 일반적 (성능, 결정론, 서버 동기화에 유리).

### 3.5 공격 처리 (Hitbox 패턴 vs Raycast)

**Hitbox 패턴 (간단)**:
```dart
class AttackHitbox extends PositionComponent with CollisionCallbacks {
  final int damage;
  AttackHitbox({required this.damage}) {
    add(RectangleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void onCollisionStart(Set<Vector2> pts, PositionComponent other) {
    if (other is Damageable) other.takeDamage(damage);
  }
}

// 공격 발동
void doAttack() {
  final hb = AttackHitbox(damage: 10)
    ..position = position + facing * 30
    ..size = Vector2(40, 40);
  parent?.add(hb);
  hb.add(RemoveEffect(delay: 0.15));  // 0.15초 후 제거
}
```

**거리 기반 (단순)** — 엄밀히는 raycast가 아니라 "범위 내 대상 순회":
```dart
void doAttack() {
  for (final m in parent!.children.whereType<Monster>()) {
    final d = (m.position - position).length;
    if (d < attackRange && _facing(m)) m.takeDamage(10);
  }
}
```

> MMORPG 시작 단계에선 **거리 기반**이 단순하고 서버에서 검증하기도 쉽습니다. (이 코드를 "raycast"라 부르지 마세요 — 광선 교차가 아니라 원형 범위 검사입니다.)

**진짜 Raycast / Raytrace (Flame 내장)** — 화살·총알·시야(LoS) 판정처럼 "한 점에서 한 방향으로 처음 맞는 것"이 필요할 때 사용합니다. `HasCollisionDetection`을 가진 World/게임의 `collisionDetection` 객체가 제공합니다(2026-05 기준 시그니처):

```dart
// 단일 광선: origin에서 direction 방향으로 쏴 처음 맞는 히트박스
final ray = Ray2(origin: muzzlePosition, direction: facing.normalized());
final RaycastResult<ShapeHitbox>? hit =
    game.world.collisionDetection.raycast(ray, maxDistance: 600);
if (hit != null && hit.hitbox?.parent is Damageable) {
  (hit.hitbox!.parent! as Damageable).takeDamage(15);
  // hit.intersectionPoint(명중 좌표), hit.normal(법선), hit.reflectionRay(반사선) 활용 가능
}
```

| 메서드 | 시그니처(요약) | 용도 |
|---|---|---|
| `raycast` | `RaycastResult<ShapeHitbox>? raycast(Ray2 ray, {List<ShapeHitbox>? ignoreHitboxes, double? maxDistance})` | 투사체 명중, 한 발 사격, 시야 차단 검사 |
| `raycastAll` | `List<RaycastResult<ShapeHitbox>> raycastAll(Vector2 origin, {int numberOfRays = 32, double? startAngle, double? sweepAngle, ...})` | 폭발/원뿔 범위 공격, 360° 시야 |
| `raytrace` | `Iterable<RaycastResult<ShapeHitbox>> raytrace(Ray2 ray, {int maxDepth = 10, ...})` | 튕기는 광선(반사 총알, 레이저), **지연 평가**라 필요한 만큼만 계산 |

- 자기 자신을 맞히지 않도록 `ignoreHitboxes: [myHitbox]`를 넘깁니다.
- `raytrace`는 lazy `Iterable`이라 `.take(3)`처럼 필요한 반사 횟수만 평가됩니다.
- 출처: https://docs.flame-engine.org/latest/flame/collision_detection.html

### 3.6 HP 시스템

```dart
mixin Damageable on PositionComponent {
  int hp = 100;
  int maxHp = 100;
  bool get isDead => hp <= 0;

  void takeDamage(int dmg) {
    if (isDead) return;
    hp = (hp - dmg).clamp(0, maxHp);
    _onHit();
    if (isDead) _onDeath();
  }

  void _onHit();
  void _onDeath();
}
```

### 3.7 간단한 AI

```dart
class Slime extends ... with Damageable {
  static const detectRange = 200.0;
  static const attackRange = 40.0;
  static const moveSpeed = 80.0;
  static const attackCooldown = 1.2;

  void _idle(double dt) {
    final p = _findPlayer();
    if (p != null && _distTo(p) < detectRange) {
      target = p;
      _setState(MonsterState.chase);
    }
  }

  void _chase(double dt) {
    if (target == null) { _setState(MonsterState.idle); return; }
    final d = _distTo(target!);
    if (d > detectRange * 1.5) { target = null; _setState(MonsterState.idle); return; }
    if (d < attackRange) { _setState(MonsterState.attack); return; }
    final dir = (target!.position - position).normalized();
    position += dir * moveSpeed * dt;
  }

  void _attack(double dt) {
    if (stateTime < attackCooldown) return;
    if (target != null && _distTo(target!) < attackRange) {
      target!.takeDamage(8);
    }
    _setState(MonsterState.chase);
  }
}
```

---

## 4. HUD (체력바)

월드 위에 떠 있는 체력바:

```dart
class HpBar extends PositionComponent {
  final Damageable owner;
  HpBar(this.owner) : super(size: Vector2(40, 4));

  @override
  void update(double dt) {
    super.update(dt);
    position = owner.position + Vector2(-20, -owner.size.y / 2 - 8);
  }

  @override
  void render(Canvas c) {
    c.drawRect(Offset.zero & size.toSize(), Paint()..color = Colors.black54);
    final w = size.x * (owner.hp / owner.maxHp);
    c.drawRect(Offset.zero & Size(w, size.y), Paint()..color = Colors.red);
  }
}
```

---

## 5. 실습 프로젝트 — "2D RPG Battle Test"

### 5.1 요구사항
- 플레이어: WASD 이동, Space 공격
- 몬스터 (Slime): 3~5마리 랜덤 배치
- 몬스터 AI: idle → chase → attack → 사망
- 플레이어 / 몬스터 모두 HP 바 표시
- 사망 시 페이드아웃 후 제거, 5초 후 리스폰
- 플레이어 사망 시 게임오버 화면
- HUD: 플레이어 HP, 처치 카운트, FPS

### 5.2 폴더 구조
```
phase2_action/
├── lib/
│   ├── main.dart
│   └── game/
│       ├── my_game.dart
│       ├── actors/
│       │   ├── player.dart
│       │   ├── slime.dart
│       │   └── attack_hitbox.dart
│       ├── mixins/
│       │   └── damageable.dart
│       ├── hud/
│       │   ├── hp_bar.dart
│       │   └── kill_count.dart
│       └── spawner.dart
└── assets/images/
```

### 5.3 검증 시나리오
- [ ] 몬스터 5마리 동시 처치 시 FPS 유지
- [ ] 공격 판정이 시각과 일치 (눈에 보이는 곳에서 데미지)
- [ ] 사망 처리가 매끄러움 (소멸 직전 hp 음수 가지 않음)
- [ ] 리스폰이 정상 작동

---

## 6. 시니어가 빠지기 쉬운 함정

### 6.1 "공격 hitbox를 매 프레임 새로 만든다"
- 매 프레임 객체 생성 → GC. **Pool 패턴**으로 재사용 또는 **0.15초만 존재**하는 일회성으로.

### 6.2 "FSM을 if-else로 끝없이"
- Phase 2까진 OK. Phase 4 RPG에서 **상태별 클래스 분리** (State 패턴)로 리팩토링.

### 6.3 "Future.delayed로 공격 쿨다운"
- Future 큐에 쌓이면 일시정지/재시작 시 꼬임. **stateTime + cooldown 비교**로 처리.

### 6.4 "Player가 Monster를 직접 참조"
- 결합도 높음. **Damageable 인터페이스**나 **이벤트 버스**로 분리. 단, MMO 가기 전엔 적당히.

### 6.5 "Collision으로 모든 것 해결"
- 100마리 넘으면 N×N 충돌 검사 폭발. Phase 7에서 **Spatial Hash / QuadTree**로 해결. 지금은 OK.

### 6.6 "애니메이션 끝나기 전에 다음 상태 진입"
- attack 애니가 5프레임인데 1프레임만에 chase 복귀 → 어색
- 해결: `stateTime >= animDuration` 수동 비교 대신, **`loop: false` 애니메이션 + `animationTickers![state]!.onComplete`(또는 `done()` / `await ...completed`)** 로 완료 시점을 정확히 잡습니다(3.2 참고). 프레임 수·stepTime을 바꿔도 코드 수정이 필요 없어집니다.

---

## 7. 이 Phase에서 도입할 Flame 공식 패키지

| 패키지 | 용도 | 코멘트 |
|---|---|---|
| **`flame_audio`** | BGM + SFX (공격, 피격, 사망음) | iOS silent-mode 회피 위해 `bgm.initialize()` 필수. 공격 SFX는 `AudioPool(maxPlayers: 4)` |
| **`flame_test`** (dev) | FSM 상태 전이, 데미지 공식, 8방향 sprite 골든 테스트 | `testRandom`으로 시드 고정 → 결정론 검증 |
| **`flame_noise`** | 피격/공격 시 카메라 셰이크 | `MoveEffect.by(Vector2.all(6), NoiseEffectController(duration: 0.2))` 한 줄로 도입 |

```yaml
dependencies:
  flame_audio: ^2.12.1
  flame_noise: ^0.3.2+22
dev_dependencies:
  flame_test: ^2.2.4
```

```dart
// 사전 로딩 (onLoad 안)
await FlameAudio.audioCache.loadAll([
  'sfx/slash.wav', 'sfx/hit.wav', 'sfx/death.wav', 'bgm/town.mp3',
]);
FlameAudio.bgm.initialize();
FlameAudio.bgm.play('bgm/town.mp3');

// 공격 SFX 풀
final slashPool = await FlameAudio.createPool('sfx/slash.wav', maxPlayers: 4);
slashPool.start();

// 카메라 셰이크 (피격 시) — import 'package:flame_noise/flame_noise.dart';
cam.viewfinder.add(
  MoveEffect.by(Vector2.all(6), NoiseEffectController(duration: 0.2)),
);
```

> **시그니처 확인(2026-05)**: `NoiseEffectController({required double duration, Noise? noise, ...})`는 `flame_noise`가 export하는 `EffectController`이고, `MoveEffect.by(Vector2 offset, EffectController controller)`는 flame 코어 표준 시그니처입니다. 둘 다 현행 유효합니다. 직전 패치 `flame_noise 0.3.2+21`에서 *"NoiseEffectController가 일부 플랫폼에서 progress=0을 내보내 흔들리지 않던"* 버그(#3831)가 수정되었으니, 셰이크가 안 보이면 버전을 `^0.3.2+22`로 올렸는지 확인하세요. 셰이크 후 카메라가 원위치로 정확히 돌아오게 하려면 `MoveEffect.by`는 누적 오프셋이 0으로 수렴하는 noise 컨트롤러와 함께 쓰는 것이 핵심입니다.
> 출처: https://github.com/flame-engine/flame/blob/main/packages/flame_noise/CHANGELOG.md

> 본 코스의 전체 패키지 카탈로그는 [flame-official-packages.md](./flame-official-packages.md) 참조.

---

## 8. 학습 자료

- Flame 공식 예제 "Klondike" (카드 게임이지만 컴포넌트/입력 학습에 좋음)
- "Bonfire" 패키지 (Flame 위 RPG 프레임워크 — **참고만**, 직접 쓰지는 말 것. 추상화가 학습 방해)
- Aseprite (스프라이트 제작): https://www.aseprite.org
- Free Sprite: itch.io, OpenGameArt.org
- 캐릭터/몬스터 액션 타이밍: https://gameprogrammingpatterns.com/state.html
- Pooling/데미지 텍스트/VFX 재사용: https://gameprogrammingpatterns.com/object-pool.html
- 전체 그래픽/VFX 출처 목록: [resources.md §0.2](./resources.md)

---

## 9. 학습 후 메모 (직접 작성)

- FSM 설계 시 가장 큰 시행착오:
- Hitbox vs 거리 기반, 어느 쪽을 선택했고 왜:
- Phase 3로 가져갈 패턴:

---

## 10. 다음 단계

[03-phase3-isometric-2.5d.md](./03-phase3-isometric-2.5d.md) — **본 코스의 핵심**. 2D를 2.5D Isometric으로 전환합니다. Depth Sorting을 반드시 마스터해야 MMORPG의 그릇이 됩니다.
