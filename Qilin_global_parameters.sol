pragma solidity ^0.8.4;
contract global{

    uint256 public Liquidation_bonus;
    uint256 public Tick_range;
    uint256 public Base_rate;
    uint256 public swap_fee;
    uint256 public perp_fee;
    address public factory;
    bool public Two_white;
    
    
    
    constructor() public {
        factory = msg.sender;
    }



    //留端口设置 清算罚金
    function Set_Liquidation_bonus(uint rate) external{
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Liquidation_bonus = rate;
    }

    //留端口设置tick 大小
    function Set_tickrange(uint tickrange) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Tick_range = tickrange;
    }

    //更改保证金种类
    function update_margintypes(bool two_white) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Two_white = two_white;
    }

    //留端口设置base rate
    function Set_baserate(uint baserate) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Base_rate = baserate;
    }

    //留端口设置swap fee
    function Set_swapfee(uint swapfee) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        swap_fee = swapfee;
    }

    //留端口设置perp fee
    function Set_perpfee(uint perpfee) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        perp_fee = perpfee;
    }




    //留端口查询 清算罚金
    function Get_Liquidation_bonus() external view returns (uint rate){

        rate = Liquidation_bonus;
    }

    //留端口查询tick 大小
    function Get_tickrange() external view returns (uint tickrange){

        tickrange = Tick_range;
    }

    //查询保证金种类
    function Get_margintypes() external view returns (bool two_white){

        two_white = Two_white;
    }

    //留端口查询base rate
    function Get_baserate() external view returns (uint baserate){

        baserate = Base_rate;
    }

    //留端口查询swap fee
    function Get_swapfee() external view returns (uint swapfee){

        swapfee = swap_fee;
    }

    //留端口查询perp fee
    function Get_perpfee() external view returns (uint perpfee){

        perpfee = perp_fee;
    }







}