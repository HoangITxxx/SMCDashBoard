// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface DataTypes {
    struct NetflowInfo {
        int256 amount;
        uint256 lastUpdatedAt;
    }

    struct StablecoinOverallInfo {
        int256 dailyNetflowSum;
        int256 weeklyNetflowSum;
        int256 monthlyNetflowSum;
        int256 marketCapChangePercent;
        uint256 lastUpdatedAt;
    }

    struct NarrativePerformanceInfo {
        string name;
        int256 performancePercent24h;
        uint256 lastUpdatedAt;
    }

    struct NarrativeTopTokenInfo {
        string narrativeName;
        string tokenSymbol;
        int256 relativePerformancePercent;
        uint256 lastUpdatedAt;
    }

    struct AssetPerformanceInfo {
        string tokenSymbol;
        address tokenAddress;
        int256 performancePercent24h;
        int256 performanceVsMarketPercent;
        uint256 lastUpdatedAt;
    }
}