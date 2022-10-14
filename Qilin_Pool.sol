pragma solidity ^0.8.4;
import './libraries/Math.sol';
import './libraries/Safemath.sol';
import './interface/IERC20.sol';
import './interface/IQilin_Factory.sol';
import './interface/IQilin_Callee.sol';
import './interface/IQilin_Pool.sol';
import './QilinERC20.sol';

contract Pool {
    uint256 public B;
    uint256 public C;
    uint256 public D;
    uint256 public D0;
    uint256 public Xeq;
    uint256 public Yeq;
    uint256 public X_Coord;
    uint256 public Y_Coord;
    uint256 public Peqy;
    uint256 public Peqx;
    uint256 public Ygetp;
    uint256 public Xgetp;
    uint256 public True_Liquid_Y0;
    uint256 public True_Liquid_X0;
    uint256 public True_Liquid_Y;
    uint256 public True_Liquid_X;
    uint256 public X_Coord_Last;
    uint256 public Y_Coord_Last;
    uint256 public Price_local;
    
    uint256 public Tick_range;                      //固定值，留接口修改

    uint256 public Total_debt_X;
    uint256 public Total_debt_Y;
    uint256 public Total_debttoken_X;
    uint256 public Total_debttoken_Y;
    uint256 public Leverage_Max;                    //固定值，留接口修改
    uint256 public funding_Last;                    //系统内记录上一次funding值
    uint256 public fundingtime_Last;                //系统内记录上一次funding时间
    uint256 public funding_x_8h_upper;              //= 5000000000固定值，留接口修改
    uint256 public interest_rate;
    uint256 public Base_rate;                       //= 156200，固定值，留接口修改
    uint256 public M;
    uint256 public N;
    uint256 public M_Last;
    uint256 public N_Last;

    address public factory;
    address public tokenX;
    address public tokenY;

    uint256 public Total_Liquidity;

    uint256 public Liquidation_rate;                //强平线
    uint256 public Liquidation_bonus;               //清算人罚金

    constructor() public {
        factory = msg.sender;
    }

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Qilin: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function initialize(address _tokenX, address _tokenY) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN'); // sufficient check
        tokenX = _tokenX;
        tokenY = _tokenY;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Qilin: TRANSFER_FAILED');
    }

    function getReserves() public view returns (uint _reserveX, uint _reserveY, uint32 _blockTimestampLast) {
        _reserveX = True_Liquid_X;
        _reserveY = True_Liquid_Y;
        _blockTimestampLast = blockTimestampLast;
    }

    // 获取资金费率
    function Getfundingrate () public view returns(uint256 funding_x ,uint256 funding_x_8h , bool paying_side){
        uint256 XE = True_Liquid_X * Peqx;
        uint256 YE = True_Liquid_Y * Peqy;
        uint256 DE = D / M;
        uint256 BE = (DE * DE * DE / 4 / XE / YE - 2 * YE) / (XE - YE);
        uint256 CE = 2-BE;
        uint256 PE = (4 * CE * XE * XE * YE * YE + DE * D * D * XE) / (4 * BE * XE * XE * YE * YE + DE * DE * DE * YE) * Peqy / Peqx;
        uint256 PS = (4 * C * X * X * Y * Y + D * D * D * X) / (4 * B * X * X * Y * Y + D * D * D * Y) * Peqy / Peqx;
        if(PS > PE){
            uint256 interest_rate = Ygetp / (True_Liquid_Y + Ygetp) / 57600 + Base_rate;
            funding_x = (PS-PE) / PE / 5760 + interest_rate;
            paying_side = 0;
        }else{
            uint256 interest_rate = Xgetp / (True_Liquid_X + Xgetp) / 57600 + Base_rate;
            funding_x = (PE-PX) / PE / 5760 + interest_rate;
            paying_side = 1;
        }
        funding_x_8h = funding_x * 1920;
        if(funding_x_8h > fundingx_8h_upper){
            funding_x_8h = funding_x_8h_upper;
            funding_x = funding_x_8h / 1920;
        }
    }

    // 虚拟流动性更新
    function Virtual_Liquidity_Update() internal {
        N = cbrt((True_Liquid_X * B * Peqx + Peqy * C * True_Liquid_Y) * True_Liquid_X * True_Liquid_Y / (True_Liquid_X0 * B * Peqx + Peqy * C * True_Liquid_Y0) / True_Liquid_X0 / True_Liquid_Y0);
        uint XA = X_Coord * N / Peqx / N_Last / M_Last;
        uint YA = Y_Coord * N / Peqx / N_Last / M_Last;
        M = min3 (Leverage_Max, (XA / Peqx + Xgetp) / (XA / Peqx), (YA / Peqy + Ygetp) / (YA / Peqy));
        D = D0 * M * N;
        Xeq = D/2;
        Yeq = Xeq;
        N_Last = N;
        M_Last = M;
    }

    // 添加流动性
    function Add_Liquidity(uint AddX , uint AddY) external lock returns(uint Liquidity){
        X_Coord = X_Coord * (True_Liquid_X + AddX) / True_Liquid_X;
        Y_Coord = Y_Coord * (True_Liquid_Y + AddY) / True_Liquid_Y;
        Liquidity = Total_Liquidity * AddX / True_Liquid_X;
        Total_Liquidity = Total_Liquidity + Liquidity;
        True_Liquid_X = True_Liquid_X + AddX;
        True_Liquid_Y = True_Liquid_Y + AddY;
        Virtual_Liquidity_Update();
    }

    // 撤出流动性//
    function Burn_Liquidity(uint Liquidity) external lock returns(uint BurX , uint BurY){
        BurX = Liquidity * True_Liquid_X / Total_Liquidity;
        BurY = Liquidity * True_Liquid_Y / Total_Liquidity;
        X_Coord = X_Coord * (True_Liquid_X - BurX) / True_Liquid_X;
        Y_Coord = Y_Coord * (True_Liquid_Y - BurY) / True_Liquid_Y;
        True_Liquid_X = True_Liquid_X - BurX;
        True_Liquid_Y = True_Liquid_Y - BurY;
        Total_Liquidity = Total_Liquidity - Liquidity;
        Virtual_Liquidity_Update();
    }

    //现货 交易，用X买Y
    function Trade_XtoY(uint delta) internal lock returns(uint Yget) {
        uint deltaX = delta;
        bool check = 1;
        while(check == 1){

            uint X_Coord_Test = X_Coord + deltaX * Peqx;
            uint Y_Coord_Test = cal_Y(B, C, D, X_Coord_Test);

            if(X_Coord_Test > Xeq * Tick_range){
                X_Coord_Test = Xeq * Tick_range;
                Y_Coord_Test = cal_Y(B, C, D, X_Coord_Test);
                uint P_test = cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Yget = (Y_Coord - Y_Coord_Test) / Peqy + Yget;
                deltaX = deltaX - (X_Coord_Test - X_Coord) / Peqx;

                True_Liquid_X = True_Liquid_X + (X_Coord_Test - X_Coord) / Peqx;
                True_Liquid_Y = True_Liquid_Y - (Y_Coord - Y_Coord_Test) / Peqy;

                uint Peqxt = Peqx;
                uint Peqyt = Peqy;
                Peqy = Peqyt * Yeq / Y_Coord_Test;
                Peqx = Peqxt * Xeq / X_Coord_Test;
                Price_local = P_test * Peqyt * Peqx / Peqxt / Peqy;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = cal_price(X_Coord, Y_Coord, D, Price_local);
                C = 2 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                X_Coord = X_Coord + deltaX * Peqx;
                Y_Coord <<- cal_Y(B, C, D, X_Coord);
                Yget = (Y_Coord_Last - Y_Coord) / Peqy + Yget;
                True_Liquid_X = True_Liquid_X + (X_Coord - X_Coord_Last) / Peqx;
                True_Liquid_Y = True_Liquid_Y - (Y_Coord_Last - Y_Coord) / Peqy;
                check = 0;
            }
        }
    }

    //现货 交易，用Y买X
    function Trade_YtoX(uint delta) internal lock returns(uint Xget) {
        uint deltaY = delta;
        bool check = 1;
        while(check == 1){

            uint Y_Coord_Test = Y_Coord + deltaY * Peqy;
            uint X_Coord_Test = cal_X(B, C, D, Y_Coord_Test);

            if(Y_Coord_Test > Xeq * Tick_range){
                Y_Coord_Test = Xeq * Tick_range;
                X_Coord_Test = cal_X(B, C, D, Y_Coord_Test);
                uint P_test = cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Xget = (X_Coord - X_Coord_Test) / Peqx + Xget;
                deltaY = deltaY - (Y_Coord_Test - Y_Coord) / Peqy;

                True_Liquid_X = True_Liquid_X - (X_Coord - X_Coord_Test) / Peqx;
                True_Liquid_Y = True_Liquid_Y + (Y_Coord_Test - Y_Coord) / Peqy;

                uint Peqxt = Peqx;
                uint Peqyt = Peqy;
                Peqy = Peqyt * Yeq / Y_Coord_Test;
                Peqx = Peqxt * Xeq / X_Coord_Test;
                Price_local = P_test * Peqyt * Peqx / Peqxt / Peqy;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = cal_price(X_Coord, Y_Coord, D, Price_local);
                C = 2 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                Y_Coord = Y_Coord + deltaY * Peqy;
                X_Coord = cal_X(B, C, D, Y_Coord);
                Xget = (X_Coord_Last - X_Coord) / Peqx + Xget;
                True_Liquid_Y = True_Liquid_Y + (Y_Coord - Y_Coord_Last) / Peqy;
                True_Liquid_X = True_Liquid_X - (X_Coord_Last - X_Coord) / Peqx;
                check = 0;
            }
        }
    }

    //Perp 交易，用X买Y，只被开平仓函数调用
    function Perp_XtoY(uint delta) internal lock returns(uint Yget){
        uint deltaX = delta;
        bool check = 1;
        while(check == 1){

            uint X_Coord_Test = X_Coord + deltaX * Peqx;
            uint Y_Coord_Test = cal_Y(B, C, D, X_Coord_Test);

            if(X_Coord_Test > Xeq * Tick_range){
                X_Coord_Test = Xeq * Tick_range;
                Y_Coord_Test = cal_Y(B, C, D, X_Coord_Test);
                uint P_test = cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Yget = (Y_Coord - Y_Coord_Test) / Peqy + Yget;
                Ygetp = (Y_Coord - Y_Coord_Test) / Peqy + Ygetp;
                deltaX = deltaX - (X_Coord_Test - X_Coord) / Peqx;

                uint Peqxt = Peqx;
                uint Peqyt = Peqy;
                Peqy = Peqyt * Yeq / Y_Coord_Test;
                Peqx = Peqxt * Xeq / X_Coord_Test;
                Price_local = P_test * Peqyt * Peqx / Peqxt / Peqy;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = cal_price(X_Coord, Y_Coord, D, Price_local);
                C = 2 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                X_Coord = X_Coord + deltaX * Peqx;
                Y_Coord <<- cal_Y(B, C, D, X_Coord);
                Yget = (Y_Coord_Last - Y_Coord) / Peqy + Yget;
                Ygetp = (Y_Coord_Last - Y_Coord) / Peqy + Ygetp;
                check = 0;
            }
        }
    }

    //Perp 交易，用Y买X，只被开平仓函数调用
    function Perp_YtoX(uint delta) internal lock returns(uint Xget){
        uint deltaY = delta;
        bool check = 1;
        while(check == 1){

            uint Y_Coord_Test = Y_Coord + deltaY * Peqy;
            uint X_Coord_Test = cal_X(B, C, D, Y_Coord_Test);

            if(Y_Coord_Test > Xeq * Tick_range){
                Y_Coord_Test = Xeq * Tick_range;
                X_Coord_Test = cal_X(B, C, D, Y_Coord_Test);
                uint P_test = cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Xget = (X_Coord - X_Coord_Test) / Peqx + Xget;
                Xgetp = (X_Coord - X_Coord_Test) / Peqx + Xgetp;
                deltaY = deltaY - (Y_Coord_Test - Y_Coord) / Peqy;

                uint Peqxt = Peqx;
                uint Peqyt = Peqy;
                Peqy = Peqyt * Yeq / Y_Coord_Test;
                Peqx = Peqxt * Xeq / X_Coord_Test;
                Price_local = P_test * Peqyt * Peqx / Peqxt / Peqy;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = cal_price(X_Coord, Y_Coord, D, Price_local);
                C = 2 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                Y_Coord = Y_Coord + deltaY * Peqy;
                X_Coord = cal_X(B, C, D, Y_Coord);
                Xget = (X_Coord_Last - X_Coord) / Peqx + Xget;
                Xgetp = (X_Coord_Last - X_Coord) / Peqx + Xgetp;
                check = 0;
            }
        }
    }

    //得到实时价格 (Y in X)
    function getPrice() public view returns(uint price){
        price = Price_local * Peqy / Peqx;
    }

    struct debtbook{
        address user_ID;
        bool token_ID; 
        int debttoken_amount;
        int position_amount;
    }


    address[] public Margin_tpyes; //记录白名单内token的address

    mapping(address => mapping(bool => debtbook)) public debt_index;  //将用户address + 债务token（左侧资产还是右侧资产）与存储其debt_token和仓位 对应

    mapping(address => uint[]) public margin_index;  //将用户address与存储其保证金的数组对应

    mapping(address => uint) public margin_type; //将保证金白名单token address与其在数组中的序列对应

    //增加保证金种类
    function add_margintypes(address token) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Margin_tpyes.push(token);
    }

    //求单一保证金种类价格 待完成
    function get_margin_price(address token) public view returns(uint price){

    }

    //求各保证金价格
    function Get_Margin_price() public view returns(uint[] margins){
        uint Lei = Margin_tpyes.length;
        for(uint i = 0; i < Lei ; i++){
            margins.push(get_margin_price(Margin_tpyes[i]));
        }
    }

    //求保证金净值
    function Net_Margin(address userID) public view returns(uint net){
        uint[] user_margin = margin_index[userID];
        uint[] margin_price = Get_Margin_price();
        uint Lei = user_margin.length;
        for(uint i = 0 ; i < Lei ; i++){
            net += user_margin[i]*margin_price[i];
        }
    }

    //求仓位净值
    function Net_Position(address userID) public view returns(uint net){
        net = debt_index[userID][0].position_amount * get_margin_price(tokenX) + debt_index[userID][1].position_amount * get_margin_price(tokenY);
    }

    //求债务净值
    function Net_debt(address userID) public view returns(uint net){
        net = debt_index[userID][1].debttoken_amount * Total_debt_Y / Total_debttoken_Y * get_margin_price(tokenY) + debt_index[userID][0].debttoken_amount * Total_debt_X / Total_debttoken_X * get_margin_price(tokenX);
    }

    //更新debt总账
    function refresh_totalbook() internal {
        (uint funding_x , , bool paying_side) = Getfundingrate();
        uint time_gap = block.number - fundingtime_Last;
        fundingtime_Last = block.number;
        uint price = getPrice();
        if(paying_side == 0){
            Total_debt_X = Total_debt_X * (1 + funding_Last) * time_gap;
            Total_debt_Y = Total_debt_Y - funding_Last * Total_debt_X * time_gap * price;
        }else{
            Total_debt_Y = Total_debt_Y * (1 + funding_Last) * time_gap;
            Total_debt_X = Total_debt_X - funding_Last * Total_debt_Y * time_gap / price;
        }
        funding_Last = funding_x;
        }


    //开仓 允许多空同时开仓
    function Perp_open(uint delta_X, uint delta_Y, address userID) external lock{
        require(delta_X >= 0 && delta_Y >= 0);
        refresh_totalbook(); 
        require(Net_Margin(userID) - Net_Position(userID) > max (delta_X * get_margin_price(tokenX) , delta_Y * get_margin_price(tokenY)),'Qilin: NOT ENOUGH MARGIN');
        if(delta_X > 0){
            Get = Perp_XtoY(delta_X);
            debt_index[userID][0].debttoken_amount += delta_X * Total_debttoken_X / Total_debt_X;
            debt_index[userID][1].position_amount += Get;
            Total_debttoken_X = delta_X * Total_debttoken_X / Total_debt_X + Total_debttoken_X;
            Total_debt_X = Total_debt_X + delta_X ;
        }
        if(delta_Y > 0){
            Get = Perp_YtoX(delta_Y);
            debt_index[userID][1].debttoken_amount += delta_Y * Total_debttoken_Y / Total_debt_Y;
            debt_index[userID][0].position_amount += Get;
            Total_debttoken_Y = delta_Y * Total_debttoken_Y / Total_debt_Y + Total_debttoken_Y;
            Total_debt_Y += delta_Y ;
        }
    }
    

    //平仓
    function Perp_close(uint delta_X, uint delta_Y, address userID) public lock {
        require(delta_X >= 0 && delta_Y >= 0);
        refresh_totalbook();
        require(delta_X <= debt_index[userID][0].position_amount && delta_Y <= debt_index[userID][1].position_amount,'Qilin: NOT ENOUGH POSITION');
        if(delta_X > 0){   
            uint Get = Perp_XtoY(delta_X);
            debt_index[userID][0].position_amount -= delta_X;
            if(Get > debt_index[userID][1].debttoken_amount * Total_debt_Y / Total_debttoken_Y){
                margin_index[userID][margin_type[tokenX]] += Trade_YtoX(Get - debt_index[userID][1].debttoken_amount * Total_debt_Y / Total_debttoken_Y);
                Total_debt_Y = Total_debt_Y - debt_index[userID][1].debttoken_amount * Total_debt_Y / Total_debttoken_Y ; 
                Total_debttoken_Y = Total_debttoken_Y - debt_index[userID][1].debttoken_amount;
                debt_index[userID][1].debttoken_amount = 0;
            }else{
                debt_index[userID][1].debttoken_amount -= Get * Total_debttoken_Y  / Total_debt_Y ;
                Total_debttoken_Y = Total_debttoken_Y - Get * Total_debttoken_Y  / Total_debt_Y ;
                Total_debt_Y -= Get;
            }
        } 
        if(delta_Y > 0){
            uint Get = Perp_YtoX(delta_Y);
            debt_index[userID][1].position_amount -= delta_Y;
            if(Get > debt_index[userID][0].debttoken_amount * Total_debt_X / Total_debttoken_X){
                margin_index[userID][margin_type[tokenX]] += Get - debt_index[userID][0].debttoken_amount * Total_debt_X / Total_debttoken_X;
                Total_debt_X = Total_debt_X - debt_index[userID][0].debttoken_amount * Total_debt_X / Total_debttoken_X ; 
                Total_debttoken_X = Total_debttoken_X - debt_index[userID][0].debttoken_amount;
                debt_index[userID][0].debttoken_amount = 0;
            }else{
                debt_index[userID][0].debttoken_amount -= Get * Total_debttoken_X  / Total_debt_X ;
                Total_debttoken_X = Total_debttoken_X - Get * Total_debttoken_X  / Total_debt_X ;
                Total_debt_X -= Get;
            }
        }
    }

    //清债 待完成
    function Clean_debt(address userID , bool token) internal lock{
        
    }

    //清算 
    function Liquidate(address userID, address _to) external lock {
        require(Net_debt(userID) > Net_Position(userID) && Net_debt(userID) - Net_Position(userID) > Liquidation_rate * Net_Margin(userID), 'Qilin: FORBIDDEN');
        uint Lei = Margin_tpyes.length;
        uint[] margin_togo = margin_index[userID] * Liquidation_bonus;
        for(uint i = 0 ; i < Lei ; i ++ ){
            _safeTransfer(Margin_tpyes[i], _to , margin_togo[i]);
        }
        margin_index[userID] = 0;
        debt_index[userID][0].debttoken_amount = 0;
        debt_index[userID][1].debttoken_amount = 0;
        Perp_close(debt_index[userID][0].position_amount, debt_index[userID][1].position_amount);
    }


    //加保证金
    function Add_Margin(uint new_margin, address userID) public {
        margin_index[userID] += new_margin;
    } 

    //留端口设置杠杆上限
    function Set_LeverageMax(uint L) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Leverage_Max = L;
    }

    //留端口设置funding rate上限
    function Set_fundingrate_upper(uint f) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        funding_x_8h_upper = f;
    }

    //留端口设置base rate
    function Set_baserate(uint baserate) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Base_rate = baserate;
    }

    //留端口设置tick 大小
    function Set_tickrange(uint tickrange) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Tick_range = tickrange;
    }

    //留端口设置 清算线
    function Set_Liquidation_rate(uint rate) external{
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Liquidation_rate = rate;
    }

    //留端口设置 清算罚金
    function Set_Liquidation_bonus(uint rate) external{
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Liquidation_bonus = rate;
    }

    //使真实资产存量等于记录值，可被外部套利者调用
     function skim(address to) external lock {
        address _tokenX = tokenX; // gas savings
        address _tokenY = tokenY; // gas savings
        _safeTransfer(_tokenX, to, IERC20(_tokenX).balanceOf(address(this)).sub(True_Liquid_X));
        _safeTransfer(_tokenY, to, IERC20(_tokenY).balanceOf(address(this)).sub(True_Liquid_Y));
    }

    //使记录值等于真实资产存量
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }


}