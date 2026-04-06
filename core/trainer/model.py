from __future__ import annotations

from dataclasses import dataclass

import timm
import torch
from torch import Tensor, nn
from torch.nn import functional as F

try:
    from .contract import (
        FACE_PARAM_DIM,
        FOREGROUND_PARAM_DIM,
        GLOBAL_COLOR_DIM,
        GLOBAL_TONE_DIM,
        MASK_DIM,
        OPTICS_ATMOSPHERE_DIM,
        OUTPUT_FINISH_DIM,
        PERSON_PARAM_DIM,
        SECTOR_COLOR_DIM,
        TEXTURE_SURFACE_DIM,
        TONAL_PARAM_DIM,
        TOTAL_PARAMETER_DIM,
        parameter_is_bipolar,
    )
except ImportError:  # pragma: no cover
    from contract import (
        FACE_PARAM_DIM,
        FOREGROUND_PARAM_DIM,
        GLOBAL_COLOR_DIM,
        GLOBAL_TONE_DIM,
        MASK_DIM,
        OPTICS_ATMOSPHERE_DIM,
        OUTPUT_FINISH_DIM,
        PERSON_PARAM_DIM,
        SECTOR_COLOR_DIM,
        TEXTURE_SURFACE_DIM,
        TONAL_PARAM_DIM,
        TOTAL_PARAMETER_DIM,
        parameter_is_bipolar,
    )


FASTVIT_SA24_EMBED_DIMS = (64, 128, 256, 512)
IMAGENET_RGB_MEAN = (0.485, 0.456, 0.406)
IMAGENET_RGB_STD = (0.229, 0.224, 0.225)


@dataclass(slots=True)
class StyleParamOutput:
    params: Tensor
    gates: Tensor


@dataclass(slots=True)
class StyleParamNetConfig:
    image_size: int = 256
    embedding_dim: int = 512
    fusion_dim: int = 256
    hidden_dim: int = 256
    dropout: float = 0.1
    backbone_model_name: str = "fastvit_sa24.apple_in1k"
    pretrained_backbone: bool = True
    backbone_checkpoint: str | None = None


class MlpHead(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int, output_dim: int) -> None:
        super().__init__()
        self.linear_1 = nn.Linear(input_dim, hidden_dim)
        self.linear_2 = nn.Linear(hidden_dim, output_dim)

    def forward(self, x: Tensor) -> Tensor:
        return self.linear_2(F.relu(self.linear_1(x)))


class FastVitBackbone(nn.Module):
    def __init__(self, model_name: str, pretrained: bool, checkpoint_path: str | None = None) -> None:
        super().__init__()
        try:
            self.model = timm.create_model(
                model_name,
                pretrained=pretrained,
                checkpoint_path=checkpoint_path,
            )
        except Exception as error:
            if checkpoint_path is not None:
                raise RuntimeError(
                    f"failed to load local backbone checkpoint `{checkpoint_path}`"
                ) from error
            if pretrained:
                raise RuntimeError(
                    "failed to load official pretrained backbone; "
                    "set backbone_checkpoint to a local timm checkpoint or set pretrained_backbone=false"
                ) from error
            raise
        self.output_dim = FASTVIT_SA24_EMBED_DIMS[3]
        self.register_buffer(
            "input_mean",
            torch.tensor(IMAGENET_RGB_MEAN, dtype=torch.float32).reshape(1, 3, 1, 1),
            persistent=False,
        )
        self.register_buffer(
            "input_std",
            torch.tensor(IMAGENET_RGB_STD, dtype=torch.float32).reshape(1, 3, 1, 1),
            persistent=False,
        )

    def normalize_input(self, x: Tensor) -> Tensor:
        mean = self.input_mean.to(device=x.device, dtype=x.dtype)
        std = self.input_std.to(device=x.device, dtype=x.dtype)
        return (x - mean) / std

    def forward_with_feature_map(self, x: Tensor) -> tuple[Tensor, Tensor]:
        x = self.normalize_input(x)
        x = self.model.stem(x)
        x = self.model.stages(x)
        feature_map = x
        pooled = feature_map.mean(dim=(2, 3))
        return pooled, feature_map

    def forward(self, x: Tensor) -> Tensor:
        pooled, _ = self.forward_with_feature_map(x)
        return pooled


