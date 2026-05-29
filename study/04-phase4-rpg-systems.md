# Phase 4 — RPG 시스템

> **기간**: 2주
> **목표**: 2.5D 그릇 위에 RPG의 도메인 모델(엔티티, 스탯, 전투, 아이템, 인벤토리, 레벨)을 구축한다. **싱글플레이로 완벽하게** 만든 후 Phase 5로 간다.
> **금기**: 멀티플레이, 서버. 지금은 클라이언트가 진실(Source of Truth).

---

## 1. 학습 목표

- [ ] Entity 계층 (Player / NPC / Monster / Projectile) 깔끔하게 분리
- [ ] Stats 시스템 (HP, MP, ATK, DEF, EXP, Level)
- [ ] Combat 시스템 (Melee, Ranged, Skill, Cooldown, Damage Formula)
- [ ] Inventory + Equipment + Item DB
- [ ] EXP / Level / 성장 곡선
- [ ] Save / Load (로컬, JSON)
- [ ] 게임 진행: 사냥 → 경험치 → 레벨업 → 더 좋은 아이템

---

## 2. 핵심 도메인 모델

```
GameState
├── Player
│   ├── Stats         (hp, mp, atk, def, ...)
│   ├── Level         (lv, exp, expToNext)
│   ├── Inventory     (List<ItemStack>)
│   ├── Equipment     (head, body, weapon, ...)
│   └── Skills        (List<SkillSlot>)
├── World
│   ├── Map
│   ├── NPCs
│   └── Monsters
└── ItemDB / SkillDB / MonsterDB   (정적 데이터, JSON 로딩)
```

### 2.1 정적 데이터 vs 런타임 상태 분리

| 정적 (DB / JSON) | 런타임 |
|---|---|
| 아이템 정의 (ID, 이름, 스프라이트, 공격력) | 인벤토리 슬롯 (item_id × 수량 × 강화도) |
| 스킬 정의 (쿨다운, 데미지, 효과) | 스킬 쿨다운 타이머 |
| 몬스터 정의 (기본 HP, 드롭) | 현재 HP, 상태 |

이 분리는 시니어에게는 익숙한 패턴 (게임 = DB 정규화와 비슷). MMO에선 정적 데이터는 클라/서버 양쪽이 같은 버전을 가져야 합니다.

---

## 3. Entity 계층 설계

```dart
abstract class Entity extends IsoActor {       // Phase 3에서 만든 베이스
  String entityId;                              // 런타임 고유 ID (uuid)
  int hp = 100;
  int maxHp = 100;
  bool get isAlive => hp > 0;

  void takeDamage(int dmg, Entity? from);
  void onDeath();
}

abstract class Creature extends Entity {
  Stats stats;
  int level = 1;
  // 공격, 이동 능력
}

class Player extends Creature {
  Inventory inventory;
  Equipment equipment;
  int exp = 0;
  // 효과 합산: stats.atk + equipment.weapon.atk
  int get totalAtk => stats.atk + equipment.totalAtk;
}

class Monster extends Creature {
  MonsterDef def;          // 정적 정의 참조
  List<ItemDrop> drops;
  // AI FSM (Phase 2에서 만든 것 재사용)
}

class NPC extends Entity { /* 대화, 상점 */ }

class Projectile extends Entity { /* 화살, 마법탄 */ }
```

---

## 4. 캐릭터/몬스터 제작 파이프라인

MMORPG에서 캐릭터와 몬스터는 "한 장의 sprite"가 아니라 **데이터, 애니메이션, 이펙트, 서버 판정이 연결된 제품 단위**입니다. Phase 4에서 아래 규약을 잡아두면 Phase 5 이후 멀티플레이로 넘어갈 때 흔들리지 않습니다.

### 4.1 Sprite naming SSOT

```text
assets/sprites/
├── player/
│   ├── warrior_idle_s_00.png
│   ├── warrior_walk_ne_03.png
│   └── warrior_attack1_e_05.png
├── monsters/
│   ├── slime_idle_s_00.png
│   ├── wolf_lunge_w_04.png
│   └── boss_golem_slam_s_08.png
└── fx/
    ├── slash_arc_e_00.png
    └── hit_spark_critical_02.png
```

