//
//  Color.swift
//  ios
//
//  Created by TAO DAI on 2025/6/28.
//

import SwiftUI

// MARK: - 颜色定义
/// 应用程序的颜色常量集合，包含浅色和深色主题的颜色定义
struct AppColor {
    static let buttonColor = Color("buttonColor")
    // MARK: - 浅色主题颜色
    /// 主要颜色 - 浅色主题
    static let primaryLight = Color("primaryLight")
    /// 主要颜色上的内容颜色 - 浅色主题
    static let onPrimaryLight = Color("onPrimaryLight")
    /// 主要容器颜色 - 浅色主题
    static let primaryContainerLight = Color("primaryContainerLight")
    /// 主要容器上的内容颜色 - 浅色主题
    static let onPrimaryContainerLight = Color("onPrimaryContainerLight")
    /// 次要颜色 - 浅色主题
    static let secondaryLight = Color("secondaryLight")
    /// 次要颜色上的内容颜色 - 浅色主题
    static let onSecondaryLight = Color("onSecondaryLight")
    /// 次要容器颜色 - 浅色主题
    static let secondaryContainerLight = Color("secondaryContainerLight")
    /// 次要容器上的内容颜色 - 浅色主题
    static let onSecondaryContainerLight = Color("onSecondaryContainerLight")
    /// 第三颜色 - 浅色主题
    static let tertiaryLight = Color("tertiaryLight")
    /// 第三颜色上的内容颜色 - 浅色主题
    static let onTertiaryLight = Color("onTertiaryLight")
    /// 第三容器颜色 - 浅色主题
    static let tertiaryContainerLight = Color("tertiaryContainerLight")
    /// 第三容器上的内容颜色 - 浅色主题
    static let onTertiaryContainerLight = Color("onTertiaryContainerLight")
    /// 错误颜色 - 浅色主题
    static let errorLight = Color("errorLight")
    /// 错误颜色上的内容颜色 - 浅色主题
    static let onErrorLight = Color("onErrorLight")
    /// 错误容器颜色 - 浅色主题
    static let errorContainerLight = Color("errorContainerLight")
    /// 错误容器上的内容颜色 - 浅色主题
    static let onErrorContainerLight = Color("onErrorContainerLight")
    /// 背景颜色 - 浅色主题
    static let backgroundLight = Color("backgroundLight")
    /// 背景上的内容颜色 - 浅色主题
    static let onBackgroundLight = Color("onBackgroundLight")
    /// 表面颜色 - 浅色主题
    static let surfaceLight = Color("surfaceLight")
    /// 表面上的内容颜色 - 浅色主题
    static let onSurfaceLight = Color("onSurfaceLight")
    /// 表面变体颜色 - 浅色主题
    static let surfaceVariantLight = Color("surfaceVariantLight")
    /// 表面变体上的内容颜色 - 浅色主题
    static let onSurfaceVariantLight = Color("onSurfaceVariantLight")
    /// 轮廓线颜色 - 浅色主题
    static let outlineLight = Color("outlineLight")
    /// 轮廓线变体颜色 - 浅色主题
    static let outlineVariantLight = Color("outlineVariantLight")
    /// 遮罩颜色 - 浅色主题
    static let scrimLight = Color("scrimLight")
    /// 反向表面颜色 - 浅色主题
    static let inverseSurfaceLight = Color("inverseSurfaceLight")
    /// 反向表面上的内容颜色 - 浅色主题
    static let inverseOnSurfaceLight = Color("inverseOnSurfaceLight")
    /// 反向主要颜色 - 浅色主题
    static let inversePrimaryLight = Color("inversePrimaryLight")
    /// 暗淡表面颜色 - 浅色主题
    static let surfaceDimLight = Color("surfaceDimLight")
    /// 明亮表面颜色 - 浅色主题
    static let surfaceBrightLight = Color("surfaceBrightLight")
    /// 最低容器表面颜色 - 浅色主题
    static let surfaceContainerLowestLight = Color("surfaceContainerLowestLight")
    /// 低容器表面颜色 - 浅色主题
    static let surfaceContainerLowLight = Color("surfaceContainerLowLight")
    /// 容器表面颜色 - 浅色主题
    static let surfaceContainerLight = Color("surfaceContainerLight")
    /// 高容器表面颜色 - 浅色主题
    static let surfaceContainerHighLight = Color("surfaceContainerHighLight")
    /// 最高容器表面颜色 - 浅色主题
    static let surfaceContainerHighestLight = Color("surfaceContainerHighestLight")

