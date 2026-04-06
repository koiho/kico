//
//  LightTheme.swift
//  ios
//
//  Created by TAO DAI on 2025/7/30.
//

// MARK: - 浅色主题
/// 浅色主题实现，使用 AppColor 中定义的浅色主题颜色
struct LightTheme: Theme {
    // MARK: - 颜色属性
    /// 主要颜色
    let primary = AppColor.primaryLight
    /// 主要颜色上的内容颜色
    let onPrimary = AppColor.onPrimaryLight
    /// 主要容器颜色
    let primaryContainer = AppColor.primaryContainerLight
    /// 主要容器上的内容颜色
    let onPrimaryContainer = AppColor.onPrimaryContainerLight
    /// 次要颜色
    let secondary = AppColor.secondaryLight
    /// 次要颜色上的内容颜色
    let onSecondary = AppColor.onSecondaryLight
    /// 次要容器颜色
    let secondaryContainer = AppColor.secondaryContainerLight
    /// 次要容器上的内容颜色
    let onSecondaryContainer = AppColor.onSecondaryContainerLight
    /// 第三颜色
    let tertiary = AppColor.tertiaryLight
    /// 第三颜色上的内容颜色
    let onTertiary = AppColor.onTertiaryLight
    /// 第三容器颜色
    let tertiaryContainer = AppColor.tertiaryContainerLight
    /// 第三容器上的内容颜色
    let onTertiaryContainer = AppColor.onTertiaryContainerLight
    /// 错误颜色
    let error = AppColor.errorLight
    /// 错误颜色上的内容颜色
    let onError = AppColor.onErrorLight
    /// 错误容器颜色
    let errorContainer = AppColor.errorContainerLight
    /// 错误容器上的内容颜色
    let onErrorContainer = AppColor.onErrorContainerLight
    /// 背景颜色
    let background = AppColor.onPrimaryLight
    /// 背景上的内容颜色
    let onBackground = AppColor.onBackgroundLight
    /// 表面颜色
    let surface = AppColor.surfaceLight
    /// 表面上的内容颜色
    let onSurface = AppColor.onSurfaceLight
    /// 表面变体颜色
    let surfaceVariant = AppColor.surfaceVariantLight
    /// 表面变体上的内容颜色
    let onSurfaceVariant = AppColor.onSurfaceVariantLight
    /// 轮廓线颜色
    let outline = AppColor.outlineLight
    /// 轮廓线变体颜色
    let outlineVariant = AppColor.outlineVariantLight
    /// 遮罩颜色
    let scrim = AppColor.scrimLight
    /// 反向表面颜色
    let inverseSurface = AppColor.inverseSurfaceLight
    /// 反向表面上的内容颜色
    let inverseOnSurface = AppColor.inverseOnSurfaceLight
    /// 反向主要颜色
    let inversePrimary = AppColor.inversePrimaryLight
    /// 暗淡表面颜色
    let surfaceDim = AppColor.surfaceDimLight
    /// 明亮表面颜色
    let surfaceBright = AppColor.surfaceBrightLight
    /// 最低容器表面颜色
    let surfaceContainerLowest = AppColor.surfaceContainerLowestLight
    /// 低容器表面颜色
    let surfaceContainerLow = AppColor.surfaceContainerLowLight
    /// 容器表面颜色
    let surfaceContainer = AppColor.surfaceContainerLight
    /// 高容器表面颜色
    let surfaceContainerHigh = AppColor.surfaceContainerHighLight
    /// 最高容器表面颜色
    let surfaceContainerHighest = AppColor.surfaceContainerHighestLight

