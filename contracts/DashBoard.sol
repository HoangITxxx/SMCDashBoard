// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../structs/DataTypes.sol";

contract Dashboard is Ownable, DataTypes {

// ------- STATE VARIABLES -------
    NetflowInfo public exchangeNetflow; 
    NetflowAlert[] public userNetflowAlerts;
    uint256 public constant MAX_ALERTS_PER_USER = 10;
    int256 public previousExchangeNetflowAmount; 
    bool public hasPreviousExchangeNetflowAmount = false; 

    StablecoinOverallInfo public stablecoinExchangeOverallNetflow;
    mapping(string => NarrativePerformanceInfo) public narrativePerformances;
    string[] public narrativeKeys;
    mapping(string => NarrativeTopTokenInfo) public narrativeTopPerformers;
    AssetPerformanceInfo[] public topOutperformingAssets;
    AssetPerformanceInfo[] public topUnderperformingAssets;
    int256 public marketAverageMovementPercent24h;
    uint256 public marketPerformanceLastUpdatedAt;

    enum AlertCondition {
        NONE, GREATER_THAN, LESS_THAN, EQUAL_TO, CROSSING, CROSSING_UP, CROSSING_DOWN,
        ENTERING_CHANNEL, EXITING_CHANNEL, INSIDE_CHANNEL, OUTSIDE_CHANNEL,
        MOVING_UP, MOVING_DOWN
    }
//======= Struct Alert =====================
    struct NetflowAlert {
        uint256 id;
        address user;
        AlertCondition condition;
        int256 threshold1;
        int256 threshold2; 
        bool isActive;
        bool isTriggered;
        uint256 lastTriggeredAt;
        string message;
    }

    NetflowAlert public userNetflowAlert;
    uint256 private nextAlertId = 1;

    // ------- EVENTS -------
    event NetflowUpdated(int256 amount, uint256 timestamp);
    event StablecoinOverallNetflowUpdated(int256 daily, int256 weekly, int256 monthly, int256 marketCapChange, uint256 timestamp);
    event NarrativePerformanceUpdated(string indexed narrativeName, int256 performancePercent, uint256 timestamp);
    event NarrativeKeyAdded(string indexed narrativeName);
    event NarrativeKeyRemoved(string indexed narrativeName);
    event NarrativeTopTokenUpdated(string indexed narrativeName, string tokenSymbol, int256 relativePerformance, uint256 timestamp);
    event MarketPerformersUpdated(int256 marketAverage, uint256 timestamp);

    // Event chung cho việc cấu hình alert
    event AlertConfigured(
        uint256 indexed alertId,
        address indexed user,
        AlertCondition condition,
        int256 threshold1,
        int256 threshold2, 
        string message
    );
    event AlertTriggered(uint256 indexed alertId, address indexed user, int256 currentValue, string message);
    event AlertDeactivated(uint256 indexed alertId);
    event AlertActivated(uint256 indexed alertId);
    event AlertTriggerReset(uint256 indexed alertId);

    constructor() Ownable(msg.sender) {
        userNetflowAlert.isActive = false;
        userNetflowAlert.id = 0;
    }

    // ------- SETTER FUNCTIONS -------
    function updateExchangeNetflow(int256 _amount) external onlyOwner {
        if (hasPreviousExchangeNetflowAmount || exchangeNetflow.lastUpdatedAt != 0) {
            previousExchangeNetflowAmount = exchangeNetflow.amount;
        } else {
            previousExchangeNetflowAmount = _amount; 
        }
        hasPreviousExchangeNetflowAmount = true;

        exchangeNetflow.amount = _amount;
        exchangeNetflow.lastUpdatedAt = block.timestamp;
        emit NetflowUpdated(_amount, block.timestamp);

        checkAndTriggerAlert(exchangeNetflow.amount, previousExchangeNetflowAmount, hasPreviousExchangeNetflowAmount);
    }

    function updateStablecoinOverallNetflow(
        int256 _dailyNetflow, int256 _weeklyNetflow, int256 _monthlyNetflow, int256 _marketCapChangePercent
    ) external onlyOwner {
        stablecoinExchangeOverallNetflow.dailyNetflowSum = _dailyNetflow;
        stablecoinExchangeOverallNetflow.weeklyNetflowSum = _weeklyNetflow;
        stablecoinExchangeOverallNetflow.monthlyNetflowSum = _monthlyNetflow;
        stablecoinExchangeOverallNetflow.marketCapChangePercent = _marketCapChangePercent;
        stablecoinExchangeOverallNetflow.lastUpdatedAt = block.timestamp;
        emit StablecoinOverallNetflowUpdated(_dailyNetflow, _weeklyNetflow, _monthlyNetflow, _marketCapChangePercent, block.timestamp);
    }

    function addOrUpdateNarrativePerformance(string calldata _narrativeName, int256 _performancePercent) external onlyOwner {
        NarrativePerformanceInfo storage narrative = narrativePerformances[_narrativeName];
        bool found = false;
        for (uint i = 0; i < narrativeKeys.length; i++) {
            if (keccak256(abi.encodePacked(narrativeKeys[i])) == keccak256(abi.encodePacked(_narrativeName))) {
                found = true;
                break;
            }
        }
        if (!found) {
            narrativeKeys.push(_narrativeName);
            emit NarrativeKeyAdded(_narrativeName);
        }
        narrative.name = _narrativeName;
        narrative.performancePercent24h = _performancePercent;
        narrative.lastUpdatedAt = block.timestamp;
        emit NarrativePerformanceUpdated(_narrativeName, _performancePercent, block.timestamp);
    }

    function batchUpdateNarrativePerformances(NarrativePerformanceInfo[] calldata _performances) external onlyOwner {
        for (uint i = 0; i < _performances.length; i++) {
            this.addOrUpdateNarrativePerformance(_performances[i].name, _performances[i].performancePercent24h);
        }
    }

    function updateNarrativeTopPerformer(
        string calldata _narrativeName, string calldata _tokenSymbol, int256 _relativePerformancePercent
    ) external onlyOwner {
        NarrativeTopTokenInfo storage topToken = narrativeTopPerformers[_narrativeName];
        topToken.narrativeName = _narrativeName;
        topToken.tokenSymbol = _tokenSymbol;
        topToken.relativePerformancePercent = _relativePerformancePercent;
        topToken.lastUpdatedAt = block.timestamp;
        emit NarrativeTopTokenUpdated(_narrativeName, _tokenSymbol, _relativePerformancePercent, block.timestamp);
    }

    function updateMarketPerformance(
        AssetPerformanceInfo[] calldata _topOutperformers, AssetPerformanceInfo[] calldata _topUnderperformers, int256 _marketAvgMove24h
    ) external onlyOwner {
        delete topOutperformingAssets;
        for(uint i=0; i < _topOutperformers.length; i++){
            topOutperformingAssets.push(AssetPerformanceInfo({
                tokenSymbol: _topOutperformers[i].tokenSymbol, tokenAddress: _topOutperformers[i].tokenAddress,
                performancePercent24h: _topOutperformers[i].performancePercent24h, performanceVsMarketPercent: _topOutperformers[i].performanceVsMarketPercent,
                lastUpdatedAt: block.timestamp
            }));
        }
        delete topUnderperformingAssets;
        for(uint i=0; i < _topUnderperformers.length; i++){
            topUnderperformingAssets.push(AssetPerformanceInfo({
                tokenSymbol: _topUnderperformers[i].tokenSymbol, tokenAddress: _topUnderperformers[i].tokenAddress,
                performancePercent24h: _topUnderperformers[i].performancePercent24h, performanceVsMarketPercent: _topUnderperformers[i].performanceVsMarketPercent,
                lastUpdatedAt: block.timestamp
            }));
        }
        marketAverageMovementPercent24h = _marketAvgMove24h;
        marketPerformanceLastUpdatedAt = block.timestamp;
        emit MarketPerformersUpdated(_marketAvgMove24h, block.timestamp);
    }

    // ------- ALERT CREATION FUNCTIONS (Chia làm 2 hàm) -------

    function SingleThresholdNetflowAlert( 
        AlertCondition _condition,
        int256 _threshold1,
        string calldata _message
    ) external onlyOwner {
        require(
            _condition == AlertCondition.GREATER_THAN ||    //1    
            _condition == AlertCondition.LESS_THAN ||       //2
            _condition == AlertCondition.EQUAL_TO ||        //3
            _condition == AlertCondition.CROSSING ||        //4
            _condition == AlertCondition.CROSSING_UP ||     //5
            _condition == AlertCondition.CROSSING_DOWN ||   //6
            _condition == AlertCondition.MOVING_UP ||       //7
            _condition == AlertCondition.MOVING_DOWN,       //8
            "Dashboard: Invalid condition for single threshold alert"
        );
        uint256 newAlertId = nextAlertId++;
            NetflowAlert memory newAlert = NetflowAlert({
            id: newAlertId,
            user: msg.sender,
            condition: _condition,
            threshold1: _threshold1,
            threshold2: 0,
            message: _message,
            isActive: true,
            isTriggered: false,
            lastTriggeredAt: 0
        });
        if (userNetflowAlert.id == 0) {
             userNetflowAlert.id = nextAlertId++;
        }
        userNetflowAlert.user = msg.sender; 
        userNetflowAlert.condition = _condition;
        userNetflowAlert.threshold1 = _threshold1;
        userNetflowAlert.threshold2 = 0; 
        userNetflowAlert.message = _message;
        userNetflowAlert.isActive = true;
        userNetflowAlert.isTriggered = false;
        userNetflowAlert.lastTriggeredAt = 0;

        userNetflowAlerts.push(newAlert);
        emit AlertConfigured(userNetflowAlert.id, msg.sender, _condition, _threshold1, 0, _message);
    }

    function DoubleNetflowAlert( 
        AlertCondition _condition,
        int256 _channelBound1,
        int256 _channelBound2,
        string calldata _message
    ) external onlyOwner {
        require(
            _condition == AlertCondition.ENTERING_CHANNEL || //7
            _condition == AlertCondition.EXITING_CHANNEL || //8
            _condition == AlertCondition.INSIDE_CHANNEL || //9
            _condition == AlertCondition.OUTSIDE_CHANNEL, //10
            "Dashboard: Invalid condition for channel alert"
        );
        require(_channelBound1 != _channelBound2, "Dashboard: Channel bounds must be different");

        if (userNetflowAlert.id == 0) {
             userNetflowAlert.id = nextAlertId++;
        }
        uint256 newAlertId = nextAlertId++;
        int256 t1;
        int256 t2;
        userNetflowAlert.user = msg.sender;
        userNetflowAlert.condition = _condition;
        if (_channelBound1 < _channelBound2) {
            userNetflowAlert.threshold1 = _channelBound1;
            userNetflowAlert.threshold2 = _channelBound2;
        } else {
            userNetflowAlert.threshold1 = _channelBound2;
            userNetflowAlert.threshold2 = _channelBound1;
        }
        userNetflowAlert.message = _message;
        userNetflowAlert.isActive = true;
        userNetflowAlert.isTriggered = false;
        userNetflowAlert.lastTriggeredAt = 0;
        
        NetflowAlert memory newAlert = NetflowAlert({
            id: newAlertId,
            user: msg.sender,
            condition: _condition,
            threshold1: t1,
            threshold2: t2,
            message: _message,
            isActive: true,
            isTriggered: false,
            lastTriggeredAt: 0
        });
        userNetflowAlerts.push(newAlert);
        emit AlertConfigured(userNetflowAlert.id, msg.sender, _condition, userNetflowAlert.threshold1, userNetflowAlert.threshold2, _message);
    }


    // ------- CHECK ALERT LOGIC -------
    function checkAndTriggerAlert(
        int256 _currentValue, int256 _previousValue, bool _hasPreviousValue
    ) internal {
        if (!userNetflowAlert.isActive || userNetflowAlert.isTriggered || userNetflowAlert.id == 0) {
            return;
        }
        bool triggered = false;
        AlertCondition condition = userNetflowAlert.condition;
        int256 threshold1 = userNetflowAlert.threshold1;
        int256 lowerChannelBound = userNetflowAlert.threshold1; 
        int256 upperChannelBound = userNetflowAlert.threshold2; 

        if (condition == AlertCondition.GREATER_THAN) {
            if (_currentValue > threshold1) triggered = true;
        } else if (condition == AlertCondition.LESS_THAN) {
            if (_currentValue < threshold1) triggered = true;
        } else if (condition == AlertCondition.EQUAL_TO) {
            if (_currentValue == threshold1) triggered = true;
        } else if (_hasPreviousValue) {
            if (condition == AlertCondition.CROSSING) {
                if ((_previousValue < threshold1 && _currentValue >= threshold1) ||
                    (_previousValue > threshold1 && _currentValue <= threshold1)) triggered = true;
            } else if (condition == AlertCondition.CROSSING_UP) {
                if (_previousValue < threshold1 && _currentValue >= threshold1) triggered = true;
            } else if (condition == AlertCondition.CROSSING_DOWN) {
                if (_previousValue > threshold1 && _currentValue <= threshold1) triggered = true;
            } else if (condition == AlertCondition.ENTERING_CHANNEL) {
                bool previouslyOutside = (_previousValue < lowerChannelBound || _previousValue > upperChannelBound);
                bool currentlyInside = (_currentValue >= lowerChannelBound && _currentValue <= upperChannelBound);
                if (previouslyOutside && currentlyInside) triggered = true;
            } else if (condition == AlertCondition.EXITING_CHANNEL) {
                bool previouslyInside = (_previousValue >= lowerChannelBound && _previousValue <= upperChannelBound);
                bool currentlyOutside = (_currentValue < lowerChannelBound || _currentValue > upperChannelBound);
                if (previouslyInside && currentlyOutside) triggered = true;
            } else if (condition == AlertCondition.INSIDE_CHANNEL) {
                if (_currentValue >= lowerChannelBound && _currentValue <= upperChannelBound) triggered = true;
            } else if (condition == AlertCondition.OUTSIDE_CHANNEL) {
                if (_currentValue < lowerChannelBound || _currentValue > upperChannelBound) triggered = true;
            } else if (condition == AlertCondition.MOVING_UP) {
                if (_currentValue > _previousValue) triggered = true;
            } else if (condition == AlertCondition.MOVING_DOWN) {
                if (_currentValue < _previousValue) triggered = true;
            }
        }

        if (triggered) {
            userNetflowAlert.isTriggered = true;
            userNetflowAlert.lastTriggeredAt = block.timestamp;
            emit AlertTriggered(userNetflowAlert.id, userNetflowAlert.user, _currentValue, userNetflowAlert.message);
        }
    }

    // ------- ALERT MANAGEMENT FUNCTIONS -------
    function turnOffAlert() external onlyOwner {
        if(userNetflowAlert.id != 0 && userNetflowAlert.isActive){
            userNetflowAlert.isActive = false;
            emit AlertDeactivated(userNetflowAlert.id);
        }
    }

    function activateAlert() external onlyOwner {
         if(userNetflowAlert.id != 0 && !userNetflowAlert.isActive){
            userNetflowAlert.isActive = true;
            userNetflowAlert.isTriggered = false; 
            emit AlertActivated(userNetflowAlert.id);
        }
    }

    function resetAlertTriggerState() external onlyOwner {
        if(userNetflowAlert.id != 0 && userNetflowAlert.isTriggered) {
            userNetflowAlert.isTriggered = false;
            userNetflowAlert.lastTriggeredAt = 0;
            emit AlertTriggerReset(userNetflowAlert.id);
        }
    }

    // ------- GETTER FUNCTIONS -------
    function getAllNetflowAlerts() external view returns (NetflowAlert[] memory alerts) {
        return userNetflowAlerts;
    }

    function getAllNarrativeKeys() external view returns (string[] memory) {
        return narrativeKeys;
    }
    function getNarrativePerformance(string calldata _narrativeName) external view returns (NarrativePerformanceInfo memory) {
        return narrativePerformances[_narrativeName];
    }
    function getNarrativeTopPerformer(string calldata _narrativeName) external view returns (NarrativeTopTokenInfo memory) {
        return narrativeTopPerformers[_narrativeName];
    }
    function getTopOutperformingAssets() external view returns (AssetPerformanceInfo[] memory) {
        return topOutperformingAssets;
    }
    function getTopUnderperformingAssets() external view returns (AssetPerformanceInfo[] memory) {
        return topUnderperformingAssets;
    }

    // ------- HELPER FUNCTIONS -------
    function removeNarrativeKey(string calldata _narrativeName) external onlyOwner {
        bool found = false;
        uint indexToRemove = 0;
        for (uint i = 0; i < narrativeKeys.length; i++) {
            if (keccak256(abi.encodePacked(narrativeKeys[i])) == keccak256(abi.encodePacked(_narrativeName))) {
                found = true;
                indexToRemove = i;
                break;
            }
        }
        if (found) {
            delete narrativePerformances[_narrativeName]; // Xóa mapping entry
            if (narrativeKeys.length > 0 && indexToRemove < narrativeKeys.length) { // Xóa khỏi mảng keys
                narrativeKeys[indexToRemove] = narrativeKeys[narrativeKeys.length - 1];
                narrativeKeys.pop();
                emit NarrativeKeyRemoved(_narrativeName);
            }
        }
    }
}