    /// 主要颜色 - 浅色主题中等对比度
    static let primaryLightMediumContrast = Color("primaryLightMediumContrast")
    /// 主要颜色上的内容颜色 - 浅色主题中等对比度
    static let onPrimaryLightMediumContrast = Color("onPrimaryLightMediumContrast")
    /// 主要容器颜色 - 浅色主题中等对比度
    static let primaryContainerLightMediumContrast = Color("primaryContainerLightMediumContrast")
    /// 主要容器上的内容颜色 - 浅色主题中等对比度
    static let onPrimaryContainerLightMediumContrast = Color("onPrimaryContainerLightMediumContrast")
    /// 次要颜色 - 浅色主题中等对比度
    static let secondaryLightMediumContrast = Color("secondaryLightMediumContrast")
    /// 次要颜色上的内容颜色 - 浅色主题中等对比度
    static let onSecondaryLightMediumContrast = Color("onSecondaryLightMediumContrast")
    /// 次要容器颜色 - 浅色主题中等对比度
    static let secondaryContainerLightMediumContrast = Color("secondaryContainerLightMediumContrast")
    /// 次要容器上的内容颜色 - 浅色主题中等对比度
    static let onSecondaryContainerLightMediumContrast = Color("onSecondaryContainerLightMediumContrast")
    /// 第三颜色 - 浅色主题中等对比度
    static let tertiaryLightMediumContrast = Color("tertiaryLightMediumContrast")
    /// 第三颜色上的内容颜色 - 浅色主题中等对比度
    static let onTertiaryLightMediumContrast = Color("onTertiaryLightMediumContrast")
    /// 第三容器颜色 - 浅色主题中等对比度
    static let tertiaryContainerLightMediumContrast = Color("tertiaryContainerLightMediumContrast")
    /// 第三容器上的内容颜色 - 浅色主题中等对比度
    static let onTertiaryContainerLightMediumContrast = Color("onTertiaryContainerLightMediumContrast")
    /// 错误颜色 - 浅色主题中等对比度
    static let errorLightMediumContrast = Color("errorLightMediumContrast")
    /// 错误颜色上的内容颜色 - 浅色主题中等对比度
    static let onErrorLightMediumContrast = Color("onErrorLightMediumContrast")
    /// 错误容器颜色 - 浅色主题中等对比度
    static let errorContainerLightMediumContrast = Color("errorContainerLightMediumContrast")
    /// 错误容器上的内容颜色 - 浅色主题中等对比度
    static let onErrorContainerLightMediumContrast = Color("onErrorContainerLightMediumContrast")
    /// 背景颜色 - 浅色主题中等对比度
    static let backgroundLightMediumContrast = Color("backgroundLightMediumContrast")
    /// 背景上的内容颜色 - 浅色主题中等对比度
    static let onBackgroundLightMediumContrast = Color("onBackgroundLightMediumContrast")
    /// 表面颜色 - 浅色主题中等对比度
    static let surfaceLightMediumContrast = Color("surfaceLightMediumContrast")
    /// 表面上的内容颜色 - 浅色主题中等对比度
    static let onSurfaceLightMediumContrast = Color("onSurfaceLightMediumContrast")
    /// 表面变体颜色 - 浅色主题中等对比度
    static let surfaceVariantLightMediumContrast = Color("surfaceVariantLightMediumContrast")
    /// 表面变体上的内容颜色 - 浅色主题中等对比度
    static let onSurfaceVariantLightMediumContrast = Color("onSurfaceVariantLightMediumContrast")
    /// 轮廓线颜色 - 浅色主题中等对比度
    static let outlineLightMediumContrast = Color("outlineLightMediumContrast")
    /// 轮廓线变体颜色 - 浅色主题中等对比度
    static let outlineVariantLightMediumContrast = Color("outlineVariantLightMediumContrast")
    /// 遮罩颜色 - 浅色主题中等对比度
    static let scrimLightMediumContrast = Color("scrimLightMediumContrast")
    /// 反向表面颜色 - 浅色主题中等对比度
    static let inverseSurfaceLightMediumContrast = Color("inverseSurfaceLightMediumContrast")
    /// 反向表面上的内容颜色 - 浅色主题中等对比度
    static let inverseOnSurfaceLightMediumContrast = Color("inverseOnSurfaceLightMediumContrast")
    /// 反向主要颜色 - 浅色主题中等对比度
    static let inversePrimaryLightMediumContrast = Color("inversePrimaryLightMediumContrast")
    /// 暗淡表面颜色 - 浅色主题中等对比度
    static let surfaceDimLightMediumContrast = Color("surfaceDimLightMediumContrast")
    /// 明亮表面颜色 - 浅色主题中等对比度
    static let surfaceBrightLightMediumContrast = Color("surfaceBrightLightMediumContrast")
    /// 最低容器表面颜色 - 浅色主题中等对比度
    static let surfaceContainerLowestLightMediumContrast = Color("surfaceContainerLowestLightMediumContrast")
    /// 低容器表面颜色 - 浅色主题中等对比度
    static let surfaceContainerLowLightMediumContrast = Color("surfaceContainerLowLightMediumContrast")
    /// 容器表面颜色 - 浅色主题中等对比度
    static let surfaceContainerLightMediumContrast = Color("surfaceContainerLightMediumContrast")
    /// 高容器表面颜色 - 浅色主题中等对比度
    static let surfaceContainerHighLightMediumContrast = Color("surfaceContainerHighLightMediumContrast")
    /// 最高容器表面颜色 - 浅色主题中等对比度
    static let surfaceContainerHighestLightMediumContrast = Color("surfaceContainerHighestLightMediumContrast")

