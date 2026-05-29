# Phase 7 — 최적화

> **기간**: 지속 (Phase 6 안정화 후 1~2개월)
> **목표**: 100+ entity, 30+ 동시 접속, 60fps 안정. 모바일 디바이스에서도 발열·배터리 합리적.
> **원칙**: **측정 → 가장 큰 병목 → 해결 → 재측정.** 추측 금지.

---

## 1. 학습 목표

- [ ] DevTools (Performance, Memory, CPU)로 병목 식별
- [ ] Impeller 렌더러 기준으로 raster 비용 측정·해석 (셰이더 지터 사라짐을 전제)
- [ ] Sprite Atlas, Image Cache로 GPU draw call 감소
- [ ] Object Pool로 GC 압박 제거
- [ ] Camera Culling, Off-screen Skip
- [ ] Spatial Partition (QuadTree, Spatial Hash)
- [ ] Server tick 비용 분석 (pprof / flame graph)
- [ ] Delta Compression, Bit Packing
- [ ] LOD (Level of Detail) — 멀리 있는 entity 단순화

---

## 2. 측정이 먼저 — Profiling

### 2.1 Flutter DevTools
```bash
flutter run --profile        # release에 가까운 성능
# DevTools → Performance → Timeline 녹화
```
보는 것:
- **Build phase** 가 길면 → Widget rebuild가 잦음 (UI/Provider 문제)
- **Layout/Paint** 가 길면 → 너무 많은 RenderObject
- **Raster** 가 길면 → GPU 부하 (draw call 많음, 큰 텍스처)

Flame은 build phase가 짧고 raster가 길어야 정상. 반대면 게임 외부 UI가 문제.

### 2.2 Flame 내장 FPS
```dart
add(FpsTextComponent());
add(ChildCounterComponent<Component>(target: world));   // 살아있는 컴포넌트 수
```

### 2.3 Dart Observatory / Memory tab
- 매 프레임 객체 생성 → "GC events" 증가
- Vector2.zero() 같은 호출도 다 비용

### 2.4 서버 측 (Go)
```bash
import _ "net/http/pprof"
go func() { http.ListenAndServe(":6060", nil) }()
# go tool pprof http://localhost:6060/debug/pprof/profile
```

### 2.5 어떤 렌더러로 측정하는가 — Impeller (2026 현황)

raster 비용은 **어떤 렌더러가 그리는가**에 따라 의미가 달라집니다. 옛 Flutter는 Skia로 그렸지만, 2026 기준 기본 렌더러는 **Impeller**로 전환이 사실상 마무리됐습니다. 프로파일링 전에 이 전제를 알아야 측정값을 올바로 해석할 수 있습니다.

- **iOS**: Impeller만 지원하며 Skia 백엔드는 **제거**됐습니다(Skia로 되돌릴 수 없음). Metal 위에서 동작.
- **Android**: API 29+(Android 10+)에서 Impeller가 **기본**입니다. 2026 로드맵에서 legacy Skia(GLES) 백엔드 제거를 마무리하는 작업이 진행 중입니다. Vulkan을 우선 사용하고 미지원 기기에서 GLES로 폴백.
- **데스크톱/웹**: macOS(Metal), Windows·Linux(Vulkan)로 확장 작업이 진행 중이며, 전 플랫폼 단일 렌더러를 목표로 합니다.

측정 시 주의:
- `flutter run --profile` 시 렌더러는 **플랫폼 기본값**(iOS = Impeller)으로 동작합니다. 별도 플래그 없이 측정하면 실배포와 같은 렌더러를 보게 됩니다.
- Impeller는 셰이더를 **빌드 시점에 사전 컴파일**하므로, Skia에서 악명 높던 "첫 등장 객체의 첫 프레임 셰이더 컴파일 지터(shader jank)"가 사라졌습니다. 따라서 Timeline에서 raster spike가 보이면 셰이더 컴파일이 아니라 실제 draw call/텍스처 부하일 가능성이 높습니다 — Atlas(§3.1)·culling(§3.4)으로 접근하세요.
- 출처: https://docs.flutter.dev/perf/impeller

---

## 3. 클라이언트 최적화 — 우선순위

