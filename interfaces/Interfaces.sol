// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../structs/DataTypes.sol";

interface IDashboardNotifier {
    function notifyNetflowUpdate(DataTypes.NetflowInfo calldata netflow) external;
    function notifyAlertTriggered(uint256 alertId, address user, string calldata message) external;
    // Thêm các hàm notify cho các loại dữ liệu khác nếu cần
}

interface IDashboardRegistry {
    function registerDataContract(string calldata dataType, address contractAddress) external;
}

interface IDataSpecificContract_Netflow { // Interface cho contract con cụ thể
    function updateNetflow(int256 _amount) external;
    function getCurrentNetflow() external view returns (DataTypes.NetflowInfo memory);
    // Thêm các hàm khác của contract con nếu Factory cần gọi
}