pragma solidity ^0.8.4;

// a library for pDrforming various math opDrations

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
    function cal_price(uint B,uint C, uint D, uint X, uint Y) internal pure returns(uint P){
        P = (4 * C * X * X * Y * Y + D * D * D * X) * 1e18 / (4 * B * X * X * Y * Y + D * D * D * Y);
    }

    // 用曲线公式求X
    function cal_X(uint B, uint C, uint D, uint Y) internal pure returns(uint X){
        X = (0 - (4 * C * Y * Y) + sqrt((4 * C * Y * Y)**2 - 16 * B * Y * (0 - D * D * D) * 1e18)) / (8 * B * Y); 
    }

    // 用曲线公式求Y
    function cal_Y(uint B, uint C, uint D, uint X) internal pure returns(uint Y){
        Y = (0 - (4 * B * X * X) + sqrt((4 * B * X * X)**2 - 16 * C * X * (0 - D * D * D) * 1e18)) / (8 * C * X); 
    }

    // 用曲线公式求B
    function cal_B(uint X, uint Y, uint D, uint P) internal pure returns(uint B){
        B = (8 * X * X * Y * Y * 1e36 + D * D * D * X * 1e36 - D * D * D * Y * P * 1e18) / (4 * X * X * Y * Y * (1e18 + P));
    }

    // funding中求B
    function cal_B_f(uint X, uint Y, uint D) internal pure returns(uint B){
        B = (D * D * D / 4 / X / Y - 2 * Y) * 1E18 / (X - Y);
    }

    // funding中求interest rate
    function cal_interest(uint getp, uint True_Liquid, uint Base_rate) internal pure returns(uint I){
        I = getp * 1e18  / (True_Liquid + getp) / 57600 + Base_rate;
    }

    //swap中计算增减量
    function cal_cross(uint A, uint B, uint C) internal pure returns(uint D){
        D = (A - B) * 1e18 / C;
    }

    // 计算N值第一步 
    function cal_multi(uint A, uint B, uint C, uint D, uint E, uint F) internal pure returns(uint I){
        I = ( A * B * C + D * E * F ) * A * D;
    }

    //计算N值
    function cal_N(uint A, uint B, uint C, uint D, uint E, uint F , uint G , uint H) internal pure returns(uint z){
        z = cbrt(cal_multi(A, B, C, D, E, F) * 1e54 / cal_multi(G, B, C, H, E, F));
    }

    //
    function cal_times(uint A, uint B, uint C) internal pure returns (uint F) {
        F = A * B / C ;

    }

    function cal_times2(uint A, uint B, uint C, uint D, uint E) internal pure returns (uint F) {
        F = A * B * C / D / E;
    }


    function Get_PEPS(uint True_Liquid_X , uint True_Liquid_Y , uint Peqx , uint Peqy , uint X_Coord , uint Y_Coord, uint B ,uint C ,uint D) internal pure returns (uint PE, uint PS){
        uint256 XE = Math.cal_times( True_Liquid_X , Peqx , 1e18 );
        uint256 YE = Math.cal_times( True_Liquid_Y , Peqy , 1e18 );
        uint256 BE = Math.cal_B_f(XE, YE, D);
        uint256 CE = 2 * 1e18 - BE;
        PE = Math.cal_times( Math.cal_price(BE, CE, D, XE, YE) , Peqy , Peqx );
        PS = Math.cal_times( Math.cal_price(B, C, D, X_Coord, Y_Coord) , Peqy , Peqx );
    }

    function Get_funding(uint PE, uint PS , uint Xgetp , uint Ygetp , uint Base_rate , uint funding_x_8h_upper , uint True_Liquid_X , uint True_Liquid_Y) internal pure returns (uint funding_x , bool paying_side){
        if(PS > PE){
            funding_x = Math.cal_cross(PS , PE , PE) / 5760 + Math.cal_interest(Ygetp , True_Liquid_Y , Base_rate);
            paying_side = false;
        }else{
            funding_x = Math.cal_cross(PE , PS , PE) / 5760 + Math.cal_interest(Xgetp , True_Liquid_X , Base_rate);
            paying_side = true;
        }
        if(funding_x * 1920 > funding_x_8h_upper){
            funding_x = funding_x_8h_upper / 1920;
        }
    }





    
}