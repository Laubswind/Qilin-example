pragma solidity ^0.8.4;

import './libraries/Math.sol';
import './libraries/Safemath.sol';
import './interface/IERC20.sol';
import './interface/IQilin_Factory.sol';
import './interface/IQilin_Pool.sol';

// Inheritance
import './QilinERC20.sol';

contract Pool is QilinERC20{

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


    /* ========== CONSTRUCTOR ========== */
    constructor() public {
        factory = msg.sender;
    }


    /* ========== MODIFIERS ========== */
    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier onlyFactoryCall() {
        require(msg.sender == factory);
        _;
    }

    /* ========== EVENTS ========== */
    event Mint(address indexed sender, uint amountX, uint amountY);
    event Burn(address indexed sender, uint amountX, uint amountY, address indexed to);
    event Swap(
        address indexed sender,
        uint amountXIn,
        uint amountYIn,
        uint amountXOut,
        uint amountYOut,
        address indexed to
    );

    /* ========== VIEWS ========== */

    // update D value
    function _virtualLiquidityUpdate() internal view returns (uint _D){
        uint N = Math.calN(trueLiquidX , B , peqX , trueLiquidY , 2 * const18 - B , peqY , trueLiquidX0 , trueLiquidY0); 
        _D = D0 * N / const18;
    }


    /* ========== MUTATIVE FUNCTIONS ========== */

    function initialize(address _tokenX, address _tokenY) external onlyFactoryCall {
        tokenX = _tokenX;
        tokenY = _tokenY;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }


    // add liquidity
    function addLiquidity(address to) external lock returns(uint liquidity){
        uint addX = IERC20(tokenX).balanceOf(address(this)) - (trueLiquidX + marginReserve[0]);
        uint addY = IERC20(tokenY).balanceOf(address(this)) - (trueLiquidY + marginReserve[1]);
        // if the pool is empty before adding liquidity, initialize params
        if(totalLiquidity == 0){
            B = const18;
            D = const18;
            D0 = D;
            coordX = const18;
            coordY = const18;
            peqX = const18**2 / addX;
            peqY = const18**2 / addY;
            trueLiquidX0 = addX;
            trueLiquidY0 = addY;
            liquidity = const18;
        }else{
            coordX = Math.calTimes(coordX , (trueLiquidX + addX) , trueLiquidX );
            coordY = Math.calTimes(coordY , (trueLiquidY + addY) , trueLiquidY );
            liquidity = Math.min( Math.calTimes (totalLiquidity , addX , trueLiquidX ) , Math.calTimes (totalLiquidity , addY , trueLiquidY ) );
        }
        totalLiquidity = totalLiquidity + liquidity;
        trueLiquidX = trueLiquidX + addX;
        trueLiquidY = trueLiquidY + addY;
        QilinERC20._mint(to, liquidity);
        D = _virtualLiquidityUpdate();
    }

    // withdraw liquidity
    function burnLiquidity(uint liquidity , address to) external lock returns(uint burnX , uint burnY){
        burnX = Math.calTimes(liquidity , trueLiquidX , totalLiquidity );
        burnY = Math.calTimes(liquidity , trueLiquidY , totalLiquidity );
        coordX = Math.calTimes(coordX , (trueLiquidX - burnX) , trueLiquidX );
        coordY = Math.calTimes(coordY , (trueLiquidY - burnY) , trueLiquidY );
        trueLiquidX = trueLiquidX - burnX;
        trueLiquidY = trueLiquidY - burnY;
        totalLiquidity = totalLiquidity - liquidity;
        QilinERC20._burn(address(this), liquidity);
        _safeTransfer(tokenX, to, burnX);
        _safeTransfer(tokenY, to, burnY);
        D = _virtualLiquidityUpdate();
    }//

    // deltaX：amount of X trader paid; perp：perp trading (T) or swap trading (F); exactY : user want exact output (T) or not (F); output: amount of Y users get
    function _delegateTradeXtoY(uint deltaX , bool perp , uint exactY) internal lock returns(uint) {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("_tradeXToY(uint , bool , uint)", deltaX , perp , exactY)
        );
        return abi.decode(data, (uint));
            
        
    }

    // deltaX：amount of Y trader paid; perp：perp trading (T) or swap trading (F); exactX : user want exact output (T) or not (F); output: amount of X users get
    function _delegateTradeYtoX(uint deltaY , bool perp , uint exactX) internal lock returns(uint) {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("_tradeYToX(uint , bool , uint)", deltaY , perp , exactX)
        );
        return abi.decode(data, (uint));
        
    }

    // swap function   to：address the token will be sent to ，Xout：exact X output， Yout：exact Y output；
    function swap(address to, uint256 Xout, uint256 Yout) external lock{

        //check, at least one of Xout and Yout is 0
        require( (Xout == 0 && Yout < trueLiquidY) || (Yout == 0 && Xout < trueLiquidY) );
        // require(to != tokenX && to != tokenY, 'Qilin: INVALID_TO');  

        //check amount in
        uint amountXIn = IERC20(tokenX).balanceOf(address(this)) - (trueLiquidX + marginReserve[0]);
        uint amountYIn = IERC20(tokenY).balanceOf(address(this)) - (trueLiquidY + marginReserve[1]);

        //check amount in values
        require(amountXIn > 0 || amountYIn > 0);

        // charge swap fee
        amountXIn *= (1e18 - swapFee) / 1e18;
        amountYIn *= (1e18 - swapFee) / 1e18;
             
        // "Xout > 0" means "Y to exact X", transfer back the rest Y if any
        if(Xout > 0){
            _safeTransfer(tokenY, to, amountYIn - _delegateTradeYtoX(amountYIn , false , Xout));
            _safeTransfer(tokenX, to, Xout);

        // "Yout > 0" means "X to exact Y", transfer back the rest X if any
        }else if(Yout > 0){
            _safeTransfer(tokenX, to, amountXIn - _delegateTradeXtoY(amountXIn , false , Yout));
            _safeTransfer(tokenY, to, Yout);

        // if Xout and Yout are both 0, means no exact trading, pool will swap whatever received to the other token
        }else{
            if(amountXIn > 0) _safeTransfer(tokenY, to, _delegateTradeXtoY(amountXIn , false , 0));
            if(amountYIn > 0) _safeTransfer(tokenX, to, _delegateTradeYtoX(amountYIn , false , 0));
        }

        // update true liquidity
        trueLiquidX += amountXIn * swapFee / (1e18 - swapFee) ;
        trueLiquidY += amountYIn * swapFee / (1e18 - swapFee) ;
    }



    //  open position
    function delegatePerpOpen( uint deltaX, uint deltaY, bool XtoY, address userID) external lock{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("perpOpen(uint , uint , bool , address)", deltaX , deltaY , XtoY , userID)
        );
    }

    // open two-way positions
    function delegatePerpBiopen(uint deltaX, uint deltaY, address userID) external lock{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("perpBipen(uint , uint , address)", deltaX , deltaY ,  userID)
        );
    }
    

    // close position
    function delegatePerpClose(uint deltaX, uint deltaY, address userID) external lock {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("perpClose(uint , uint ,  address)", deltaX , deltaY ,  userID)
        );
    }

    // liquidation 
    function delegateLiquidate(address userID, address _to) external lock {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("liquidate(uint ,  address)", userID , _to)
        );
    }

    
    // add margin
    function delegateAddMargin(address tokenID, address userID) external {
        uint newMargin;
        newMargin = IERC20(tokenID).balanceOf(address(this));
        if(tokenID == tokenY && twoWhite == true){
            newMargin = newMargin - trueLiquidY - marginReserve[1];
            marginIndex[userID][1] += newMargin;
            marginReserve[1] += newMargin;
        }else{
            newMargin = newMargin - trueLiquidX - marginReserve[0];
            marginIndex[userID][0] += newMargin;
            marginReserve[0] += newMargin;
        }
    }//

    // withdraw margin
    function delegateWithdrawMargin (address userID , address tokenID, address to, uint amount) external lock{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("withdrawMargin(address , address , address , amount)", userID , tokenID , to , amount)
        );
    }


    // set marginLeverage
    function setLeverageMargin(uint L) external onlyFactoryCall {

        marginLeverage = L;
    }//

    // set upperFunding8H
    function setFundingrateUpper(uint f) external onlyFactoryCall {

        upperFunding8H = f;
    }//

    // set liquidationRate
    function setLiquidationRate(uint rate) external onlyFactoryCall {

        liquidationRate = rate;
    }//

    // set _addr
    function setLogicAddress(address addr) external onlyFactoryCall {

        _addr = addr;
    }//

    // set liquidationBonus
    function setLiquidationBonus(uint _rate) external onlyFactoryCall{
        
        liquidationBonus = _rate;
    }

    // set tickrange
    function setTickrange(uint _tickrange) external onlyFactoryCall{
        
        tickrange = _tickrange;
    }

    // set twoWhite
    function updateMargintypes(bool _twoWhite) external onlyFactoryCall{
        
        twoWhite = _twoWhite;
    }

    // set base rate
    function setBaserate(uint _baserate) external onlyFactoryCall{
        
        baserate = _baserate;
    }

    // setswap fee
    function setSwapFee(uint _swapFee) external onlyFactoryCall{
        
        swapFee = _swapFee;
    }

    // set perp fee
    function setPerpFee(uint _perpFee) external onlyFactoryCall{
        
        perpFee = _perpFee;
    }
    
    // set limitation
    function setLIimitation(uint8 _limitation) external onlyFactoryCall{
        
        limitation = _limitation;
    }

    //
    function skim(address to) external lock {
        _safeTransfer(tokenX, to, IERC20(tokenX).balanceOf(address(this)) - (trueLiquidX + marginReserve[0]));
        _safeTransfer(tokenY, to, IERC20(tokenY).balanceOf(address(this)) - (trueLiquidY + marginReserve[1]));
    }//

}

