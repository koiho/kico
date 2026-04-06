//
//  DarkTheme.swift
//  ios
//
//  Created by TAO DAI on 2025/7/30.
//

// MARK: - 深色主题
/// 深色主题实现，使用 AppColor 中定义的深色主题颜色
struct DarkTheme: Theme {
    // MARK: - 颜色属性
    /// 主要颜色
    let primary = AppColor.primaryDark
    /// 主要颜色上的内容颜色
    let onPrimary = AppColor.onPrimaryDark
    /// 主要容器颜色
    let primaryContainer = AppColor.primaryContainerDark
    /// 主要容器上的内容颜色
    let onPrimaryContainer = AppColor.onPrimaryContainerDark
    /// 次要颜色
    let secondary = AppColor.secondaryDark
    /// 次要颜色上的内容颜色
    let onSecondary = AppColor.onSecondaryDark
    /// 次要容器颜色
    let secondaryContainer = AppColor.secondaryContainerDark
    /// 次要容器上的内容颜色
    let onSecondaryContainer = AppColor.onSecondaryContainerDark
    /// 第三颜色
    let tertiary = AppColor.tertiaryDark
    /// 第三颜色上的内容颜色
    let onTertiary = AppColor.onTertiaryDark
    /// 第三容器颜色
    let tertiaryContainer = AppColor.tertiaryContainerDark
    /// 第三容器上的内容颜色
    let onTertiaryContainer = AppColor.onTertiaryContainerDark
    /// 错误颜色
    let error = AppColor.errorDark
    /// 错误颜色上的内容颜色
    let onError = AppColor.onErrorDark
    /// 错误容器颜色
    let errorContainer = AppColor.errorContainerDark
    /// 错误容器上的内容颜色
    let onErrorContainer = AppColor.onErrorContainerDark
    /// 背景颜色
    let background = AppColor.backgroundDark
    /// 背景上的内容颜色
    let onBackground = AppColor.onBackgroundDark
    /// 表面颜色
    let surface = AppColor.surfaceDark
    /// 表面上的内容颜色
    let onSurface = AppColor.onSurfaceDark
    /// 表面变体颜色
    let surfaceVariant = AppColor.surfaceVariantDark
    /// 表面变体上的内容颜色
    let onSurfaceVariant = AppColor.onSurfaceVariantDark
    /// 轮廓线颜色
    let outline = AppColor.outlineDark
    /// 轮廓线变体颜色
    let outlineVariant = AppColor.outlineVariantDark
    /// 遮罩颜色
    let scrim = AppColor.scrimDark
    /// 反向表面颜色
    let inverseSurface = AppColor.inverseSurfaceDark
    /// 反向表面上的内容颜色
    let inverseOnSurface = AppColor.inverseOnSurfaceDark
    /// 反向主要颜色
    let inversePrimary = AppColor.inversePrimaryDark
    /// 暗淡表面颜色
    let surfaceDim = AppColor.surfaceDimDark
    /// 明亮表面颜色
    let surfaceBright = AppColor.surfaceBrightDark
    /// 最低容器表面颜色
    let surfaceContainerLowest = AppColor.surfaceContainerLowestDark
    /// 低容器表面颜色
    let surfaceContainerLow = AppColor.surfaceContainerLowDark
    /// 容器表面颜色
    let surfaceContainer = AppColor.surfaceContainerDark
    /// 高容器表面颜色
    let surfaceContainerHigh = AppColor.surfaceContainerHighDark
    /// 最高容器表面颜色
    let surfaceContainerHighest = AppColor.surfaceContainerHighestDark