권장 키 규칙:

```text
{actor}_{state}_{dir}_{frame}
{fx}_{variant}_{dir}_{frame}
```

이 규칙을 atlas key, Tiled object property, 스킬 데이터, 테스트 fixture에서 모두 공유합니다. row/column index를 코드에 직접 박으면 나중에 atlas 재패킹 때 전부 깨집니다.

### 4.2 Actor 데이터 정의

```json
{
  "id": "wolf",
  "displayName": "Forest Wolf",
  "size": [64, 64],
  "footOffset": [0, -6],
  "collision": {"type": "circle", "radius": 14},
  "animations": {
    "idle": {"frames": 6, "step": 0.12},
    "walk": {"frames": 8, "step": 0.08},
    "attack": {"frames": 10, "step": 0.06, "activeFrame": 5},
    "hit": {"frames": 3, "step": 0.05},
    "death": {"frames": 12, "step": 0.08}
  }
}
```

`footOffset`, `collision`, `activeFrame`은 시각 품질과 서버 판정 사이를 맞추는 핵심 데이터입니다.

### 4.3 아름답고 화려한 몬스터를 만드는 규칙

- 일반 몬스터도 idle/walk/attack/hit/death 5상태는 최소로 둡니다.
- 정예/보스는 telegraph, charge, recovery, enraged 상태를 추가합니다.
- 공격 범위는 시각 이펙트보다 작게 잡습니다. "보이는 곳보다 약간 덜 맞는" 쪽이 덜 억울합니다.
- 피격은 sprite tint, hit-stop, 작은 knockback, hit spark 4개가 함께 들어갈 때 타격감이 살아납니다.
- 보스는 몸 전체를 한 component로 두기보다 `body`, `armLeft`, `armRight`, `weapon`, `shadow`, `aura`처럼 분해하면 연출 폭이 커집니다.
- Rive/Spine은 컷씬·UI·대형 보스 부위 애니메이션에는 좋지만, MMO 본체 캐릭터는 8방향 sprite atlas가 서버 동기화와 성능 면에서 단순합니다.

### 4.4 스킬 타임라인 데이터화

```json
{
  "id": "fire_slash",
  "cooldown": 1.2,
  "range": 52,
  "timeline": [
    {"t": 0.00, "event": "anim", "name": "attack"},
    {"t": 0.12, "event": "sfx", "name": "sword_whoosh"},
    {"t": 0.18, "event": "hitbox", "shape": "arc", "duration": 0.08},
    {"t": 0.20, "event": "fx", "name": "slash_arc"},
    {"t": 0.22, "event": "shake", "power": 0.4}
  ]
}
```

싱글플레이 Phase 4에서는 이 타임라인이 실제 데미지도 처리합니다. Phase 5 이후에는 클라이언트 타임라인은 **예측 연출**이고, Go Zone Server가 authoritative hit 결과를 보내면 데미지 숫자와 사망을 확정합니다.

---

## 5. Stats 시스템

```dart
class Stats {
  int strength;     // 물공
  int intelligence; // 마공
  int dexterity;    // 명중, 회피
  int vitality;     // HP, DEF
  int luck;         // 크리

  int get atk => strength * 2;
  int get matk => intelligence * 2;
  int get def => vitality;
  int get maxHp => 100 + vitality * 10;
  // ...
}
```

> 시니어 팁: **derived stat은 getter**. 저장은 base만. 그래야 장비 변경, 버프 적용이 단순해집니다.

