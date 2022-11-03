pragma solidity ^0.8.4;
import './libraries/Math.sol';
import './libraries/Safemath.sol';
import './interface/IERC20.sol';
import './interface/IQilin_Factory.sol';
import './interface/IQilin_Callee.sol';
import './interface/IQilin_Pool.sol';
import './QilinERC20.sol';

contract Pool is QilinERC20{
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
    bool public paying_side_Last;                   //系统内记录上一次funding方向
    uint256 public funding_x_8h_upper;              //= 5000000000固定值，留接口修改
    uint256 public Base_rate;                       //= 156200，固定值，留接口修改
    uint256 public M;
    uint256 public N;
    uint256 public M_Last;
    uint256 public N_Last;
    
    address public factory;
    address public tokenX;
    address public tokenY;
    uint256 public Leverage_Margin;                 //开仓杠杆 18位

    uint256 public Total_Liquidity;                 //LPtoken总值

    uint256 public Liquidation_rate;                //维持保证金率
    uint256 public Liquidation_bonus;               //清算人罚金

    uint256 public const18 = 1e18;
 
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    constructor() public {
        factory = msg.sender;
    }

    using Safemath  for uint;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function initialize(address _tokenX, address _tokenY) external {
        require(msg.sender == factory, 'FORBIDDEN'); // sufficient check
        tokenX = _tokenX;
        tokenY = _tokenY;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    //function getReserves() public view returns (uint _reserveX, uint _reserveY, uint256 _blockTimestampLast) {
    //    _reserveX = True_Liquid_X;
    //    _reserveY = True_Liquid_Y;
    //   _blockTimestampLast = block.timestamp;
    //}

    // 获取资金费率
    function Getfundingrate () internal view returns(uint256 funding_x , bool paying_side){
        uint256 XE = True_Liquid_X * Peqx / const18;
        uint256 YE = True_Liquid_Y * Peqy / const18;
        uint256 DE = D * const18 / M;
        uint256 BE = Math.cal_B_f(XE, YE, DE);
        uint256 CE = 2* const18 - BE;
        uint256 PE = Math.cal_price(BE, CE, DE, XE, YE) * Peqy / Peqx;
        uint256 PS = Math.cal_price(B, C, D, X_Coord, Y_Coord) * Peqy / Peqx;
        if(PS > PE){
            uint256 interest_rate = Math.cal_interest(Ygetp , True_Liquid_Y , Base_rate);
            funding_x = (PS-PE) * const18 / PE / 5760 + interest_rate;
            paying_side = false;
        }else{
            uint256 interest_rate = Math.cal_interest(Xgetp , True_Liquid_X , Base_rate);
            funding_x = (PE-PS) * const18 / PE / 5760 + interest_rate;
            paying_side = true;
        }
        if(funding_x * 1920 > funding_x_8h_upper){
            funding_x = funding_x_8h_upper / 1920;
        }
    }

    // 虚拟流动性更新
    function Virtual_Liquidity_Update() internal {
        N = Math.cbrt((True_Liquid_X * B * Peqx + Peqy * C * True_Liquid_Y) * True_Liquid_X * True_Liquid_Y * const18 * const18 * const18 / (True_Liquid_X0 * B * Peqx + Peqy * C * True_Liquid_Y0) / True_Liquid_X0 / True_Liquid_Y0);
        uint XA = X_Coord * N * const18 * const18 / Peqx / N_Last / M_Last;
        uint YA = Y_Coord * N * const18 * const18 / Peqx / N_Last / M_Last;
        M = Math.min3 (Leverage_Max, (XA + Xgetp) * const18 / (XA), (YA + Ygetp) * const18 / (YA));
        D = D0 * M * N / const18 / const18;
        Xeq = D/2;
        Yeq = Xeq;
        N_Last = N;
        M_Last = M;
    }

    // 添加流动性
    function Add_Liquidity(uint AddX , uint AddY , address to) external lock returns(uint Liquidity){
        X_Coord = X_Coord * (True_Liquid_X + AddX) / True_Liquid_X;
        Y_Coord = Y_Coord * (True_Liquid_Y + AddY) / True_Liquid_Y;
        Liquidity = Total_Liquidity * AddX / True_Liquid_X;
        Total_Liquidity = Total_Liquidity + Liquidity;
        True_Liquid_X = True_Liquid_X + AddX;
        True_Liquid_Y = True_Liquid_Y + AddY;
        QilinERC20._mint(to, Liquidity);
        Virtual_Liquidity_Update();
    }

    // 撤出流动性
    function Burn_Liquidity(uint Liquidity , address to) external lock returns(uint BurX , uint BurY){
        BurX = Liquidity * True_Liquid_X / Total_Liquidity;
        BurY = Liquidity * True_Liquid_Y / Total_Liquidity;
        X_Coord = X_Coord * (True_Liquid_X - BurX) / True_Liquid_X;
        Y_Coord = Y_Coord * (True_Liquid_Y - BurY) / True_Liquid_Y;
        True_Liquid_X = True_Liquid_X - BurX;
        True_Liquid_Y = True_Liquid_Y - BurY;
        Total_Liquidity = Total_Liquidity - Liquidity;
        QilinERC20._burn(address(this), Liquidity);
        _safeTransfer(tokenX, to, BurX);
        _safeTransfer(tokenY, to, BurY);
        Virtual_Liquidity_Update();
    }

    //现货/合约 交易，用X买Y input为X
    function Trade_XtoY(uint delta, bool perp) internal lock returns(uint Yget) {
        uint deltaX = delta;
        bool check = true;
        while(check == true){

            uint X_Coord_Test = Xeq * Tick_range / const18; 
            uint Y_Coord_Test = Math.cal_Y(B, C, D, X_Coord_Test);

            if(deltaX > Math.cal_cross(X_Coord_Test, X_Coord, Peqx)){
                uint P_test = Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Yget += Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                deltaX -= Math.cal_cross(X_Coord_Test, X_Coord, Peqx);
                if(perp == true) {
                    Ygetp += Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                }else{
                    True_Liquid_X += Math.cal_cross(X_Coord_Test, X_Coord, Peqx);
                    True_Liquid_Y -= Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                }

                Peqy = Peqy * Yeq / Y_Coord_Test;
                Peqx = Peqx * Xeq / X_Coord_Test;
                Price_local = P_test * Y_Coord_Test * Xeq / X_Coord_Test / Yeq;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B; 
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                X_Coord +=  deltaX * Peqx / const18;
                Y_Coord = Math.cal_Y(B, C, D, X_Coord);
                Yget += Math.cal_cross(Y_Coord_Last, Y_Coord, Peqy);
                if(perp == true){
                    Ygetp += Math.cal_cross(Y_Coord_Last, Y_Coord, Peqy);
                }else{
                    True_Liquid_X += deltaX;
                    True_Liquid_Y -= Math.cal_cross(Y_Coord_Last, Y_Coord, Peqy);
                }
                check = false;
            }
        }
    }

    //现货/合约 交易，用X买Y，input为Y
    function TradeXToExactY(uint delta, uint Xmax, bool perp) internal lock returns(uint Xin) {
        uint deltaY = delta;
        bool check = true;
        while(check == true){

            uint X_Coord_Test = Xeq * Tick_range / const18;
            uint Y_Coord_Test = Math.cal_Y(B, C, D, X_Coord_Test);

            if(deltaY > Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy)){
                uint P_test = Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Xin += Math.cal_cross(X_Coord_Test, X_Coord, Peqx);
                deltaY -= Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                if(perp == true){
                    Ygetp += Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                }else{
                    True_Liquid_X +=  Math.cal_cross(X_Coord_Test, X_Coord, Peqx);
                    True_Liquid_Y -=  Math.cal_cross(Y_Coord, Y_Coord_Test, Peqy);
                }

                Peqy = Peqy * Yeq / Y_Coord_Test;
                Peqx = Peqx * Xeq / X_Coord_Test;
                Price_local = P_test * Y_Coord_Test * Xeq / X_Coord_Test / Yeq;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                Y_Coord -= deltaY * Peqy / const18;
                X_Coord = Math.cal_X(B, C, D, Y_Coord);
                Xin += Math.cal_cross(X_Coord, X_Coord_Last, Peqx);
                if(perp == true){
                    Ygetp += deltaY;
                }else{
                    True_Liquid_X += Math.cal_cross(X_Coord, X_Coord_Last, Peqx);
                    True_Liquid_Y -= deltaY;
                }
                check = false;
            }
        }
        if(perp == false) require(Xmax > Xin);
    }

    //现货/合约  交易，用Y买X input为Y
    function Trade_YtoX(uint delta , bool perp) internal lock returns(uint Xget) {
        uint deltaY = delta;
        bool check = true;
        while(check == true){

            uint Y_Coord_Test = Xeq * Tick_range / const18;
            uint X_Coord_Test = Math.cal_X(B, C, D, Y_Coord_Test);

            if(deltaY > Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy)){

                uint P_test = Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Xget += Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                deltaY -= Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                if(perp == true){
                    Xgetp += Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                }else{
                    True_Liquid_X -= Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                    True_Liquid_Y += Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                }

                Peqy = Peqy * Yeq / Y_Coord_Test;
                Peqx = Peqx * Xeq / X_Coord_Test;
                Price_local = P_test * Y_Coord_Test * Xeq / X_Coord_Test / Yeq;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                Y_Coord += deltaY * Peqy / const18;
                X_Coord = Math.cal_X(B, C, D, Y_Coord);
                Xget += Math.cal_cross(X_Coord_Last, X_Coord, Peqx);
                if(perp == true){
                    Xgetp += Math.cal_cross(X_Coord_Last, X_Coord, Peqx);
                }else{
                    True_Liquid_Y += deltaY;
                    True_Liquid_X -= Math.cal_cross(X_Coord_Last, X_Coord, Peqx);
                }
                check = false;
            }
        }
    }

    //现货/合约  交易，用Y买X input为X
    function TradeYToExactX(uint delta, uint Ymax, bool perp) internal lock returns(uint Yin) {
        uint deltaX = delta;
        bool check = true;
        while(check == true){

            uint Y_Coord_Test = Yeq * Tick_range / const18;
            uint X_Coord_Test = Math.cal_X(B, C, D, Y_Coord_Test);

            if(deltaX > Math.cal_cross(X_Coord, X_Coord_Test, Peqx)){
                uint P_test = Math.cal_price(B, C, D, X_Coord_Test, Y_Coord_Test);

                Yin += Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                deltaX -= Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                if(perp == true){
                    Xgetp += Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                }else{
                    True_Liquid_Y +=  Math.cal_cross(Y_Coord_Test, Y_Coord, Peqy);
                    True_Liquid_X -=  Math.cal_cross(X_Coord, X_Coord_Test, Peqx);
                }

                Peqy = Peqy * Yeq / Y_Coord_Test;
                Peqx = Peqx * Xeq / X_Coord_Test;
                Price_local = P_test * Y_Coord_Test * Xeq / X_Coord_Test / Yeq;
                
                X_Coord = Xeq;
                Y_Coord = Yeq;
                B = Math.cal_B(X_Coord, Y_Coord, D, Price_local);
                C = 2 * const18 - B;
                Virtual_Liquidity_Update();
                X_Coord = Xeq;
                Y_Coord = Yeq;

            }else{
                X_Coord_Last = X_Coord;
                Y_Coord_Last = Y_Coord;
                X_Coord -= deltaX * Peqx / const18;
                Y_Coord = Math.cal_Y(B, C, D, X_Coord);
                Yin += Math.cal_cross(Y_Coord, Y_Coord_Last, Peqy);
                if(perp == true){
                    Xgetp += deltaX;
                }else{
                    True_Liquid_Y += Math.cal_cross(Y_Coord, Y_Coord_Last, Peqy);
                    True_Liquid_X -= deltaX;
                }
                check = false;
            }
        }
        if(perp == false) require(Ymax > Yin);
    }

    // 总的swap function 不支持闪电贷
    function swap(address to, uint256 Xout, uint256 Yout) external lock{
        require(Xout == 0 || Yout == 0, 'QIlin: INVALID_OUT');
        // require(to != tokenX && to != tokenY, 'Qilin: INVALID_TO');  不是很理解
        uint balanceX = IERC20(tokenX).balanceOf(address(this));
        uint balanceY = IERC20(tokenY).balanceOf(address(this));
        uint amountXIn = balanceX - True_Liquid_X;
        uint amountYIn = balanceY - True_Liquid_Y;
        require(amountXIn > 0 || amountYIn > 0, 'Qilin: INSUFFICIENT_INPUT_AMOUNT');
        if(Xout > 0){
            _safeTransfer(tokenY, to, amountYIn - TradeYToExactX(Xout, amountYIn, false));
            _safeTransfer(tokenX, to, Xout);
        }else if(Yout > 0){
            _safeTransfer(tokenX, to, amountXIn - TradeXToExactY(Yout, amountXIn, false));
            _safeTransfer(tokenY, to, Yout);
        }else{
            if(amountXIn > 0) _safeTransfer(tokenY, to, Trade_XtoY(amountXIn, false));
            if(amountYIn > 0) _safeTransfer(tokenX, to, Trade_YtoX(amountYIn, false));
        }
    }

    
    //得到实时价格 (Y in X)
    //function getPrice() public view returns(uint price){
    //    price = Price_local * Peqy / Peqx;
    //}

    struct debtbook{
        address user_ID;
        bool token_ID; 
        uint debttoken_amount;
        uint position_amount;
    }


    address[] public Margin_tpyes; //记录白名单内token的address

    mapping(address => mapping(bool => debtbook)) public debt_index;  //将用户address + 债务token（左侧资产还是右侧资产）与存储其debt_token和仓位 对应

    mapping(address => uint[]) public margin_index;  //将用户address与存储其保证金的数组对应

    mapping(address => uint) public margin_type; //将保证金白名单token address与其在数组中的序列对应


    //求单一保证金种类价格 待完成
    function get_margin_price(address token) internal view returns(uint price){

    }

    //求各保证金价格
    function GetMarginPrice() internal view returns(uint[] memory margins){
        uint Lei = Margin_tpyes.length;
        for(uint i = 0; i < Lei ; i++){
            margins[i] = get_margin_price(Margin_tpyes[i]); 
        }
    }

    //求保证金净值
    function Net_Margin(address userID) internal view returns(uint net){
        uint[] memory user_margin = margin_index[userID];
        uint[] memory margin_price = GetMarginPrice();
        uint Lei = user_margin.length;
        for(uint i = 0 ; i < Lei ; i++){
            net += user_margin[i] * margin_price[i] / const18;
        }
    }

    //求仓位净值 注：36位
    function Net_Position(address userID) internal view returns(uint net){
        net = debt_index[userID][false].position_amount * get_margin_price(tokenX) + debt_index[userID][true].position_amount * get_margin_price(tokenY);
    }

    //求债务净值
    function Net_debt(address userID) internal view returns(uint net){
        net = debt_index[userID][true].debttoken_amount * Total_debt_Y / Total_debttoken_Y * get_margin_price(tokenY) /1e18 + debt_index[userID][false].debttoken_amount * Total_debt_X / Total_debttoken_X * get_margin_price(tokenX) / 1e18;
    }

    //更新debt总账
    function refresh_totalbook() internal {
        (uint funding_x , bool paying_side) = Getfundingrate();
        uint time_gap = block.number - fundingtime_Last;
        fundingtime_Last = block.number;
        uint price; 
        price = Price_local * Peqy / Peqx;
        if(paying_side_Last == false){
            Total_debt_X = Total_debt_X * (const18 + funding_Last) * time_gap / const18;
            Total_debt_Y = Total_debt_Y - funding_Last * Total_debt_X * time_gap * price / const18 / const18;
        }else{
            Total_debt_Y = Total_debt_Y * (const18 + funding_Last) * time_gap / const18;
            Total_debt_X = Total_debt_X - funding_Last * Total_debt_Y * time_gap / price;
        }
        funding_Last = funding_x; 
        paying_side_Last = paying_side;
        }


    //开仓 不允许多空同时开仓
    function Perp_open(uint delta_X, uint delta_Y, bool XtoY, address userID) public lock{
        require(delta_X * delta_Y == 0 && delta_X + delta_Y > 0);
        refresh_totalbook(); 
        require((Net_Margin(userID) +  Net_Position(userID) - Net_debt(userID)) / Leverage_Margin > Math.max (delta_X * get_margin_price(tokenX) + Net_Position(userID), delta_Y * get_margin_price(tokenY) + Net_Position(userID)),'Qilin: NOT ENOUGH MARGIN');
        uint256 Out;
        uint256 In;
        if(XtoY == true){
            if(delta_X > 0){
                Out = Trade_XtoY(delta_X , true);
                In = delta_X;
            }else{
                Out = delta_Y;
                In = TradeXToExactY(delta_Y , 0 , true);
            }
            debt_index[userID][false].debttoken_amount += In * Total_debttoken_X / Total_debt_X;
            debt_index[userID][true].position_amount += Out;
            Total_debttoken_X = In * Total_debttoken_X / Total_debt_X + Total_debttoken_X;
            Total_debt_X += In ;
        }else{
            if(delta_X > 0){
                Out = delta_X;
                In = TradeYToExactX(delta_X , 0 , true);
            }else{
                Out = Trade_YtoX(delta_Y , true);
                In = delta_Y;
            }
            debt_index[userID][true].debttoken_amount += In * Total_debttoken_Y / Total_debt_Y;
            debt_index[userID][false].position_amount += Out;
            Total_debttoken_Y = In * Total_debttoken_Y / Total_debt_Y + Total_debttoken_Y;
            Total_debt_Y += In ;
        }
    }

    //一键 多空双开
    function Perp_biopen(uint delta_X, uint delta_Y, address userID) external lock{
        require(delta_X * delta_Y == 0 && delta_X + delta_Y > 0);
        if(delta_X > 0){
            Perp_open(delta_X , 0 , true , userID);
            Perp_open(delta_X , 0 , false, userID);
        }else{
            Perp_open(0 , delta_Y , true , userID);
            Perp_open(0 , delta_Y , false, userID);
        }
    }
    

    //平仓 待修改 默认只有X资产是白名单内
    function Perp_close(uint delta_X, uint delta_Y, address userID) public lock {
        require(delta_X * delta_Y == 0 && delta_X + delta_Y > 0);
        refresh_totalbook();
        require(delta_X <= debt_index[userID][false].position_amount && delta_Y <= debt_index[userID][true].position_amount,'NOT ENOUGH POSITION');
        if(delta_X > 0){   
            uint Get = Trade_XtoY(delta_X , true);
            uint Y_close = delta_X * debt_index[userID][true].debttoken_amount * Total_debt_Y / Total_debttoken_Y / debt_index[userID][false].position_amount ;
            debt_index[userID][false].position_amount -= delta_X;
            Total_debt_Y -= Y_close ; 
            Total_debttoken_Y -= debt_index[userID][true].debttoken_amount * delta_X / debt_index[userID][false].position_amount ;
            debt_index[userID][true].debttoken_amount -= debt_index[userID][true].debttoken_amount * delta_X / debt_index[userID][false].position_amount;

            if(Get >= Y_close){
                margin_index[userID][margin_type[tokenX]] += Trade_YtoX(Get - Y_close , false);
            }else{
                //此处留有保证金还债的路由
            }
        }else{
            uint Get = Trade_YtoX(delta_Y , true);
            uint X_close = delta_Y * debt_index[userID][false].debttoken_amount * Total_debt_X / Total_debttoken_X / debt_index[userID][true].position_amount ;
            debt_index[userID][true].position_amount -= delta_Y;
            Total_debt_X -= X_close ; 
            Total_debttoken_X -= debt_index[userID][false].debttoken_amount * delta_Y / debt_index[userID][true].position_amount ;
            debt_index[userID][false].debttoken_amount -= debt_index[userID][false].debttoken_amount * delta_Y / debt_index[userID][true].position_amount;
            
            if(Get > X_close){
                margin_index[userID][margin_type[tokenX]] += Get - X_close;
            }else{
                //此处留有保证金还债的路由
            }
        }
    }

    //清债 待完成
    function Clean_debt(address userID , bool token) internal lock{
        
    }

    //清算 待修改
    function Liquidate(address userID, address _to) external lock {
        require(Net_debt(userID) > Net_Position(userID) && Net_debt(userID) - Net_Position(userID) > Liquidation_rate * Net_Margin(userID), 'Qilin: FORBIDDEN');
        uint Lei = Margin_tpyes.length;
        for(uint i = 0 ; i < Lei ; i ++ ){
            _safeTransfer(Margin_tpyes[i], _to ,  margin_index[userID][i] * Liquidation_bonus);
        }
        delete margin_index[userID]; //
        debt_index[userID][false].debttoken_amount = 0;
        debt_index[userID][true].debttoken_amount = 0;
        Perp_close(debt_index[userID][false].position_amount, debt_index[userID][true].position_amount, userID);
    }


    //加保证金
    function Add_Margin(uint new_margin, address tokenID, address userID) public {
        margin_index[userID][margin_type[tokenID]] += new_margin;
    } 

    //留端口设置虚拟流动性杠杆上限
    function Set_LeverageMax(uint L) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Leverage_Max = L;
    }

    //留端口设置保证金杠杆上限
    function Set_LeverageMargin(uint L) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Leverage_Margin = L;
    }

    //留端口设置funding rate上限
    function Set_fundingrate_upper(uint f) external {
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        funding_x_8h_upper = f;
    }



    //留端口设置 清算线
    function Set_Liquidation_rate(uint rate) external{
        require(msg.sender == factory, 'Qilin: FORBIDDEN');
        Liquidation_rate = rate;
    }


    //使真实资产存量等于记录值，可被外部套利者调用
     function skim(address to) external lock {
        _safeTransfer(tokenX, to, IERC20(tokenX).balanceOf(address(this)).sub(True_Liquid_X));
        _safeTransfer(tokenY, to, IERC20(tokenY).balanceOf(address(this)).sub(True_Liquid_Y));
    }



}