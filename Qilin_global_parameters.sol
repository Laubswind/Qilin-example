pragma solidity ^0.8.4;
contract global{

    uint256 public liquidationBonus;
    uint256 public tickrange;
    uint256 public baserate;
    uint256 public swapFee;
    uint256 public perpFee;
    address public factory;
    bool public twoWhite;
    
    //constructor() public {
    //    factory = ???;
    //}



    //留端口设置 清算罚金
    function setLiquidationBonus(uint _rate) external{
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        liquidationBonus = _rate;
    }

    //留端口设置tick 大小
    function setTickrange(uint _tickrange) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        tickrange = _tickrange;
    }

    //更改保证金种类
    function updateMargintypes(bool _twoWhite) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        twoWhite = _twoWhite;
    }

    //留端口设置base rate
    function setBaserate(uint _baserate) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        baserate = _baserate;
    }

    //留端口设置swap fee
    function setSwapFee(uint _swapFee) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        swapFee = _swapFee;
    }

    //留端口设置perp fee
    function setPerpFee(uint _perpFee) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        perpFee = _perpFee;
    }




    //留端口查询 清算罚金
    function getLiquidationBonus() external view returns (uint256){

        return liquidationBonus;
    }

    //留端口查询tick 大小
    function getTickrange() external view returns (uint256){

        return tickrange;
    }

    //查询保证金种类
    function getMargintypes() external view returns (bool){

        return twoWhite;
    }

    //留端口查询base rate
    function getBaserate() external view returns (uint256){

        return baserate;
    }

    //留端口查询swap fee
    function getSwapFee() external view returns (uint256){

        return swapFee;
    }

    //留端口查询perp fee
    function getPerpFee() external view returns (uint256){

        return perpFee;
    }







}