    /// 主要颜色 - 中等对比度
    let primaryMediumContrast = AppColor.primaryLightMediumContrast
    /// 主要颜色上的内容颜色 - 中等对比度
    let onPrimaryMediumContrast = AppColor.onPrimaryLightMediumContrast
    /// 主要容器颜色 - 中等对比度
    let primaryContainerMediumContrast = AppColor.primaryContainerLightMediumContrast
    /// 主要容器上的内容颜色 - 中等对比度
    let onPrimaryContainerMediumContrast = AppColor.onPrimaryContainerLightMediumContrast
    /// 次要颜色 - 中等对比度
    let secondaryMediumContrast = AppColor.secondaryLightMediumContrast
    /// 次要颜色上的内容颜色 - 中等对比度
    let onSecondaryMediumContrast = AppColor.onSecondaryLightMediumContrast
    /// 次要容器颜色 - 中等对比度
    let secondaryContainerMediumContrast = AppColor.secondaryContainerLightMediumContrast
    /// 次要容器上的内容颜色 - 中等对比度
    let onSecondaryContainerMediumContrast = AppColor.onSecondaryContainerLightMediumContrast
    /// 第三颜色 - 中等对比度
    let tertiaryMediumContrast = AppColor.tertiaryLightMediumContrast
    /// 第三颜色上的内容颜色 - 中等对比度
    let onTertiaryMediumContrast = AppColor.onTertiaryLightMediumContrast
    /// 第三容器颜色 - 中等对比度
    let tertiaryContainerMediumContrast = AppColor.tertiaryContainerLightMediumContrast
    /// 第三容器上的内容颜色 - 中等对比度
    let onTertiaryContainerMediumContrast = AppColor.onTertiaryContainerLightMediumContrast
    /// 错误颜色 - 中等对比度
    let errorMediumContrast = AppColor.errorLightMediumContrast
    /// 错误颜色上的内容颜色 - 中等对比度
    let onErrorMediumContrast = AppColor.onErrorLightMediumContrast
    /// 错误容器颜色 - 中等对比度
    let errorContainerMediumContrast = AppColor.errorContainerLightMediumContrast
    /// 错误容器上的内容颜色 - 中等对比度
    let onErrorContainerMediumContrast = AppColor.onErrorContainerLightMediumContrast
    /// 背景颜色 - 中等对比度
    let backgroundMediumContrast = AppColor.onPrimaryLight
    /// 背景上的内容颜色 - 中等对比度
    let onBackgroundMediumContrast = AppColor.onBackgroundLightMediumContrast
    /// 表面颜色 - 中等对比度
    let surfaceMediumContrast = AppColor.surfaceLightMediumContrast
    /// 表面上的内容颜色 - 中等对比度
    let onSurfaceMediumContrast = AppColor.onSurfaceLightMediumContrast
    /// 表面变体颜色 - 中等对比度
    let surfaceVariantMediumContrast = AppColor.surfaceVariantLightMediumContrast
    /// 表面变体上的内容颜色 - 中等对比度
    let onSurfaceVariantMediumContrast = AppColor.onSurfaceVariantLightMediumContrast
    /// 轮廓线颜色 - 中等对比度
    let outlineMediumContrast = AppColor.outlineLightMediumContrast
    /// 轮廓线变体颜色 - 中等对比度
    let outlineVariantMediumContrast = AppColor.outlineVariantLightMediumContrast
    /// 遮罩颜色 - 中等对比度
    let scrimMediumContrast = AppColor.scrimLightMediumContrast
    /// 反向表面颜色 - 中等对比度
    let inverseSurfaceMediumContrast = AppColor.inverseSurfaceLightMediumContrast
    /// 反向表面上的内容颜色 - 中等对比度
    let inverseOnSurfaceMediumContrast = AppColor.inverseOnSurfaceLightMediumContrast
    /// 反向主要颜色 - 中等对比度
    let inversePrimaryMediumContrast = AppColor.inversePrimaryLightMediumContrast
    /// 暗淡表面颜色 - 中等对比度
    let surfaceDimMediumContrast = AppColor.surfaceDimLightMediumContrast
    /// 明亮表面颜色 - 中等对比度
    let surfaceBrightMediumContrast = AppColor.surfaceBrightLightMediumContrast
    /// 最低容器表面颜色 - 中等对比度
    let surfaceContainerLowestMediumContrast = AppColor.surfaceContainerLowestLightMediumContrast
    /// 低容器表面颜色 - 中等对比度
    let surfaceContainerLowMediumContrast = AppColor.surfaceContainerLowLightMediumContrast
    /// 容器表面颜色 - 中等对比度
    let surfaceContainerMediumContrast = AppColor.surfaceContainerLightMediumContrast
    /// 高容器表面颜色 - 中等对比度
    let surfaceContainerHighMediumContrast = AppColor.surfaceContainerHighLightMediumContrast
    /// 最高容器表面颜色 - 中等对比度
    let surfaceContainerHighestMediumContrast = AppColor.surfaceContainerHighestLightMediumContrast