    /// 主要颜色 - 中等对比度
    let primaryMediumContrast = AppColor.primaryDarkMediumContrast
    /// 主要颜色上的内容颜色 - 中等对比度
    let onPrimaryMediumContrast = AppColor.onPrimaryDarkMediumContrast
    /// 主要容器颜色 - 中等对比度
    let primaryContainerMediumContrast = AppColor.primaryContainerDarkMediumContrast
    /// 主要容器上的内容颜色 - 中等对比度
    let onPrimaryContainerMediumContrast = AppColor.onPrimaryContainerDarkMediumContrast
    /// 次要颜色 - 中等对比度
    let secondaryMediumContrast = AppColor.secondaryDarkMediumContrast
    /// 次要颜色上的内容颜色 - 中等对比度
    let onSecondaryMediumContrast = AppColor.onSecondaryDarkMediumContrast
    /// 次要容器颜色 - 中等对比度
    let secondaryContainerMediumContrast = AppColor.secondaryContainerDarkMediumContrast
    /// 次要容器上的内容颜色 - 中等对比度
    let onSecondaryContainerMediumContrast = AppColor.onSecondaryContainerDarkMediumContrast
    /// 第三颜色 - 中等对比度
    let tertiaryMediumContrast = AppColor.tertiaryDarkMediumContrast
    /// 第三颜色上的内容颜色 - 中等对比度
    let onTertiaryMediumContrast = AppColor.onTertiaryDarkMediumContrast
    /// 第三容器颜色 - 中等对比度
    let tertiaryContainerMediumContrast = AppColor.tertiaryContainerDarkMediumContrast
    /// 第三容器上的内容颜色 - 中等对比度
    let onTertiaryContainerMediumContrast = AppColor.onTertiaryContainerDarkMediumContrast
    /// 错误颜色 - 中等对比度
    let errorMediumContrast = AppColor.errorDarkMediumContrast
    /// 错误颜色上的内容颜色 - 中等对比度
    let onErrorMediumContrast = AppColor.onErrorDarkMediumContrast
    /// 错误容器颜色 - 中等对比度
    let errorContainerMediumContrast = AppColor.errorContainerDarkMediumContrast
    /// 错误容器上的内容颜色 - 中等对比度
    let onErrorContainerMediumContrast = AppColor.onErrorContainerDarkMediumContrast
    /// 背景颜色 - 中等对比度
    let backgroundMediumContrast = AppColor.backgroundDarkMediumContrast
    /// 背景上的内容颜色 - 中等对比度
    let onBackgroundMediumContrast = AppColor.onBackgroundDarkMediumContrast
    /// 表面颜色 - 中等对比度
    let surfaceMediumContrast = AppColor.surfaceDarkMediumContrast
    /// 表面上的内容颜色 - 中等对比度
    let onSurfaceMediumContrast = AppColor.onSurfaceDarkMediumContrast
    /// 表面变体颜色 - 中等对比度
    let surfaceVariantMediumContrast = AppColor.surfaceVariantDarkMediumContrast
    /// 表面变体上的内容颜色 - 中等对比度
    let onSurfaceVariantMediumContrast = AppColor.onSurfaceVariantDarkMediumContrast
    /// 轮廓线颜色 - 中等对比度
    let outlineMediumContrast = AppColor.outlineDarkMediumContrast
    /// 轮廓线变体颜色 - 中等对比度
    let outlineVariantMediumContrast = AppColor.outlineVariantDarkMediumContrast
    /// 遮罩颜色 - 中等对比度
    let scrimMediumContrast = AppColor.scrimDarkMediumContrast
    /// 反向表面颜色 - 中等对比度
    let inverseSurfaceMediumContrast = AppColor.inverseSurfaceDarkMediumContrast
    /// 反向表面上的内容颜色 - 中等对比度
    let inverseOnSurfaceMediumContrast = AppColor.inverseOnSurfaceDarkMediumContrast
    /// 反向主要颜色 - 中等对比度
    let inversePrimaryMediumContrast = AppColor.inversePrimaryDarkMediumContrast
    /// 暗淡表面颜色 - 中等对比度
    let surfaceDimMediumContrast = AppColor.surfaceDimDarkMediumContrast
    /// 明亮表面颜色 - 中等对比度
    let surfaceBrightMediumContrast = AppColor.surfaceBrightDarkMediumContrast
    /// 最低容器表面颜色 - 中等对比度
    let surfaceContainerLowestMediumContrast = AppColor.surfaceContainerLowestDarkMediumContrast
    /// 低容器表面颜色 - 中等对比度
    let surfaceContainerLowMediumContrast = AppColor.surfaceContainerLowDarkMediumContrast
    /// 容器表面颜色 - 中等对比度
    let surfaceContainerMediumContrast = AppColor.surfaceContainerDarkMediumContrast
    /// 高容器表面颜色 - 中等对比度
    let surfaceContainerHighMediumContrast = AppColor.surfaceContainerHighDarkMediumContrast
    /// 最高容器表面颜色 - 中等对比度
    let surfaceContainerHighestMediumContrast = AppColor.surfaceContainerHighestDarkMediumContrast

