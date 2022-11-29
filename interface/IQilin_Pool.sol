pragma solidity ^0.8.4;

interface IQilinPool {
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
    function initialize(address _tokenX, address _tokenY, uint addX , uint addY , address to) external;
    function addLiquidity(uint addX , uint addY , address to) external returns(uint liquidity);
    function burnLiquidity(uint liquidity , address to) external returns(uint burnX , uint burnY);
    function swap(address to, uint256 Xout, uint256 Yout) external;
    function delegatePerpOpen( uint deltaX, uint deltaY, bool XtoY, address userID) external;
    function delegatePerpBiopen(uint deltaX, uint deltaY, address userID) external;
    function delegatePerpClose(uint deltaX, uint deltaY, address userID) external;
    function delegateLiquidate(address userID, address _to) external;
    function delegateAddMargin(address tokenID, address userID) external;
    function delegateWithdrawMargin (address userID , address tokenID, address to, uint amount) external;
    function setLeverageMargin(uint L) external;
    function setFundingrateUpper(uint f) external;
    function setLiquidationRate(uint rate) external;
    function setLogicAddress(address addr) external;
    function setLiquidationBonus(uint _rate) external;
    function setTickrange(uint _tickrange) external;
    function updateMargintypes(bool _twoWhite) external;
    function setBaserate(uint _baserate) external;
    function setSwapFee(uint _swapFee) external;
    function setPerpFee(uint _perpFee) external;
    function setLIimitation(uint _limitation) external;
    function skim(address to) external;
}