    /// 主要颜色 - 浅色主题高对比度
    static let primaryLightHighContrast = Color("primaryLightHighContrast")
    /// 主要颜色上的内容颜色 - 浅色主题高对比度
    static let onPrimaryLightHighContrast = Color("onPrimaryLightHighContrast")
    /// 主要容器颜色 - 浅色主题高对比度
    static let primaryContainerLightHighContrast = Color("primaryContainerLightHighContrast")
    /// 主要容器上的内容颜色 - 浅色主题高对比度
    static let onPrimaryContainerLightHighContrast = Color("onPrimaryContainerLightHighContrast")
    /// 次要颜色 - 浅色主题高对比度
    static let secondaryLightHighContrast = Color("secondaryLightHighContrast")
    /// 次要颜色上的内容颜色 - 浅色主题高对比度
    static let onSecondaryLightHighContrast = Color("onSecondaryLightHighContrast")
    /// 次要容器颜色 - 浅色主题高对比度
    static let secondaryContainerLightHighContrast = Color("secondaryContainerLightHighContrast")
    /// 次要容器上的内容颜色 - 浅色主题高对比度
    static let onSecondaryContainerLightHighContrast = Color("onSecondaryContainerLightHighContrast")
    /// 第三颜色 - 浅色主题高对比度
    static let tertiaryLightHighContrast = Color("tertiaryLightHighContrast")
    /// 第三颜色上的内容颜色 - 浅色主题高对比度
    static let onTertiaryLightHighContrast = Color("onTertiaryLightHighContrast")
    /// 第三容器颜色 - 浅色主题高对比度
    static let tertiaryContainerLightHighContrast = Color("tertiaryContainerLightHighContrast")
    /// 第三容器上的内容颜色 - 浅色主题高对比度
    static let onTertiaryContainerLightHighContrast = Color("onTertiaryContainerLightHighContrast")
    /// 错误颜色 - 浅色主题高对比度
    static let errorLightHighContrast = Color("errorLightHighContrast")
    /// 错误颜色上的内容颜色 - 浅色主题高对比度
    static let onErrorLightHighContrast = Color("onErrorLightHighContrast")
    /// 错误容器颜色 - 浅色主题高对比度
    static let errorContainerLightHighContrast = Color("errorContainerLightHighContrast")
    /// 错误容器上的内容颜色 - 浅色主题高对比度
    static let onErrorContainerLightHighContrast = Color("onErrorContainerLightHighContrast")
    /// 背景颜色 - 浅色主题高对比度
    static let backgroundLightHighContrast = Color("backgroundLightHighContrast")
    /// 背景上的内容颜色 - 浅色主题高对比度
    static let onBackgroundLightHighContrast = Color("onBackgroundLightHighContrast")
    /// 表面颜色 - 浅色主题高对比度
    static let surfaceLightHighContrast = Color("surfaceLightHighContrast")
    /// 表面上的内容颜色 - 浅色主题高对比度
    static let onSurfaceLightHighContrast = Color("onSurfaceLightHighContrast")
    /// 表面变体颜色 - 浅色主题高对比度
    static let surfaceVariantLightHighContrast = Color("surfaceVariantLightHighContrast")
    /// 表面变体上的内容颜色 - 浅色主题高对比度
    static let onSurfaceVariantLightHighContrast = Color("onSurfaceVariantLightHighContrast")
    /// 轮廓线颜色 - 浅色主题高对比度
    static let outlineLightHighContrast = Color("outlineLightHighContrast")
    /// 轮廓线变体颜色 - 浅色主题高对比度
    static let outlineVariantLightHighContrast = Color("outlineVariantLightHighContrast")
    /// 遮罩颜色 - 浅色主题高对比度
    static let scrimLightHighContrast = Color("scrimLightHighContrast")
    /// 反向表面颜色 - 浅色主题高对比度
    static let inverseSurfaceLightHighContrast = Color("inverseSurfaceLightHighContrast")
    /// 反向表面上的内容颜色 - 浅色主题高对比度
    static let inverseOnSurfaceLightHighContrast = Color("inverseOnSurfaceLightHighContrast")
    /// 反向主要颜色 - 浅色主题高对比度
    static let inversePrimaryLightHighContrast = Color("inversePrimaryLightHighContrast")
    /// 暗淡表面颜色 - 浅色主题高对比度
    static let surfaceDimLightHighContrast = Color("surfaceDimLightHighContrast")
    /// 明亮表面颜色 - 浅色主题高对比度
    static let surfaceBrightLightHighContrast = Color("surfaceBrightLightHighContrast")
    /// 最低容器表面颜色 - 浅色主题高对比度
    static let surfaceContainerLowestLightHighContrast = Color("surfaceContainerLowestLightHighContrast")
    /// 低容器表面颜色 - 浅色主题高对比度
    static let surfaceContainerLowLightHighContrast = Color("surfaceContainerLowLightHighContrast")
    /// 容器表面颜色 - 浅色主题高对比度
    static let surfaceContainerLightHighContrast = Color("surfaceContainerLightHighContrast")
    /// 高容器表面颜色 - 浅色主题高对比度
    static let surfaceContainerHighLightHighContrast = Color("surfaceContainerHighLightHighContrast")
    /// 最高容器表面颜色 - 浅色主题高对比度
    static let surfaceContainerHighestLightHighContrast = Color("surfaceContainerHighestLightHighContrast")