    /// 主要颜色 - 高对比度
    let primaryHighContrast = AppColor.primaryDarkHighContrast
    /// 主要颜色上的内容颜色 - 高对比度
    let onPrimaryHighContrast = AppColor.onPrimaryDarkHighContrast
    /// 主要容器颜色 - 高对比度
    let primaryContainerHighContrast = AppColor.primaryContainerDarkHighContrast
    /// 主要容器上的内容颜色 - 高对比度
    let onPrimaryContainerHighContrast = AppColor.onPrimaryContainerDarkHighContrast
    /// 次要颜色 - 高对比度
    let secondaryHighContrast = AppColor.secondaryDarkHighContrast
    /// 次要颜色上的内容颜色 - 高对比度
    let onSecondaryHighContrast = AppColor.onSecondaryDarkHighContrast
    /// 次要容器颜色 - 高对比度
    let secondaryContainerHighContrast = AppColor.secondaryContainerDarkHighContrast
    /// 次要容器上的内容颜色 - 高对比度
    let onSecondaryContainerHighContrast = AppColor.onSecondaryContainerDarkHighContrast
    /// 第三颜色 - 高对比度
    let tertiaryHighContrast = AppColor.tertiaryDarkHighContrast
    /// 第三颜色上的内容颜色 - 高对比度
    let onTertiaryHighContrast = AppColor.onTertiaryDarkHighContrast
    /// 第三容器颜色 - 高对比度
    let tertiaryContainerHighContrast = AppColor.tertiaryContainerDarkHighContrast
    /// 第三容器上的内容颜色 - 高对比度
    let onTertiaryContainerHighContrast = AppColor.onTertiaryContainerDarkHighContrast
    /// 错误颜色 - 高对比度
    let errorHighContrast = AppColor.errorDarkHighContrast
    /// 错误颜色上的内容颜色 - 高对比度
    let onErrorHighContrast = AppColor.onErrorDarkHighContrast
    /// 错误容器颜色 - 高对比度
    let errorContainerHighContrast = AppColor.errorContainerDarkHighContrast
    /// 错误容器上的内容颜色 - 高对比度
    let onErrorContainerHighContrast = AppColor.onErrorContainerDarkHighContrast
    /// 背景颜色 - 高对比度
    let backgroundHighContrast = AppColor.backgroundDarkHighContrast
    /// 背景上的内容颜色 - 高对比度
    let onBackgroundHighContrast = AppColor.onBackgroundDarkHighContrast
    /// 表面颜色 - 高对比度
    let surfaceHighContrast = AppColor.surfaceDarkHighContrast
    /// 表面上的内容颜色 - 高对比度
    let onSurfaceHighContrast = AppColor.onSurfaceDarkHighContrast
    /// 表面变体颜色 - 高对比度
    let surfaceVariantHighContrast = AppColor.surfaceVariantDarkHighContrast
    /// 表面变体上的内容颜色 - 高对比度
    let onSurfaceVariantHighContrast = AppColor.onSurfaceVariantDarkHighContrast
    /// 轮廓线颜色 - 高对比度
    let outlineHighContrast = AppColor.outlineDarkHighContrast
    /// 轮廓线变体颜色 - 高对比度
    let outlineVariantHighContrast = AppColor.outlineVariantDarkHighContrast
    /// 遮罩颜色 - 高对比度
    let scrimHighContrast = AppColor.scrimDarkHighContrast
    /// 反向表面颜色 - 高对比度
    let inverseSurfaceHighContrast = AppColor.inverseSurfaceDarkHighContrast
    /// 反向表面上的内容颜色 - 高对比度
    let inverseOnSurfaceHighContrast = AppColor.inverseOnSurfaceDarkHighContrast
    /// 反向主要颜色 - 高对比度
    let inversePrimaryHighContrast = AppColor.inversePrimaryDarkHighContrast
    /// 暗淡表面颜色 - 高对比度
    let surfaceDimHighContrast = AppColor.inversePrimaryDarkHighContrast
    /// 明亮表面颜色 - 高对比度
    let surfaceBrightHighContrast = AppColor.surfaceBrightDarkHighContrast
    /// 最低容器表面颜色 - 高对比度
    let surfaceContainerLowestHighContrast = AppColor.surfaceContainerLowestDarkHighContrast
    /// 低容器表面颜色 - 高对比度
    let surfaceContainerLowHighContrast = AppColor.surfaceContainerLowDarkHighContrast
    /// 容器表面颜色 - 高对比度
    let surfaceContainerHighContrast = AppColor.surfaceContainerHighDarkHighContrast
    /// 高容器表面颜色 - 高对比度
    let surfaceContainerHighHighContrast = AppColor.surfaceContainerHighDarkHighContrast
    /// 最高容器表面颜色 - 高对比度
    let surfaceContainerHighestHighContrast = AppColor.surfaceContainerHighestDarkHighContrast
    
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
