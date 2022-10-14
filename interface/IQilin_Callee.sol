pragma solidity ^0.8.4;

interface IQilin_Callee {
    function Qilin_Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}