    // MARK: - 深色主题颜色
    /// 主要颜色 - 深色主题
    static let primaryDark = Color("primaryDark")
    /// 主要颜色上的内容颜色 - 深色主题
    static let onPrimaryDark = Color("onPrimaryDark")
    /// 主要容器颜色 - 深色主题
    static let primaryContainerDark = Color("primaryContainerDark")
    /// 主要容器上的内容颜色 - 深色主题
    static let onPrimaryContainerDark = Color("onPrimaryContainerDark")
    /// 次要颜色 - 深色主题
    static let secondaryDark = Color("secondaryDark")
    /// 次要颜色上的内容颜色 - 深色主题
    static let onSecondaryDark = Color("onSecondaryDark")
    /// 次要容器颜色 - 深色主题
    static let secondaryContainerDark = Color("secondaryContainerDark")
    /// 次要容器上的内容颜色 - 深色主题
    static let onSecondaryContainerDark = Color("onSecondaryContainerDark")
    /// 第三颜色 - 深色主题
    static let tertiaryDark = Color("tertiaryDark")
    /// 第三颜色上的内容颜色 - 深色主题
    static let onTertiaryDark = Color("onTertiaryDark")
    /// 第三容器颜色 - 深色主题
    static let tertiaryContainerDark = Color("tertiaryContainerDark")
    /// 第三容器上的内容颜色 - 深色主题
    static let onTertiaryContainerDark = Color("onTertiaryContainerDark")
    /// 错误颜色 - 深色主题
    static let errorDark = Color("errorDark")
    /// 错误颜色上的内容颜色 - 深色主题
    static let onErrorDark = Color("onErrorDark")
    /// 错误容器颜色 - 深色主题
    static let errorContainerDark = Color("errorContainerDark")
    /// 错误容器上的内容颜色 - 深色主题
    static let onErrorContainerDark = Color("onErrorContainerDark")
    /// 背景颜色 - 深色主题
    static let backgroundDark = Color("backgroundDark")
    /// 背景上的内容颜色 - 深色主题
    static let onBackgroundDark = Color("onBackgroundDark")
    /// 表面颜色 - 深色主题
    static let surfaceDark = Color("surfaceDark")
    /// 表面上的内容颜色 - 深色主题
    static let onSurfaceDark = Color("onSurfaceDark")
    /// 表面变体颜色 - 深色主题
    static let surfaceVariantDark = Color("surfaceVariantDark")
    /// 表面变体上的内容颜色 - 深色主题
    static let onSurfaceVariantDark = Color("onSurfaceVariantDark")
    /// 轮廓线颜色 - 深色主题
    static let outlineDark = Color("outlineDark")
    /// 轮廓线变体颜色 - 深色主题
    static let outlineVariantDark = Color("outlineVariantDark")
    /// 遮罩颜色 - 深色主题
    static let scrimDark = Color("scrimDark")
    /// 反向表面颜色 - 深色主题
    static let inverseSurfaceDark = Color("inverseSurfaceDark")
    /// 反向表面上的内容颜色 - 深色主题
    static let inverseOnSurfaceDark = Color("inverseOnSurfaceDark")
    /// 反向主要颜色 - 深色主题
    static let inversePrimaryDark = Color("inversePrimaryDark")
    /// 暗淡表面颜色 - 深色主题
    static let surfaceDimDark = Color("surfaceDimDark")
    /// 明亮表面颜色 - 深色主题
    static let surfaceBrightDark = Color("surfaceBrightDark")
    /// 最低容器表面颜色 - 深色主题
    static let surfaceContainerLowestDark = Color("surfaceContainerLowestDark")
    /// 低容器表面颜色 - 深色主题
    static let surfaceContainerLowDark = Color("surfaceContainerLowDark")
    /// 容器表面颜色 - 深色主题
    static let surfaceContainerDark = Color("surfaceContainerDark")
    /// 高容器表面颜色 - 深色主题
    static let surfaceContainerHighDark = Color("surfaceContainerHighDark")
    /// 最高容器表面颜色 - 深色主题
    static let surfaceContainerHighestDark = Color("surfaceContainerHighestDark")

