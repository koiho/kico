# 渲染模型输出映射表

这份文档是 [`src/pipeline/model_mapping.rs`](/Users/taodai/Desktop/code/Kico/app/ml/render/src/pipeline/model_mapping.rs) 的中文可读版，用来快速对齐模型输出、stage、uniform 和 GPU pass。

## 总览

- 参数数量：100
- Gate 数量：11
- Mask 数量：5
- Stage 数量：12
- 顶层 Stage 调用数量：12
- 实际 GPU 子 pass 数量：大于 12，尤其 `mask_prep / bloom / halation / lens_character` 都会展开成多个内部 pass

## 关键说明

- 参数顺序大体按 stage 分组，但并不是所有 stage 都是连续区间。
- `exposure_wb` 对应的参数索引是 `[0, 12, 13]`，不是一个连续段。
- `mask_prep` 现在直接消费 `65..68` 这 4 个 tonal mask 形状参数，用来控制高光 / 阴影 mask 的阈值和羽化。
- `pass_schedule.rs` 里的 9 个 pass 描述是“逻辑 pass 家族”，不是当前运行时的真实 GPU 提交次数。
- 当前运行时没有把 `exposure_wb + global_tone` 真正融合成一个 pass，也没有把 `global_color + sector_color` 真正融合成一个 pass。
- `output_finish` 只负责渲染器域内的最终收尾，最终的传输函数转换和文件落盘仍然交给原生层处理。

## Stage 到 Pass 的映射

| Stage | 分组 | 参数索引 | Gate 索引 | 使用的 Mask | Uniform 包 | GPU Pass |
| --- | --- | --- | --- | --- | --- | --- |
| `mask_prep` | `input` | `[65..68]` | `-` | `face, person, highlight, shadow, foreground_subject` | `-` | `-` |
| `exposure_wb` | `global` | `[0, 12, 13]` | `-` | `-` | `exposure_wb_tone.exposure_wb` | `pass_1_exposure_wb` |
| `global_tone` | `global` | `[1..11]` | `-` | `-` | `exposure_wb_tone.tone_a/tone_b/tone_c` | `pass_1_global_tone` |
| `global_color` | `global` | `[14..26]` | `-` | `-` | `global_color_sector.global_a/global_b/split_*` | `pass_2_global_color` |
| `sector_color` | `global` | `[27..46]` | `[0]` | `-` | `global_color_sector.red..sector_shared` | `pass_2_sector_color` |
| `semantic_local` | `local` | `[47..64]` | `[1..4]` | `face, person, highlight, shadow, foreground_subject` | `semantic_local.*` | `pass_3_semantic_local` |
| `bloom` | `optical` | `[69..73]` | `[5]` | `-` | `bloom.params/gate` | `pass_4_bloom_*` |
| `halation` | `optical` | `[74..79]` | `[6]` | `-` | `halation.params_a/params_b` | `pass_5_halation_*` |
| `lens_character` | `optical` | `[84..85]` | `[8]` | `-` | `vignette_lens.lens` | `pass_6_lens_character_*` |
| `vignette` | `optical` | `[80..83]` | `[7]` | `-` | `vignette_lens.vignette` | `pass_7_vignette` |
| `texture_grain` | `output` | `[86..94]` | `[9, 10]` | `-` | `texture_finish.grain_a/grain_b/texture` | `pass_8_texture_grain` |
| `output_finish` | `output` | `[95..99]` | `-` | `-` | `texture_finish.finish` | `pass_9_output_finish` |

## 参数区段总表