### 3.1 Sprite Atlas (필수)
- 개별 png 100장 = draw call 100번 = 프레임 드랍
- 모아서 큰 png 1장 (atlas) + UV 좌표 → draw call 1번
- 도구: TexturePacker, Free Texture Packer

```dart
final atlas = await Sprite.load('atlas.png');
final iconHp = Sprite(atlas.image, srcPosition: Vector2(0, 0), srcSize: Vector2(32, 32));
```

**SpriteBatch + bleed 옵션 (flame 1.37.0)**: 동일 텍스처에서 잘라낸 다수의 스프라이트(타일, 파티클, 동일 atlas의 아이콘)를 한 번의 draw call로 그릴 때는 `SpriteBatch`를 씁니다. flame 1.37.0(2026-04-01)에서 `SpriteBatch`에 **`bleed` 옵션**이 추가됐습니다(PR [#3871](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md)). 이는 카메라 zoom·서브픽셀 위치에서 타일 경계에 생기는 seam(가는 흰 줄/이음새) artifact를 방지합니다. 1.30.0의 `Sprite` measure 기반 ghost-line 수정(PR #3590)에 이은 후속 개선으로, Isometric/Staggered 타일맵(Phase 3)을 atlas로 렌더할 때 함께 다루면 좋습니다.

**`HasAutoBatchedChildren` mixin (flame 1.37.0)**: 같은 이미지를 공유하는 자식 컴포넌트들의 draw call을 자동으로 배칭해 주는 mixin이 추가됐습니다(PR [#3850](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md)). 수동으로 `SpriteBatch`를 조립하지 않아도 draw call 수를 줄일 수 있어, 동일 atlas 기반 다수 엔티티에 유용합니다.

> 참고: `SpawnComponent`의 `target`/`spawnCount` 인자(PR #3635/#3634)와 `RasterSpriteComponent.fromImage`(PR #3627)는 **1.37.0이 아니라 1.30.0** 신기능입니다. 본문에서 이들을 "신기능"으로 소개할 때 버전을 정확히(1.30.0) 적으세요.

### 3.2 Image Cache
- 같은 이미지 두 번 load → 두 번 디코딩
- Flame은 `game.images.load()` (with `HasGameReference<MyGame>`) 가 캐시. 직접 `decodeImageFromList()` 호출 자제.
- 정정: 여기서 deprecate된 것은 `images.load` 같은 개별 메서드가 아니라 옛 `gameRef` getter(`HasGameRef` mixin) 자체입니다. `HasGameRef` → `HasGameReference` deprecate는 **flame 1.28.0**(PR [#3559](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md))에서 도입됐고, 대체 getter는 `game`(`HasGameReference` mixin)입니다. 따라서 `gameRef.images.load()` → `game.images.load()` 로 마이그레이션하면 됩니다. (기존 문서의 "v1.33부터" 표기는 버전 오류로 정정)

### 3.3 Object Pool
대표적으로 화살, 데미지 텍스트, 이펙트:

```dart
class DamageTextPool {
  final List<DamageText> pool = [];

  DamageText acquire() {
    final t = pool.isEmpty ? DamageText() : pool.removeLast();
    t.activate();
    return t;
  }

  void release(DamageText t) {
    t.deactivate();
    pool.add(t);
  }
}
```

> 매 프레임 생성되는 모든 객체를 후보로 검토하세요. Vector2, Paint, TextPainter 모두 대상.

**현행화 — flame 내장 `ComponentPool`**: 위처럼 손수 풀을 구현하는 대신, flame 1.36.0(2026-03-24, PR [#3816](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md))부터 코어에 `ComponentPool`이 추가되어 컴포넌트 객체 풀링을 표준 방식으로 제공합니다. 투사체·데미지 텍스트·파티클처럼 대량 생성·제거되는 컴포넌트에 적용하면 GC 압박을 줄일 수 있습니다.

```dart
// flame 1.36+ : Factory로 새 인스턴스 생성 방식을 정의
final pool = ComponentPool<Bullet>(() => Bullet());

// 발사 시: 풀에서 꺼냄 (없으면 factory로 생성)
final bullet = pool.get();
world.add(bullet);

// 수명 종료 시: removeFromParent() 대신 풀로 반환해 재사용
pool.release(bullet);
```

> 같은 1.36.0에서 게임 종료/해제 시 리소스 정리를 위한 `FlameGame.dispose()`(PR #3825)도 추가됐습니다. 라이프사이클 종료 경로에서 풀·캐시·스트림 구독을 정리할 때 활용하세요.

### 3.4 Camera Culling
화면 밖 entity의 render() 호출 자체를 막아야 raster 비용 줄어듭니다.

```dart
class Cullable extends PositionComponent with HasGameReference<MyGame> {
  @override
  void renderTree(Canvas canvas) {
    final visible = game.camera.visibleWorldRect;     // Rect (Flame 1.x)
    if (!visible.overlaps(toRect())) return;
    super.renderTree(canvas);
  }
}
```

> 단, update는 막지 마세요 (게임 로직이 멈춤). render만 skip.
> 정정: `visibleWorldRect` API 자체는 deprecate된 적이 없습니다. `CameraComponent.visibleWorldRect`(`Rect` 반환)는 flame 1.6.0에서 도입되어 현재(1.37.0)도 유효합니다. deprecate된 것은 접근 경로인 옛 `gameRef` getter뿐이며, 이는 **flame 1.28.0**에서 일어났습니다(기존 문서의 "v1.33부터"는 버전 오류). 따라서 옛 `gameRef.camera.visibleWorldRect` 는 **`game.camera.visibleWorldRect`** (with `HasGameReference<MyGame>`) 로 대체하세요.
> flame 1.36.0(2026-03-24)부터 Hitbox가 부모의 scale·rotation을 정확히 반영하므로(PR [#3834](https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md)), Isometric 스케일 환경에서 `toRect()` 기반 culling 판정의 정확도도 함께 개선됐습니다.

### 3.5 Off-screen update 빈도 낮추기
화면 밖에서 빠르게 움직이지 않는 NPC는 update 빈도 1/3로:
```dart
double _tickSkip = 0;
@override
void update(double dt) {
  if (!_visible) {
    _tickSkip += dt;
    if (_tickSkip < 0.1) return;
    dt = _tickSkip;
    _tickSkip = 0;
  }
  super.update(dt);
}
```

### 3.6 Paint 객체 재사용
```dart
// 나쁜 예
@override
void render(Canvas c) {
  c.drawRect(rect, Paint()..color = Colors.red);   // 매 프레임 Paint 생성
}

// 좋은 예
static final _redPaint = Paint()..color = Colors.red;
@override
void render(Canvas c) {
  c.drawRect(rect, _redPaint);
}
```

### 3.7 Widget Overlay 최소화
- Flutter Widget이 게임 위에 떠 있으면 매 프레임 그 영역 rebuild 가능
- 인벤토리는 열렸을 때만 overlay, 닫히면 즉시 제거

### 3.8 Text 렌더링
- `TextComponent`는 매 update에 layout. 자주 바뀌지 않으면 cached TextPainter로.
- 데미지 텍스트는 짧은 수명 → Pool 필수.

### 3.9 Animation Stride
- 60Hz 게임에서 8프레임 애니메이션은 0.0125초/프레임이면 부드러우나 비쌈
- 시각적으로 충분하면 0.1초/프레임 (10fps 애니)으로 충분

### 3.10 priority 갱신 비용
- Phase 3에서 매 프레임 `priority = position.y.round()` 했음
- World가 그걸로 sort → 100개 객체 × 매 프레임 sort = 비쌈
- 해결: y가 변한 객체만 표시, world의 sort 알고리즘 검토

---

## 4. 서버 측 최적화

### 4.1 Spatial Hash / QuadTree
Phase 6에서 도입. 100명 N² → N log N 또는 N.

### 4.2 Lock 최소화
- 한 zone 안에서는 단일 goroutine tick → 락 자체 없음
- 락이 보이면 설계가 잘못된 것

### 4.3 메모리 할당 최소화
- Go에서 매 tick `make([]byte, 1024)` → GC 폭발
- `sync.Pool` 사용
- **Go 1.26 Green Tea GC**(2026-02-10 정식, **기본 활성화**): small object(≤ 512B)를 8KiB span 단위로 처리해 마킹/스캐닝의 메모리 지역성(locality)과 CPU 확장성을 개선합니다. span은 정확히 8KiB 크기·정렬입니다(설계 이슈 [golang/go#73581](https://github.com/golang/go/issues/73581)). 게임서버처럼 small object를 매 tick 대량 생성하는 워크로드에 즉시 효과가 있으며, 별도 설정 없이 1.26 이상으로 빌드하면 적용됩니다.
  - **수치 정정**: Go 공식 릴리스 노트의 표현은 "**GC를 많이 쓰는 실세계 프로그램에서 GC 오버헤드 10~40% 감소**"입니다(pause/throughput를 분리해 명시하지 않음). 기존 문서의 "pause 최대 40%↓ + throughput 10~15%↑"는 InfoWorld·byteiota 같은 **2차 출처의 정리**이므로, 공식 표현인 "GC 오버헤드 10~40% 감소"를 기준으로 삼으세요.
  - **신형 CPU 추가 이득**: Intel Ice Lake / AMD Zen 4 이상에서는 small object 스캔에 **vector instruction**을 활용해 추가로 **약 10%** 더 개선됩니다.
  - **cgo**: cgo 호출의 기본 런타임 오버헤드가 **약 30% 감소**(공식 명시).
- **`goroutineleak` 프로파일 (1.26 신규, 실험적)**: 채널/뮤텍스에 영구 블록된 goroutine을 탐지합니다. Zone Server의 goroutine 누수 진단에 유용합니다. 단 **기본 비활성**이라 빌드 시 `GOEXPERIMENT=goroutineleakprofile` 플래그가 필요하며, `runtime/pprof`의 `goroutineleak` 프로파일 또는 `net/http/pprof`의 `/debug/pprof/goroutineleak`로 접근합니다(1.27 기본화 목표).
- 추가: 컴파일러가 일부 slice backing store를 스택에 할당하는 경우를 확대해 힙 할당 자체를 더 줄입니다.
- 참고: Green Tea GC 자체의 도입은 **1.26.0**(2026-02-10)이며, `server-architecture.md`가 기준으로 쓰는 **1.26.3**(2026-05-07)은 1.26 계열 최신 보안 패치입니다.
- 출처: https://go.dev/doc/go1.26 , https://go.dev/blog/greenteagc

### 4.4 Delta Compression
- entity가 멈춰 있으면 송신 안 함 (last sent 비교)
- 이동 중에도 변경된 필드만

### 4.5 Bit Packing
- 시간 (32비트 unix) → 16비트 (시작 시각 기준 offset)
- direction enum (8개) → 3비트
- → Protobuf, FlatBuffers 또는 자체 비트 스트림

### 4.6 Snapshot Rate — LOD for Network
거리(또는 AoI 관심도)에 따라 **갱신 빈도와 정밀도를 함께 낮추는** 것이 네트워크 LOD입니다.

| 대상 | 갱신 빈도 | 비고 |
|---|---|---|
| 본인(로컬 플레이어) | 30Hz | 예측·보정 대상이라 가장 자주 |
| 시야 내 가까운 entity | 30Hz | 보간 품질 유지 |
| 시야 내 먼 entity | 10Hz | 위치만, 애니메이션 상태는 생략 가능 |
| 시야 가장자리 | 5Hz | extrapolation으로 메움 |
| AoI(관심영역) 밖 | 0Hz | 아예 송신 안 함 (Phase 6 grid/9-cell AoI와 직결) |

추가로 빈도뿐 아니라 **데이터 정밀도(quantization)** 도 LOD로 낮춥니다:
- 먼 entity는 좌표를 16비트 고정소수점으로 양자화(§4.5 Bit Packing), 회전은 8비트, 애니메이션 프레임 인덱스는 생략.
- 빈도를 낮춘 entity는 클라이언트에서 **보간(interpolation) 또는 외삽(extrapolation)** 으로 시각적 부드러움을 유지하므로, 송신량을 줄여도 체감 품질 손실이 작습니다.
- 이 LOD는 §5.2 모바일 발열과도 직결됩니다 — 송신 패킷 수가 줄면 셀룰러 라디오 활성 시간이 줄어 발열·배터리가 개선됩니다.

### 4.7 Tick 비용 측정
```go
start := time.Now()
s.tick()
elapsed := time.Since(start)
if elapsed > 20*time.Millisecond {
    log.Warnf("slow tick: %v", elapsed)
}
```
33ms tick interval에서 한 tick이 20ms 넘으면 위험.

---

## 5. 모바일 특화

### 5.1 배터리
- 화면 꺼져도 60Hz 돌리면 안 됨. 백그라운드 진입 시 tick 정지.
- `WidgetsBindingObserver.didChangeAppLifecycleState`로 `AppLifecycleState.paused`/`inactive`/`hidden`을 감지해 게임 루프(`pauseEngine()`)와 네트워크 송신을 함께 멈춥니다. 포그라운드 복귀(`resumed`) 시 `resumeEngine()` + 서버 재동기화(snapshot 재요청 + clock 재동기).
- 비전투/메뉴 화면처럼 정적인 장면에서는 굳이 60fps를 유지할 필요가 없습니다. **적응형 프레임레이트**로 메뉴·맵 화면은 30fps로 낮추면 GPU/CPU 클럭이 내려가 배터리를 아낍니다(전투 진입 시 60fps 복귀).
- Impeller(§2.5)는 셰이더 사전 컴파일로 첫 프레임 지터 시 발생하던 CPU 스파이크가 줄어, 그만큼 순간 전력 피크도 완화됩니다.

### 5.2 발열
- 4G/5G **무선 통신(라디오)** 이 발열·전력의 큰 비중을 차지합니다. 패킷을 자주, 잘게 보내면 라디오가 idle로 내려가지 못해(RRC connected 유지) 전력을 계속 씁니다. 따라서 **Snapshot rate(§4.6)와 송신 빈도 조정**이 발열 제어의 핵심입니다.
- 작은 패킷을 여러 번 보내는 대신 **묶어서(coalescing) 보내고**, 변경 없는 entity는 송신 생략(§4.4 Delta Compression)하면 라디오 활성 시간이 줄어 발열·배터리 모두 개선됩니다.
- 지속 고부하(고사양 이펙트 풀 가동 + 고프레임레이트)는 SoC thermal throttling을 유발해 오히려 프레임이 더 떨어집니다. `GraphicsTier`(§5.3)로 발열 상한을 설계에 반영하세요.

### 5.3 다양한 디바이스
- 저사양: 30fps lock + 단순 셰이더
- 고사양: 60fps + 이펙트 full

```dart
class GraphicsTier { static const low=0, mid=1, high=2; }
int currentTier = _detectTier();   // 디바이스 모델 / RAM 기준
```

### 5.4 패킷 손실 대응
- 모바일 셀룰러 환경은 패킷 loss 5~10% 흔함
- UDP + Reliable layer (KCP, ENet) 또는 message retry

---

## 6. 실습 — 부하 테스트

### 6.1 봇 클라이언트
```go
// 100개 봇 동시 접속, 랜덤 이동
for i := 0; i < 100; i++ {
    go func(id int) {
        c := connect()
        for {
            c.send(InputMsg{Dx: rand.Float()-0.5, Dy: rand.Float()-0.5})
            time.Sleep(33 * time.Millisecond)
        }
    }(i)
}
```

### 6.2 측정 지표
- 서버: tick time, CPU, RAM, goroutine 수, GC pause
- 클라 (실제 디바이스): FPS, 메모리, 통신량
- 패킷: 평균 size, 초당 메시지 수

### 6.3 목표
- 30+ 동시 접속, 평균 tick < 10ms
- 모바일 (중급 안드로이드) 안정 60fps
- 패킷 손실 5% 인공 추가 시에도 게임 진행 가능

---

## 7. 시니어가 빠지기 쉬운 함정

### 7.1 "추측으로 최적화"
- 측정 없이 손대지 마세요. 실제 병목은 항상 예상과 다릅니다.

### 7.2 "Atlas 한 번에 다 합침"
- 한 atlas가 4096×4096 넘으면 일부 GPU에서 못 받음. 2048 또는 4096 안에서 분할.

### 7.3 "Pool로 모든 객체"
- 코드 복잡도 폭발. 매 프레임 만들어지는 것만 Pool. 일회성은 그냥 new.

### 7.4 "Culling으로 다 안 그림"
- update까지 막으면 게임 로직이 멈춤. **render만** skip.

### 7.5 "Delta Compression이 복잡해서 미룸"
- Phase 6 끝나면 즉시 도입. 안 하면 30명에서 트래픽 폭발.

### 7.6 "서버 CPU 80% 찍히는데 OK"
- 트래픽 스파이크 시 즉사. 평소 30~40% 유지.

### 7.7 "리얼타임 모니터링 안 두고 출시"
- 사고 나면 원인 파악 불가. Phase 8에서 필수.

### 7.8 "Dart는 느려서 한계"
- Dart는 충분히 빠릅니다. 99%는 코드 구조 문제.

---

## 8. 이 Phase에서 도입할 Flame 공식 패키지

| 패키지 | 용도 | 코멘트 |
|---|---|---|
| **`flame_test`** | 부하/회귀 테스트, 결정론 검증 | Phase 2부터 사용 중. Phase 7에선 성능 회귀 회피용 |
| **`flame_fire_atlas`** *또는* **`flame_texturepacker`** | 스프라이트 atlas (Phase 3에서 도입 미뤘다면 여기서 필수) | draw call 감소 효과 가장 큼 |
| ⚠️ **`flame_isolate`** (신중) | 무거운 클라 계산 격리 (path-finding 등) | **Web 미지원**. mob마다 mixin 금지 — 단일 manager Component 에만. 본 코스에선 서버가 무거운 계산 담당하므로 사용 빈도 낮음 |

```yaml
dependencies:
  flame_fire_atlas: ^1.8.17
  # 또는 flame_texturepacker: ^5.1.1

  # 측정 후 정말 필요한 경우만:
  flame_isolate: ^0.6.2+22
```

> ⚠️ `flame_isolate`는 측정 후 필요할 때만. 추측 도입은 isolate 폭증으로 오히려 느려집니다.

---

## 9. 최신 참고 출처

- Flutter DevTools performance: https://docs.flutter.dev/tools/devtools/performance
- Flutter Impeller 렌더러 현황: https://docs.flutter.dev/perf/impeller
- Flame CHANGELOG (ComponentPool / SpriteBatch bleed / HasAutoBatchedChildren 등 버전 확인): https://github.com/flame-engine/flame/blob/main/packages/flame/CHANGELOG.md
- Flame 공식 패키지 버전표: [flame-official-packages.md](./flame-official-packages.md)
- TexturePacker docs: https://www.codeandweb.com/texturepacker/documentation
- Go pprof: https://pkg.go.dev/net/http/pprof
- Go 1.26 릴리스 노트(Green Tea GC / cgo / goroutineleak): https://go.dev/doc/go1.26
- Green Tea GC 설계·해설: https://go.dev/blog/greenteagc
- 전체 그래픽/서버 최적화 출처: [resources.md §0.2](./resources.md), [resources.md §0.3](./resources.md)

> 본 코스의 전체 패키지 카탈로그는 [flame-official-packages.md](./flame-official-packages.md) 참조.

---

## 10. 학습 자료

- Flutter Performance: https://docs.flutter.dev/perf
- "Game Engine Architecture" (Jason Gregory) — 시니어가 평생 곁에 둘 책
- pprof (Go), perf (Linux), Instruments (macOS)
- "1 Billion Updates Per Second" — ECS / DoD 검색

---

## 11. 학습 후 메모 (직접 작성)

- 가장 큰 효과를 본 최적화:
- 측정 결과 의외였던 병목:
- 본인 게임에서 포기한 최적화와 이유:

---

## 12. 다음 단계

[08-phase8-live-service.md](./08-phase8-live-service.md) — 게임을 만든 것과 운영하는 것은 다릅니다. 라이브 서비스의 도구와 프로세스를 다룹니다.
