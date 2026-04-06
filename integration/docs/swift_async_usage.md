# Swift Async Usage

## Recommendation

Keep the Rust/UniFFI pipeline itself synchronous, but wrap it in a long-lived Swift `actor`.

This gives you the behavior we want during capture:

- the ONNX model is loaded once and reused
- calls are serialized through one shared pipeline instance
- camera/UI code can `await` the actor instead of blocking the main thread

## Why not force Rust-side async first

The current Rust work is CPU/GPU-bound synchronous work:

1. resize image and masks
2. run ONNX inference
3. render final output

Making the UniFFI export itself `async` would not automatically make this work non-blocking unless we also add a dedicated Rust async runtime or background worker layer.

For the current app shape, Swift-side async orchestration is the simpler and safer option.

## Recommended shape

1. Create one shared `PhotoStylePipeline` actor when the camera feature starts.
2. Reuse that actor for every capture.
3. Call it from `Task(priority: .userInitiated)` or another background async path.
4. Hop back to `MainActor` only when updating UI.

See: [OnnxRenderPipelineClient.swift](/Users/taodai/Desktop/code/Kico/app/integration/docs/OnnxRenderPipelineClient.swift)
