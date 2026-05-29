# GAME SSOT (Single Source of Truth)

이 문서는 앞으로 만들 게임이 **반드시 따라야 할 절대적 규칙**을 기록한다.
여기에 적힌 내용은 모든 코드·에셋·설계보다 우선하며, 예외 없이 준수해야 한다.

---

## 1. 캐릭터 스프라이트시트 규격 (ABSOLUTE RULE)

> **isometric 시점의 애니메이션 재생을 위해, 캐릭터 1개당 `8 x 64` 스프라이트시트(최대 512장의 프레임 셀)를 사용한다.**

- **시점**: isometric → 자연스러운 움직임을 위해 **반드시 8방향**을 모두 그린다. (4방향 금지)
- **시트 구성**: 가로 8칸 × 세로 64칸 = **최대 512 프레임 셀**
  - 가로 8칸 = 프레임 0~7 (**한 동작당 최대 8프레임**)
  - 세로 64칸 = 애니메이션 8종 × 방향 8개
- **프레임 수**: 각 애니메이션은 **최대 8프레임**. 동작이 8프레임보다 적으면 앞에서부터 채우고 **뒤 칸은 비워 둔다**(가변 허용). 16프레임은 용량 대비 과해 채택하지 않는다.
- **미러링 금지**: 8방향을 전부 직접 만든다. 좌우 반전(미러링) 절약 기법은 사용하지 않는다.
  - (이유: `gun-shooting`, `swing-attack` 등 비대칭 무기 동작은 미러링 시 무기가 반대 손으로 가는 문제가 발생하므로, 일관성을 위해 전 동작을 직접 만든다.)

### 1.1 애니메이션 8종 (행 그룹 순서 고정)

| 행 번호 | 애니메이션      | 방향(8행)                       |
| ------- | --------------- | ------------------------------- |
| 0~7     | idle            | S, SE, E, NE, N, NW, W, SW      |
| 8~15    | walk            | (동일 순서)                     |
| 16~23   | run             | (동일 순서)                     |
| 24~31   | gun-shooting    | (동일 순서)                     |
| 32~39   | swing-attack    | (동일 순서)                     |
| 40~47   | hit             | (동일 순서)                     |
| 48~55   | death           | (동일 순서)                     |
| 56~63   | skill           | (동일 순서)                     |

### 1.2 방향 순서 (고정)

방향은 **시계방향 `S → SE → E → NE → N → NW → W → SW`** 로 통일한다.
한 번 정한 이 순서는 모든 애니메이션에 동일하게 적용되어야 하며, 변경할 수 없다.
(순서를 통일해야 인덱스 계산 코드가 단순해진다.)

### 1.3 핵심 인덱스 공식

```
row = animation_index * 8 + direction_index
col = frame_index            // 0 ~ 7 (해당 동작의 실제 프레임 수 만큼만 사용)

픽셀 좌표:
x = col * frameWidth
y = row * frameHeight
```

> 동작마다 프레임 수가 다를 수 있으므로, 각 애니메이션의 **실제 프레임 수(frameCount ≤ 8)** 를
> 별도 메타데이터로 들고 있다가 그 개수만큼만 재생한다.

### 1.4 Flame 구현 — 인덱스 공식을 코드로

Flame에서 이 `8x64` 규격을 다루는 표준 도구는 두 가지다.

- **`SpriteSheet`** — 한 장의 시트 이미지를 격자로 잘라 `getSprite(row, col)`·`createAnimation(row:...)`로 셀/행 단위 접근.
- **`SpriteAnimationGroupComponent<T>`** — 여러 `SpriteAnimation`을 키 `T`에 담아두고 `current` 한 줄로 전환하는 컴포넌트. 우리 규격에서 키 `T`는 "(동작, 방향)" 조합 64개다.

핵심은 `row = animation_index * 8 + direction_index`(1.3)를 **코드의 enum 선언 순서에 못박는 것**이다. enum의 `index`가 곧 공식의 `animation_index`/`direction_index`가 되므로, 선언 순서만 SSOT와 맞으면 인덱스 계산이 자동으로 맞는다.

