# AGENTS.md

Guidance for AI coding agents working on this repository.

## Project Overview

**NahidaRenderProject** is a Unity sample project that demonstrates toon-style
rendering of Genshin Impact characters (primarily Nahida, with a Furina variant
added later). It is a rendering/shader showcase, not a game — there is no
gameplay logic, no builds, and no tests.

- **Unity version:** 2022.3.62f3c1 (any 2022.3 LTS should work; see
  `ProjectSettings/ProjectVersion.txt`)
- **Render pipeline:** Universal Render Pipeline (URP) 14.0.12
  (`Packages/manifest.json`)
- **License:** MIT (© 2023 风澪瑟)
- **Language:** C# (runtime MonoBehaviours) + ShaderLab/HLSL

Derived from two reference projects:
- [UnityGenshinToonShader](https://github.com/kaze-mio/UnityGenshinToonShader)
- [UnityGenshinPostProcessing](https://github.com/kaze-mio/UnityGenshinPostProcessing)

## Build and Run

There is no command-line build, test suite, or CI. Development is done entirely
in the Unity Editor:

1. Open the project with Unity Hub using Unity **2022.3** (Editor version is
   pinned in `ProjectSettings/ProjectVersion.txt`).
2. Unity auto-imports assets and regenerates `Library/`, `*.csproj`, and
   `NahidaRenderProject.sln` (all git-ignored; do not commit them).
3. Open `Assets/Scenes/SampleScene.unity` (or `Assets/Furina/Furina.unity`)
   and press **Play**. In Play mode the `FirstPersonController` on the camera
   allows WASD movement, mouse look, Q/E elevation, and Esc to unlock the
   cursor.

Verification of changes = the project compiles in the Editor (check the
Console for C# and shader errors) and the scene renders correctly in Play mode.
The `com.unity.test-framework` package is present by default but **no tests
exist** in this repository.

## Repository Layout

Only `Assets/`, `Packages/`, and `ProjectSettings/` are source-controlled
project content (plus `Images/`, `README.md`, `LICENSE`).

| Path | Contents |
| --- | --- |
| `Assets/Scripts/` | C# runtime scripts (all gameplay-agnostic utilities) |
| `Assets/Scripts/Editor/` | Editor tools (`Nahida.Editor` namespace, e.g. one-click post-processing setup) |
| `Assets/Scripts/Rendering/` | URP post-processing framework (`Nahida.Rendering` namespace) |
| `Assets/Shaders/GenshinToon/` | `URPGenshinToon` toon shader + HLSL includes |
| `Assets/Shaders/Character/` | `Character` shader — copy of `URPGenshinToon` with two stackable shadow features: screen-space bangs shadow (`_RECEIVE_SHADOWS`, face-only, samples `_HairMaskTexture` from `HairShadowFeature`; `CharacterHairShadowPass.hlsl` writes the mask, hair materials set `_HairShadowCaster`) and a dedicated character shadow map (`_RECEIVE_SHADOW_MAP`, samples `_CharacterShadowMap` from `CharacterShadowMap.cs`; `CharacterShadowDepth.shader` writes depth); used by the Odette materials |
| `Assets/Shaders/Gem/` | `URPGem` faceted gem shader + HLSL includes |
| `Assets/Shaders/PostProcessing/` | `URPGenshinPostProcess` fullscreen post-processing shader |
| `Assets/Materials/` | Materials: `Nahida/`, `NahidaMMD/`, plus scene materials |
| `Assets/Models/` | Nahida FBX models (`Avatar_Loli_Catalyst_Nahida.fbx`, `Nahida_MMD.fbx`) |
| `Assets/Furina/` | Furina character: FBX, textures, scene, prefab, `Material/` (Chinese names, e.g. `体.mat`, `裙.mat`) |
| `Assets/Avatar_Girl_Sword_Odette/` | Odette character: FBX + textures, `Material/` (`Odette_*.mat`, remapped via the FBX importer's `externalObjects`) |
| `Assets/Textures/` | Character texture sets (`Avatar/`, `Nahida/`, `Scene/`) |
| `Assets/Meshes/` | `Nahida_Body_Smooth.mesh` (smoothed-normal mesh used for outline extrusion) |
| `Assets/Scenes/` | `SampleScene.unity` + `SceneRoot.prefab` |
| `Assets/URPSettings/` | URP asset, renderer data, and volume profiles |
| `Packages/manifest.json` | Unity package dependencies (URP 14.0.12, IDE integrations, etc.) |
| `ProjectSettings/` | Unity project settings; `ProjectVersion.txt` pins the editor version |

## Architecture / How It Fits Together

The project has two custom rendering systems wired into URP via
`Assets/URPSettings/URPRendererData.asset`:

**1. Toon character shader — `Shader "URPGenshinToon"`** (`Assets/Shaders/GenshinToon/`)

- `ToonInput.hlsl` — shared properties/structs; `ToonForwardPass.hlsl` — main
  shading (`ComputeToonShading` is the reusable core); `ToonOutlinePass.hlsl` —
  inverted-hull outline (`Cull Front`); `ToonBrowShowThroughPass.hlsl` —
  brow show-through hair (眉毛透发) overlay.
- Passes: `Forward` (UniversalForward), `BrowShowThrough`
  (UniversalForwardOnly), plus `ShadowCaster`, `DepthOnly`,
  `DepthNormals` (reusing URP Lit pass includes), and `Outline`
  (`SRPDefaultUnlit`).
- Genshin-style features: lightmap-based stepped shadow with shadow ramp,
  SDF face shadow (uses `_FaceDirection` + face lightmap/shadow textures),
  specular metal map with specular ramp, rim light, emission, normal maps,
  and per-part outline colors (5 slots) with optional smoothed normals.
- Brow/eye show-through (眉毛透发): the `Forward` pass writes `_StencilRef`
  (only hair materials set it to 1, everything else stays 0). Brow and eye
  materials (`Nahida_Brow*`, Furina `眉/目/星目/白目/睫/二重`) enable
  `_BROW_SHOW_THROUGH`; their extra `BrowShowThrough` pass renders after all
  `UniversalForward` passes with `ZTest Greater` + stencil `Equal` against
  `_ShowThroughStencilRef` (default 1), blending the brow/eye
  semi-transparently (`_ShowThroughAlpha`) over bangs only. The overlay alpha
  is faded by view angle (`saturate(dot(N, V))`) and by face orientation
  (`smoothstep(0, 0.3, dot(_FaceDirection, V))` — `_FaceDirection` is written
  every frame by `MaterialUpdater`) so the effect disappears at grazing
  angles and is completely off when the camera is behind the head. Because Furina's eye is a stack of
  layered submeshes, the eye materials use ascending `m_CustomRenderQueue`
  values (白目 2001 → 目 2002 → 二重 2003 → 星目 2004 → 睫 2005 → 眉 2006) so
  the overlays composite back-to-front like proper alpha layers (deepest
  first); without this the eye-white layer would draw last and wash out the
  iris. A scene-depth proximity check (`_ShowThroughMaxDepth`, view-space
  meters) discards pixels where the occluding hair is too far away (e.g.
  back of head), so they never show through distant hair or non-hair
  occluders — including the eye's own layered submeshes, which write
  stencil 0 and therefore never trigger the overlay on visible eyes.
  (Nahida's eyes are part of the face texture, so only her brow submesh can
  use this; Furina has dedicated eye materials.)
- Face shading needs the head bone direction at runtime: `MaterialUpdater`
  (`Nahida` namespace) computes the direction from a head bone and writes it
  to the `_FaceDirection` vector of the face renderers' materials every frame.

**2. Custom post-processing — `Nahida.Rendering` namespace** (`Assets/Scripts/Rendering/`)

- `PostProcessFeature` (`ScriptableRendererFeature`, added to the URP renderer,
  injects at `BeforeRenderingPostProcessing`) → `PostProcessPass`
  (`ScriptableRenderPass`) → `Shader "URPGenshinPostProcess"`.
- Two custom Volume components (menu: *Custom/Bloom*, *Custom/ColorGrading*):
  `BloomVolume` (4-iteration dual-Kawase-style Gaussian bloom, threshold by
  color or brightness via `BloomMode`, weighted upsample) and
  `ColorGradingVolume` (exposure, optional filmic tonemap, ACEScc contrast,
  saturation). Volume profiles live in `Assets/URPSettings/`.
- The pass allocates `RTHandle` bloom pyramid buffers via
  `RenderingUtils.ReAllocateIfNeeded` and blits with
  `Blitter.BlitCameraTexture`; it skips Preview/Reflection cameras.
- `HairShadowFeature.cs` (`ScriptableRendererFeature`, added to the URP renderer,
  injects at `BeforeRenderingOpaques`): renders the hair mask for the
  screen-space bangs shadow (刘海投影). The pass draws every renderer whose
  shader has a `HairShadowMask` pass (only `Character`, and only materials
  with `_HairShadowCaster = 1` actually emit fragments) into an R16G16 screen
  RT `_HairMaskTexture` — R = hair flag, G = view-space depth in meters. In
  the `Character` shader's face path (`_IS_FACE` + `_RECEIVE_SHADOWS`),
  `GetHairShadow` offsets the screen UV along the view-space light direction
  (scaled by `_HairShadowDistance`, corrected by `1/NDC.w`) and samples the
  mask; a depth check (`_HairShadowDepthBias`) rejects shadows from hair
  behind the head. The result is combined with the SDF face shadow via `min`.
- `CharacterShadowMap.cs` (`ExecuteAlways` MonoBehaviour, on the
  `CharacterShadowMap` object in the Odette scene, target = the Odette FBX
  instance): the alternative **dedicated shadow map** solution. Each
  `LateUpdate` it fits an orthographic frustum to the target along the main
  light direction, draws all renderers under it with
  `Shader "Hidden/Character/ShadowDepth"` into an `RFloat` RT via
  `CommandBuffer.DrawRenderer` (note: the view matrix needs the right-handed
  Z-flip to match `Camera.worldToCameraMatrix`), and publishes the globals
  `_CharacterShadowMap` / `_CharacterShadowMatrix` / `_CharacterShadowBias` /
  `_CharacterShadowMap_TexelSize`. In the `Character` shader the
  `_RECEIVE_SHADOW_MAP` keyword makes `GetCharacterShadowMap` sample it (2x2
  PCF, `min`-combined with the toon/SDF shadow on every material, not just
  the face). It coexists with the screen-space bangs shadow; toggle per
  material via the *Receive Shadow Map* / *Receive Shadows* checkboxes, or
  disable the component / the `HairShadowFeature` to compare. Has a
  `m_DebugView` OnGUI overlay showing the RT and renderer count.

**Utility scripts** (`Assets/Scripts/`):
- `FirstPersonController.cs` — Play-mode fly camera (comments in Chinese).
- `MaterialUpdater.cs`, `TransformRotator.cs` — `Nahida` namespace helpers.

## Code Style Guidelines

- **Namespaces:** rendering code uses `namespace Nahida.Rendering`; other
  shared scripts use `namespace Nahida`. `FirstPersonController` is a later
  addition and has no namespace (legacy).
- **Field naming:** serialized private fields use `m_PascalCase`; other
  private fields use `_camelCase`; public fields/parameters use `camelCase`.
- **Serialized fields:** use `[SerializeField] private` (or the
  `[Header]`/`public` pattern in `FirstPersonController`) instead of public
  fields for new inspector-exposed values.
- **Shaders:** one `.shader` file plus HLSL includes; custom shader features
  use `#pragma shader_feature_local_fragment` keywords toggled by material
  inspector keywords (`_EMISSION`, `_NORMAL_MAP`, `_IS_FACE`, `_SPECULAR`,
  `_RIM`, `_DOUBLE_SIDED`, plus `_BROW_SHOW_THROUGH` which is declared as
  `shader_feature_local` because its vertex stage also branches). Follow the
  existing URP pass/tag conventions when adding passes.
- **Comments/docs:** the project is bilingual — README is English with a
  Chinese subtitle; in-code comments may be in Chinese (see
  `FirstPersonController.cs`). Matching the surrounding language is fine.

## Testing

No automated tests. After changing C# or shader code, let the Editor
recompile and check the Console; then run the scene and visually compare
rendering against the reference images in `README.md` / `Images/`.

## Security & Git Considerations

- `Library/`, `Temp/`, `Logs/`, `obj/`, `UserSettings/`, `*.csproj`, `*.sln`,
  and build artifacts are git-ignored — never commit them.
- Every asset has a `.meta` file that **must** be kept in sync and committed
  alongside its asset; do not delete or rename assets outside the Unity
  Editor (or move the `.meta` with them).
- Character models/textures are ripped game assets (Genshin Impact) for
  non-commercial rendering study — do not redistribute them commercially.
- Scene/prefab/material files are Unity YAML; avoid hand-editing unless you
  understand the format, and never merge them with standard text merge tools.
