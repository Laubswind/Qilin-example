pragma solidity ^0.8.4;

// a library for performing various math operations

library Math {

    //求二者最大值
    function max(uint x, uint y) internal pure returns (uint z) {
        z = x > y ? x : y;
    }

    // 求三者中最小值
    function min3(uint x, uint y,uint z) internal pure returns (uint u) {
        x = x < y ? x : y;
        u = x < z ? x : z;
    }

    // 求平方根 babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(int y) internal pure returns (int z) {
        if (y > 3) {
            z = y;
            int x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // 求立方根 Newton's method (https://en.wikipedia.org/wiki/Cube_root#Numerical_methods) 
    function cbrt(int y) internal pure returns (int z) {
        if (y > 8) {
            z = y;
            int x = y / 3 + 1;
            while (x < z) {
                z = x;
                x = (y / (x * x) + 2 * x) / 3;
            }
        }else if (y != 0) {
            z = 1;
        }
    }

    // 价格公式
    function cal_price(int B,int C, int D, int X, int Y) internal pure returns(int P){
        P = (4 * C * X * X * Y * Y + D * D * D * X) * 1e18 / (4 * B * X * X * Y * Y + D * D * D * Y);
    }

    // 用曲线公式求X
    function cal_X(int B, int C, int D, int Y) internal pure returns(int X){
        X = (-(4 * C * Y * Y) + sqrt((4 * C * Y * Y)**2 - 16 * B * Y * (-D * D * D) * 1e18)) / (8 * B * Y); 
    }

    // 用曲线公式求Y
    function cal_Y(int B, int C, int D, int X) internal pure returns(int Y){
        Y = (-(4 * B * X * X) + sqrt((4 * B * X * X)**2 - 16 * C * X * (-D * D * D) * 1e18)) / (8 * C * X); 
    }

    // 用曲线公式求B
    function cal_B(int X, int Y, int D, int P) internal pure returns(int B){
        B = (8 * X * X * Y * Y * 1e36 + D * D * D * X * 1e36 - D * D * D * Y * P * 1e18) / (4 * X * X * Y * Y * (1e18 + P));
    }

    
}