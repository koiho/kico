# data_generation

cargo run --manifest-path core/data_generation/Cargo.toml -- \
  --neutral-dir core/dataset/cold_start \
  --output-dir core/dataset/cold_start_generated \
  --image-size 256 \
  --samples-per-image 4 \
  --val-ratio 0.1 \
  --seed 42

这个目录现在是一个独立的 Rust 冷启动数据生成器。

它会自动完成下面这些事：

- 读取 `neutral_dir` 下 app 导出的 capture folder
  - `neutral_preview.png`
  - `neutral_linear.rgba16f.bin`
  - `neutral_linear.rgba16f.json`
  - `mask_bundle.npz`
- 自动采样全量 `100 params + 11 gates`
- 调用 `render` crate 的渲染接口生成 reference 图
- 用 `neutral_linear.rgba16f.bin` 作为 renderer 输入
- 输出 `refs / previews / masks / labels / metadata`
- 自动写 `train_manifest.csv` 和 `val_manifest.csv`
  - manifest 会额外带上 `neutral_image_path`

当前阶段它只做一件事：

- 冷启动自举数据生成
- 不做 cross-scene pairing
- 不做 source style transfer augmentation

这意味着它的作用更偏向：

- 先教模型学会 renderer 参数空间
- 先学会 `(reference, neutral, mask) -> params` 这件事本身

但它还不是最终的真实用户参考图训练集，因为这里的 `reference`
仍然来自当前 capture 自己的 `neutral_linear.rgba16f.bin`，不覆盖
“用户拿另一张完全不同场景照片当参考图”的情况。

单个训练样本的语义是：

- `target neutral`
  - 当前 capture 的 `neutral_preview.png`
- `target mask`
  - 当前 capture 的 `mask_bundle.npz`
- `reference`
  - 用当前 capture 自己的 `neutral_linear.rgba16f.bin`
  - 配合本次随机采样出来的 `params + gates`
  - 经过 renderer 渲染出来的参考图
- `label`
  - 就是这次渲染时使用的同一组 `renderer_params + module_gates`

也就是训练输入输出关系：

- `(reference, target_neutral, target_mask) -> target_params_and_gates`

## 运行方式

在 `data_generation` 目录下执行：

```powershell
cargo run -- `
  --neutral-dir C:\path\to\neutral_images `
  --output-dir C:\path\to\generated_dataset `
  --image-size 256 `
  --samples-per-image 4 `
  --val-ratio 0.1 `
  --seed 42
```

也可以直接：

```powershell
cargo run -- --neutral-dir C:\path\to\neutral_images --output-dir C:\path\to\generated_dataset --image-size 256 --samples-per-image 4 --val-ratio 0.1 --seed 42
```

## neutral_dir 应该放什么

推荐直接指向 app 导出的采集根目录，例如：

```text
NeutralExports/
  20260404_120001_wide_xxxxxx/
    neutral_preview.png
    neutral_linear.rgba16f.bin
    neutral_linear.rgba16f.json
    mask_bundle.npz
  20260404_120145_wide_xxxxxx/
    neutral_preview.png
    neutral_linear.rgba16f.bin
    neutral_linear.rgba16f.json
    mask_bundle.npz
```

这样 `data_generation` 会：

- 用 `neutral_preview.png` 生成训练 manifest 里的 `neutral_preview_path`
- 用 `neutral_linear.rgba16f.bin` 生成训练 manifest 里的 `neutral_image_path`
- 用 `neutral_linear.rgba16f.json` 读取线性 payload 的真实宽高
- 用 `mask_bundle.npz` 直接生成训练 mask
- 用 `neutral_linear.rgba16f.bin` 去喂 renderer 生成 reference 图

现在不再支持旧的普通图片 fallback。旧 capture 如果缺少
`neutral_linear.rgba16f.json`，只有在 preview 和 payload 本来就是同分辨率时才会兼容读取。

## 输出结构

```text
output/
  refs/
  previews/
  masks/
  labels/
  metadata/
  train_manifest.csv
  val_manifest.csv
  generation_summary.json
```

其中：

- `refs/`
  - 由当前 capture 自身的 `neutral_linear.rgba16f.bin` 渲染出来的参考图
  - 默认导出为 `jpg`，刻意更接近后续真实参考图的压缩分布
- `previews/`
  - 当前 capture 的 neutral preview
  - 继续保留为 `png`，尽量不额外引入输入端压缩失真
- `masks/`
  - `.npz` 五通道 mask
- `labels/`
  - `renderer_params + module_gates`
- `metadata/`
  - 仅用于追溯采样过程：style code、control jitter、capture 路径、场景统计、物理参数

## 对接训练

生成完成后，可以直接把 manifest 喂给当前训练脚本。

例如：

```powershell
python -m model.main.train `
  --manifest C:\path\to\generated_dataset\train_manifest.csv `
  --val-manifest C:\path\to\generated_dataset\val_manifest.csv `
  --output-dir C:\path\to\checkpoints
```

因为 manifest 已经包含 `label_json_path`，训练时不一定要单独传 `labels_dir`。
