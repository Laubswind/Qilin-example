pragma solidity ^0.8.4;

contract B {
    uint256 public param1 = 7;
    uint256 public param2 = 8;
    uint256 public param3 = 9;
    mapping(uint256 => bool ) public answer;
    uint256[] public test;
    struct debtbook{
        address user_ID;
        bool token_ID; 
        uint debttoken_amount;
        uint position_amount;
    }

    mapping(uint => mapping(bool => debtbook)) public debt_index; 


    //function ini() public{
    //    answer[0] = false;
    //    answer[1] = false;
    //}


    function delegatecallSetVars(address _addr, uint _num) external payable{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("SetParam(uint256)", _num)
        );
    }

    function delegatecallSetAnswer(address _addr, uint256 _num) external payable{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("SetAnswer(uint256)", _num)
        );
    }

    function delegatecallSetTest(address _addr, uint256 _num) external payable{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("SetTest(uint256)", _num)
        );
    }

}