    /// 主要颜色 - 深色主题中等对比度
    static let primaryDarkMediumContrast = Color("primaryDarkMediumContrast")
    /// 主要颜色上的内容颜色 - 深色主题中等对比度
    static let onPrimaryDarkMediumContrast = Color("onPrimaryDarkMediumContrast")
    /// 主要容器颜色 - 深色主题中等对比度
    static let primaryContainerDarkMediumContrast = Color("primaryContainerDarkMediumContrast")
    /// 主要容器上的内容颜色 - 深色主题中等对比度
    static let onPrimaryContainerDarkMediumContrast = Color("onPrimaryContainerDarkMediumContrast")
    /// 次要颜色 - 深色主题中等对比度
    static let secondaryDarkMediumContrast = Color("secondaryDarkMediumContrast")
    /// 次要颜色上的内容颜色 - 深色主题中等对比度
    static let onSecondaryDarkMediumContrast = Color("onSecondaryDarkMediumContrast")
    /// 次要容器颜色 - 深色主题中等对比度
    static let secondaryContainerDarkMediumContrast = Color("secondaryContainerDarkMediumContrast")
    /// 次要容器上的内容颜色 - 深色主题中等对比度
    static let onSecondaryContainerDarkMediumContrast = Color("onSecondaryContainerDarkMediumContrast")
    /// 第三颜色 - 深色主题中等对比度
    static let tertiaryDarkMediumContrast = Color("tertiaryDarkMediumContrast")
    /// 第三颜色上的内容颜色 - 深色主题中等对比度
    static let onTertiaryDarkMediumContrast = Color("onTertiaryDarkMediumContrast")
    /// 第三容器颜色 - 深色主题中等对比度
    static let tertiaryContainerDarkMediumContrast = Color("tertiaryContainerDarkMediumContrast")
    /// 第三容器上的内容颜色 - 深色主题中等对比度
    static let onTertiaryContainerDarkMediumContrast = Color("onTertiaryContainerDarkMediumContrast")
    /// 错误颜色 - 深色主题中等对比度
    static let errorDarkMediumContrast = Color("errorDarkMediumContrast")
    /// 错误颜色上的内容颜色 - 深色主题中等对比度
    static let onErrorDarkMediumContrast = Color("onErrorDarkMediumContrast")
    /// 错误容器颜色 - 深色主题中等对比度
    static let errorContainerDarkMediumContrast = Color("errorContainerDarkMediumContrast")
    /// 错误容器上的内容颜色 - 深色主题中等对比度
    static let onErrorContainerDarkMediumContrast = Color("onErrorContainerDarkMediumContrast")
    /// 背景颜色 - 深色主题中等对比度
    static let backgroundDarkMediumContrast = Color("backgroundDarkMediumContrast")
    /// 背景上的内容颜色 - 深色主题中等对比度
    static let onBackgroundDarkMediumContrast = Color("onBackgroundDarkMediumContrast")
    /// 表面颜色 - 深色主题中等对比度
    static let surfaceDarkMediumContrast = Color("surfaceDarkMediumContrast")
    /// 表面上的内容颜色 - 深色主题中等对比度
    static let onSurfaceDarkMediumContrast = Color("onSurfaceDarkMediumContrast")
    /// 表面变体颜色 - 深色主题中等对比度
    static let surfaceVariantDarkMediumContrast = Color("surfaceVariantDarkMediumContrast")
    /// 表面变体上的内容颜色 - 深色主题中等对比度
    static let onSurfaceVariantDarkMediumContrast = Color("onSurfaceVariantDarkMediumContrast")
    /// 轮廓线颜色 - 深色主题中等对比度
    static let outlineDarkMediumContrast = Color("outlineDarkMediumContrast")
    /// 轮廓线变体颜色 - 深色主题中等对比度
    static let outlineVariantDarkMediumContrast = Color("outlineVariantDarkMediumContrast")
    /// 遮罩颜色 - 深色主题中等对比度
    static let scrimDarkMediumContrast = Color("scrimDarkMediumContrast")
    /// 反向表面颜色 - 深色主题中等对比度
    static let inverseSurfaceDarkMediumContrast = Color("inverseSurfaceDarkMediumContrast")
    /// 反向表面上的内容颜色 - 深色主题中等对比度
    static let inverseOnSurfaceDarkMediumContrast = Color("inverseOnSurfaceDarkMediumContrast")
    /// 反向主要颜色 - 深色主题中等对比度
    static let inversePrimaryDarkMediumContrast = Color("inversePrimaryDarkMediumContrast")
    /// 暗淡表面颜色 - 深色主题中等对比度
    static let surfaceDimDarkMediumContrast = Color("surfaceDimDarkMediumContrast")
    /// 明亮表面颜色 - 深色主题中等对比度
    static let surfaceBrightDarkMediumContrast = Color("surfaceBrightDarkMediumContrast")
    /// 最低容器表面颜色 - 深色主题中等对比度
    static let surfaceContainerLowestDarkMediumContrast = Color("surfaceContainerLowestDarkMediumContrast")
    /// 低容器表面颜色 - 深色主题中等对比度
    static let surfaceContainerLowDarkMediumContrast = Color("surfaceContainerLowDarkMediumContrast")
    /// 容器表面颜色 - 深色主题中等对比度
    static let surfaceContainerDarkMediumContrast = Color("surfaceContainerDarkMediumContrast")
    /// 高容器表面颜色 - 深色主题中等对比度
    static let surfaceContainerHighDarkMediumContrast = Color("surfaceContainerHighDarkMediumContrast")
    /// 最高容器表面颜色 - 深色主题中等对比度
    static let surfaceContainerHighestDarkMediumContrast = Color("surfaceContainerHighestDarkMediumContrast")

