pragma solidity ^0.8.4;

import '../Qilin_Pool.sol';

// a library for pDrforming various math opDrations

library Math {

    //求二者最大值
    function max(uint x, uint y) internal pure returns (uint z) {
        z = x > y ? x : y;
    }

    // minimum of two
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x > y ? y : x;
    }

    // 求三者中最小值
    function min3(uint x, uint y,uint z) internal pure returns (uint u) {
        x = x < y ? x : y;
        u = x < z ? x : z;
    }

    // 求平方根 babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // 求立方根 Newton's method (https://en.wikipedia.org/wiki/Cube_root#Numerical_methods) 
    function cbrt(uint y) internal pure returns (uint z) {
        if (y > 8) {
            z = y;
            uint x = y / 3 + 1;
            while (x < z) {
                z = x;
                x = (y / (x * x) + 2 * x) / 3;
            }
        }else if (y != 0) {
            z = 1;
        }
    }

    // 价格公式
    function calPrice(uint B,uint C, uint D, uint X, uint Y) internal pure returns(uint P){
        P = (4 * C * X * X * Y * Y + D * D * D * X) * 1e18 / (4 * B * X * X * Y * Y + D * D * D * Y);
    }

    // 用曲线公式求X
    function calX(uint B, uint C, uint D, uint Y) internal pure returns(uint X){
        X = (0 - (4 * C * Y * Y) + sqrt((4 * C * Y * Y)**2 - 16 * B * Y * (0 - D * D * D) * 1e18)) / (8 * B * Y); 
    }

    // 用曲线公式求Y
    function calY(uint B, uint C, uint D, uint X) internal pure returns(uint Y){
        Y = (0 - (4 * B * X * X) + sqrt((4 * B * X * X)**2 - 16 * C * X * (0 - D * D * D) * 1e18)) / (8 * C * X); 
    }

    // 用曲线公式求B
    function calB(uint D, uint P) internal pure returns(uint B){
        uint X = D/2;
        uint Y = D/2;
        B = (8 * X * X * Y * Y * 1e36 + D * D * D * X * 1e36 - D * D * D * Y * P * 1e18) / (4 * X * X * Y * Y * (1e18 + P));
    }

    // funding中求B
    function calBE(uint X, uint Y, uint D) internal pure returns(uint B){
        B = (D * D * D / 4 / X / Y - 2 * Y) * 1E18 / (X - Y);
    }

    // funding中求interest rate
    function calInterest(uint getp, uint True_Liquid, uint baserate) internal pure returns(uint I){
        I = getp * 1e18  / (True_Liquid + getp) / 57600 + baserate;
    }

    //swap中计算增减量
    function calCross(uint A, uint B, uint C) internal pure returns(uint D){
        D = (A - B) * 1e18 / C;
    }

    // 计算N值第一步 
    function calMulti(uint A, uint B, uint C, uint D, uint E, uint F) internal pure returns(uint I){
        I = ( A * B * C + D * E * F ) * A * D;
    }

    //计算N值
    function calN(uint A, uint B, uint C, uint D, uint E, uint F , uint G , uint H) internal pure returns(uint z){
        z = cbrt(calMulti(A, B, C, D, E, F) * 1e54 / calMulti(G, B, C, H, E, F));
    }

    //
    function calTimes(uint A, uint B, uint C) internal pure returns (uint F) {
        F = A * B / C ;

    }

    function calTimes2(uint A, uint B, uint C, uint D, uint E) internal pure returns (uint F) {
        F = A * B * C / D / E;
    }


    function getPEPS(uint trueLiquidX , uint trueLiquidY , uint peqX , uint peqY , uint coordX , uint coordY, uint B ,uint C ,uint D) internal pure returns (uint PE, uint PS){
        uint256 XE = Math.calTimes( trueLiquidX , peqX , 1e18 );
        uint256 YE = Math.calTimes( trueLiquidY , peqY , 1e18 );
        uint256 BE = Math.calBE(XE, YE, D);
        uint256 CE = 2 * 1e18 - BE;
        PE = Math.calTimes( Math.calPrice(BE, CE, D, XE, YE) , peqY , peqX );
        PS = Math.calTimes( Math.calPrice(B, C, D, coordX, coordY) , peqY , peqX );
    }

    function getFunding(uint PE, uint PS , uint getpX , uint getpY , uint baserate , uint upperFunding8H , uint trueLiquidX , uint trueLiquidY) internal pure returns (uint funding_x , bool paying_side){
        if(PS > PE){
            funding_x = Math.calCross(PS , PE , PE) / 5760 + Math.calInterest(getpY , trueLiquidY , baserate);
            paying_side = false;
        }else{
            funding_x = Math.calCross(PE , PS , PE) / 5760 + Math.calInterest(getpX , trueLiquidX , baserate);
            paying_side = true;
        }
        if(funding_x * 1920 > upperFunding8H){
            funding_x = upperFunding8H / 1920;
        }
    }


    // 计算N值第一步 
    function calTestN(uint256 A, uint256 B, uint256 C, uint256 D, uint256 E, uint256 F , uint256 G , uint256 H) internal pure returns(uint256 I){
        I = A * B * C + D * E * F ;
        I = I / ( G * B * C + H * E * F );
        I = I * A * D / G / H;
    }

    function calC(uint _B) internal returns(uint C){
        C = 2 * 1e18 - _B;
    }
 }