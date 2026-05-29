# Flame 공식 패키지 카탈로그 — 학습 코스 도입 가이드

> **출처**: pub.dev verified publisher `flame-engine.org` — Flame 팀이 직접 개발·유지하는 38종 공식 패키지.
> **목적**: 본 study 코스(Flutter Flame 2.5D MMORPG)에서 **각 Phase 별로 어떤 공식 패키지를 도입하는지**를 한눈에 정리.
> **원칙**: 새 기능을 추가할 때 **반드시 Flame 공식 패키지부터 먼저 검토**. 자체 구현 / 비공식 패키지 / 별도 라이브러리는 그 다음.
> **최신 확인일**: 2026-05-28. pub.dev package API와 publisher page 기준.

---

## 0. 2026-05 최신 버전 빠른 표

### 0.1 본 코스에서 실제로 쓰는 패키지

| 패키지 | 최신 버전 | Phase | 비고 |
|---|---:|---|---|
| `flame` | **1.37.0** | Prereq | 2026-04-01 출시. Dart SDK `>=3.11.0 <4.0.0`, Flutter `>=3.41.0` 요구(v1.36에서 Flutter min bump) |
| `flame_lint` | **1.4.3** | Phase 1 | dev dependency |
| `flame_test` | **2.2.4** | Phase 2+ | 결정론/회귀 테스트 |
| `flame_audio` | **2.12.1** | Phase 2 | BGM/SFX |
| `flame_noise` | **0.3.2+22** | Phase 2 | 카메라 셰이크 |
| `flame_tiled` | **3.1.1** | Phase 3 | Tiled TMX 로딩 |
| `flame_kenney_xml` | **0.1.2+1** | Phase 3 | Kenney XML atlas |
| `flame_fire_atlas` | **1.8.17** | Phase 3/7 | Flame Fire Atlas |
| `flame_texturepacker` | **5.1.1** | Phase 3/7 | TexturePacker/GDX atlas |
| `flame_riverpod` | **5.5.4** | Phase 4 | Riverpod bridge |
| `flame_behaviors` | **1.3.5** | Phase 4 | 시각 행동 컴포지션 |
| `jenny` | **1.5.1** | Phase 4 | Yarn Spinner 대화 |
| `flame_rive` | **1.11.1** | Phase 4 | 컷씬/스킬 FX |
| `flame_isolate` | **0.6.2+22** | Phase 7 | 측정 후 신중 도입. **Web 미지원**(Android/iOS/Linux/macOS/Windows만) |
| `flame_splash_screen` | **0.3.1+3** | Phase 8 | 선택 |
| `gamepads` | **0.1.10+2** | 출시 검토 | PC/콘솔 입력. SDK 요구가 더 낮음(아래 주석) |

