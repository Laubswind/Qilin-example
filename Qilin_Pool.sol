pragma solidity ^0.8.4;

import './libraries/Math.sol';
import './libraries/Safemath.sol';
import './interface/IERC20.sol';
import './interface/IQilin_Factory.sol';
import './interface/IQilin_Callee.sol';
import './interface/IQilin_Pool.sol';

// Inheritance
import './QilinERC20.sol';

contract Pool is QilinERC20{

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

    struct debtbook{
        address user_ID;
        bool token_ID; 
        uint debttokenAmount;
        uint positionAmount;
    }

    uint[2] public marginReserve;   //记录保证金的总存储量
    mapping(address => mapping(bool => debtbook)) public debtIndex;  //将用户address + 债务token（左侧资产还是右侧资产）与存储其debt_token和仓位 对应
    mapping(address => uint[2]) public marginIndex;  //将用户address与存储其保证金的数组对应

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

    // 虚拟流动性更新
    function _virtualLiquidityUpdate() internal view returns (uint _D){
        uint N = Math.calN(trueLiquidX , B , peqX , trueLiquidY , 2 * 1e18 - B , peqY , trueLiquidX0 , trueLiquidY0); 
        _D = D0 * N / const18;
    }


    /* ========== MUTATIVE FUNCTIONS ========== */

    function initialize(address _tokenX, address _tokenY, uint addX , uint addY , address to) external onlyFactoryCall {
        require(addX * addY > 0);
        tokenX = _tokenX;
        tokenY = _tokenY;
        B = const18;
        D = const18;
        D0 = D;
        totalLiquidity = const18;
        coordX = const18;
        coordY = const18;
        trueLiquidX = addX;
        trueLiquidY = addY;
        peqX = const18**2 / addX;
        peqY = const18**2 / addY;
        QilinERC20._mint(to, const18);
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }


    // 添加流动性
    function addLiquidity(uint addX , uint addY , address to) external lock returns(uint liquidity){
        
        coordX = Math.calTimes(coordX , (trueLiquidX + addX) , trueLiquidX );
        coordY = Math.calTimes(coordY , (trueLiquidY + addY) , trueLiquidY );
        liquidity = Math.calTimes (totalLiquidity , addX , trueLiquidX );
        totalLiquidity = totalLiquidity + liquidity;
        trueLiquidX = trueLiquidX + addX;
        trueLiquidY = trueLiquidY + addY;
        QilinERC20._mint(to, liquidity);
        D = _virtualLiquidityUpdate();
    }//

    // 撤出流动性
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

    //现货/合约 交易，用X买Y input为 delta：用户支付的X值，perp：是否为合约交易，output为 Yget：用户支付的X值所能换出的Y值
    function _delegateTradeXtoY(uint deltaX , bool perp , uint exactY) internal lock returns(uint) {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("_tradeXToY(uint , bool , uint)", deltaX , perp , exactY)
        );
        return abi.decode(data, (uint));
            
        
    }

    //现货/合约  交易，用Y买X input为Y
    function _delegateTradeYtoX(uint deltaY , bool perp , uint exactX) internal lock returns(uint) {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("_tradeYToX(uint , bool , uint)", deltaY , perp , exactX)
        );
        return abi.decode(data, (uint));
        
    }

    //总的swap function 现货交易时调用  input为 to：资产输出地址 ，Xout：用户所需Y to exact X 的精准X输出值， Yout：用户所需X to exact Y 的精准X输出值；如果Xout&Yout均为0，则代表用户无需exact，只需将输入资产全部输出即可
    function swap(address to, uint256 Xout, uint256 Yout) external lock{

        //检测，Xout和Yout不可同时大于0
        require( (Xout == 0 && Yout < trueLiquidY) || (Yout == 0 && Xout < trueLiquidY) );
        // require(to != tokenX && to != tokenY, 'Qilin: INVALID_TO');  不是很理解

        //检测用户转入池的资产量
        uint amountXIn = IERC20(tokenX).balanceOf(address(this)) - (trueLiquidX + marginReserve[0]);
        uint amountYIn = IERC20(tokenY).balanceOf(address(this)) - (trueLiquidY + marginReserve[1]);
        //检测用户转入池的资产量
        require(amountXIn > 0 || amountYIn > 0);
        amountXIn *= (1e18 - swapFee) / 1e18;
        amountYIn *= (1e18 - swapFee) / 1e18;
             
        //Xout大于0则代表Y to exact X，并将剩余Y转出
        if(Xout > 0){
            _safeTransfer(tokenY, to, amountYIn - _delegateTradeYtoX(amountYIn , false , Xout));
            _safeTransfer(tokenX, to, Xout);

        //Yout大于0则代表X to exact Y，并将剩余X转出
        }else if(Yout > 0){
            _safeTransfer(tokenX, to, amountXIn - _delegateTradeXtoY(amountXIn , false , Yout));
            _safeTransfer(tokenY, to, Yout);

        //都为0则将用户转入资产全部swap并转出
        }else{
            if(amountXIn > 0) _safeTransfer(tokenY, to, _delegateTradeXtoY(amountXIn , false , 0));
            if(amountYIn > 0) _safeTransfer(tokenX, to, _delegateTradeYtoX(amountYIn , false , 0));
        }
        trueLiquidX += amountXIn * swapFee / (1e18 - swapFee) ;
        trueLiquidY += amountYIn * swapFee / (1e18 - swapFee) ;
    }



    //开仓 不允许多空同时开仓
    function delegatePerpOpen( uint deltaX, uint deltaY, bool XtoY, address userID) external lock{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("perpOpen(uint , uint , bool , address)", deltaX , deltaY , XtoY , userID)
        );
    }

    //一键 多空双开
    //function Perp_biopen(uint deltaX, uint deltaY, address userID) external lock{
    //    require(deltaX * deltaY == 0 && deltaX + deltaY > 0);
    //    if(deltaX > 0){
    //        Perp_open(deltaX , 0 , true , userID);
    //        Perp_open(deltaX , 0 , false, userID);
    //    }else{
    //        Perp_open(0 , deltaY , true , userID);
    //        Perp_open(0 , deltaY , false, userID);
    //    }
    //}
    

    //平仓 
    function delegatePerpClose(uint deltaX, uint deltaY, address userID) external lock {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("perpClose(uint , uint ,  address)", deltaX , deltaY ,  userID)
        );
    }

    //清算 待修改
    function delegateLiquidate(address userID, address _to) external lock {
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("liquidate(uint ,  address)", userID , _to)
        );
    }

    
    //加保证金
    function delegateAddMargin(address tokenID, address userID) external {
        uint new_margin;
        new_margin = IERC20(tokenID).balanceOf(address(this));
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("addMargin(uint , uint ,  address)", new_margin , userID , userID)
        );
    }//

    //提取保证金
    function delegateWithdrawMargin (address userID , address tokenID, address to, uint amount) external lock{
        (bool success, bytes memory data) = _addr.delegatecall(
            abi.encodeWithSignature("withdrawMargin(address , address , address , amount)", userID , tokenID , to , amount)
        );
    }


    //留端口设置保证金杠杆上限
    function setLeverageMargin(uint L) external onlyFactoryCall {

        marginLeverage = L;
    }//

    //留端口设置funding rate上限
    function setFundingrateUpper(uint f) external onlyFactoryCall {

        upperFunding8H = f;
    }//

    //留端口设置 维持保证金率
    function setLiquidationRate(uint rate) external onlyFactoryCall {

        liquidationRate = rate;
    }//

    //留端口设置 逻辑合约地址
    function setLogicAddress(address addr) external onlyFactoryCall {

        _addr = addr;
    }//

    //留端口设置 清算罚金
    function setLiquidationBonus(uint _rate) external onlyFactoryCall{
        
        liquidationBonus = _rate;
    }

    //留端口设置tick 大小
    function setTickrange(uint _tickrange) external onlyFactoryCall{
        
        tickrange = _tickrange;
    }

    //更改保证金种类
    function updateMargintypes(bool _twoWhite) external onlyFactoryCall{
        
        twoWhite = _twoWhite;
    }

    //留端口设置base rate
    function setBaserate(uint _baserate) external onlyFactoryCall{
        
        baserate = _baserate;
    }

    //留端口设置swap fee
    function setSwapFee(uint _swapFee) external onlyFactoryCall{
        
        swapFee = _swapFee;
    }

    //留端口设置perp fee
    function setPerpFee(uint _perpFee) external onlyFactoryCall{
        
        perpFee = _perpFee;
    }


    //使真实资产存量等于记录值，可被外部套利者调用
    function skim(address to) external lock {
        _safeTransfer(tokenX, to, IERC20(tokenX).balanceOf(address(this)) - (trueLiquidX + marginReserve[0]));
        _safeTransfer(tokenY, to, IERC20(tokenY).balanceOf(address(this)) - (trueLiquidY + marginReserve[1]));
    }//

}