(1) enum 선언 순서를 1.1(행)·1.2(방향) 순서와 1:1로 맞춘다. Dart 3 enhanced enum으로 동작별 메타데이터(프레임 수·stepTime·loop)까지 한 곳에 둔다. (아래 `frameCount`/`stepTime` 숫자는 가변 규칙(1.3)·권장표(2.3)에 맞춘 **예시 출발값**이다.)

```dart
// 선언 순서 = SSOT 1.1 행 그룹 순서(idle..skill). 따라서 enum.index == animation_index.
enum AnimState {
  idle       (frameCount: 4, stepTime: 0.15, loop: true),
  walk       (frameCount: 8, stepTime: 0.09, loop: true),
  run        (frameCount: 8, stepTime: 0.06, loop: true),
  gunShooting(frameCount: 6, stepTime: 0.07, loop: false),
  swingAttack(frameCount: 7, stepTime: 0.07, loop: false),
  hit        (frameCount: 3, stepTime: 0.06, loop: false),
  death      (frameCount: 8, stepTime: 0.12, loop: false),
  skill      (frameCount: 8, stepTime: 0.08, loop: false);

  const AnimState({
    required this.frameCount, // 1.3의 "실제 프레임 수(≤8)" 메타데이터
    required this.stepTime,
    required this.loop,
  });
  final int frameCount;
  final double stepTime;
  final bool loop;
}

// 선언 순서 = SSOT 1.2 방향 순서(S..SW). 따라서 enum.index == direction_index.
enum Dir { s, se, e, ne, n, nw, w, sw }
```

(2) 시트를 한 번 잘라 64개 `SpriteAnimation`을 키 `(AnimState, Dir)` **record**로 보관한다. Dart 3 record는 값 기반 동등성/해시를 가지므로 별도 키 클래스 없이 `Map` 키로 바로 쓸 수 있다.

```dart
class HeroComponent extends SpriteAnimationGroupComponent<(AnimState, Dir)>
    with HasGameReference<MyGame> {
  HeroComponent()
      : super(size: Vector2.all(128), anchor: Anchor.bottomCenter);

  @override
  Future<void> onLoad() async {
    // 권장 접근자는 game.images. (HasGameRef/gameRef는 flame 1.28.0부터 deprecated → HasGameReference 사용)
    final image = await game.images.load('hero.png');
    final sheet = SpriteSheet(image: image, srcSize: Vector2.all(128));

    final map = <(AnimState, Dir), SpriteAnimation>{};
    for (final a in AnimState.values) {
      for (final d in Dir.values) {
        final row = a.index * 8 + d.index; // ← SSOT 1.3 핵심 공식 그대로
        map[(a, d)] = sheet.createAnimation(
          row: row,
          stepTime: a.stepTime,
          loop: a.loop,
          to: a.frameCount, // 가변 프레임: 빈 뒤칸은 잘라내고 실제 프레임만 재생
        );
      }
    }
    animations = map;
    current = (AnimState.idle, Dir.s);
  }
}
```

`SpriteSheet.createAnimation`의 `to`에 `frameCount`를 넘기면 1.3의 "뒤 칸은 비워 둔다(가변)" 규칙이 그대로 반영된다(빈 셀은 재생되지 않음). 전체 시그니처는 `createAnimation({required int row, required double stepTime, bool loop = true, int from = 0, int? to})`이며 `to`가 null이면 행 끝(8칸)까지 쓴다.

(3) 방향/동작 전환은 `current`에 record를 대입만 하면 된다. 비반복 동작(공격·피격·사망 등)은 끝난 뒤 idle로 되돌리기 위해 해당 티커의 `onComplete`를 건다.

```dart
void play(AnimState a, Dir d) {
  current = (a, d);
  if (!a.loop) {
    animationTickers?[(a, d)]?.onComplete = () => current = (AnimState.idle, d);
  }
}
```