> **패턴 연계**: "base는 필드, 파생값은 getter" 규약은 *Game Programming Patterns*의 **Dirty Flag / Subclass Sandbox** 관점과 맞닿아 있습니다. 장비/버프가 자주 바뀌고 파생 계산이 무거워지면(예: 수십 개의 가산·승산 modifier 합성), getter가 매번 전체를 재계산하지 않도록 "modifier 목록이 바뀔 때만 재계산하고 캐시한다"는 dirty-flag 캐시를 도입합니다. 본 코스 규모(파생 계산이 가볍고 modifier 수가 적음)에서는 **단순 getter로 충분**하며, 프로파일러로 병목이 확인되기 전에는 캐시를 넣지 마세요(조기 최적화 금지). [출처: https://gameprogrammingpatterns.com/dirty-flag.html]

---

## 6. 데미지 공식

가장 단순한 형태:
```
damage = max(1, atk - def)
```

조금 더:
```
damage = atk * (100 / (100 + def))    // 비율 감소
critical = random < (luck / 100)
if critical: damage *= 1.5
```

```dart
class DamageCalculator {
  static int compute(Creature attacker, Creature defender, {required Skill skill}) {
    var base = (attacker.totalAtk + skill.power) * skill.scale;
    base *= 100 / (100 + defender.totalDef);
    final isCrit = math.Random().nextDouble() < attacker.critRate;
    if (isCrit) base *= 1.5;
    return base.round().clamp(1, 99999);
  }
}
```

---

## 7. Skill / Cooldown 시스템

```dart
class Skill {
  final String id;
  final String name;
  final double cooldown;     // 초
  final double castTime;     // 캐스팅 시간
  final int manaCost;
  final double range;
  final SkillType type;      // melee, ranged, aoe
  final int power;
  final double scale;
}

class SkillSlot {
  Skill skill;
  double remaining = 0;     // 남은 쿨다운

  bool get isReady => remaining <= 0;

  void tick(double dt) { if (remaining > 0) remaining -= dt; }
  void use() { remaining = skill.cooldown; }
}

class Player extends Creature {
  List<SkillSlot> skills = [];
  Skill? casting;
  double castTimer = 0;

  void tryCast(Skill s) {
    final slot = skills.firstWhere((x) => x.skill.id == s.id);
    if (!slot.isReady || mp < s.manaCost) return;
    casting = s;
    castTimer = s.castTime;
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (final s in skills) s.tick(dt);

    if (casting != null) {
      castTimer -= dt;
      if (castTimer <= 0) {
        _executeSkill(casting!);
        casting = null;
      }
    }
  }
}
```

> MMORPG에서 **캐스팅 중 이동하면 캐스팅 취소** 같은 룰을 처음부터 코드에 박아두세요. 멀티플레이에서 이게 안 잡혀 있으면 동기화 지옥.

---

## 8. Inventory + Equipment

### 7.1 ItemDef vs ItemStack
```dart
class ItemDef {
  final String id;
  final String name;
  final String iconPath;
  final ItemType type;       // consumable, weapon, armor
  final Map<String, int> stats;   // {"atk": 10, "vit": 2}
  final int stackable;       // 0 = unique, >1 = stackable
}

class ItemStack {
  final ItemDef def;
  int quantity;
  int? plus;                 // 강화 +N
}
```

### 7.2 Inventory
```dart
class Inventory {
  static const slots = 50;
  final List<ItemStack?> items = List.filled(slots, null);

  bool add(ItemStack stack) { ... }
  bool remove(int slot, [int qty = 1]) { ... }
  void swap(int a, int b) { ... }
}
```

### 7.3 Equipment
```dart
enum EquipSlot { head, body, weapon, shield, gloves, boots, accessory1, accessory2 }

class Equipment {
  final Map<EquipSlot, ItemStack?> slots = { for (final s in EquipSlot.values) s: null };
  int get totalAtk => slots.values
      .where((x) => x != null)
      .map((x) => x!.def.stats['atk'] ?? 0)
      .fold(0, (a, b) => a + b);
}
```

---

## 9. EXP / Level

```dart
int expToNext(int lv) => (100 * math.pow(1.5, lv - 1)).round();

void gainExp(Player p, int amount) {
  p.exp += amount;
  while (p.exp >= expToNext(p.level)) {
    p.exp -= expToNext(p.level);
    _levelUp(p);
  }
}
```

> 곡선은 게임 디자인 문제. 본 코스는 학습이 목적이므로 단순 지수 곡선 충분.

---

## 10. Save / Load

```dart
class SaveData {
  final Map<String, dynamic> player;
  final Map<String, dynamic> world;
}

extension on Player {
  Map<String, dynamic> toJson() => {
    'level': level, 'exp': exp,
    'stats': stats.toJson(),
    'inventory': inventory.toJson(),
    'equipment': equipment.toJson(),
    'position': {'x': position.x, 'y': position.y},
  };
}

// shared_preferences 또는 파일
final json = jsonEncode({'player': player.toJson()});
await prefs.setString('save', json);
```

> 시니어 팁: 처음부터 **json_serializable + freezed** 로 모델 정의. 나중에 서버 동기화할 때 같은 모델을 재사용 가능.

### 10.1 freezed 3.x / json_serializable 최신 규약 (2026-05)

`SaveData`/`Stats`/`ItemStack` 같은 직렬화 모델은 손으로 `toJson()`을 쓰지 말고 **freezed 3.x + json_serializable**로 코드 생성하는 편이 안전합니다(누락·오타로 인한 save 손상 방지). 2026-05 기준 정식 최신 버전은 다음과 같습니다.

```yaml
dependencies:
  freezed_annotation: ^3.x        # freezed 본체와 짝
  json_annotation: ^4.x
dev_dependencies:
  build_runner: ^2.x
  freezed: ^3.2.5                 # 2026-02, 정식 최신
  json_serializable: ^6.14.0      # 2026-05, 정식 최신
```

> **freezed 3.x 마이그레이션 주의**: freezed 2.x의 암묵적 union 생성 방식이 바뀌어, **클래스에 `sealed` 또는 `abstract` 키워드를 직접 붙여야** 합니다. 단일 데이터 클래스는 `abstract`, 여러 생성자로 union(합타입)을 만들 때는 `sealed`를 씁니다. JSON 직렬화가 필요하면 여전히 `json_serializable`이 `fromJson`/`toJson`을 생성하므로 `part 'xxx.g.dart';`도 함께 선언합니다.

```dart
// save_data.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'save_data.freezed.dart';
part 'save_data.g.dart';

// freezed 3.x: 단일 클래스는 abstract, union은 sealed
@freezed
abstract class StatsDto with _$StatsDto {
  const factory StatsDto({
    required int strength,
    required int intelligence,
    required int dexterity,
    required int vitality,
    required int luck,
  }) = _StatsDto;

  factory StatsDto.fromJson(Map<String, dynamic> json) =>
      _$StatsDtoFromJson(json);
}

@freezed
abstract class SaveData with _$SaveData {
  const factory SaveData({
    @Default(1) int saveVersion,        // 마이그레이션용 스키마 버전
    required int level,
    required int exp,
    required StatsDto stats,
    required List<ItemStackDto> inventory,
    required Map<String, dynamic> equipment,
    required ({double x, double y}) position,
  }) = _SaveData;

  factory SaveData.fromJson(Map<String, dynamic> json) =>
      _$SaveDataFromJson(json);
}
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

> **`saveVersion` 필드를 처음부터 박아두세요.** Phase 5에서 서버와 같은 DTO를 공유하게 되면 스키마가 진화합니다. 버전 필드가 없으면 구버전 save를 읽다가 앱이 죽습니다. `fromJson`에서 `saveVersion`을 보고 분기/마이그레이션하는 자리를 미리 마련합니다.
>
> **domain ↔ DTO 분리**: §11.2의 `domain/` 폴더(순수 Dart)에는 freezed 의존을 넣지 않는 편이 깔끔합니다. domain은 순수 비즈니스 모델로 두고, `*Dto`(freezed)는 직렬화 경계에서만 쓰며 `toDomain()`/`fromDomain()`으로 변환하면 Phase 5에서 서버 패킷 DTO와 클라 domain 모델이 깔끔히 분리됩니다(단, 학습 규모에선 DTO를 domain으로 직접 써도 무방).
>
> 출처: [freezed](https://pub.dev/packages/freezed) · [json_serializable](https://pub.dev/packages/json_serializable)

---

## 11. UI (Flutter Widget으로!)

게임 내부는 Flame, **인벤토리/스킬바/대화창은 Flutter Widget**으로 만들고 GameWidget 위에 overlay 합니다.

```dart
GameWidget(
  game: myGame,
  overlayBuilderMap: {
    'inventory': (ctx, MyGame g) => InventoryOverlay(player: g.player),
    'dialog':    (ctx, MyGame g) => DialogOverlay(dialog: g.currentDialog!),
  },
);

// 게임 코드에서
overlays.add('inventory');     // 표시
overlays.remove('inventory');  // 숨김
```

> Flutter 위젯 작업 경험이 그대로 살아납니다. 게임 UI(메뉴/HUD/인벤토리/대화창) 80%는 Flutter Widget으로 만드는 편이 더 빠르고 깔끔합니다.

---

## 12. 실습 프로젝트 — "싱글플레이 RPG"

### 11.1 요구사항
- Phase 3의 2.5D 맵 위에
- 몬스터 3종 (난이도 차등)
- 스킬 3~5개 (단일 공격, 광역, 회복)
- 아이템 10~20개 (포션, 무기, 방어구)
- 인벤토리 / 장비창 / 스킬바 UI (Flutter Widget)
- NPC 상점 1곳, 퀘스트 1개 ("슬라임 10마리 잡고 와")
- EXP / 레벨업
- Save / Load
- 게임오버 / 부활

### 11.2 폴더 구조
```
phase4_rpg/
├── lib/
│   ├── main.dart
│   └── game/
│       ├── domain/                # 순수 Dart, Flame 의존 X
│       │   ├── stats.dart
│       │   ├── item.dart
│       │   ├── skill.dart
│       │   └── damage.dart
│       ├── data/                  # 정적 JSON 로더
│       │   ├── item_db.dart
│       │   ├── skill_db.dart
│       │   └── monster_db.dart
│       ├── entities/
│       │   ├── player.dart
│       │   ├── monster.dart
│       │   ├── npc.dart
│       │   └── projectile.dart
│       ├── systems/
│       │   ├── combat_system.dart
│       │   ├── inventory_system.dart
│       │   └── save_system.dart
│       └── ui/                    # Flutter Widget overlay
│           ├── hud.dart
│           ├── inventory_overlay.dart
│           └── dialog_overlay.dart
└── assets/
    ├── data/
    │   ├── items.json
    │   ├── skills.json
    │   └── monsters.json
    └── ...
```

> **domain 폴더는 Flame import 금지** — Phase 5에서 서버와 공유할 수 있도록 순수 유지.

### 11.3 검증 시나리오
- [ ] Lv 1 → Lv 5 까지 정상 성장
- [ ] 스킬 3개 모두 의도대로 작동, 쿨다운 표시
- [ ] 인벤토리에서 포션 사용 → HP 회복
- [ ] 장비 착용/해제 시 스탯 즉시 반영
- [ ] 상점에서 구매/판매
- [ ] Save → 앱 재시작 → Load 후 모든 상태 복원
- [ ] 60fps 유지 (50+ 객체 동시)

---

## 13. 시니어가 빠지기 쉬운 함정

### 12.1 "OOP 다중 상속처럼 Entity 트리 깊게"
- 3단계까지. `Entity → Creature → Player` 정도. 그 이상은 mixin/composition으로.

### 12.2 "ItemDef를 코드에 하드코딩"
- 30개 넘어가면 지옥. **JSON으로 처음부터**. 디자이너(나중에)가 손볼 수 있는 구조로.

### 12.3 "스킬 효과를 if-else 거대 함수로"
- `Skill`이 effect를 데이터로 갖도록: `[{"type":"damage","power":50},{"type":"slow","duration":2}]`. 인터프리터 패턴.
- **패턴 매핑**: 이 데이터 주도 effect 리스트는 *Game Programming Patterns*의 **Interpreter / Bytecode** 패턴(데이터를 작은 명령 시퀀스로 해석)과 **Command** 패턴(각 effect를 실행 가능한 객체로 캡슐화)에 정확히 대응합니다. `§4.4`의 스킬 timeline(`{"t":0.18,"event":"hitbox",...}`)도 같은 사고의 시간축 버전입니다. effect 종류별로 `EffectHandler` 인터페이스를 두고 `Map<String, EffectHandler>`로 디스패치하면, 새 효과(예: `"bleed"`, `"stun"`)를 코드 분기 없이 JSON + 핸들러 등록만으로 추가할 수 있습니다.
- ⚠️ Phase 5 대비: 이 인터프리터는 **순수 도메인 로직**으로 두세요(`domain/` 폴더, Flame import 금지). 그래야 동일 인터프리터를 Go Zone Server가 authoritative 판정에 재사용할 수 있고, 클라는 동일 데이터로 **예측 연출**만 돌립니다(§4.4 참조). [출처: https://gameprogrammingpatterns.com/bytecode.html]

### 12.4 "Inventory를 List<Item>으로"
- 슬롯 개념이 약해짐. `List<ItemStack?>` (null = 빈 슬롯) 권장.

### 12.5 "Player.hp를 Riverpod Provider로"
- 매 프레임 변경 → 매 프레임 UI rebuild → 30fps. **변경 시점에만 notify** 하거나 UI가 hp를 매 프레임 폴링.

### 12.6 "Save를 매 프레임"
- 30초 주기 또는 의미 있는 액션(레벨업, 맵 전환) 시점에. 그렇지 않으면 디스크 IO 폭발.

### 12.7 "domain 로직에 Flame import"
- Phase 5에서 서버와 모델 공유할 때 의존성 지옥. 처음부터 분리.

### 12.8 "처음부터 ECS(Entity-Component-System) 프레임워크부터 깔자"
- 데이터 지향 설계(DOD) 경험이 있는 시니어가 자주 빠지는 함정입니다. **Flame은 ECS가 아니라 컴포지션 기반 씬그래프(컴포넌트 트리)** 입니다. `Component`는 ECS의 "data-only Component"가 아니라 자체 `update()`/`render()`를 가진 객체이고, 별도의 "System"이 모든 컴포넌트를 한꺼번에 훑는 구조가 아닙니다. Flame 위에 진짜 ECS를 얹으려면 `flame_oxygen`(`oxygen` ECS 위 어댑터)을 써야 하는데, **`oxygen` 본체는 2024-03-19 이후 약 2년간 dormant**라 본 코스에서는 권장하지 않습니다.
- **판단 기준**: 같은 종류의 엔티티가 **수천 단위**로 늘어나고 매 프레임 대량 순회의 캐시 효율(데이터 지역성)이 측정상 병목일 때만 ECS를 고려하세요. 그 외 싱글/소규모 RPG(본 코스 규모: 50~수백 객체)는 **Flame 컴포넌트 트리 + 도메인 모델 분리(`domain/`)** 로 충분하며 훨씬 단순합니다.
- ECS의 장점(데이터 지향, 캐시 친화)은 §13의 `flame_behaviors`(시각 행동 컴포지션)나 effect 인터프리터(§12.3)로 "필요한 곳만" 흉내 낼 수 있습니다. 전면 ECS 도입은 엔티티 수가 실제로 폭발한 뒤(예: 대규모 군중/투사체 시뮬레이션) 프로파일러 근거를 가지고 결정하는 게 안전합니다. [출처: https://gameprogrammingpatterns.com/component.html · https://pub.dev/packages/flame_oxygen]

---

## 14. 이 Phase에서 도입할 Flame 공식 패키지

| 패키지 | 용도 | 코멘트 |
|---|---|---|
| **`flame_riverpod`** | Riverpod ↔ Flame Component 의 **유일한 공식 다리** | `LaryenGame with RiverpodGameMixin`, `GameWidget → RiverpodAwareGameWidget`. ⚠️ Web 미명시 |
| **`flame_behaviors`** | 시각 행동 컴포지션 (HpBar, hit FX, Y-sort, 보간) | ⚠️ **AI 결정 로직 절대 금지** — 멀티에서 서버 권위 위반 |
| **`jenny`** (YarnSpinner Dart) | NPC 대화, 사이드 퀘스트, 튜토리얼 SSOT | `<<set $quest_done=true>>`, custom command 가능. ⚠️ 보상 지급은 Phase 5+에서 Nakama RPC 검증 |
| **`flame_rive`** | 스킬 발동 FX, 사망 컷씬, UI 동적 효과 | 캐릭터 본체는 sprite 유지. 강력한 모션 한정. ⚠️ 2026 기준 **Rive Data Binding(ViewModel)** 이 공식 권장이며 기존 state machine `input` 은 deprecated — 코드 마이그레이션 필요 |

```yaml
dependencies:
  flame_riverpod: ^5.5.4
  flame_behaviors: ^1.3.5
  jenny: ^1.5.1
  flame_rive: ^1.11.1
```

> **Rive 마이그레이션 노트(2026-05)**: Rive Flutter 런타임은 **0.14.0**에서 기존 Dart 런타임을 **C++ 네이티브 런타임으로 완전 교체**하면서 **Data Binding(ViewModel)** 을 도입했습니다(2026-05 기준 정식 최신은 `rive 0.14.7`). 정확히는 state machine **input 및 text run 접근 메서드(`SMIInput` 획득 경로)** 가 `0.14.0-dev.14`부터 deprecated 표시되었고, Data Binding이 best practice로 권장됩니다(deprecated API가 곧 제거되는 것은 아니지만 신규 코드는 채택 비권장). `flame_rive 1.11.1`이 `rive ^0.14.0`에 의존하므로 `ViewModelInstance.boolean('attacking')`/`.number('hp')` 강타입 바인딩과 `valueStream<T>()`(0.14.2+)를 사용할 수 있습니다 — 컷씬·UI 동적 효과의 코드 양이 크게 줄고 Riverpod state와 직접 매핑하기 쉽습니다.
> ⚠️ 다만 `flame_rive`의 `RiveComponent`가 `ViewModelInstance`를 노출/바인딩하는 구체 API는 flame 공식 docs에 별도 명시가 부족하므로, **flame_rive README/example로 현재 노출 방식을 확인**한 뒤 적용하세요(필요 시 `RiveComponent`가 감싼 `Artboard`/`StateMachineController`에서 ViewModel을 직접 잡는 식으로 우회).
> 출처: [rive changelog](https://pub.dev/packages/rive/changelog) · [rive Flutter Data Binding](https://rive.app/docs/runtimes/flutter/data-binding) · [flame_rive](https://docs.flame-engine.org/latest/bridge_packages/flame_rive/rive.html)

> **(선택) Spine 도입 시 주의**: `flame_spine 0.3.0+5`는 `spine_flutter ^4.3.0`에 의존하여 **Spine 4.3 호환**입니다(v0.3.0부터 4.3 지원, v0.2.2가 Spine 4.2를 지원한 마지막 버전). **Spine 4.2 에디터로 export한 모델은 4.3 런타임에서 그대로 못 쓰므로 4.3 에디터로 재export**해야 합니다. 게임 시작 시 `await initSpineFlutter()` 호출이 필수이며, 컴포넌트 dispose 단계에서 **`onDetach()`** 에서 native resource 정리도 필수입니다. 본 코스는 캐릭터 본체는 sprite 유지를 권장하며, Spine은 보스 부위 분해/대형 컷씬에만 사용하세요.
> 출처: https://docs.flame-engine.org/latest/bridge_packages/flame_spine/flame_spine.html · https://esotericsoftware.com/spine-flutter

```dart
// flame_riverpod 통합
void main() {
  runApp(ProviderScope(
    child: MaterialApp(home: Scaffold(body: RiverpodAwareGameWidget(game: MyGame()))),
  ));
}

class MyGame extends FlameGame with RiverpodGameMixin { ... }

class Player extends PositionComponent
    with RiverpodComponentMixin, HasGameReference<MyGame> {
  @override
  void onMount() {
    super.onMount();
    addToGameWidgetBuild(() {
      ref.listen(playerHpProvider, (_, hp) => /* HUD 갱신 */);
    });
  }
}

// jenny 대화 (Phase 4 후반 도입)
final yarn = YarnProject()..parse(await rootBundle.loadString('assets/dialogues/intro.yarn'));
final dialogue = DialogueRunner(yarnProject: yarn, dialogueViews: [myFlutterDialogueView]);
await dialogue.startDialogue('IntroNode');
```

### 14.1 Riverpod 3.x 코드 생성 패턴 (위 `playerHpProvider`의 정의)

2026-05 기준 정식 최신은 `flutter_riverpod 3.3.1` / `riverpod 3.2.1`입니다(모노레포라 두 패키지의 버전 숫자가 다른 것은 정상). Riverpod 3.x에서는 수동 `Provider`/`StateNotifierProvider` 선언보다 **`riverpod_annotation`의 `@riverpod` 어노테이션 + `riverpod_generator`(build_runner)** 로 `NotifierProvider`/`AsyncNotifierProvider`를 코드 생성하는 방식이 공식 권장입니다. 위 예제의 `playerHpProvider`는 이렇게 정의합니다.

```yaml
dependencies:
  flutter_riverpod: ^3.3.1
  riverpod_annotation: ^3.x
dev_dependencies:
  build_runner: ^2.x
  riverpod_generator: ^3.x
  custom_lint: ^0.x
  riverpod_lint: ^3.x
```

```dart
// player_hp_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_hp_provider.g.dart';

@riverpod
class PlayerHp extends _$PlayerHp {
  @override
  int build() => 100;                 // 초기 HP

  void set(int v) => state = v;        // 변경 시점에만 notify (§12.5 함정 회피)
}
// 생성된 provider 이름: playerHpProvider
```

> ⚠️ **§12.5 함정과 직결**: `playerHp`를 **매 프레임 `set()` 하면 매 프레임 위젯 rebuild**가 일어나 프레임이 무너집니다. HP/MP처럼 자주 바뀌는 값은 (1) 게임 루프(`update()`)에서는 일반 필드로 들고, (2) **의미 있는 변화 시점**(피격·회복·레벨업)에만 provider로 push하거나, (3) HUD를 Flame 컴포넌트(`flame_behaviors`의 HpBar)로 그려 위젯 rebuild 자체를 피하세요. `flame_riverpod`의 `addToGameWidgetBuild`로 등록한 `ref.listen`은 game widget 빌드 주기에 묶이므로, 고빈도 값은 watch가 아니라 **listen + 디바운스**가 안전합니다.
>
> 출처: [Riverpod code generation](https://riverpod.dev/docs/concepts/about_code_generation) · [flame_riverpod](https://pub.dev/packages/flame_riverpod)

> 본 코스의 전체 패키지 카탈로그는 [flame-official-packages.md](./flame-official-packages.md) 참조.

---

## 15. 학습 자료

- 시니어용 도서:
  - "Game Programming Patterns" — Robert Nystrom (무료 온라인). **State, Command, Object Pool, Component 패턴은 본 Phase 필독**
- Flame Effects 패키지 (스킬 시각 효과)
- json_serializable: https://pub.dev/packages/json_serializable
- freezed: https://pub.dev/packages/freezed
- Aseprite docs: https://www.aseprite.org/docs/
- Rive Flutter runtime: https://rive.app/docs/runtimes/flutter/flutter
- Spine user guide: https://esotericsoftware.com/spine-user-guide
- 전체 캐릭터/몬스터/VFX 출처 목록: [resources.md §0.2](./resources.md)

---

## 16. 학습 후 메모 (직접 작성)

- 도메인 분리(domain 폴더)를 지키며 얻은 효과:
- 스킬 시스템 설계에서 가장 어려웠던 부분:
- Phase 5(멀티)에서 깨질 가능성 있는 가정:

---

## 17. 다음 단계

[05-phase5-multiplayer.md](./05-phase5-multiplayer.md) — **본 코스의 두 번째 큰 산**. Server Authority, Prediction, Reconciliation을 도입합니다. Phase 4의 클라이언트 진실 모델이 전부 뒤집힙니다.