| 索引区间 | 参数名 | 所属 Stage | Uniform 包 | GPU Pass |
| --- | --- | --- | --- | --- |
| `[0, 12, 13]` | `exposure_ev`, `wb_r_gain`, `wb_b_gain` | `exposure_wb` | `exposure_wb_tone` | `pass_1_exposure_wb` |
| `[1..11]` | `contrast`, `contrast_pivot`, `blacks`, `whites`, `shadows`, `highlights`, `toe_strength`, `shoulder_strength`, `fade`, `midtone_boost`, `clarity_global` | `global_tone` | `exposure_wb_tone` | `pass_1_global_tone` |
| `[14..26]` | `global_saturation`, `global_vibrance`, `global_hue_shift`, `color_density`, `warmth_bias`, `green_magenta_bias`, `shadow_hue`, `shadow_sat`, `midtone_hue`, `midtone_sat`, `highlight_hue`, `highlight_sat`, `split_balance` | `global_color` | `global_color_sector` | `pass_2_global_color` |
| `[27..46]` | `red_hue_shift`, `red_sat_scale`, `red_luma_shift`, `yellow_hue_shift`, `yellow_sat_scale`, `yellow_luma_shift`, `green_hue_shift`, `green_sat_scale`, `green_luma_shift`, `cyan_hue_shift`, `cyan_sat_scale`, `cyan_luma_shift`, `blue_hue_shift`, `blue_sat_scale`, `blue_luma_shift`, `magenta_hue_shift`, `magenta_sat_scale`, `magenta_luma_shift`, `sector_width_scale`, `sector_smoothness` | `sector_color` | `global_color_sector` | `pass_2_sector_color` |
| `[47..64]` | `face_exposure`, `face_sat`, `face_hue_shift`, `face_warmth`, `face_soft_clarity`, `person_exposure`, `person_sat`, `person_hue_shift`, `person_clarity`, `foreground_subject_hue_shift`, `foreground_subject_sat`, `foreground_subject_luma`, `foreground_subject_exposure`, `foreground_subject_contrast`, `foreground_subject_pop`, `highlight_warmth_local`, `shadow_tint_local`, `shadow_desat` | `semantic_local` | `semantic_local` | `pass_3_semantic_local` |
| `[65..68]` | `highlight_mask_threshold`, `highlight_mask_feather`, `shadow_mask_threshold`, `shadow_mask_feather` | `mask_prep` | `-` | `-` |
| `[69..73]` | `bloom_threshold`, `bloom_intensity`, `bloom_radius`, `bloom_softness`, `bloom_veil_mix` | `bloom` | `bloom` | `pass_4_bloom` |
| `[74..79]` | `halation_threshold`, `halation_intensity`, `halation_radius`, `halation_red_bias`, `halation_warmth`, `halation_core_balance` | `halation` | `halation` | `pass_5_halation` |
| `[84..85]` | `soft_glow`, `edge_softness` | `lens_character` | `vignette_lens` | `pass_6_lens_character_*` |
| `[80..83]` | `vignette_amount`, `vignette_midpoint`, `vignette_feather`, `vignette_roundness` | `vignette` | `vignette_lens` | `pass_7_vignette` |
| `[86..94]` | `grain_luma_amount`, `grain_chroma_amount`, `grain_size`, `grain_shadow_bias`, `grain_highlight_suppress`, `texture_boost`, `noise_clean_bias`, `detail_preserve`, `texture_microcontrast_balance` | `texture_grain` | `texture_finish` | `pass_8_texture_grain` |
| `[95..99]` | `gamut_compress`, `final_gamma_bias`, `highlight_clip_softness`, `highlight_rolloff_pivot`, `shadow_floor` | `output_finish` | `texture_finish` | `pass_9_output_finish` |

## Gate 索引总表

| 索引 | Gate 名 | 所属 Stage | Uniform 包 | GPU Pass |
| --- | --- | --- | --- | --- |
| 0 | `sector_color_gate` | `sector_color` | `global_color_sector` | `pass_2_global_color_sector` |
| 1 | `face_gate` | `semantic_local` | `semantic_local` | `pass_3_semantic_local` |
| 2 | `person_gate` | `semantic_local` | `semantic_local` | `pass_3_semantic_local` |
| 3 | `foreground_subject_gate` | `semantic_local` | `semantic_local` | `pass_3_semantic_local` |
| 4 | `tonal_local_gate` | `semantic_local` | `semantic_local` | `pass_3_semantic_local` |
| 5 | `bloom_gate` | `bloom` | `bloom` | `pass_4_bloom` |
| 6 | `halation_gate` | `halation` | `halation` | `pass_5_halation` |
| 7 | `vignette_gate` | `vignette` | `vignette_lens` | `pass_7_vignette` |
| 8 | `lens_character_gate` | `lens_character` | `vignette_lens` | `pass_6_lens_character_*` |
| 9 | `grain_gate` | `texture_grain` | `texture_finish` | `pass_8_texture_grain` |
| 10 | `texture_gate` | `texture_grain` | `texture_finish` | `pass_8_texture_grain` |

## Mask 说明

| Mask | 典型来源 | 消费方 |
| --- | --- | --- |
| `face` | 分析阶段 / 原生分割 | `mask_prep`, `semantic_local` |
| `person` | 分析阶段 / 原生分割 | `mask_prep`, `semantic_local` |
| `highlight` | 分析阶段 / 亮度逻辑 | `mask_prep`, `semantic_local` |
| `shadow` | 分析阶段 / 亮度逻辑 | `mask_prep`, `semantic_local` |
| `foreground_subject` | 分析阶段 / 原生主体提取 | `mask_prep`, `semantic_local` |
