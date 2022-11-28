pragma solidity ^0.8.4;

contract A {
    uint256 public param1 = 7;
    uint256 public param2 = 8;
    uint256 public param3 = 9;
    mapping(uint256 => bool ) public answer;
    uint256[] public test = new uint[](1);
    struct debtbook{
        address user_ID;
        bool token_ID; 
        uint debttoken_amount;
        uint position_amount;
    }

    mapping(uint => mapping(bool => debtbook)) public debt_index; 

    function min3(uint x, uint y,uint z) public pure returns (uint u) {
        x = x < y ? x : y;
        u = x < z ? x : z;
    }

    function uni () public {
        param1 = min3(param1 , param2 , param3);
        param2 = param1 + 1;
        param3 = param2 + 1;
    }

    function SetAnswer (uint256 u) public{
        for(uint i = 0; i < u; i++){
        debt_index[i][true].token_ID = true;
        }
    }


    function SetParam(uint256 param4) public {
        param1 *= param4;
        param2 *= param4;
        param3 *= param4;
        uni();
    }

    function SetTest(uint256 param5) public {
        test[0] = param5;
        test.push(2);
        test[1] = param5;
    }



}