    /// 主要颜色 - 深色主题高对比度
    static let primaryDarkHighContrast = Color("primaryDarkHighContrast")
    /// 主要颜色上的内容颜色 - 深色主题高对比度
    static let onPrimaryDarkHighContrast = Color("onPrimaryDarkHighContrast")
    /// 主要容器颜色 - 深色主题高对比度
    static let primaryContainerDarkHighContrast = Color("primaryContainerDarkHighContrast")
    /// 主要容器上的内容颜色 - 深色主题高对比度
    static let onPrimaryContainerDarkHighContrast = Color("onPrimaryContainerDarkHighContrast")
    /// 次要颜色 - 深色主题高对比度
    static let secondaryDarkHighContrast = Color("secondaryDarkHighContrast")
    /// 次要颜色上的内容颜色 - 深色主题高对比度
    static let onSecondaryDarkHighContrast = Color("onSecondaryDarkHighContrast")
    /// 次要容器颜色 - 深色主题高对比度
    static let secondaryContainerDarkHighContrast = Color("secondaryContainerDarkHighContrast")
    /// 次要容器上的内容颜色 - 深色主题高对比度
    static let onSecondaryContainerDarkHighContrast = Color("onSecondaryContainerDarkHighContrast")
    /// 第三颜色 - 深色主题高对比度
    static let tertiaryDarkHighContrast = Color("tertiaryDarkHighContrast")
    /// 第三颜色上的内容颜色 - 深色主题高对比度
    static let onTertiaryDarkHighContrast = Color("onTertiaryDarkHighContrast")
    /// 第三容器颜色 - 深色主题高对比度
    static let tertiaryContainerDarkHighContrast = Color("tertiaryContainerDarkHighContrast")
    /// 第三容器上的内容颜色 - 深色主题高对比度
    static let onTertiaryContainerDarkHighContrast = Color("onTertiaryContainerDarkHighContrast")
    /// 错误颜色 - 深色主题高对比度
    static let errorDarkHighContrast = Color("errorDarkHighContrast")
    /// 错误颜色上的内容颜色 - 深色主题高对比度
    static let onErrorDarkHighContrast = Color("onErrorDarkHighContrast")
    /// 错误容器颜色 - 深色主题高对比度
    static let errorContainerDarkHighContrast = Color("errorContainerDarkHighContrast")
    /// 错误容器上的内容颜色 - 深色主题高对比度
    static let onErrorContainerDarkHighContrast = Color("onErrorContainerDarkHighContrast")
    /// 背景颜色 - 深色主题高对比度
    static let backgroundDarkHighContrast = Color("backgroundDarkHighContrast")
    /// 背景上的内容颜色 - 深色主题高对比度
    static let onBackgroundDarkHighContrast = Color("onBackgroundDarkHighContrast")
    /// 表面颜色 - 深色主题高对比度
    static let surfaceDarkHighContrast = Color("surfaceDarkHighContrast")
    /// 表面上的内容颜色 - 深色主题高对比度
    static let onSurfaceDarkHighContrast = Color("onSurfaceDarkHighContrast")
    /// 表面变体颜色 - 深色主题高对比度
    static let surfaceVariantDarkHighContrast = Color("surfaceVariantDarkHighContrast")
    /// 表面变体上的内容颜色 - 深色主题高对比度
    static let onSurfaceVariantDarkHighContrast = Color("onSurfaceVariantDarkHighContrast")
    /// 轮廓线颜色 - 深色主题高对比度
    static let outlineDarkHighContrast = Color("outlineDarkHighContrast")
    /// 轮廓线变体颜色 - 深色主题高对比度
    static let outlineVariantDarkHighContrast = Color("outlineVariantDarkHighContrast")
    /// 遮罩颜色 - 深色主题高对比度
    static let scrimDarkHighContrast = Color("scrimDarkHighContrast")
    /// 反向表面颜色 - 深色主题高对比度
    static let inverseSurfaceDarkHighContrast = Color("inverseSurfaceDarkHighContrast")
    /// 反向表面上的内容颜色 - 深色主题高对比度
    static let inverseOnSurfaceDarkHighContrast = Color("inverseOnSurfaceDarkHighContrast")
    /// 反向主要颜色 - 深色主题高对比度
    static let inversePrimaryDarkHighContrast = Color("inversePrimaryDarkHighContrast")
    /// 暗淡表面颜色 - 深色主题高对比度
    static let surfaceDimDarkHighContrast = Color("surfaceDimDarkHighContrast")
    /// 明亮表面颜色 - 深色主题高对比度
    static let surfaceBrightDarkHighContrast = Color("surfaceBrightDarkHighContrast")
    /// 最低容器表面颜色 - 深色主题高对比度
    static let surfaceContainerLowestDarkHighContrast = Color("surfaceContainerLowestDarkHighContrast")
    /// 低容器表面颜色 - 深色主题高对比度
    static let surfaceContainerLowDarkHighContrast = Color("surfaceContainerLowDarkHighContrast")
    /// 容器表面颜色 - 深色主题高对比度
    static let surfaceContainerDarkHighContrast = Color("surfaceContainerDarkHighContrast")
    /// 高容器表面颜色 - 深色主题高对比度
    static let surfaceContainerHighDarkHighContrast = Color("surfaceContainerHighDarkHighContrast")
    /// 最高容器表面颜色 - 深色主题高对比度
    static let surfaceContainerHighestDarkHighContrast = Color("surfaceContainerHighestDarkHighContrast")
}