class StyleParamNet(nn.Module):
    def __init__(self, config: StyleParamNetConfig) -> None:
        super().__init__()
        if config.embedding_dim != FASTVIT_SA24_EMBED_DIMS[3]:
            raise ValueError("SA24 backbone expects embedding_dim == 512")

        self.config = config
        feature_map_size = max(config.image_size // 32, 1)
        self.ref_encoder = FastVitBackbone(
            config.backbone_model_name,
            config.pretrained_backbone,
            config.backbone_checkpoint,
        )
        self.mask_spatial_pool = nn.AdaptiveAvgPool2d((feature_map_size, feature_map_size))
        self.mask_vector_proj = nn.Linear(config.embedding_dim, config.fusion_dim)
        global_input_dim = config.embedding_dim * 3
        local_input_dim = config.fusion_dim * 2 + config.embedding_dim * 3
        self.global_fusion_1 = nn.Linear(global_input_dim, config.hidden_dim)
        self.global_fusion_2 = nn.Linear(config.hidden_dim, config.fusion_dim)
        self.local_fusion_1 = nn.Linear(local_input_dim, config.hidden_dim)
        self.local_fusion_2 = nn.Linear(config.hidden_dim, config.fusion_dim)
        self.tonal_fusion_1 = nn.Linear(config.fusion_dim * 2, config.hidden_dim)
        self.tonal_fusion_2 = nn.Linear(config.hidden_dim, config.fusion_dim)
        self.atmosphere_fusion_1 = nn.Linear(config.fusion_dim * 3, config.hidden_dim)
        self.atmosphere_fusion_2 = nn.Linear(config.hidden_dim, config.fusion_dim)
        self.texture_fusion_1 = nn.Linear(config.fusion_dim * 3, config.hidden_dim)
        self.texture_fusion_2 = nn.Linear(config.hidden_dim, config.fusion_dim)
        self.tone_head = MlpHead(config.fusion_dim, config.hidden_dim, GLOBAL_TONE_DIM)
        self.color_head = MlpHead(config.fusion_dim, config.hidden_dim, GLOBAL_COLOR_DIM)
        self.sector_head = MlpHead(config.fusion_dim, config.hidden_dim, SECTOR_COLOR_DIM)
        self.face_head = MlpHead(config.fusion_dim, config.hidden_dim, FACE_PARAM_DIM)
        self.person_head = MlpHead(config.fusion_dim, config.hidden_dim, PERSON_PARAM_DIM)
        self.foreground_head = MlpHead(config.fusion_dim, config.hidden_dim, FOREGROUND_PARAM_DIM)
        self.tonal_head = MlpHead(config.fusion_dim, config.hidden_dim, TONAL_PARAM_DIM)
        self.atmosphere_head = MlpHead(config.fusion_dim, config.hidden_dim, OPTICS_ATMOSPHERE_DIM)
        self.texture_head = MlpHead(config.fusion_dim, config.hidden_dim, TEXTURE_SURFACE_DIM)
        self.finish_head = MlpHead(config.fusion_dim, config.hidden_dim, OUTPUT_FINISH_DIM)
        self.sector_gate_head = MlpHead(config.fusion_dim, config.hidden_dim, 1)
        self.face_gate_head = MlpHead(config.fusion_dim, config.hidden_dim, 1)
        self.person_gate_head = MlpHead(config.fusion_dim, config.hidden_dim, 1)
        self.foreground_gate_head = MlpHead(config.fusion_dim, config.hidden_dim, 1)
        self.tonal_gate_head = MlpHead(config.fusion_dim, config.hidden_dim, 1)
        self.atmosphere_gate_head = MlpHead(config.fusion_dim, config.hidden_dim, 4)
        self.texture_gate_head = MlpHead(config.fusion_dim, config.hidden_dim, 2)
        self.dropout = nn.Dropout(config.dropout)

    def two_layer_fusion(self, x: Tensor, linear_1: nn.Linear, linear_2: nn.Linear) -> Tensor:
        x = F.relu(linear_1(x))
        x = self.dropout(x)
        x = linear_2(x)
        return F.relu(x)

    def two_layer_fusion_3d(self, x: Tensor, linear_1: nn.Linear, linear_2: nn.Linear) -> Tensor:
        batch, seq, dim = x.shape
        x = x.reshape(batch * seq, dim)
        x = self.two_layer_fusion(x, linear_1, linear_2)
        return x.reshape(batch, seq, self.config.fusion_dim)

    def build_global_context(self, ref_embedding: Tensor, scene_embedding: Tensor) -> Tensor:
        style_delta = ref_embedding - scene_embedding
        global_inputs = torch.cat([ref_embedding, scene_embedding, style_delta], dim=1)
        return self.two_layer_fusion(global_inputs, self.global_fusion_1, self.global_fusion_2)

    def build_local_features(
        self,
        global_fused: Tensor,
        ref_embedding: Tensor,
        scene_embedding: Tensor,
        scene_feature_map: Tensor,
        mask_tensor: Tensor,
    ) -> tuple[Tensor, Tensor, Tensor, Tensor, Tensor]:
        pooled_masks = self.mask_spatial_pool(mask_tensor)
        mask_vectors = masked_average_pool_tokens(scene_feature_map, pooled_masks)
        batch, _, scene_channels = mask_vectors.shape
        mask_features = self.mask_vector_proj(mask_vectors.reshape(batch * MASK_DIM, scene_channels))
        mask_features = mask_features.reshape(batch, MASK_DIM, self.config.fusion_dim)
        global_seq = repeat_along_seq(global_fused, MASK_DIM)
        ref_seq = repeat_along_seq(ref_embedding, MASK_DIM)
        scene_seq = repeat_along_seq(scene_embedding, MASK_DIM)
        delta_seq = ref_seq - scene_seq
        local_inputs = torch.cat([global_seq, ref_seq, scene_seq, delta_seq, mask_features], dim=2)
        local_features = self.two_layer_fusion_3d(local_inputs, self.local_fusion_1, self.local_fusion_2)
        face_feature = slice_token(local_features, 0)
        person_feature = slice_token(local_features, 1)
        highlight_feature = slice_token(local_features, 2)
        shadow_feature = slice_token(local_features, 3)
        foreground_feature = slice_token(local_features, 4)
        return face_feature, person_feature, highlight_feature, shadow_feature, foreground_feature

    def emit_outputs(
        self,
        global_fused: Tensor,
        face_feature: Tensor,
        person_feature: Tensor,
        highlight_feature: Tensor,
        shadow_feature: Tensor,
        foreground_feature: Tensor,
    ) -> StyleParamOutput:
        tonal_feature = self.two_layer_fusion(
            torch.cat([highlight_feature, shadow_feature], dim=1),
            self.tonal_fusion_1,
            self.tonal_fusion_2,
        )
        atmosphere_feature = self.two_layer_fusion(
            torch.cat([global_fused, highlight_feature, shadow_feature], dim=1),
            self.atmosphere_fusion_1,
            self.atmosphere_fusion_2,
        )
        texture_feature = self.two_layer_fusion(
            torch.cat([global_fused, foreground_feature, shadow_feature], dim=1),
            self.texture_fusion_1,
            self.texture_fusion_2,
        )
        raw_params = torch.cat(
            [
                self.tone_head(global_fused),
                self.color_head(global_fused),
                self.sector_head(global_fused),
                self.face_head(face_feature),
                self.person_head(person_feature),
                self.foreground_head(foreground_feature),
                self.tonal_head(tonal_feature),
                self.atmosphere_head(atmosphere_feature),
                self.texture_head(texture_feature),
                self.finish_head(global_fused),
            ],
            dim=1,
        )
        raw_gates = torch.cat(
            [
                self.sector_gate_head(global_fused),
                self.face_gate_head(face_feature),
                self.person_gate_head(person_feature),
                self.foreground_gate_head(foreground_feature),
                self.tonal_gate_head(tonal_feature),
                self.atmosphere_gate_head(atmosphere_feature),
                self.texture_gate_head(texture_feature),
            ],
            dim=1,
        )
        return StyleParamOutput(params=normalize_params(raw_params), gates=torch.sigmoid(raw_gates))

    def forward_from_backbone_outputs(
        self,
        ref_embedding: Tensor,
        scene_embedding: Tensor,
        scene_feature_map: Tensor,
        mask_tensor: Tensor,
    ) -> StyleParamOutput:
        global_fused = self.build_global_context(ref_embedding, scene_embedding)
        local_features = self.build_local_features(
            global_fused,
            ref_embedding,
            scene_embedding,
            scene_feature_map,
            mask_tensor,
        )
        return self.emit_outputs(global_fused, *local_features)

    def forward(self, ref_image: Tensor, neutral_preview: Tensor, mask_tensor: Tensor) -> StyleParamOutput:
        ref_embedding = self.ref_encoder(ref_image)
        scene_embedding, scene_feature_map = self.ref_encoder.forward_with_feature_map(neutral_preview)
        return self.forward_from_backbone_outputs(
            ref_embedding,
            scene_embedding,
            scene_feature_map,
            mask_tensor,
        )

    def forward_frozen_backbone(self, ref_image: Tensor, neutral_preview: Tensor, mask_tensor: Tensor) -> StyleParamOutput:
        with torch.no_grad():
            ref_embedding = self.ref_encoder(ref_image)
            scene_embedding, scene_feature_map = self.ref_encoder.forward_with_feature_map(neutral_preview)
        return self.forward_from_backbone_outputs(
            ref_embedding,
            scene_embedding,
            scene_feature_map,
            mask_tensor,
        )


def masked_average_pool_tokens(feature_map: Tensor, mask_tensor: Tensor) -> Tensor:
    batch, channels, height, width = feature_map.shape
    feature_flat = feature_map.reshape(batch, channels, height * width)
    pooled = []
    for index in range(MASK_DIM):
        mask = mask_tensor[:, index : index + 1, :, :]
        mask_flat = mask.reshape(batch, 1, height * width)
        numerator = (feature_flat * mask_flat).sum(dim=2)
        denominator = mask_flat.sum(dim=2).reshape(batch, 1) + 1e-6
        pooled.append((numerator / denominator).reshape(batch, 1, channels))
    return torch.cat(pooled, dim=1)


def repeat_along_seq(x: Tensor, seq_len: int) -> Tensor:
    return x.unsqueeze(1).expand(-1, seq_len, -1)


def slice_token(tokens: Tensor, index: int) -> Tensor:
    return tokens[:, index, :]


def normalize_params(raw_params: Tensor) -> Tensor:
    parts = []
    for index in range(TOTAL_PARAMETER_DIM):
        value = raw_params[:, index : index + 1]
        if parameter_is_bipolar(index):
            value = (torch.tanh(value) + 1.0) / 2.0
        else:
            value = torch.sigmoid(value)
        parts.append(value)
    return torch.cat(parts, dim=1)