`SpriteAnimationGroupComponent.animationTickers`는 `Map<T, SpriteAnimationTicker>?`로, 키별 재생 상태(`onComplete`, `reset()`, `currentIndex` 등)를 노출한다. (출처: [Flame 공식 컴포넌트 문서](https://docs.flame-engine.org/latest/flame/components.html))

### 1.5 단일 시트 대신 atlas로 묶을 때 — 8방향 키 네이밍

`8x64` 단일 PNG는 가변 프레임 때문에 **빈 셀이 다수 생긴다**(예: hit가 3프레임이면 그 행에서 5칸이 낭비). 빈 셀 낭비와 GPU 텍스처 한계(→ 5번)를 피하려면 실제 프레임만 packing하는 **TexturePacker atlas**(`flame_texturepacker` 5.1.1) 또는 **`flame_fire_atlas`**(1.8.17)로 묶는 편이 낫다. 이때 **region 이름 규칙을 SSOT 축과 1:1로 못박아** 둔다.

- 네이밍 규칙(권장): `{anim}_{dir}_{frame}` — 모두 소문자. 예: `idle_s_0`, `walk_ne_3`, `gun-shooting_w_5`.
- 방향 토큰(8개, 1.2 순서 고정): `s, se, e, ne, n, nw, w, sw`.
- 동작 토큰(8개, 1.1 순서 고정): `idle, walk, run, gun-shooting, swing-attack, hit, death, skill`.

```dart
// flame_texturepacker 5.1.1: region 이름 prefix로 한 동작·한 방향의 프레임들을 모아 애니메이션 생성
final atlas = await loadTexturePackerAtlas('hero.atlas', 'hero.png');
final frames = atlas.findSpritesByName('walk_ne'); // 'walk_ne_0','walk_ne_1'... 이름순 정렬
final walkNe = SpriteAnimation.spriteList(frames, stepTime: AnimState.walk.stepTime);
```

> atlas 방식의 장점: 가변 프레임에서 빈 셀이 사라져 용량이 **실제 프레임 수에 비례**하고, 동작별 프레임 수를 바꿔도 시트 격자를 다시 맞출 필요가 없다. 단점: 빌드 단계에 packing 도구가 끼고, region 이름 규칙을 어기면 곧장 런타임 미스가 난다. (정확한 로드 메서드명은 패키지 버전별로 다를 수 있으니 [flame_texturepacker README](https://pub.dev/packages/flame_texturepacker)를 확인할 것.)

---

## 2. 애니메이션 부드러움 가이드 (참고 원칙)

> 본 게임은 위 1번 규칙(8x64 / 최대 8프레임)을 기준선으로 삼되,
> 부드러움이 부족할 경우 아래 보완책을 **프레임 수를 늘리지 않고** 우선 적용한다.

### 2.1 부드러움을 만드는 진짜 요소 3가지

1. **충분한 프레임 수** — 이론상 walk는 12프레임 이상이 이상적이나, 본 게임은 **용량을 우선하여 최대 8프레임**으로 제한한다.
2. **재생 프레임레이트(fps)** — 보통 12~24fps. Flame 엔진의 `stepTime`으로 동작별로 조절한다. (walk는 빠르게, death는 느리게)
3. **(고급) 프레임 보간** — 프레임 사이를 위치/회전으로 보간하면 적은 프레임으로도 부드러워 보인다. 캐릭터의 화면 위치(`position`)는 매 프레임 lerp 이동시키고, 스프라이트 프레임만 순환시킨다.

### 2.2 정리

- `8x32`는 8방향엔 불가능하다. 최소 `8x64`(프레임 8개 기준)부터 가능하다.
- 프레임을 16개까지 늘리면 더 부드럽지만 시트가 `16x64`로 **용량이 2배**가 된다 → 본 게임은 **용량을 우선해 최대 8프레임**을 채택한다.
- 미러링으로 좌우 3방향을 아끼면 용량을 크게 절약할 수 있으나, 비대칭 무기 문제 때문에 본 게임은 사용하지 않는다.
- 부족한 부드러움은 **프레임 증가가 아니라** `stepTime` 조절(2.1-2) → 위치 보간(2.1-3) 으로 보완한다.

> **현재 확정 사항**: 용량과 일관성을 우선하여, **8방향 전부 그리기 + 각 동작 최대 8프레임 = `8x64` (최대 512셀)** 을 표준으로 채택한다.

### 2.3 동작별 `stepTime` 권장표

`stepTime`은 "한 프레임을 보여주는 시간(초)"이며 `stepTime = 1 / fps`다(2.1-2). 같은 8프레임이라도 `stepTime`만으로 체감 속도가 크게 달라지므로, **프레임 수를 8로 고정한 본 게임에서 부드러움/속도의 1순위 튜닝 손잡이는 이 표**다. 아래 값은 출발점이며, 1.4의 `AnimState` enum 메타데이터와 한 곳에서 일치시켜 관리한다.

| 동작 | 목표 fps | stepTime(초) | loop | 비고 |
| --- | --- | --- | --- | --- |
| idle | ~7 | 0.15 | true | 호흡 정도, 느리게 |
| walk | ~11 | 0.09 | true | 보행 1주기 = frameCount × stepTime |
| run | ~16 | 0.06 | true | walk보다 빠르게 |
| gun-shooting | ~14 | 0.07 | false | 끝나면 idle 복귀(1.4 `onComplete`) |
| swing-attack | ~14 | 0.07 | false | 끝나면 idle 복귀 |
| hit | ~16 | 0.06 | false | 짧고 빠르게 |
| death | ~8 | 0.12 | false | 느리게, 마지막 프레임 유지 |
| skill | ~12 | 0.08 | false | 끝나면 idle 복귀 |

### 2.4 미러링을 쓴다면: Flame 코드와 트레이드오프

1번은 **미러링 금지**(8방향 전부 직접 제작)를 확정했다. 그 결정의 비용을 코드 수준에서 분명히 해 둔다. 8방향 중 `S`/`N`은 좌우 대칭축이라 자체 사용하고, 우측 3방향(`E`/`SE`/`NE`)만 그린 뒤 좌측 3방향(`W`/`SW`/`NW`)을 **수평 반전**으로 대체하면, 그릴 방향이 8개 → **5개(약 37.5% 절감)**, 시트 행도 64 → 40으로 준다.

```dart
// 미러링을 택했을 때의 전환 코드 (참고용 — 본 SSOT는 미채택)
const _mirror = {Dir.w: Dir.e, Dir.sw: Dir.se, Dir.nw: Dir.ne};

void faceMirrored(AnimState a, Dir d) {
  final src = _mirror[d];
  current = (a, src ?? d);
  final shouldFlip = src != null;
  if (shouldFlip != isFlippedHorizontally) {
    flipHorizontallyAroundCenter(); // PositionComponent의 수평 반전
  }
}
```

`PositionComponent.flipHorizontallyAroundCenter()`(현재 반전 상태는 `isFlippedHorizontally` getter)로 좌우를 뒤집는다. 절감은 분명하지만, 1번이 적은 대로 **`gun-shooting`/`swing-attack` 같은 비대칭 무기 동작은 반전 시 무기가 반대 손으로 가는** 문제가 코드에 그대로 드러난다(반전된 방향에서 총·검의 좌우가 뒤바뀜). 그래서 본 게임은 이 절감을 포기하고 전 방향 직접 제작을 유지한다.

---

## 3. 렌더링/제작 방식 비교 (의사결정 기록)

isometric 8방향을 구현하는 방식을 검토한 결과를 남긴다. **핵심 결론: Flame은 2D 엔진이므로 8방향은 결국 스프라이트시트로 귀결된다.**

| 방식 | 런타임 셀 수 | 8방향 제작비 | 부드러움 | Flame 적합성 |
| --- | --- | --- | --- | --- |
| 손으로 그린 스프라이트시트 | 많음 | 비쌈 | 칸 수 비례 | ✅ 쉬움 |
| **3D 프리렌더 스프라이트시트** | **많음** | **쌈** | 자유 | ✅ 쉬움 |
| Spine (2D 스켈레탈) | 없음 | 방향은 수작업 | 무한 | △ 가능 |
| 런타임 3D | 없음 | 공짜 | 무한 | ❌ 어려움 |

### 3.1 셀 수에 대한 핵심 통찰

- 셀(프레임 그림)이 생기는 이유는 "3D라서"가 아니라 **"런타임에 2D 이미지로 굽기(pre-render) 때문"** 이다.
- 따라서 **3D 렌더링은 셀 수를 줄여주지 않는다.** 셀을 만드는 **노동(8방향·다수 프레임 수작업)** 을 줄여줄 뿐이다.
- 셀 자체를 없애려면 런타임 3D 또는 Spine으로 가야 하는데, 전자는 Flame에서 미성숙하고 후자는 방향이 여전히 수작업이다.
- → **Flame + isometric 8방향에서는 "셀이 많은 것"이 숙명이다.** 본 게임은 이를 받아들이고, 대신 **제작 노동을 3D 파이프라인으로 자동화**한다.

### 3.2 Spine을 쓸 경우의 활용법 (대안, 현재 미채택)

Spine은 셀이 없어 동작·장비가 많은 게임에 유리하나, 8방향은 직접 데이터를 가져야 한다. 만약 채택한다면:

- **방향 = 애니메이션 클립 이름 축**으로 분리 (`walk_s`, `walk_e` …), sw/w/nw는 미러링
- **상·하체 본 분리(track)** 로 조합 폭발 방지: 하체 8방향 + 상체 8방향을 따로 만들어 **8×8=64 조합을 8+8=16 제작**으로 해결
- **Skin**으로 장비 교체 (무기 추가 = Skin 1개, 애니메이션 재작업 0)
- Flutter 연동: `spine_flutter` 공식 런타임 (단, Spine 에디터는 유료)

---

## 4. 에셋 제작 파이프라인 (ABSOLUTE RULE)

> **Mixamo(애니메이션) → Blender(8방향 isometric 렌더) → `8x64` 스프라이트시트 → Flame `SpriteAnimation` 재생**

3D 프리렌더 방식을 채택하며, 애니메이션 제작 노동을 **Mixamo로 대체**한다.

```
[1] Mixamo
    휴머노이드 캐릭터 + 동작 애니메이션(FBX) 무료 다운로드
    (idle, walk, run, sword slash, gun, hit, death, skill 등 — SSOT 8동작 대부분 존재)
         │
[2] Blender
    FBX import → isometric 카메라(약 30°) 8방향(45° 간격) 세팅
    무기 모델은 손 본(bone)에 parent 로 부착
         │
[3] 렌더링 (Blender 파이썬 스크립트로 자동화)
    8방향 × 동작별 (최대 8프레임) → PNG 시퀀스 자동 출력
         │
[4] 스프라이트시트 합치기
    → 본 SSOT 1번 규격 "8방향 × 8동작 × 최대 8프레임 = 8x64" 시트 완성
         │
[5] Flutter Flame
    SpriteAnimation 으로 재생 (1.3 인덱스 공식 사용)
```

### 4.1 Mixamo 활용 규칙 및 제약

- **그대로 못 쓴다**: Mixamo는 3D(FBX)이고 Flame엔 FBX 런타임 로더가 없다. **반드시 Blender 프리렌더를 거친다.**
- **휴머노이드 전용**: PC와 인간형 몬스터는 Mixamo 자동 리깅 OK.
  - **비인간형 몬스터(4족·드래곤·슬라임 등)는 Mixamo 자동 리깅 불가** → Blender에서 직접 리깅하거나 별도 에셋 사용.
- **무기는 Mixamo가 제공하지 않는다**: 모션(검 휘두르기/총 쏘기)은 있으나 무기 모델은 Blender에서 손 본에 부착해야 한다.
- **라이선스**: Mixamo는 Adobe 계정만 있으면 무료·상업적 사용 가능(로열티 프리).
- **셀 수는 줄지 않는다**: Mixamo는 제작 노동을 줄일 뿐, 최종 스프라이트시트의 셀 수는 1번 규격 그대로다.

### 4.2 용량 판단 기준

- 캐릭터/장비 종류가 **적으면(수~십수 종)** → 3D 프리렌더 스프라이트시트로 충분히 감당 가능 → **현재 채택안.**
- 캐릭터/장비 조합이 **수백 종으로 폭발하면** → Spine(셀 없음, 3.2) 재검토.
- 실제 셀 크기별 용량·메모리·텍스처 한계는 **5번(용량/메모리 추정)** 을 기준으로 판단한다.

---

## 5. 용량/메모리 추정 (실측 기준)

`8x64` 한 장의 비용은 **셀(프레임) 크기**가 좌우한다. 디스크의 PNG는 압축으로 작아지지만, **GPU에 올라가는 순간 RGBA8888 raw(픽셀당 4바이트)로 전개**되므로 런타임 메모리는 아래 표가 기준이다.

```
raw 메모리 = (가로 셀 8 × 셀폭) × (세로 셀 64 × 셀높) × 4바이트
```

| 셀 크기 | 단일 8x64 시트 해상도 | GPU raw 메모리 | 단일 텍스처로 가능? |
| --- | --- | --- | --- |
| 64×64 | 512 × 4096 | 8 MiB | 대체로 가능(4096 한계 경계) |
| 128×128 | 1024 × 8192 | 32 MiB | 세로 8192 → 구형 모바일에서 위험 |
| 256×256 | 2048 × 16384 | 128 MiB | 불가 — 반드시 분할/atlas |

### 5.1 GPU 텍스처 한계와 분할 권장

- OpenGL ES / Impeller 환경에서 안전하게 보장되는 최대 텍스처 변은 **4096px**다(신형 기기는 8192~16384px이나 구형은 4096). 128px 셀의 단일 `8x64` 시트는 세로가 8192px라 **구형 모바일에서 로드 실패·강제 축소** 위험이 있다.
- 따라서 실전에서는 **동작 8종을 각각 `8행×8열` 시트로 분할**(128px 셀 → 1024×1024, 4096 이내 안전)하거나, 1.5의 **atlas**로 묶어 한 텍스처에 안전하게 packing한다.
- 분할하면 텍스처가 8장으로 늘지만, 각 동작을 독립 로드/언로드할 수 있어 안 쓰는 동작(예: `death`)을 지연 로드하는 메모리 절약이 가능하다.

### 5.2 가변 프레임의 실제 절감

- 1.3의 "최대 8프레임, 부족분은 빈 칸"은 단일 시트에서 **빈 셀만큼 디스크·VRAM이 낭비**된다(2.3 예시처럼 8동작 평균 6프레임이면 단일 시트의 약 1/4이 빈 칸).
- atlas(1.5)는 빈 셀을 packing하지 않으므로 용량이 **실제 프레임 수에 비례**한다. 캐릭터·장비 종류가 늘수록(4.2) 차이가 커지므로, 종류가 많아지면 atlas 전환이 용량 면에서 유리하다.

> packing 시에는 인접 region 색이 번지는 **bleeding** 방지를 위해 region마다 1~2px 여백(padding/extrude)을 주는 것이 안전하다. (참고: Flame 1.37.0(2026-04-01 출시)은 타일맵용 `SpriteBatch`에 `bleed` 옵션을 추가해 같은 종류의 이음새 artifact를 줄였다 — 출처: [flame CHANGELOG](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md))
