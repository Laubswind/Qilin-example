pragma solidity ^0.8.4;

import './libraries/Math.sol';
import './libraries/Safemath.sol';
import './interface/IERC20.sol';
import './interface/IQilin_Factory.sol';
import './interface/IQilin_Callee.sol';
import './interface/IQilin_Pool.sol';
import './QilinERC20.sol';

contract PoolLogic{

    /* ========== STATE VARIABLES ========== */
    uint256 public B;
    uint256 public D;
    uint256 public D0;
    uint256 public coordX; 
    uint256 public coordY;
    uint256 public peqX;
    uint256 public peqY;
    uint256 public getpX;
    uint256 public getpY;
    uint256 public trueLiquidX0;
    uint256 public trueLiquidY0;
    uint256 public trueLiquidX;
    uint256 public trueLiquidY;
    uint256 public priceLocal;
    uint256 public totalDebtX;
    uint256 public totalDebtY;
    uint256 public totalDebttokenX;
    uint256 public totalDebttokenY;
    uint256 public leverageMax;                    //固定值，留接口修改
    uint256 public lastFunding;                    //系统内记录上一次funding值
    uint256 public lastFundingTime;                //系统内记录上一次funding时间
    bool public lastPayingSide;                    //系统内记录上一次funding方向
    uint256 public upperFunding8H;                 //= 5000000000固定值，留接口修改
    address public factory;
    address public tokenX;
    address public tokenY;
    uint256 public marginLeverage;                 //开仓杠杆 18位
    uint256 public totalLiquidity;                 //LPtoken总值
    uint256 public liquidationRate;                //维持保证金率
    uint256 public const18 = 1e18;
    address public _addr;                          //logic 合约地址 可变更
    uint256 public liquidationBonus;
    uint256 public tickrange;
    uint256 public baserate;                       //= 156200，固定值，留接口修改
    uint256 public swapFee;
    uint256 public perpFee;
    bool public twoWhite;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    uint private unlocked = 1;
    uint8 limitation = 0;                          // 0 , 1 , 2 三个档位
    
    struct debtbook{
        address user_ID;
        bool token_ID; 
        uint debttokenAmount;
        uint positionAmount;
    }

    uint[2] public marginReserve;   //记录保证金的总存储量
    mapping(address => mapping(bool => debtbook)) public debtIndex;  //将用户address + 债务token（左侧资产还是右侧资产）与存储其debt_token和仓位 对应
    mapping(address => uint[2]) public marginIndex;  //将用户address与存储其保证金的数组对应


    /* ========== MODIFIERS ========== */
    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /* ========== EVENTS ========== */

    /* ========== VIEWS ========== */

    // 虚拟流动性更新
    function _virtualLiquidityUpdate() internal view returns (uint _D){
        uint N = Math.calN(trueLiquidX , B , peqX , trueLiquidY , 2 * 1e18 - B , peqY , trueLiquidX0 , trueLiquidY0); 
        _D = D0 * N / const18;
    }

    //求保证金净值
    function netMargin(address userID) internal view returns(uint net){
        net = marginIndex[userID][0] + Math.calTimes2(marginIndex[userID][1] ,  priceLocal , peqY , peqX , const18);
        
    }

    //求仓位净值 注：36位
    function netPosition(address userID) internal view returns(uint net){
        net = debtIndex[userID][false].positionAmount + Math.calTimes2(debtIndex[userID][true].positionAmount , priceLocal , peqY , peqX , const18 );
    }

    //求债务净值
    function netDebt(address userID) internal view returns(uint net){
        net = Math.calTimes(debtIndex[userID][true].debttokenAmount ,  totalDebtY , totalDebttokenY) + Math.calTimes( Math.calTimes2(debtIndex[userID][false].debttokenAmount ,  totalDebtX , priceLocal , totalDebttokenX , const18) , peqY , peqX);
    }



    /* ========== MUTATIVE FUNCTIONS ========== */

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }


    //现货/合约 交易，用X买Y input为 delta：用户支付的X值，perp：是否为合约交易，output为 Yget：用户支付的X值所能换出的Y值
    function _tradeXToY(uint deltaX, bool perp, uint exactY) internal lock returns(uint Yget) {

        uint Xin;
        while(deltaX - Xin > Math.calCross(Math.calTimes(D/2 , tickrange , const18), coordX, peqX)){
            //计算此时曲线内触发跨tick的X值
            uint coordTestX = Math.calTimes(D/2 , tickrange , const18);

            //计算对应的Y值
            uint coordTestY = Math.calY(B, Math.calC(B), D, coordTestX);


            if( exactY > 0 && Yget + Math.calCross(coordY, coordTestY, peqY) > exactY) break;

            Yget += Math.calCross(coordY, coordTestY, peqY);

            //deltaX减少跨tick所用的这部分X
            Xin += Math.calCross(coordTestX, coordX, peqX);

            //如果是perp交易，则累加系统内总的Y Position
            if(perp == false) {
                trueLiquidX += Math.calCross(coordTestX, coordX, peqX);
                trueLiquidY -= Math.calCross(coordY, coordTestY, peqY);
            }

            // 按照跨tick后系统状态更新peqX peqY
            peqY = Math.calTimes(peqY , D/2 , coordTestY);
            peqX = Math.calTimes(peqX , D/2 , coordTestX);

            //计算跨tick后的曲线斜率所对应的priceLocal
            priceLocal = Math.calTimes2 (Math.calPrice(B, Math.calC(B), D, coordTestX, coordTestY) , coordTestY , D/2 , coordTestX , D/2 );
            
            //更新 跨tick后X Y坐标
            //计算此时对应的B C值
            B = Math.calB(D, priceLocal);
            //C = 2 * const18 - B; 

            //根据新的各参数 更正流动性
            D = _virtualLiquidityUpdate();
            //将更新流动性后的参数传入曲线
            coordX = D/2;
            coordY = D/2;

        }
        
        uint coordLastX = coordX;
        uint coordLastY = coordY;
        if(exactY == 0){
            coordX +=  Math.calTimes(deltaX - Xin, peqX , const18);
            coordY = Math.calY(B, Math.calC(B), D, coordX);
        }else{
            coordY -= Math.calTimes(exactY - Yget, peqY , const18);
            coordX = Math.calX(B, Math.calC(B), D, coordY);
        }
        Yget += Math.calCross(coordLastY, coordY, peqY);
        Xin += Math.calCross(coordX, coordLastX, peqX);
        if(perp == true){
            getpY += Yget;
        }else{
            trueLiquidX += Math.calCross(coordX, coordLastX, peqX);
            trueLiquidY -= Math.calCross(coordLastY, coordY, peqY);
        } 
            
        
    }

    //现货/合约  交易，用Y买X input为Y
    function _tradeYToX(uint deltaY , bool perp , uint exactX) internal lock returns(uint Xget) {

        uint Yin;
        while(deltaY - Yin > Math.calCross(Math.calTimes(D/2 , tickrange , const18), coordY, peqY)){

            uint coordTestY = Math.calTimes(D/2 , tickrange , const18);
            uint coordTestX = Math.calX(B, Math.calC(B), D, coordTestY);

            if(exactX > 0 && Xget + Math.calCross(coordX, coordTestX, peqX) > exactX ) break;

            Xget += Math.calCross(coordX, coordTestX, peqX);
            Yin += Math.calCross(coordTestY, coordY, peqY);

            if(perp == false){
                trueLiquidX -= Math.calCross(coordX, coordTestX, peqX);
                trueLiquidY += Math.calCross(coordTestY, coordY, peqY);
            }

            peqY = Math.calTimes(peqY , D/2 , coordTestY);
            peqX = Math.calTimes(peqX , D/2 , coordTestX);
            priceLocal = Math.calTimes2 (Math.calPrice(B, Math.calC(B), D, coordTestX, coordTestY) , coordTestY , D/2 , coordTestX , D/2);
                

            B = Math.calB( D, priceLocal);
            D = _virtualLiquidityUpdate();
            coordX = D/2;
            coordY = D/2;
        }
            
        uint coordLastX = coordX;
        uint coordLastY = coordY;
        if(exactX == 0){
            coordY += Math.calTimes(deltaY - Yin, peqY , const18);
            coordX = Math.calX(B, Math.calC(B), D, coordY);
        }else{
            coordX -= Math.calTimes(exactX - Xget , peqX , const18);
            coordY = Math.calY(B, Math.calC(B), D, coordX);
        }
        Xget += Math.calCross(coordLastX, coordX, peqX);
        Yin += Math.calCross(coordY, coordLastY, peqY);
        if(perp == true){
            getpX += Xget;
        }else{
            trueLiquidY += Math.calCross(coordY, coordLastY, peqY);
            trueLiquidX -= Math.calCross(coordLastX, coordX, peqX);
        }    
    }

    //更新debt总账
    function _refreshTotalbook() internal {
        (uint PE , uint PS ) = Math.getPEPS(trueLiquidX , trueLiquidY ,  peqX , peqY , coordX , coordY , B , Math.calC(B) , D) ;
        (uint fundingX , bool payingSide) = Math.getFunding(PE, PS , getpX , getpY , baserate , upperFunding8H , trueLiquidX , trueLiquidY);
        uint timeGap = block.number - lastFundingTime;
        lastFundingTime = block.number;
        if(lastPayingSide == false){
            totalDebtX = totalDebtX + Math.calTimes2(totalDebtX , lastFunding , timeGap , const18 , 1);
            totalDebtY = totalDebtY - Math.calTimes2(lastFunding , totalDebtX , Math.calTimes(priceLocal , peqY , peqX) , const18 , const18) * timeGap;
        }else{
            totalDebtY = totalDebtY + Math.calTimes2(totalDebtY , lastFunding , timeGap , const18 , 1);
            totalDebtX = totalDebtX - Math.calTimes2(lastFunding , totalDebtY , timeGap , Math.calTimes(priceLocal , peqY , peqX) , 1);
        }
        lastFunding = fundingX; 
        lastPayingSide = payingSide;
    }


    //开仓 不允许多空同时开仓 开仓极限不能临近维持保证金线
    function perpOpen(uint deltaX, uint deltaY, bool XtoY, address userID) public lock{
        require(deltaX * deltaY == 0 && deltaX + deltaY > 0);
        _refreshTotalbook(); 
        require((netMargin(userID) +  netPosition(userID) - netDebt(userID)) * const18 / marginLeverage > Math.max (deltaX + netPosition(userID), Math.calTimes2(deltaY , priceLocal , peqY , peqX , const18) + netPosition(userID)));
        uint256 Out;
        uint256 In;
        if(XtoY == true){
            require(limitation > 0);
            if(deltaX > 0){
                Out = _tradeXToY(deltaX , true , 0);
                In = deltaX;
            }else{
                Out = deltaY;
                In = _tradeXToY(deltaY * const18 / Math.calTimes(priceLocal , peqY , peqX) , true , deltaY );//
            }
            debtIndex[userID][false].debttokenAmount += Math.calTimes(In , totalDebttokenX , totalDebtX);
            debtIndex[userID][true].positionAmount += Out;
            totalDebttokenX = Math.calTimes(In , totalDebttokenX , totalDebtX) + totalDebttokenX;
            totalDebtX += In ;
            if(marginIndex[userID][0] > In * perpFee / 1e18){
                marginIndex[userID][0] -= In * perpFee / 1e18 ;
                trueLiquidX += In * perpFee / 1e18 ;
            }else{
                uint _gap;
                _gap = In * perpFee / 1e18 - marginIndex[userID][0];
                marginIndex[userID][0] = 0;
                _gap = _tradeYToX( marginIndex[userID][1] , false , _gap );
                marginIndex[userID][1] -= _gap;
                trueLiquidY += _gap;
            }
        }else{
            require(limitation > 1);
            if(deltaX > 0){
                Out = deltaX;
                In = _tradeYToX( deltaX * Math.calTimes(priceLocal , peqY , peqX) / const18 , true , deltaX );//
            }else{
                Out = _tradeYToX(deltaY , true , 0);
                In = deltaY;
            }////
            debtIndex[userID][true].debttokenAmount += Math.calTimes(In , totalDebttokenY , totalDebtY);
            debtIndex[userID][false].positionAmount += Out;
            totalDebttokenY = Math.calTimes(In , totalDebttokenY , totalDebtY) + totalDebttokenY;
            totalDebtY += In ;
            if(marginIndex[userID][1] > In * perpFee / 1e18){
                marginIndex[userID][1] -= In * perpFee / 1e18 ;
                trueLiquidY += In * perpFee / 1e18 ;
            }else{
                uint _gap;
                _gap = In * perpFee / 1e18 - marginIndex[userID][1];
                marginIndex[userID][1] = 0;
                _gap = _tradeXToY( marginIndex[userID][0] , false , _gap );
                marginIndex[userID][0] -= _gap;
                trueLiquidX += _gap;
            }
        }
    }

    //一键 多空双开
    function perpBiopen(uint deltaX, uint deltaY, address userID) external lock{
        require(deltaX * deltaY == 0 && deltaX + deltaY > 0);
        if(deltaX > 0){
            perpOpen(deltaX , 0 , true , userID);
            perpOpen(deltaX , 0 , false, userID);
        }else{
            perpOpen(0 , deltaY , true , userID);
            perpOpen(0 , deltaY , false, userID);
        }
    }
    

    //平仓 
    function perpClose(uint deltaX, uint deltaY, address userID) public lock {
        require(deltaX * deltaY == 0 && deltaX + deltaY > 0 && netMargin(userID) + netPosition(userID) > netDebt(userID) && deltaX <= debtIndex[userID][false].positionAmount && deltaY <= debtIndex[userID][true].positionAmount);
        _refreshTotalbook();
        if(deltaX > 0){   
            uint Get = _tradeXToY(deltaX , true , 0);
            uint Y_close = Math.calTimes2(deltaX , debtIndex[userID][true].debttokenAmount , totalDebtY , totalDebttokenY , debtIndex[userID][false].positionAmount) ;
            debtIndex[userID][false].positionAmount -= deltaX;
            totalDebtY -= Y_close ; 
            totalDebttokenY -= Math.calTimes(debtIndex[userID][true].debttokenAmount , deltaX , debtIndex[userID][false].positionAmount) ;
            debtIndex[userID][true].debttokenAmount -= Math.calTimes(debtIndex[userID][true].debttokenAmount , deltaX , debtIndex[userID][false].positionAmount);

            if(Get > Y_close && twoWhite == false){
                marginIndex[userID][0] += _tradeYToX(Get - Y_close , false , 0);
            }else if(marginIndex[userID][1] + Get > Y_close && twoWhite == true){
                marginIndex[userID][1] = marginIndex[userID][1] + Get - Y_close;
            }else{
                marginIndex[userID][0] = marginIndex[userID][0] - _tradeXToY( marginIndex[userID][0], false , Y_close - Get - marginIndex[userID][1]);
                marginIndex[userID][1] = 0;
            }
        }else{
            uint Get = _tradeYToX(deltaY , true , 0);
            uint X_close = Math.calTimes2(deltaY , debtIndex[userID][false].debttokenAmount , totalDebtX , totalDebttokenX , debtIndex[userID][true].positionAmount) ;
            debtIndex[userID][true].positionAmount -= deltaY;
            totalDebtX -= X_close ; 
            totalDebttokenX -= Math.calTimes(debtIndex[userID][false].debttokenAmount , deltaY , debtIndex[userID][true].positionAmount) ;
            debtIndex[userID][false].debttokenAmount -= Math.calTimes(debtIndex[userID][false].debttokenAmount , deltaY , debtIndex[userID][true].positionAmount);
            
            if(marginIndex[userID][0] + Get > X_close){
                marginIndex[userID][0] = marginIndex[userID][0] + Get - X_close;
            }else{
                marginIndex[userID][1] = marginIndex[userID][1] - _tradeYToX( marginIndex[userID][1], false , X_close - Get - marginIndex[userID][0]);
                marginIndex[userID][0] = 0;
            }
        }
    }



    

    //清算 待修改
    function liquidate(address userID, address _to) external lock {
        require(netMargin(userID) + netPosition(userID) <= netDebt(userID) || netMargin(userID) + netPosition(userID) - netDebt(userID) <= netPosition(userID) * liquidationRate);
        _safeTransfer(tokenX, _to ,  marginIndex[userID][0] * liquidationBonus);
        _safeTransfer(tokenY, _to ,  marginIndex[userID][1] * liquidationBonus);
        delete marginIndex[userID]; //
        debtIndex[userID][false].debttokenAmount = 0;
        debtIndex[userID][true].debttokenAmount = 0;
        perpClose(debtIndex[userID][false].positionAmount, debtIndex[userID][true].positionAmount, userID);
    }/////

    //加保证金
    //function addMargin(uint newMargin , address tokenID , address userID) external lock {
    //    if(tokenID == tokenY && twoWhite == true){
    //        newMargin = newMargin - trueLiquidY - marginReserve[1];
    //        marginIndex[userID][1] += newMargin;
    //        marginReserve[1] += newMargin;
    //    }else{
    //        newMargin = newMargin - trueLiquidX - marginReserve[0];
    //        marginIndex[userID][0] += newMargin;
    //        marginReserve[0] += newMargin;
    //    }
    //}//

    //提取保证金
    function withdrawMargin (address userID , address tokenID, address to, uint amount) external lock {
        if(tokenID == tokenX){
            require(marginIndex[userID][0] > amount);
            marginIndex[userID][0] -= amount;
        }else{
            require(marginIndex[userID][1] > amount);
            marginIndex[userID][1] -= amount;
        }
        require(netMargin(userID) + netPosition(userID) > netDebt(userID) && netMargin(userID) + netPosition(userID) - netDebt(userID) > netPosition(userID) * liquidationRate);
        _safeTransfer(tokenID, to, amount);
    }

}