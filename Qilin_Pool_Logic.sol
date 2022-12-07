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
    uint256 public B;                             // equation variable B
    uint256 public D;                             // equation variable D
    uint256 public D0;                            // initial D value
    uint256 public coordX;                        // coordinate of X on curve
    uint256 public coordY;                        // coordinate of Y on curve
    uint256 public peqX;                          // the increase  of X coordinate when 1 unit of X liquidity increases
    uint256 public peqY;                          // the increase  of Y coordinate when 1 unit of X liquidity increases
    uint256 public getpX;                         // sum of positions recorded in X
    uint256 public getpY;                         // sum of positions recorded in Y
    uint256 public trueLiquidX0;                  // initial X true liquidity
    uint256 public trueLiquidY0;                  // initial Y true liquidity
    uint256 public trueLiquidX;                   // X true liquidity
    uint256 public trueLiquidY;                   // Y true liquidity
    uint256 public priceLocal;                    // negative reciprocal of the derivative of the curve
    uint256 public totalDebtX;                    // the total debt in X that traders own the pool
    uint256 public totalDebtY;                    // the total debt in Y that traders own the pool
    uint256 public totalDebttokenX;               // the total debt token that represents total debt in X
    uint256 public totalDebttokenY;               // the total debt token that represents total debt in Y
    uint256 public lastFunding;                   // the funding that was recorded last time
    uint256 public lastFundingTime;               // the time that the last funding was recorded
    bool public lastPayingSide;                   // the paying side of last funding
    uint256 public upperFunding8H;                // = 5000000000 , the max funding in 8H
    address public factory;                       // the address of factory contract
    address public tokenX;                        // the address of token X
    address public tokenY;                        // the address of token Y
    uint256 public marginLeverage;                // the max leverage that perpetual traders can use when opening position
    uint256 public totalLiquidity;                // the sum of all LPs' liquidity
    uint256 public liquidationRate;               // maintenance margin rate
    uint256 public const18 = 1e18;
    address public _addr;                         // the address of logic contract
    uint256 public liquidationBonus;              // reward rate of liquidation
    uint256 public tickrange;                     
    uint256 public baserate;                      // = 156200
    uint256 public swapFee;                       // swap trading fee rate
    uint256 public perpFee;                       // perpetual trading fee rate
    bool public twoWhite;                         // if the Y token is in the white list (X token must be in the white list)
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    uint private unlocked = 1;
    uint8 limitation = 0;                         // 0: only swap trading allowed ;  1: swap trading +  X to Y perpetual trading allowed;  2: all trading allowed;

    struct debtbook{
        uint debttokenAmount;
        uint positionAmount;
    }

    uint[2] public marginReserve;   // total reserve of margins of all users
    mapping(address => mapping(bool => debtbook)) public debtIndex;  // userID + token(0:X;1:Y)  =>  debtbook
    mapping(address => uint[2]) public marginIndex;  // userID => margin reserves of two tokens


    /* ========== MODIFIERS ========== */
    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /* ========== EVENTS ========== */

    /* ========== VIEWS ========== */

    // update liquidity
    function _virtualLiquidityUpdate() internal view returns (uint _D){
        uint N = Math.calN(trueLiquidX , B , peqX , trueLiquidY , 2 * 1e18 - B , peqY , trueLiquidX0 , trueLiquidY0); 
        _D = D0 * N / const18;
    }

    // calculate the net value of [userID]'s margin
    function netMargin(address userID) internal view returns(uint net){
        net = marginIndex[userID][0] + Math.calTimes2(marginIndex[userID][1] ,  priceLocal , peqY , peqX , const18);
        
    }

    // calculate the net value of [userID]'s position
    function netPosition(address userID) internal view returns(uint net){
        net = debtIndex[userID][false].positionAmount + Math.calTimes2(debtIndex[userID][true].positionAmount , priceLocal , peqY , peqX , const18 );
    }

    // calculate the net value of [userID]'s debt
    function netDebt(address userID) internal view returns(uint net){
        net = Math.calTimes(debtIndex[userID][true].debttokenAmount ,  totalDebtY , totalDebttokenY) + Math.calTimes( Math.calTimes2(debtIndex[userID][false].debttokenAmount ,  totalDebtX , priceLocal , totalDebttokenX , const18) , peqY , peqX);
    }



    /* ========== MUTATIVE FUNCTIONS ========== */

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }


    // deltaX：amount of X trader paid; perp：perp trading (T) or swap trading (F); exactY : user want exact output (T) or not (F); output: amount of Y users get
    function _tradeXToY(uint deltaX, bool perp, uint exactY) internal lock returns(uint Yget) {

        uint Xin;
        while(deltaX - Xin > Math.calCross(Math.calTimes(D/2 , tickrange , const18), coordX, peqX)){
            //calculate the X value that triggers the cross-tick
            uint coordTestX = Math.calTimes(D/2 , tickrange , const18);

            //calculate the corresponding Y coordinate
            uint coordTestY = Math.calY(B, Math.calC(B), D, coordTestX);

            
            if( exactY > 0 && Yget + Math.calCross(coordY, coordTestY, peqY) > exactY) break;

            //update Yget and Xin (cumulated)
            Yget += Math.calCross(coordY, coordTestY, peqY);
            Xin += Math.calCross(coordTestX, coordX, peqX);

            // if swap trading, cumulate true liquidity
            if(perp == false) {
                trueLiquidX += Math.calCross(coordTestX, coordX, peqX);
                trueLiquidY -= Math.calCross(coordY, coordTestY, peqY);
            }

            // update peqX peqY
            peqY = Math.calTimes(peqY , D/2 , coordTestY);
            peqX = Math.calTimes(peqX , D/2 , coordTestX);

            //calculate priceLocal
            priceLocal = Math.calTimes2 (Math.calPrice(B, Math.calC(B), D, coordTestX, coordTestY) , coordTestY , D/2 , coordTestX , D/2 );
            
            //calculate B (and C)
            B = Math.calB(D, priceLocal);
            

            // update D
            D = _virtualLiquidityUpdate();

            //update coordinates
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

    // deltaX：amount of Y trader paid; perp：perp trading (T) or swap trading (F); exactX : user want exact output (T) or not (F); output: amount of X users get
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

    // update totaldebt by exercising the funding
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


    // open position
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

    // open two-way positions
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
    

    // close position
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


    // liquidation
    function liquidate(address userID, address _to) external lock {
        require(netMargin(userID) + netPosition(userID) <= netDebt(userID) || netMargin(userID) + netPosition(userID) - netDebt(userID) <= netPosition(userID) * liquidationRate);
        _safeTransfer(tokenX, _to ,  marginIndex[userID][0] * liquidationBonus);
        _safeTransfer(tokenY, _to ,  marginIndex[userID][1] * liquidationBonus);
        delete marginIndex[userID]; //

        perpClose(debtIndex[userID][false].positionAmount, debtIndex[userID][true].positionAmount, userID);
        // let insurance fund transfer corresponding tokens to the pool, according to the
        // UNFINISHED
        debtIndex[userID][false].debttokenAmount = 0;
        debtIndex[userID][true].debttokenAmount = 0;
    }


    // withdraw margin
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