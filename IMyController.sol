// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interface/IMyController.sol";
import "./MyToken.sol";
import "./utilContracts/MyUtility.sol";

contract MyController is IMyController {

    address private immutable myGovernmentAddress;

    mapping(address => Role) private myUserRoleMap;
    mapping(address => UserData) private myUserInformationMap;

    mapping(uint256 => address) private myProjectMap;
    mapping(address => uint256) private myAddressToIdMap;
    mapping(uint256 => bool) private myProjectIsTransactionAvailable;
    uint256 private myAvailableProjectId;

    mapping(address => mapping(uint16 => uint256)) private myUserPaymentsMap;
    uint256 private myAvailableMoneyRequestId;
    mapping(uint256 => MoneyRequest) myMoneyRequestMap;

    constructor(){
        myGovernmentAddress = msg.sender;
        myUserRoleMap[msg.sender] = Role.Gov;
        myAvailableProjectId = 0;
        myAvailableMoneyRequestId = 1;
    }

    modifier onlyGov() {
        requireGov();
        _;
    }

    modifier onlySecondaryAuth() {
        require(
            isSenderGovAddress() || myUserRoleMap[msg.sender] == Role.Admin,
            "You don't have the authority to access. ERROR:1"
        );
        _;
    }

    modifier onlyRegisterdUser() {
        require(
            myUserRoleMap[msg.sender] != Role.NotRegisterd,
            "You haven't registered yet. ERROR:3"
        );
        _;
    }

    modifier onlyTransactionAvailableProjectToken() {
        require(
            myProjectIsTransactionAvailable[myAddressToIdMap[msg.sender]],
            "Contract money request blocked. ERROR:4"
        );
        _;
    }

    modifier onlyValidProjectOwner(address projectOwner){
        require(myUserRoleMap[projectOwner] == Role.ProjectOwner, "Invalid project owner. Error:7");
        _;
    }

    modifier onlyValidRequestId(uint256 requestId){
        MoneyRequest memory moneyRequest = myMoneyRequestMap[requestId];
        require(
            (moneyRequest.requestId != 0) && 
            (moneyRequest.status == ProjectMoneyEventType.SendMoneyRequest),
            "Invalid request id. Error:8"
        );
        _;
    }

    modifier onlyHaveMoney(uint256 requestId){
        require(address(this).balance >= myMoneyRequestMap[requestId].money, "Insufficient funds in the contract. Error:6");
        _;
    }

    modifier onlyApprovalAvailable(uint256 requestId){
        require(myMoneyRequestMap[requestId].approvedBy == address(0), "Approval not available. Error:9");
        _;
    }

    function isSenderGovAddress() private view returns (bool) {
        return (msg.sender == myGovernmentAddress);
    }

    function requireGov() private view {
        require(isSenderGovAddress(), "You don't have the authority to access. ERROR:0");
    }

    function setUserData(bytes calldata userInfo, address userAddress) private {
        myUserInformationMap[userAddress].userInfo = userInfo;
    }

    function getUserData(address userAddress) private view returns(UserData memory){
        return myUserInformationMap[userAddress];
    }

    function getUserRole() external view returns (Role) {
        return myUserRoleMap[msg.sender];
    }

    function setUserRole(
        address newUserAddress,
        Role role,
        bytes calldata userInfo
    ) external onlySecondaryAuth {

        if(role == Role.Admin){
            requireGov();
        }
        require(role != Role.Gov, "You don't have authority to add this role: Error:2");

        myUserRoleMap[newUserAddress] = role;
        setUserData(userInfo,newUserAddress);

        emit registerNewUserAddress(newUserAddress, role);
    }

    function getMyUserData() external view returns(UserData memory){
        return getUserData(msg.sender);
    }

    function getIndividualUserData(address userAddress) external view onlySecondaryAuth returns (UserData memory){
        return getUserData(userAddress);
    }

    function createNewProject(bytes memory projectImmutableData, string memory projectName, address projectOwner) external onlySecondaryAuth onlyValidProjectOwner(projectOwner){

        address newProjectAddress = address(new MyToken(projectImmutableData, projectName, myAvailableProjectId, projectOwner));

        myProjectMap[myAvailableProjectId] = newProjectAddress;
        myProjectIsTransactionAvailable[myAvailableProjectId] = true;
        myAddressToIdMap[newProjectAddress] = myAvailableProjectId;

        emit createNewProjectToken(myAvailableProjectId, newProjectAddress, projectName);

        myAvailableProjectId++;
    }

    function payTax(uint16 year) external payable onlyRegisterdUser{
        myUserPaymentsMap[msg.sender][year] += msg.value;
        emit taxPayment(msg.sender, year, msg.value);
    } 

    function getMyTaxPaymentDataInYear(uint16 year) external view returns(uint){
        return myUserPaymentsMap[msg.sender][year];
    }

    function getIndividualUserTaxPaymentDataInYear(address user, uint16 year) external view onlySecondaryAuth returns(uint){
        return myUserPaymentsMap[user][year];
    }

    function getProjectById(uint256 id) external view returns(address){
        return myProjectMap[id];
    }

    function changeTokenMoneyRequestingState(uint256 tokenId, bool state) external onlySecondaryAuth {
        myProjectIsTransactionAvailable[tokenId] = state;
        emit changeTokenMoneyRequestingStateEvent(tokenId, state);
    }

    function projectMoneyRequest(MoneyRequest memory moneyRequest) external override onlyTransactionAvailableProjectToken returns(uint256) {
        moneyRequest.requestId = myAvailableMoneyRequestId;
        myMoneyRequestMap[myAvailableMoneyRequestId] = moneyRequest;

        emit projectMoneyRequestEvent(msg.sender, moneyRequest.tokenId, myAvailableMoneyRequestId, moneyRequest.money, moneyRequest.requestReason);
        myAvailableMoneyRequestId++;

        return moneyRequest.requestId;
    }

    function rejectMoneyRequest(uint256 requestId, string calldata reason) external onlySecondaryAuth onlyValidRequestId(requestId){
        MoneyRequest memory moneyRequest = myMoneyRequestMap[requestId];

        moneyRequest.status = ProjectMoneyEventType.Rejected;
        moneyRequest.rejectedBy = msg.sender;
        moneyRequest.rejectReason = reason;

        myMoneyRequestMap[moneyRequest.requestId] = moneyRequest;

        emit rejectMoneyRequestEvent(requestId, msg.sender, moneyRequest.money, reason);
    }

    function approveMoneyRequest(uint256 requestId) external onlySecondaryAuth onlyValidRequestId(requestId) onlyHaveMoney(requestId){
        MoneyRequest memory moneyRequest = myMoneyRequestMap[requestId];

        moneyRequest.status = ProjectMoneyEventType.Approved;
        moneyRequest.approvedBy = msg.sender;
        myMoneyRequestMap[moneyRequest.requestId] = moneyRequest;

        address tokenAddress = myProjectMap[moneyRequest.tokenId];
        (bool success, ) = tokenAddress.call{value: moneyRequest.money}("");
        require(success, "Transfer to Money failed");

        emit approveMoneyRequestEvent(requestId, msg.sender, moneyRequest.money);
    }
}