> **버전 검증 메모(2026-05-29)**:
> - 위 14개 본 코스 패키지 버전은 2026-05-29 시점 pub.dev 최신과 모두 일치(오차 없음). `flame_splash_screen 0.3.1+3`, `gamepads 0.1.10+2`까지 일치 확인.
> - `flame-engine.org` verified publisher의 거의 모든 공식 패키지(`flame`/`flame_tiled`/`flame_audio`/`flame_noise`/`flame_test`/`flame_riverpod`/`flame_behaviors`/`flame_rive`/`flame_fire_atlas`/`flame_texturepacker`/`flame_kenney_xml`/`flame_isolate` 등)가 **2026-04-01경 일제히 동시 릴리스**되었고, 모두 `flame ^1.37.0`을 요구합니다. 따라서 이들 버전을 함께 올리고 함께 검증하는 것이 안전합니다.
> - **SDK 요구치 통일**: 동시 릴리스 패키지(`flame_riverpod`/`flame_isolate`/`jenny` 등)는 Dart sdk `>=3.11.0 <4.0.0`을 요구합니다. **예외는 `gamepads 0.1.10+2`** 로, sdk `>=3.9.0` / Flutter `>=3.35.0` 으로 요구치가 더 낮습니다(2026-05-02 출시). 본 study pubspec의 `sdk: ^3.12.0`은 모든 요구치를 충족합니다.
> - 출처: [pub.dev API(flame)](https://pub.dev/api/packages/flame), [pub.dev API(flame_tiled)](https://pub.dev/api/packages/flame_tiled), [pub.dev(gamepads)](https://pub.dev/packages/gamepads)

### 0.2 검토했지만 기본 미도입인 공식/관련 패키지

| 패키지 | 최신 버전 | 상태 | 판단 |
|---|---:|---|---|
| `flame_forge2d` | 0.19.2+6 | active(flame ^1.37.0) | 본 코스의 server authority 이동/충돌에는 미도입 |
| `forge2d` | 0.14.2+1 | active(느린 주기 ~7개월) | 연출용 물리만 예외 |
| `jolt_physics` | 0.0.1-dev.1 | **prerelease** | "Coming Soon" 표기. 프로덕션 사용 비권장 |
| `flame_spine` | 0.3.0+5 | active(flame ^1.37.0) | Spine 4.3 호환. `initSpineFlutter()` / `onDetach()` dispose 필수. 라이선스·파이프라인 비용 |
| `flame_svg` | 1.12.1 | active | UI 아이콘 정도 |
| `flame_lottie` | 0.4.2+22 | active | Flutter overlay 쪽이 보통 단순 |
| `flame_3d` | 0.2.0 | **active(experimental)** | Android/iOS/macOS만 지원. 2.5D 코스 기본 미도입 |
| `flame_sprite_fusion` | 0.2.3+1 | active | Isometric/Tiled 중심이라 기본 미도입 |
| `flame_markdown` | 0.2.4+15 | active | 긴 lore 필요 전까지 미도입 |
| `flame_bloc` | 1.12.23 | active | Riverpod 표준과 중복 |
| `oxygen` | 0.3.1 | **dormant (2년)** | ECS 도입 비용 큼. 본체가 dormant라 신규 도입 비권장 |
| `flame_oxygen` | 0.2.3+22 | active(flame ^1.37.0) | 단 본체(`oxygen`)는 dormant. 기본 미도입 |
| `behavior_tree` | 0.1.5+1 | active | 클라 AI 결정 로직 금지 |
| `flame_behavior_tree` | 0.1.4+4 | active | 시각/튜토리얼 flow 정도만 |
| `flame_steering_behaviors` | 0.2.1+5 | active | 시각 보간/ambient만 |
| `flame_jenny` | 1.0.0 | **dormant (3년)** | **`flame ^1.6.0`(=`>=1.6.0 <2.0.0`) 요구 — 버전 제약상 1.37.0을 포함하므로 `pub get` 자체는 통과할 수 있으나**, 1.28(HasGameRef deprecate)/1.29(children retain parent)/1.30(32bit Vector2 등) 다수 breaking change로 인한 컴파일·런타임 깨짐 가능성이 큼. 일반 대화는 Flutter Widget + `jenny` 단독 권장 |
| `flame_network_assets` | 0.3.3+22 | active | 본 코스는 CDN + 앱 데이터 패치 설계 우선 |
| `flame_console` | 0.1.3 | active | 자체 debug overlay 권장 |
| `flame_shells` | 0.0.1 | **사실상 discontinued (6년)** | **Dart 3 비호환, `flame ^0.18.1` 요구**. 사용 불가 |
| `gamepads_web` | 0.1.1+1 | active | `gamepads`의 web endorsed federated 구현. **별도 도입 대상이 아님** — `gamepads`를 쓰면 web에서 자동 포함 |
| `gamepads_platform_interface` | 0.1.3 | active | transitive |
| `tiled` | 0.11.1 | active(느린 주기 ~11개월) | `flame_tiled` transitive. Tiled 1.12 신기능 일부는 별도 처리 |

> **2026-05 dormant 경고 3종** — 검색 결과 다음 패키지는 신규 도입을 피하세요:
> 1. **`flame_jenny 1.0.0`** — 3년간 업데이트 없음(2023-01-14 출시). `flame ^1.6.0`은 `>=1.6.0 <2.0.0`이므로 **버전 제약만 보면 1.37.0을 포함해 `pub get`은 통과할 수 있습니다.** 실제 위험은 버전 충돌이 아니라 그 이후 누적된 breaking change(1.28 HasGameRef→HasGameReference, 1.29 children retain parent, 1.30 32bit Vector2 등)로 인한 **컴파일·런타임 깨짐**입니다. NPC 대화는 `jenny 1.5.1` 단독 + Flutter Widget으로 처리하세요.
> 2. **`flame_shells 0.0.1`** — 6년간 업데이트 없음, Dart 3 비호환. 사실상 사용 불가.
> 3. **`oxygen 0.3.1`** — 2년간 업데이트 없음. ECS는 Component 트리 사고와 충돌, 본 코스는 미도입.

### 0.3 Flame 공식이 없는 영역의 최신 일반 패키지

| 패키지 | 최신 버전 | 용도 |
|---|---:|---|
| `nakama` | **1.3.0** | Nakama Dart SDK |
| `web_socket_channel` | **3.0.3** | Phase 5 초반 WebSocket |
| `protobuf` | **6.0.0** | UDP packet 직렬화 |
| `freezed` | **3.2.5** | immutable DTO/model |
| `json_serializable` | **6.14.0** | JSON model codegen |
| `flutter_riverpod` | **3.3.1** | Flutter UI 상태 |
| `riverpod` | **3.2.1** | 순수 Dart 상태 |

---

## 0.4 flame 1.37.0 / 1.36.0 신기능 (코스 관점)

> 본 코스는 `flame 1.37.0`(2026-04-01 출시) 기준입니다. 아래는 **이 버전대에서 실제로 새로 들어온 기능** 중 본 코스(특히 Phase 3 아트, Phase 7 최적화)에 영향이 있는 항목입니다. 출처는 [flame CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md).

### 0.4.1 flame 1.37.0 (2026-04-01) 신기능

| 변경 | 분류 | 코스 적용 |
|---|---|---|
| `SpriteBatch`에 **`bleed` 옵션** 추가 (#3871) | FEAT | **Phase 3**: Isometric/Staggered 타일맵을 atlas/`SpriteBatch`로 렌더할 때 타일 경계의 seam(가는 흰 줄/이음새) artifact를 방지. 카메라 zoom·서브픽셀 위치에서 생기는 줄을 줄여줌 |
| `OverlayManager.setActive()` 추가 (#3875) | FEAT | overlay(HUD/메뉴) 활성 상태를 명령형으로 토글 |
| **`HueEffect` + `HueDecorator`** 추가 (#3852) | FEAT | **Phase 4 연출**: 색조(hue) 이펙트. 피격 플래시·상태이상 틴트 등에 활용 |
| **`HasAutoBatchedChildren`** mixin 추가 (#3850) | FEAT | **Phase 7**: 자식 스프라이트를 자동 배칭해 draw call을 줄임(렌더 성능 최적화) |
| sprite / sprite-animation 위젯에 `size` 파라미터 추가 (#3870) | FEAT | Flutter 위젯으로 스프라이트를 띄울 때 크기 직접 지정 |
| `Block`을 `isometric_tile_map_component`에서 분리 + 헬퍼 메서드 (#3859) | FEAT | **Phase 3**: isometric 타일맵 컴포넌트 내부 구조 정리. 자체 isometric 좌표 계산 시 `Block` API 변화 주의 |
| `CollisionProspect` hash 결합 수정 (#3864) | FIX | 충돌 감지 flaky 동작 수정 |
| flame test helper에서 `async` 제거 (#3860) | FIX | `flame_test 2.2.4`와 동기. 테스트 헬퍼 시그니처 변화 |

### 0.4.2 flame 1.36.0 (2026-03-24) — Phase 7 최적화에 유용

| 변경 | 코스 적용 |
|---|---|
| **`ComponentPool`** — 객체 풀링 (#3816) | **Phase 7**: 투사체/타격 이펙트처럼 대량 생성·제거되는 컴포넌트를 재사용해 GC 압력을 낮춤 |
| **`FlameGame.dispose()`** (#3825) | 게임 종료/해제 시 리소스 정리 진입점 |
| `IconComponent` — `IconData` 직접 렌더 (#3820) | Material/Cupertino 아이콘을 게임 월드에 바로 배치(Kenney atlas 보완) |
| 컴포넌트 트리로 Flutter hot reload 전파 (#3828) | 개발 중 핫 리로드가 컴포넌트 트리에 반영 |
| asset 로딩 메서드/위젯의 `package` 인자 (#3835) | 패키지 번들 에셋 로딩 |
| `onLoad`/`onMount` 중 `buildContext` 사용 가능 (#3833) | 초기화 단계에서 Flutter context 접근 |
| Hitbox가 부모 scale·rotation을 정확히 반영 (#3834) | **Phase 3**: Isometric 스케일 환경의 충돌 정확도 개선 |
| Flutter min version을 3.41.0으로 bump (#3807) | **Prereq**: flame 1.37.0의 Flutter `>=3.41.0` 요구는 여기서 시작됨 |

### 0.4.3 "1.37.0 신기능"으로 오해하기 쉬운 API의 실제 도입 버전

> 본 코스 본문이나 다른 study 문서에서 아래 API를 **신기능으로 소개할 때 1.37.0이라 적지 마세요.** 모두 더 이전 버전에서 도입되었습니다.

| API / 변경 | 실제 도입 버전 | PR |
|---|---|---|
| `SpawnComponent`의 `target` 인자 | **1.30.0** | #3635 |
| `SpawnComponent`의 `spawnCount` | **1.30.0** | #3634 |
| `RasterSpriteComponent.fromImage` 생성자 | **1.30.0** | #3627 |
| 스프라이트 ghost-line/그래픽 artifact 수정(`measure` 도입) | **1.30.0** | #3590 |
| `testGolden`의 `prepare`에 `WidgetTester` 전달 (BREAKING) | **1.30.0** | #3624 |
| Children should retain parent after parent removed (BREAKING) | **1.29.0** | #3602 |
| **`HasGameRef` → `HasGameReference` deprecate** | **1.28.0** | #3559 |

> ⚠️ **`HasGameReference` 정정**: 다른 study 문서 곳곳에 "`HasGameRef`는 v1.33부터 deprecate"라고 적혀 있다면 **오류**입니다. CHANGELOG 기준 deprecation 도입은 **1.28.0(#3559)** 입니다(`HasGameReference` 사용 권장이라는 결론 자체는 맞음). 출처: [flame CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md)

---

## 1. 절대 원칙 (Flame 공식 우선)

본 학습 코스는 다음 우선순위로 패키지를 선택합니다:

```
1순위: flame-engine.org verified publisher 공식 패키지 (본 문서 38종)
2순위: pub.dev에서 광범위 검증된 패키지 (Riverpod, freezed, json_serializable 등)
3순위: 자체 구현
```

**왜 Flame 공식 우선인가**:
- Flame 코어와 호환성·생명주기·라이프사이클이 보장됨
- 다른 공식 패키지와 함께 쓸 때 충돌이 적음
- API 변경 시 동기화됨 (1.x 메이저 변경 시 모든 공식 패키지가 같이 갱신)
- 학습 자료(공식 docs, 예제)가 한 곳에 모임

**공식 패키지가 *없는* 영역**(네트워크, JSON 직렬화, OAuth 등)에서만 일반 pub.dev 패키지를 사용.

---

## 2. Phase 별 도입 타이밍 (TL;DR)

| Phase | 도입할 Flame 공식 패키지 | 이유 |
|---|---|---|
| **Prereq** | `flame` | 엔진 코어 |
| **Phase 1** | `flame_lint` | 코드 품질 (모든 코스 공통) |
| **Phase 2** | `flame_test`, `flame_audio`, `flame_noise` | 단위 테스트 + 사운드 + 카메라 셰이크 |
| **Phase 3** | `flame_tiled` (+ `tiled` transitive), `flame_fire_atlas` 또는 `flame_texturepacker`, `flame_kenney_xml` | 맵, 스프라이트 아틀라스, CC0 에셋 |
| **Phase 4** | `flame_riverpod`, `flame_behaviors`, `jenny`, `flame_rive` | 상태관리 다리, 행동 분해, 대화/퀘스트, 컷씬 |
| **Phase 5** | (없음 — 네트워크는 공식 패키지 부재) | 자체 구현 (`web_socket_channel`, `dart:io`, `protobuf`) |
| **Phase 6** | (없음 — MMORPG 구조는 공식 패키지 부재) | 자체 구현 |
| **Phase 7** | `flame_test` (성능 테스트), `flame_isolate` (신중) | 부하 테스트, 무거운 계산 격리 |
| **Phase 8** | `flame_splash_screen` (선택) | 부팅 화면 |

---

## 3. 카테고리별 평가 (38종 전체)

### 3.1 코어 & 물리 & ECS (6종)

| 패키지 | 권고 | 도입 Phase | 코멘트 |
|---|---|---|---|
| **`flame`** | ✅ A | Prereq | 엔진 코어. 필수 |
| `forge2d` | ❌ E | — | Box2D Dart 포팅. 2.5D Isometric + Server Authority 와 본질 충돌. 본 코스 사용 금지 |
| `flame_forge2d` | ❌ E | — | `forge2d` wrapper. 동일 이유로 미도입. 연출용 ragdoll 같은 격리된 용도에만 가능 |
| `jolt_physics` | ❌ E | — | 0.0.1-dev 초기. 2.5D 코스와 무관 |
| `oxygen` | ❌ E | — | Dart ECS. Flame Component 트리와 사고방식 충돌. dormant |
| `flame_oxygen` | ❌ E | — | oxygen bridge. 본체가 dormant |

> **시니어 코멘트**: MMORPG는 클라이언트가 충돌 시뮬레이션의 진실원이 아닙니다(서버 권위). 물리 엔진은 *완전 시각용 연출*에만 격리해서 쓰거나, 본 코스에선 도입하지 마세요.

---

### 3.2 렌더링 · 애니메이션 · 맵 (12종)

| 패키지 | 권고 | 도입 Phase | 코멘트 |
|---|---|---|---|
| **`flame_tiled`** | ✅ A | Phase 3 | Tiled 맵 로딩. **Orthogonal/Isometric/Staggered/Hexagonal 네 가지 투영 모두 지원**. **본 코스 필수** |
| `tiled` | ✅ A (자동) | Phase 3 | `flame_tiled` transitive. AI 생성 TMX 검증 스크립트 등에 직접 import 가능 |
| **`flame_rive`** | ✅ B | Phase 4 | Rive 애니메이션. 사망/리스폰 컷씬, 스킬 발동 FX, UI 동적 효과. 캐릭터 본체는 sprite 유지 |
| `flame_spine` | ⚠️ C | (선택) | Spine 4.3 skeletal. **Spine Editor 유료 라이선스**. 본 코스 학습엔 sprite 기반 추천 |
| `flame_svg` | ❌ D | — | 벡터. 픽셀아트 톤과 충돌. UI 아이콘에 한정 |
| `flame_lottie` | ❌ D | — | Lottie 마이크로 모션. Flutter Widget overlay가 더 깔끔 |
| `flame_3d` | ❌ E | — | 실험적. 2.5D 코스와 무관 |
| **`flame_texturepacker`** | ✅ B | Phase 3 후반 또는 Phase 7 | 큰 atlas 패킹. TexturePacker (유료 Pro) 또는 GDX Texture Packer (CC0) 결과 로딩 |
| **`flame_fire_atlas`** | ✅ B | Phase 3 후반 또는 Phase 7 | **Flame 팀 자체 atlas 에디터**. 오픈소스. CC0 정책과 정합 |
| `flame_sprite_fusion` | ❌ D | — | Orthogonal 위주, Isometric 미지원 가능성 큼. `flame_tiled` 유지 |
| **`flame_kenney_xml`** | ✅ B | Phase 3 | **Kenney.nl CC0 자산** 직결. UI 아이콘/효과/프로토타입에 강력 |
| `flame_markdown` | ❌ D | — | NPC 대화/lore가 길어질 때까지 불필요. Flutter Widget으로 충분 |

> **본 코스 권고**:
> - **Phase 3**: `flame_tiled` 필수. `flame_kenney_xml`로 UI 아이콘 빠르게 확보. `flame_tiled`는 Orthogonal/Isometric/Staggered/Hexagonal 네 가지 투영을 모두 지원하지만 본 코스는 Isometric이 핵심.
> - **Phase 3 후반 또는 Phase 7 최적화 시**: 30+ 스프라이트로 늘어나면 `flame_fire_atlas`(오픈소스) 또는 `flame_texturepacker` 도입. draw call 감소 효과 큼.
>   - **타일맵 seam(이음새) artifact 주의**: Isometric/Staggered 타일맵을 atlas/`SpriteBatch`로 렌더할 때 카메라 zoom·서브픽셀 위치에서 타일 경계에 가는 흰 줄이 보일 수 있습니다. `flame 1.37.0`의 `SpriteBatch` **`bleed` 옵션**(#3871)과 1.30.0의 sprite `measure` 기반 ghost-line 수정이 이를 완화합니다. atlas 도입과 함께 다루세요.
>   - 대형 타일셋이면 `TiledComponent.load`의 `atlasMaxX`/`atlasMaxY` 옵션으로 atlas 텍스처 한계를 넓혀야 할 수 있습니다(Phase 3 문서 참조).
> - **Phase 4**: `flame_rive`로 스킬 이펙트나 컷씬에 한정 도입. 색조 틴트(피격 플래시 등)는 1.37.0 신규 `HueEffect`/`HueDecorator`로 코어에서 처리 가능.

---

### 3.3 상태관리 · 입력 (5종)

| 패키지 | 권고 | 도입 Phase | 코멘트 |
|---|---|---|---|
| `flame_bloc` | ❌ D | — | 본 코스는 Riverpod 표준. 이중 상태관리 금지 |
| **`flame_riverpod`** | ✅ A | Phase 4 | **Riverpod ↔ Flame Component의 *유일한* 공식 다리**. `RiverpodAwareGameWidget` + `RiverpodGameMixin` + `RiverpodComponentMixin`. ⚠️ 공식 명시 플랫폼에 Web 없음 (모바일·데스크탑 OK) |
| **`gamepads`** | ✅ B | (PC/콘솔 출시 검토 시) | Xbox/DualSense/Switch Pro. `Gamepads.normalizedEvents.listen`. android/iOS/linux/macOS/windows/**web** 모두 지원하는 federated plugin. 모바일-only면 우선순위 낮음 |
| `gamepads_web` | (자동) | — | **`gamepads`의 web endorsed federated 구현**. 별도로 추가하는 패키지가 아니라 `gamepads`를 의존하면 web에서 자동으로 끌려옴 |
| `gamepads_platform_interface` | (자동) | — | gamepads transitive. 직접 import 불필요 |

> **본 코스 권고**:
> - **Phase 4부터 `flame_riverpod` 즉시 도입**. ActorComponent의 hp/exp 같은 게임 상태와 Flutter UI(인벤토리/HUD) 사이를 깔끔하게 연결.
> - Phase 1~3까지는 Component 자체 필드로 충분 — 도입을 미루세요.
>
> **`gamepads` federated 구조 메모(오해 방지)**: `gamepads 0.1.10+2`는 android/iOS/linux/macOS/windows/web을 모두 타겟으로 등록한 federated plugin이며, **web 구현은 `gamepads_web`이라는 endorsed 구현으로 이미 내부에 포함**됩니다. 즉 Web을 정식 타겟으로 잡더라도 `gamepads_web`을 pubspec에 따로 추가할 필요가 없습니다(의존하면 자동으로 끌려옴). 또 `gamepads`는 sdk `>=3.9.0` / Flutter `>=3.35.0`으로 flame(`>=3.11.0`/`>=3.41.0`)보다 요구치가 낮아, flame을 쓰는 환경이라면 자연히 충족됩니다. [출처: pub.dev(gamepads)](https://pub.dev/packages/gamepads)

---

### 3.4 오디오 · UI · 유틸 (9종)

| 패키지 | 권고 | 도입 Phase | 코멘트 |
|---|---|---|---|
| **`flame_audio`** | ✅ A | Phase 2 후반 | BGM(`Bgm`) + SFX(`AudioPool(maxPlayers: 4)`). iOS silent-mode 회피 위해 `bgm.initialize()` 필수 |
| **`flame_lint`** | ✅ A | Phase 1 | 0-cost 적용. `include: package:flame_lint/analysis_options.yaml`. 학습 초기부터 켜기 |
| **`flame_test`** | ✅ A | Phase 2 | 단위/결정론 테스트. `testRandom` 시드 고정, 8방향 sprite 골든. **DTD/통합 테스트와 역할 분리** |
| **`flame_noise`** | ✅ A | Phase 2 또는 Phase 4 | `NoiseEffectController` + `MoveEffect.by`로 카메라 셰이크 한 줄. Boss slam, hit-stop, 환경 효과 |
| `flame_splash_screen` | ⚠️ C | (선택) Phase 8 | 부팅 인트로. Flame 로고 강제 노출 부담이 있음 |
| `flame_console` | ❌ D | — | 인-게임 콘솔. 자체 디버그 패널이 더 ROI 높음 |
| `flame_shells` | ❌ E | — | 0.0.1 legacy/실험적. 본 코스 미도입 |
| `flame_isolate` | ⚠️ C | Phase 7 (신중) | 무거운 계산 isolate 격리. **Web 미지원**. mob마다 mixin 붙이면 isolate 폭증 — 단일 manager에만. 본 코스에선 서버가 무거운 계산 담당 |
| `flame_network_assets` | ❌ D | — | 원격 에셋 로딩. 본 코스는 번들 SSOT + `cached_network_image`로 주변 자산 처리 |

> **본 코스 권고**:
> - **Phase 1**: `flame_lint` 즉시 적용. 학습 초기 코드 품질 신호.
> - **Phase 2**: `flame_test`, `flame_audio`, `flame_noise` 세 가지 모두 도입.
> - **Phase 7**: `flame_isolate`는 측정 후 필요한 경우에만(**Web 미지원** 주의).
>   - 외부 패키지 도입 전에 **flame 코어 신기능부터** 검토하세요. `ComponentPool`(1.36.0, #3816)로 투사체/이펙트의 GC 압력을 낮추고, `HasAutoBatchedChildren`(1.37.0, #3850)으로 자식 스프라이트 draw call을 줄이며, `FlameGame.dispose()`(1.36.0, #3825)로 종료 시 리소스를 정리합니다. 자세한 목록은 §0.4 참조.
>
> **`flame_noise` 메모**: `flame_noise 0.3.2+22`의 `NoiseEffectController` + `MoveEffect.by(Vector2, EffectController)`는 현행 유효 API입니다. 직전 버전 0.3.2+21에서 "일부 플랫폼에서 NoiseEffectController가 zero progress를 내던" 버그(#3831)가 수정되었으니 0.3.2+22 이상을 쓰세요. [출처: flame_noise CHANGELOG](https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame_noise/CHANGELOG.md)

---

### 3.5 AI · 행동 · 내러티브 (6종)

| 패키지 | 권고 | 도입 Phase | 코멘트 |
|---|---|---|---|
| **`flame_behaviors`** | ✅ B | Phase 4 | Entity ↔ Behavior 컴포지션. **시각 행동만**(애니메이션, HpBar, 보간, hit FX, Y-sort). ⚠️ **AI 결정 로직 절대 금지** — 서버 권위 위반 |
| `behavior_tree` | ❌ D | — | 0.1.x 초기. 클라 BT는 이중 결정(R2-MONSTER-CLIENT-SHIELD 가드). UI flow 한정 가능 |
| `flame_behavior_tree` | ❌ D | — | Flame BT mixin. 동일 이유. 카메라 follow fallback, 튜토리얼 step 정도에만 |
| `flame_steering_behaviors` | ⚠️ C | Phase 4 후반 | Reynolds Wander/Separation. **서버 좌표 SSOT 보존 필수** — 시각 보간/투사체 trail/swarm ambient 한정 |
| **`jenny`** | ✅ A | Phase 4 | **YarnSpinner Dart 포팅 (1.5.1 production-ready, Flame 비의존, sdk `>=3.11.0`)**. NPC 대화·퀘스트·튜토리얼 SSOT. `<<set $flag=true>>` 변수, custom command. Flame에 의존하지 않으므로 flame 버전 bump와 무관하게 안정적. ⚠️ 보상 지급은 반드시 **Nakama RPC 서버 검증** — yarn 변수만 믿고 지갑 갱신 금지 |
| `flame_jenny` | ❌ E | — | jenny ↔ Flame bridge. **3년 dormant(2023-01-14)**. `flame ^1.6.0`은 버전상 1.37.0을 포함하나, 누적 breaking change로 빌드/런타임 깨짐 위험. world-space 대화 버블이 본질적으로 필요할 때만. 일반 대화는 Flutter Widget + `jenny 1.5.1` 단독이 더 단순 |

> **본 코스 권고**:
> - **Phase 4**: `jenny` 도입으로 NPC 대화/퀘스트를 .yarn 스크립트로 외부화. `flame_behaviors`로 시각 행동을 깔끔히 분해.
> - **AI 결정 로직(몬스터 의도, 공격 결정)은 클라이언트 BT에 두지 마세요**. 멀티플레이에서는 서버가 결정. 싱글플레이 Phase 4에선 단순 FSM(Phase 2)으로 충분.

---

## 4. 본 코스의 절대 금지 가드 (Flame 패키지 도입 시)

본 코스는 멀티플레이 + Server Authority + Nakama 메타 + Go UDP Zone 구조를 전제로 합니다. 다음을 위반하지 마세요:

1. **클라이언트 BT / Steering으로 몬스터 위치/공격 결정 금지** — `behavior_tree`/`flame_behavior_tree`/`flame_steering_behaviors`는 *시각 보간·이펙트* 한정. Go Zone Server가 결정의 진실원.
2. **Forge2D / Jolt로 캐릭터·몬스터 충돌 시뮬 금지** — Y-sort + Isometric + UDP Server Authority와 본질 충돌. 완전 클라이언트 연출(붕괴 / ragdoll)에만 격리.
3. **Yarn 변수만 믿고 보상 지급 금지** — 퀘스트 완료 / 인벤토리 변동은 반드시 Nakama RPC 서버 검증.
4. **`flame_bloc` + `flame_riverpod` 동시 도입 금지** — 이중 상태관리 SSOT 깨짐. 본 코스는 Riverpod 표준.
5. **`flame_3d` 도입 금지** — 2.5D 코스의 자산 파이프라인을 갈아엎는 비용 거대.
6. **벡터(SVG/Lottie/Rive)를 캐릭터 본체에 도입 금지** — 8방향 sprite + isometric 규약과 맞지 않음. UI overlay에만.
7. **`flame_console`을 사람 디버그 채널로 만들지 말 것** — 자체 디버그 오버레이가 ROI 높음.
8. **Atlas 도입(`flame_fire_atlas`/`flame_texturepacker`) 시 이름 컨벤션 라벨링 SSOT 선행 작성** — 안 하면 row 인덱스보다 atlas 키가 더 디버깅 어려움.

---

## 5. 단계별 즉시 도입 액션 (학습자가 곧장 따라할 수 있는)

### Phase 1 (Flame 기초)
```yaml
# pubspec.yaml
dependencies:
  flame: ^1.37.0
dev_dependencies:
  flame_lint: ^1.4.3   # 코드 품질
```
```yaml
# analysis_options.yaml
include: package:flame_lint/analysis_options.yaml
```

### Phase 2 (2D 액션)
```yaml
dependencies:
  flame_audio: ^2.12.1
  flame_noise: ^0.3.2+22
dev_dependencies:
  flame_test: ^2.2.4
```
- `audioCache.loadAll([...])` 사전 로딩
- 공격 SFX는 `AudioPool(maxPlayers: 4)` 로 동시 발사 처리
- 단위 테스트로 FSM 상태 전이, 데미지 공식 결정론 검증
- 피격 시 `MoveEffect.by(Vector2.all(6), NoiseEffectController(duration: 0.2))` 로 카메라 셰이크

### Phase 3 (2.5D Isometric)
```yaml
dependencies:
  flame_tiled: ^3.1.1
  flame_kenney_xml: ^0.1.2+1   # CC0 UI 아이콘
```
- Phase 3 후반에 스프라이트 30+ 도달하면:
  ```yaml
  flame_fire_atlas: ^1.8.17     # 오픈 에디터 (Flame 팀 자체)
  # 또는
  flame_texturepacker: ^5.1.1   # TexturePacker / GDX 결과 로딩
  ```

### Phase 4 (RPG 시스템)
```yaml
dependencies:
  flame_riverpod: ^5.5.4        # Riverpod 다리
  flame_behaviors: ^1.3.5       # 시각 행동 컴포지션
  jenny: ^1.5.1                  # 대화/퀘스트
  flame_rive: ^1.11.1            # 컷씬/스킬 FX
```
- `LaryenGame` (또는 본인 게임) 에 `with RiverpodGameMixin`
- `GameWidget` → `RiverpodAwareGameWidget`
- ActorComponent의 `hp`, `exp` 등을 `ref.listen(actorStateProvider, ...)` 로 Flutter UI에 연결
- `assets/dialogues/*.yarn` 으로 NPC 대화 외부화

### Phase 5 (멀티플레이)
Flame 공식 패키지 없음. 다음 일반 패키지 사용:
```yaml
dependencies:
  nakama: ^1.3.0                  # Nakama 클라이언트 SDK
  web_socket_channel: ^3.0.3      # 학습 초반 WS
  protobuf: ^6.0.0                # UDP 패킷 직렬화
  # dart:io RawDatagramSocket은 SDK 내장
```

### Phase 7 (최적화)
```yaml
dependencies:
  flame_isolate: ^0.6.2+22       # 신중하게 — 측정 후
```
- mob마다 mixin 금지. **단일 manager Component** (예: pathfinding manager)에만 적용
- Web 빌드 대상이면 미도입

### Phase 8 (라이브 서비스)
```yaml
dependencies:
  flame_splash_screen: ^0.3.1+3  # 선택
```

---

## 6. 빠른 결정 트리

```
새 기능을 추가하려는가?
├── 오디오/BGM/SFX?               → flame_audio (Phase 2)
├── 단위/결정론 테스트?            → flame_test (Phase 2)
├── 카메라 셰이크/노이즈?          → flame_noise (Phase 2)
├── 타일맵 / Isometric?           → flame_tiled (Phase 3) ✓ 이미
├── 스프라이트 atlas?              → flame_fire_atlas 또는 flame_texturepacker (Phase 3 후반)
├── CC0 UI 아이콘?                 → flame_kenney_xml (Phase 3)
├── Riverpod ↔ Component 다리?    → flame_riverpod (Phase 4)
├── 시각 행동 컴포지션?            → flame_behaviors (Phase 4)
├── NPC 대화/퀘스트 스크립트?      → jenny (Phase 4)
├── 컷씬 / 스킬 이펙트?            → flame_rive (Phase 4)
├── 게임패드 입력?                 → gamepads (출시 검토 시)
├── 무거운 클라 계산 격리?         → flame_isolate (Phase 7, 측정 후)
├── 부팅 인트로?                   → flame_splash_screen (Phase 8 선택)
├── 코드 lint?                     → flame_lint (Phase 1)
├── 네트워크 / 멀티플레이?         → 공식 없음, 자체 구현 (Phase 5)
└── MMORPG 구조 (AoI, Zone)?      → 공식 없음, 자체 구현 (Phase 6)
```

---

## 7. 참고 링크

- **pub.dev verified publisher**: https://pub.dev/publishers/flame-engine.org/packages
- **flame pub.dev/API**: https://pub.dev/packages/flame / https://pub.dev/api/packages/flame
- **flame_tiled pub.dev/API**: https://pub.dev/packages/flame_tiled / https://pub.dev/api/packages/flame_tiled
- **nakama pub.dev/API**: https://pub.dev/packages/nakama / https://pub.dev/api/packages/nakama
- **Flame Docs**: https://docs.flame-engine.org
- **Flame GitHub (모노레포)**: https://github.com/flame-engine/flame
- **공식 예제**: https://github.com/flame-engine/flame/tree/main/examples
- **flame CHANGELOG (신기능/도입 버전 근거)**: https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame/CHANGELOG.md
- **flame_noise CHANGELOG**: https://raw.githubusercontent.com/flame-engine/flame/main/packages/flame_noise/CHANGELOG.md
- **flame_tiled Tiled 가이드(투영 지원)**: https://docs.flame-engine.org/latest/bridge_packages/flame_tiled/tiled.html

---

## 8. 마무리

본 문서는 **새 기능을 만들기 전 항상 먼저 확인하는** SSOT 입니다. 본 코스 진행 중 새 요구가 생기면:

1. 본 문서 §6 결정 트리부터 확인
2. 해당 카테고리의 ✅ A/B 등급 패키지가 있으면 그것을 우선 도입
3. ❌ D/E 등급은 본 문서 §4 절대 금지 가드 참조
4. Flame 공식이 없으면 일반 pub.dev 패키지 (이때만 자체 구현 또는 외부 패키지 선택)

> **시니어 코멘트**: 40년 경력으로 패키지 선택의 감은 있지만, Flame 생태계는 별도 문법입니다. "공식 우선" 원칙을 지키면 호환성·생명주기 문제를 90% 회피합니다.
