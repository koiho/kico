use thiserror::Error;

pub type RenderResult<T> = Result<T, RenderError>;

#[derive(Debug, Error)]
pub enum RenderError {
    #[error("missing required mask: {0}")]
    MissingMask(&'static str),
    #[error("non-finite value in {what} at index {index}")]
    NonFiniteInput { what: &'static str, index: usize },
    #[error("length mismatch for {what}: expected {expected}, got {actual}")]
    LengthMismatch {
        what: &'static str,
        expected: usize,
        actual: usize,
    },
    #[error(
        "image or mask size mismatch: expected {expected_width}x{expected_height}, got {actual_width}x{actual_height}"
    )]
    SizeMismatch {
        expected_width: u32,
        expected_height: u32,
        actual_width: u32,
        actual_height: u32,
    },
    #[error("invalid working format")]
    InvalidWorkingFormat,
    #[error("gpu submit or poll failed: {0}")]
    GpuExecution(String),
}