    /// 主要颜色 - 高对比度
    let primaryHighContrast = AppColor.primaryLightHighContrast
    /// 主要颜色上的内容颜色 - 高对比度
    let onPrimaryHighContrast = AppColor.onPrimaryLightHighContrast
    /// 主要容器颜色 - 高对比度
    let primaryContainerHighContrast = AppColor.primaryContainerLightHighContrast
    /// 主要容器上的内容颜色 - 高对比度
    let onPrimaryContainerHighContrast = AppColor.onPrimaryContainerLightHighContrast
    /// 次要颜色 - 高对比度
    let secondaryHighContrast = AppColor.secondaryLightHighContrast
    /// 次要颜色上的内容颜色 - 高对比度
    let onSecondaryHighContrast = AppColor.onSecondaryLightHighContrast
    /// 次要容器颜色 - 高对比度
    let secondaryContainerHighContrast = AppColor.secondaryContainerLightHighContrast
    /// 次要容器上的内容颜色 - 高对比度
    let onSecondaryContainerHighContrast = AppColor.onSecondaryContainerLightHighContrast
    /// 第三颜色 - 高对比度
    let tertiaryHighContrast = AppColor.tertiaryLightHighContrast
    /// 第三颜色上的内容颜色 - 高对比度
    let onTertiaryHighContrast = AppColor.onTertiaryLightHighContrast
    /// 第三容器颜色 - 高对比度
    let tertiaryContainerHighContrast = AppColor.tertiaryContainerLightHighContrast
    /// 第三容器上的内容颜色 - 高对比度
    let onTertiaryContainerHighContrast = AppColor.onTertiaryContainerLightHighContrast
    /// 错误颜色 - 高对比度
    let errorHighContrast = AppColor.errorLightHighContrast
    /// 错误颜色上的内容颜色 - 高对比度
    let onErrorHighContrast = AppColor.onErrorLightHighContrast
    /// 错误容器颜色 - 高对比度
    let errorContainerHighContrast = AppColor.errorContainerLightHighContrast
    /// 错误容器上的内容颜色 - 高对比度
    let onErrorContainerHighContrast = AppColor.onErrorContainerLightHighContrast
    /// 背景颜色 - 高对比度
    let backgroundHighContrast = AppColor.onPrimaryLight
    /// 背景上的内容颜色 - 高对比度
    let onBackgroundHighContrast = AppColor.onBackgroundLightHighContrast
    /// 表面颜色 - 高对比度
    let surfaceHighContrast = AppColor.surfaceLightHighContrast
    /// 表面上的内容颜色 - 高对比度
    let onSurfaceHighContrast = AppColor.onSurfaceLightHighContrast
    /// 表面变体颜色 - 高对比度
    let surfaceVariantHighContrast = AppColor.surfaceVariantLightHighContrast
    /// 表面变体上的内容颜色 - 高对比度
    let onSurfaceVariantHighContrast = AppColor.onSurfaceVariantLightHighContrast
    /// 轮廓线颜色 - 高对比度
    let outlineHighContrast = AppColor.outlineLightHighContrast
    /// 轮廓线变体颜色 - 高对比度
    let outlineVariantHighContrast = AppColor.outlineVariantLightHighContrast
    /// 遮罩颜色 - 高对比度
    let scrimHighContrast = AppColor.scrimLightHighContrast
    /// 反向表面颜色 - 高对比度
    let inverseSurfaceHighContrast = AppColor.inverseSurfaceLightHighContrast
    /// 反向表面上的内容颜色 - 高对比度
    let inverseOnSurfaceHighContrast = AppColor.inverseOnSurfaceLightHighContrast
    /// 反向主要颜色 - 高对比度
    let inversePrimaryHighContrast = AppColor.inversePrimaryLightHighContrast
    /// 暗淡表面颜色 - 高对比度
    let surfaceDimHighContrast = AppColor.inversePrimaryLightHighContrast
    /// 明亮表面颜色 - 高对比度
    let surfaceBrightHighContrast = AppColor.surfaceBrightLightHighContrast
    /// 最低容器表面颜色 - 高对比度
    let surfaceContainerLowestHighContrast = AppColor.surfaceContainerLowestLightHighContrast
    /// 低容器表面颜色 - 高对比度
    let surfaceContainerLowHighContrast = AppColor.surfaceContainerLowLightHighContrast
    /// 容器表面颜色 - 高对比度
    let surfaceContainerHighContrast = AppColor.surfaceContainerHighLightHighContrast
    /// 高容器表面颜色 - 高对比度
    let surfaceContainerHighHighContrast = AppColor.surfaceContainerHighLightHighContrast
    /// 最高容器表面颜色 - 高对比度
    let surfaceContainerHighestHighContrast = AppColor.surfaceContainerHighestLightHighContrast
    
    // MARK: - 字体排版属性
    /// 大号显示字体
    let displayLarge = AppTypography.displayLarge
    /// 中号显示字体
    let displayMedium = AppTypography.displayMedium
    /// 小号显示字体
    let displaySmall = AppTypography.displaySmall
    /// 大号标题字体
    let headlineLarge = AppTypography.headlineLarge
    /// 中号标题字体
    let headlineMedium = AppTypography.headlineMedium
    /// 小号标题字体
    let headlineSmall = AppTypography.headlineSmall
    /// 大号标题字体
    let titleLarge = AppTypography.titleLarge
    /// 中号标题字体
    let titleMedium = AppTypography.titleMedium
    /// 小号标题字体
    let titleSmall = AppTypography.titleSmall
    /// 大号正文字体
    let bodyLarge = AppTypography.bodyLarge
    /// 中号正文字体
    let bodyMedium = AppTypography.bodyMedium
    /// 小号正文字体
    let bodySmall = AppTypography.bodySmall
    /// 大号标签字体
    let labelLarge = AppTypography.labelLarge
    /// 中号标签字体
    let labelMedium = AppTypography.labelMedium
    /// 小号标签字体
    let labelSmall = AppTypography.labelSmall
}
